remotes::install_github('ohdsi/OhdsiReportGenerator', ref = 'develop') 
#or install.packages('OhdsiReportGenerator')

webApiPassword <- .rs.askForPassword("Enter your web api password: ")

config <- config::get()

OhdsiReportGenerator::generateFullReport(
  server = Sys.getenv("OHDA_RESULTS_SERVER"),
  password = Sys.getenv("OHDA_RESULTS_RO_PASSWORD"),
  username =  Sys.getenv("OHDA_RESULTS_RO_USER"),
  dbms = "postgresql",
  resultsSchema = config$resultsDatabaseSchema,
  targetId = 20126,
  outcomeIds = c(20129, 20130),
  indicationIds = 20128,
  comparatorIds = c(20127),
  cohortIds = c(20126,20127,20128,20129, 20130),
  cohortNames = c('Ace inhibitor','Diuretic','Hypertensive disorder','AMI', 'Angioedema'),
  includeCI = TRUE,
  includeCharacterization = TRUE,
  includeCohortMethod = TRUE,
  includeSccs = TRUE,
  includePrediction = TRUE,
  webAPI = config$webApiUrl,
  authMethod = "windows",
  webApiUsername = gsub('admin_','',Sys.info()['user']),
  webApiPassword = webApiPassword,
  outputLocation = config$resultFolder,
  outputName = paste0('full_report_', gsub(':', '_',gsub(' ','_',as.character(date()))),'.html'),
  intermediateDir = tempdir(),
  pathToDriver = file.path(config$projectRootFolder,'drivers')
)

# To add to rconnect:
##rsconnect::deployDoc(file.path(config$resultFolder, paste0('full_report_', gsub(':', '_',gsub(' ','_',as.character(date()))),'.html')))
