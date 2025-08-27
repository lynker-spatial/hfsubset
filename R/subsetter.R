st_exists <- function(gpkg, layer){
  layers = sf::st_layers(gpkg)$name
  layer %in% layers
}

#' Subset a NextGen GeoPackage upstream of an origin feature
#'
#' Given a NextGen GeoPackage and an origin identifier (by `flowpath_id`,
#' by an external `comid`, or by an `hl_reference` tag), build an upstream
#' subgraph return/write filtered layers.
#' @param gpkg      Path to a NextGen GeoPackage.
#' @param id        Origin `flowpath_id` (character).
#' @param comid     Origin NHDPlusV2 COMID.
#' @param hl_reference Origin `hl_reference` tag (e.g. `nwis-09112500`).
#' @param outfile   Optional path to write the subset to a new GeoPackage.
#' @param lyrs      Character vector of layer names to extract. Defaults to
#'   `c("flowpaths","divides","nexus","network","flowpath-attributes","divide-attributes")`.
#'
#' @return A named list of tibbles/sf objects if `outfile` is missing;
#'   otherwise (invisibly) the list after writing to `outfile`.
#' @examples
#'
#' \dontrun{
#'   out <- nextgen_subset("hydrofabric.gpkg", hl_reference = "nwis-09112500")
#' }
#'
#' @importFrom igraph graph_from_data_frame subcomponent as_ids
#' @importFrom dplyr filter select distinct left_join mutate pull collect rename %>% bind_rows everything
#' @importFrom tidyr drop_na
#' @importFrom cli cli_abort cli_alert_info cli_alert_success
#' @importFrom rlang .data
#' @importFrom hfsubsetR as_ogr st_as_sf
#' @importFrom sf write_sf st_layers

hfsubset <- function(gpkg,
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
                              "divide-attributes")) {
  divide_id <-
    flowpath_id <-
    flowpath_toid <-
    hf_id <-
    toid <-
    vpuid <- NULL

  # ---- helpers -------------------------------------------------------------

  # Compose a clear stop if origin not found
  .abort_origin <- function() {
    cli::cli_abort(
      c("!" = "Couldn't locate an origin row in the {.strong network} layer.",
        "i" = "Provide exactly one of: {.code id}, {.code comid}, or {.code hl_reference}."
      )
    )
  }

  # Graph upstream finder (returns character vector of node ids)
  .get_upstream <- function(graph, node_id) {
    v <- as.character(node_id)
    if (!v %in% igraph::V(graph)$name) {
      cli::cli_abort(c("!" = "Origin node {.code {v}} not present in the VPU graph."))
    }
    igraph::as_ids(igraph::subcomponent(graph, v, mode = "in"))
  }

  # Ensure only one origin selector is provided
  supplied <- c(!missing(id), !missing(comid), !missing(hl_reference))

  if (sum(supplied) != 1) {
    cli::cli_abort(c(
      "!" = "Provide exactly one of {.code id}, {.code comid}, or {.code hl_reference}."
    ))
  }

  # ---- find origin row -----------------------------------------------------
  if(!missing(id)){
    tmp <-  as_ogr(gpkg, "network") |>
      filter(flowpath_id == id) |>
      collect()
  } else if (!missing(comid)) {
    tmp <- filter(ngsubset::ref_net, flowpath_id == !!comid)
  } else if (!missing(hl_reference)) {
    tmp <- filter(ngsubset::ref_net, hl_reference == !!hl_reference)
  } else {
    cli::cli_alert_danger("Origin must be provided.")
  }

  if (nrow(tmp) != 1) .abort_origin()

  origin_fp  <- tmp$flowpath_id[[1]]
  origin_vpu <- tmp$vpuid[[1]]

  cli::cli_alert_info("Origin flowpath: {origin_fp} (VPU: {origin_vpu})")

  # ---- build VPU subgraph --------------------------------------------------
  ids <- filter(ngsubset::ref_net, vpuid == tmp$vpuid) |>
    select(flowpath_id, flowpath_toid) |>
    distinct() |>
    tidyr::drop_na(flowpath_toid) |>
    graph_from_data_frame(directed = TRUE) |>
    .get_upstream(node_id = tmp$flowpath_id)

  net <- as_ogr(gpkg, "network") |>
    filter(hf_id %in% ids) |>
    collect()

  flowpath_flag <- ifelse('flowpath_id' %in% names(net), TRUE, FALSE)

  # ---- filter requested layers --------------------------------------------
  out <- list()

  if("network" %in% lyrs && st_exists(gpkg, "network")){
    out[['network']] <- as_ogr(gpkg, "network") |>
      filter(hf_id %in% ids) |>
      collect()
  }

  if("flowpaths" %in% lyrs && st_exists(gpkg, "flowpaths")){
    if(flowpath_flag){
      out[['flowpaths']] <- as_ogr(gpkg, "flowpaths") |>
        filter(flowpath_id %in% net$flowpath_id) |>
        st_as_sf()
    } else {
      out[['flowpaths']] <- as_ogr(gpkg, "flowpaths") |>
        filter(id %in% net$id) |>
        st_as_sf()
    }
  }

  if("divides" %in% lyrs && st_exists(gpkg, "divides")){
    out[['divides']] <- as_ogr(gpkg, "divides") |>
      filter(divide_id %in% net$divide_id) |>
      st_as_sf()
  }

  if("nexus" %in% lyrs && st_exists(gpkg, "nexus")){
    if(flowpath_flag){
      out[['nexus']] <- as_ogr(gpkg, "nexus") |>
        filter(flowpath_id %in% net$flowpath_toid) |>
        st_as_sf()
    } else {
      out[['nexus']] <- as_ogr(gpkg, "nexus") |>
        filter(id %in% net$toid) |>
        st_as_sf()
    }
  }

  if("divide-attributes" %in% lyrs && st_exists(gpkg, "divide-attributes")){
    out[['divide-attributes']] <- as_ogr(gpkg, "divide-attributes") |>
      filter(divide_id %in% net$divide_id) |>
      st_as_sf()
  }

  if("flowpath-attributes" %in% lyrs && st_exists(gpkg, "flowpath-attributes")){
    if(flowpath_flag){
      out[['flowpath-attributes']] <-  as_ogr(gpkg, "flowpath-attributes") |>
        filter(flowpath_id %in% net$flowpath_id) |>
        st_as_sf()
    } else {
      out[['flowpath-attributes']] <-  as_ogr(gpkg, "flowpath-attributes") |>
        filter(id %in% net$id) |>
        st_as_sf()
    }
  }

  if("pois" %in% lyrs && st_exists(gpkg, "pois")){
    if(flowpath_flag){
      out[['pois']] <-  as_ogr(gpkg, "pois") |>
        filter(flowpath_id %in% net$flowpath_id) |>
        st_as_sf()
    } else {
      out[['pois']] <-  as_ogr(gpkg, "pois") |>
        filter(id %in% net$id) |>
        st_as_sf()
    }
  }

  if("hydrolocations" %in% lyrs && st_exists(gpkg, "hydrolocations")){
    if(flowpath_flag){
      out[['hydrolocations']] <-  as_ogr(gpkg, "hydrolocations") |>
        filter(flowpath_id %in% net$flowpath_id) |>
        st_as_sf()
    } else {
      out[['hydrolocations']] <-  as_ogr(gpkg, "hydrolocations") |>
        filter(id %in% net$id) |>
        st_as_sf()
    }
  }

  if(!missing(outfile)){
    for(i in seq_along(out)){
      write_sf(out[[i]],
               dsn = outfile,
               layer = names(out)[i])
    }
  } else {
    return(out)
  }
}

