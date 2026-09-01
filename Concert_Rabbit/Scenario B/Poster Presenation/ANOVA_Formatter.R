
                                       ########################
                                       #       Libaries       #
                                       ########################
                                       
#Checking and loading needed libraries
if(!requireNamespace("readxl", quietly = TRUE)) install.packages ("readxl")
if(!requireNamespace("tidyverse", quietly = TRUE)) install.packages ("tidyverse")
if(!requireNamespace("purrr", quietly = TRUE)) install.packages ("purrr")
if(!requireNamespace("rstudioapi", quietly = TRUE)) install.packages ("rstudioapi")
if(!requireNamespace("openxlsx", quietly = TRUE)) install.packages ("openxlsx")
                                       
library(readxl)
library(tidyverse)
library(purrr)
library(rstudioapi)
library(openxlsx)
options(scipen=999)


                                       ########################
                                       #     Change These     #
                                       ########################

#Log File Name
log_filename <- "Scenario B-Experimental Subject Log-UMB_08052026.xlsx"

#Files to modify
datasets_to_process<-list(
  df_B_B         <-c("B-B_Low Res_02022026", "B-B"),
  df_LR           <-c("B-LR_Low Res_04132026", "B-LR"),
  df_EM          <-c("B-EM_Low Res_04132026 ", "B-EM")
  #df_PRC          <-c("B-PRC_Low Res_08042026", "B-PRC")
)

target_measurements <- c("MAP", "LAC", "pH", "bpm")

                                        ########################
                                        #      Functions      #
                                        ########################
mypath=getwd()

Excel_Folder_Path<-mypath

#Dynamically checks if there is a path, if not ask for one
if(trimws(Excel_Folder_Path)==""){
  Folder_Path<-selectDirectory()
} else{
  Folder_Path<-Excel_Folder_Path
}


if(tolower(basename(Folder_Path))!="Input"){
  input_folder<-file.path(Folder_Path,"Input")
} else{
  input_folder<-Folder_Path
}

if(!dir.exists(input_folder)){
  dir.create(input_folder,recursive = TRUE,showWarnings = FALSE)
}

data_parent_folder<-dirname(input_folder)

#Stops the script if the folder doesn't exist
if(!dir.exists(input_folder)){
  stop(paste("Error: The directory",input_folder,"does not exist. Please check your path"))
}
#==========================================================================================

Remaining_Files<-list.files(Folder_Path,pattern="\\.(xlsx?|xlsm|csv)$",full.names = TRUE,recursive = FALSE)
Remaining_Files<-Remaining_Files[!startsWith(basename(Remaining_Files),"~$")]


if(length(Remaining_Files)>0 && normalizePath(Folder_Path,mustWork = FALSE) != normalizePath(input_folder,mustWork = FALSE)){
  
  dest_files<-file.path(input_folder,basename(Remaining_Files))
  
  copy_status<-file.copy(from=Remaining_Files,to=dest_files,overwrite=TRUE)
  
  succesfully_copied<-Remaining_Files[copy_status]
  
  if(length(succesfully_copied)>0){
    #Deletes the orignal file from the data folder
    remove_status<-file.remove(succesfully_copied)
    if(any(!remove_status)){
      message("Warning: Files were copied to input, but couldn't delete the orginals")
    } else{
      message("Success: Moved ",length(succesfully_copied)," file(s) into the input folder.")
    }
  }else{
    message("Error: Failed to copy files - Check folder permission")
  }
}
excel_files<-list.files(input_folder,pattern="\\.(xlsx?|xlsm|csv)$",full.names = TRUE,recursive = FALSE)
excel_files<-excel_files[!startsWith(basename(excel_files),"~$")]

message("Found ",length(excel_files)," Excel file(s) to process in: ",input_folder)

if(length(excel_files)==0){
  message("No Valid Excel Files were found")
}

#==========================================================================================
#Clock time helper function
normalize_Clock_time<- function(x){
  if(inherits(x,"POSIXct")){
    return(format(x,"%H:%M"))
  }
  
  x<-toupper(trimws(as.character(x)))
  
  parsed<-suppressWarnings(parse_date_time(
    x, orders=c("HM","IMp","HMW","UMSp")
  )
  )
  
  format(parsed, "%H:%M")
}


