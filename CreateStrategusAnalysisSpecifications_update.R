########################################################
# Load the configuration - DO NOT MODIFY ---------------
########################################################
# Load the study configuration
source("LoadConfiguration.R")
library(Strategus)
library(tibble)

########################################################
# Above the line - MODIFY ------------------------------
########################################################

tcis <- list(
  list(
    targetId = c(5081, 5089, 5090, 5092, 5098, 5085),
    comparatorId = 5082,
    # indicationId = 10629, # Uncomment if needed
    genderConceptIds = c(8507, 8532),
    minAge = NULL,
    maxAge = NULL
    # excludedCovariateConceptIds = c()
  )
)

outcomes <- tibble::tibble(
  cohortId = c(5086,5087,5088), # VTE
  cleanWindow = c(99999,99999,99999)
)
negativeConceptSetId <- 257 

covariateConceptsToExcludeId <- 7149 # ASSURE concepts to exclude from LSPS that indicate administration and visits
#we did not have this line in the original analysis

# Time-at-risks (TARs) for the outcomes of interest in your study
timeAtRisks <- tibble::tibble(
  label = c("On treatment","fixed 180d","fixed365d","all-avail"),
  riskWindowStart  = c(1,1,1,1),
  startAnchor = c("cohort start","cohort start","cohort start","cohort start"),
  riskWindowEnd  = c(0, 180,365,99999),
  endAnchor = c("cohort end","cohort start","cohort start","cohort start")
)
# Try to avoid intent-to-treat TARs for SCCS, or then at least disable calendar time spline:
sccsTimeAtRisks <- tibble::tibble(
  label = c("On treatment"),
  riskWindowStart  = c(1),
  startAnchor = c("cohort start"),
  riskWindowEnd  = c(0),
  endAnchor = c("cohort end")
)

plpTimeAtRisks <- tibble::tibble(
  riskWindowStart  = c(1),
  startAnchor = c("cohort start"),
  riskWindowEnd  = c(365),
  endAnchor = c("cohort start"),
)

# If you are not restricting your study to a specific time window, 
# please make these strings empty
#saba updated the dates to match dates available in medicaid (found on rhealth)
studyStartDate <- "20060101" #YYYYMMDD
studyEndDate <- "20241231"   #YYYYMMDD
# Some of the settings require study dates with hyphens
studyStartDateWithHyphens <- gsub("(\\d{4})(\\d{2})(\\d{2})", "\\1-\\2-\\3", studyStartDate)
studyEndDateWithHyphens <- gsub("(\\d{4})(\\d{2})(\\d{2})", "\\1-\\2-\\3", studyEndDate)

# Probably don't change below this line ----------------------------------------


# Consider these settings for estimation  ----------------------------------------

useCleanWindowForPriorOutcomeLookback <- TRUE # If FALSE, lookback window is all time prior, i.e., including only first events
psMatchMaxRatio <- 100 # If bigger than 1, the outcome model will be conditioned on the matched set
cmMaxCohortSizeForFitting <- 250000 # Downsampled example study to 10000
cmMaxCovBalanceCohortSize <- cmMaxCohortSizeForFitting # Used for covariate balance
sccsMaxCasesPerOutcome <- 100000 # Mostly used to limit computation for negative controls. 

# Consider these settings for patient-level prediction  ----------------------------------------
plpMaxSampleSize <- 1000000 # Downsampled example study to 20000

########################################################
# Below the line - DO NOT MODIFY -----------------------
########################################################

# Don't change below this line (unless you know what you're doing) -------------

# Shared Resources -------------------------------------------------------------

.authWebApi()
cohortDefinitionSet <- ROhdsiWebApi::exportCohortDefinitionSet(
  cohortIds =  unique(
    c(
      outcomes$cohortId,
      unlist(sapply(tcis, function(x) c(x$targetId, x$comparatorId, x$indicationId)))
    )
  ),
  generateStats = TRUE,
  baseUrl = config$webApiUrl
)
if (!is.null(negativeConceptSetId)) {
  negativeControlOutcomeCohortSet <- ROhdsiWebApi::getConceptSetDefinition(
    conceptSetId = negativeConceptSetId,
    baseUrl = config$webApiUrl
  ) |>
    ROhdsiWebApi::resolveConceptSet(
      baseUrl = config$webApiUrl
    ) |>
    ROhdsiWebApi::getConcepts(
      baseUrl = config$webApiUrl
    ) |>
    dplyr::rename(outcomeConceptId = "conceptId",
           cohortName = "conceptName") |>
    dplyr::mutate(cohortId = dplyr::row_number() + 1000)
}
if (!is.null(covariateConceptsToExcludeId)) {
  covariateConceptsToExclude <- ROhdsiWebApi::getConceptSetDefinition(
    conceptSetId = covariateConceptsToExcludeId,
    baseUrl = config$webApiUrl
  ) |>
    ROhdsiWebApi::resolveConceptSet(
      baseUrl = config$webApiUrl
    ) |>
    ROhdsiWebApi::getConcepts(
      baseUrl = config$webApiUrl
    ) |>
    dplyr::pull("conceptId")
} else {
  covariateConceptsToExclude <- c()
}

