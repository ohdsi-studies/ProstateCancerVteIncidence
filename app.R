# -----------------------------------------------------------------
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# -------------->  PLEASE READ THESE INSTRUCTIONS <----------------
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# NOTE: This script is a bit different from the others
# in this template since it is designed with the intent 
# that you would deploy this script to the RConnect shiny server.
# 
# 
# The connection to the OHDA results database is in your OHDA keyring 
# that was setup initially when configuring the Strategus project
# template. Unfortunatley we can't yet use keyring on RConnect so 
# we have to do things a bit differently in this script. To start, 
# if you are running this file on your local machine (or EC2), you
# will need to set up the environment variables by running 
# the code below which is commented out that sets the environment
# variables that we will eventually set on RConnect. Then you can run
# the script without modification below. If you restart your 
# R Session, you may need to re-run the code to re-set the 
# environment variables.
# ------------------------------------------------------------------
options(java.parameters = "-Xss15m")
Sys.setenv(DATABASECONNECTOR_JAR_FOLDER = './drivers')
if(!dir.exists('./drivers')){
  dir.create('./drivers')
  DatabaseConnector::downloadJdbcDrivers(
    dbms = 'postgresql',
    pathToDriver = './drivers'
  )
}

# Get the study configuration from the config.yml
config <- config::get()

library(ShinyAppBuilder)
library(OhdsiShinyModules)

themePackage <- "ShinyAppBuilder"
# start theme OPTION -- If you want to add a theme uncomment lines 40-43
#if(!require("OhdaThemeJnJ")){
#  install.packages("OhdaThemeJnJ", repos = 'https://rstudiopm.jnj.com/JNJ/latest')
#}
#themePackage <- "OhdaThemeJnJ"
# end theme OPTION

# Specify the connection to the results database
resultsDatabaseConnectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = 'postgresql', 
  user = Sys.getenv("OHDA_RESULTS_RO_USER"), 
  password = Sys.getenv("OHDA_RESULTS_RO_PASSWORD"), 
  server = Sys.getenv("OHDA_RESULTS_SERVER")
)

# ADD OR REMOVE MODULES TAILORED TO YOUR STUDY
shinyConfig <- ShinyAppBuilder::initializeModuleConfig() |>
  ShinyAppBuilder::addModuleConfig(
    ShinyAppBuilder::createDefaultAboutConfig()
  )  |>
  ShinyAppBuilder::addModuleConfig(
    ShinyAppBuilder::createDefaultDatasourcesConfig()
  )  |>
  ShinyAppBuilder::addModuleConfig(
    ShinyAppBuilder::createDefaultCohortGeneratorConfig()
  ) |>
  #ShinyAppBuilder::addModuleConfig(
   # ShinyAppBuilder::createDefaultCohortDiagnosticsConfig()
  #) |>
  ShinyAppBuilder::addModuleConfig(
    ShinyAppBuilder::createDefaultCharacterizationConfig()
  #) |>
  #ShinyAppBuilder::addModuleConfig(
   # ShinyAppBuilder::createDefaultPredictionConfig()
  #) |>
  #ShinyAppBuilder::addModuleConfig(
  #  ShinyAppBuilder::createDefaultEstimationConfig()
  ) 

# now create the shiny app based on the config file and view the results
# based on the connection 
ShinyAppBuilder::createShinyApp(
  title = config$studyName, # Change this to something friendly for the title of the app
  studyDescription = config$studyName, # Change this to something friendly for the description of the app
  config = shinyConfig, 
  connectionDetails = resultsDatabaseConnectionDetails,
  resultDatabaseSettings = ShinyAppBuilder::createDefaultResultDatabaseSettings(schema = config$resultsDatabaseSchema),
  themePackage = themePackage
)


