
#Checking and loading needed libraries
if(!requireNamespace("readxl", quietly = TRUE)) install.packages ("readxl")
if(!requireNamespace("tidyverse", quietly = TRUE)) install.packages ("tidyverse")
if(!requireNamespace("purrr", quietly = TRUE)) install.packages ("purrr")
if(!requireNamespace("rstudioapi", quietly = TRUE)) install.packages ("rstudioapi")
if(!requireNamespace("lubridate", quietly = TRUE)) install.packages ("lubridate")

library(readxl)
library(tidyverse)
library(purrr)
library(rstudioapi)
library(lubridate)
options(scipen=999)

#Log File Name
log_filename <- "Scenario A-Experimental Subject Log-UMB.xlsx"


Excel_Folder_Path<-mypath

#Dynamically checks if there is a path, if not ask for one
if(trimws(Excel_Folder_Path)==""){
  Folder_Path<-selectDirectory()
} else{
  Folder_Path<-Excel_Folder_Path
}


#Checks for "INVIVO" or "INVINO"
has_invivo <-grepl("INVIVO",Folder_Path,ignore.case = TRUE) | grepl("INVINO",Folder_Path,ignore.case=TRUE)

#Checks for the data and input folder
  if(has_invivo){
    
    #Case 1: if the input folder was selected directly
    if(tolower(basename(Folder_Path))=="input" && tolower(basename(dirname(Folder_Path)))=="data"){
      data_parent_folder<-dirname(Folder_Path)
      input_folder<-Folder_Path
    }
    
    #If data folder was selected
    else if(tolower(basename(Folder_Path))=="data"){
      data_parent_folder<-Folder_Path
      input_folder<-file.path(data_parent_folder,"Input")
    } 
    
    else{
      next
    }
    #If no INVIVO folder, creates one
  }else {
    data_parent_folder<-file.path(Folder_Path,"Data")
    input_folder<-file.path(data_parent_folder,"Input")
  }

  #Creates an input folder if it doesn't exist
  if(!dir.exists(input_folder)){
    dir.create(input_folder,recursive = TRUE,showWarnings = FALSE)
  }

  #Moves excel files to the input folder
  excel_files<-list.files(Folder_Path,pattern="\\.(xlsx?|xlsm|csv)$",full.names = TRUE,recursive = FALSE)
  
  #Filters out tempoary lock files
  excel_files<-excel_files[!startsWith(basename(excel_files),"~$")]
  
  message("Found ",length(excel_files)," Excel file(s) in: ",Folder_Path)
  
  if(length(excel_files)>0 && normalizePath(Folder_Path,mustWork = FALSE) != normalizePath(input_folder,mustWork = FALSE)){
    
    dest_files<-file.path(input_folder,basename(excel_files))
    
    copy_status<-file.copy(from=excel_files,to=dest_files,overwrite=TRUE)
    
    succesfully_copied<-excel_files[copy_status]
    
    if(length(succesfully_copied)>0){
      #Deletes the orignal file from the data folder
      remove_status<-file.remove(succesfully_copied)
      if(any(!remove_status)){
        message("Warning: Files were copied to input, but couldn't delete the orginals")
      } else{
        message("Success: Moved ",length(succesfully_copied),"file(s) into the input folder.")
      }
    }else{
      message("Error: Failed to copy files - Check folder permission")
    }
  }else if (length(excel_files)==0){
      message("No valid excel files were found")
  }
  
  #==========================================================================================  
  
  #Clock time helper function
  normalize_Clock_time<- function(x){
    if(inherits(x,"POSIXct")){
      return(format(x,"%H:%M"))
    }
    
    x_chr <- trimws(as.character(x))
    
    parsed<-suppressWarnings(parse_date_time(
      toupper(x_chr), 
      orders=c("HM","IMp","HMW","UMSp")
    ))
    
    is_num_str <- grepl("^[0-9\\.]+$", x_chr) & is.na(parsed) & !is.na(x_chr)
    
    if (any(is_num_str)){
      parsed[is_num_str] <- as.POSIXct(
        as.numeric(x_chr[is_num_str]) * 86400, 
        origin = "1899-12-30", 
        tz = "UTC"
      )
    }
    
    
    format(parsed, "%H:%M")
  }
  

