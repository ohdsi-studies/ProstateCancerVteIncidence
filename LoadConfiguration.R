# Code for setting the connection details and schemas for the various databases,
# as well as some folders in the local file system.

.getDatabricksConnectionDetails <- function(asList = FALSE) {
  password <- Sys.getenv("DATABRICKS_TOKEN")

  if (is.null(password) || password == "")
    cli::cli_abort("DATABRICKS_TOKEN ENVIRONMENT VARIABLE NOT SET")

  databricksConnectionString <- glue::glue("jdbc:databricks://{Sys.getenv('DATABRICKS_HOST')}/default;transportMode=http;ssl=1;AuthMech=3;httpPath={Sys.getenv('DATABRICKS_HTTP_PATH')}")

  cdList <- list(
    dbms = "spark",
    connectionString = databricksConnectionString,
    user = "token",
    password = password
  )
  
  if (asList)
    return(cdList)
  
  return(do.call(DatabaseConnector::createConnectionDetails, cdList))
}

getCatalog <- function(databaseId) {
  switch(
    databaseId,
    HealthVerity = "healthverity_cc",
    AustraliaLpd = "iqvia_australia",
    Ccae = "merative_ccae",
    Cprd = "cprd",
    FranceDa = "iqvia_france",
    GermanyDa = "iqvia_germany",
    Jmdc = "jmdc",
    OptumDod = "optum_extended_dod",
    OptumEhr = "optum_ehr",
    OptumSes = "optum_extended_ses",
    Mdcd = "merative_mdcd",
    Mdcr = "merative_mdcr",
    Pharmetrics = "iqvia_pharmetrics",
    Premier = "premier"
  )
}

testConnection <- function(...) {
  
  connectionWorks <- tryCatch({
    connection <- DatabaseConnector::connect(.getDatabricksConnectionDetails())
    DatabaseConnector::disconnect(connection)
    TRUE
  }, error = function(err) {
    cli::cli_alert_danger(paste(err))
    return (FALSE)
  })
  
  if (connectionWorks) {
    cli::cli_alert_success("CONNECTION TO DATABRICKS SUCCESS!")
    writeLines("connection success", ".environ_status")
    return(TRUE)
  }
  cli::cli_alert_danger("CONNECTION TO DATABRICKS FAILS")
  return(FALSE)
}

#' Cross platform aut for WebApi
.authWebApi <- function(config = config::get()) {
  params <- list(
    baseUrl = config$webApiUrl,
    authMethod = "windows"
  )
  if (.Platform$OS.type != "windows") {
    params$webApiUsername <- Sys.info()['user']
    if (rstudioapi::isAvailable())
      params$webApiPassword <- rstudioapi::askForSecret("Enter your web api password")
    else
      params$webApiPassword <- getPass::getPass("Enter your web api password: ")
  }
  do.call(ROhdsiWebApi::authorizeWebApi, params)
}


createDatabaseSettings <- function(databaseId, config = config::get()) {
  checkmate::assertChoice(databaseId, names(config$cdm))
  cdmSchema <- paste0(getCatalog(databaseId), ".", config$cdm[[databaseId]])
  dbRootFolder <- file.path(config$resultFolder, "results", databaseId)
  strategusInternalsRootFolder = file.path(config$resultFolder, "strategusInternals", databaseId)
  database <- list(
    platform = "databricks",
    cdmDatabaseSchema = cdmSchema,
    scratchSchema = Sys.getenv("DATABRICKS_SCRATCH_SCHEMA"),
    cohortDatabaseSchema = Sys.getenv("DATABRICKS_SCRATCH_SCHEMA"),
    databaseId = databaseId,
    connectionDetailsList = .getDatabricksConnectionDetails(asList = TRUE),
    connectionDetails = .getDatabricksConnectionDetails(),
    cohortTable = sprintf("cohort_%s_%s", config$studyName, databaseId),
    databaseResultsRootFolder = dbRootFolder,
    cohortDiagnosticsFolder = file.path(dbRootFolder, "cohortDiagnostics"),
    pheValuatorFolder = file.path(dbRootFolder, ("pheValuator")),
    strategusResultsFolder = file.path(dbRootFolder, ("strategusResults")),
    strategusInternalsRootFolder = strategusInternalsRootFolder,
    strategusWorkFolder = file.path(strategusInternalsRootFolder, ("strategusWork")),
    strategusExecutionFolder = file.path(strategusInternalsRootFolder, ("strategusExecution"))
  )
  # set temp schema
  options(sqlRenderTempEmulationSchema = Sys.getenv("DATABRICKS_SCRATCH_SCHEMA"))

  class(database) <- "cdmSettings"
  return(database)
}


