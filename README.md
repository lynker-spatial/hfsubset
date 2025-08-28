
<!-- README.md is generated from README.Rmd. Please edit that file -->

# hfsubset <a href="https://github.com/lynker-spatial/hfsubset"><img src="man/figures/logo.png" align="right" width="25%"/></a>

<!-- badges: start -->

[![License: Apache License (\>=
2)](https://img.shields.io/badge/License-Apache%20License%20%28%3E%3D%202%29-blue.svg)](https://choosealicense.com/licenses/apache-2.0/)
[![LifeCycle](https://img.shields.io/badge/lifecycle-experimental-orange)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![Dependencies](https://img.shields.io/badge/dependencies-7/74-orange?style=flat)](#)
[![Website](https://github.com/mikejohnson51/hfsubset/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/mikejohnson51/hfsubset/actions/workflows/pkgdown.yaml)
<!-- badges: end -->

`hfsubset` offers a lightweight subsetting utility for Lynker Spatial
Hydrofabrics.

To use, define a source geopackage and a hydrologic location reference
(e.g. NHDPlusV2 COMID, Hydrofabric ID or hydrolocation reference^\*
(`hl_reference`)). The function will return an `sf` object for each
requested layer containing all upstream features.

An hl_reference is defined as `{source}-{native_id}`, so, if you were
looking for the NWIS gage 07187000 you would use `nwis-07187000`.

``` r
library(hfsubset)

hfsubset(gpkg =  glue::glue('{base_dir}/v3.0/reference_fabric.gpkg'),
         hl_reference = "nwis-07187000") |> 
  lobstr::tree(max_depth = 1)
#> ℹ Origin flowpath: 7590701 (VPU: 11)
#> <list>
#> ├─network: S3<tbl_df/tbl/data.frame>...
#> ├─flowpaths: S3<sf/tbl_df/tbl/data.frame>...
#> ├─divides: S3<sf/tbl_df/tbl/data.frame>...
#> ├─pois: S3<sf/tbl_df/tbl/data.frame>...
#> └─hydrolocations: S3<sf/tbl_df/tbl/data.frame>...


hfsubset(gpkg =   glue::glue('{base_dir}/v3.0/refactored_fabric.gpkg'),
         hl_reference = "nwis-07187000") |> 
  lobstr::tree(max_depth = 1)
#> ℹ Origin flowpath: 7590701 (VPU: 11)
#> <list>
#> ├─network: S3<tbl_df/tbl/data.frame>...
#> ├─flowpaths: S3<sf/tbl_df/tbl/data.frame>...
#> ├─divides: S3<sf/tbl_df/tbl/data.frame>...
#> ├─pois: S3<sf/tbl_df/tbl/data.frame>...
#> └─hydrolocations: S3<sf/tbl_df/tbl/data.frame>...

hfsubset(gpkg =  glue::glue('{base_dir}/CONUS/v2.2/nextgen/v2.2_conus.gpkg'),
         hl_reference = "nwis-07187000") |> 
  lobstr::tree(max_depth = 1)
#> ℹ Origin flowpath: 7590701 (VPU: 11)
#> <list>
#> ├─network: S3<tbl_df/tbl/data.frame>...
#> ├─flowpaths: S3<sf/tbl_df/tbl/data.frame>...
#> ├─divides: S3<sf/tbl_df/tbl/data.frame>...
#> ├─nexus: S3<sf/tbl_df/tbl/data.frame>...
#> ├─divide-attributes: S3<tbl_df/tbl/data.frame>...
#> ├─flowpath-attributes: S3<tbl_df/tbl/data.frame>...
#> ├─pois: S3<tbl_df/tbl/data.frame>...
#> └─hydrolocations: S3<tbl_df/tbl/data.frame>...
```
