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
#' @param gage      Origin USGS gage id (e.g. `"09112500"`). Convenience for
#'   `hl_reference = paste0("nwis-", gage)`; an 8-digit id is expected.
#' @param xy        Origin point as `c(x, y)` (defaults to lon/lat, EPSG:4326).
#'   Resolved to the containing divide, then to its flowpath. Uses the GPKG
#'   R-tree on OGR stores; reads the full divides layer otherwise.
#' @param outfile   Optional path to write the subset to a new GeoPackage.
#' @param lyrs      Character vector of layer names to extract. Defaults to
#'   c("flowpaths","divides","nexus","network","hydrolocations","pois",
#'     "flowpath-attributes","divide-attributes").
#' @param crs       Optional EPSG/int for sf outputs when reading GeoParquet (recommended if CRS missing).
#' @param check     Logical. If `TRUE`, run `hfutils::hf_check_invariants("ngen", ...)` on the
#'   returned subset (warnings only, does not stop). Default `FALSE`.
#' @param cache     Logical. Reuse an in-memory per-VPU network graph across
#'   calls (big win for batch subsetting). Default `TRUE`. See
#'   [hfsubset_clear_cache()].
#' @param optimize  Logical. When writing `outfile`, index and optimize the
#'   GeoPackage via [optimize_gpkg()]. Default `TRUE`.
#'
#' @return A named list of tibbles/sf if `outfile` is missing; invisibly the list after writing otherwise.
#' @importFrom igraph V graph_from_data_frame subcomponent as_ids
#' @importFrom dplyr filter select distinct left_join mutate pull collect rename bind_rows everything if_any any_of
#' @importFrom tidyr drop_na
#' @importFrom cli cli_abort cli_alert_info cli_alert_success cli_alert_warning
#' @importFrom rlang %||%
#' @importFrom hfutils as_ogr st_as_sf write_hydrofabric hf_check_invariants
#' @importFrom sf write_sf st_layers
#' @export
hfsubset <- function(
  src,
  id,
  comid,
  hl_reference,
  gage,
  xy,
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
  check = FALSE,
  cache = TRUE,
  optimize = TRUE
) {
  # Infer store if not provided
  store <- .infer_store(src)
  cli::cli_alert_info("Inferred store type: {class(store)[1]}")

  supplied <- c(!missing(id), !missing(comid), !missing(hl_reference),
                !missing(gage), !missing(xy))

  if (sum(supplied) != 1) {
    cli::cli_abort(c(
      "!" = "Provide exactly one of {.code id}, {.code comid}, {.code hl_reference}, {.code gage}, or {.code xy}."
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
  } else if (!missing(gage)) {
    gg <- gsub("\\s", "", as.character(gage))
    if (!grepl("^[0-9]{8}$", gg)) {
      cli::cli_alert_warning("Gage {.val {gg}} is not an 8-digit USGS id; resolving as {.val nwis-{gg}}.")
    }
    origin_row <- store_filter_hl_reference(store, "network", paste0("nwis-", gg))
  } else if (!missing(xy)) {
    div <- store_locate_point(store, xy, crs_pt = if (is.null(crs)) 4326L else crs)
    if (!"divide_id" %in% names(div) || nrow(div) == 0) {
      cli::cli_abort(c("!" = "No divide contains point ({.val {xy[1]}}, {.val {xy[2]}})."))
    }
    origin_div <- div$divide_id[[1]]
    cli::cli_alert_info("Point resolved to divide {origin_div}")
    origin_row <- net_tbl |>
      dplyr::filter(divide_id == !!origin_div)
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

  # ---- upstream traversal --------------------------------------------------
  # Backend-pushed where possible: ogr_store walks the network in-DB with a
  # recursive CTE (only upstream rows); other backends collect the VPU edges
  # once and traverse a cached igraph. Both honor the flowline vs flowpath graph
  # distinction internally. We rely on the flowline_id -> flowline_toid (or
  # reference-fabric flowpath) edges, NOT fp->nex->fp topology, because the nexus
  # table is not exhaustive and would fragment the graph.
  vpu_sub <- store_upstream_ids(store, origin_fp_id, origin_vpu, has_vpuid,
                                cache = cache)

  # id sets for layer filtering — guard columns that a given schema may lack.
  .vals <- function(nm) if (nm %in% names(vpu_sub)) unique(na.omit(vpu_sub[[nm]])) else integer(0)
  fp_vals  <- .vals("flowpath_id")
  nex_vals <- .vals("flowpath_toid")
  poi_vals <- .vals("poi_id")
  div_vals <- .vals("divide_id")
  fl_vals  <- .vals("flowline_id")

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
    } else if ("flowline_id" %in% store_layer_cols(store, layer)) {
      out[[layer]] <- store_filter_layer(store, layer, "flowline_id", fl_vals)
    } else {
      # e.g. the reference `network` layer, which has no flowline_id column.
      out[[layer]] <- store_filter_layer(store, layer, "flowpath_id", fp_vals)
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

  if (!missing(outfile) && !is.null(outfile)) {
    written <- hfutils::write_hydrofabric(out, outfile, enforce_dm = FALSE)
    if (isTRUE(optimize)) {
      try(optimize_gpkg(written, verbose = verbose), silent = !verbose)
    }
    invisible(out)
  } else {
    out
  }
}
