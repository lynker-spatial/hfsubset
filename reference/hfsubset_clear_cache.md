# Clear the cached subsetting graphs

[`hfsubset()`](https://lynker-spatial.github.io/hfsubset/reference/hfsubset.md)
caches each VPU's network id-table and traversal graph in memory so
repeated subsets over the same fabric are fast. Call this to free that
memory or to force a rebuild after the underlying source changes.

## Usage

``` r
hfsubset_clear_cache()
```

## Value

Number of cached entries removed, invisibly.
