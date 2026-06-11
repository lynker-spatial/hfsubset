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

  # Postconditions: must be something the dplyr verbs + collect() understand.
  # dbplyr tbls inherit "tbl"; arrow datasets/queries are ArrowObjects (NOT
  # "tbl") yet support the same lazy filter/collect contract, so accept both.
  stopifnot(inherits(.tbl, "tbl") || inherits(.tbl, "ArrowObject"))

  .tbl
}


#' Filter network layer by hl_reference (supports pipe-delimited values)
#' @returns A data.frame / tbl with matching rows
#' @keywords internal
store_filter_hl_reference <- function(store, layer, hl_reference, ...) {
  UseMethod("store_filter_hl_reference")
}

#' @keywords internal
store_filter_hl_reference.default <- function(store, layer, hl_reference, ...) {
  store_get_layer(store, layer) |>
    dplyr::filter(grepl(!!hl_reference, hl_reference, fixed = TRUE))
}


#' Return column names for a store layer
#' @returns character vector of column names
#' @keywords internal
store_layer_cols <- function(store, layer, ...) {
  UseMethod("store_layer_cols")
}

#' @keywords internal
store_layer_cols.default <- function(store, layer, ...) {
  tbl <- store_get_layer(store, layer)
  names(dplyr::collect(utils::head(tbl, 0L)))
}


#' Filter a store layer and return collected results
#'
#' Dispatches to a store-appropriate backend so that Arrow/DuckDB stores keep
#' full predicate pushdown while OGR stores bypass dbplyr translation and issue
#' hand-crafted SQL directly to the underlying SQLite engine (GPKG is SQLite).
#'
#' @param store  A store object.
#' @param layer  Layer name (character scalar).
#' @param col    Column name to filter on (character scalar).
#' @param vals   Values to match (character or coercible to character).
#' @returns A data.frame / sf object with rows matching `col %in% vals`.
#' @keywords internal
store_filter_layer <- function(store, layer, col, vals, ...) {
  UseMethod("store_filter_layer")
}

#' @keywords internal
store_filter_layer.default <- function(store, layer, col, vals, ...) {
  # Lazy filter + collect — full pushdown for Arrow / DuckDB stores
  store_get_layer(store, layer) |>
    dplyr::filter(.data[[col]] %in% vals) |>
    dplyr::collect()
}
