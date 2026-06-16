# Per-(source, VPU) cache of the collected network id table and its igraph.
#
# Rebuilding the upstream-traversal graph means collect()-ing the VPU's network
# rows and constructing an igraph every call. Batch workflows (many gages over
# one fabric/VPU -- e.g. the calibration-subset scripts) repeat that work
# identically. NGIAB's `get_graph()` is `@cache`-decorated and pickles the
# igraph for the same reason; we keep an in-memory env keyed by source + VPU.
.graph_cache <- new.env(parent = emptyenv())

.graph_cache_key <- function(store, vpu) {
  paste0(store$src %||% paste(unlist(store), collapse = "|"), "::vpu=", vpu %||% "ALL")
}

#' Clear the cached subsetting graphs
#'
#' [hfsubset()] caches each VPU's network id-table and traversal graph in memory
#' so repeated subsets over the same fabric are fast. Call this to free that
#' memory or to force a rebuild after the underlying source changes.
#'
#' @returns Number of cached entries removed, invisibly.
#' @export
hfsubset_clear_cache <- function() {
  n <- length(ls(.graph_cache))
  rm(list = ls(.graph_cache), envir = .graph_cache)
  invisible(n)
}
