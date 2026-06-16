# Resolve the upstream id table for an origin flowpath

Return the subset of the network's id table (one row per upstream
flowline/flowpath) that drains to `origin_fp_id`. The result carries
whichever of `flowpath_id`, `flowpath_toid`, `poi_id`, `divide_id`,
`flowline_id` the schema provides – enough to filter every downstream
layer.

## Usage

``` r
store_upstream_ids(store, origin_fp_id, vpu, has_vpuid, cache = TRUE, ...)
```

## Arguments

- store:

  A store object.

- origin_fp_id:

  Origin `flowpath_id`.

- vpu:

  Origin VPU id (character) or `NA`.

- has_vpuid:

  Logical; whether the network carries a `vpuid` column.

- cache:

  Logical; reuse the per-(source, VPU) graph (default path).

## Value

A data.frame of upstream id columns.

## Details

Dispatch picks the cheapest correct traversal for the backend:

- `ogr_store` pushes the walk into SQLite with a recursive CTE, touching
  only upstream rows (no whole-VPU materialization, no graph build).

- the default collects the VPU's edges once and walks an in-memory
  igraph, caching both per (source, VPU) for batch reuse.
