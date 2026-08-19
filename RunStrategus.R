# Run Strategus on the databases configured in config.yml
source("LoadConfiguration.R")

# Code for running Strategus
analysisSpecifications <- ParallelLogger::loadSettingsFromJson(file.path(config$projectRootFolder, config$studySpecificationFileName))
options(sqlRenderTempEmulationSchema = Sys.getenv("DATABRICKS_SCRATCH_SCHEMA"))

for (i in seq_along(databases)) {
  executionSettings <- Strategus::createCdmExecutionSettings(
    workDatabaseSchema = databases[[i]]$cohortDatabaseSchema,
    cdmDatabaseSchema = databases[[i]]$cdmDatabaseSchema,
    cohortTableNames = CohortGenerator::getCohortTableNames(databases[[i]]$cohortTable),
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
