# Resolve an origin (and/or traversal structure) from a cached S3 sidecar

STUB. Establishes the download + `R_user_dir` cache contract; not yet
wired into
[`hfsubset()`](https://lynker-spatial.github.io/hfsubset/reference/hfsubset.md).
Errors with guidance until the producer publishes the sidecar artifact.
When live: check cache -\> validate ETag/version -\> download if
missing/stale -\> read parquet.

## Usage

``` r
resolve_sidecar(
  version,
  vpu,
  base = "https://proxy.lynker-spatial.com/hydrofabric"
)
```

## Arguments

- version:

  Fabric version (e.g. "2.2", "3.0").

- vpu:

  VPU id (e.g. "09").

- base:

  Sidecar root URL on the lynker-spatial proxy.
