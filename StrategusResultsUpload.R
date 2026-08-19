# Code for uploading results to a (Postgres) database

# By default we set bulk load off as there will be an error
# if this is TRUE but POSTGRES_PATH is not set
Sys.setenv("DATABASE_CONNECTOR_BULK_UPLOAD" = FALSE)
# However, if you want to use bulk uploading, activate these settings
# by uncommenting lines 9 and 10 plus provide the proper path to
# the PostgreSQL bin folder on line 10
#Sys.setenv("DATABASE_CONNECTOR_BULK_UPLOAD" = TRUE)
#Sys.setenv("POSTGRES_PATH" = "D:/Program Files/PostgreSQL/13/bin")

library(dplyr)
source("LoadConfiguration.R")
# Code for uploading results to a Postgres database
resultsDatabaseSchema <- config$resultsDatabaseSchema
analysisSpecifications <- ParallelLogger::loadSettingsFromJson(
  fileName = file.path(config$projectRootFolder,config$studySpecificationFileName)
)
resultsDatabaseConnectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = 'postgresql',
  user = Sys.getenv("OHDA_RESULTS_USER"),
  password = Sys.getenv("OHDA_RESULTS_PASSWORD"),
  server = Sys.getenv("OHDA_RESULTS_SERVER")
)

# Setup logging ----------------------------------------------------------------
ParallelLogger::clearLoggers()
ParallelLogger::addDefaultFileLogger(
  fileName = "upload-log.txt",
  name = "RESULTS_FILE_LOGGER"
)
ParallelLogger::addDefaultErrorReportLogger(
  fileName = "upload-errorReport.txt",
  name = "RESULTS_ERROR_LOGGER"
)

# Upload Results ---------------------------------------------------------------
for (resultFolder in list.dirs(path = file.path(config$resultFolder, "results"), full.names = T, recursive = F)) {
  
  # only upload databases uncommented in config
  dbsInConfig <- names(config$cdm)
  
  if(basename(resultFolder) %in% dbsInConfig){
  
    message(paste0('Uploading results for ', basename(resultFolder)))
  resultsDataModelSettings <- Strategus::createResultsDataModelSettings(
    resultsDatabaseSchema = resultsDatabaseSchema,
    resultsFolder = file.path(resultFolder, "strategusResults"),
  )

  Strategus::uploadResults(
    analysisSpecifications = analysisSpecifications,
    resultsDataModelSettings = resultsDataModelSettings,
    resultsConnectionDetails = resultsDatabaseConnectionDetails
  )
  } else{
    warning(paste0('Found results for ', basename(resultFolder), ' but not in config so ignoring from upload'))
  }
  
  
}

# Grant read only permissions to all tables ------------------------------------
connection <- DatabaseConnector::connect(
  connectionDetails = resultsDatabaseConnectionDetails
)

configureResultsSchema(
  connection = connection
)

# Disconnect from the database -------------------------------------------------
DatabaseConnector::disconnect(connection)

# Unregister loggers -----------------------------------------------------------
ParallelLogger::unregisterLogger("RESULTS_FILE_LOGGER")
ParallelLogger::unregisterLogger("RESULTS_ERROR_LOGGER")