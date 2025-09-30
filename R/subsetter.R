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

# Works on lazy tables (Arrow, dbplyr, etc.)

filter_ids_lazy <- function(tbl, ids, cols = c("hf_id", "reference_id")) {
  nm <- colnames(tbl) # no collect; just schema
  present <- intersect(cols, nm)
  if (length(present) == 0) {
    stop("None of the id columns exist: ", paste(cols, collapse = ", "))
  }
  # build OR expression: (col1 %in% ids) | (col2 %in% ids) | ...
  preds <- lapply(present, function(col) rlang::expr(.data[[!!col]] %in% !!ids))
  cond <- Reduce(function(a, b) expr((!!a) | (!!b)), preds)
  dplyr::filter(tbl, !!cond)
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
#'
#' @return A named list of tibbles/sf if `outfile` is missing; invisibly the list after writing otherwise.
#' @importFrom igraph V graph_from_data_frame subcomponent as_ids
#' @importFrom dplyr filter select distinct left_join mutate pull collect rename bind_rows everything if_any any_of
#' @importFrom tidyr drop_na
#' @importFrom cli cli_abort cli_alert_info cli_alert_success
#' @importFrom hfutils as_ogr st_as_sf write_hydrofabric
#' @importFrom sf write_sf st_layers
#' @export
hfsubset <- function(
  src,
  id,
  comid,
  hl_reference,
  outfile,
  lyrs = c(
    "flowpaths",
    "divides",
    "nexus",
    "network",
    "hydrolocations",
    "pois",
    "flowpath-attributes",
    "divide-attributes",
    "events"
  ),
  crs = NULL
) {
  # Infer store if not provided
  store <- .infer_store(src)
  cli::cli_alert_info("Inferred store type: {class(store)[1]}")

  divide_id <-
    flowpath_id <-
      flowpath_toid <-
        hf_id <-
          toid <-
            vpuid <- NULL

  # ---- helpers -------------------------------------------------------------
  .abort_origin <- function() {
    cli::cli_abort(
      c(
        "!" = "Couldn't locate an origin row in the {.strong network} layer.",
        "i" = "Provide exactly one of: {.code id}, {.code comid}, or {.code hl_reference}."
      )
    )
  }

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

  # ---- find origin row (network layer) -------------------------------------
  if (!store_has_layer(store, "network")) {
    cli::cli_abort(c(
      "!" = "Couldn't find a {.strong network} layer in the source."
    ))
  }

  if (!missing(id)) {
    tmp <- store_get_layer(store, "network") |>
      dplyr::filter(flowpath_id == id) |>
      dplyr::collect()
  } else if (!missing(comid)) {
    tmp <- dplyr::filter(hfsubset::ref_net, flowpath_id == !!comid)
  } else if (!missing(hl_reference)) {
    tmp <- dplyr::filter(hfsubset::ref_net, hl_reference == !!hl_reference)
  } else {
    cli::cli_alert_danger("Origin must be provided.")
  }

  if (nrow(tmp) != 1) {
    .abort_origin()
  }

  origin_fp <- tmp$flowpath_id[[1]]
  origin_vpu <- tmp$vpuid[[1]]
  cli::cli_alert_info("Origin flowpath: {origin_fp} (VPU: {origin_vpu})")

  # ---- build VPU subgraph --------------------------------------------------
  ids <- dplyr::filter(hfsubset::ref_net, vpuid == tmp$vpuid) |>
    dplyr::select(flowpath_id, flowpath_toid) |>
    dplyr::distinct() |>
    tidyr::drop_na(flowpath_toid) |>
    igraph::graph_from_data_frame(directed = TRUE) |>
    .get_upstream(node_id = tmp$flowpath_id)

  net <- store_get_layer(store, "network") |>
    dplyr::filter(hf_id %in% ids) |>
    dplyr::collect()

  # Decide keys once (flowpath_id schema vs legacy id schema)
  flowpath_flag <- "flowpath_id" %in% names(net)
  fp_key <- ifelse(flowpath_flag, "flowpath_id", "id")
  nx_key <- ifelse(flowpath_flag, "nexus_id", "id")

  if (flowpath_flag) {
    fp_vals <- net$flowpath_id
  } else {
    fp_vals <- net$id
  }

  if (flowpath_flag) {
    nx_vals <- unique(net$flowpath_toid)
  } else {
    nx_vals <- unique(net$toid)
  }

  # ---- filter requested layers --------------------------------------------
  out <- list()
  has <- function(ly) store_has_layer(store, ly)

  for (layer in lyrs) {
    if (layer == "network") {
      out[[layer]] <- net
      next
    }

    if (!store_has_layer(store, layer)) {
      warning("layer `", layer, "` is not available in the given store. Skipping")
      next
    }

    .tbl <- store_get_layer(store, layer)

    # Filter cases
    if (layer %in% c("divides", "divide-attributes")) {
      .tbl <- dplyr::filter(.tbl, divide_id %in% !!net$divide_id)
    } else if (layer == "nexus") {
      .tbl <- .filter_by(.tbl, nx_key, nx_valus)
    } else {
      # filter by flowpath_id
      .tbl <- .filter_by(.tbl, fp_key, fp_vals)
    }

    out[[layer]] <- dplyr::collect(.tbl)
    if (layer %in% c("flowpaths", "divides", "nexus", "hydrolocations", "pois", "events")) {
      out[[layer]] <- tryCatch(
        sf:st_as_sf(out[[layer]]),
        error = function(condition) out[[layer]]
      )
    }
  }

  if (!missing(outfile)) {
    # your writer (keeps DM enforcement off for subsets)
    hfutils::write_hydrofabric(out, outfile, enforce_dm = FALSE)
    invisible(out)
  } else {
    out
  }
}