#==========================================================================================
  process_INVIVO_rabbit_data <- function(data_file, model) {
    
    file_path <- file.path(input_folder, paste0(data_file, ".xlsx"))
    sheets <- excel_sheets(file_path)
    sheets <- sheets[!grepl("Round|Example|Sheet", sheets, ignore.case = TRUE)]
    
    print(basename(data_file))
    
    df_all <-suppressWarnings(suppressMessages(purrr::map_dfr(sheets, function(sheet) {
  
      read_excel(file_path, range = "A13:BA20", sheet = sheet, trim_ws=T,
                 na = c("", " ","\u00A0", "NA", "N/A", "Not available","unk","did not work", "didnt work", "this does nt seem right", "why????"),
                 .name_repair = function(x) gsub(" ", "_", x)) %>%
        mutate(ID = sheet, MODEL = model) %>% 
        mutate(Clock_Time=normalize_Clock_time(Clock_Time)) 
        })))
    
    template_names <- names(suppressMessages(read_excel(
      file_path,range="A13:BA14",sheet= sheets[1],
      .name_repair = function(x) gsub(" ","_",x)
    )))
    
    exact_metrics_cols<- template_names[3:length(template_names)]
  
    #names(df_all) <- make.names(names(df_all), unique = TRUE)
    
    df_domains <- suppressWarnings(suppressMessages(as.data.frame(
      t(read_excel(
        file_path,
        range = "C11:BA13",
        sheet = sheets[1],
        na = "",
        col_names = FALSE
      ))
    ) %>%
      rename(GROUP = V1, UNITS = V2, METRIC = V3) %>% 
      fill(GROUP, .direction = "down") %>%
      mutate(METRIC = exact_metrics_cols) %>% 

      # Create complex superscript expression
      mutate(
        UNITS = as.character(UNITS),
        UNITS = gsub("10\\^3", "10^3", UNITS),
        UNITS = gsub("10\\^6", "10^6", UNITS),
        UNITS = gsub("mm\\^3", "mm^3", UNITS),
        

        UNITS = case_when(
          grepl("R- | K-", METRIC)    ~ "min",
          grepl("Angle", METRIC)      ~ "degree",
          METRIC == "MA" ~ "mm",
          is.na(UNITS)                ~ "",   
          TRUE                        ~ UNITS
        )
    )))
    
    df_final <- df_all %>% 
      fill(Timepoint, .direction = "down") %>% 
      pivot_longer(MAP:Troponin, values_to = "VALUE", names_to = "METRIC") %>%
      left_join(df_domains, by = "METRIC")  %>% 
      filter(!is.na(VALUE))
      
    
    return(df_final)
  }
  
  master_dataset <- tribble(
  ~sheet_name,                              ~model_name,           ~include,
  "CONCERT Y2 Low Res - A-FB",              "FWB",                TRUE,
  "CONCERT Y2 Low Res - A-LR",              "LR",                 TRUE,
  "CONCERT Y2 Low Res - A-SB",              "SWB",                TRUE,
  "CONCERT Y2 Low Res - A-pHb-WBA",         "WBA-pHb",            TRUE,
  "CONCERT Y2 Low Res - A-EMv2.0-WBA",      "EMv2.0_WBA",         TRUE,
  "CONCERT Y2 Low Res - A-EMv3.0-WBA",      "EMv3.0_WBA",         TRUE,
  "CONCERT Y2 Low Res - A-EMv2.0-SAC",      "EMv2.0_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv3.0-SAC",      "EMv3.0_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv3.0L-SAC",     "EMv3.0L_SAC",        FALSE,  
  "CONCERT Y2 Low Res - A-EMv3.1-SAC",      "EMv3.1_SAC",         FALSE,  
  "CONCERT Y2 Low Res - A-EMv4.0-SAC",      "EMv4.0_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv4.2-SAC",      "EMv4.2_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv4.3-SAC",      "EMv4.3_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv4.4-SAC",      "EMv4.4_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv4.4DL-SAC",    "EMv4.4DL_SAC",       FALSE, 
  "CONCERT Y2 Low Res - A-EMv4.4L-SAC",     "EMv4.4L_SAC",        FALSE,  
  "CONCERT Y2 Low Res - A-EMv4.5-SAC",      "EMv4.5_SAC",         FALSE, 
  "CONCERT Y2 Low Res - A-EMv4.12-SAC",     "EMv4.12_SAC",        FALSE,
  "CONCERT Y2 Low Res - A-EMv4.12L-SAC",    "EMv4.12L_SAC",       FALSE,
  "CONCERT Y2 Low Res - A-EMv4.14L-SAC",    "EMv4.14L_SAC",       FALSE,
  "CONCERT Y2 Low Res - A-EMv4.15DL-SAC",   "EMv4.15DL_SAC",      FALSE,  
  "CONCERT Y2 Low Res - A-EMv4.15L-SAC",    "EMv4.15L_SAC",       FALSE, 
  "CONCERT Y2 Low Res - A-EMv4.4DL-SAC",    "EMv4.4DL_SAC",       FALSE, 
  "CONCERT Y2 Low Res - A-EMv5.0-SAC",      "EMv5.0_SAC",         FALSE, 
  "CONCERT Y2 Low Res - A-EMv5.0L-SAC",     "EMv5.0L_SAC",        FALSE,
  "CONCERT Y2 Low Res - A-EMv5.2-SAC",      "EMv5.2_SAC",         FALSE,
  "CONCERT Y2 Low Res - A-EMv6.0.3sc-SAC",  "EMv6.0.3sc_SAC",     FALSE,
  "CONCERT Y2 Low Res - A-EMv6.0.3L-SAC",   "EMv6.0.3L_SAC",      FALSE,
  "CONCERT Y2 Low Res - A-EMv6.0.3rHb-SAC", "EMv6.0.3rHb_SAC",    FALSE,
  "CONCERT Y2 Low Res - A-EMv6.1.1-SAC",    "EMv6.1.1_SAC",       FALSE,
  "CONCERT Y2 Low Res - A-EMv6.1.3-SAC",    "EMv6.1.3_SAC",       FALSE,
  "CONCERT Y2 Low Res - A-EMv6.3.3c-SAC",   "EMv6.3.3c_SAC",      FALSE,
  "CONCERT Y2 Low Res - A-EMv6.5.3-SAC",    "EMv6.5.3_SAC",       FALSE,
  "CONCERT Y2 Low Res - A-EMv6.6.3-SAC",    "EMv6.6.3_SAC",       FALSE 
   )
  
  datasets_to_process <- master_dataset %>% 
    filter(include) %>% 
    pmap(function(sheet_name, model_name, ...) c(sheet_name, model_name)) %>% 
    set_names(paste0("df_", master_dataset %>% filter(include) %>% pull(model_name)))


  df_log <- read_excel(paste0(input_folder,"/", log_filename), 
                       sheet=2, na = c(""), 
                       .name_repair = function(x) gsub(" ", "_", x)) %>%
    select(1:15) %>% 
    rename(INCLUDE = 'In/Excluded', INTERNAL = 'Internal?') %>% 
    mutate(ID = paste0(Group_Name, " ", ID)) 
  
  vec_internal <- df_log  %>% filter(INCLUDE == "Included" & !is.na(INTERNAL))  %>% pull(ID)
  vec_include <- df_log  %>% filter(INCLUDE == "Included" & is.na(INTERNAL))  %>% pull(ID)
  
  
  processed_list <- purrr::map(datasets_to_process, ~ process_INVIVO_rabbit_data(.x[1], .x[2]))
  
  
  df_INVIVO_scenarioA_Master <- bind_rows(processed_list) %>%
    filter(!(is.na(METRIC))) 
  
#==========================================================================================
#Creates a folder path for "analysis_read_data"
analysis_ready_folder<-file.path(data_parent_folder,"analysis_ready_data")

if(!dir.exists(analysis_ready_folder)){
  dir.create(analysis_ready_folder,recursive=FALSE,showWarnings = FALSE)
}

#Creates the 'master'
df_INVIVO_scenarioA_Master$ID<-trimws(df_INVIVO_scenarioA_Master$ID)

write_csv(df_INVIVO_scenarioA_Master,file.path(analysis_ready_folder,"df_INVIVO_scenarioA_Master.csv"))

df_INVIVO_scenarioA_internal<-df_INVIVO_scenarioA_Master |> filter(ID %in% vec_internal)
write_csv(df_INVIVO_scenarioA_internal,file.path(analysis_ready_folder,"df_INVIVO_scenarioA_internal.csv"))

df_INVIVO_ScenarioA<-df_INVIVO_scenarioA_Master |> filter(ID%in% vec_include)
write_csv(df_INVIVO_ScenarioA,file.path(analysis_ready_folder,"df_INVIVO_ScenarioA.csv"))


