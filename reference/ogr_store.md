# Create a lazy OGR store

Resolves the source's layer names and per-layer CRS once at construction
so repeated
[`store_has_layer()`](https://lynker-spatial.github.io/hfsubset/reference/store_has_layer.md)
/ point-lookup calls within a single subset don't each re-open the file
with
[`sf::st_layers()`](https://r-spatial.github.io/sf/reference/st_layers.html).

## Usage

``` r
ogr_store(src)
```

## Arguments

- src:

  Source URI
