args <- (commandArgs(trailingOnly = TRUE))
for (i in 1:length(args)) {
  eval(parse(text = args[[i]]))
}

suppressPackageStartupMessages(library(iCOBRA))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tidyr))
suppressPackageStartupMessages(library(caTools))

print(dataset)
print(filt)

if (filt == "") {
  exts <- filt
} else {
  exts <- paste0("_", filt)
}

## Function to calculate concordance for a matrix mtx. Considering the top
## maxrank variables, returning the number of hits shared by at least a fraction
## frac of the columns of mtx.
calculate_concordance <- function(mtx, maxrank, frac) {
  if (ncol(mtx) > 1) {
    data.frame(t(sapply(1:maxrank, function(i) {
      p <- sum(table(unlist(mtx[1:i, ])) >= frac * ncol(mtx))
      c(k = i, p = p, frac = frac)
    })), stringsAsFactors = FALSE)
  } else {
    NULL
  }
}

get_method <- function(x) sapply(strsplit(x, "\\."), .subset, 1)
get_nsamples <- function(x) sapply(strsplit(x, "\\."), .subset, 2)
get_repl <- function(x) sapply(strsplit(x, "\\."), .subset, 3)

cobratmp <- readRDS(paste0("figures/cobra_data/", dataset, exts, "_cobra.rds"))
pval(cobratmp)[is.na(pval(cobratmp))] <- 1
padj(cobratmp)[is.na(padj(cobratmp))] <- 1

summary_data <- list()

## -------------------------- Concordance plots --------------------------- ##
maxrank <- 1000
minfrac <- 1

pconc <- pval(cobratmp)
## For methods not returning p-values, use adjusted p-values
addm <- setdiff(colnames(padj(cobratmp)), colnames(pconc))
if (length(addm) > 0) {
  pconc <- dplyr::full_join(data.frame(gene = rownames(pconc), pconc),
                            data.frame(gene = rownames(padj(cobratmp)), padj(cobratmp)[, addm]))
  rownames(pconc) <- pconc$gene
  pconc$gene <- NULL
}
## Find ordering of each column
for (i in colnames(pconc)) {
  pconc[, i] <- order(pconc[, i])
}

all_methods <- unique(get_method(colnames(pconc)))
all_nsamples <- unique(get_nsamples(colnames(pconc)))
all_repl <- unique(get_repl(colnames(pconc)))

## Across all instances (all sample sizes, all replicates), for the same method
concvals <- do.call(rbind, lapply(all_methods, function(mth) {
  concval <- calculate_concordance(mtx = pconc[, which(get_method(colnames(pconc)) == mth)], 
                                   maxrank = maxrank, frac = minfrac)
  concval$method <- mth
  concval
}))
summary_data$concordance_fullds <- 
  rbind(summary_data$concordance_fullds, 
        concvals %>% dplyr::mutate(dataset = dataset, filt = filt))

conc_auc <- concvals %>% dplyr::group_by(method) %>% 
  dplyr::summarize(auc = caTools::trapz(c(0, k, k[length(k)]), c(0, p, 0))/(maxrank^2/2)) %>%
  dplyr::mutate(frac = minfrac)
summary_data$concordance_fullds_auc <- 
  rbind(summary_data$concordance_fullds_auc, 
        conc_auc %>% dplyr::mutate(dataset = dataset, filt = filt))

## Across all instances with a given sample size, for the same method
concvals_ss <- do.call(rbind, lapply(all_methods, function(mth) {
  do.call(rbind, lapply(all_nsamples, function(i) {
    concval <- 
      calculate_concordance(mtx = pconc[, intersect(which(get_method(colnames(pconc)) == mth),
                                                    which(get_nsamples(colnames(pconc)) == i)), 
                                        drop = FALSE],
                            maxrank = maxrank, frac = minfrac)
    if (!is.null(concval)) {
      concval$method <- mth
      concval$ncells <- i
      concval
    } else {
      NULL
    }
  }))
}))
concvals_ss$ncells <- factor(concvals_ss$ncells,
                             levels = sort(unique(as.numeric(as.character(concvals_ss$ncells)))))
summary_data$concordance_byncells <- 
  rbind(summary_data$concordance_byncells, 
        concvals_ss %>% dplyr::mutate(dataset = dataset, filt = filt))

