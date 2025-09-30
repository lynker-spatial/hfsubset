#' @keywords internal
arrow_store <- function(src) {
  require_pkg("arrow")
  store <- new_store(src = src)
  class(store) <- c("arrow_store", class(store))
  store
}


#' @keywords internal
store_has_layer.arrow_store <- function(store, layer, ...) {
  require_pkg("arrow")
  p <- file.path(store$src, layer)
  ok <- try({
    ds <- arrow::open_dataset(p, ...)
    invisible(ds$schema$names)
    TRUE
  }, silent = TRUE)
  isTRUE(ok)
}


#' @keywords internal
store_get_layer.arrow_store <- function(store, layer, ...) {
  require_pkg("arrow")
  arrow::open_dataset(file.path(src, layer), ...)
}
