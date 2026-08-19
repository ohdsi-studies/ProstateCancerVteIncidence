config <- config::get()

# Get latest CDMs for config.yml ---------------------------------------
webApiUrl <- config$webApiUrl
ROhdsiWebApi::authorizeWebApi(
  baseUrl = webApiUrl,
  authMethod = "windows"
)

# Get the Spark (DataBricks) sources configured in ATLAS
cdmSources <- ROhdsiWebApi::getCdmSources(baseUrl = webApiUrl) |>
  dplyr::filter(sourceDialect == 'spark') |>
  dplyr::mutate(
    cdmDatabaseName = sub("\\..*", "", cdmDatabaseSchema),
    cdmDatabaseSchemaOnly =  sub("^[^.]*\\.", "", cdmDatabaseSchema),
    cdmDatabaseSchemaRoot = sub(".*\\.(.*)_v\\d+$", "\\1", cdmDatabaseSchema),
    cdmVersion = as.integer(sub(".*_v(\\d+)$", "\\1", cdmDatabaseSchema))
  ) 

# Iterate over the values found in the config.yml 
# and use the information found in the version string
# to see if any updates are required
latestCdms <- list()
for (i in seq_along(config$cdm)) {
  cdmName <- names(config$cdm)[i]
  cdmSchema <- config$cdm[[i]]
  cdmSchemaWithoutVersion <- sub("_v\\d+$", "", cdmSchema)
  print(cdmName)
  
  latestCdm <- cdmSources |>
    dplyr::filter(cdmDatabaseSchemaRoot == cdmSchemaWithoutVersion) |>
    dplyr::filter(cdmVersion == max(cdmVersion))
 
  if (nrow(latestCdm) != 1) {
    stop("ERROR: Multiple rows found - can't figure out the latest CDM version.")
  } else {
    latestCdms[[cdmName]] <- latestCdm$cdmDatabaseSchemaOnly
  }
}


yamlFile <- "config.yml"
yamlConfig <- readLines(yamlFile)
findPatternTemplate <- "^    %s:.*$"
replacementPatternTemplate <- "    %s: %s"
for (i in seq_along(latestCdms)) {
  yamlConfig <- gsub(
    pattern = sprintf(findPatternTemplate, names(latestCdms)[i]), 
    replacement = sprintf(replacementPatternTemplate, names(latestCdms)[i], latestCdms[[i]]),
    yamlConfig
  )
}
cat(yamlConfig, sep = "\n", file = yamlFile)