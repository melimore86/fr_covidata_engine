# Change Log
All notable changes to the REDCap First Responder COVID-19 ETL Engine project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).


## [0.1.0] - 2020-04-14
### Summary
 - First release of fr_covidata_engine
 - Supports swab results: pos, neg, and ina
 - Updates only blank results in survey project
 - Provides a log of upload results and non-loadable for swabs
 - Writes a custom email body using good/bad result count, project titles, PIDs, and URL to result project for address errors
 - Emails log file to configurable addressees
