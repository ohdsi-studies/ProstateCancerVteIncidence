# Run Strategus on the databases configured in config.yml
source("LoadConfiguration.R")

# Code for running Strategus
analysisSpecifications <- ParallelLogger::loadSettingsFromJson(file.path(config$projectRootFolder, config$studySpecificationFileName))

connectionDetails <- Eunomia::getEunomiaConnectionDetails()


# Create and save execution settings ----------------------------------------------------
strategusInternalsRootFolder <- file.path(config$resultFolder, "strategusInternals", "Eunomia")
strategusWorkFolder <- file.path(strategusInternalsRootFolder, "strategusWork")
strategusExecutionFolder = file.path(strategusInternalsRootFolder, "strategusExecution")
databaseResultsRootFolder <- file.path(config$resultFolder, "results", "Eunomia")
strategusResultsFolder = file.path(databaseResultsRootFolder, "strategusResults")

executionSettings <- Strategus::createCdmExecutionSettings(
  workDatabaseSchema = "main",
  cdmDatabaseSchema = "main",
  cohortTableNames = CohortGenerator::getCohortTableNames("strategus_test"),
  workFolder = strategusWorkFolder,
  resultsFolder = strategusResultsFolder,
  minCellCount = 1
  # IF YOU NEED TO RE-RUN A STUDY BUT ONLY WANT TO 
  # RUN SPECIFIC MODULES, USE modulesToExecute
  # modulesToExecute = c("CohortGeneratorModule", "SelfControlledCaseSeriesModule", etc)
)
  
# Save the execution settings in the results folder
if (!dir.exists(databaseResultsRootFolder)) {
  dir.create(databaseResultsRootFolder, recursive = TRUE)
}
ParallelLogger::saveSettingsToJson(executionSettings, fileName = file.path(databaseResultsRootFolder, "executionSettings.json"))
 

result <- Strategus::execute(
  analysisSpecifications = analysisSpecifications,
  executionSettings = executionSettings,
  connectionDetails = connectionDetails
)

