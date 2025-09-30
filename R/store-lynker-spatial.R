#' @keywords internal
lynker_spatial_store <- function(version, domain, kind) {
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
    conn = duckdb_connection(extensions = "httpfs")
  )

  hfutils::lynker_spatial_auth(libs = "duckdb", duckdb_con = store$conn)

  class(store) <- c("lynker_spatial_store", class(store))
  store
}


#' @keywords internal
store_has_layer.lynker_spatial_store <- function(store, layer, ...) {
  p <- paste(store$src, layer, "vpuid=01", "part-0.parquet", sep = "/")

  ok <- try({
    tbl_http_parquet(p, conn = store$conn)
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

  tbl_http_parquet(urls, conn = store$conn)
}


#' Create a new DuckDB connection.
#' @param ... Arguments passed to [DBI::dbConnect()].
#' @param extensions Character vector of extensions to install and load on connect.
#' @returns A DBI connection to a DuckDB instance.
#' @keywords internal
duckdb_connection <- function(..., extensions = character(0)) {
  conn <- DBI::dbConnect(duckdb::duckdb(), ...)

  if (length(extensions) > 0) {
    for (ext in extensions) {
      DBI::dbExecute(conn, paste("INSTALL", ext))
      DBI::dbExecute(conn, paste("LOAD", ext))
    }
  }

  conn
}

#' @keywords internal
tbl_http_parquet <- function(urls, ..., conn = duckdb_connection(extensions = "httpfs")) {
  query <- paste0("SELECT * FROM read_parquet([",
    paste0("'", urls, "'", collapse = ","),
  "])")

  dplyr::tbl(conn, dbplyr::sql(query))
}
