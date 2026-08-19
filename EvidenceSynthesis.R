library(Strategus)

source("LoadConfiguration.R")

resultsDatabaseSchema <- config$resultsDatabaseSchema
# Specify the connection to the results database
resultsConnectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = 'postgresql',
  user = Sys.getenv("OHDA_RESULTS_USER"),
  password = Sys.getenv("OHDA_RESULTS_PASSWORD"),
  server = Sys.getenv("OHDA_RESULTS_SERVER")
)
esModuleSettingsCreator <- EvidenceSynthesisModule$new()
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
  resultsDatabaseSchema = resultsDatabaseSchema,
  resultsFolder = file.path(config$resultFolder, "results", "evidence_sythesis", "strategusOutput"),
  workFolder = file.path(config$resultFolder, "results", "evidence_sythesis", "strategusWork")
)

Strategus::execute(
  analysisSpecifications = esAnalysisSpecifications,
  executionSettings = resultsExecutionSettings,
  connectionDetails = resultsConnectionDetails
)

resultsDataModelSettings <- Strategus::createResultsDataModelSettings(
  resultsDatabaseSchema = resultsDatabaseSchema,
  resultsFolder = resultsExecutionSettings$resultsFolder,
)

Strategus::createResultDataModel(
  analysisSpecifications = esAnalysisSpecifications,
  resultsDataModelSettings = resultsDataModelSettings,
  resultsConnectionDetails = resultsConnectionDetails
)

Strategus::uploadResults(
  analysisSpecifications = esAnalysisSpecifications,
  resultsDataModelSettings = resultsDataModelSettings,
  resultsConnectionDetails = resultsConnectionDetails
)

# Grant read only permissions to all tables ------------------------------------
connection <- DatabaseConnector::connect(
  connectionDetails = resultsConnectionDetails
)

configureResultsSchema(
  connection = connection
)

# Disconnect from the database -------------------------------------------------
DatabaseConnector::disconnect(connection)