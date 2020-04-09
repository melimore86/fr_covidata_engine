FROM rocker/tidyverse

WORKDIR /home/fr_covidata_engine

RUN apt update -y && apt install -y \
 libcurl4-openssl-dev

#install necessary libraries
RUN R -e "install.packages(c('tidyverse', 'sendmailR', 'dotenv', 'REDCapR', 'RCurl', 'checkmate', 'openxlsx'))"

#set the unix commands to run the app
CMD R -e "source('load_results_into_survey_project.R')"
