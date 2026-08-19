# Always use renv in your projects for audit trails and reproducibility!

if (!"renv" %in% as.data.frame(installed.packages())$Package)
  install.packages("renv")

if (!"reticulate" %in% as.data.frame(installed.packages())$Package) {
  install.packages("reticulate")
  reticulate::install_miniconda()
}


renv::restore(prompt=FALSE)
