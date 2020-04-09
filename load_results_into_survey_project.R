library(tidyverse)
library(dotenv)
library(REDCapR)

# NOTE: For production script the data will be read from pid 8270
# to get the research_encounter_id which will then be written to pid 8258
  
# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))

# read data from survey project
survey_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("SURVEY_TOKEN"))$data %>%
  filter(!is.na(research_encounter_id)) %>%
  select(record_id, redcap_event_name, research_encounter_id, 
         covid_19_swab_result, igg_antibodies, igm_antibodies)

survey_swab_data <- survey_project_read %>%
  filter(is.na(covid_19_swab_result)) %>%
  select(record_id, redcap_event_name, research_encounter_id)

# read data from result upload project, pid 8258
result_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("RESULT_TOKEN"))$data

# make result upload file for swabs
swab_result <-
  result_project_read %>%
  filter(!is.na(record_id)) %>% 
  select(research_encounter_id = record_id, covid_19_swab_result) %>%
  filter(!is.na(covid_19_swab_result)) %>% 
  inner_join(survey_swab_data, by=c("research_encounter_id")) %>%
  mutate(covid_19_swab_result = case_when(
    str_detect(str_to_lower(covid_19_swab_result), "pos") ~ "1",
    str_detect(str_to_lower(covid_19_swab_result), "neg") ~ "0",
    TRUE ~ as.character(NA)
  )) %>%
  select(record_id, redcap_event_name, covid_19_swab_result) %>%
  arrange(record_id) 

# write data to survey project
redcap_write_oneshot(swab_result,
                     redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                     token = Sys.getenv("SURVEY_TOKEN"))

