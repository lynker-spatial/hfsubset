library(dplyr)
library(sf)
library(igraph)
library(hfsubset)
library(hfrefactor)

src     <- "/tmp/superconus_parquet"   # local mirror of s3://.../v4.0/superconus parquet tiles
out_dir <- "outputs/all_calibration_nwmv4"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

gages <- read.csv("vpu_calibration_subset_gages.csv",
                  colClasses = c(gage_id = "character", vpuid = "character"))

# Skip gages already completed in any prior run
already_done <- sub("subset_", "", sub("\\.gpkg$", "", c(
  list.files("outputs/vpu01_calibration_nwmv4", pattern = "^subset_.*\\.gpkg$"),
  list.files(out_dir,                            pattern = "^subset_.*\\.gpkg$")
)))
gages <- gages[!gages$gage_id %in% already_done, ]

cat(sprintf("Running %d gages (302 total minus %d already done)\n",
            nrow(gages), length(already_done)))

results <- vector("list", nrow(gages))

for (i in seq_len(nrow(gages))) {
  gage_id  <- gages$gage_id[i]
  hl_ref   <- paste0("nwis-", gage_id)
  out_path <- file.path(out_dir, sprintf("subset_%s.gpkg", gage_id))

  cat(sprintf("\n[%d/%d] %s (VPU %s)\n", i, nrow(gages), hl_ref, gages$vpuid[i]))

  # ---- subset ----------------------------------------------------------------
  # hfsubset() infers geoparquet store from s3:// prefix; Arrow reads only the
  # origin VPU partition of each layer — no full-domain load.
  sub <- tryCatch(
    hfsubset(src = src, hl_reference = hl_ref, outfile = out_path, crs = 5070),
    error = function(e) {
      cat(sprintf("  ERROR subsetting: %s\n", conditionMessage(e)))
      NULL
    }
  )

  if (is.null(sub)) {
    results[[i]] <- list(gage_id = gage_id, vpuid = gages$vpuid[i],
                         subset_ok = FALSE, invariants_ok = NA,
                         downstream_ok = NA, notes = "subset failed")
    next
  }

  # ---- invariant suite -------------------------------------------------------
  inv_ok <- tryCatch({
    hfrefactor::hf_check_invariants(
      "ngen",
      flowpaths = sub$flowpaths,
      divides   = sub$divides,
      nexus     = sub$nexus,
      strict    = FALSE
    )$ok
  }, error = function(e) {
    cat(sprintf("  ERROR in invariants: %s\n", conditionMessage(e)))
    FALSE
  })

  # ---- downstream-element check ----------------------------------------------
  ds_ok <- tryCatch({
    fp_sub  <- sf::st_drop_geometry(sub$flowpaths)
    nex_sub <- sf::st_drop_geometry(sub$nexus)
    net_sub <- if (inherits(sub$network, "sf")) sf::st_drop_geometry(sub$network)
               else as.data.frame(sub$network)

    sub_fp_ids  <- fp_sub$flowpath_id
    sub_nex_ids <- nex_sub$nexus_id

    # Find origin flowpath from the subset's own network table
    origin_fp_row <- net_sub |>
      filter(grepl(hl_ref, hl_reference, fixed = TRUE)) |>
      select(flowpath_id) |>
      distinct()

    if (nrow(origin_fp_row) == 0) stop("origin fp not found in subset network")

    origin_fp  <- origin_fp_row$flowpath_id[1]
    origin_nex <- fp_sub |> filter(flowpath_id == origin_fp) |>
      pull(flowpath_toid)

    if (length(origin_nex) == 0 || is.na(origin_nex[1])) {
      stop("origin flowpath has no flowpath_toid")
    }
    origin_nex <- origin_nex[1]

    origin_nex_in_sub <- origin_nex %in% sub_nex_ids
    origin_is_nexus   <- startsWith(origin_nex, "nex-") | startsWith(origin_nex, "tnx-")

    nex_toid <- nex_sub |> filter(nexus_id == origin_nex) |> pull(nexus_toid)
    toid_in_subset <- length(nex_toid) > 0 &&
      !is.na(nex_toid[1]) &&
      (nex_toid[1] %in% sub_fp_ids | nex_toid[1] %in% sub_nex_ids)

    if (!origin_nex_in_sub) {
      cat(sprintf("  WARN downstream: origin nexus %s not in subset\n", origin_nex))
      FALSE
    } else if (!origin_is_nexus) {
      cat(sprintf("  WARN downstream: terminal node %s is not a nexus (nex-/tnx-)\n", origin_nex))
      FALSE
    } else if (toid_in_subset) {
      cat(sprintf("  WARN downstream: origin nexus %s drains into subset\n", origin_nex))
      FALSE
    } else {
      cat(sprintf("  OK  downstream: terminal nexus = %s\n", origin_nex))
      TRUE
    }
  }, error = function(e) {
    cat(sprintf("  ERROR downstream check: %s\n", conditionMessage(e)))
    FALSE
  })

  results[[i]] <- list(
    gage_id       = gage_id,
    vpuid         = gages$vpuid[i],
    subset_ok     = TRUE,
    invariants_ok = inv_ok,
    downstream_ok = ds_ok,
    notes         = ""
  )

  cat(sprintf("  invariants: %s | downstream: %s\n",
              if (inv_ok) "PASS" else "FAIL",
              if (ds_ok)  "PASS" else "FAIL"))
}

# ---- summary ---------------------------------------------------------------
summary_df <- bind_rows(lapply(results, as.data.frame, stringsAsFactors = FALSE))
write.csv(summary_df,
          file.path(out_dir, "subset_quality_summary.csv"),
          row.names = FALSE)

cat(sprintf("\n\nDone. %d/%d subsets OK | %d/%d invariants OK | %d/%d downstream OK\n",
            sum(summary_df$subset_ok,     na.rm = TRUE), nrow(summary_df),
            sum(summary_df$invariants_ok, na.rm = TRUE), nrow(summary_df),
            sum(summary_df$downstream_ok, na.rm = TRUE), nrow(summary_df)))
cat(sprintf("Summary written to %s\n", file.path(out_dir, "subset_quality_summary.csv")))
