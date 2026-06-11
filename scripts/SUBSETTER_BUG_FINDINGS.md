# Subsetter Bug Findings — VPU-01 Calibration Subset Run

Discovered and fixed during the VPU-01 calibration gage subsetting run
(`scripts/run_vpu01_calibration_subsets.R`) against `ngen_vpu01.gpkg`.

---

## Bug 1 — `flowlines` layer filtered by wrong ID column

**File:** `R/subsetter.R`

**Symptom:** Flowlines appeared spatially far from all other layers (flowpaths,
divides, nexus). Zero flowlines intersected any divide geometry.

**Root cause:** The `flowlines` layer in per-VPU ngen gpkg files uses its own
internal sequential `flowline_id` (e.g. 11640, 11641…). The `network` table
stores NHDPlus COMID-based `flowline_id` integers (e.g. 18640, 18644…) — a
completely different ID space. The subsetter was passing the NHDPlus integers
from `network` as the filter key against the `flowlines` layer, returning rows
from a geographically unrelated part of the VPU.

**Fix:** Added `"flowlines"` to the `flowpath_id` filter branch so the flowlines
layer is filtered by `flowpath_id` (which is consistent across both layers)
rather than by `flowline_id`.

```r
# Before
} else if (layer %in% c("flowpaths", "flowpath-attributes")) {
  out[[layer]] <- store_filter_layer(store, layer, "flowpath_id", fp_vals)
} else {
  out[[layer]] <- store_filter_layer(store, layer, "flowline_id", fl_vals)
}

# After
} else if (layer %in% c("flowpaths", "flowlines", "flowpath-attributes")) {
  out[[layer]] <- store_filter_layer(store, layer, "flowpath_id", fp_vals)
} else {
  out[[layer]] <- store_filter_layer(store, layer, "flowline_id", fl_vals)
}
```

---

## Bug 2 — `fl_vals` included downstream `flowline_toid`, polluting the filter set

**File:** `R/subsetter.R`

**Symptom:** Flowlines from outside the upstream catchment were included in
subsets (caught by inspecting `flowpath_id` values on returned flowlines).

**Root cause:** `fl_vals` was computed as
`unique(c(vpu_sub$flowline_id, vpu_sub$flowline_toid))`. The `flowline_toid`
of the most-downstream flowline in the subset points to a flowline *outside*
the upstream network (the outlet's downstream neighbour). Including it pulled
in an extra row.

**Fix:** Drop `flowline_toid` from the set — only use `flowline_id`.

```r
# Before
fl_vals <- unique(c(vpu_sub$flowline_id, vpu_sub$flowline_toid))

# After
fl_vals <- unique(vpu_sub$flowline_id)
```

---

## Bug 3 — Origin anchor used `flowpath_toid` (nexus) instead of `flowpath_id`

**File:** `R/subsetter.R`

**Symptom:** For some gages (e.g. `nwis-01031500`) the returned subset
contained only the immediately downstream flowpath rather than the gage's own
catchment and everything upstream.

**Root cause:** After resolving the `hl_reference` row, the code set
`origin_fp <- origin_row$flowpath_toid[[1]]` — the *nexus* the gage drains
into — then found flowlines whose `flowpath_toid` equalled that nexus. This
resolves to the *next downstream* flowpath, not the gage's own flowpath.

**Fix:** Use `flowpath_id` as the anchor and find the outlet flowline (the
one whose `flowline_toid` exits the flowpath).

```r
# Before
origin_fp  <- origin_row$flowpath_toid[[1]]
origin_fl  <- vpu_ids$flowline_id[vpu_ids$flowpath_toid == origin_fp][1]

# After
origin_fp_id    <- origin_row$flowpath_id[[1]]
origin_fp_rows  <- vpu_ids[vpu_ids$flowpath_id == origin_fp_id, ]
fp_fl_ids       <- origin_fp_rows$flowline_id
outlet_mask     <- !(origin_fp_rows$flowline_toid %in% fp_fl_ids)
origin_fl       <- origin_fp_rows$flowline_id[which(outlet_mask)[1]]
```

---

## Bug 4 — `hl_reference` exact match fails for pipe-delimited values

**File:** `R/subsetter.R`, `R/store-ogr.R`, `R/store.R`

**Symptom:** `hfsubset(..., hl_reference = "nwis-01030500")` threw
"Could not locate origin in the network layer" even though the gage existed.

**Root cause:** The network table stores compound references like
`"nwis-01030500|huc12-010200030703"`. The subsetter used exact equality
(`hl_reference == "nwis-01030500"`) which never matched.

**Fix:** Added a `store_filter_hl_reference()` generic dispatched per store
type. The OGR implementation uses SQLite `LIKE '%nwis-XXXXXX%'`; the default
implementation uses `grepl(..., fixed = TRUE)`.

---

## Bug 5 — Per-VPU gpkg has no `vpuid` column in `network`

**File:** `R/subsetter.R`, `R/store.R`, `R/store-ogr.R`

**Symptom:** Error `Column 'vpuid' doesn't exist` when subsetting from a
single-VPU gpkg (e.g. `ngen_vpu01.gpkg`).

**Root cause:** The subsetter was written for a multi-VPU store where `vpuid`
exists in the network table. Per-VPU files omit this column — the whole file
is already one VPU.

**Fix:** Added `store_layer_cols()` generic. Subsetter detects `vpuid`
presence; when absent, skips the VPU filter and uses all network rows.
