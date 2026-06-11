#' Index and optimize a hydrofabric GeoPackage
#'
#' Make a written subset cheap to query and re-subset. Three things, borrowed
#' from the `verify_indices()` / R-tree handling in CIROH's
#' NGIAB_data_preprocess:
#'
#' \enumerate{
#'   \item **Attribute indices** on the id / foreign-key columns of every table
#'     (e.g. `flowpath_id`, `divide_id`, `vpuid`). `sf` writes the spatial
#'     R-tree but leaves attribute tables (`network`, `*-attributes`) and
#'     non-geometry id columns unindexed, so `WHERE flowpath_id IN (...)`
#'     re-subsetting scans the whole table without these.
#'   \item **Spatial R-tree verification.** GDAL builds `rtree_<layer>_<geom>`
#'     at write time (`SPATIAL_INDEX=YES`). We confirm each feature layer has
#'     one and rebuild any that is missing, so the index is present *and*
#'     freshly built (optimal) before anything copies it downstream.
#'   \item **`ANALYZE` + `PRAGMA optimize`** so SQLite's planner actually uses
#'     the new indices and the R-tree statistics are current.
#' }
#'
#' @param gpkg     Path to a GeoPackage written by [hfsubset()].
#' @param extra_cols Additional column names to index when present.
#' @param verbose  Logical; report indices created and R-trees rebuilt.
#' @returns The `gpkg` path, invisibly.
#' @importFrom DBI dbConnect dbDisconnect dbListTables dbListFields dbExecute dbGetQuery
#' @export
optimize_gpkg <- function(gpkg, extra_cols = character(), verbose = FALSE) {
  require_pkg("RSQLite")
  stopifnot(file.exists(gpkg))

  index_cols <- unique(c(
    "flowpath_id", "flowpath_toid", "flowline_id", "flowline_toid",
    "divide_id", "nexus_id", "poi_id", "mainstem_id", "vpuid",
    "hl_reference", "hf_id", "reference_id", "id", "toid", "fid",
    extra_cols
  ))

  # ---- pass 1: discover feature layers and any missing R-trees -------------
  con <- DBI::dbConnect(RSQLite::SQLite(), gpkg)
  tables <- DBI::dbListTables(con)
  feats <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT c.table_name AS tbl, g.column_name AS geom
         FROM gpkg_contents c
         JOIN gpkg_geometry_columns g ON c.table_name = g.table_name
        WHERE c.data_type = 'features'"
    ),
    error = function(e) data.frame(tbl = character(), geom = character())
  )
  DBI::dbDisconnect(con)

  missing_rtree <- feats[
    !paste0("rtree_", feats$tbl, "_", feats$geom) %in% tables, ,
    drop = FALSE
  ]

  # ---- rebuild missing R-trees via GDAL (re-write the layer w/ index) ------
  for (i in seq_len(nrow(missing_rtree))) {
    lyr <- missing_rtree$tbl[i]
    obj <- sf::st_read(gpkg, layer = lyr, quiet = TRUE)
    sf::write_sf(
      obj, dsn = gpkg, layer = lyr,
      delete_layer = TRUE,
      layer_options = "SPATIAL_INDEX=YES"
    )
    if (verbose) cli::cli_alert_info("Rebuilt spatial index for {.strong {lyr}}.")
  }

  # ---- pass 2: attribute indices + planner stats ---------------------------
  con <- DBI::dbConnect(RSQLite::SQLite(), gpkg)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  n_idx <- 0L
  for (tb in tables) {
    if (grepl("^(gpkg_|rtree_|sqlite_)", tb)) next
    cols <- tryCatch(DBI::dbListFields(con, tb), error = function(e) character())
    for (cc in intersect(index_cols, cols)) {
      idx <- sprintf("idx_%s_%s", gsub("[^A-Za-z0-9_]", "_", tb), cc)
      DBI::dbExecute(
        con,
        sprintf('CREATE INDEX IF NOT EXISTS "%s" ON "%s"("%s")', idx, tb, cc)
      )
      n_idx <- n_idx + 1L
    }
  }

  DBI::dbExecute(con, "ANALYZE")
  DBI::dbExecute(con, "PRAGMA optimize")

  if (verbose) {
    cli::cli_alert_success("Optimized {.path {gpkg}}: {n_idx} attribute index(es), planner stats refreshed.")
  }
  invisible(gpkg)
}
