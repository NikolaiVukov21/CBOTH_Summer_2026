
                                                                              ##################################
                                                                              #      Packages/ Libaries        #
                                                                              ##################################




required_packages<-c("dplyr","readxl", "tidyr","tidyverse", "tools","purrr","rstudioapi","REDCapR")

new_packages<-required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {install.packages(new_packages)}

invisible(lapply(required_packages,library,character.only = TRUE))

if(Excel_File_Path !=" "){
  Excel_File_Path<-gsub("\\\\","/",Excel_File_Path,ignore.case=FALSE)
}



  #Allows users to select the folder with all the excel sheets
ifelse(Excel_File_Path==" ",Folder_Path <- selectDirectory(),Folder_Path<-Excel_File_Path)

  #Catches / Selects all excel files from choosen folder
excel_files<-list.files(Folder_Path,pattern="\\.xlsx?$",full.names=TRUE,recursive=FALSE)
 
  #Gets parent directory
Parent_Directory<-dirname(Directory)

  #Final Results folder
Results_Folder<-file.path(Parent_Directory,paste("Output Sheets"))

if(!dir.exists(Results_Folder)){
  dir.create(Results_Folder,recursive = TRUE, showWarnings = FALSE)
}

  #Finding The data range of the input folders
  find_long_data_range<-function(file_path, sheet_name, na_strings=nas_instance){
    
    #Establishing clean and valid headers for later comparision
    clean_header<-function(x) gsub("[^a-z0-9]","",tolower(trimws(as.character(x))))
    valid_headers<-c("timepoint","event")
    
    #'Walks' the vector, returning the index of the last value
    
    last_contiguous<-function(vals, start){
      last<-start
      i<-start+1
      while(i<=length(vals) && !is.na(vals[i]) && trimws(vals[i])!=""){
        last<-i
        i<-i+1
      }
      last
    }
    
    #Pulls all of column A and looks for the valid header role
    col_a<-suppressMessages(read_excel(
      file_path,sheet=sheet_name,
      range=cell_limits(c(1,1),c(NA,1)),
      col_names= FALSE, col_types="text",na=na_strings, .name_repair="minimal"
    ))[[1]]
    
    header_row<- which(vapply(col_a,clean_header,character(1)) %in% valid_headers)[1]
    if(is.na(header_row)){
      stop(paste0("Could not find a Timepoint/Event header in column A of sheet '",sheet_name,"'"))
    }
    
    last_row<-last_contiguous(col_a,header_row)
    
    #reads across the header row to find where the variable columns stop
    
    header_vals<- suppressMessages(read_excel(file_path, sheet=sheet_name,
                                    range=cell_limits(c(header_row,1),c(header_row,NA)),
                                    col_names=FALSE,col_types="text",na=na_strings, .name_repair="minimal"))
    
    header_vals<- as.character(unlist(header_vals[1, ]))
    last_cols<-last_contiguous(header_vals, 1)
    cell_limits(c(header_row,1 ),c(last_row,last_cols))
  }

                                                                              ##################################
                                                                              #         Excel Cleaning         #
                                                                              #           Extracting           #
                                                                              ##################################

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