# Get the unique subset criteria from the tcis
# object to construct the cohortDefintionSet's 
# subset definitions for each target/comparator
# cohort
dfUniqueTcis <- data.frame()
for (i in seq_along(tcis)) {
  dfUniqueTcis <- rbind(dfUniqueTcis, data.frame(cohortId = tcis[[i]]$targetId,
                                                 indicationId = paste(tcis[[i]]$indicationId, collapse = ","),
                                                 genderConceptIds = paste(tcis[[i]]$genderConceptIds, collapse = ","),
                                                 minAge = paste(tcis[[i]]$minAge, collapse = ","),
                                                 maxAge = paste(tcis[[i]]$maxAge, collapse = ",")
  ))
  if (!is.null(tcis[[i]]$comparatorId)) {
    dfUniqueTcis <- rbind(dfUniqueTcis, data.frame(cohortId = tcis[[i]]$comparatorId,
                                                   indicationId = paste(tcis[[i]]$indicationId, collapse = ","),
                                                   genderConceptIds = paste(tcis[[i]]$genderConceptIds, collapse = ","),
                                                   minAge = paste(tcis[[i]]$minAge, collapse = ","),
                                                   maxAge = paste(tcis[[i]]$maxAge, collapse = ",")
    ))
  }
}

dfUniqueTcis <- unique(dfUniqueTcis)
dfUniqueTcis$subsetDefinitionId <- 0 # Adding as a placeholder for loop below
dfUniqueSubsetCriteria <- unique(dfUniqueTcis[,-1])

for (i in seq_len(nrow(dfUniqueSubsetCriteria))) {
  uniqueSubsetCriteria <- dfUniqueSubsetCriteria[i,]
  dfCurrentTcis <- dfUniqueTcis[dfUniqueTcis$indicationId == uniqueSubsetCriteria$indicationId &
                                  dfUniqueTcis$genderConceptIds == uniqueSubsetCriteria$genderConceptIds &
                                  dfUniqueTcis$minAge == uniqueSubsetCriteria$minAge & 
                                  dfUniqueTcis$maxAge == uniqueSubsetCriteria$maxAge,]
  targetCohortIdsForSubsetCriteria <- as.integer(dfCurrentTcis[, "cohortId"])
  dfUniqueTcis[dfUniqueTcis$indicationId == dfCurrentTcis$indicationId &
                 dfUniqueTcis$genderConceptIds == dfCurrentTcis$genderConceptIds &
                 dfUniqueTcis$minAge == dfCurrentTcis$minAge & 
                 dfUniqueTcis$maxAge == dfCurrentTcis$maxAge,]$subsetDefinitionId <- i
  
  subsetOperators <- list()
  
  # Indication restrict (always first if there is an indication)
  indicationName <- ""
  if (uniqueSubsetCriteria$indicationId != "") {
    subsetOperators[[length(subsetOperators) + 1]] <- CohortGenerator::createCohortSubset(
      cohortIds = uniqueSubsetCriteria$indicationId,
      negate = FALSE,
      cohortCombinationOperator = "all",
      startWindow = CohortGenerator::createSubsetCohortWindow(-99999, 0, "cohortStart"),
      endWindow = CohortGenerator::createSubsetCohortWindow(0, 99999, "cohortStart")
    )
    # saving name for the cohort subset name
    indicationName <- cohortDefinitionSet$cohortName[cohortDefinitionSet$cohortId == uniqueSubsetCriteria$indicationId]
  }
  
  # Always first restrict for CM/PLP - also if running annual IRs need to change limitTo = 'firstEver' to 'all'
  subsetOperators[[length(subsetOperators) + 1]] <- CohortGenerator::createLimitSubset(
    priorTime = 365,
    followUpTime = 1,
    limitTo = "firstEver"
  )
  
  # Demo settings
  demoName <- ""
  if (uniqueSubsetCriteria$genderConceptIds != "" ||
      uniqueSubsetCriteria$minAge != "" ||
      uniqueSubsetCriteria$maxAge != "") {
    subsetOperators[[length(subsetOperators) + 1]] <- CohortGenerator::createDemographicSubset(
      ageMin = if(uniqueSubsetCriteria$minAge == "") 0 else as.integer(uniqueSubsetCriteria$minAge),
      ageMax = if(uniqueSubsetCriteria$maxAge == "") 99999 else as.integer(uniqueSubsetCriteria$maxAge),
      gender = if(uniqueSubsetCriteria$genderConceptIds == "") NULL else as.integer(strsplit(uniqueSubsetCriteria$genderConceptIds, ",")[[1]])
    )
    
    if(uniqueSubsetCriteria$genderConceptIds != ""){
      # could map to name but for now doing code to make it generalizable
      demoName <- paste0(" gender ",uniqueSubsetCriteria$genderConceptIds)
    }
    if(uniqueSubsetCriteria$minAge != "" & uniqueSubsetCriteria$maxAge == ""){
      # check the >= is true
      demoName <- paste0(demoName, ' age >= ', uniqueSubsetCriteria$minAge)
    }
    if(uniqueSubsetCriteria$minAge == "" & uniqueSubsetCriteria$maxAge != ""){
      # check the >= is true
      demoName <- paste0(demoName, ' age <= ', uniqueSubsetCriteria$maxAge)
    }
    if(uniqueSubsetCriteria$minAge != "" & uniqueSubsetCriteria$maxAge != ""){
      # check the <= is true
      demoName <- paste0(demoName, ' ', uniqueSubsetCriteria$minAge, ' <= age <= ', uniqueSubsetCriteria$maxAge)
    }

  }
  
  # Time settings
  timeName <- ""
  if (studyStartDate != "" || studyEndDate != "") {
    subsetOperators[[length(subsetOperators) + 1]] <- CohortGenerator::createLimitSubset(
      calendarStartDate = if (studyStartDate == "") NULL else as.Date(studyStartDate, "%Y%m%d"),
      calendarEndDate = if (studyEndDate == "") NULL else as.Date(studyEndDate, "%Y%m%d")
    )
    
    if(studyStartDate != ""){
      timeName <- paste0(" from ", studyStartDate)
    }
    if(studyEndDate != ""){
      timeName <- paste0(timeName, " until ", studyEndDate)
    }
    
  }
  # add the indication/demo/year subset for the targets with this subset
  subsetDef <- CohortGenerator::createCohortSubsetDefinition(
    name = paste0("first time ",ifelse(indicationName == '', '', 'in '), indicationName, demoName, timeName),
    subsetCohortNameTemplate = "@baseCohortName - @subsetDefinitionName",
    definitionId = i,
    subsetOperators = subsetOperators
  )
  cohortDefinitionSet <- cohortDefinitionSet |>
    CohortGenerator::addCohortSubsetDefinition(
      cohortSubsetDefintion = subsetDef,
      targetCohortIds = targetCohortIdsForSubsetCriteria
    ) 
  
  # add the indication cohort without the indication subset
  if (uniqueSubsetCriteria$indicationId != "") {
    # Also create restricted version of indication cohort:
    subsetDef <- CohortGenerator::createCohortSubsetDefinition(
      #name = "restricted",
      name = paste0("first time ", demoName, timeName),
      subsetCohortNameTemplate = "@baseCohortName - @subsetDefinitionName",
      definitionId = i + 100,
      subsetOperators = subsetOperators[2:length(subsetOperators)] # indic removed
    )
    cohortDefinitionSet <- cohortDefinitionSet |>
      CohortGenerator::addCohortSubsetDefinition(
        cohortSubsetDefintion = subsetDef,
        targetCohortIds = as.integer(uniqueSubsetCriteria$indicationId)
      )
  }  
}

