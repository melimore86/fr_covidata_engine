library(tidyverse)
library(dotenv)
library(REDCapR)

# NOTE: For production script the data will be read from prod version of pid 8236 
# to get the research_encounter_id which will then be written to pid 8258
  
# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))

# read data from pid 8218
records <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                                       token = Sys.getenv("READ_FROM"))$data %>% 
  filter(!is.na(research_encounter_id)) %>% 
  select(research_encounter_id, covid_19_swab_result, igg_antibodies, igm_antibodies) %>% 
  rename(record_id  = research_encounter_id) %>% 
  mutate(igg_antibodies = c(rep("positive", 18), rep("negative", 14)),
         igm_antibodies = c(rep("positive", 14), rep("negative", 18)))

# TODO:write data to pid 8236
# redcap_write_oneshot(records, 
#                      redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
#                      token = Sys.getenv("WRITE_TO"))