process_lowres_rabbitdata<- function(file_path,arm){
  
  #Getting each excel sheet
  sheets<-excel_sheets(file_path)
  
  #Excluding the template sheet
  sheets <- sheets[!grepl("template",sheets,ignore.case = TRUE)]

  
  #Trying to capture these excel entries to treat as blanks
  nas_instnce<-c("", " ","\u00A0", "NA", "N/A", "Not available","unk","did not work", "didnt work", "this does nt seem right", "why????")
  
  #Mapping each sheets to it's variables
  map_dfr(sheets,function(sheet_name){
    
    #Extracting information/ Meta data for "baseline_data"
    #B column
    meta_B<-suppressMessages(read_excel(file_path,sheet=sheet_name,range="B4:B9",col_names=c("val"),trim_ws=TRUE,na=nas_instnce,.name_repair = "minimal"))
    
    #F column
    meta_F<-suppressMessages(read_excel(file_path,sheet=sheet_name,range="F4:F5",col_names=c("val"),trim_ws=TRUE,na=nas_instnce,.name_repair = "minimal"))
    
    #Retrieves baseline information from input excel sheet
    subject_id_val<-as.character(meta_B$val[1])
    rabbit_weight_val<- as.numeric(gsub("[^0-9.]","",meta_B$val[2]))
    
    #Had issues with date converting to the number of days after January 1,1900
    date_raw<-meta_B$val[3]
    
    #Converts transfusion date into REDCap's Format (YYYY-MM-DD) 
    transfusion_date_cld<- if(is.na(date_raw)){NA_character_
      
    }else if (inherits(date_raw,"POSIXt") || inherits(date_raw,"Date")){
      format(as.Date(date_raw),"%Y-%m-%d")
      
    }else if (grepl("^[0-9]{5}",as.character(date_raw))){
     format(as.Date(as.numeric(date_raw),
                    origin="1899-12-30"),
                             "%Y-%m-%d") 
    } else{
      parsed_date<-suppressWarnings(parse_date_time(as.character(date_raw),
                                                    orders=c("ymd","mdy","dmy","ymd HMS","mdy HMS","dmy HMS"),quiet=TRUE
        )
      )
      
     if(is.na(parsed_date)){
      warning("Could not parse transfusion date: ", as.character(date_raw))
      NA_character_
     } else{
       format(parsed_date,"%Y-%m-%d")
     }
    }
    
    #Extracting baseline variables
    bld_volume_val<-as.numeric(meta_B$val[4])
    transf_vol_val<-as.numeric(meta_B$val[5])
    Tele_ID<-as.numeric(meta_B$val[6])
    
    #Handles Exclusion
    exclude_raw<-tolower(trimws(as.character(meta_F$val[1])))
    exclusion_reason_val<-trimws(as.character(meta_F$val[2]))
    
    is_excluded<-grepl("^(1|y|yes|t|true|exclude|excluded)$",exclude_raw)
    has_reason<-!is.na(exclusion_reason_val) & exclusion_reason_val !=" "
    
    exclude_val<-ifelse(is_excluded | has_reason,1,0)
    
    #Scenario C extractions:
    damp_ld_info<-NA;damp_gtt_info<- NA
    damp_ld_5min_val <- NA; damp_ld_4_hrs_val <- NA
    m_vol_5min_val <- NA; m_vol_4hr_val <- NA
    braintissue_vol_5min_val <- NA; braintissue_vol_4hr_val <- NA 
    total_damp_5min_val <- NA; total_damp_4hr_val <- NA
    bld_vol_5min_val <- NA; bld_vol_4hr_val <- NA
    
    if (arm=="Scenario C"){
      
      #K Column
      meta_K<-suppressMessages(read_excel(file_path,sheet=sheet_name,range="K5:K6",col_names=c("val"),trim_ws=TRUE,na=nas_instnce,.name_repair = "minimal"))
      
      #O-P Column
      meta_OP<-suppressMessages(read_excel(file_path,sheet=sheet_name,range="O5:P7",col_names=c("val_o","val_p"),trim_ws=TRUE,na=nas_instnce,.name_repair = "minimal"))
      
      #S-T Column
      meta_ST<-suppressMessages(read_excel(file_path,sheet=sheet_name,range="S5:T6",col_names=c("val_s","val_t"),trim_ws=TRUE,na=nas_instnce,.name_repair = "minimal"))
      
      #Checks if the columns exists before extracting data
      clean_extraction<- function(df,col_name,row_idx){
        if(col_name %in% names(df) && nrow(df) >= row_idx){
          return(as.numeric(df[[col_name]][row_idx]))
        } else{
          return(NA)
        }
      }
      
      #Gets variables of interest in Scenario C
      damp_ld_info_val<-clean_extraction(meta_K,"val",1)
      damp_gtt_info_val<-clean_extraction(meta_K,"val",2)
      
      
      
      damp_ld_5min_val<-clean_extraction(meta_OP,"val_o",1)
      damp_ld_4_hrs_val<-clean_extraction(meta_OP,"val_p",1)
      
      braintissue_vol_5min_val<-clean_extraction(meta_OP,"val_o",2)
      braintissue_vol_4hr_val<-clean_extraction(meta_OP,"val_p",2)
      
      total_damp_5min_val<-clean_extraction(meta_OP,"val_o",3)
      total_damp_4hr_val<-clean_extraction(meta_OP,"val_p",3)
      
      
      m_vol_5min_val<-clean_extraction(meta_ST,"val_s",1)
      m_vol_4hr_val<-clean_extraction(meta_ST,"val_t",1)
      
      bld_vol_5min_val<-clean_extraction(meta_ST,"val_s",2)
      bld_vol_4hr_val<-clean_extraction(meta_ST,"val_t",2)
    }
    
    #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++       
    
    
    ranges<-find_long_data_range(file_path,sheet_name,na_strings=nas_instnce)
    
    
    long_data <- suppressMessages(read_excel(
      file_path,
      range=ranges,
      sheet=sheet_name,
      trim_ws=TRUE,
      na=nas_instnce, #Na's
      .name_repair="unique"
    ))
    
    
    #Convers all headers to lowercase
    names(long_data)<- tolower(gsub("\\.","",names(long_data)))
    
    #Cleans up the data and maps the messy headers to the REDCap variables
    long_data<- long_data %>% 
      rename(
        timepoint=any_of(c("timepoint","event","time_point")),
        
        #Catches basic vitals
        time=any_of(c("clock_time","time","clocktime","clock time")),
        body_temp= any_of(c("temp","body_temp")),
        bpm=any_of(c("bpm","heartrate")),
        
        
        #Catches Teg columns
        r_min = any_of(c("r-", "r_time", "r-time", "r_min","ckhr time")),
        k_min = any_of(c("k-", "k_time", "k-time", "k_min","ckh k")),
        angle_deg=any_of(c("angle","angledeg","degree","ckh angle")),
        ma_mm=any_of(c("ma","mamm","ckh ma")),
        
        #Catches COAG columns
        aptt= any_of(c("APTT","appt")),
        pt= any_of(c("pt","PT")),
        tt= any_of(c("tt","TT")),
        fib= any_of(c("fib","FIB")),
        
        #Additional catches
        pc02 = any_of(c("pco2", "pc02")),
        hgb = any_of(c("hb", "hgb", "hemoglobin"))
      ) %>% filter(!is.na(timepoint)) %>% 
      
      mutate(across(c(-timepoint,-time), ~ as.integer(as.numeric(.)))
      ) %>%
      
      #Fixing dynamica naming of timepoints
      mutate(timepoint=as.character(timepoint),
             timepoint=tolower(timepoint),
             timepoint=gsub("hr","h",timepoint),
             timepoint=gsub(" ","",timepoint),
             tp_num=suppressWarnings(as.numeric(gsub("%","",timepoint))) #Creates a temporarily numeric column
      ) %>% 
      
      #Had an issue where 10% is defined as 'First Bleed' in one procedure, but then 'Third Bleed' in another
      mutate(
        is_format_2 = any(tp_num==20 | tp_num == 0.2,na.rm=TRUE), 
        
        timepoint=case_when(
          
          #Format 2 logic: 10% is the third bleed
          is_format_2 & near(tp_num,20) ~ "first_bleed",
          is_format_2 & near(tp_num,0.2) ~ "first_bleed",
          is_format_2 & near(tp_num,15) ~ "second_bleed",
          is_format_2 & near(tp_num,0.15) ~ "second_bleed",
          is_format_2 & near(tp_num,10) ~ "third_bleed",
          is_format_2 & near(tp_num,0.1) ~ "third_bleed",
          
          #Format 1 logic: 10% is the First bleed
          !is_format_2 & near(tp_num,10) ~ "first_bleed",
          !is_format_2 & near(tp_num,0.1) ~ "first_bleed",
          !is_format_2 & near(tp_num,7.5) ~ "second_bleed",
          !is_format_2 & near(tp_num,0.075) ~ "second_bleed",
          !is_format_2 & near(tp_num,5.0) ~ "third_bleed",
          !is_format_2 & near(tp_num,0.05) ~ "third_bleed",
          !is_format_2 & near(tp_num,2.5) ~ "fourth_bleed",
          !is_format_2 & near(tp_num,0.025) ~ "fourth_bleed",
          
          TRUE ~ timepoint
        )
      ) %>%
      select(-tp_num,-is_format_2) #removes temp columns
    
    #Safety check
    if(nrow(long_data)==0) return(NULL)
    
    
    #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++    

    
                                                                              ##################################
                                                                              #    Final DataFrame Payload     #
                                                                              ##################################
    
    
    
    cleaned_data<-long_data %>% 
      mutate(subject_id=subject_id_val,
             
             #ReDCap requires "_arm_#_ for each timepoint/event
             redcap_event_name=case_when(
               arm=="Scenario A"~paste0(timepoint,"_arm_1"),
               arm=="Scenario B"~paste0(timepoint,"_arm_2"),
               arm=="Scenario C"~paste0(timepoint,"_arm_3"),
               TRUE~ timepoint
             ),      
             
             #Imports baseline data
             rabbit_weight=ifelse(timepoint=="baseline",rabbit_weight_val,NA),
             transfusion_date=ifelse(timepoint=="baseline",transfusion_date_cld,NA),
             bld_volume=ifelse(timepoint=="baseline",bld_volume_val,NA),
             transf_vol=ifelse(timepoint=="baseline",transf_vol_val,NA),
             telemetry_id=ifelse(timepoint=="baseline",Tele_ID,NA),
             exclude=ifelse(timepoint=="baseline",exclude_val,NA),
             exclusion_reason=ifelse(timepoint=="baseline",exclusion_reason_val,NA),
             
             
             #Imports baseline_c data
             damp_ld_info=ifelse(arm=="Scenario C" & timepoint=="baseline",damp_ld_info_val,NA),
             damp_gtt_info=ifelse(arm=="Scenario C" & timepoint=="baseline",damp_gtt_info_val,NA),
             damp_ld_5min=ifelse(arm=="Scenario C" & timepoint=="baseline",damp_ld_5min_val,NA),
             damp_ld_4_hrs=ifelse(arm=="Scenario C" & timepoint=="baseline",damp_ld_4_hrs_val,NA),
             
             braintissue_vol_5min=ifelse(arm=="Scenario C" & timepoint=="baseline",braintissue_vol_5min_val,NA),
             
             braintissue_vol_4hr=ifelse(arm=="Scenario C" & timepoint=="baseline",braintissue_vol_4hr_val,NA),
             total_damp_5min=ifelse(arm=="Scenario C" & timepoint=="baseline",total_damp_5min_val,NA),
             total_damp_4hr=ifelse(arm=="Scenario C" & timepoint=="baseline",total_damp_4hr_val,NA),
             m_vol_5min=ifelse(arm=="Scenario C" & timepoint=="baseline",m_vol_5min_val,NA),
             m_vol_4hr=ifelse(arm=="Scenario C" & timepoint=="baseline",m_vol_4hr_val,NA),
             bld_vol_5min=ifelse(arm=="Scenario C" & timepoint=="baseline",bld_vol_5min_val,NA),
             bld_vol_4hr=ifelse(arm=="Scenario C" & timepoint=="baseline",bld_vol_4hr_val,NA)) %>% 
      
      #Selects baseline and baseline_c data only
      select(subject_id,redcap_event_name,rabbit_weight,transfusion_date,bld_volume,transf_vol,telemetry_id,exclude,exclusion_reason,
             damp_ld_info,damp_gtt_info,damp_ld_5min,damp_ld_4_hrs,braintissue_vol_5min,braintissue_vol_4hr,total_damp_5min,total_damp_4hr,m_vol_5min,m_vol_4hr,bld_vol_5min,bld_vol_4hr,
             
             #Selects dynamically timeline data
             any_of(c(
               "time", "map", "bpm", "body_temp", 
               "ph", "pc02", "po2", "lac",
               "wbc", "rbc", "hgb", "hct", "plt",
               "ggt", "ast", "alt", "amy", "ldh", "crea", "bun", "glu", "tg",
               "r_min", "k_min", "angle_deg", "ma_mm",
               "aptt","pt","tt","fib"
             ))
      )
    
    
    
    cleaned_data <-cleaned_data %>%
      mutate(time=normalize_Clock_time(time))
    
    
    return(cleaned_data)
  })
}

