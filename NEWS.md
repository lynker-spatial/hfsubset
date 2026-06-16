# hfsubset 0.2

* Subsetting works against both GeoPackage (OGR) and GeoParquet stores, with
  upstream network traversal from an origin `id`, `comid`, or `hl_reference`.
* Optional `check = TRUE` runs `hfutils::hf_check_invariants("ngen", ...)` on the
  returned subset (warnings only; does not stop).
* Lynker Spatial pkgdown site with cross-stack navigation.
* Removed the bundled `ref_net` dataset (~6 MB). It was a vestige of the
  pre-store architecture and is no longer consumed: origin resolution and
  upstream traversal now run against the OGR/Arrow/Lynker Spatial stores, and
  the planned per-VPU sidecar (see `R/sidecar.R`) supersedes it. Dropping it
  also keeps the Apache-2.0 code separate from the ODbL-tracked fabric data.
