library(dplyr)
p   <- '/Users/mikejohnson/hydrofabric/v3.0/ls-modeling-fabric.gpkg'
out <- 'outputs/hfsubset_nwis-01017290.gpkg'

# output divides
div_out <- sf::st_read(out, 'divides', quiet = TRUE)
cat('output divides cols:', paste(names(div_out), collapse=', '), '\n')
cat('nrow:', nrow(div_out), '\n')
cat('divide_id sample:', paste(head(div_out$divide_id, 6), collapse=', '), '\n')
cat('flowpath_id sample:', paste(head(div_out$flowpath_id, 6), collapse=', '), '\n')

# source divides - get divide_id and flowpath_id for counterpart lookup
fp_ids <- unique(na.omit(div_out$flowpath_id))
cat('\nfp_ids type:', class(fp_ids), ' sample:', paste(head(fp_ids, 4), collapse=', '), '\n')

src_div <- sf::st_read(p, query = paste0(
  "SELECT divide_id, flowpath_id FROM divides WHERE flowpath_id IN (",
  paste(sprintf("'%s'", fp_ids), collapse=","),
  ")"
), quiet = TRUE)
cat('src divides rows:', nrow(src_div), '\n')
cat('src divide_id sample:', paste(head(src_div$divide_id, 6), collapse=', '), '\n')
cat('src flowpath_id sample:', paste(head(src_div$flowpath_id, 6), collapse=', '), '\n')

# cross-check: out flowpath_id vs out divide_id vs src divide_id
joined <- left_join(
  sf::st_drop_geometry(div_out)[, c("divide_id", "flowpath_id")],
  sf::st_drop_geometry(src_div)[, c("divide_id", "flowpath_id")],
  by = "flowpath_id", suffix = c("_out", "_src")
)
mismatches <- filter(joined, divide_id_out != divide_id_src)
cat('\nMismatched divide_id (out vs src) for same flowpath_id:', nrow(mismatches), '\n')
if (nrow(mismatches) > 0) print(mismatches)