if (any(duplicated(cohortDefinitionSet$cohortId, negativeControlOutcomeCohortSet$cohortId))) {
  stop("*** Error: duplicate cohort IDs found ***")
}

# CohortGeneratorModule Settings --------------------------------------------------------
cgModuleSettingsCreator <- CohortGeneratorModule$new()
cohortDefinitionShared <- cgModuleSettingsCreator$createCohortSharedResourceSpecifications(cohortDefinitionSet)
negativeControlsShared <- cgModuleSettingsCreator$createNegativeControlOutcomeCohortSharedResourceSpecifications(
  negativeControlOutcomeCohortSet = negativeControlOutcomeCohortSet,
  occurrenceType = "first",
  detectOnDescendants = TRUE
)
cohortGeneratorModuleSpecifications <- cgModuleSettingsCreator$createModuleSpecifications(
  generateStats = TRUE
)

# CohortDiagnosticsModule Settings ---------------------------------------------
cdModuleSettingsCreator <- CohortDiagnosticsModule$new()
cohortDiagnosticsModuleSpecifications <- cdModuleSettingsCreator$createModuleSpecifications(
  cohortIds = cohortDefinitionSet$cohortId,
  runInclusionStatistics = TRUE,
  runIncludedSourceConcepts = TRUE,
  runOrphanConcepts = TRUE,
  runTimeSeries = FALSE,
  runVisitContext = TRUE,
  runBreakdownIndexEvents = TRUE,
  runIncidenceRate = TRUE,
  runCohortRelationship = TRUE,
  runTemporalCohortCharacterization = TRUE,
  minCharacterizationMean = 0.01
)

# CharacterizationModule Settings ---------------------------------------------
cModuleSettingsCreator <- CharacterizationModule$new()
allCohortIdsExceptOutcomes <- cohortDefinitionSet |>
  dplyr::filter(!cohortId %in% outcomes$cohortId) |>
  dplyr::pull(cohortId)

