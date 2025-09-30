#' Create a new store structure
#' @keywords internal
new_store <- function(...) {
  structure(list(...), class = "store")
}


#' Check if a store has a layer
#' @returns `logical(n)`
#' @keywords internal
store_has_layer <- function(store, layer, ...) {
  # Preconditions
  stopifnot(all(is.character(layer)))
  
  .pred <- UseMethod("store_has_layer")

  # Postconditions
  stopifnot(is.logical(.pred))
  stopifnot(length(.pred) == length(layer))

  .pred
}


#' Get a store layer
#' @returns Object inheriting from `tbl`
#' @keywords internal
store_get_layer <- function(store, layer, ...) {
  # Preconditions
  stopifnot(length(layer) == 1)
  stopifnot(is.character(layer))

  .tbl <- UseMethod("store_get_layer")

  # Postconditions
  stopifnot(inherits(.tbl, "tbl"))

  .tbl
}