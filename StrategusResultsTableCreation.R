# Code for creating the result schema and tables in a (Postgres) database
library(dplyr)
source("LoadConfiguration.R")

analysisSpecifications <- ParallelLogger::loadSettingsFromJson(
  fileName = file.path(config$projectRootFolder,config$studySpecificationFileName)
)

# Setup logging ----------------------------------------------------------------
ParallelLogger::clearLoggers()
ParallelLogger::addDefaultFileLogger(
  fileName = file.path(config$resultFolder, "results-schema-setup-log.txt"),
  name = "RESULTS_SCHEMA_SETUP_FILE_LOGGER"
)
ParallelLogger::addDefaultErrorReportLogger(
  fileName = file.path(config$resultFolder, 'results-schema-setup-errorReport.txt'),
  name = "RESULTS_SCHEMA_SETUP_ERROR_LOGGER"
)

# Connect to the database ------------------------------------------------------
connection <- DatabaseConnector::connect(connectionDetails = resultsDatabaseConnectionDetails)

# Create the schema ------------------------------------------------------------
tryCatch(
  expr = {
    sql <- "CREATE SCHEMA @schema;"
    sql <- SqlRender::render(sql = sql, schema = config$resultsDatabaseSchema)
    DatabaseConnector::executeSql(connection = connection, sql = sql)
  }, 
  error = function(e) {
    errorMsg <- paste0(
      e,
      "\n----------------------------------------------\n",
      "A schema with results already exists!\n",
      "----------------------------------------------\n",
      "Do you want to drop this schema and recreate all tables?\nNOTE: This will remove all previous results that have been uploaded.\n"
    )
    message(errorMsg)
    switch(
      menu(
        choices = c(
          no = "Stop this process and preserve the results schema and all tables.",
          yes = "Recreate results schema and tables which will remove all results."
        ),
        title = "How would you like to proceed?"
      ) + 1,
      cat("Nothing done\n"),
      no = {
        cli::cli_inform("Stopping this script.")
        DatabaseConnector::disconnect(connection = connection)
      }
      ,
      yes = {
        sql <- "DROP SCHEMA IF EXISTS @schema CASCADE; CREATE SCHEMA @schema;"
        sql <- SqlRender::render(sql = sql, schema = config$resultsDatabaseSchema)
        DatabaseConnector::executeSql(connection = connection, sql = sql)
      }
    )
  }  
)

resultsFolder <- list.dirs(path = file.path(config$resultFolder,"results"), full.names = T, recursive = F)[1]
resultsDataModelSettings <- Strategus::createResultsDataModelSettings(
  resultsDatabaseSchema = config$resultsDatabaseSchema,
  resultsFolder = file.path(resultsFolder, "strategusResults")
)

Strategus::createResultDataModel(
  analysisSpecifications = analysisSpecifications,
  resultsDataModelSettings = resultsDataModelSettings,
  resultsConnectionDetails = resultsDatabaseConnectionDetails
)

# Unregister loggers -----------------------------------------------------------
ParallelLogger::unregisterLogger("RESULTS_SCHEMA_SETUP_FILE_LOGGER")
ParallelLogger::unregisterLogger("RESULTS_SCHEMA_SETUP_ERROR_LOGGER")