conc_auc_ss <- concvals_ss %>% dplyr::group_by(method, ncells) %>% 
  dplyr::summarize(auc = caTools::trapz(c(0, k, k[length(k)]), c(0, p, 0))/(maxrank^2/2)) %>%
  dplyr::mutate(frac = minfrac)
summary_data$concordance_byncells_auc <- 
  rbind(summary_data$concordance_byncells_auc, 
        conc_auc_ss %>% dplyr::mutate(dataset = dataset, filt = filt))

## Between pairwise instances with a given sample size, for the same method
concvals_pairwise <- do.call(rbind, lapply(all_methods, function(mth) {
  do.call(rbind, lapply(all_nsamples, function(i) {
    tmp <- pconc[, intersect(which(get_method(colnames(pconc)) == mth),
                             which(get_nsamples(colnames(pconc)) == i)), drop = FALSE]
    if (ncol(tmp) > 1) {
      concval <- NULL
      for (j1 in 1:(ncol(tmp) - 1)) {
        for (j2 in (j1 + 1):(ncol(tmp))) {
          cv <- calculate_concordance(mtx = tmp[, c(j1, j2)], maxrank = maxrank, frac = minfrac)
          cv$ncells1 <- i
          cv$ncells2 <- i
          cv$replicate1 <- get_repl(colnames(tmp)[j1])
          cv$replicate2 <- get_repl(colnames(tmp)[j2])
          concval <- rbind(concval, cv)
        }
      }
      concval$method <- mth
      concval
    } else {
      NULL
    }
  }))
}))
summary_data$concordance_pairwise <- 
  rbind(summary_data$concordance_pairwise, 
        concvals_pairwise %>% dplyr::mutate(dataset = dataset, filt = filt))

conc_auc_pw <- concvals_pairwise %>% 
  dplyr::group_by(method, ncells1, ncells2, replicate1, replicate2) %>% 
  dplyr::summarize(auc = caTools::trapz(c(0, k, k[length(k)]), c(0, p, 0))/(maxrank^2/2)) %>%
  dplyr::mutate(frac = minfrac)
summary_data$concordance_pairwise_auc <- 
  rbind(summary_data$concordance_pairwise_auc, 
        conc_auc_pw %>% dplyr::mutate(dataset = dataset, filt = filt))

## Between pairs of methods, for a given data set instance (fixed sample size, replicate)
concvals_btwmth <- do.call(rbind, lapply(all_nsamples, function(ss) {
  do.call(rbind, lapply(all_repl, function(i) {
    tmp <- pconc[, intersect(which(get_repl(colnames(pconc)) == i),
                             which(get_nsamples(colnames(pconc)) == ss)), drop = FALSE]
    if (ncol(tmp) > 1) {
      concval <- NULL
      for (j1 in 1:(ncol(tmp) - 1)) {
        for (j2 in (j1 + 1):(ncol(tmp))) {
          cv <- calculate_concordance(mtx = tmp[, c(j1, j2)], maxrank = maxrank, frac = minfrac)
          cv$method1 <- get_method(colnames(tmp)[j1])
          cv$method2 <- get_method(colnames(tmp)[j2])
          concval <- rbind(concval, cv)
        }
      }
      concval$ncells <- ss
      concval$repl <- i
      concval
    } else {
      NULL
    }
  }))
}))
summary_data$concordance_betweenmethods <- 
  rbind(summary_data$concordance_betweenmethods, 
        concvals_btwmth %>% dplyr::mutate(dataset = dataset, filt = filt))

conc_auc_btwmth <- concvals_btwmth %>% 
  dplyr::group_by(method1, method2, ncells, repl) %>% 
  dplyr::summarize(auc = caTools::trapz(c(0, k, k[length(k)]), c(0, p, 0))/(maxrank^2/2)) %>%
  dplyr::mutate(frac = minfrac)
summary_data$concordance_betweenmethods_auc <- 
  rbind(summary_data$concordance_betweenmethods_auc, 
        conc_auc_btwmth %>% dplyr::mutate(dataset = dataset, filt = filt))

saveRDS(summary_data, file = paste0("figures/consistency/", dataset, exts, "_concordances.rds"))

sessionInfo()