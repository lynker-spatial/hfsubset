# ---------------------------------------------------------------------------
# Cached S3 sidecar resolver  (STUB — integration point, not yet wired in)
#
# Design (see also memory: hfsubset is a consumer):
#   hfsubset is a *consumer* of the hydrofabric. The *producer* pipeline
#   publishes a small per-(fabric-version, VPU) parquet "sidecar" alongside
#   each fabric release on the lynker-spatial proxy. The sidecar carries:
#     * an origin index   : comid / hl_reference -> flowpath_id + vpuid
#     * a traversal struct : reverse-adjacency, or (eventually) topo_lo/topo_hi
#   One parquet serves both consumers — hfsubset (R) and NGIAB (Python) — and
#   replaces BOTH the bundled `ref_net` and NGIAB's local pickle.
#
#   On first use for a (version, vpu) we download the sidecar to a per-user
#   cache dir and read locally thereafter (the "downloaded + cached on first
#   run" pattern), keyed by version + ETag so it cannot silently go stale.
#
# LICENSING: the sidecar is *data*, a derivative of the hydrofabric — Apache-2.0
# governs this package's code, not that artifact. The data ships under
# CC-BY-SA-4.0 (attribution + share-alike: keeps it open and forces derivatives
# open, while staying usable by NGIAB / CIROH / federal / commercial users —
# which an -NC clause would have blocked). Declared at the S3 artifact level (a
# sibling LICENSE/manifest), since it crosses into NGIAB too. CAVEAT: CC-BY-SA
# is only valid if the *upstream* fabric license permits it (e.g. CC-BY or
# matching SA); if upstream is ODbL the sidecar must be ODbL instead — confirm
# the upstream license before publishing. See .sidecar_license_note().
# ---------------------------------------------------------------------------

#' Local cache directory for downloaded sidecars
#' @keywords internal
.sidecar_cache_dir <- function() {
  tools::R_user_dir("hfsubset", which = "cache")
}

#' One-time data-license / attribution notice for cached sidecars
#' @keywords internal
.sidecar_license_note <- function() {
  cli::cli_alert_info(
    "Sidecar data is derived from the Lynker Spatial hydrofabric, licensed CC-BY-SA-4.0 (attribution + share-alike) — separate from this package's Apache-2.0 code."
  )
}

#' Resolve an origin (and/or traversal structure) from a cached S3 sidecar
#'
#' STUB. Establishes the download + `R_user_dir` cache contract; not yet wired
#' into [hfsubset()]. Errors with guidance until the producer publishes the
#' sidecar artifact. When live: check cache -> validate ETag/version ->
#' download if missing/stale -> read parquet.
#'
#' @param version Fabric version (e.g. "2.2", "3.0").
#' @param vpu     VPU id (e.g. "09").
#' @param base    Sidecar root URL on the lynker-spatial proxy.
#' @keywords internal
resolve_sidecar <- function(version, vpu,
                            base = "https://proxy.lynker-spatial.com/hydrofabric") {
  cli::cli_abort(c(
    "!" = "Sidecar resolver is not yet wired up.",
    "i" = "Producer must publish {.path {base}/v{version}/sidecar/vpu={vpu}/part-0.parquet}.",
    "i" = "Until then, traversal uses the in-DB recursive CTE (ogr) or cached igraph (arrow/ls)."
  ))
}
