# This script is used once to initialize your project

is_renv_active <- function() {
  if (requireNamespace("renv", quietly = TRUE)) {
    !is.null(renv::project())
  } else {
    FALSE
  }
}
if (!is_renv_active()) {
  cli::cli_abort("RUN _packageInstall.R and  make sure renv is active")
}

# RUN source("_packageInstall.R") first
cli::cli_alert_info("Setting up rconnect and shared environment variables")

if (!file.exists(".environ_status") & nrow(rsconnect::accounts()) > 0) {
  continue <- TRUE
  if (file.exists(".Renviron") ) {
    continue <- askYesNo("This process will overwite settings in the project's Renviron, continue?")
  }
  
  if (isTRUE(continue)) {
    cli::cli_alert_info("Using jnj rconnect server {rsconnect::accounts()$server[1]}")
    
    pinBoard <- pins::board_connect("rconnect.jnj.com", auth = "auto")
    pinPath <- pins::pin_download(pinBoard, "JGilber2/ohda_shared_renviron")
    
    lines <- readLines(pinPath)
    if (file.exists(".Renviron")) {
      lines <- c(readLines(".Renviron"), lines)
    }
    
    writeLines(unique(lines), ".Renviron")
    
    cli::cli_alert_success("Shared Enviornment variables set. Review the .Renviron file to set your DataBricks credentials, restart your R session and re-run _init.R")
    writeLines("Shared environment set", ".environ_status")
  }
} else if (nrow(rsconnect::accounts()) == 0){
  cli::cli_alert_danger("Please check the readme and setup your JNJ rconnect environment!")
  cli::cli_abort("RCONNECT SETUP NOT COMPLETE")
}

# Make sure Java 8 is used otherwise the DataBricks driver has issues 
# with the arrow library
getJavaVersion <- function() {
  rJava::.jinit()  # Initializes the Java Virtual Machine
  java_version <- rJava::.jcall("java/lang/System", "S", "getProperty", "java.version")
  major_version <- sub("^[^\\.]*\\.([^\\.]+).*", "\\1", java_version)
  return(major_version)
}
javaVersion <- getJavaVersion()
if (javaVersion != "8") {
  cli::cli_abort("JAVA 8 not found! Please set JAVA_HOME in your .Renviron to the JDK8 path (example: 'C:/Program Files/Amazon Corretto/jdk1.8.0_412')")
}

source("LoadConfiguration.R")
res <- testConnection()

if (!res) {
  cli::cli_alert_info("Browsing to databricks url to generate new access token...")
  config <- config::get()
  browseURL(paste0(config$databricksUrl, "settings/user/developer/access-tokens"))
  
  usethis::edit_r_environ("project")
  
  cli::cli_alert_info("To restart: Hit ctrl + shfit + F10 or (command + shift + 0 on mac) then source _init.R again!")
}

# # Get latest CDMs for config.yml ---------------------------------------
#.authWebApi()
# TODO: Replace when databricks works OR is consistent with naming conventions for databases with redshift
# # Get a list of latest CDM versions of data sources
# cdmSources <- ROhdsiWebApi::getCdmSources(baseUrl = webApiUrl) %>%
#   dplyr::filter(!is.na(.data$cdmDatabaseSchema) &
#                   startsWith(.data$sourceKey, "cdm_") &
#                   grepl("\\d{3,}$", .data$sourceKey)) %>%
#   dplyr::mutate(baseUrl = webApiUrl,
#                 dbms = 'redshift',
#                 sourceDialect = 'redshift',
#                 port = 5439,
#                 version = regmatches(.data$sourceKey, regexpr("\\d{3,}$", .data$sourceKey)) %>% as.integer(),
#                 database = regmatches(.data$sourceKey, regexpr(".*(?=_v)", .data$sourceKey, perl=TRUE))) %>%
#   dplyr::group_by(.data$database) %>%
#   dplyr::arrange(dplyr::desc(.data$version)) %>%
#   dplyr::mutate(sequence = dplyr::row_number()) %>%
#   dplyr::ungroup() %>%
#   dplyr::arrange(.data$database, .data$sequence) %>%
#   dplyr::filter(sequence == 1)
#
# # Iterate over the keyring keys to get the latest CDM schema
# latestCdms <- list()
# for(databaseKey in databaseKeyringKeys) {
#   connectionString <- keyring::key_get(databaseKey, keyring = config$keyringName)
#   # HV breaks the conventions a bit so handling it as a one-off
#   if (endsWith(databaseKey, "HealthVerity")) {
#     cdmSchemaRoot <- "cdm_health_verity_cc_ehr_cce"
#   } else {
#     cdmSchemaRoot <- paste0("cdm_", tail(strsplit(connectionString, "/")[[1]], 1), "_v")
#   }
#   cdmDatabaseSchema <- cdmSources[startsWith(cdmSources$cdmDatabaseSchema, cdmSchemaRoot), ]$cdmDatabaseSchema[[1]]
#   configKey <- substr(databaseKey, nchar(config$keyringConnectionStringPrefix)+1, nchar(databaseKey))
#   latestCdms[[configKey]] <- cdmDatabaseSchema
# }
#
# yamlFile <- "config.yml"
# yamlConfig <- readLines(yamlFile)
# findPatternTemplate <- "^    %s:.*$"
# replacementPatternTemplate <- "    %s: %s"
# for (i in seq_along(latestCdms)) {
#   yamlConfig <- gsub(
#     pattern = sprintf(findPatternTemplate, names(latestCdms)[i]),
#     replacement = sprintf(replacementPatternTemplate, names(latestCdms)[i], latestCdms[[i]]),
#     yamlConfig
#   )
# }
# cat(yamlConfig, sep = "\n", file = yamlFile)