process_INVIVO_rabbit_data <- function(data_file, model) {
  
  file_path <- file.path(input_folder, paste0(data_file, ".xlsx"))
  sheets <- excel_sheets(file_path)
  
  print(data_file)
  sheets <- sheets[!grepl("template",sheets,ignore.case = TRUE)]
  df_all <-suppressWarnings(suppressMessages(purrr::map_dfr(sheets, function(sheet) {
    
    #+++++++++++++++++++ debugging
    cat("Processing:", sheet, "\n")
    
    tmp<-read_excel(file_path, range = "A14:BA25", sheet = sheet, trim_ws=T,
                    na = c("", " ","\u00A0", "NA", "N/A", "Not available","unk","did not work", "didnt work", "this does nt seem right", "why????"),
                    .name_repair = function(x) make.names(gsub(" ", "_", x),unique=TRUE)) %>%
      mutate(Clock_Time=normalize_Clock_time(Clock_Time)) %>%
      mutate(ID = sheet, MODEL = model) %>%
      mutate(across(MAP:C5a, as.numeric)) %>% 
      select(-X)
  })
  
  
  ))
  
  names(df_all) <- make.names(names(df_all), unique = TRUE)
  
  df_domains <- suppressWarnings(suppressMessages(as.data.frame(
    t(read_excel(
      file_path,
      range = "C12:BA14",
      sheet = sheets[1],
      na = "",
      col_names = FALSE
    ))
  ) %>%
    rename(GROUP = V1, UNITS = V2, METRIC = V3) %>% 
    fill(GROUP, .direction = "down") %>%
    mutate(METRIC = gsub(" ", "_", as.character(METRIC))) %>%
    mutate(METRIC = gsub("%", "X.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("R-", "R.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("K-", "K.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("IL-", "IL.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("MCP-", "MCP.", as.character(METRIC))) %>%
    # Create complex superscript expression
    mutate(
      UNITS = as.character(UNITS),
      UNITS = gsub("10\\^3", "10^3", UNITS),
      UNITS = gsub("10\\^6", "10^6", UNITS),
      UNITS = gsub("mm\\^3", "mm^3", UNITS)
    )
  ))
  
  df_final <- df_all %>% 
    fill(Timepoint, .direction = "down") %>% 
    pivot_longer(MAP:C5a, values_to = "VALUE", names_to = "METRIC") %>%
    left_join(df_domains, by = "METRIC")  %>% 
    filter(!is.na(VALUE)) %>%
    mutate(METRIC = gsub("HGB","Hb",METRIC)) %>% 
    select(-Measurement_.) 
  
  
  return(df_final)
}




df_log <- read_excel(paste0(input_folder,"/", log_filename), 
                     range = "A1:O500", sheet=2, na = c(""), .name_repair = function(x) gsub(" ", "_", x)) %>%
  rename(INCLUDE = 'In/Excluded', INTERNAL = 'Internal?') %>% 
  mutate(ID = paste0(Group_Name, " ", ID)) 

vec_exclude <- df_log %>%
  filter(INCLUDE=="Excluded") %>%
  pull(ID) %>%
  trimws()



processed_list <- purrr::map(datasets_to_process, ~ process_INVIVO_rabbit_data(.x[1], .x[2]))


df_INVIVO_scenarioB_Master <- bind_rows(processed_list) %>%
  filter(!(is.na(METRIC))) 
df_INVIVO_scenarioB_Master %>%
  count(MODEL)

df_INVIVO_scenarioB_Master %>%
  distinct(MODEL, ID) %>%
  count(MODEL)

#==========================================================================================
#Creates a folder path for "analysis_read_data"

data_parent_folder<-dirname(input_folder)
analysis_ready_folder<-file.path(data_parent_folder,"ANOVA_Ready_Data")

if(!dir.exists(analysis_ready_folder)){
  dir.create(analysis_ready_folder,recursive=FALSE,showWarnings = FALSE)
}

#Creates the 'master'
df_INVIVO_scenarioB_Master$ID<-trimws(df_INVIVO_scenarioB_Master$ID)

#Filters out Excluded Models
df_INVIVO_scenarioB <- df_INVIVO_scenarioB_Master %>%filter(!(ID %in% vec_exclude))

#==========================================================================================
# Final Output Formatting
#==========================================================================================

df_final_formatted <- df_INVIVO_scenarioB %>% 
#Extracts Group and ID from original ID column
  mutate(
    Group= str_remove(ID, "\\s*\\d+$"),
    ID_num= str_extract(ID, "\\d+$"),
    Variable=METRIC,
    Value=VALUE
  ) %>%
  
  #Filters down to target measurments
  filter(Variable %in% target_measurements) %>%
  #caculates Baseline and Change grouped by ID and Variable
  group_by(ID_num, Group, Variable) %>% 
  mutate(Baseline = if(any(Timepoint== "Baseline"))Value[Timepoint=="Baseline"][1] else NA,
         Change= Baseline - Value) %>%
  mutate(
    Timepoint = case_when(
      Timepoint %in% c("20%")   ~ "1st Bleed",
      Timepoint %in% c("15%")  ~ "2nd Bleed",
      Timepoint %in% c("10%") & MODEL != "B-PRC" ~ "1st Bleed",
      Timepoint %in% c("10%") & MODEL == "B-PRC" ~ "3rd Bleed",
      Timepoint %in% c("7.5%") ~ "2nd Bleed",
      Timepoint %in% c("5%")  ~ "3rd Bleed",
      Timepoint %in% c("2.5%") ~ "4th Bleed",
      Timepoint %in% c("1 HR", "1H") ~ "1HR",
      Timepoint == "24 HR" ~ "24HR",
      TRUE ~ Timepoint
    )
  ) %>% 
  filter(Timepoint != "4th Bleed")%>% 
  ungroup() %>% 
  select(Group,ID= ID_num, Variable, Timepoint, Value, Baseline, Change)

final_excel_path<- file.path(analysis_ready_folder,"Anova_Ready_Data.xlsx")

Final_List <- split(df_final_formatted, df_final_formatted$Variable)

write.xlsx(Final_List,final_excel_path)
message("Final ANOVA ready data sent to: \n", final_excel_path)