# Get the study configuration from the config.yml ----------
config <- config::get()

if (config$studyName == "") {
  cli::cli_abort(
    "The config.yml file requires a value for the studyName which is currently set to '{config$studyName}'. Please set it to be a value such as 'epi_12345'"
  )
}

# Build the databases list --------------------
cdmSources <- names(config$cdm)[!names(config$cdm) %in% names(config)]
databases <- list()

databricksScratchSchema <- Sys.getenv("DATABRICKS_SCRATCH_SCHEMA")

if (is.null(databricksScratchSchema) || databricksScratchSchema == "")
  cli::cli_abort("DATABRICKS_SCRATCH_SCHEMA ENVIRONMENT VARIABLE NOT SET")

for (i in seq_along(cdmSources)) {
  databaseId <- cdmSources[i]
  databases[[length(databases) + 1]] <- createDatabaseSettings(databaseId, config = config)
}


# Results database -------------------------------------------------------------
resultsDatabaseConnectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "postgresql",
  server = Sys.getenv("OHDA_RESULTS_SERVER"),
  port = 5432,
  user = Sys.getenv("OHDA_RESULTS_USER"),
  password = Sys.getenv("OHDA_RESULTS_PASSWORD")
)

# This helper function is used to set permissions for the read-only account
# to all tables in the results schema and to run the ANALYZE command for all 
# tables in the results schema
configureResultsSchema <- function(connection = NULL) {
  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(
      connectionDetails = resultsDatabaseConnectionDetails
    )
    on.exit(DatabaseConnector::disconnect(connection))
  }
# 
#   # Grant read only permissions to all tables
#   sql <- "GRANT USAGE ON SCHEMA @schema TO @results_user;
#   GRANT SELECT ON ALL TABLES IN SCHEMA @schema TO @results_user; 
#   GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA @schema TO @results_user;"
  
  # Grant read only permissions to all tables
  sql <- "GRANT USAGE ON SCHEMA @schema TO \"@results_user\";
  GRANT SELECT ON ALL TABLES IN SCHEMA @schema TO \"@results_user\"; 
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA @schema TO \"@results_user\";"
  
  
  message("Setting permissions for results schema")
  sql <- SqlRender::render(
    sql = sql,
    schema = config$resultsDatabaseSchema,
    results_user = Sys.getenv("OHDA_RESULTS_RO_USER")
  )
  DatabaseConnector::executeSql(
    connection = connection,
    sql = sql,
    progressBar = FALSE,
    reportOverallTime = FALSE
  )

  # Analyze all tables in the results schema
  message("Analyzing all tables in results schema")
  sql <- "ANALYZE @schema.@table_name;"
  tableList <- DatabaseConnector::getTableNames(
    connection = connection,
    databaseSchema = config$resultsDatabaseSchema
  )
  for (i in 1:length(tableList)) {
    DatabaseConnector::renderTranslateExecuteSql(
      connection = connection,
      sql = sql,
      schema = config$resultsDatabaseSchema,
      table_name = tableList[i],
      progressBar = FALSE,
      reportOverallTime = FALSE
    )
  }
}

# Data Profile database ---------------
## Create the connection details for the database where the dbProfile results are held
dbProfileConnectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "postgresql",
  server = Sys.getenv("OHDA_DP_RESULTS_SERVER"),
  user = Sys.getenv("OHDA_DP_RESULTS_USER"),
  password = Sys.getenv("OHDA_DP_RESULTS_PASSWORD")
)


