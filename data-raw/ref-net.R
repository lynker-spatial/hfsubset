qq <- hfsubsetR::as_ogr('/Users/mikejohnson/hydrofabric/v3.0/reference_fabric.gpkg', "network") |>
  dplyr::select('flowpath_id', 'flowpath_toid', 'hl_reference', 'vpuid') |>
  dplyr::distinct() |>
  dplyr::collect() |>
  dplyr::mutate(flowpath_id   = as.integer(flowpath_id),
         flowpath_toid = as.integer(flowpath_toid),
         vpuid = as.factor(vpuid))

usethis::use_data(ref_net, overwrite = T, compress = "xz", version = 3)
arrow::write_parquet(qq, sink = "data-raw/ref-net.parquet", compression = "ZSTD")
