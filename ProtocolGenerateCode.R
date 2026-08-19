# Note: you may need to set github path to download 
# if you get an error with running line 3.
if (!"ProtocolGenerator" %in% as.data.frame(installed.packages())$Package) {
  remotes::install_github('ohdsi/ProtocolGenerator')
}

# open this inside your strategus project or set the directory
# using setwd('location to strategus directory')
ProtocolGenerator::generateProtocol(
  jsonLocation = file.path(config$projectRootFolder,"analysisSpecifications.json"),
  webAPI = 'https://atlas-demo.ohdsi.org/WebAPI', 
  outputLocation = config$resultFolder, 
  outputName = 'protocol.html', 
  intermediateDir = tempdir()
)