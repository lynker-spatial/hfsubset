.infer_store <- function(src) {
  # Lynker Spatial Store
  if (startsWith(src, "ls://")) {
    groups <- regmatches(src, regexec("ls://(\\d\\.\\d)/(.*)/(.*)", src))[[1]]
    return(
      lynker_spatial_store(
        version = groups[2],
        domain = groups[3],
        kind = groups[4]
      )
    )
  }

  # S3 File
  if (
    endsWith(src, ".parquet") || startsWith(src, "s3://") || dir.exists(src)
  ) {
    return(arrow_store(src))
  }

  # Local File
  if (endsWith(src, ".gpkg")) {
    return(ogr_store(src))
  }

  cli::cli_abort(c(
    "!" = "Could not infer store type from: {src}",
    "i" = "Pass store='gpkg' or store='geoparquet'."
  ))
}

st_exists <- function(src, layer, store = c("gpkg", "geoparquet")) {
  store <- match.arg(store)
  if (store == "gpkg") {
    layers <- try(sf::st_layers(src)$name, silent = TRUE)
    if (inherits(layers, "try-error")) {
      return(FALSE)
    }
    return(layer %in% layers)
  } else {
    # geoparquet: try opening dataset metadata under <src>/<layer>
    if (startsWith(src, "https://")) {
      p <- paste0(
        src,
        ifelse(!endsWith(src, "/"), "/", ""),
        layer
      )
    } else {
      p <- file.path(src, layer)
    }

    ok <- try(
      {
        ds <- arrow::open_dataset(p)
        invisible(ds$schema$names) # touch metadata
        TRUE
      },
      silent = TRUE
    )
    isTRUE(ok)
  }
}

# Back-compat with your original name/signature (gpkg only)
st_exists_legacy <- function(gpkg, layer) st_exists(gpkg, layer, "gpkg")

# Return a dplyr tbl for the requested layer
.as_tbl <- function(src, layer, store = c("gpkg", "geoparquet")) {
  store <- match.arg(store)
  if (store == "gpkg") {
    hfutils::as_ogr(src, layer) # your existing lazy OGR reader
  } else {
    arrow::open_dataset(file.path(src, layer))
  }
}

# Convert to sf if there is a recognizable geometry column (WKB preferred, fall back to WKT)
.to_sf_if_geom <- function(df, crs = NULL) {
  nm <- names(df)
  if (!any(nm %in% c("geometry", "wkb_geometry", "geom", "wkt"))) {
    return(df)
  }
  if ("geometry" %in% nm) {
    out <- try(sf::st_as_sf(df, wkb = "geometry", crs = crs), silent = TRUE)
    if (!inherits(out, "try-error")) {
      return(out)
    }
    out <- try(sf::st_as_sf(df, wkt = "geometry", crs = crs), silent = TRUE)
    if (!inherits(out, "try-error")) return(out)
  }
  if ("wkb_geometry" %in% nm) {
    return(sf::st_as_sf(df, wkb = "wkb_geometry", crs = crs))
  }
  if ("geom" %in% nm) {
    return(sf::st_as_sf(df, wkb = "geom", crs = crs))
  }
  if ("wkt" %in% nm) {
    return(sf::st_as_sf(df, wkt = "wkt", crs = crs))
  }
  df
}

# Avoid RHS {} in base pipes: string-safe column filter
.filter_by <- function(tbl, col, vals) {
  dplyr::filter(tbl, .data[[col]] %in% vals)
}

# ---- main ------------------------------------------------------------------

