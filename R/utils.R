#' @keywords internal
require_pkg <- function(pkgname) {
  if (!requireNamespace(pkgname, quietly = TRUE)) {
    stop("Package `", pkgname, "` is required.")
  }
}