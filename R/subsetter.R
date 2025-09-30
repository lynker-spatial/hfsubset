.infer_store <- function(src) {
  # 1) Extension signals
  if (grepl("\\.gpkg$", src, ignore.case = TRUE)) return("gpkg")
  if (grepl("\\.parquet$", src, ignore.case = TRUE)) return("geoparquet")

  # 2) Local directory with parquet children?
  if (dir.exists(src)) {
    pq <- try(length(list.files(src, pattern = "\\.parquet$", recursive = TRUE)) > 0, silent = TRUE)
    if (!inherits(pq, "try-error") && isTRUE(pq)) return("geoparquet")
  }

  # 3) S3 path heuristic: assume geoparquet root unless .gpkg path
  if (grepl("^s3://", src)) return("geoparquet")

  cli::cli_abort(c("!" = "Could not infer store type from: {src}",
                   "i" = "Pass store='gpkg' or store='geoparquet'."))
}

st_exists <- function(src, layer, store = c("gpkg","geoparquet")) {
  store <- match.arg(store)
  if (store == "gpkg") {
    layers <- try(sf::st_layers(src)$name, silent = TRUE)
    if (inherits(layers, "try-error")) return(FALSE)
    return(layer %in% layers)
  } else {
    # geoparquet: try opening dataset metadata under <src>/<layer>
    p <- file.path(src, layer)
    ok <- try({
      ds <- arrow::open_dataset(p)
      invisible(ds$schema$names) # touch metadata
      TRUE
    }, silent = TRUE)
    isTRUE(ok)
  }
}

# Back-compat with your original name/signature (gpkg only)
st_exists_legacy <- function(gpkg, layer) st_exists(gpkg, layer, "gpkg")

# Return a dplyr tbl for the requested layer
.as_tbl <- function(src, layer, store = c("gpkg","geoparquet")) {
  store <- match.arg(store)
  if (store == "gpkg") {
    hfutils::as_ogr(src, layer)  # your existing lazy OGR reader
  } else {
   arrow::open_dataset(file.path(src, layer))
  }
}

