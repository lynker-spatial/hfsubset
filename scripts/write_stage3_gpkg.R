library(devtools)

devtools::load_all('.')

p <- '/Users/mikejohnson/hydrofabric/v3.0/ls-modeling-fabric.gpkg'
outfile <- file.path('outputs','hfsubset_nwis-01017290.gpkg')
cat('Writing subset to', outfile, '\n')
res <- hfsubset(src = p,
                hl_reference = 'nwis-01017290',
                lyrs = c('flowpaths','divides','nexus','network','hydrolocations','pois'),
                outfile = outfile,
                verbose = TRUE)
cat('Done. Wrote:', outfile, '\n')