characterizationModuleSpecifications <- cModuleSettingsCreator$createModuleSpecifications(
  targetIds = allCohortIdsExceptOutcomes,
  outcomeIds = outcomes$cohortId,
  outcomeWashoutDays = outcomes$cleanWindow,
  dechallengeStopInterval = 30,
  dechallengeEvaluationWindow = 30,
  riskWindowStart = timeAtRisks$riskWindowStart,
  startAnchor = timeAtRisks$startAnchor,
  riskWindowEnd = timeAtRisks$riskWindowEnd,
  endAnchor = timeAtRisks$endAnchor,
  minCharacterizationMean = 0.01,
  casePreTargetDuration = 365,
  casePostOutcomeDuration = 365,
  minPriorObservation = 365, 
  covariateSettings = FeatureExtraction::createCovariateSettings( useDemographicsGender = T,
                                                                  useDemographicsAge = T,
                                                                  useDemographicsAgeGroup = T,
                                                                  useDemographicsRace = T,
                                                                  useDemographicsEthnicity = T,
                                                                  useDemographicsIndexYear = T,
                                                                  useDemographicsIndexMonth = T,
                                                                  useDemographicsTimeInCohort = T,
                                                                  useDemographicsPriorObservationTime = T,
                                                                  useDemographicsPostObservationTime = T,
                                                                  useConditionGroupEraLongTerm = T,
                                                                  useDrugGroupEraOverlapping = T,
                                                                  useDrugGroupEraLongTerm = T,
                                                                  useProcedureOccurrenceLongTerm = T,
                                                                  useMeasurementLongTerm = T,
                                                                  useObservationLongTerm = T,
                                                                  useDeviceExposureLongTerm = T,
                                                                  useVisitConceptCountLongTerm = T,
                                                                  useConditionGroupEraShortTerm = T,
                                                                  useDrugGroupEraShortTerm = T,
                                                                  useProcedureOccurrenceShortTerm = T,
                                                                  useMeasurementShortTerm = T,
                                                                  useObservationShortTerm = T,
                                                                  useDeviceExposureShortTerm = T,
                                                                  useVisitConceptCountShortTerm = T,
                                                                  endDays = 0,
                                                                  longTermStartDays = -365,
                                                                  shortTermStartDays = -30,
                                                                  useCharlsonIndex = T, 
                                                                  useDcsi = T, 
                                                                  useChads2 = T, 
                                                                  useChads2Vasc = T)
)

# CohortIncidenceModule Settings --------------------------------------------------------
ciModuleSettingsCreator <- CohortIncidenceModule$new()
exposureIndicationIds <- cohortDefinitionSet |>
  dplyr::filter(!cohortId %in% outcomes$cohortId & isSubset) |>
  dplyr::pull(cohortId)
targetList <- lapply(
  exposureIndicationIds,
  function(cohortId) {
    CohortIncidence::createCohortRef(
      id = cohortId, 
      name = cohortDefinitionSet$cohortName[cohortDefinitionSet$cohortId == cohortId]
    )
  }
)
outcomeList <- lapply(
  seq_len(nrow(outcomes)),
  function(i) {
    CohortIncidence::createOutcomeDef(
      id = i, 
      name = cohortDefinitionSet$cohortName[cohortDefinitionSet$cohortId == outcomes$cohortId[i]], 
      cohortId = outcomes$cohortId[i], 
      cleanWindow = outcomes$cleanWindow[i]
    )
  }
)

tars <- list()
for (i in seq_len(nrow(timeAtRisks))) {
  tars[[i]] <- CohortIncidence::createTimeAtRiskDef(
    id = i, 
    startWith = gsub("cohort ", "", timeAtRisks$startAnchor[i]), 
    endWith = gsub("cohort ", "", timeAtRisks$endAnchor[i]), 
    startOffset = timeAtRisks$riskWindowStart[i],
    endOffset = timeAtRisks$riskWindowEnd[i]
  )
}
analysis1 <- CohortIncidence::createIncidenceAnalysis(
  targets = exposureIndicationIds,
  outcomes = seq_len(nrow(outcomes)),
  tars = seq_along(tars)
)
irStudyWindow <- CohortIncidence::createDateRange(
  startDate = studyStartDateWithHyphens,
  endDate = studyEndDateWithHyphens
)
irDesign <- CohortIncidence::createIncidenceDesign(
  targetDefs = targetList,
  outcomeDefs = outcomeList,
  tars = tars,
  analysisList = list(analysis1),
  studyWindow = irStudyWindow,
  strataSettings = CohortIncidence::createStrataSettings(
    byYear = TRUE,
    byGender = TRUE,
    byAge = TRUE,
    ageBreaks = seq(0, 110, by = 10)
  )
)
cohortIncidenceModuleSpecifications <- ciModuleSettingsCreator$createModuleSpecifications(
  irDesign = irDesign$toList()
)


# CohortMethodModule Settings -----------------------------------------------------------
cmModuleSettingsCreator <- CohortMethodModule$new()
covariateSettings <- FeatureExtraction::createDefaultCovariateSettings(
  addDescendantsToExclude = TRUE # Keep TRUE because you're excluding concepts
)

