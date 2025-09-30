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