# Convert to sf if there is a recognizable geometry column (WKB preferred, fall back to WKT)
.to_sf_if_geom <- function(df, crs = NULL) {
  nm <- names(df)
  if (!any(nm %in% c("geometry","wkb_geometry","geom","wkt"))) return(df)
  if ("geometry" %in% nm) {
    out <- try(sf::st_as_sf(df, wkb = "geometry", crs = crs), silent = TRUE)
    if (!inherits(out, "try-error")) return(out)
    out <- try(sf::st_as_sf(df, wkt = "geometry", crs = crs), silent = TRUE)
    if (!inherits(out, "try-error")) return(out)
  }
  if ("wkb_geometry" %in% nm) return(sf::st_as_sf(df, wkb = "wkb_geometry", crs = crs))
  if ("geom" %in% nm)         return(sf::st_as_sf(df, wkb = "geom", crs = crs))
  if ("wkt" %in% nm)          return(sf::st_as_sf(df, wkt = "wkt", crs = crs))
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
#'
#' @return A named list of tibbles/sf if `outfile` is missing; invisibly the list after writing otherwise.
#' @importFrom igraph graph_from_data_frame subcomponent as_ids
#' @importFrom dplyr filter select distinct left_join mutate pull collect rename %>% bind_rows everything
#' @importFrom tidyr drop_na
#' @importFrom cli cli_abort cli_alert_info cli_alert_success
#' @importFrom rlang .data
#' @importFrom hfutils as_ogr st_as_sf write_hydrofabric
#' @importFrom sf write_sf st_layers
#' @export
hfsubset <- function(src,
                     id,
                     comid,
                     hl_reference,
                     outfile,
                     lyrs = c("flowpaths",
                              "divides",
                              "nexus",
                              "network",
                              "hydrolocations",
                              "pois",
                              "flowpath-attributes",
                              "divide-attributes",
                              "events"),
                     crs = NULL) {

  # Infer store if not provided
  store <- .infer_store(src)
  cli::cli_alert_info("Inferred store type: {store}")

  divide_id <-
    flowpath_id <-
    flowpath_toid <-
    hf_id <-
    toid <-
    vpuid <- NULL

  # ---- helpers -------------------------------------------------------------
  .abort_origin <- function() {
    cli::cli_abort(
      c("!" = "Couldn't locate an origin row in the {.strong network} layer.",
        "i" = "Provide exactly one of: {.code id}, {.code comid}, or {.code hl_reference}."
      )
    )
  }

  .get_upstream <- function(graph, node_id) {
    v <- as.character(node_id)
    if (!v %in% igraph::V(graph)$name) {
      cli::cli_abort(c("!" = "Origin node {.code {v}} not present in the VPU graph."))
    }
    igraph::as_ids(igraph::subcomponent(graph, v, mode = "in"))
  }

  supplied <- c(!missing(id), !missing(comid), !missing(hl_reference))

  if (sum(supplied) != 1) {
    cli::cli_abort(c("!" = "Provide exactly one of {.code id}, {.code comid}, or {.code hl_reference}."))
  }

  # ---- find origin row (network layer) -------------------------------------
  if (!st_exists(src, "network", store)) {
    cli::cli_abort(c("!" = "Couldn't find a {.strong network} layer in the source."))
  }

  if (!missing(id)) {
    tmp <- .as_tbl(src, "network", store) |>
      dplyr::filter(flowpath_id == id) |>
      dplyr::collect()
  } else if (!missing(comid)) {
    tmp <- dplyr::filter(hfsubset::ref_net, flowpath_id == !!comid)
  } else if (!missing(hl_reference)) {
    tmp <- dplyr::filter(hfsubset::ref_net, hl_reference == !!hl_reference)
  } else {
    cli::cli_alert_danger("Origin must be provided.")
  }

  if (nrow(tmp) != 1) .abort_origin()

  origin_fp  <- tmp$flowpath_id[[1]]
  origin_vpu <- tmp$vpuid[[1]]
  cli::cli_alert_info("Origin flowpath: {origin_fp} (VPU: {origin_vpu})")

  # ---- build VPU subgraph --------------------------------------------------
  ids <- dplyr::filter(hfsubset::ref_net, vpuid == tmp$vpuid) |>
    dplyr::select(flowpath_id, flowpath_toid) |>
    dplyr::distinct() |>
    tidyr::drop_na(flowpath_toid) |>
    igraph::graph_from_data_frame(directed = TRUE) |>
    .get_upstream(node_id = tmp$flowpath_id)

  net <- .as_tbl(src, "network", store) |>
    dplyr::filter(hf_id %in% ids) |>
    dplyr::collect()

  # Decide keys once (flowpath_id schema vs legacy id schema)
  flowpath_flag <- "flowpath_id" %in% names(net)
  fp_key  <- ifelse(flowpath_flag, "flowpath_id", "id")
  nx_key  <- ifelse(flowpath_flag,"flowpath_id", "id")

  if(flowpath_flag){
    fp_vals <- net$flowpath_id
  } else {
    fp_vals <- net$id
  }

  if(flowpath_flag){
     nx_vals <- net$flowpath_toid
  } else {
      nx_vals <-  net$toid
  }

  # ---- filter requested layers --------------------------------------------
  out <- list()
  has <- function(ly) st_exists(src, ly, store)

  if ("network" %in% lyrs && has("network")) {
    out[["network"]] <- .as_tbl(src, "network", store) |>
      dplyr::filter(hf_id %in% ids) |>
      collect()
  }

  if ("flowpaths" %in% lyrs && has("flowpaths")) {
    out[["flowpaths"]] <- .as_tbl(src, "flowpaths", store) |>
      .filter_by(fp_key, fp_vals) |>
      collect() |>
      st_as_sf()
  }

  if ("divides" %in% lyrs && has("divides")) {
    out[["divides"]] <- .as_tbl(src, "divides", store) |>
      dplyr::filter(divide_id %in% !!net$divide_id) |>
      collect() |>
      st_as_sf()
  }

  if ("nexus" %in% lyrs && has("nexus")) {
    out[["nexus"]] <- .as_tbl(src, "nexus", store) |>
      .filter_by(nx_key, nx_vals) |>
      collect() |>
      st_as_sf()
  }

  if ("divide-attributes" %in% lyrs && has("divide-attributes")) {
    out[["divide-attributes"]] <- .as_tbl(src, "divide-attributes", store) |>
      dplyr::filter(divide_id %in% !!net$divide_id) |>
      collect()
  }

  if ("flowpath-attributes" %in% lyrs && has("flowpath-attributes")) {
    out[["flowpath-attributes"]] <- .as_tbl(src, "flowpath-attributes", store) |>
      .filter_by(fp_key, fp_vals) |>
      collect()
  }

  if ("pois" %in% lyrs && has("pois")) {
    out[["pois"]] <- .as_tbl(src, "pois", store) |>
      .filter_by(fp_key, fp_vals) |>
      collect() |>
      st_as_sf()
  }

  if ("hydrolocations" %in% lyrs && has("hydrolocations")) {
    out[["hydrolocations"]] <- .as_tbl(src, "hydrolocations", store) |>
      .filter_by(fp_key, fp_vals) |>
      collect() |>
      st_as_sf()
  }

  if ("events" %in% lyrs && has("events")) {
    out[["events"]] <- .as_tbl(src, "events", store) |>
      .filter_by(fp_key, fp_vals) |>
      collect() |>
      st_as_sf()
  }

  if (!missing(outfile)) {
    # your writer (keeps DM enforcement off for subsets)
    write_hydrofabric(out, outfile, enforce_dm = FALSE)
    invisible(out)
  } else {
    out
  }
}