# code below errors if same outcome with different cleanWindows - should we enable?
outcomeList <- append(
  lapply(seq_len(nrow(outcomes)), function(i) {
    if (useCleanWindowForPriorOutcomeLookback)
      priorOutcomeLookback <- outcomes$cleanWindow[i]
    else
      priorOutcomeLookback <- 99999
    CohortMethod::createOutcome(
      outcomeId = outcomes$cohortId[i],
      outcomeOfInterest = TRUE,
      trueEffectSize = NA,
      priorOutcomeLookback = priorOutcomeLookback
    )
  }),
  lapply(negativeControlOutcomeCohortSet$cohortId, function(i) {
    CohortMethod::createOutcome(
      outcomeId = i,
      outcomeOfInterest = FALSE,
      trueEffectSize = 1
    )
  })
)
# removing any duplicates
outcomeList <- unique(outcomeList)

targetComparatorOutcomesList <- list()
for (i in seq_along(tcis)) {
  tci <- tcis[[i]]
  # Get the subset definition ID that matches
  # the target ID. The comparator will also use the same subset
  # definition ID
  currentSubsetDefinitionId <- dfUniqueTcis |>
    dplyr::filter(cohortId == tci$targetId &
             indicationId == paste(tci$indicationId, collapse = ",") &
             genderConceptIds == paste(tci$genderConceptIds, collapse = ",") &
             minAge == paste(tci$minAge, collapse = ",") &
             maxAge == paste(tci$maxAge, collapse = ",")) |>
    dplyr::pull(subsetDefinitionId)
  targetId <- cohortDefinitionSet |>
    dplyr::filter(subsetParent == tci$targetId & subsetDefinitionId == currentSubsetDefinitionId) |>
    dplyr::pull(cohortId)
  comparatorId <- cohortDefinitionSet |>
    dplyr::filter(subsetParent == tci$comparatorId & subsetDefinitionId == currentSubsetDefinitionId) |>
    dplyr::pull(cohortId)
  targetComparatorOutcomesList[[i]] <- CohortMethod::createTargetComparatorOutcomes(
    targetId = targetId,
    comparatorId = comparatorId,
    outcomes = outcomeList,
    excludedCovariateConceptIds = c(tci$excludedCovariateConceptIds, covariateConceptsToExclude)
  )
}
getDbCohortMethodDataArgs <- CohortMethod::createGetDbCohortMethodDataArgs(
  restrictToCommonPeriod = TRUE,
  studyStartDate = studyStartDate,
  studyEndDate = studyEndDate,
  maxCohortSize = 0,
  covariateSettings = covariateSettings
)
createPsArgs = CohortMethod::createCreatePsArgs(
  maxCohortSizeForFitting = cmMaxCohortSizeForFitting,
  errorOnHighCorrelation = TRUE,
  stopOnError = FALSE, # Setting to FALSE to allow Strategus complete all CM operations; when we cannot fit a model, the equipoise diagnostic should fail
  estimator = "att",
  prior = Cyclops::createPrior(
    priorType = "laplace", 
    exclude = c(0), 
    useCrossValidation = TRUE
  ),
  control = Cyclops::createControl(
    noiseLevel = "silent", 
    cvType = "auto", 
    seed = 1, 
    resetCoefficients = TRUE, 
    tolerance = 2e-07, 
    cvRepetitions = 1, 
    startingVariance = 0.01
  )
)
matchOnPsArgs = CohortMethod::createMatchOnPsArgs(
  maxRatio = psMatchMaxRatio,
  caliper = 0.2,
  caliperScale = "standardized logit",
  allowReverseMatch = FALSE,
  stratificationColumns = c()
)
# stratifyByPsArgs <- CohortMethod::createStratifyByPsArgs(
#   numberOfStrata = 5,
#   stratificationColumns = c(),
#   baseSelection = "all"
# )
computeSharedCovariateBalanceArgs = CohortMethod::createComputeCovariateBalanceArgs(
  maxCohortSize = cmMaxCovBalanceCohortSize,
  covariateFilter = NULL
)
computeCovariateBalanceArgs = CohortMethod::createComputeCovariateBalanceArgs(
  maxCohortSize = cmMaxCovBalanceCohortSize,
  covariateFilter = FeatureExtraction::getDefaultTable1Specifications()
)
fitOutcomeModelArgs = CohortMethod::createFitOutcomeModelArgs(
  modelType = "cox",
  stratified = psMatchMaxRatio != 1,
  useCovariates = FALSE,
  inversePtWeighting = FALSE,
  prior = Cyclops::createPrior(
    priorType = "laplace", 
    useCrossValidation = TRUE
  ),
  control = Cyclops::createControl(
    cvType = "auto", 
    seed = 1, 
    resetCoefficients = TRUE,
    startingVariance = 0.01, 
    tolerance = 2e-07, 
    cvRepetitions = 1, 
    noiseLevel = "quiet"
  )
)
cmAnalysisList <- list()
for (i in seq_len(nrow(timeAtRisks))) {
  createStudyPopArgs <- CohortMethod::createCreateStudyPopulationArgs(
    firstExposureOnly = FALSE,
    washoutPeriod = 0,
    removeDuplicateSubjects = "keep first",
    censorAtNewRiskWindow = TRUE,
    removeSubjectsWithPriorOutcome = FALSE,
    priorOutcomeLookback = 0,
    riskWindowStart = timeAtRisks$riskWindowStart[[i]],
    startAnchor = timeAtRisks$startAnchor[[i]],
    riskWindowEnd = timeAtRisks$riskWindowEnd[[i]],
    endAnchor = timeAtRisks$endAnchor[[i]],
    minDaysAtRisk = 1,
    maxDaysAtRisk = 99999
  )
  cmAnalysisList[[i]] <- CohortMethod::createCmAnalysis(
    analysisId = i,
    description = sprintf(
      "Cohort method, %s",
      timeAtRisks$label[i]
    ),
    getDbCohortMethodDataArgs = getDbCohortMethodDataArgs,
    createStudyPopArgs = createStudyPopArgs,
    createPsArgs = createPsArgs,
    matchOnPsArgs = matchOnPsArgs,
    # stratifyByPsArgs = stratifyByPsArgs,
    computeSharedCovariateBalanceArgs = computeSharedCovariateBalanceArgs,
    computeCovariateBalanceArgs = computeCovariateBalanceArgs,
    fitOutcomeModelArgs = fitOutcomeModelArgs
  )
}
cohortMethodModuleSpecifications <- cmModuleSettingsCreator$createModuleSpecifications(
  cmAnalysisList = cmAnalysisList,
  targetComparatorOutcomesList = targetComparatorOutcomesList,
  analysesToExclude = NULL,
  refitPsForEveryOutcome = FALSE,
  refitPsForEveryStudyPopulation = FALSE,  
  # set thresholds to be impossible to pass / unblind
  cmDiagnosticThresholds = CohortMethod::createCmDiagnosticThresholds(mdrrThreshold = 1,
                                                                      easeThreshold = 0,
                                                                      sdmThreshold = 0,
                                                                      equipoiseThreshold = 1,
                                                                      attritionFractionThreshold = NULL,
                                                                      generalizabilitySdmThreshold = 1)
)


