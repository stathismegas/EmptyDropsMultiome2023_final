library(scDblFinder)
library(Seurat)
library(Signac)
library(scater)
# library("optparse")
library(dplyr)
library(ggridges)
library(eulerr)
source("simulations/fcn_for_sim.R")

# read date from user input
# option_list = list(
#   make_option(c("-d", "--date"), type="character", default=NULL,
#               help="date of creation of seurat object aka location of directory", metavar="character")
# );
# opt_parser = OptionParser(option_list=option_list);
# opt = parse_args(opt_parser);
old_date <-  "20230712"  #"20230517"   #"20230329" #opt$date
samples <- c("valentina_8176", "valentina_8177")  #, "valentina_8177")

for (sample in samples){

# create directory
current_date= paste(unlist(strsplit(as.character(Sys.Date()), "-")), collapse="")
downpath <- paste0("data/output/realdata/", old_date, "/", sample, "/downstream_manybad_", current_date)
dir.create(downpath, recursive=TRUE)


fdoublet <- file.path(downpath, "downstream.pdf")
markers_tsv <- file.path(downpath, "markers.tsv")
markers_tsv_in_atac <- file.path(downpath, "markers_in_atac.tsv")
srat_vale_clean <- file.path(downpath, "srat_vale_clean.rds")
srat_atac_vale_clean <- file.path(downpath, "srat_atac_vale_clean.rds")
venns_per_cl <- file.path(downpath, "venns_per_cl.tsv")  
venns_for_kmeans <- file.path(downpath, "venns_for_kmeans.tsv")  

vale <- readRDS( paste0("data/output/realdata/", old_date, "/", sample, "/srat_", sample, ".rds") )
eD.out_multi <- read.table( paste0("data/output/realdata/", old_date, "/", sample,"/",sample, "_eD_multiome.tsv"), sep="\t", header=T) 

sce <- as.SingleCellExperiment(vale)
set.seed(123)
sce.mam.dbl <- scDblFinder(sce, clusters=colData(sce)$ident)
pdf(fdoublet)
print(plotUMAP(sce.mam.dbl, colour_by="scDblFinder.score"))
print(DimPlot(vale, label=T))
vale$scDblFinder.score  <- sce.mam.dbl$scDblFinder.score
t = table(sce.mam.dbl$scDblFinder.class)
print(FeaturePlot(vale, features=c("scDblFinder.score"),  order=T)+ggtitle(paste0("singlets: ", unname(t)[1], "; doublets: ", unname(t)[2]) ) )
print(VlnPlot(vale, features=c("scDblFinder.score"), y.max = 0.10)+stat_summary(fun.y = median, geom='point', size = 2, colour = "blue")+NoLegend()+ggtitle(paste0("singlets: ", unname(t)[1], "; doublets: ", unname(t)[2]) ) )

# remove clusters and doublets
if (sample=="valentina_8176"){
  #bad_clusters = c("3", "21")
#   bad_clusters = c("3", "13", "20", "21", "22")
  # at sanger cluster use
  bad_clusters = c("3", "15", "20", "21", "22")
} else if (sample=="valentina_8177") {
  #bad_clusters = c("7", "17")
  #bad_clusters = c("7", "12", "17")
  #bad_clusters = c("7", "11", "15")
  bad_clusters = c("8", "11", "17")
}
keep_cells <- colnames(vale)[ !(vale$seurat_clusters %in% bad_clusters) & sce.mam.dbl$scDblFinder.class=="singlet" & vale$FRiP>median(vale$FRiP)-mad(vale$FRiP)   ] 
vale_clean <- subset(vale, cells = keep_cells)

plot.new()
rejected_cells = sum( vale$FRiP<median(vale$FRiP)-mad(vale$FRiP) )
text(x=0.2, y=.1, paste0("rejected_cells below 1 MAD less than median FRiP=", rejected_cells))


plot( vale$seurat_clusters[!vale$k_means], xlab="cluster", main="before qc: cells below k_means" )
plot( vale$seurat_clusters , xlab="cluster", main="before qc: total cells" )

# re-preprocess
vale_clean <- SCTransform(vale_clean)
vale_clean <- RunPCA(vale_clean, seed.use=42, features = VariableFeatures(object = vale_clean))
print(ElbowPlot(vale_clean, ndims = 50)     )
vale_clean <- FindNeighbors(vale_clean, dims = 1:50)
vale_clean <- FindClusters(vale_clean, resolution = 1, random.seed = 0)   
vale_clean <- RunUMAP(vale_clean, dims = 1:50, seed.use = 42)

plot( vale_clean$seurat_clusters[!vale_clean$k_means], xlab="cluster", main="after qc: cells below k_means" )
plot( vale_clean$seurat_clusters , xlab="cluster", main="after qc: total cells" )

# create table with number of cells below k-means, before and after qc
venn_df <- data.frame("0" = c( 
                              sum(vale_clean$seurat_clusters=="0"),
                              sum(vale_clean$seurat_clusters[!vale_clean$k_means]=="0")
                              )
                      )
                              

for ( cl in c(1:(max(as.integer(vale_clean$seurat_clusters))-1))   ){
  char_cl = as.character(cl)
  temp_df <- data.frame("new" = c(
                                  sum(vale_clean$seurat_clusters==char_cl),
                                  sum(vale_clean$seurat_clusters[!vale_clean$k_means]==char_cl)
                                 )
                        )

  venn_df <- cbind(venn_df, temp_df)
}
temp_df <- data.frame("new" = c(
                              sum(venn_df[1,]),
                              sum(venn_df[2,])
                             )
                    )
venn_df <- cbind(venn_df, temp_df)
colnames(venn_df) <- as.character(c(c(0:(max(as.integer(vale_clean$seurat_clusters))-1), "Total" ))  )
rownames(venn_df) <- c("number of cells",
                       "number of cells below k-means line"
                       )
write.table(venn_df, venns_for_kmeans, sep = '\t', row.names = T, col.names = T, quote = F)
    

# QC plots
print(DimPlot(vale_clean, label=T, group.by = "seurat_clusters"))
print(VlnPlot(vale_clean,group.by = "seurat_clusters", features="percent.mt")+ stat_summary(fun.y = median, geom='point', size = 2, colour = "blue") )
print(VlnPlot(vale_clean,group.by = "seurat_clusters", features="percent.ribo")+ stat_summary(fun.y = median, geom='point', size = 2, colour = "blue"))
print(VlnPlot(vale_clean,group.by = "seurat_clusters", features="nFeature_RNA")+ stat_summary(fun.y = median, geom='point', size = 2, colour = "blue"))
print(VlnPlot(vale_clean,group.by = "seurat_clusters", features="nCount_RNA")+ stat_summary(fun.y = median, geom='point', size = 2, colour = "blue"))
print(VlnPlot(vale_clean,group.by = "seurat_clusters", features="nCount_ATAC")+ stat_summary(fun.y = median, geom='point', size = 2, colour = "blue"))
print(VlnPlot(vale_clean,group.by = "seurat_clusters", features="nFeature_ATAC")+ stat_summary(fun.y = median, geom='point', size = 2, colour = "blue"))

# FRiP plot per cluster
df_FRiP <- data.frame("frip"=vale_clean$FRiP, "cluster"=vale_clean$seurat_clusters)
max_frip_of_excluded = max(vale_clean$FRiP[vale_clean$excluded_reason==2]  )
print(ggplot(df_FRiP, aes(x = frip, y = cluster, height = stat(density))) + 
        geom_density_ridges(stat = "binline", bins = 80, scale = 0.95, draw_baseline = FALSE)+
        theme_ridges(grid = FALSE, center_axis_labels = TRUE)+
        geom_vline(xintercept = max_frip_of_excluded))

# # gene marker dotplot
# genes_PGC_FGC_FGCmitotic_oogoniaSTRA8 = c("DAZL", "IFITM1", "NANOG", "NANOS3", "POU5F1", "DDX4", "MAEL", "ZGLP1", "STRA8")
# genes_oogoniameiotic_preoocyte_oocyte_prespermatogonia = c( "MEIOC", "SYCP1", "FIGLA", "LHX8", "NOBOX", "GDF9", "ZP3", "DCC")
# DotPlot(srat, dot.scale=3, features = c(genes_PGC_FGC_FGCmitotic_oogoniaSTRA8, genes_oogoniameiotic_preoocyte_oocyte_prespermatogonia), 
#                          assay = "SCT")+
#     theme(
#       # Hide panel borders and remove grid lines
#       panel.border = element_blank(),
#       panel.background = element_rect("white"),
#       panel.grid.major = element_blank(),
#       panel.grid.minor = element_blank(),
#       legend.text=element_text(size=text_size),
#       legend.title = element_text(size=text_size),
#       # Change axis line
#       axis.line = element_line(colour = "black"),
#       axis.text=element_text(size=text_size),
#       axis.title=element_text(size=text_size),
#       axis.text.x = element_text(size=text_size, angle=45, vjust=.8, hjust=0.8)
#     ) + 
#     ylab("clusters")+
#     ggplot2::ggtitle("")+
#     guides(colour = guide_legend(override.aes = list(size=5)))    
    

# UMAP with eD vs cR
# print(DimPlot(vale_clean, group.by = "comparison", sizes.highlight=0.1, reduction = "umap", label=T, cols = c("grey", "blue", "red")) )  #+scale_color_manual(labels = c( "eD", "both", "cR",), values = c("blue", "red"))    )
print(DimPlot(vale_clean, group.by = "comparison", sizes.highlight=0.1, reduction = "umap", label=F, cols = c("grey", "blue", "red")) )  #+scale_color_manual(labels = c( "eD", "both", "cR",), values = c("blue", "red"))    )


# plot venn diagram eD vs cR
listInput <- list(eD = colnames(vale_clean)[vale_clean$comparison %in% c("Emptydrops-multiome", "both")], 
                  cR = colnames(vale_clean)[vale_clean$comparison %in% c("cellRanger-arc"  , "both")]
                  )
overlaps <- euler(listInput, shape = "ellipse")
p2 <- plot(overlaps, 
           quantities = TRUE,
           labels = list(font = 4))
print(p2)

# find markers plot heatmap
eD_all.markers <- FindAllMarkers(vale_clean,  min.pct = 0.25, logfc.threshold = 0.25)
eD_all.markers50 <- eD_all.markers %>%
  group_by(cluster) %>%
  slice_max(n = 50, order_by = avg_log2FC)

eD_all.markers <- eD_all.markers %>%
  group_by(cluster) %>%
  slice_max(n = 5, order_by = avg_log2FC)

write.table(eD_all.markers50,
            markers_tsv,
            sep = '\t', row.names = T, col.names = T, quote = F)

print(DoHeatmap(vale_clean, features = eD_all.markers$gene, size=4,
                angle = 90) + NoLegend()+ theme(axis.text.y = element_text(size = 5))   )

# calculate cR/eD venn diagram by cluster
eD_cells = colnames(vale_clean)[vale_clean$comparison %in% c("Emptydrops-multiome", "both")]
cR_cells = colnames(vale_clean)[vale_clean$comparison %in% c("cellRanger-arc"  , "both")]
venn_df <- data.frame("0" = c(as.integer(sum(vale_clean$seurat_clusters=="0")),
                              as.integer(sum(vale_clean$seurat_clusters=="0" & colnames(vale_clean) %in% eD_cells)),
                              as.integer(sum(vale_clean$seurat_clusters=="0" & colnames(vale_clean) %in% cR_cells)),
                              sum(vale_clean$seurat_clusters=="0" & colnames(vale_clean) %in% cR_cells & colnames(vale_clean) %in% eD_cells),
                              round(sum(vale_clean$seurat_clusters=="0" & colnames(vale_clean) %in% eD_cells)/sum(vale_clean$seurat_clusters=="0"),2),
                              round(sum(vale_clean$seurat_clusters=="0" & colnames(vale_clean) %in% cR_cells)/sum(vale_clean$seurat_clusters=="0"),2),
                              round(sum(vale_clean$seurat_clusters=="0" & colnames(vale_clean) %in% cR_cells & colnames(vale_clean) %in% eD_cells)/sum(vale_clean$seurat_clusters=="0"),2)
))
for ( cl in c(1:(max(as.integer(vale_clean$seurat_clusters))-1))   ){
  char_cl = as.character(cl)
  temp_df <- data.frame("new" = c(sum(vale_clean$seurat_clusters==char_cl),
                                  sum(vale_clean$seurat_clusters==char_cl & colnames(vale_clean) %in% eD_cells),
                                  sum(vale_clean$seurat_clusters==char_cl & colnames(vale_clean) %in% cR_cells),
                                  sum(vale_clean$seurat_clusters==char_cl & colnames(vale_clean) %in% cR_cells & colnames(vale_clean) %in% eD_cells),
                                  round(sum(vale_clean$seurat_clusters==char_cl & colnames(vale_clean) %in% eD_cells)/sum(vale_clean$seurat_clusters==char_cl),2),
                                  round(sum(vale_clean$seurat_clusters==char_cl & colnames(vale_clean) %in% cR_cells)/sum(vale_clean$seurat_clusters==char_cl),2),
                                  round(sum(vale_clean$seurat_clusters==char_cl & colnames(vale_clean) %in% cR_cells & colnames(vale_clean) %in% eD_cells)/sum(vale_clean$seurat_clusters==char_cl),2)
  ))
  venn_df <- cbind(venn_df, temp_df)
}
colnames(venn_df) <- as.character(c(0:(max(as.integer(vale_clean$seurat_clusters))-1) ))
rownames(venn_df) <- c("total cells",
                       "# of eD cells",
                       "# of cR cells",
                       "# of common cells",
                       "% of eD cells",
                       "% of cR cells",
                       "% of common cells"
)
write.table(venn_df, venns_per_cl, sep = '\t', row.names = T, col.names = T, quote = F)
eD_tpr_only <- unname(unlist(venn_df["% of eD cells",])) - unname(unlist(venn_df["% of common cells",]) )
cR_tpr_only <- unname(unlist(venn_df["% of cR cells",])) - unname(unlist(venn_df["% of common cells",]) )
common <- unname(unlist(venn_df["% of common cells",]))

Values <- matrix(c(cR_tpr_only, common, eD_tpr_only), nrow = 3, ncol = max(as.integer(vale_clean$seurat_clusters)), byrow = TRUE)
barplot(Values, main = "eD vs cR by cluster", names.arg = seq(0, max(as.integer(vale_clean$seurat_clusters))-1) , 
        xlab = "cluster", ylab = "fraction", col = c("grey", "pink", "salmon"))
#legend(25, 0.1, lwd=3, col=c("salmon", "pink", "grey"), lty=c(1,1,1), legend=c("EmptyDrops_multiome ", "common", "cellRanger-arc") )
legend("topleft", bg="white", lwd=3, col=c("salmon", "pink", "grey"), lty=c(1,1,1),
       legend=c("EmptyDrops_multiome ", "common", "cellRanger-arc") )



saveRDS(vale_clean, srat_vale_clean)

dev.off()




}
