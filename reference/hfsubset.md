# Subset a NextGen HydroFabric from either a GPKG or layered Hive-partitioned GeoParquets

Given a HydroFabric store and an origin identifier (by `flowpath_id`, by
an external `comid`, or by an `hl_reference` tag), build an upstream
subgraph and return/write filtered layers.

## Usage

``` r
hfsubset(
  src,
  id,
  comid,
  hl_reference,
  gage,
  xy,
  outfile = NULL,
  lyrs = c("flowpaths", "flowlines", "divides", "nexus", "network", "hydrolocations",
    "pois", "flowpath-attributes", "divide-attributes"),
  crs = NULL,
  verbose = FALSE,
  check = FALSE,
  cache = TRUE,
  optimize = TRUE
)
```

## Arguments

- src:

  Path to a GeoPackage (.gpkg) OR the root directory of layered
  hive-partitioned GeoParquet (e.g., //v1/vpu=01/part-\*.parquet). The
  store type (GeoPackage vs GeoParquet) is inferred from `src`.

- id:

  Origin `flowpath_id` (character).

- comid:

  Origin NHDPlusV2 COMID.

- hl_reference:

  Origin `hl_reference` tag (e.g. `nwis-09112500`).

- gage:

  Origin USGS gage id (e.g. `"09112500"`). Convenience for
  `hl_reference = paste0("nwis-", gage)`; an 8-digit id is expected.

- xy:

  Origin point as `c(x, y)` (defaults to lon/lat, EPSG:4326). Resolved
  to the containing divide, then to its flowpath. Uses the GPKG R-tree
  on OGR stores; reads the full divides layer otherwise.

- outfile:

  Optional path to write the subset to a new GeoPackage.

- lyrs:

  Character vector of layer names to extract. Defaults to
  c("flowpaths","divides","nexus","network","hydrolocations","pois",
  "flowpath-attributes","divide-attributes").

- crs:

  Optional EPSG/int for sf outputs when reading GeoParquet (recommended
  if CRS missing).

- verbose:

  Logical. Emit progress messages. Default `FALSE`.

- check:

  Logical. If `TRUE`, run `hfutils::hf_check_invariants("ngen", ...)` on
  the returned subset (warnings only, does not stop). Default `FALSE`.

- cache:

  Logical. Reuse an in-memory per-VPU network graph across calls (big
  win for batch subsetting). Default `TRUE`. See
  [`hfsubset_clear_cache()`](https://lynker-spatial.github.io/hfsubset/reference/hfsubset_clear_cache.md).

- optimize:

  Logical. When writing `outfile`, index and optimize the GeoPackage via
  [`optimize_gpkg()`](https://lynker-spatial.github.io/hfsubset/reference/optimize_gpkg.md).
  Default `TRUE`.

## Value

A named list of tibbles/sf if `outfile` is missing; invisibly the list
after writing otherwise.