# SelfControlledCaseSeriesModule Settings -----------------------------------------------
sccsModuleSettingsCreator <- SelfControlledCaseSeriesModule$new()
uniqueTargetIndicationsDemo <- lapply(tcis,
                                  function(x) data.frame(
                                    exposureId = c(x$targetId, x$comparatorId),
                                    nestingCohortId = if (is.null(x$indicationId)) NA else x$indicationId,
                                    genderConceptIds = paste(x$genderConceptIds, collapse = ","),
                                    minAge = if (is.null(x$minAge)) NA else x$minAge,
                                    maxAge = if (is.null(x$maxAge)) NA else x$maxAge
                                  )) |>
  dplyr::bind_rows() |>
  dplyr::distinct()

targetInds <- uniqueTargetIndicationsDemo %>%
  dplyr::select("exposureId", "nestingCohortId") %>%
  dplyr::distinct() 

sccsDemoIds <- uniqueTargetIndicationsDemo %>%
  dplyr::select("genderConceptIds", "minAge", "maxAge") %>% 
  dplyr::distinct() %>%
  dplyr::mutate(analysisId = dplyr::row_number())

# add the rowIds as we will use this for the excludes
# as SCCS wants to do cartesian of targetInd and demo
uniqueTargetIndicationsDemo <- uniqueTargetIndicationsDemo %>%
  dplyr::inner_join(
    y = sccsDemoIds,
    by = c("genderConceptIds", "minAge", "maxAge")
  ) 


# now do the target/ind based on the targetInds
eoList <- list()
for (i in seq_len(nrow(targetInds))) {
  targetIndication <- targetInds[i, ]
  currentIndicationId <- NULL
  if (!is.na(targetIndication$nestingCohortId)) {
    currentIndicationId <- targetIndication$nestingCohortId
  }
  
  # Specify the indication/outcome pairs for the current exposure
  for (outcomeId in unique(outcomes$cohortId)) {
    eoList[[length(eoList) + 1]] <- SelfControlledCaseSeries::createExposuresOutcome(
      outcomeId = outcomeId,
      nestingCohortId = currentIndicationId,
      exposures = list(
        SelfControlledCaseSeries::createExposure(
          exposureId = targetIndication$exposureId,
          trueEffectSize = NA
        )
      )
    )
  }
  
  # Specify the indication/negative control outcome pairs for the current exposure
  for (outcomeId in negativeControlOutcomeCohortSet$cohortId) {
    eoList[[length(eoList) + 1]] <- SelfControlledCaseSeries::createExposuresOutcome(
      outcomeId = outcomeId,
      nestingCohortId = currentIndicationId,
      exposures = list(SelfControlledCaseSeries::createExposure(
        exposureId = targetIndication$exposureId, 
        trueEffectSize = 1
      ))
    )
  }
  
}

