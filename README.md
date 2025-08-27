
<!-- README.md is generated from README.Rmd. Please edit that file -->

# hfsubset

<!-- badges: start -->

[![License: Apache License (\>=
2)](https://img.shields.io/badge/License-Apache%20License%20%28%3E%3D%202%29-blue.svg)](https://choosealicense.com/licenses/apache-2.0/)
[![LifeCycle](https://img.shields.io/badge/lifecycle-experimental-orange)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![Dependencies](https://img.shields.io/badge/dependencies-7/74-orange?style=flat)](#)
<!-- badges: end -->

``` r
library(hfsubset)

hfsubset(gpkg =  glue::glue('{base_dir}/v3.0/reference_fabric.gpkg'),
         hl_reference = "nwis-07187000") |> 
  str(max.level = 1)
#> ℹ Origin flowpath: 7590701 (VPU: 11)
#> List of 5
#>  $ network       : tibble [262 × 22] (S3: tbl_df/tbl/data.frame)
#>  $ flowpaths     : sf [244 × 26] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..- attr(*, "names")= chr [1:25] "flowpath_id" "vpuid" "reachcode" "frommeas" ...
#>  $ divides       : sf [241 × 6] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA
#>   .. ..- attr(*, "names")= chr [1:5] "divide_id" "vpuid" "areasqkm" "has_flowpath" ...
#>  $ pois          : sf [31 × 9] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA
#>   .. ..- attr(*, "names")= chr [1:8] "poi_id" "flowpath_id" "hl_count" "hl_classes" ...
#>  $ hydrolocations: sf [49 × 13] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..- attr(*, "names")= chr [1:12] "vpuid" "flowpath_id" "poi_id" "hl_id" ...

hfsubset(gpkg =   glue::glue('{base_dir}/v3.0/refactored_fabric.gpkg'),
         hl_reference = "nwis-07187000") |> 
  str(max.level = 1)
#> ℹ Origin flowpath: 7590701 (VPU: 11)
#> List of 5
#>  $ network       : tibble [280 × 21] (S3: tbl_df/tbl/data.frame)
#>  $ flowpaths     : sf [209 × 13] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..- attr(*, "names")= chr [1:12] "flowpath_id" "flowpath_toid" "vpuid" "levelpathid" ...
#>  $ divides       : sf [207 × 6] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA
#>   .. ..- attr(*, "names")= chr [1:5] "divide_id" "areasqkm" "vpuid" "flowpath_id" ...
#>  $ pois          : sf [0 × 10] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA
#>   .. ..- attr(*, "names")= chr [1:9] "poi_id" "poi_offset" "flowpath_id" "flowpath_measure" ...
#>  $ hydrolocations: sf [64 × 16] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..- attr(*, "names")= chr [1:15] "hf_id" "poi_id" "hl_id" "hl_link" ...

hfsubset(gpkg =  glue::glue('{base_dir}/CONUS/v2.2/nextgen/v2.2_conus.gpkg'),
         hl_reference = "nwis-07187000") |> 
  str(max.level = 1)
#> ℹ Origin flowpath: 7590701 (VPU: 11)
#> List of 8
#>  $ network            : tibble [282 × 19] (S3: tbl_df/tbl/data.frame)
#>  $ flowpaths          : sf [86 × 13] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..- attr(*, "names")= chr [1:12] "id" "toid" "mainstem" "order" ...
#>  $ divides            : sf [86 × 11] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA NA NA NA NA NA
#>   .. ..- attr(*, "names")= chr [1:10] "divide_id" "toid" "type" "ds_id" ...
#>  $ nexus              : sf [47 × 6] (S3: sf/tbl_df/tbl/data.frame)
#>   ..- attr(*, "sf_column")= chr "geom"
#>   ..- attr(*, "agr")= Factor w/ 3 levels "constant","aggregate",..: NA NA NA NA NA
#>   .. ..- attr(*, "names")= chr [1:5] "id" "toid" "type" "vpuid" ...
#>  $ divide-attributes  : tibble [86 × 40] (S3: tbl_df/tbl/data.frame)
#>  $ flowpath-attributes: tibble [86 × 21] (S3: tbl_df/tbl/data.frame)
#>  $ pois               : tibble [10 × 4] (S3: tbl_df/tbl/data.frame)
#>  $ hydrolocations     : tibble [13 × 11] (S3: tbl_df/tbl/data.frame)
```
