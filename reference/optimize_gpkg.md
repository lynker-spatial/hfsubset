# Index and optimize a hydrofabric GeoPackage

Make a written subset cheap to query and re-subset. Three things,
borrowed from the `verify_indices()` / R-tree handling in CIROH's
NGIAB_data_preprocess:

## Usage

``` r
optimize_gpkg(gpkg, extra_cols = character(), verbose = FALSE)
```

## Arguments

- gpkg:

  Path to a GeoPackage written by
  [`hfsubset()`](https://lynker-spatial.github.io/hfsubset/reference/hfsubset.md).

- extra_cols:

  Additional column names to index when present.

- verbose:

  Logical; report indices created and R-trees rebuilt.

## Value

The `gpkg` path, invisibly.

## Details

1.  **Attribute indices** on the id / foreign-key columns of every table
    (e.g. `flowpath_id`, `divide_id`, `vpuid`). `sf` writes the spatial
    R-tree but leaves attribute tables (`network`, `*-attributes`) and
    non-geometry id columns unindexed, so `WHERE flowpath_id IN (...)`
    re-subsetting scans the whole table without these.

2.  **Spatial R-tree verification.** GDAL builds `rtree_<layer>_<geom>`
    at write time (`SPATIAL_INDEX=YES`). We confirm each feature layer
    has one and rebuild any that is missing, so the index is present
    *and* freshly built (optimal) before anything copies it downstream.

3.  **`ANALYZE` + `PRAGMA optimize`** so SQLite's planner actually uses
    the new indices and the R-tree statistics are current.
