library(dplyr)
library(igraph)
p <- '/Users/mikejohnson/hydrofabric/v3.0/ls-modeling-fabric.gpkg'

o <- sf::st_read(p, query = 'SELECT flowpath_id, vpuid, flowline_id FROM network WHERE hl_reference = "nwis-01017290"', quiet=TRUE)
cat('origin_fp:', o$flowpath_id, '  origin_vpu:', o$vpuid, '  origin_flowline_id:', o$flowline_id, '\n')

vpu_ids <- sf::st_read(p, query = paste0('SELECT flowpath_id, divide_id, flowpath_toid, flowline_id, flowline_toid FROM network WHERE vpuid = "', o$vpuid, '"'), quiet=TRUE)
cat('vpu_ids rows:', nrow(vpu_ids), '\n')
cat('vpu_ids NAs in flowpath_toid:', sum(is.na(vpu_ids$flowpath_toid)), '\n')
cat('vpu_ids NAs in flowline_toid:', sum(is.na(vpu_ids$flowline_toid)), '\n')

nex_fp <- sf::st_read(p, query = paste0('SELECT nexus_id, nexus_toid FROM nexus WHERE vpuid = "', o$vpuid, '"'), quiet=TRUE)
cat('nex_fp rows:', nrow(nex_fp), '\n')
cat('nex_fp NAs in nexus_toid:', sum(is.na(nex_fp$nexus_toid)), '\n')

# fp->nex->fp graph
fp_nex_edges <- vpu_ids |> filter(!is.na(flowpath_toid)) |> select(from=flowpath_id, to=flowpath_toid)
nex_fp_edges <- nex_fp |>
  dplyr::filter(!is.na(nexus_toid)) |>
  select(from=nexus_id, to=nexus_toid)
all_edges <- bind_rows(fp_nex_edges, nex_fp_edges)
cat('total fp->nex->fp edges:', nrow(all_edges), '\n')

g_fp <- graph_from_data_frame(all_edges, directed=TRUE)
up_fp <- as_ids(subcomponent(g_fp, as.character(o$flowpath_id), mode='in'))
fp_up_fp <- up_fp[startsWith(up_fp, 'fp-')]
cat('upstream fp nodes (fp->nex->fp graph):', length(fp_up_fp), '\n')

# flowline_id graph (scratch code approach)
fl_edges <- vpu_ids |>
  filter(!is.na(flowline_toid)) |>
  select(from=flowline_id, to=flowline_toid)
cat('flowline edges:', nrow(fl_edges), '\n')
g_fl <- graph_from_data_frame(fl_edges, directed=TRUE)
up_fl <- as_ids(subcomponent(g_fl, as.character(o$flowline_id), mode='in'))
fl_ids_upstream <- as.integer(up_fl[!is.na(suppressWarnings(as.integer(up_fl)))])
fp_up_fl <- vpu_ids |> filter(flowline_id %in% fl_ids_upstream) |> pull(flowpath_id)
cat('upstream fp nodes (flowline graph):', length(fp_up_fl), '\n')

# Check: does origin_fp appear in nex_fp$nexus_toid?
cat('\nIs origin_fp in nexus_toid?', o$flowpath_id %in% nex_fp$nexus_toid, '\n')
# What nexus points to origin_fp?
feeder <- nex_fp[nex_fp$nexus_toid == o$flowpath_id, ]
cat('Nexus that feeds origin_fp:', paste(feeder$nexus_id, collapse=', '), '\n')

# How many fps drain to that feeder nexus?
feeder_nex_id <- feeder$nexus_id[1]
fps_to_feeder <- vpu_ids[vpu_ids$flowpath_toid == feeder_nex_id, ]
cat('FPs draining to feeder nexus (', feeder_nex_id, '):', nrow(fps_to_feeder), '\n')

# What does origin_fp drain to?
origin_toid <- vpu_ids[vpu_ids$flowpath_id == o$flowpath_id, "flowpath_toid"]
cat('origin_fp drains to:', origin_toid$flowpath_toid, '\n')

# Full subcomponent report
cat('\nAll nodes upstream of origin_fp:\n')
print(up_fp)

# Check if nex_fp edges connect correctly - what are nex-6679 predecessors?
cat('\nWhat fp-ids have flowpath_toid == feeder nexus?\n')
cat(paste(fps_to_feeder$flowpath_id, collapse=', '), '\n')
