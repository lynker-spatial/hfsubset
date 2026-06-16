#' Resolve the upstream id table for an origin flowpath
#'
#' Return the subset of the network's id table (one row per upstream
#' flowline/flowpath) that drains to `origin_fp_id`. The result carries
#' whichever of `flowpath_id`, `flowpath_toid`, `poi_id`, `divide_id`,
#' `flowline_id` the schema provides -- enough to filter every downstream layer.
#'
#' Dispatch picks the cheapest correct traversal for the backend:
#'   * `ogr_store` pushes the walk into SQLite with a recursive CTE, touching
#'     only upstream rows (no whole-VPU materialization, no graph build).
#'   * the default collects the VPU's edges once and walks an in-memory igraph,
#'     caching both per (source, VPU) for batch reuse.
#'
#' @param store        A store object.
#' @param origin_fp_id Origin `flowpath_id`.
#' @param vpu          Origin VPU id (character) or `NA`.
#' @param has_vpuid    Logical; whether the network carries a `vpuid` column.
#' @param cache        Logical; reuse the per-(source, VPU) graph (default path).
#' @returns A data.frame of upstream id columns.
#' @keywords internal
store_upstream_ids <- function(store, origin_fp_id, vpu, has_vpuid, cache = TRUE, ...) {
  UseMethod("store_upstream_ids")
}


# Upstream subcomponent of a directed graph (edges point downstream, so walk
# "in"). Shared by the default method.
.get_upstream <- function(graph, node_id) {
  v <- as.character(node_id)
  if (!v %in% igraph::V(graph)$name) {
    cli::cli_abort(c("!" = "Origin node {.code {v}} not present in the VPU graph."))
  }
  igraph::as_ids(igraph::subcomponent(graph, v, mode = "in"))
}


#' @keywords internal
#
# GPKG is SQLite: a recursive CTE walks `flowline_toid -> flowline_id` (or
# `flowpath_toid -> flowpath_id` for the reference fabric) upstream from the
# origin, then selects the matching id columns. This visits only the upstream
# subgraph, so it scales with the *result* size rather than the VPU size, and
# needs no in-R graph at all. The recursion joins on the *_toid column, so we
# ensure an index on it first (idempotent; a no-op on read-only sources, where
# the CTE still runs, just unindexed).
store_upstream_ids.ogr_store <- function(store, origin_fp_id, vpu, has_vpuid, cache = TRUE, ...) {
  require_pkg("RSQLite")
  cols <- store_layer_cols(store, "network")
  has_flowline <- all(c("flowline_id", "flowline_toid") %in% cols)

  con <- DBI::dbConnect(RSQLite::SQLite(), store$src)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  sel  <- intersect(
    c("flowpath_id", "flowpath_toid", "poi_id", "divide_id", "flowline_id"),
    cols
  )
  sel_sql     <- paste(sprintf('"%s"', sel), collapse = ", ")
  seed_filter <- if (has_vpuid && !is.na(vpu)) "AND vpuid = :vpu" else ""

  if (has_flowline) {
    try(DBI::dbExecute(con,
      'CREATE INDEX IF NOT EXISTS "idx_network_flowline_toid" ON "network"("flowline_toid")'),
      silent = TRUE)
    sql <- sprintf('
      WITH RECURSIVE up(fid) AS (
        SELECT "flowline_id" FROM "network" WHERE "flowpath_id" = :origin %s
        UNION
        SELECT n."flowline_id" FROM "network" n
          JOIN up ON n."flowline_toid" = up.fid
      )
      SELECT DISTINCT %s FROM "network" WHERE "flowline_id" IN (SELECT fid FROM up)',
      seed_filter, sel_sql)
  } else {
    try(DBI::dbExecute(con,
      'CREATE INDEX IF NOT EXISTS "idx_network_flowpath_toid" ON "network"("flowpath_toid")'),
      silent = TRUE)
    sql <- sprintf('
      WITH RECURSIVE up(fid) AS (
        SELECT "flowpath_id" FROM "network" WHERE "flowpath_id" = :origin %s
        UNION
        SELECT n."flowpath_id" FROM "network" n
          JOIN up ON n."flowpath_toid" = up.fid
      )
      SELECT DISTINCT %s FROM "network" WHERE "flowpath_id" IN (SELECT fid FROM up)',
      seed_filter, sel_sql)
  }

  params <- list(origin = origin_fp_id)
  if (has_vpuid && !is.na(vpu)) params$vpu <- as.character(vpu)
  DBI::dbGetQuery(con, sql, params = params)
}


