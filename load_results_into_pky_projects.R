library(tidyverse)
library(lubridate)
library(dotenv)
library(REDCapR)
library(openxlsx)
library(sendmailR)

source("functions.R")

# echo details from the .env file we read
Sys.getenv("INSTANCE")
Sys.getenv("PROJECT")

# set the timezone
Sys.setenv(TZ = Sys.getenv("TIME_ZONE"))

script_run_time <- strftime(Sys.time(), format = "%Y%m%d_%H%M") 

# email credentials
email_server <- list(smtpServer = Sys.getenv("SMTP_SERVER"))
email_from <- Sys.getenv("EMAIL_FROM")
email_to <- unlist(strsplit(Sys.getenv("EMAIL_TO")," "))
email_cc <- unlist(strsplit(Sys.getenv("EMAIL_CC")," "))
email_subject <- paste(Sys.getenv("EMAIL_SUBJECT"), script_run_time)

# read data from survey project
survey_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("SURVEY_TOKEN"))$data %>%
  filter(!is.na(research_encounter_id)) %>%
  mutate(test_date_and_time=ymd_hms(test_date_and_time)) %>%
  select(record_id,
         redcap_event_name,
         ce_firstname,
         ce_lastname,
         icf_age,
         patient_dob,
         icf_lar_name,
         icf_lar_relationship,
         ce_orgconsentdate,
         icf_email,
         qpk_phone,
         research_encounter_id,
         test_date_and_time,
         covid_19_swab_result)

# If data already in Survey got flushed from Serial (generally due to testing), load it into serial now
old_records_for_serial <- survey_project_read %>%
  filter(redcap_event_name == "baseline_arm_1") %>%
  filter(covid_19_swab_result == "1")

# write the new rows to serial if there were any
if(nrow(old_records_for_serial) > 0 ){
  redcap_write_oneshot(old_records_for_serial,
                       redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                       token = Sys.getenv("SERIAL_TOKEN"))
}


# read data from the serial project...if there is any
serial_project_read_all <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                                           token = Sys.getenv("SERIAL_TOKEN"))
if(serial_project_read_all$success) {
  serial_project_read <- serial_project_read_all$data %>%
    filter(!is.na(research_encounter_id)) %>%
    mutate(research_encounter_id = as.character(research_encounter_id)) %>%
    select(record_id,
           redcap_event_name,
           research_encounter_id,
           test_date_and_time,
           consecutive_negative_swab_results,
           covid_19_swab_result)
  } else {
  serial_project_read <- tibble(record_id = numeric(),
                                redcap_event_name=character(),
                                research_encounter_id=character(),
                                test_date_and_time=ymd_hm(),
                                consecutive_negative_swab_results=numeric(),
                                covid_19_swab_result=logical())
}


# survey records without swab data
survey_swab_data <- survey_project_read %>%
  filter(is.na(covid_19_swab_result)) %>%
  select(record_id, redcap_event_name, research_encounter_id)

# serial records without swab data
serial_swab_data <- serial_project_read %>%
  filter(is.na(covid_19_swab_result)) %>%
  select(record_id, redcap_event_name, research_encounter_id)

# combined target rows
combined_read_data <- bind_rows(
  survey_project_read %>% select(record_id, redcap_event_name, research_encounter_id),
  serial_project_read %>% select(record_id, redcap_event_name, research_encounter_id)
  )


# read data from result upload project, (prod pid 8270)
result_project_read <- redcap_read_oneshot(redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                               token = Sys.getenv("RESULT_TOKEN"))$data  %>%
  mutate(covid_19_swab_result = case_when(
    str_detect(str_to_lower(covid_19_swab_result), "pos") ~ "1",
    str_detect(str_to_lower(covid_19_swab_result), "neg") ~ "0",
    str_detect(str_to_lower(covid_19_swab_result), "ina") ~ "99",
    TRUE ~ covid_19_swab_result
  )) %>% 
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
  anti_join(combined_read_data, by = c("record_id" = "research_encounter_id")) %>%
  mutate(reason_not_imported = 'no match in target project') %>% 
  select(record_id, covid_19_swab_result, verified_id, 
         reason_not_imported)

# make result upload file for swabs in the survey project
swab_result <- result_project_read %>% 
  filter(!is.na(record_id)) %>% 
  select(research_encounter_id = record_id, covid_19_swab_result, verified_id) %>%
  filter(!is.na(covid_19_swab_result)) %>%  
  # join to get records in survey project without swab results
  inner_join(survey_swab_data, by=c("research_encounter_id")) %>%
  select(record_id, redcap_event_name, covid_19_swab_result, verified_id) %>%
  filter(!(redcap_event_name != "baseline_arm_1" & covid_19_swab_result == 1)) %>%
  arrange(record_id)


# make result file for swab results that were scheduled in the Survey project 
# but need to be written to the serial project
swab_result_for_serial_spawned_from_survey <- result_project_read %>% 
  filter(!is.na(record_id)) %>% 
  select(research_encounter_id = record_id, covid_19_swab_result, verified_id) %>%
  filter(!is.na(covid_19_swab_result)) %>%  
  # join to get records in survey project without swab results
  inner_join(survey_swab_data, by=c("research_encounter_id")) %>%
  select(record_id, redcap_event_name, covid_19_swab_result, verified_id) %>%
  filter(redcap_event_name == "baseline_arm_1" & covid_19_swab_result == 1) %>%
  arrange(record_id)

