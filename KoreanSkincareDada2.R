# Install bioconductor controller, BiocManager
#if (!requireNamespace("BiocManager", quietly = TRUE))
#  install.packages("BiocManager")

#Install dada2 from bioconductor
#BiocManager::install(version = "3.15")
#BiocManager::install("dada2", version = "3.15")


# Load dada2 and check the version
library("dada2"); packageVersion("dada2")

# Make a variable that lists all the files in the KoreanSkincareTrimmedReads_g folder and then list them.
path <- "/cloud/project/KoreanSkincareTrimmedReads_g" # using option g right now
list.files(path)


# Forward and reverse fastq filenames end in _1.fastq.gz and _2.fastq.gz
fnFs <- sort(list.files(path, pattern="_1.fastq.gz", full.names = TRUE))
fnRs <- sort(list.files(path, pattern="_2.fastq.gz", full.names = TRUE))
# Changed 1 (tutorial value) to 2 to extract the info after the first underscore
# Extract sample names, assuming filenames start with Trimmed_SAMPLENAME
sample.names <- sapply(strsplit(basename(fnFs), "_"), `[`, 2)

# Plot quality profile of fastq files
plotQualityProfile(fnFs[1])
plotQualityProfile(fnRs[1])

# Place filtered files in filtered/ subdirectory
filtFs <- file.path(path, "filtered", paste0(sample.names, "_F_filt.fastq.gz"))
filtRs <- file.path(path, "filtered", paste0(sample.names, "_R_filt.fastq.gz"))

# Assign sample names to the column names of the filtered data
names(filtFs) <- sample.names
names(filtRs) <- sample.names

# Trim reads
# Updated truncLen based on how our reads look post trimming
# Trying to keep as many reads as possible while cutting off the very bad ones
out <- filterAndTrim(fnFs, filtFs, fnRs, filtRs, truncLen=c(275,230),
                     maxN=0, maxEE=c(2,2), truncQ=2, rm.phix=TRUE,
                     compress=TRUE, multithread=FALSE) # On Windows set multithread=FALSE
head(out)

# These are test files to check error file and read file to get error in each read
errF <- learnErrors(filtFs, multithread=FALSE)
errR <- learnErrors(filtRs, multithread=FALSE)

# Plot the errors
plotErrors(errF, nominalQ=TRUE)

# Actually run dada
dadaFs <- dada(filtFs, err=errF, multithread=FALSE)
dadaRs <- dada(filtRs, err=errR, multithread=FALSE)
dadaFs[[1]]

# Perform quality control and trimming of the reads
mergers <- mergePairs(dadaFs, filtFs, dadaRs, filtRs, verbose=TRUE)
# Inspect the merger data.frame from the first sample
head(mergers[[1]])

# Change the dataframe to a sequence table and print dimensions
seqtab <- makeSequenceTable(mergers)
dim(seqtab)

# Inspect distribution of sequence lengths
table(nchar(getSequences(seqtab)))

# Remove bimera and print dimensions
seqtab.nochim <- removeBimeraDenovo(seqtab, method="consensus", multithread=FALSE, verbose=TRUE)
dim(seqtab.nochim)

sum(seqtab.nochim)/sum(seqtab)

# Return number of sequences in file
getN <- function(x) sum(getUniques(x))

# Make table of number of reads before and after processing
track <- cbind(out, sapply(dadaFs, getN), sapply(dadaRs, getN), sapply(mergers, getN), rowSums(seqtab.nochim))

# Name columns
colnames(track) <- c("input", "filtered", "denoisedF", "denoisedR", "merged", "nonchim")
rownames(track) <- sample.names
head(track)


# Now begin Part 2 (Assigning taxonomy)

# Need to upload the silva_nr_v132_train_set.fa.gz file into the KoreanSkincareTrimmedReads_g folder
# Assign taxonomy using SILVA database
taxa <- assignTaxonomy(seqtab.nochim, "/cloud/project/KoreanSkincareTrimmedReads_g/silva_nr_v132_train_set.fa.gz", multithread=FALSE)

# Optional addition
# Need to upload silva_species_assignment_v132.fa.gz file into the KoreanSkincareTrimmedReads_g folder
taxa <- addSpecies(taxa, "/cloud/project/KoreanSkincareTrimmedReads_g/silva_species_assignment_v132.fa.gz")

# Create new datafrom from old one
taxa.print <- taxa 
# Remove row names
rownames(taxa.print) <- NULL
# Display new dataframe to print
head(taxa.print)

# Just to see what we're working with
rownames(seqtab.nochim)

# Load packages
library(phyloseq); packageVersion("phyloseq")
library(Biostrings); packageVersion("Biostrings")
library(ggplot2); packageVersion("ggplot2")

# Setting black/white color theme
theme_set(theme_bw())

# Code that extracts subject, gender, day and time (early/late) from sample names
metadata <- read.table(file = 'Metadata.txt', sep = ',', header = TRUE)
View(metadata)

# This makes a new metadata file that contains week as a column name since our metadata file doesn't explicitly list week
# This step is not required for most metadata files
samples.out <- rownames(seqtab.nochim)
subject <- substr(metadata$Submitter_Id, 6,8)
week <- substr(metadata$Submitter_Id, 4,4)
samdf <- data.frame(Subject = subject, Week = week)
rownames(samdf) <- samples.out


# Setting phyloseq object
# otu_table is seqtab.nochim
# sample_data is metadata
# tax_table is taxa
ps_data <- phyloseq(otu_table(seqtab.nochim, taxa_are_rows=FALSE), sample_data(samdf), 
                    tax_table(taxa))


# Plotting alpha diversity
# Use phyloseq object "ps_data"
# Set x to the variable we are interested in (week)
# Chose to only do Simpson and Shannon plots 
plot_richness(ps_data, x="Week", color="Week", measures=c("Simpson", "Shannon")) +
  guides(color = "none") +
  theme(axis.text.x = element_text(angle = 0))

# Bar plot
# x = Week
top20 <- names(sort(taxa_sums(ps_data), decreasing=TRUE))[1:20]
ps.top20 <- transform_sample_counts(ps_data, function(OTU) OTU/sum(OTU))
ps.top20 <- prune_taxa(top20, ps.top20)
plot_bar(ps.top20, x = "Week", fill="Family")
