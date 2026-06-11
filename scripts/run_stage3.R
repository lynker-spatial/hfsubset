library(devtools)
library(dplyr)

devtools::load_all('.')

p <- '/Users/mikejohnson/hydrofabric/v3.0/ls-modeling-fabric.gpkg'
cat('Running hfsubset for hl_reference nwis-01017290 on', p, '\n')

res <- hfsubset(src = p, hl_reference = 'nwis-01017290', lyrs = c('flowpaths','divides','nexus','network','hydrolocations','pois'))

cat('\nResult layer counts:\n')
for (nm in names(res)) {
  r <- res[[nm]]
  n <- if (is.data.frame(r)) nrow(r) else NA
  cat(sprintf('%-15s %6s\n', nm, n))
}

# show sample flowpath ids
if ('flowpaths' %in% names(res) && is.data.frame(res$flowpaths)) {
  cat('\nSample flowpath ids:', paste(head(res$flowpaths$flowpath_id, 10), collapse=', '), '\n')
}

saveRDS(res, file = file.path(tempdir(), 'hfsubset_stage3.rds'))
cat('\nSaved result to', file.path(tempdir(), 'hfsubset_stage3.rds'), '\n')