# seed new demographic data in serial for each new positive swab in the Survey project
new_records_for_serial <- swab_result_for_serial_spawned_from_survey %>% 
  filter(verified_id & covid_19_swab_result == 1) %>%
  select(record_id, redcap_event_name) %>%
  inner_join(survey_project_read) %>%
  mutate(test_date_and_time = ymd_hms(test_date_and_time)) %>%
  select(-covid_19_swab_result)

# write the new rows to serial if there were any
if(nrow(new_records_for_serial) > 0 ){
  redcap_write_oneshot(new_records_for_serial,
                       redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                       token = Sys.getenv("SERIAL_TOKEN"))
}

# make the dataset for the log file
new_records_for_serial_log_content <- new_records_for_serial %>%
  select(record_id,
         redcap_event_name,
         icf_age,
         ce_orgconsentdate,
         research_encounter_id,
         test_date_and_time)

# make result file for swab results that were scheduled in the Serial project 
# and need to be written to the serial project
swab_result_for_serial_spawned_from_serial <- result_project_read %>% 
  filter(!is.na(record_id)) %>% 
  select(research_encounter_id = record_id, covid_19_swab_result, verified_id) %>%
  filter(!is.na(covid_19_swab_result)) %>%  
  # join to get records in survey project without swab results
  inner_join(serial_swab_data, by=c("research_encounter_id")) %>%
  select(record_id, redcap_event_name, covid_19_swab_result, verified_id) %>%
  arrange(record_id)

swab_result_for_serial <- bind_rows(swab_result_for_serial_spawned_from_survey, 
                                swab_result_for_serial_spawned_from_serial)


all_swab_result <- bind_rows(swab_result, swab_result_for_serial)

# only send an email when there are new swab results
if (nrow(all_swab_result) > 0){

  # create folder to store output
  output_dir <- paste0("pky_covid19_import_log_", script_run_time)
  dir.create(output_dir, recursive = T)
  
  bad_swab_result <- all_swab_result %>% 
    select(-redcap_event_name) %>% 
    filter(!covid_19_swab_result %in% c("1","0", "99") & verified_id) %>% 
    mutate(reason_not_imported = "improper value for swab result") %>%   
    mutate_at(vars(record_id), as.character) %>% 
    bind_rows(result_id_with_bad_checksum) %>% 
    bind_rows(result_id_with_no_match_in_survey)

  # Write results to the survey project...
  swab_result_to_import <- swab_result %>% 
  filter(covid_19_swab_result %in% c("1","0", "99") & verified_id) %>% 
    select(-verified_id)
  
  # ...only write to redcap when there are legit records
  if(nrow(swab_result_to_import) > 0 ){
  redcap_write_oneshot(swab_result_to_import,
                       redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                       token = Sys.getenv("SURVEY_TOKEN"))
  }

  
  # Write results to the serial project
  swab_result_serial_to_import <- swab_result_for_serial %>% 
    filter(covid_19_swab_result %in% c("1","0", "99") & verified_id) %>% 
    select(-verified_id)
  
  # ...only write to redcap when there are legit records
  if(nrow(swab_result_serial_to_import) > 0 ){
    redcap_write_oneshot(swab_result_serial_to_import,
                         redcap_uri = 'https://redcap.ctsi.ufl.edu/redcap/api/',
                         token = Sys.getenv("SERIAL_TOKEN"))
  }

  # make an Excel file with tabs for each slice of data
  all_output <- list("Swab Results Imported Scheduled" = swab_result_to_import,
                     "Swab Results Imported in Serial" = swab_result_serial_to_import,
                     "New records added to Serial" = new_records_for_serial_log_content,
                     "Swab Results Not Imported" = bad_swab_result)
  
  write.xlsx(all_output, 
             paste0(output_dir, "/swab_result_log_", script_run_time, ".xlsx"), 
             na = "")

  # Zip the reports generated
  zipfile_name <-  paste0(output_dir, ".zip")
  zip(zipfile_name, output_dir)
  
  # Write the email
  # Attach the zip file
  attachment_object <- mime_part(zipfile_name, zipfile_name)
  project_title <- Sys.getenv("SURVEY_PROJECT_TITLE")
  project_pid   <- Sys.getenv("SURVEY_PROJECT_PID")
  result_project_pid <- Sys.getenv("RESULT_PROJECT_PID")
  
  # Write the body of the email
  body <- paste0("The attached file(s) includes a log of all results that were uploaded",
               " to the REDCap project, ", project_title, " (PID ", project_pid ,")",
               "\n\nNumber of results loaded in Scheduled: ", nrow(swab_result_to_import),
               "\n\nNumber of results loaded in Serial: ", nrow(swab_result_serial_to_import),
               "\n\nNumber of records added to Serial: ", nrow(new_records_for_serial_log_content),
               "\nNumber of results not loaded: ", nrow(bad_swab_result),
               "\n\nIf there are records that were not loaded, then there were",
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