#' @keywords internal
#
# Arrow / Lynker-Spatial and any other backend: collect the VPU's edge table
# once and traverse an igraph in memory. Both the collected table and the built
# graph are identical for every origin in a VPU, so cache them per (source, VPU)
# -- the win for batch subsetting one fabric (see hfsubset_clear_cache()).
store_upstream_ids.default <- function(store, origin_fp_id, vpu, has_vpuid, cache = TRUE, ...) {
  key   <- .graph_cache_key(store, vpu)
  entry <- if (isTRUE(cache)) .graph_cache[[key]] else NULL

  if (is.null(entry)) {
    q <- store_get_layer(store, "network")
    if (has_vpuid && !is.na(vpu)) {
      q <- dplyr::filter(q, vpuid == !!vpu)
    }
    vpu_ids <- q |>
      dplyr::select(dplyr::any_of(c(
        "flowpath_id", "flowpath_toid", "flowline_id", "flowline_toid",
        "poi_id", "divide_id", "mainstem_id", "is_mainstem"
      ))) |>
      dplyr::collect()

    has_flowline <- all(c("flowline_id", "flowline_toid") %in% names(vpu_ids))

    edges <- if (has_flowline) {
      dplyr::filter(vpu_ids, !is.na(flowline_toid), !is.na(flowpath_id)) |>
        dplyr::select(flowline_id, flowline_toid) |>
        dplyr::distinct()
    } else {
      dplyr::filter(vpu_ids, !is.na(flowpath_toid), !is.na(flowpath_id)) |>
        dplyr::select(flowpath_id, flowpath_toid) |>
        dplyr::distinct()
    }
    graph <- igraph::graph_from_data_frame(edges, directed = TRUE)

    entry <- list(vpu_ids = vpu_ids, graph = graph, has_flowline = has_flowline)
    if (isTRUE(cache)) .graph_cache[[key]] <- entry
  }

  vpu_ids      <- entry$vpu_ids
  graph        <- entry$graph
  has_flowline <- entry$has_flowline

  if (has_flowline) {
    # Outlet flowline of the origin flowpath: the one whose toid leaves the fp.
    origin_fp_rows <- unique(vpu_ids[vpu_ids$flowpath_id == origin_fp_id,
                                     c("flowline_id", "flowline_toid")])
    if (nrow(origin_fp_rows) == 0) {
      cli::cli_abort(c("!" = "Origin flowpath {.code {origin_fp_id}} has no flowlines in the network."))
    }
    fp_fl_ids   <- origin_fp_rows$flowline_id
    outlet_mask <- !(origin_fp_rows$flowline_toid %in% fp_fl_ids)
    origin_fl   <- if (any(outlet_mask, na.rm = TRUE)) {
      origin_fp_rows$flowline_id[which(outlet_mask)[1]]
    } else {
      fp_fl_ids[[length(fp_fl_ids)]]
    }
    # Compare as character: igraph vertex names are character, so coercing the
    # id column to character is type-safe regardless of its storage type.
    fl_ids <- .get_upstream(graph, node_id = origin_fl)
    dplyr::filter(vpu_ids, as.character(flowline_id) %in% fl_ids) |>
      dplyr::distinct()
  } else {
    fp_ids <- .get_upstream(graph, node_id = origin_fp_id)
    dplyr::filter(vpu_ids, as.character(flowpath_id) %in% fp_ids) |>
      dplyr::distinct()
  }
}