# now do the analyses based on the demos
sccsAnalysisList <- list()
for (i in seq_len(nrow(sccsDemoIds))) {
  demo <- sccsDemoIds[i, ]
    
  getDbSccsDataArgs <- SelfControlledCaseSeries::createGetDbSccsDataArgs(
    maxCasesPerOutcome = sccsMaxCasesPerOutcome,
    studyStartDate = studyStartDate,
    studyEndDate = studyEndDate,
    deleteCovariatesSmallCount = 0
  )
  createStudyPopulationArgs = SelfControlledCaseSeries::createCreateStudyPopulationArgs(
    firstOutcomeOnly = TRUE,
    naivePeriod = 365,
    minAge = if (is.na(demo$minAge)) NULL else demo$minAge,
    maxAge = if (is.na(demo$maxAge)) NULL else demo$maxAge
  )
  covarPreExp <- SelfControlledCaseSeries::createEraCovariateSettings(
    label = "Pre-exposure",
    includeEraIds = "exposureId",
    start = -30,
    startAnchor = "era start",
    end = -1,
    endAnchor = "era start",
    firstOccurrenceOnly = FALSE,
    allowRegularization = FALSE,
    profileLikelihood = FALSE,
    exposureOfInterest = FALSE
  )
  calendarTimeSettings <- SelfControlledCaseSeries::createCalendarTimeCovariateSettings(
    calendarTimeKnots = 5,
    allowRegularization = TRUE,
    computeConfidenceIntervals = FALSE
  )
  seasonalitySettings <- SelfControlledCaseSeries::createSeasonalityCovariateSettings(
    seasonKnots = 5,
    allowRegularization = TRUE,
    computeConfidenceIntervals = FALSE
  )
  fitSccsModelArgs <- SelfControlledCaseSeries::createFitSccsModelArgs(
    prior = Cyclops::createPrior("laplace", useCrossValidation = TRUE),
    control = Cyclops::createControl(
      cvType = "auto",
      selectorType = "byPid",
      startingVariance = 0.1,
      seed = 1,
      resetCoefficients = TRUE,
      noiseLevel = "quiet")
  )
  for (j in seq_len(nrow(sccsTimeAtRisks))) {
    covarExposureOfInt <- SelfControlledCaseSeries::createEraCovariateSettings(
      label = "Main",
      includeEraIds = "exposureId",
      start = sccsTimeAtRisks$riskWindowStart[j],
      startAnchor = gsub("cohort", "era", sccsTimeAtRisks$startAnchor[j]),
      end = sccsTimeAtRisks$riskWindowEnd[j],
      endAnchor = gsub("cohort", "era", sccsTimeAtRisks$endAnchor[j]),
      firstOccurrenceOnly = FALSE,
      allowRegularization = FALSE,
      profileLikelihood = TRUE,
      exposureOfInterest = TRUE
    )
    createSccsIntervalDataArgs <- SelfControlledCaseSeries::createCreateSccsIntervalDataArgs(
      eraCovariateSettings = list(covarPreExp, covarExposureOfInt),
      seasonalityCovariateSettings = seasonalitySettings,
      calendarTimeCovariateSettings = calendarTimeSettings
    )
    description <- "SCCS"
    if (demo$genderConceptIds == "8507") {
      description <- sprintf("%s, male", description)
    } else if (demo$genderConceptIds == "8532") {
      description <- sprintf("%s, female", description)
    }
    if (!is.na(demo$minAge) || !is.na(demo$maxAge)) {
      description <- sprintf("%s, age %s-%s",
                             description,
                             if(is.na(demo$minAge)) "" else demo$minAge,
                             if(is.na(demo$maxAge)) "" else demo$maxAge)
    }
    description <- sprintf("%s, %s", description, sccsTimeAtRisks$label[j])
    sccsAnalysisList[[length(sccsAnalysisList) + 1]] <- SelfControlledCaseSeries::createSccsAnalysis(
      analysisId = length(sccsAnalysisList) + 1,
      description = description,
      getDbSccsDataArgs = getDbSccsDataArgs,
      createStudyPopulationArgs = createStudyPopulationArgs,
      createIntervalDataArgs = createSccsIntervalDataArgs,
      fitSccsModelArgs = fitSccsModelArgs
    )
  }
}

# now figure out what to exclude
includeSccs <- uniqueTargetIndicationsDemo %>% 
  dplyr::select("exposureId","nestingCohortId", "analysisId") %>%
  dplyr::distinct()

# remove the included from all combinations to get the combinations you dont want
analysesToExclude <- expand.grid(
  exposureId = unique(uniqueTargetIndicationsDemo$exposureId),
  analysisId = unique(uniqueTargetIndicationsDemo$analysisId),
  nestingCohortId = unique(uniqueTargetIndicationsDemo$nestingCohortId)
) |>
  dplyr::anti_join(includeSccs, by = dplyr::join_by(exposureId, analysisId,nestingCohortId))


selfControlledModuleSpecifications <- sccsModuleSettingsCreator$createModuleSpecifications(
  sccsAnalysisList = sccsAnalysisList,
  exposuresOutcomeList = eoList,
  analysesToExclude = analysesToExclude,
  combineDataFetchAcrossOutcomes = FALSE,
  sccsDiagnosticThresholds = SelfControlledCaseSeries::createSccsDiagnosticThresholds()
)

