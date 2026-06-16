# Register S3 methods for the internal `store_*` generics.
#
# These generics and their methods are unexported, and several generics
# (store_has_layer, store_get_layer) have no `.default`, so dispatch *must* find
# the class method or it hard-errors. Rather than hand-maintain a list (the old
# version was incomplete -- it omitted locate_point, upstream_ids, and the
# `.default`s), discover every `generic.class` method in the namespace and
# register it. New store methods are picked up automatically.
.onLoad <- function(libname, pkgname) {
  ns <- asNamespace(pkgname)
  generics <- c(
    "store_has_layer", "store_get_layer", "store_layer_cols",
    "store_filter_layer", "store_filter_hl_reference",
    "store_locate_point", "store_upstream_ids"
  )
  pat <- paste0("^(", paste(generics, collapse = "|"), ")\\.")
  for (fn in ls(ns, pattern = pat)) {
    hit <- generics[vapply(generics, function(g) startsWith(fn, paste0(g, ".")), logical(1))]
    g   <- hit[which.max(nchar(hit))]          # longest prefix wins
    cls <- substring(fn, nchar(g) + 2L)        # text after "generic."
    registerS3method(g, cls, get(fn, envir = ns), envir = ns)
  }
}
