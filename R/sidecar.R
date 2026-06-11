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
# governs this package's code, not that artifact. The data is DUAL-LICENSED to
# support selling it: an open **ODbL** track (strong database share-alike, which
# motivates commercial users to buy out of the copyleft) plus a separate paid
# **commercial license**. The open sidecar is therefore ODbL; commercial
# customers receive it under the commercial terms. Declared at the S3 artifact
# level (a sibling LICENSE/manifest), since it crosses into NGIAB too.
#
# CAVEATS (gate the sell-the-data plan — resolve before relying on revenue):
#   * Dual-licensing requires holding ALL rights -> a contributor CLA if anyone
#     else contributes, or you lose the right to relicense commercially.
#   * You can only sell your VALUE-ADD (curation/QA/processing). The fabric is
#     built on US public-domain federal data (NHDPlus/NWM/NWIS); the underlying
#     facts are free and reproducible, so the moat is processing + support, not
#     the raw bytes.
#   * If the fabric was produced under federal funding (CIROH/NOAA), the funding
#     terms may REQUIRE it stay publicly available / forbid exclusive sale.
#     CHECK the funding agreement first — this is the real risk to monetization.
# See .sidecar_license_note().
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
    "Sidecar data is derived from the Lynker Spatial hydrofabric: open use under ODbL (share-alike), or a commercial license — separate from this package's Apache-2.0 code."
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
