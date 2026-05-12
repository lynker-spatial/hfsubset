library(dplyr)
library(sf)
library(igraph)
library(hfsubset)

src     <- "s3://lynker-spatial/hydrofabric/v4.0/superconus"
out_dir <- "outputs/vpu01_calibration_nwmv4_v2"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

vpu01_gages <- c(
  "01030500","01031500","01069700","01073500","01078000",
  "01108000","01115187","01115630","01118000","01144000",
  "01152500","01162500","01193500"
)

results <- vector("list", length(vpu01_gages))

for (i in seq_along(vpu01_gages)) {
  gage_id  <- vpu01_gages[i]
  hl_ref   <- paste0("nwis-", gage_id)
  out_path <- file.path(out_dir, sprintf("subset_%s.gpkg", gage_id))

  cat(sprintf("\n[%d/%d] %s\n", i, length(vpu01_gages), hl_ref))

  sub <- tryCatch(
    hfsubset(src = src, hl_reference = hl_ref, outfile = out_path, crs = 5070),
    error = function(e) { cat(sprintf("  ERROR: %s\n", conditionMessage(e))); NULL }
  )
  if (is.null(sub)) {
    results[[i]] <- list(gage_id=gage_id, subset_ok=FALSE, invariants_ok=NA, downstream_ok=NA)
    next
  }

  inv_ok <- tryCatch({
    hfutils::hf_check_invariants("ngen",
      flowpaths=sub$flowpaths, divides=sub$divides, nexus=sub$nexus, strict=FALSE)$ok
  }, error=function(e) FALSE)

  ds_ok <- tryCatch({
    nex_sub <- sf::st_drop_geometry(sub$nexus)
    fp_sub  <- sf::st_drop_geometry(sub$flowpaths)
    origin_nex <- fp_sub$flowpath_toid[fp_sub$flowpath_id ==
      dplyr::filter(as.data.frame(sub$network), grepl(hl_ref, hl_reference, fixed=TRUE))$flowpath_id[1]]
    if (length(origin_nex) == 0 || is.na(origin_nex[1])) stop("no origin nex")
    origin_nex <- origin_nex[1]
    in_sub  <- origin_nex %in% nex_sub$nexus_id
    is_nex  <- startsWith(origin_nex, "nex-") | startsWith(origin_nex, "tnx-")
    nex_toid <- nex_sub$nexus_toid[nex_sub$nexus_id == origin_nex]
    drains_in <- length(nex_toid) > 0 && !is.na(nex_toid[1]) &&
                 (nex_toid[1] %in% fp_sub$flowpath_id | nex_toid[1] %in% nex_sub$nexus_id)
    in_sub && is_nex && !drains_in
  }, error=function(e) { cat(sprintf("  ds check error: %s\n", conditionMessage(e))); FALSE })

  results[[i]] <- list(gage_id=gage_id, subset_ok=TRUE, invariants_ok=inv_ok, downstream_ok=ds_ok)
  cat(sprintf("  invariants: %s | downstream: %s\n",
              if (inv_ok) "PASS" else "FAIL", if (ds_ok) "PASS" else "FAIL"))
}

summary_df <- dplyr::bind_rows(lapply(results, as.data.frame, stringsAsFactors=FALSE))
write.csv(summary_df, file.path(out_dir, "subset_quality_summary.csv"), row.names=FALSE)

cat(sprintf("\nDone. %d/%d subsets OK\n",
            sum(summary_df$subset_ok, na.rm=TRUE), nrow(summary_df)))

# Upload to S3
cat("Uploading to S3...\n")
for (gpkg in list.files(out_dir, "^subset_.*\\.gpkg$", full.names=TRUE)) {
  gage_id <- sub("\\.gpkg$", "", sub("subset_", "", basename(gpkg)))
  s3_key  <- sprintf("s3://lynker-spatial/hydrofabric/v4.0/subsets/gage/USGS-%s-ngen.gpkg", gage_id)
  cat(sprintf("  %s\n", s3_key))
  system2("aws", c("s3", "cp", shQuote(gpkg), shQuote(s3_key),
                   "--storage-class", "STANDARD_IA", "--no-progress"),
          stdout=FALSE, stderr=FALSE)
}
cat("Done.\n")
