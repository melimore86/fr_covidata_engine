library(tidyverse)
library(dotenv)
library(REDCapR)

# NOTE: For production script the data will be read from prod version of pid 8236 
# to get the research_encounter_id which will then be written to pid 8258
  
# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))
# Sys.getenv("INSTANCE")

# read data from pid 8218
records <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                                       token = Sys.getenv("SURVEY_TOKEN"))$data %>% 
  filter(!is.na(research_encounter_id)) %>% 
  select(research_encounter_id, covid_19_swab_result, igg_antibodies, igm_antibodies) %>% 
  rename(record_id  = research_encounter_id) %>% 
  mutate(covid_19_swab_result =  sample(c("Positive", "Negative", "negative", "positive"), 32, replace = T)) %>%
  mutate(igg_antibodies = sample(c("Positive", "Negative", "negative", "positive"), 32, replace = T),
         igm_antibodies = sample(c("Positive", "Negative", "negative", "positive"), 32, replace = T))

# TODO:write data to pid 8236
redcap_write_oneshot(records, 
                    redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                    token = Sys.getenv("RESULT_TOKEN"))
