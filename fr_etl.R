library(tidyverse)
library(dotenv)
library(REDCapR)

# NOTE: For production script the data will be read from pid 8270
# to get the research_encounter_id which will then be written to pid 8258
  
# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))

# read data from survey project
survey_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("WRITE_TO"))$data %>%
  filter(!is.na(research_encounter_id)) %>%
  select(record_id, redcap_event_name, research_encounter_id, 
         covid_19_swab_result, igg_antibodies, igm_antibodies)

survey_swab_data <- survey_project_read %>%
  filter(is.na(covid_19_swab_result)) %>%
  select(record_id, redcap_event_name, research_encounter_id)

# read data from result upload project, pid 8258
upload_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("READ_FROM"))$data

# make result upload file for swabs
swab_result <- upload_project_read %>%
  filter(!is.na(record_id)) %>% 
  select(research_encounter_id = record_id, covid_19_swab_result) %>%
  filter(!is.na(covid_19_swab_result)) %>% 
  inner_join(survey_swab_data, by=c("research_encounter_id")) %>% 
  select(record_id, redcap_event_name, covid_19_swab_result) %>%
  arrange(record_id) 

# TODO:write data to survey project
# redcap_write_oneshot(records, 
#                      redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
#                      token = Sys.getenv("WRITE_TO"))

