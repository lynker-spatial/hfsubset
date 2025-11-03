#' View layers with mapview (robust to NULLs/mixed lists)
#'
#' @param x List (possibly mixed, with NULLs) or path to a GeoPackage (.gpkg).
#' @param quiet Logical; if TRUE, suppress messages when mapview isn't installed or no layers found.
#' @param drop_empty Logical; if TRUE, drop sf layers with zero rows. Default TRUE.
#' @return A mapview object (if any layers + mapview available) or NULL (invisibly).
#' @export

hfview <- function(x, quiet = FALSE, drop_empty = TRUE) {
  # Dependency check
  if (!requireNamespace("mapview", quietly = TRUE)) {
    if (!quiet) message("Package 'mapview' not installed. Install it to view maps.")
    return(invisible(NULL))
  }

  sf_list <- list()

  if (inherits(x, "list")) {
    nms <- names(x)
    for (i in seq_along(x)) {
      el <- x[[i]]
      if (is.null(el)) next
      if (inherits(el, "sf")) {
        if (drop_empty && nrow(el) == 0) next
        nm <- if (!is.null(nms) && nms[i] != "") nms[i] else paste0("layer_", i)
        sf_list[[nm]] <- el
      }
    }
  } else if (is.character(x) && length(x) == 1 && file.exists(x)) {
    layer_names <- sf::st_layers(x)$name
    if (length(layer_names) == 0L) {
      if (!quiet) message("No layers found in GeoPackage: ", x)
      return(invisible(NULL))
    }
    read_one <- function(lyr) {
      sf::st_read(x, layer = lyr, quiet = TRUE)
    }
    tmp <- lapply(layer_names, read_one)
    names(tmp) <- layer_names
    # keep only sf, optionally drop empties
    for (nm in names(tmp)) {
      el <- tmp[[nm]]
      if (inherits(el, "sf") && (!drop_empty || nrow(el) > 0)) {
        sf_list[[nm]] <- el
      }
    }
  } else {
    stop("Input must be a list (may contain NULLs) or a valid GeoPackage path.")
  }

  if (length(sf_list) == 0) {
    if (!quiet) message("No mappable sf layers found.")
    return(invisible(NULL))
  }

  # Build mapview layers and combine
  mv_list <- lapply(names(sf_list), function(nm) {
    mapview::mapview(sf_list[[nm]], layer.name = nm)
  })
  Reduce(`+`, mv_list)
}
