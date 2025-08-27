#' Flowpath References Table
#'
#' A tibble mapping flowpaths to upstream/downstream connectivity and external
#' reference identifiers. Each row represents a relationship between a
#' \code{flowpath_id} and either its downstream feature or an associated
#' hydrologic reference.
#'
#' @format A tibble with 2,860,009 rows and 4 variables:
#' \describe{
#'   \item{flowpath_id}{`integer`. Unique identifier for a flowpath.}
#'   \item{vpuid}{`factor`. Vector Processing Unit (VPU) identifier indicating
#'   the regional partition of the hydrologic fabric.}
#'   \item{flowpath_toid}{`integer`. Identifier of the downstream flowpath.
#'   `NA` if terminal.}
#'   \item{hl_reference}{`factor`. Optional external reference code(s)
#'   associated with the flowpath, e.g. NBI bridge IDs, watershed outlets,
#'   or terminus identifiers. May be `NA`.}
#' }
#'
#' @details
#' This dataset is intended to support graph operations and external
#' lookups in hydrologic network analysis. A single `flowpath_id` can
#' appear multiple times when multiple `hl_reference` entries are
#' associated with it. Use dplyr::distinct where it makes sense :)
#'
#' @source Derived from lynker-spatial data products.
#'
#' @examples
#' data(ref_net)
#' dplyr::filter(ref_net, flowpath_id == 931090014)

"ref_net"
