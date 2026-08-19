# Override the config to use the one in the unit test directory
Sys.setenv("R_CONFIG_FILE" = "extras/unitTest/unitTestConfig.yml")

# Run Strategus on the databases configured in config.yml
source("LoadConfiguration.R")

# Code for running Strategus
analysisSpecifications <- ParallelLogger::loadSettingsFromJson(file.path(config$projectRootFolder, config$studySpecificationFileName))
options(sqlRenderTempEmulationSchema = Sys.getenv("DATABRICKS_SCRATCH_SCHEMA"))

for (i in seq_along(databases)) {
  executionSettings <- Strategus::createCdmExecutionSettings(
    workDatabaseSchema = databases[[i]]$cohortDatabaseSchema,
    cdmDatabaseSchema = databases[[i]]$cdmDatabaseSchema,
    cohortTableNames = CohortGenerator::getCohortTableNames(paste0(databases[[i]]$cohortTable, "_sample")),
    workFolder = databases[[i]]$strategusWorkFolder,
    resultsFolder = databases[[i]]$strategusResultsFolder,
    minCellCount = 5
    # IF YOU NEED TO RE-RUN A STUDY BUT ONLY WANT TO 
    # RUN SPECIFIC MODULES, USE modulesToExecute
    # modulesToExecute = c("CohortGeneratorModule", "SelfControlledCaseSeriesModule", etc)
  )

  # Save the execution settings in the results folder
  if (!dir.exists(databases[[i]]$databaseResultsRootFolder)) {
    dir.create(databases[[i]]$databaseResultsRootFolder, recursive = TRUE)
  }
  ParallelLogger::saveSettingsToJson(executionSettings, fileName = file.path(databases[[i]]$databaseResultsRootFolder, "executionSettings.json"))
  
  # Execute the study on the database
  result <- Strategus::execute(
    analysisSpecifications = analysisSpecifications,
    executionSettings = executionSettings,
    connectionDetails = databases[[i]]$connectionDetails
  )
}


# Upload results ---------------------------------------------------------------
analysisSpecifications <- ParallelLogger::loadSettingsFromJson(
  fileName = file.path(config$projectRootFolder,config$studySpecificationFileName)
)

# Setup logging 
ParallelLogger::clearLoggers()
ParallelLogger::addDefaultFileLogger(
  fileName = file.path(config$projectRootFolder, "upload-log.txt"),
  name = "UPLOAD_FILE_LOGGER"
)
ParallelLogger::addDefaultErrorReportLogger(
  fileName = file.path(config$projectRootFolder, 'upload-errorReport.txt'),
  name = "UPLOAD_ERROR_LOGGER"
)

# Connect to the database 
connection <- DatabaseConnector::connect(connectionDetails = resultsDatabaseConnectionDetails)

# Create the schema ------------------------------------------------------------
sql <- "DROP SCHEMA IF EXISTS @schema CASCADE; CREATE SCHEMA @schema;"
sql <- SqlRender::render(sql = sql, schema = config$resultsDatabaseSchema)
DatabaseConnector::executeSql(connection = connection, sql = sql)

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

# Upload Results ---------------------------------------------------------------
for (resultFolder in list.dirs(path = file.path(config$resultFolder, "results"), full.names = T, recursive = F)) {
  
  # only upload databases uncommented in config
  dbsInConfig <- names(config$cdm)
  
  if(basename(resultFolder) %in% dbsInConfig){
    
    message(paste0('Uploading results for ', basename(resultFolder)))
    resultsDataModelSettings <- Strategus::createResultsDataModelSettings(
      resultsDatabaseSchema = config$resultsDatabaseSchema,
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


# Evidence Synthesis
esModuleSettingsCreator <- Strategus::EvidenceSynthesisModule$new()
evidenceSynthesisSourceCm <- esModuleSettingsCreator$createEvidenceSynthesisSource(
  sourceMethod = "CohortMethod",
  likelihoodApproximation = "adaptive grid"
)
metaAnalysisCm <- esModuleSettingsCreator$createBayesianMetaAnalysis(
  evidenceSynthesisAnalysisId = 1,
  alpha = 0.05,
  evidenceSynthesisDescription = "Bayesian random-effects alpha 0.05 - adaptive grid",
  evidenceSynthesisSource = evidenceSynthesisSourceCm
)
evidenceSynthesisSourceSccs <- esModuleSettingsCreator$createEvidenceSynthesisSource(
  sourceMethod = "SelfControlledCaseSeries",
  likelihoodApproximation = "adaptive grid"
)
metaAnalysisSccs <- esModuleSettingsCreator$createBayesianMetaAnalysis(
  evidenceSynthesisAnalysisId = 2,
  alpha = 0.05,
  evidenceSynthesisDescription = "Bayesian random-effects alpha 0.05 - adaptive grid",
  evidenceSynthesisSource = evidenceSynthesisSourceSccs
)
evidenceSynthesisAnalysisList <- list(metaAnalysisCm, metaAnalysisSccs)
evidenceSynthesisAnalysisSpecifications <- esModuleSettingsCreator$createModuleSpecifications(
  evidenceSynthesisAnalysisList
)
esAnalysisSpecifications <- Strategus::createEmptyAnalysisSpecificiations() |>
  Strategus::addModuleSpecifications(evidenceSynthesisAnalysisSpecifications)

ParallelLogger::saveSettingsToJson(
  esAnalysisSpecifications,
  file.path(config$resultFolder, "results", "esAnalysisSpecification.json"))


resultsExecutionSettings <- Strategus::createResultsExecutionSettings(
  resultsDatabaseSchema = config$resultsDatabaseSchema,
  resultsFolder = file.path(config$resultFolder, "results", "evidence_sythesis", "strategusOutput"),
  workFolder = file.path(config$resultFolder, "results", "evidence_sythesis", "strategusWork")
)

Strategus::execute(
  analysisSpecifications = esAnalysisSpecifications,
  executionSettings = resultsExecutionSettings,
  connectionDetails = resultsDatabaseConnectionDetails
)

resultsDataModelSettings <- Strategus::createResultsDataModelSettings(
  resultsDatabaseSchema = config$resultsDatabaseSchema,
  resultsFolder = resultsExecutionSettings$resultsFolder,
)

Strategus::createResultDataModel(
  analysisSpecifications = esAnalysisSpecifications,
  resultsDataModelSettings = resultsDataModelSettings,
  resultsConnectionDetails = resultsDatabaseConnectionDetails
)

Strategus::uploadResults(
  analysisSpecifications = esAnalysisSpecifications,
  resultsDataModelSettings = resultsDataModelSettings,
  resultsConnectionDetails = resultsDatabaseConnectionDetails
)

# Grant read only permissions to all tables ------------------------------------
connection <- DatabaseConnector::connect(
  connectionDetails = resultsDatabaseConnectionDetails
)

configureResultsSchema(
  connection = connection
)

# Disconnect from the database -------------------------------------------------
DatabaseConnector::disconnect(connection)

ParallelLogger::unregisterLogger("UPLOAD_FILE_LOGGER")
ParallelLogger::unregisterLogger("UPLOAD_ERROR_LOGGER")

# Reset the location of the config.yml
Sys.unsetenv("R_CONFIG_FILE")
