#' Create a lazy OGR store
#'
#' Resolves the source's layer names and per-layer CRS once at construction so
#' repeated `store_has_layer()` / point-lookup calls within a single subset
#' don't each re-open the file with `sf::st_layers()`.
#' @param src Source URI
#' @keywords internal
ogr_store <- function(src) {
  li <- try(sf::st_layers(src), silent = TRUE)
  ok <- !inherits(li, "try-error")
  store <- new_store(
    src    = src,
    layers = if (ok) li$name else character(),
    crs    = if (ok) stats::setNames(li$crs, li$name) else NULL
  )
  class(store) <- c("ogr_store", class(store))
  store
}


#' @keywords internal
store_has_layer.ogr_store <- function(store, layer, ...) {
  layer %in% store$layers
}


#' @keywords internal
store_get_layer.ogr_store <- function(store, layer, ...) {
  hfutils::as_ogr(store$src, layer, ...)
}


#' @keywords internal
store_layer_cols.ogr_store <- function(store, layer, ...) {
  row <- sf::st_read(store$src,
                     query = sprintf('SELECT * FROM "%s" LIMIT 0', layer),
                     quiet = TRUE)
  names(row)
}


#' @keywords internal
# hl_reference in GPKG is often pipe-delimited (e.g. "nwis-X|huc12-Y").
# Use SQLite LIKE so we match partial values without dbplyr translation.
store_filter_hl_reference.ogr_store <- function(store, layer, hl_reference, ...) {
  safe_ref <- gsub("'", "''", hl_reference)
  sql <- sprintf(
    'SELECT * FROM "%s" WHERE "hl_reference" LIKE \'%%%s%%\'',
    layer, safe_ref
  )
  sf::st_read(store$src, query = sql, quiet = TRUE)
}


#' @keywords internal
#
# For GPKG (= SQLite) files, GDAL routes `ExecuteSQL` through the SQLite
# engine, so a hand-crafted IN clause works regardless of size.  This avoids
# dbplyr's translation layer, which produces SQL that GDAL's OGR SQL
# interpreter cannot parse when the IN list is large.
store_filter_layer.ogr_store <- function(store, layer, col, vals, ...) {
  if (length(vals) == 0) {
    return(sf::st_read(
      store$src,
      query = sprintf('SELECT * FROM "%s" WHERE 1=0', layer),
      quiet = TRUE
    ))
  }
  # Preserve numeric types so SQLite can use any index on the column
  vals_sql <- if (is.numeric(vals) || is.integer(vals)) {
    paste(vals, collapse = ", ")
  } else {
    paste(sprintf("'%s'", gsub("'", "''", as.character(vals))), collapse = ", ")
  }
  sql <- sprintf('SELECT * FROM "%s" WHERE "%s" IN (%s)', layer, col, vals_sql)
  sf::st_read(store$src, query = sql, quiet = TRUE)
}
