#' @keywords internal
lynker_spatial_store <- function(version, domain, kind, ..., conn = hfutils::duckdb_connection(extensions = "httpfs")) {
  # TODO(justin): this is a mess

  if (startsWith(version, "v")) {
    version <- substring(version, 2)
  }

  if (version == "2.2") {
    # TODO(justin): fix this
    stop("Subsetting version 2.2 is not supported by this implementation")
  }

  if (kind == "reference") {
    if (version == "2.3") {
      kind <- "cn"
    } else {
      kind <- "reference/cn"
    }
  }

  store <- new_store(
    version = version,
    domain = domain,
    kind = kind,
    src = sprintf(
      "https://proxy.lynker-spatial.com/hydrofabric/v%s/%s/%s",
      version, domain, kind
    ),
    conn = conn
  )

  hfutils::lynker_spatial_auth(libs = c("gdal", "duckdb"), duckdb_con = store$conn)

  class(store) <- c("lynker_spatial_store", class(store))
  store
}


#' @keywords internal
store_has_layer.lynker_spatial_store <- function(store, layer, ...) {
  p <- paste(store$src, layer, "vpuid=01", "part-0.parquet", sep = "/")

  ok <- try({
    hfutils::tbl_http(p, conn = store$conn, read_func = "read_parquet")
    TRUE
  }, silent = TRUE)

  isTRUE(ok)
}


#' @keywords internal
store_get_layer.lynker_spatial_store <- function(store, layer, ...) {
  vpus <- sort(c(
    sprintf("%02d", c(1, 2, 4:9, 11:18)),
    "03N", "03S", "03W", "10L", "10U"
  ))

  urls <- paste(
    store$src,
    layer,
    paste0("vpuid=", vpus),
    "part-0.parquet",
    sep = "/"
  )

  hfutils::tbl_http(urls, conn = store$conn, read_func = "read_parquet")
}
