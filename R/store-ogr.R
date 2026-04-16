#' Create a lazy OGR store
#' @param src Source URI
#' @keywords internal
ogr_store <- function(src) {
  store <- new_store(src = src)
  class(store) <- c("ogr_store", class(store))
  store
}


#' @keywords internal
store_has_layer.ogr_store <- function(store, layer, ...) {
  layers <- try(sf::st_layers(store$src, ...)$name, silent = TRUE)
  if (inherits(layers, "try-error")) {
    return(FALSE)
  }
  
  layer %in% layers
}


#' @keywords internal
store_get_layer.ogr_store <- function(store, layer, ...) {
  hfutils::as_ogr(store$src, layer, ...)
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