#' Subset a NextGen HydroFabric from either a GPKG or layered Hive-partitioned GeoParquets
#'
#' Given a HydroFabric store and an origin identifier (by `flowpath_id`,
#' by an external `comid`, or by an `hl_reference` tag), build an upstream
#' subgraph and return/write filtered layers.
#'
#' @param src       Path to a GeoPackage (.gpkg) OR the root directory of layered
#'                  hive-partitioned GeoParquet (e.g., <root>/<layer>/v1/vpu=01/part-*.parquet).
#' @param store     Optional. One of "gpkg" or "geoparquet". If missing, inferred.
#' @param id        Origin `flowpath_id` (character).
#' @param comid     Origin NHDPlusV2 COMID.
#' @param hl_reference Origin `hl_reference` tag (e.g. `nwis-09112500`).
#' @param outfile   Optional path to write the subset to a new GeoPackage.
#' @param lyrs      Character vector of layer names to extract. Defaults to
#'   c("flowpaths","divides","nexus","network","hydrolocations","pois",
#'     "flowpath-attributes","divide-attributes").
#' @param crs       Optional EPSG/int for sf outputs when reading GeoParquet (recommended if CRS missing).
#' @param check     Logical. If `TRUE`, run `hfutils::hf_check_invariants("ngen", ...)` on the
#'   returned subset (warnings only, does not stop). Default `FALSE`.
#'
#' @return A named list of tibbles/sf if `outfile` is missing; invisibly the list after writing otherwise.
#' @importFrom igraph V graph_from_data_frame subcomponent as_ids
#' @importFrom dplyr filter select distinct left_join mutate pull collect rename bind_rows everything if_any any_of
#' @importFrom tidyr drop_na
#' @importFrom cli cli_abort cli_alert_info cli_alert_success
#' @importFrom hfutils as_ogr st_as_sf write_hydrofabric hf_check_invariants
#' @importFrom sf write_sf st_layers
#' @export
hfsubset <- function(
  src,
  id,
  comid,
  hl_reference,
  outfile = NULL,
  lyrs = c(
    "flowpaths",
    "flowlines",
    "divides",
    "nexus",
    "network",
    "hydrolocations",
    "pois",
    "flowpath-attributes",
    "divide-attributes"
  ),
  crs = NULL,
  verbose = FALSE,
  check = FALSE
) {
  # Infer store if not provided
  store <- .infer_store(src)
  cli::cli_alert_info("Inferred store type: {class(store)[1]}")

  # ---- helpers -------------------------------------------------------------
  .get_upstream <- function(graph, node_id) {
    v <- as.character(node_id)
    if (!v %in% igraph::V(graph)$name) {
      cli::cli_abort(c(
        "!" = "Origin node {.code {v}} not present in the VPU graph."
      ))
    }
    igraph::as_ids(igraph::subcomponent(graph, v, mode = "in"))
  }

  supplied <- c(!missing(id), !missing(comid), !missing(hl_reference))

  if (sum(supplied) != 1) {
    cli::cli_abort(c(
      "!" = "Provide exactly one of {.code id}, {.code comid}, or {.code hl_reference}."
    ))
  }

  # ---- check store has network ---------------------------------------------
  if (!store_has_layer(store, "network")) {
    cli::cli_abort(c("!" = "Couldn't find a {.strong network} layer in the source."))
  }

  # ---- resolve origin: deferred filter → single origin flowline_id + vpuid --
  net_tbl  <- store_get_layer(store, "network")
  net_cols <- store_layer_cols(store, "network")
  has_vpuid      <- "vpuid"       %in% net_cols

  if (!missing(id)) {
    origin_row <- net_tbl |>
      dplyr::filter(flowpath_id == !!as.character(id))
  } else if (!missing(comid)) {
    # NHD COMID lookup: stored as `hf_id` (character) in the new schema after
    # finalize_data_model renames reference_id → hf_id. A single COMID maps to
    # multiple rows (one per flowline in its reconciled group, plus absorbed
    # tributaries).
    comid_col <- if ("hf_id" %in% net_cols) "hf_id" else "reference_id"
    origin_row <- net_tbl |>
      dplyr::filter(.data[[comid_col]] == !!as.character(comid))
  } else {
    origin_row <- store_filter_hl_reference(store, "network", hl_reference)
  }

  sel_cols <- c("flowpath_id", "flowpath_toid", "flowline_id", "flowline_toid",
                if (has_vpuid) "vpuid")

  origin_row <- origin_row |>
    dplyr::select(dplyr::any_of(sel_cols)) |>
    dplyr::distinct() |>
    dplyr::collect()

  if (nrow(origin_row) == 0) {
    cli::cli_abort(c("!" = "Could not locate origin in the {.strong network} layer."))
  }

  origin_fp_id <- origin_row$flowpath_id[[1]]
  origin_vpu   <- if (has_vpuid) as.character(origin_row$vpuid[[1]]) else NA_character_
  cli::cli_alert_info("Origin: {origin_fp_id} (VPU: {origin_vpu})")

  # ---- fetch VPU id table in one shot: all columns needed for graph + id sets
  # flowline_id/flowline_toid form a self-contained directed graph within the
  # network table. fp→nex→fp topology cannot be used here because the nexus
  # table is not exhaustive — many interior nexuses have no entry, fragmenting
  # the graph and producing incorrect (too few) results.
  vpu_ids_q <- net_tbl
  if (has_vpuid && !is.na(origin_vpu)) {
    vpu_ids_q <- dplyr::filter(vpu_ids_q, vpuid == !!origin_vpu)
  }
  vpu_ids <- vpu_ids_q |>
    dplyr::select(dplyr::any_of(c(
      "flowpath_id", "flowpath_toid", "flowline_id", "flowline_toid",
      "poi_id", "divide_id", "mainstem_id", "is_mainstem"
    ))) |>
    dplyr::collect()

  # Find the outlet flowline of the origin flowpath — the one whose toid
  # does not belong to the same flowpath (i.e. it exits the fp).
  origin_fp_rows <- unique(vpu_ids[vpu_ids$flowpath_id == origin_fp_id,
                                    c("flowline_id", "flowline_toid")])
  if (nrow(origin_fp_rows) == 0) {
    cli::cli_abort(c("!" = "Origin flowpath {.code {origin_fp_id}} has no flowlines in the network."))
  }
  fp_fl_ids <- origin_fp_rows$flowline_id
  # outlet: its toid is not one of the fp's own mainstem flowlines
  outlet_mask <- !(origin_fp_rows$flowline_toid %in% fp_fl_ids)
  origin_fl   <- if (any(outlet_mask, na.rm = TRUE)) {
    origin_fp_rows$flowline_id[which(outlet_mask)[1]]
  } else {
    fp_fl_ids[[length(fp_fl_ids)]]
  }

  fl_ids <- igraph::graph_from_data_frame(
    dplyr::filter(vpu_ids, !is.na(flowline_toid), !is.na(flowpath_id)) |>
      dplyr::select(flowline_id, flowline_toid) |>
      dplyr::distinct(),
    directed = TRUE
  ) |>
    .get_upstream(node_id = origin_fl)

  vpu_sub  <- dplyr::filter(vpu_ids, flowline_id %in% as.integer(fl_ids)) |>
    distinct()

  fp_vals  <- unique(na.omit(vpu_sub$flowpath_id))
  nex_vals <- unique(na.omit(vpu_sub$flowpath_toid))
  poi_vals <- unique(na.omit(vpu_sub$poi_id))
  div_vals <- unique(na.omit(vpu_sub$divide_id))
  fl_vals  <- unique(vpu_sub$flowline_id)

  cli::cli_alert_info("Upstream: {length(fp_vals)} flowpaths, {length(div_vals)} divides")

  # ---- filter requested layers --------------------------------------------
  out <- list()

  for (layer in lyrs) {
    if (!store_has_layer(store, layer)) {
      if (verbose) {
        warning("layer `", layer, "` is not available in the given store. Skipping")
      }
      next
    }

    # Filter cases — prefer the layer's native id column where possible.
    # - nexus: filter by `nexus_id` (nex- space)
    # - divides / divide-attributes: filter by `divide_id` (preferred)
    # - hydrolocations / events: filter by `poi_id`
    # - otherwise: filter by `flowpath_id` (default)
    if (layer == "nexus") {
      out[[layer]] <- store_filter_layer(store, layer, "nexus_id", nex_vals)
    } else if (layer %in% c("divides", "divide-attributes")) {
      # prefer divide_id when available; fall back to flowpath_id
      out[[layer]] <- tryCatch(
        store_filter_layer(store, layer, "divide_id", div_vals),
        error = function(e) store_filter_layer(store, layer, "flowpath_id", fp_vals)
      )
    } else if (layer %in% c("hydrolocations", "events")) {
      out[[layer]] <- store_filter_layer(store, layer, "poi_id", poi_vals)
    } else if (layer %in% c("flowpaths", "flowlines", "flowpath-attributes")) {
      out[[layer]] <- store_filter_layer(store, layer, "flowpath_id", fp_vals)
    } else {
      out[[layer]] <- store_filter_layer(store, layer, "flowline_id", fl_vals)
    }

    if (layer %in% c("flowpaths", "flowlines", "divides", "nexus", "hydrolocations", "pois", "events")) {
      out[[layer]] <- .to_sf_if_geom(out[[layer]], crs = if (is.null(crs)) 5070L else crs)
    }
  }

  if (check) {
    hfutils::hf_check_invariants(
      "ngen",
      flowpaths = out[["flowpaths"]],
      divides   = out[["divides"]],
      nexus     = out[["nexus"]],
      strict    = FALSE
    )
  }

  if (!missing(outfile)) {
    hfutils::write_hydrofabric(out, outfile, enforce_dm = FALSE)
    invisible(out)
  } else {
    out
  }
}
