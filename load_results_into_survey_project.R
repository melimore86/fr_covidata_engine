library(tidyverse)
library(dotenv)
library(REDCapR)
library(openxlsx)
library(sendmailR)

source("functions.R")
# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))

# echo details from the .env file we read
Sys.getenv("INSTANCE")
Sys.getenv("PROJECT")

script_run_time <- strftime(Sys.time(), format = "%Y%m%d_%H%M") 

# email credentials
email_server <- list(smtpServer = Sys.getenv("SMTP_SERVER"))
email_from <- Sys.getenv("EMAIL_FROM")
email_to <- unlist(strsplit(Sys.getenv("EMAIL_TO")," "))
email_cc <- unlist(strsplit(Sys.getenv("EMAIL_CC")," "))
email_subject <- paste(Sys.getenv("EMAIL_SUBJECT"), script_run_time)

# NOTE: For production script the data will be read from pid 8270
# to get the research_encounter_id which will then be written to pid 8258

# read data from survey project (prod pid 8258)
survey_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("SURVEY_TOKEN"))$data %>%
  filter(!is.na(research_encounter_id)) %>%
  select(record_id, redcap_event_name, research_encounter_id, 
         covid_19_swab_result, igg_antibodies, igm_antibodies)

# survey records without swab data
survey_swab_data <- survey_project_read %>%
  filter(is.na(covid_19_swab_result)) %>%
  select(record_id, redcap_event_name, research_encounter_id)

# read data from result upload project, (prod pid 8270)
result_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("RESULT_TOKEN"))$data %>% 
  rowwise() %>% 
  mutate(verified_id = verifyLuhn(record_id))

# Run these two tests on entire dataset so we'll know that the corrections have
# been made

# flag incorrect barcodes
result_id_with_bad_checksum <- result_project_read %>% 
  filter(!verified_id) %>% 
  mutate(reason_not_imported = 'bad checksum in barcode id') %>% 
  select(record_id, covid_19_swab_result, verified_id,
      reason_not_imported)

# on the low chance that the barcode passes checksum but does not match an id
# in the survey project
result_id_with_no_match_in_survey <- result_project_read %>% 
  filter(verified_id) %>% 
  anti_join(survey_project_read, by = c("record_id" = "research_encounter_id")) %>% 
  mutate(reason_not_imported = 'no match in target project') %>% 
  select(record_id, covid_19_swab_result, verified_id, 
         reason_not_imported)

# make result upload file for swabs
swab_result <- result_project_read %>% 
  filter(!is.na(record_id)) %>% 
  select(research_encounter_id = record_id, covid_19_swab_result, verified_id) %>%
  filter(!is.na(covid_19_swab_result)) %>%  
  # join to get records in survey project without swab results
  inner_join(survey_swab_data, by=c("research_encounter_id")) %>%
  mutate(covid_19_swab_result = case_when(
    str_detect(str_to_lower(covid_19_swab_result), "pos") ~ "1",
    str_detect(str_to_lower(covid_19_swab_result), "neg") ~ "0",
    str_detect(str_to_lower(covid_19_swab_result), "ina") ~ "99",
    TRUE ~ covid_19_swab_result
  )) %>%
  select(record_id, redcap_event_name, covid_19_swab_result, verified_id) %>%
  arrange(record_id) 

# only send an email when there are new swab results
if (nrow(swab_result) > 0){

  # create folder to store output
  output_dir <- paste0("fr_covid19_import_log_", script_run_time)
  dir.create(output_dir, recursive = T)
  
  # write data to survey project
  swab_result_to_import <- swab_result %>% 
  filter(covid_19_swab_result %in% c("1","0", "99") & verified_id) %>% 
    select(-verified_id)
  
  bad_swab_result <- swab_result %>% 
    select(-redcap_event_name) %>% 
    filter(!covid_19_swab_result %in% c("1","0", "99") & verified_id) %>% 
    mutate(reason_not_imported = "improper value for swab result") %>%   
    mutate_at(vars(record_id), as.character) %>% 
    bind_rows(result_id_with_bad_checksum) %>% 
    bind_rows(result_id_with_no_match_in_survey)
  
  # only write to redcap when there are legit records
  if(nrow(swab_result_to_import) > 0 ){
  redcap_write_oneshot(swab_result_to_import,
                       redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                       token = Sys.getenv("SURVEY_TOKEN"))
  }
  
  all_output <- list("Swab Results Imported" = swab_result_to_import,
                     "Swab Results Not Imported" = bad_swab_result)
  
  write.xlsx(all_output, 
             paste0(output_dir, "/swab_result_log_", script_run_time, ".xlsx"), 
             na = "")
  
  # Zip the reports generated
  zipfile_name <-  paste0(output_dir, ".zip")
  zip(zipfile_name, output_dir)
  
  # attach the zip file and email it
  attachment_object <- mime_part(zipfile_name, zipfile_name)
  project_title <- Sys.getenv("SURVEY_PROJECT_TITLE")
  project_pid   <- Sys.getenv("SURVEY_PROJECT_PID")
  result_project_pid <- Sys.getenv("RESULT_PROJECT_PID")
  
  body <- paste0("The attached file(s) includes a log of all results that were uploaded",
               " to the REDCap project, ", project_title, " (PID ", project_pid ,")",
               "\n\nNumber of records uploaded: ", nrow(swab_result_to_import),
               "\nNumber of records not uploaded: ", nrow(bad_swab_result),
               "\n\nIf there are records that were not uploaded, then there were",
               " improper values in the swab result column or incorrect record_ids were used", 
               " Please review the Swab Results Not Imported tab in the attached log file",
               " then update these records at ",
               "https://redcap.ctsi.ufl.edu/redcap/redcap_v9.3.5/index.php?pid=", result_project_pid)
  
  body_with_attachment <- list(body, attachment_object)
  
  # send the email with the attached output file
  sendmail(from = email_from, to = email_to, cc = email_cc,
           subject = email_subject, msg = body_with_attachment,
           control = email_server)
  
  # uncomment to delete output once on tools4
  # unlink(zipfile_name)
  
} 
