########################################################
# Load the configuration - DO NOT MODIFY ---------------
########################################################
# Load the study configuration
source("LoadConfiguration.R")

.authWebApi()
library(dplyr)
dbDiagnosticsResultsFolder <- file.path(config$resultFolder, "results", "dbDiagnostics")

########################################################
# Above the line - MODIFY ------------------------------
########################################################

# Define the target/comparator/indication/outcome concept
# sets. This script will then generate all combinations
# for running diagnostics. The only one that is required
# to use is the targetConceptSets. If you do not need
# a comparator, indication, outcome, just leave it as 
# c() to avoid problems in the script
targetConceptSets <- c(
  3560 # ACE Inhibitors
)
comparatorConceptSets <- c(
  3623 # Alpha-1 Blocker
)
indicationConceptSets <- c(
  5794 # Hypertension
)
outcomeConceptSets <- c(
  377 # MI
)

# See createDataDiagnosticsSettings in DbDiagnostics package for more details
# on these settings: 
# https://ohdsi.github.io/DbDiagnostics/reference/createDataDiagnosticsSettings.html
minAge <- 0
maxAge <- NULL
genderConceptIds <- c(8507,8532) #male and female
raceConceptIds <- NULL
ethnicityConceptIds <- NULL
studyStartDate <- "20000101" # YYYYMMDD, e.g. "2001-02-01" for January 1st, 2001
studyEndDate <- "20231231" # YYYYMMDD
requiredDurationDays = 365
requiredDomains = c("condition","drug")
desiredDomains = NULL
requiredVisits = NULL
desiredVisits = NULL

########################################################
# Below the line - DO NOT MODIFY -----------------------
########################################################

# Don't change below this line (unless you know what you're doing) -------------

if (length(targetConceptSets) <= 0) {
  stop("You must specify at least 1 target concept set to proceed")
}

# Get the list of unique concept set IDs and resolve them
# against WebAPI to get the concept set names and list of
# concept IDs
uniqueConceptSetIds <- unique(
  c(
    targetConceptSets,
    comparatorConceptSets,
    indicationConceptSets,
    outcomeConceptSets
  )
)

dfConceptSetDetails <- data.frame()
for (i in 1:length(uniqueConceptSetIds)) {
  message("Retrieving concept set ID: ", uniqueConceptSetIds[i])
  conceptSet <- ROhdsiWebApi::getConceptSetDefinition(
    conceptSetId = uniqueConceptSetIds[i],
    baseUrl = config$webApiUrl
  )
  conceptIds <- ROhdsiWebApi::resolveConceptSet(
    conceptSetDefinition = conceptSet, 
    baseUrl = config$webApiUrl
  )
  dfConceptSetDetails <- rbind(dfConceptSetDetails,
                               data.frame(
                                 conceptSetId = conceptSet$id,
                                 conceptSetName = conceptSet$name,
                                 conceptSetConceptIds = conceptIds
                               ))
}


# Get all of the combinations of T/C/I/O -------------
# Ensure that all of the vectors have at least 1 entry
# before trying to make the combos
comparatorConceptSetsForExpansion <- ifelse(
  length(comparatorConceptSets) > 0, 
  comparatorConceptSets, 
  c(0)
)
indicationConceptSetsForExpansion <- ifelse(
  length(indicationConceptSets) > 0, 
  indicationConceptSets, 
  c(0)
)
outcomeConceptSetsForExpansion <- ifelse(
  length(outcomeConceptSets) > 0, 
  outcomeConceptSets, 
  c(0)
)
analysesForEvaluation <- expand.grid(
  targetConceptSetId = targetConceptSets,
  comparatorConceptSetId = comparatorConceptSetsForExpansion,
  indicationConceptSetId = indicationConceptSetsForExpansion,
  outcomeConceptSetId = outcomeConceptSetsForExpansion
) 

# Create the analysis list 
dataDiagnosticsSettingsList <- list()

.getConceptSetName <- function(df, selectedConceptSetId) {
  if (selectedConceptSetId == 0) {
    conceptSetName <- "<NA>"
  } else {
    conceptSetName <- df %>%
      filter(conceptSetId == selectedConceptSetId) %>%
      distinct(conceptSetName) %>%
      pull(conceptSetName)
  }
  conceptSetName
}

.getConceptIds <- function(df, selectedConceptSetId) {
  if (selectedConceptSetId == 0) {
    return(NULL)
  } else {
    conceptIds <- df %>%
      filter(conceptSetId == selectedConceptSetId) %>%
      pull(conceptSetConceptIds)
  }
}

for (i in 1:nrow(analysesForEvaluation)) {
  # Get the current T/C/I/O information
  targetId <- analysesForEvaluation[i,]$targetConceptSetId
  comparatorId <- analysesForEvaluation[i,]$comparatorConceptSetId
  indicationId <- analysesForEvaluation[i,]$indicationConceptSetId
  outcomeId <- analysesForEvaluation[i,]$outcomeConceptSetId
  
  targetName <- .getConceptSetName(dfConceptSetDetails, targetId)
  comparatorName <- .getConceptSetName(dfConceptSetDetails, comparatorId)
  indicationName <- .getConceptSetName(dfConceptSetDetails, indicationId)
  outcomeName <- .getConceptSetName(dfConceptSetDetails, outcomeId)
  
  targetConceptIds <- .getConceptIds(dfConceptSetDetails, targetId)
  comparatorConceptIds <- .getConceptIds(dfConceptSetDetails, comparatorId)
  indicationConceptIds <- .getConceptIds(dfConceptSetDetails, indicationId)
  outcomeConceptIds <- .getConceptIds(dfConceptSetDetails, outcomeId)
  
  analysisName <- sprintf(
    "A%s: T: %s vs C: %s with I: %s for O: %s", 
    i, 
    targetName,
    comparatorName,
    indicationName,
    outcomeName
  )
  #print(analysisName)
  
  dataDiagnosticsSettingsList[[length(dataDiagnosticsSettingsList) + 1]] <- DbDiagnostics::createDataDiagnosticsSettings(
    analysisId = i,
    analysisName = analysisName,
    minAge = minAge,
    maxAge = maxAge,
    genderConceptIds = genderConceptIds,
    raceConceptIds = raceConceptIds,
    ethnicityConceptIds = ethnicityConceptIds,
    studyStartDate = studyStartDate,
    studyEndDate = studyEndDate,
    requiredDurationDays = requiredDurationDays,
    requiredDomains = requiredDomains,
    desiredDomains = desiredDomains,
    requiredVisits = requiredVisits,
    desiredVisits = desiredVisits,
    targetName = targetName,
    targetConceptIds = targetConceptIds,
    comparatorName = comparatorName,
    comparatorConceptIds = comparatorConceptIds,
    indicationName = indicationName,
    indicationConceptIds = indicationConceptIds,
    outcomeName = outcomeName,
    outcomeConceptIds = outcomeConceptIds
  )
}

dbDiagnosticResults <- DbDiagnostics::executeDbDiagnostics(
  connectionDetails = dbProfileConnectionDetails,
  resultsDatabaseSchema = config$databaseDiagnostics$dpResultsDatabaseSchema,
  resultsTableName = config$databaseDiagnostics$dpResultsTableName,
  outputFolder = dbDiagnosticsResultsFolder,
  dataDiagnosticsSettingsList = dataDiagnosticsSettingsList
)