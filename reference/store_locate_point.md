# Locate the divide containing a point

Resolve an `xy` coordinate to the divide (catchment) polygon that
contains it. Used by
[`hfsubset()`](https://lynker-spatial.github.io/hfsubset/reference/hfsubset.md)
to support point-based origins ("subset above where I clicked"). Mirrors
the lat/lon lookup in CIROH's NGIAB_data_preprocess: transform the point
to the layer CRS, hit the spatial index for candidates, then test exact
containment.

## Usage

``` r
store_locate_point(store, xy, crs_pt = 4326, layer = "divides", ...)
```

## Arguments

- store:

  A store object.

- xy:

  Numeric length-2 vector, `c(x, y)` (e.g. `c(lon, lat)`).

- crs_pt:

  CRS of `xy`. Default EPSG:4326 (WGS84 lon/lat).

- layer:

  Polygon layer to test containment against. Default "divides".

## Value

An `sf` of the matching divide row(s); zero rows if the point falls
outside the fabric.