#Combining Final REDCap Data
final_redcap_data<-map_dfr(excel_files,function(file){
  
  file_name<-basename(file)
  
  scenario_sheet<-toupper(strsplit(file_name,split="[\\._-]", fixed=FALSE)[[1]][1])
  
  if(grepl("C",scenario_sheet)){
    current_arm<-"Scenario C"
  } else if (grepl("A",scenario_sheet)){
    current_arm<-"Scenario A"
  }else if (grepl("B",scenario_sheet)){
    current_arm<-"Scenario B"
  } else{
    current_arm<- NA
  }
  
  #Prints a warning if arm wasn't found
  if(!is.na(current_arm)){
    message("Processing: ",file_name,"-> Assigned to:",current_arm)
    return(process_lowres_rabbitdata(file_path = file, arm = current_arm))
  }else{
    warning("Skipped: Could not determine Arm from Filename: ",file_name, " (Prefix found: '", Scenario_sheet, "')")
    return(NULL)
  }
})

#Fixes Event Name
final_redcap_data<- final_redcap_data %>% 
  mutate(
    
    redcap_event_name=case_when(
      
      #Scenario B Event Renaming
      redcap_event_name=="eob_arm_2"~"end_of_bleed_arm_2",
      redcap_event_name=="pre-death_arm_2"~"predeath_arm_2",
      
      #Scenario C Event Naming
      redcap_event_name=="1h_arm_3"~"1h_post_damp_arm_3",
      redcap_event_name=="3h_arm_3"~"3h_post_damp_arm_3",
      redcap_event_name=="6h_arm_3"~"6h_post_damp_arm_3",
      redcap_event_name=="24h_arm_3"~"24h_post_damp_arm_3",
      redcap_event_name=="48h_arm_3"~"48h_post_damp_arm_3",
      redcap_event_name=="72h_arm_3"~ "72h_post_damp_arm_3",
      
      TRUE~redcap_event_name
    ),
    
    #Marking Completion Variables
    
    #Just caculation fields, should be completed automatically
    fluids_and_drugs_data_acredit_complete=ifelse(grepl("baseline",redcap_event_name),2,NA),
    
    #Checks if any columns contaisn data, marks 2 if all fields contain data  
    
    #Baseline Instruments Checks first 
    baseline_data_complete=ifelse(
      grepl("baseline",redcap_event_name),
      ifelse(rowSums(!is.na(select(.,any_of(c("rabbit_weight", "transfusion_date", "bld_volume", "transf_vol", "exclude")))))>0,1,0), 
      NA
    ),
    
    baseline_data_c_dbb1_complete=ifelse(
      grepl("baseline",redcap_event_name) & grepl("arm_3",redcap_event_name),
      ifelse(rowSums(!is.na(select(.,any_of(c("damp_ld_info", "damp_gtt_info", "damp_ld_5min", "damp_ld_4_hrs", "braintissue_vol_5min", "braintissue_vol_4hr", "total_damp_5min", "total_damp_4hr", "m_vol_5min", "m_vol_4hr", "bld_vol_5min", "bld_vol_4hr")))))>0,1,0), 
      NA
    ),
    
    #Code to mark a section as incomplete (0) or complete (2) in REDCap
    #Returns 0 if a variable is empty, 2 if all variables have a value
    clinical_vitals_complete=ifelse(rowSums(!is.na(select(.,any_of(c("time", "map", "bpm", "body_temp")))))>0,1,0),
    
    abg_complete=ifelse(rowSums(!is.na(select(.,any_of(c("ph", "pc02", "po2", "lac")))))>0,1,0),
    
    cbc_complete=ifelse(rowSums(!is.na(select(.,any_of(c("wbc", "rbc", "hgb", "hct", "plt")))))>0,1,0),
    
    cmp_complete=ifelse(rowSums(!is.na(select(.,any_of(c("ggt", "ast", "alt", "amy", "ldh", "crea", "bun", "glu", "tg")))))>0,1,0),
    
    coagteg_complete=ifelse(rowSums(!is.na(select(.,any_of(c("r_min", "k_min", "angle_deg", "ma_mm")))))>0,1,0),
    
    coag_complete=ifelse(rowSums(!is.na(select(.,any_of(c("aptt", "pt", "tt", "fib")))))>0,1,0)
  )





                                                                              ##################################
                                                                              #       Output / Extraction      #
                                                                              ##################################




#Extracting Excel Sheet
date<-Sys.Date()

#Setups where the file is being saved
output_filepath <- file.path(Results_Folder, paste("REDCap_Import_",date,".csv"))

#Exporting CSV file to path, ensures all "NA's" are blank
write_csv(final_redcap_data, file=output_filepath, na = "")

#Automated REDCap API upload

#Retrieves token
api_token<-Sys.getenv("REDCAP_API_TOKEN")

#REDCap project URL
redcap_url<-"https://umbredcap.umaryland.edu/api/"

#checks for the token
if(api_token==""){
  warning("REDCAP_API_TOKEN not found, skipping REDcap Upload, please run R_Setup_Script.R")
} else{
  message("Uploading Pipeline")
  upload_result<-redcap_write(
    ds=final_redcap_data,
    redcap_uri=redcap_url,
    token=api_token
  )

  message(upload_result$outcome_message)
}