# PatientLevelPredictionModule Settings -------------------------------------------------
plpModuleSettingsCreator <- PatientLevelPredictionModule$new()
modelDesignList <- list()
uniqueTargetIds <- unique(unlist(lapply(tcis, function(x) { c(x$targetId ) })))
dfUniqueTis <- dfUniqueTcis[dfUniqueTcis$cohortId %in% uniqueTargetIds, ]
for (i in 1:nrow(dfUniqueTis)) {
  tci <- dfUniqueTis[i,]
  cohortId <- cohortDefinitionSet |> 
    dplyr::filter(subsetParent == tci$cohortId & subsetDefinitionId == tci$subsetDefinitionId) |>
    dplyr::pull(cohortId)
  for (j in seq_len(nrow(plpTimeAtRisks))) {
    for (k in seq_len(nrow(outcomes))) {
      if (useCleanWindowForPriorOutcomeLookback)
        priorOutcomeLookback <- outcomes$cleanWindow[k]
      else
        priorOutcomeLookback <- 99999
      modelDesignList[[length(modelDesignList) + 1]] <- PatientLevelPrediction::createModelDesign(
        targetId = cohortId,
        outcomeId = outcomes$cohortId[k],
        restrictPlpDataSettings = PatientLevelPrediction::createRestrictPlpDataSettings(
          sampleSize = plpMaxSampleSize,
          studyStartDate = studyStartDate,
          studyEndDate = studyEndDate,
          firstExposureOnly = FALSE,
          washoutPeriod = 0
        ),
        populationSettings = PatientLevelPrediction::createStudyPopulationSettings(
          riskWindowStart = plpTimeAtRisks$riskWindowStart[j],
          startAnchor = plpTimeAtRisks$startAnchor[j],
          riskWindowEnd = plpTimeAtRisks$riskWindowEnd[j],
          endAnchor = plpTimeAtRisks$endAnchor[j],
          removeSubjectsWithPriorOutcome = TRUE,
          priorOutcomeLookback = priorOutcomeLookback,
          requireTimeAtRisk = FALSE,
          binary = TRUE,
          includeAllOutcomes = TRUE,
          firstExposureOnly = FALSE,
          washoutPeriod = 0,
          minTimeAtRisk = plpTimeAtRisks$riskWindowEnd[j] - plpTimeAtRisks$riskWindowStart[j],
          restrictTarToCohortEnd = FALSE
        ),
        covariateSettings = FeatureExtraction::createCovariateSettings(
          useDemographicsGender = T,
          useDemographicsAge = T,
          useDemographicsAgeGroup = T,
          useDemographicsRace = T,
          useDemographicsEthnicity = T,
          useDemographicsIndexYear = T,
          useDemographicsIndexMonth = T,
          useDemographicsTimeInCohort = T,
          useDemographicsPriorObservationTime = T,
          useDemographicsPostObservationTime = T,
          useConditionGroupEraLongTerm = T,
          useDrugGroupEraOverlapping = T,
          useDrugGroupEraLongTerm = T,
          useProcedureOccurrenceLongTerm = T,
          useMeasurementLongTerm = T,
          useObservationLongTerm = T,
          useDeviceExposureLongTerm = T,
          useVisitConceptCountLongTerm = T,
          useConditionGroupEraShortTerm = T,
          useDrugGroupEraShortTerm = T,
          useProcedureOccurrenceShortTerm = T,
          useMeasurementShortTerm = T,
          useObservationShortTerm = T,
          useDeviceExposureShortTerm = T,
          useVisitConceptCountShortTerm = T
        ),
        preprocessSettings = PatientLevelPrediction::createPreprocessSettings(),
        modelSettings = PatientLevelPrediction::setLassoLogisticRegression()
      )
    }
  }
}
plpModuleSpecifications <- plpModuleSettingsCreator$createModuleSpecifications(
  modelDesignList = modelDesignList
)

# Create the analysis specifications ------------------------------------------

# To disable specific modules, just remove them here:
analysisSpecifications <- Strategus::createEmptyAnalysisSpecificiations() |>
  Strategus::addSharedResources(cohortDefinitionShared) |> 
  Strategus::addSharedResources(negativeControlsShared) |>
  Strategus::addModuleSpecifications(cohortGeneratorModuleSpecifications) |>
 # Strategus::addModuleSpecifications(cohortDiagnosticsModuleSpecifications) |>
  Strategus::addModuleSpecifications(characterizationModuleSpecifications) |>
  Strategus::addModuleSpecifications(cohortIncidenceModuleSpecifications) # |>
#  Strategus::addModuleSpecifications(cohortMethodModuleSpecifications) # |>
#  Strategus::addModuleSpecifications(selfControlledModuleSpecifications) |>
#  Strategus::addModuleSpecifications(plpModuleSpecifications)

if (!dir.exists(config$projectRootFolder)) {
  dir.create(config$projectRootFolder, recursive = TRUE)
}
ParallelLogger::saveSettingsToJson(analysisSpecifications, file.path(config$projectRootFolder, config$studySpecificationFileName))
