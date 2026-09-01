


#Checking and loading needed libraries
if(!requireNamespace("readxl", quietly = TRUE)) install.packages ("readxl")
if(!requireNamespace("tidyverse", quietly = TRUE)) install.packages ("tidyverse")
if(!requireNamespace("purrr", quietly = TRUE)) install.packages ("purrr")
if(!requireNamespace("rstudioapi", quietly = TRUE)) install.packages ("rstudioapi")
if(!requireNamespace("knitr", quietly = TRUE)) install.packages ("knitr")
if(!requireNamespace("stringr", quietly = TRUE)) install.packages ("stringr")

library(readxl)
library(tidyverse)
library(purrr)
library(rstudioapi)
library(knitr)
library(stringr)


#Log File Name
log_filename <- "Scenario A-Experimental Subject Log-UMB.xlsx"

#Let's the user choose the folder that has the datasets
Folder_Path <- selectDirectory()

#Testing File Path
#file.path

#Creating a list for the models 
model_results<- list()

#Creating a lowres folder
#NEED TO FIX: creates a new 'lowres' folder, even if the parent folder name is 'lowres'
if(tolower(basename(Folder_Path))!="lowres"){
  lowres_folder<-file.path(Folder_Path,"lowres")
} else{
  lowres_folder<-Folder_Path
}

if (!dir.exists(lowres_folder)){
  dir.create(lowres_folder,recursive=TRUE,showWarnings = FALSE)
}

excel_files<-list.files(Folder_Path,pattern="\\.xlsx?$",full.names=TRUE,recursive=FALSE)

if(length(excel_files)>0 && Folder_Path !=lowres_folder){
  dest_files<-file.path(lowres_folder,basename(excel_files))
  file.rename(from=excel_files,to=dest_files)
}

#Establishing a function/ pipeline to extract and clean for the targeted excel files
#This function was created using the works of Yuxin Wang, including but not limited to:
#'df_domains','df_all', and 'df_final'

process_lowres_rabbitdata<- function (data_file, model,folder_path){
  
  #Builds a path to the lowres file
  file_path<-file.path(lowres_folder,paste0(data_file,".xlsx"))
  
  #Reads the sheets from that file
  sheets <- excel_sheets(file_path)
  
  
  df_all<-map_dfr(sheets,function(sheet){
    read_excel(file_path,range="A13:BA20",sheet=sheet,trim_ws=T,
               na=c("", " ","\u00A0", "NA", "N/A", "Not available","unk","did not work", "didnt work", "this does nt seem right", "why????"),
               .name_repair = function(x) gsub(" ", "_", x)) %>%
      mutate(ID=sheet,MODEL=model)
  })
  
  #Cleans and Standarizes the columns name
  names(df_all) <- make.names(names(df_all),unique=TRUE)
  
  #Builds a lookup table for variables
  df_domains<-as.data.frame(
    
    #Gathers the file's Assay, units, and measurments
    t(read_excel(file_path,
                 range="C11:BA13",
                 sheet=sheets[1],
                 na="",
                 col_names=FALSE))
  ) %>% 
    #Cleans up Variable name issues
    rename(GROUP = V1, UNITS = V2, METRIC = V3) %>% 
    fill(GROUP, .direction = "down") %>%
    mutate(METRIC = gsub(" ", "_", as.character(METRIC))) %>%
    mutate(METRIC = gsub("%", "X.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("R-", "R.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("K-", "K.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("IL-", "IL.", as.character(METRIC))) %>%
    mutate(METRIC = gsub("MCP-", "MCP.", as.character(METRIC))) %>%
    #Create complex superscript expression
    mutate(
      UNITS = as.character(UNITS)
      #    ,UNITS = gsub("10\\^3", "10^3", UNITS),
      #    UNITS = gsub("10\\^6", "10^6", UNITS),
      #    UNITS = gsub("mm\\^3", "mm^3", UNITS)
    )
  
  #Final Dataset
  df_final <- df_all %>% 
    fill(Timepoint, .direction = "down") %>% 
    pivot_longer(MAP:Troponin, values_to = "VALUE", names_to = "METRIC") %>%
    left_join(df_domains, by = "METRIC")  %>% 
    filter(!is.na(VALUE)) %>%
    select(-any_of("Measurement_."))
  
  return (df_final)
}


df_log<-read_excel(file.path(lowres_folder,log_filename),
                   range="A1:O250",sheet=2, na=c(""),.name_repair=function(x)gsub(" ","_",x)) %>% 
  rename(INCLUDE='In/Excluded',INTERNAL='Internal?') %>% 
  mutate(ID=paste0(Group_Name," ",ID))

#Grabs all files in 'lowres' folder
all_files<-list.files(lowres_folder,pattern = "\\.xlsx?$",full.names = FALSE)

for (f in all_files){
  if(f==log_filename){
    next
  }
  #Removes the ending '.xlsx' to get a clean file name
  data_file<-sub("\\.xlsx?$","",f)
  model_name<-sub(".*- A-","",data_file) #Dynamically names the new model
  
  #Avoids an excel if it's corrupted
  df_result<-tryCatch({process_lowres_rabbitdata(data_file=data_file,model=model_name,folder_path=lowres_folder)},
                      error=function(e){
                        return(NULL)
                      })
  
  
  if(!is.null(df_result)){
    var_name<-paste0("df_",model_name)
    model_results[[var_name]]<-df_result
  }
  
}

#Used to create dynamical df's with and without the "Internal" column
vec_internal<-df_log %>% filter(INCLUDE=="Included" & !is.na(INTERNAL)) %>% pull(ID)
vec_include<-df_log  %>% filter(INCLUDE == "Included" & is.na(INTERNAL))  %>% pull(ID)

#Creates a folder path for "analysis_read_data"
analysis_ready_folder<-file.path(lowres_folder,"analysis_ready_data")

if(!dir.exists(analysis_ready_folder)|| length(analysis_ready_folder)==0){
  dir.create(analysis_ready_folder,recursive=FALSE,showWarnings = FALSE)
}

#Creates the 'master'
df_lowres_scenarioA_Master<-bind_rows(model_results) %>% filter(!(is.na(METRIC)))

df_lowres_scenarioA_Master$ID<-trimws(df_lowres_scenarioA_Master$ID)
write_csv(df_lowres_scenarioA_Master,file.path(analysis_ready_folder,"df_lowres_scenarioA_Master.csv"))

df_lowres_scenarioA_internal<-df_lowres_scenarioA_Master |> filter(ID %in% vec_internal)
write_csv(df_lowres_scenarioA_internal,file.path(analysis_ready_folder,"df_lowres_scenarioA_internal.csv"))

df_lowres_ScenarioA<-df_lowres_scenarioA_Master |> filter(ID%in% vec_include)
write_csv(df_lowres_ScenarioA,file.path(analysis_ready_folder,"df_lowres_ScenarioA.csv"))


