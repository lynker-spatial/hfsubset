# hfsubset 0.2

* Subsetting works against both GeoPackage (OGR) and GeoParquet stores, with
  upstream network traversal from an origin `id`, `comid`, or `hl_reference`.
* Optional `check = TRUE` runs `hfutils::hf_check_invariants("ngen", ...)` on the
  returned subset (warnings only; does not stop).
* Lynker Spatial pkgdown site with cross-stack navigation.
