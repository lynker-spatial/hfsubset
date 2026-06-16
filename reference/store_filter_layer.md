# Filter a store layer and return collected results

Dispatches to a store-appropriate backend so that Arrow/DuckDB stores
keep full predicate pushdown while OGR stores bypass dbplyr translation
and issue hand-crafted SQL directly to the underlying SQLite engine
(GPKG is SQLite).

## Usage

``` r
store_filter_layer(store, layer, col, vals, ...)
```

## Arguments

- store:

  A store object.

- layer:

  Layer name (character scalar).

- col:

  Column name to filter on (character scalar).

- vals:

  Values to match (character or coercible to character).

## Value

A data.frame / sf object with rows matching `col %in% vals`.
