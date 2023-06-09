library(Seurat)
library(Signac)
library(DropletUtils)
library(ggplot2)
library(ggridges)
library(mixtools)
library(UpSetR)
library(eulerr)
library(EmptyDropsMultiome)
library(dplyr)
library(EnsDb.Hsapiens.v86)
source("simulations/fcn_for_sim.R")
current_date= paste(unlist(strsplit(as.character(Sys.Date()), "-")), collapse="")
opath <- paste0("data/output/realdata/", current_date)
dir.create(file.path(opath), recursive=TRUE)


ALLFILES <- c(
               "valentina_8176/FCA_GND10288176_raw_feature_bc_matrix.h5",
               "valentina_8177/FCA_GND10288177_raw_feature_bc_matrix.h5"
            )

ALL_BARCODES <- c(
                  "valentina_8176/barcodes.tsv.gz",
                  "valentina_8177/barcodes.tsv.gz"
)


for (i in seq_along(ALLFILES) ) { 

print("now let's do the next sample")
fname = ALLFILES[i]
sce <- Read10X_h5(file.path("data/input", fname))

stub <- sub("/.*", "", fname, "_qc")
cR_barcodes_file <-  gzfile(file.path("data/input", ALL_BARCODES[i] ))

metadata10x <- read.csv(
  file = paste0("data/input/", stub, "/FCA_GND1028",  substring(stub, 11,14), "_per_barcode_metrics.csv"),
  header = TRUE,
  row.names = 1
)

# create sample specific subdirectory
dir.create(file.path(opath, stub), recursive=TRUE)

# define output file names
eD_multi_tsv <- file.path(opath, stub, paste0(stub, "_eD_multiome.tsv")) 
ffile <- file.path(opath, stub, paste0(stub, "_eD_multiome.pdf"))  
markers_tsv <- file.path(opath, stub, paste0(stub, "_cluster_markers.tsv")) 
eD_metadata <- file.path(opath, stub, paste0("eD_metadata_", stub, ".tsv"))  
venns_per_cl <- file.path(opath, stub, paste0("venns_per_cl_", stub, ".tsv"))  
venns_per_cl_pdf <- file.path(opath, stub, paste0("venns_per_cl_", stub, ".pdf"))  
srat_file <- file.path(opath, stub, paste0("srat_", stub, ".rds"))  
print(ffile)
    
# define count matrices
count_matrix_rna <- sce[["Gene Expression"]]
count_matrix_atac <- sce[["Peaks"]]

pdf(ffile)

lower_rna = NULL
barhop_rna = NULL
lower_atac = NULL
barhop_atac = NULL

start_time <- Sys.time()
set.seed(0)
eD.out_multi <- emptydrops_multiome(count_matrix_rna, lower_rna, barhop_rna, count_matrix_atac, lower_atac, barhop_atac )
print("the number of cells detected is: ")
#print(sum(eD.out_multi$FDR_multi<0.001 & ! is.na(eD.out_multi$FDR_multi)))
print(sum(eD.out_multi$FDR<0.001 & ! is.na(eD.out_multi$FDR)))
end_time <- Sys.time()
print(end_time - start_time)

write.table(eD.out_multi,
            paste0(eD_multi_tsv),
            sep = '\t', row.names = T, col.names = T, quote = F)

write.table(eD.out_multi@metadata,
            eD_metadata,
            sep = '\t', row.names = T, col.names = T, quote = F)

cR_cells <- readLines(cR_barcodes_file)

# create srat object
srat <- CreateSeuratObject(counts = count_matrix_rna,
                         meta.data = metadata10x)
srat$FRiP <- srat$atac_peak_region_fragments / srat$atac_fragments * 100

srat[["ATAC"]] <- CreateChromatinAssay(
  counts = count_matrix_atac,
  min.features = -1,
  sep = c(":", "-"),
  genome = "hg38",
  fragments = paste0("data/input/", stub, "/FCA_GND1028",  substring(stub, 11,14), "_atac_fragments.tsv.gz") ,
  #  annotation = genomeAnnotation$chromSizes,
  validate.fragments = FALSE
)

#srat$FDR_multi <- eD.out_multi[colnames(srat),]$FDR_multi
srat$FDR <- eD.out_multi[colnames(srat),]$FDR
srat$k_means <- eD.out_multi[colnames(srat),]$k_means
srat$FDR <- eD.out_multi[colnames(srat),]$FDR


# compute nucleosome signal score per cell
DefaultAssay(srat) <- "ATAC"
srat <- NucleosomeSignal(object = srat)

# extract gene annotations from EnsDb
annotations <- GetGRangesFromEnsDb(ensdb = EnsDb.Hsapiens.v86)

# change to UCSC style
seqlevelsStyle(annotations) <- 'UCSC'

# add the gene information to the object
Annotation(srat) <- annotations

# compute TSS enrichment score per cell
#srat <- TSSEnrichment(object = srat, fast = FALSE)

DefaultAssay(srat) <- "RNA"

#eD_cells <- eD.out_multi$Row.names[ eD.out_multi$FDR_multi<0.001 & ! is.na(eD.out_multi$FDR_multi) ]
eD_cells <- eD.out_multi$Row.names[ eD.out_multi$FDR<0.001 & ! is.na(eD.out_multi$FDR) ]
eD_rna_cells <- eD.out_multi$Row.names[ eD.out_multi$FDR_RNA<0.001 & ! is.na(eD.out_multi$FDR_RNA) ]
    
listInput <- list(eD = eD_cells, 
                  cR = cR_cells,
                  eDrna =eD_rna_cells
                  )
p1 <- upset(fromList(listInput), nsets = 6,, order.by = "freq")
overlaps <- euler(listInput, shape = "ellipse")
p2 <- plot(overlaps, 
           quantities = TRUE,
           labels = list(font = 4))
print(p1)
print(p2)

listInput <- list(eD = eD_cells, 
                  cR = cR_cells
                  )
p1 <- upset(fromList(listInput), nsets = 6,, order.by = "freq")
overlaps <- euler(listInput, shape = "ellipse")
p2 <- plot(overlaps, 
           quantities = TRUE,
           labels = list(font = 4))
print(p1)
print(p2)



# make umap
union_cells <- union(eD_cells, cR_cells)
eD_minus_cR <- setdiff(eD_cells, cR_cells)
cR_minus_eD <- setdiff(cR_cells, eD_cells )
intersection <- intersect(eD_cells, cR_cells)
srat_subset <- subset(srat, cells=union_cells )
DefaultAssay(srat_subset) <- "RNA"

# calculate QC metrics: mito and ribo contents and FRiP
FRiP <- srat$atac_peak_region_fragments / srat$atac_fragments * 100

# add ribo and mito metadata
C <- srat_subset@assays[["RNA"]]
rb.genes <- rownames(C)[grep("^RP[SL]",rownames(C))]
percent.ribo <- colSums(C[rb.genes,])/Matrix::colSums(C)*100
srat_subset <- AddMetaData(srat_subset, percent.ribo, col.name = "percent.ribo")
srat_subset[["percent.mt"]] <- PercentageFeatureSet(srat_subset, pattern = "^MT-")
mito_lim <- median(srat_subset[["percent.mt"]][,1]) + 3* mad(srat_subset[["percent.mt"]][,1])

# subset the srat
srat_subset <- subset(x = srat_subset, subset = percent.mt < mito_lim)
srat_subset <- SCTransform(srat_subset)
srat_subset <- RunPCA(srat_subset, seed.use=42, features = VariableFeatures(object = srat_subset))
#print(ElbowPlot(srat_subset, ndims = 50)     )
srat_subset <- FindNeighbors(srat_subset, dims = 1:50)
srat_subset <- FindClusters(srat_subset, resolution = 2, random.seed = 0)
srat_subset <- RunUMAP(srat_subset, dims = 1:50, seed.use = 42)


srat_subset$comparison <- 1
srat_subset$comparison[ colnames(srat_subset) %in% eD_minus_cR] <- "Emptydrops-multiome"
srat_subset$comparison[ colnames(srat_subset) %in% intersection] <- "both"
srat_subset$comparison[ colnames(srat_subset) %in% cR_minus_eD] <- "cellRanger-arc"

  
saveRDS(srat_subset, srat_file)


# calculate cR/eD venn diagram by cluster
venn_df <- data.frame("0" = c(as.integer(sum(srat_subset$seurat_clusters=="0")),
                              as.integer(sum(srat_subset$seurat_clusters=="0" & colnames(srat_subset) %in% eD_cells)),
                              as.integer(sum(srat_subset$seurat_clusters=="0" & colnames(srat_subset) %in% cR_cells)),
                              sum(srat_subset$seurat_clusters=="0" & colnames(srat_subset) %in% cR_cells & colnames(srat_subset) %in% eD_cells),
                              sum(srat_subset$seurat_clusters=="0" & colnames(srat_subset) %in% eD_cells)/sum(srat_subset$seurat_clusters=="0"),
                              sum(srat_subset$seurat_clusters=="0" & colnames(srat_subset) %in% cR_cells)/sum(srat_subset$seurat_clusters=="0"),
                              sum(srat_subset$seurat_clusters=="0" & colnames(srat_subset) %in% cR_cells & colnames(srat_subset) %in% eD_cells)/sum(srat_subset$seurat_clusters=="0")
                                  ))
for ( cl in c(1:(max(as.integer(srat_subset$seurat_clusters))-1))   ){
  char_cl = as.character(cl)
  temp_df <- data.frame("new" = c(sum(srat_subset$seurat_clusters==char_cl),
                                           sum(srat_subset$seurat_clusters==char_cl & colnames(srat_subset) %in% eD_cells),
                                           sum(srat_subset$seurat_clusters==char_cl & colnames(srat_subset) %in% cR_cells),
                                           sum(srat_subset$seurat_clusters==char_cl & colnames(srat_subset) %in% cR_cells & colnames(srat_subset) %in% eD_cells),
                                           round(sum(srat_subset$seurat_clusters==char_cl & colnames(srat_subset) %in% eD_cells)/sum(srat_subset$seurat_clusters==char_cl),1),
                                           round(sum(srat_subset$seurat_clusters==char_cl & colnames(srat_subset) %in% cR_cells)/sum(srat_subset$seurat_clusters==char_cl),1),
                                           round(sum(srat_subset$seurat_clusters==char_cl & colnames(srat_subset) %in% cR_cells & colnames(srat_subset) %in% eD_cells)/sum(srat_subset$seurat_clusters==char_cl),1)
  ))
  venn_df <- cbind(venn_df, temp_df)
}
colnames(venn_df) <- as.character(c(0:(max(as.integer(srat_subset$seurat_clusters))-1) ))
rownames(venn_df) <- c("total cells",
                       "# of eD cells",
                       "# of cR cells",
                       "# of common cells",
                       "% of eD cells",
                       "% of cR cells",
                       "% of common cells"
)
write.table(venn_df, venns_per_cl, sep = '\t', row.names = T, col.names = T, quote = F)

 
dev.off()





}

