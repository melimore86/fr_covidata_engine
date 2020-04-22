library(tidyverse)
library(dotenv)
library(REDCapR)

# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))
Sys.getenv("INSTANCE")

# read data from the serial project...if there is any
serial_project_read_all <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                                           token = Sys.getenv("SERIAL_TOKEN"))
if(serial_project_read_all$success) {
  records <- serial_project_read_all$data %>%
    filter(!is.na(research_encounter_id)) %>%
    filter(is.na(covid_19_swab_result)) %>%
    select(research_encounter_id, covid_19_swab_result)
  # note the number of records we have so we can make samples of the same size
  n <- nrow(records)

  # make some fake test results
  results <- records %>%
    mutate(covid_19_swab_result = case_when(
      as.integer(str_remove_all(research_encounter_id, "[a-fA-F-]")) %% 2 == 0 ~ "Negative",
      TRUE ~ "Positive"
    )
    ) %>%
    rename(record_id  = research_encounter_id)

  # Write data into the results project if it's safe to do so
  if (Sys.getenv("INSTANCE") == "Development") {
    redcap_write_oneshot(results,
                         redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                         token = Sys.getenv("RESULT_TOKEN"))
  }
}
