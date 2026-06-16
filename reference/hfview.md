# View layers with mapview (robust to NULLs/mixed lists)

View layers with mapview (robust to NULLs/mixed lists)

## Usage

``` r
hfview(x, quiet = FALSE, drop_empty = TRUE)
```

## Arguments

- x:

  List (possibly mixed, with NULLs) or path to a GeoPackage (.gpkg).

- quiet:

  Logical; if TRUE, suppress messages when mapview isn't installed or no
  layers found.

- drop_empty:

  Logical; if TRUE, drop sf layers with zero rows. Default TRUE.

## Value

A mapview object (if any layers + mapview available) or NULL
(invisibly).
