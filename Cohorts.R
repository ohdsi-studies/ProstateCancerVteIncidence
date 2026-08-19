# Code to extract relevant cohorts, save them as a set, and generate them
source("LoadConfiguration.R")

# Extract from WebApi and save to file -----------------------------------------
cohortIds <- config$cohorts$cohortIds

.authWebApi()
cohortDefinitionSet <- ROhdsiWebApi::exportCohortDefinitionSet(
  baseUrl = config$webApiUrl,
  cohortIds = cohortIds,
  generateStats = TRUE
)
if (!dir.exists(file.path(config$projectRootFolder, "cohorts"))) {
  dir.create(
    path = file.path(config$projectRootFolder, "cohorts"),
    showWarnings = FALSE,
    recursive = TRUE
  )
}

CohortGenerator::saveCohortDefinitionSet(
  cohortDefinitionSet = cohortDefinitionSet,
  settingsFileName = file.path(config$projectRootFolder, "cohorts/inst/Cohorts.csv"),
  jsonFolder = file.path(config$projectRootFolder, "cohorts/inst/cohorts"),
  sqlFolder = file.path(config$projectRootFolder, "cohorts/inst/sql/sql_server"),
  subsetJsonFolder = file.path(config$projectRootFolder, "cohorts/inst/cohort_subset_definitions")
)

# Generate Cohorts--------------------------------------------------------------
cohortDefinitionSet <- CohortGenerator::getCohortDefinitionSet(
  settingsFileName = file.path(config$projectRootFolder, "cohorts/inst/Cohorts.csv"),
  jsonFolder = file.path(config$projectRootFolder, "cohorts/inst/cohorts"),
  sqlFolder = file.path(config$projectRootFolder, "cohorts/inst/sql/sql_server"),
  subsetJsonFolder = file.path(config$projectRootFolder, "cohorts/inst/cohort_subset_definitions")  
)

for (i in seq_along(databases)) {
  database <- databases[[i]]
  message(sprintf("Creating cohorts for %s", database$databaseId))
  connection <- do.call(what = DatabaseConnector::connect,
                        args = database$connectionDetailsList)
  cohortTableNames <- CohortGenerator::getCohortTableNames(database$cohortTable)
  CohortGenerator::createCohortTables(
    connection = connection,
    cohortDatabaseSchema = database$cohortDatabaseSchema,
    cohortTableNames = cohortTableNames, 
    incremental = T
  )
  CohortGenerator::generateCohortSet(
    connection = connection,
    cdmDatabaseSchema = database$cdmDatabaseSchema,
    cohortDatabaseSchema = database$cohortDatabaseSchema,
    cohortTableNames = cohortTableNames,
    cohortDefinitionSet = cohortDefinitionSet,
    incremental = TRUE,
    incrementalFolder = file.path(config$resultFolder, "cohorts", database$databaseId)
  )
  DatabaseConnector::disconnect(connection)
}