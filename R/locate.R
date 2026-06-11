#' Locate the divide containing a point
#'
#' Resolve an `xy` coordinate to the divide (catchment) polygon that contains
#' it. Used by [hfsubset()] to support point-based origins ("subset above where
#' I clicked"). Mirrors the lat/lon lookup in CIROH's NGIAB_data_preprocess:
#' transform the point to the layer CRS, hit the spatial index for candidates,
#' then test exact containment.
#'
#' @param store  A store object.
#' @param xy     Numeric length-2 vector, `c(x, y)` (e.g. `c(lon, lat)`).
#' @param crs_pt CRS of `xy`. Default EPSG:4326 (WGS84 lon/lat).
#' @param layer  Polygon layer to test containment against. Default "divides".
#' @returns An `sf` of the matching divide row(s); zero rows if the point falls
#'   outside the fabric.
#' @keywords internal
store_locate_point <- function(store, xy, crs_pt = 4326, layer = "divides", ...) {
  stopifnot(length(xy) == 2, is.numeric(xy) || is.integer(xy))
  UseMethod("store_locate_point")
}

#' @keywords internal
#
# OGR/GPKG: use GDAL's `wkt_filter`, which routes through the GPKG R-tree, so we
# only deserialize the handful of polygons whose bounding box covers the point,
# then confirm with an exact st_intersects. This is the cheap path NGIAB gets
# from `rtree_divides_geom`.
store_locate_point.ogr_store <- function(store, xy, crs_pt = 4326, layer = "divides", ...) {
  lyrs <- sf::st_layers(store$src)
  if (!layer %in% lyrs$name) {
    cli::cli_abort(c("!" = "No {.strong {layer}} layer in the source for point lookup."))
  }
  tgt_crs <- lyrs$crs[[which(lyrs$name == layer)[1]]]

  pt <- sf::st_sfc(sf::st_point(as.numeric(xy)), crs = crs_pt)
  if (!is.na(sf::st_crs(tgt_crs))) {
    pt <- sf::st_transform(pt, tgt_crs)
  }

  cand <- sf::st_read(
    store$src,
    layer = layer,
    wkt_filter = sf::st_as_text(pt),
    quiet = TRUE
  )
  if (nrow(cand) == 0) {
    return(cand)
  }
  inside <- lengths(sf::st_intersects(cand, pt)) > 0
  cand[inside, , drop = FALSE]
}

#' @keywords internal
#
# Arrow / Lynker-Spatial: no spatial index available, so collect the divides
# layer and test containment in-memory. For CONUS-scale stores this materializes
# a lot of geometry; we warn so the cost is not a surprise.
store_locate_point.default <- function(store, xy, crs_pt = 4326, layer = "divides", ...) {
  if (!store_has_layer(store, layer)) {
    cli::cli_abort(c("!" = "No {.strong {layer}} layer in the source for point lookup."))
  }
  cli::cli_alert_info(
    "Point lookup on a non-OGR store reads the full {.strong {layer}} layer (no spatial index)."
  )
  div <- dplyr::collect(store_get_layer(store, layer))
  div <- .to_sf_if_geom(div, crs = 5070L)
  if (!inherits(div, "sf")) {
    cli::cli_abort(c("!" = "Could not build geometry from {.strong {layer}} for point lookup."))
  }
  pt <- sf::st_transform(
    sf::st_sfc(sf::st_point(as.numeric(xy)), crs = crs_pt),
    sf::st_crs(div)
  )
  inside <- lengths(sf::st_intersects(div, pt)) > 0
  div[inside, , drop = FALSE]
}
