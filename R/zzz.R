.onLoad <- function(libname, pkgname) {
  .S3method("store_has_layer", "arrow_store")
  .S3method("store_get_layer", "arrow_store")
  .S3method("store_has_layer", "lynker_spatial_store")
  .S3method("store_get_layer", "lynker_spatial_store")
  .S3method("store_has_layer", "ogr_store")
  .S3method("store_get_layer", "ogr_store")
  .S3method("store_filter_layer", "ogr_store")
}