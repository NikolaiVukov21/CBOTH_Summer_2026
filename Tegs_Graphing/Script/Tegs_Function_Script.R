
print("Checking and Loading Packages")


                                                                              ##################################
                                                                              #      Packages/ Libaries        #
                                                                              ##################################


#Checks for required packages, install them if missing
required_packages<-c("agricolae", "dplyr", "ggplot2", "ggsignif", "knitr",
"openxlsx", "patchwork", "readxl", "stringr", "tidyr",
"tidyverse", "gt", "webshot2", "chromote","tools")


new_packages<-required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {install.packages(new_packages)}

invisible(lapply(required_packages,library,character.only = TRUE))

print("Packages Loaded")
print("Loading the Excel Sheet")


  # Data Reform: TEG-Hemodilutions 
  #*Antonio Renaldo
  #*Last Updated: 06/16/2026*
  






                                                                              ##################################
                                                                              # Extracting & Cleaning Database #
                                                                              #Establishing Output Folder Paths#
                                                                              ##################################

  #---- Import----
  file_path <- file.choose()
  
  sheet_name <- "Original"
  
  data <- read_excel(file_path, sheet = sheet_name)
  
  
  
  #---- Split Sample Description----
  
  
  
  data_sep <- data %>%
    extract(
      SAMPLEDESCRIPTION,
      into = c("Exp", "Subject", "HMT_model", "Hb", "EM_Hb", "Alb", "Version_v1", "Notes"),
      regex = "^([A-Za-z]+)[-_](\\d+)[-_]([^\\-_]+)(?:[-_](\\d+))?(?:-'(\\d+))?(?:-\"([A-Za-z]))?[-_]((?:v\\d+(?:\\.\\d+)?)|[A-Za-z]+)(?:\\*(.*))?$",
      remove = FALSE
    ) %>%
    mutate(
      Subject = as.integer(Subject),
      Hb = ifelse(is.na(Hb), "N/A", Hb)
    )
  
  
  
  #---- Clean Data----
  
  #Reorganize Variables
  data_sep <- data_sep %>%
    select(
      SAMPLEDESCRIPTION,
      Exp,
      Subject,
      HMT_model,
      Hb,
      EM_Hb,
      Alb,
      Version_v1,
      Notes,
      `R(min)`,
      `K(min)`,
      `Angle(deg)`,
      `MA(mm)`,
      `LY30(%)`,
      `TMA(min)`,
      `TEG ACT(sec)`,
      `SP(min)`,
      `G(d/sc)`,
      `E(d/sc)`,
      `TPI(/sec)`,
      `EPL(%)`,
      `A30(mm)`,
      `CL30(%)`,
      `A60(mm)`,
      `CL60(%)`,
      `LY60(%)`,
      `CLT(min)`,
      `A(mm)`,
      `PMA`,
      `LTE(min)`,
      everything()
    )
  
  #Fix the Negative K/MA values
  data_sep <- data_sep %>%
    mutate(
      `K(min)` = abs(`K(min)`),
      `MA(mm)` = abs(`MA(mm)`)
    )
  
  #Create organizing groups for  HMT_Model_01
  data_sep <- data_sep %>%
    mutate(
      HMT_model_01 = case_when(
        HMT_model == "fWB"      ~ 1,
        HMT_model == "PRP"      ~ 2,
        HMT_model == "PPP"      ~ 3,
        HMT_model == "1xFDP"    ~ 4,
        HMT_model == "FDP:Buff" ~ 5,
        HMT_model == "EMv1"     ~ 6,
        HMT_model == "EMv2"     ~ 7,
        HMT_model == "EMv3"     ~ 8,
        HMT_model == "EMv4"     ~ 9,
        TRUE ~ NA_real_
      ))
  
  #Rearrange & Sort data
  data_sep <- data_sep %>%
    arrange(
      Subject,
      HMT_model_01,
      desc(as.numeric(Hb)),
      EM_Hb,
      Alb,
      Version_v1
    )
  
  
  
  #---- GraphPad Pivot----
  
  
  data_gp <- data_sep %>%
    mutate(
      HMT_label = case_when(
        HMT_model == "fWB" & Hb == "N/A" ~ "fWB",
        TRUE ~ paste0(HMT_model, " (", Hb, ")")
      )
    ) %>% ##modify to create separators for EM_Hb & Alb
    pivot_wider(
      id_cols = c(Exp, Subject, Version_v1),
      names_from = HMT_label,
      values_from = c(
        `R(min)`,
        `K(min)`,
        `Angle(deg)`,
        `MA(mm)`,
        `LY30(%)`,
        `TMA(min)`,
        `TEG ACT(sec)`
      ),
      values_fn = ~ .[1]   # ✅ TAKE FIRST VALUE (prevents list columns)
    ) %>%
    rename_with(
      ~ sub("^(.+?)_(.+)$", "\\2 \\1", .x),
      -c(Exp, Subject, Version_v1)
    )
  
  
  #----Export to Excel----
  
  # Load workbook
  wb <- loadWorkbook(file_path)
  
  clean_df <- function(df) {
    df %>%
      mutate(across(everything(), ~ {
        if (is.list(.)) as.character(.) else .
      }))
  }
  
  
  processed_sheets<- list("Processed_Data"=clean_df(data_sep))
  
  for (sheet_name in names(processed_sheets)){
    if (sheet_name %in% names(wb)){
      removeWorksheet(wb,sheet_name)
    }
    addWorksheet(wb,sheet_name)
    writeData(wb,sheet=sheet_name,x=processed_sheets[[sheet_name]])
  }  
  saveWorkbook(wb,file_path,overwrite=TRUE)
  
  #Graph Pad
  
  Graphpadwb<-createWorkbook()
  
  addWorksheet(Graphpadwb,"GraphPad")
  
  writeData(
    Graphpadwb,
    sheet="GraphPad",x=clean_df(data_gp)
  )
  

  
  #Creates a unique result folder for each excel sheet
  
  #Gets full file name
  Full_File_Name<-basename(file_path)
  
  #Strips '.xlsx'
  ExcelFile_Name<-file_path_sans_ext(Full_File_Name)
  
  #Get's the parent directory 
  #To make the result folder a separate path
  Parent_Directory<-dirname(Target_Directory)
  
  Results_Folder<-file.path(Parent_Directory,"Output Files",ExcelFile_Name)
  
  if(!dir.exists(Results_Folder)){
    dir.create(Results_Folder,recursive = TRUE, showWarnings = FALSE)
    
    
    Graphpad_Output_Path<-file.path(Results_Folder,"GraphPad_Export.xlsx")
  saveWorkbook(wb,Graphpad_Output_Path,overwrite=TRUE)  
    
  }

print("Database Loaded")
print("Loading Custom Functions")



                                                                              ##################################
                                                                              #      Universal Functions       #
                                                                              ##################################

  #Creating a dataframe (Exclusions are removed
  Cleaned_df<-read_excel(file_path,sheet="Cleaned_Data") %>% 
    filter(Exclude_Instance %in% 0 | is.na(Exclude_Instance)) %>%  mutate( across(where(is.character), ~na_if(., "NA")))
  
  
  variables= c("R(min)","K(min)","Angle(deg)","MA(mm)")



print("Loading 'Albumin Detection'")


  #++++++++++++++++++++++++++++++++++++Seperator++++++++++++++++++++++++++++++++++++++
  
  #Function for 'Albumin' detection
  ADetection<-function(data){
    
    data<-data|> mutate( across(where(is.character), ~na_if(., "NA")))
    
    "Alb" %in% colnames(data) && any(grepl("A",data$Alb[!is.na(data$Alb)]))
  }
  
  #++++++++++++++++++++++++++++++++++++Seperator++++++++++++++++++++++++++++++++++++++


print("Loading Round Statistics")


  ExportGroupStats<-function(data){
    
    #Removes temporarily 'headless' chrome popups
    #Credit: GeminiAI
    cleanup_headless_chrome <- function() {
      if(requireNamespace("chromote",quietly=TRUE)&& chromote::has_default_chromote_object()){
        try(chromote::default_chromote_object()$get_browser()$close(),silent = TRUE)
        
        gc()
      }
    }
    
    Defined_Grouping=c(ref_model,setdiff(unique(data$HMT_model),ref_model))
    
    RoundTables<-list()
    
    wb=createWorkbook()
    
    graphics.off()
    
    #Dynamically names the models
    Modeling_Values<-data %>% 
      filter((!str_detect(HMT_model,"CFF")),
             Subject %in% c(round1,round2,round3)) %>% 
      mutate(
        Hb=coalesce(Hb,EM_Hb),
        EMT_model=factor(HMT_model,levels=Defined_Grouping),
        stat_group=case_when(
          !is.na(Alb) & Alb=="A"~ paste(HMT_model, Hb,"A",sep="_"), #Albumin name assingment
          HMT_model==ref_model ~paste(HMT_model), #If ref model, skip
          TRUE ~ paste(HMT_model,Hb,sep="_")
        ), 
        stat_group=factor(stat_group), #Factoring by model (group) and HB (SubGroup)
        #Dynamically assigning names
        Round=case_when(
          Subject %in% round1~ "Round 1",
          Subject %in% round2~ "Round 2",
          Subject %in% round3~ "Round 3",
        )
      )
    
    #Reordering so that reference model goes first, than alphabetical
    all_groups<-unique(Modeling_Values$stat_group) 
    ordered_levels<- c(ref_model,sort(setdiff(all_groups,ref_model)))
    
    Modeling_Values<-Modeling_Values %>% 
      mutate(stat_group=factor(stat_group,levels=ordered_levels))
    
    #Helper Function to compute and format tables
    
    calc_tables<-function(df_sub,vars,remove_outliers){
      #Pivoting to longer format
      df_long<- df_sub %>% 
        select(stat_group, all_of(vars)) %>% 
        pivot_longer(cols=all_of(vars),names_to = "Var", values_to = "Value") %>% 
        filter(!is.na(Value))
      
      #Outlier Detection and removal
      
      if(remove_outliers){
        df_long <- df_long %>% 
          group_by(stat_group,Var) %>% 
          mutate(q1=quantile(Value, 0.25,na.rm=TRUE),q3=quantile(Value,0.75, na.rm=TRUE),i=IQR(Value, na.rm=TRUE), lower= q1-3*i, upper=q3+3*i) %>% 
          filter(Value>=lower & Value<=upper)  %>% 
          select(-q1,-q3,-i,-lower,-upper)%>% 
          ungroup()
      }
      
      #Caculate Base Statistics
      df_stats<-df_long %>% 
        group_by(stat_group,Var) %>% 
        summarise(
          Mean=round(mean(Value,na.rm=TRUE),2),
          SD=round(sd(Value,na.rm=TRUE),2),
          Median=round(median(Value,na.rm=TRUE),2),
          IQR=round(IQR(Value,na.rm=TRUE),2),
          .groups="drop"
        )
      
      #Excel Formatting 
      
      #Reshaping stats to wide format
      df_wide_excel<-df_stats %>% 
        pivot_wider(names_from=Var,values_from=c(Mean,SD,Median,IQR),
                    names_glue="{Var}_{.value}") %>%
        rename("Model"=stat_group) %>% 
        arrange(Model)
      
      #Ensuring the columns are the specificied order
      order_col_names<- c("Model",unlist(lapply(vars,function(v) paste0(v,c("_Mean","_SD","_Median","_IQR")))))
      
      #Ensures columns are selected safetly
      existing_cols<-intersect(order_col_names,names(df_wide_excel))
      df_final_excel<-df_wide_excel %>%  select(all_of(existing_cols))
      
      
      #GT Image Formatting
      df_final_gt<-df_final_excel
      
      for (v in vars){
        mean_col<-paste0(v,"_Mean")
        sd_col<-paste0(v,"_SD")
        med_col<-paste0(v,"_Median")
        iqr_col<-paste0(v,"_IQR")
        
        #Combines Mean and SD as well as Median and IQR
        if(mean_col %in% names(df_final_gt)&& sd_col %in% names(df_final_gt)){
          df_final_gt[[paste0(v,"@Mean  \n  SD")]] <- paste0(sprintf("%.2f", df_final_gt[[mean_col]]), " ± ",sprintf("%.2f",df_final_gt[[sd_col]])
          )
        } 
        
        if(med_col %in% names(df_final_gt) && iqr_col %in% names(df_final_gt)){
          df_final_gt[[paste0(v,"@Median  \n  IQR")]] <- paste0(sprintf("%.2f",df_final_gt[[med_col]]), " ± ",sprintf("%.2f",df_final_gt[[iqr_col]])
          )
        }
      }  
      order_col_names_gt<- c("Model",unlist(lapply(vars,function(v) paste0(v,c("@Mean  \n  SD","@Median  \n  IQR")))))
      
      #Ensures columns are selected safetly
      existing_cols_gt<-intersect(order_col_names_gt,names(df_final_gt))
      df_final_gt<-df_final_gt %>%  select(all_of(existing_cols_gt))
      
      return(list(excel_table=df_final_excel, gt_table=df_final_gt
      )) 
    }
    
    #Styles for wraping the text
    wrap_style <- createStyle(wrapText=TRUE, borderStyle= "medium",halign="center",valign="center")
    
    header_wrap_style<-createStyle(wrapText=TRUE,border="TopBottomLeftRight",halign="center",valign="center")
    
    #Creates the Excel sheets
    
    for (rd in c("Round 1","Round 2","Round 3")){
      #Filters for the current round
      df_rd<-Modeling_Values %>% filter(Round==rd)
      
      if(nrow(df_rd)==0) next #Skip sheets if there is no data
      
      #Generates Statistics Table
      results_with<-calc_tables(df_rd,variables,remove_outliers=FALSE)
      results_without<-calc_tables(df_rd,variables,remove_outliers=TRUE)
      
      tbl_with_excel<-results_with$excel_table
      tbl_without_excel<-results_without$excel_table
      
      tbl_with_gt<-results_with$gt_table
      tbl_without_gt<-results_without$gt_table
      
      #===Writing Data to excel===
      
      #Defining Sheet Names 
      sheet_with<-paste0(rd," (With Outliers)")
      sheet_without<-paste0(rd," (Without Outliers)")
      
      #Writing Data with Outliers
      addWorksheet(wb,sheet_with)
      writeData(wb,sheet_with,tbl_with_excel)
      
      addStyle(wb,sheet_with,header_wrap_style,rows=1,cols=1:ncol(tbl_with_excel),gridExpand=TRUE)
      
      addStyle(wb,sheet_with,wrap_style,rows=2:(nrow(tbl_with_excel)+1),cols=1:ncol(tbl_with_excel),gridExpand=TRUE)
      setColWidths(wb,sheet_with,cols=1:ncol(tbl_with_excel),widths=14)
      
      #Writing Data Without Outliers
      addWorksheet(wb,sheet_without)
      writeData(wb,sheet_without,tbl_without_excel)
      
      addStyle(wb,sheet_without,header_wrap_style,rows=1,cols=1:ncol(tbl_without_excel),gridExpand=TRUE)
      addStyle(wb,sheet_without,wrap_style,rows=2:(nrow(tbl_without_excel)+1),cols=1:ncol(tbl_without_excel),gridExpand=TRUE)
      setColWidths(wb,sheet_without,cols=1:ncol(tbl_without_excel),widths=14)
      
      #===Writing Data to Tables===
      
      #Table with outliers
      gt_table_with<-tbl_with_gt %>%
        gt() %>% 
        tab_spanner_delim(delim="@") %>% #Seperates the headers by the delim "@"
        tab_header(
          title= md(paste0("**",rd," (With Outliers)**")) 
        ) %>% 
        #Borders
        tab_options(
          table.border.top.color="black",table.border.top.width=px(2),
          heading.border.bottom.color="black",
          column_labels.border.bottom.color = "black",
          table.border.bottom.color = "black",table.border.bottom.width = px(2),
          heading.align="center",
          table_body.hlines.color = "transparent",
          table.margin.left = px(20),
          table.margin.right = px(20)) %>% 
        
        tab_style(style=cell_borders(sides="right",color="black",weight=px(1)),
                  locations=list(
                    cells_body(columns=c(2,4,6,8)),
                    cells_column_labels(columns=c(2,4,6,8))
                  )
        ) %>% 
        tab_source_note(source_note="Data are mean ± SD | Median ± IQR.") #Source Note
      
      
      
      #Writing a table without outliers
      gt_table_without<-tbl_without_gt %>%
        gt() %>% 
        tab_spanner_delim(delim="@") %>% #Seperates the headers by the delim "@"
        tab_header(
          title= md(paste0("**",rd," (Without Outliers)**")) 
        ) %>% 
        
        #Borders
        tab_options(
          table.border.top.color="black",table.border.top.width=px(2),
          heading.border.bottom.color="black",
          column_labels.border.bottom.color = "black",
          table.border.bottom.color = "black",table.border.bottom.width = px(2),
          heading.align="center",
          table_body.hlines.color = "transparent",
          table.margin.left = px(20),
          table.margin.right = px(20)) %>% 
        
        #Creates seperator lines between (mean/SD) and (Median/ IQR)
        tab_style(style=cell_borders(sides="right",color="black",weight=px(1)),
                  locations=list(
                    cells_body(columns=c(2,4,6,8)),
                    cells_column_labels(columns=c(2,4,6,8))
                  )
        ) %>% 
        tab_source_note(source_note="Data are mean ± SD | Median ± IQR.") #Source Note
      
      #Storing tables
      RoundTables[[paste0(rd,"_With")]] <-gt_table_with
      RoundTables[[paste0(rd,"_Without")]] <-gt_table_without
      
      #Creating Based Filepaths
      base_name_with<-paste0(gsub(" ","_",rd),"_With_Outliers")
      base_name_without<-paste0(gsub(" ","_",rd),"_Without_Outliers")
      
      #Creates seperate file paths for PNG and HTML
      
      PNG_Folder<- file.path(Results_Folder,"PNG_Output")
      HMTL_Folder<-file.path(Results_Folder,"HTML_Output")
      
      #Creating folder if it doesn't exists
      
      if(!dir.exists(PNG_Folder)){
        dir.create(PNG_Folder,recursive = TRUE, showWarnings = FALSE)}
        
        if(!dir.exists(HMTL_Folder)){
          dir.create(HMTL_Folder,recursive = TRUE, showWarnings = FALSE)}
      
      #Creating full File paths (Sending to Results_Folder)
      png_path_with<-file.path(PNG_Folder,paste0(base_name_with,".png"))
      png_path_without<-file.path(PNG_Folder,paste0(base_name_without,".png"))
      
      html_path_with<-file.path(HMTL_Folder,paste0(base_name_with,".html"))
      html_path_without<-file.path(HMTL_Folder,paste0(base_name_without,".html"))
      
      #Saving as PNG
      gtsave(gt_table_with,filename=png_path_with,zoom=2,vwidth=1500,expand=10)
      gtsave(gt_table_without,filename=png_path_without,zoom=2,vwidth=1500,expand=10)
      
      
      #Saving as HTML (Copyable)
      gtsave(gt_table_with,filename=html_path_with)
      gtsave(gt_table_without,filename=html_path_without)
      
    }
    
    
    
    #Saves excel sheet
    excel_output_path<-file.path(Results_Folder,"Teg_Subject_Statistics.xlsx")
    saveWorkbook(wb,excel_output_path,overwrite=TRUE)
    
    cleanup_headless_chrome()
    
    return(RoundTables)
    
  }

  #++++++++++++++++++++++++++++++++++++Seperator++++++++++++++++++++++++++++++++++++++

print("Loading Outlier Detector")


  #Adds function to detect outliers and outputs a table
  DetectOutliers<-function(data){
    
    #Capturing the raw variable name
    #Using regex to covert from 'Round1_DF' to 'Round 1'
    Round_Name<-gsub("Round(\\d+)_DF","Round \\1",deparse(substitute(data)),ignore.case=TRUE)
    
    #Title of table
    Table_title<-paste(Round_Name,"Outlier Table")
    
    #Detects and outputs outliers
    GraphValue_Outlier <- data %>%
      pivot_longer(cols=variables,
                   names_to = "Variable",
                   values_to ="Value") %>% 
      group_by(HMT_model,Hb,Variable) %>% 
      mutate(q1=quantile(Value, 0.25,na.rm=TRUE),
             q3=quantile(Value,0.75, na.rm=TRUE),
             i=IQR(Value, na.rm=TRUE), 
             lower= q1-3*i, upper=q3+3*i) %>% 
      ungroup()
    
    
    outliersTable<-GraphValue_Outlier %>% 
      filter(Value<lower | Value>upper) %>% 
      transmute(
        SAMPLEDESCRIPTION,
        Subject,
        HMT_model,
        Hb,
        Variable,
        Value
      )
    
    Graphvalues_clean <- GraphValue_Outlier %>% mutate(
      Value=ifelse(Value<lower | Value>upper, NA,Value)) %>% 
      #Removes the columns that are outliers
      select(-q1,-q3,-i,-lower,-upper) %>% 
      pivot_wider(
        names_from=Variable,
        values_from=Value
      )
    
    #Displays Table
    Table<-as_tibble(outliersTable) %>% 
      kable(format="pipe",
            booktabs=TRUE,
            align="ccc",
            kable.NA="",
            caption = Table_title)
    
    
    return(list(CleanedDF=Graphvalues_clean,Out_Tab=Table))
  }
  
  #++++++++++++++++++++++++++++++++++++Seperator++++++++++++++++++++++++++++++++++++++


print("Loading Graph Plotter")


  #Function to caculate Significance via Anova & Fischer's LSD test 
  #And to plot the graphs
  generate_hmt_plots <-function(data){
    
    
    #Needed to ensure 'NA' is regiestered as NA and not as a string ("NA")
    data<-data|> mutate( across(where(is.character), ~na_if(., "NA")))
    
    #Internal Function to plot
    core_plot_helper<-function(sub_data,list_suffix=""){
      
      
      #HTML models/ Groups of interest
      Defined_Grouping=c(ref_model,setdiff(unique(sub_data$HMT_model),ref_model))
      
      if(all(is.na(sub_data$Hb))){
        sub_data$Hb<- sub_data$EM_Hb
        label_prefix <- " EM"
        val_low <-"300"
        val_high<-"600"
      } 
      else{
        label_prefix <- " Hb"
        val_low <-"4"
        val_high<-"8"
      }
      
      
      #Creates groups for plotting and statics
      GraphValues<- sub_data %>% 
        mutate(HMT_model=factor(HMT_model,levels=Defined_Grouping)) %>% 
        mutate(stat_group=paste(HMT_model,Hb,sep="_")) %>% 
        mutate(stat_group=factor(stat_group))
      
      #Checks to see if the reference model exists in the subset
      fwb_stat_group_raw<-GraphValues %>% 
        filter(HMT_model==ref_model) %>% 
        pull(stat_group) %>% 
        first()
      
      has_ref_model<- !is.na(fwb_stat_group_raw)
      
      if(has_ref_model){
        fwb_stat_group<- as.character(fwb_stat_group_raw)
        
        #Releving the dataframe so that Fwb goes first
        GraphValues<-GraphValues %>% 
          mutate(stat_group=relevel(stat_group,ref=fwb_stat_group))
      }
      else{
        fwb_stat_group<- NA
      }
      
      #Helper function to get the pairwise p-values
      get_p_val<-function(g1,g2,comp_df){
        name1<-paste(g1,"-",g2)
        name2<-paste(g2,"-",g1)
        
        #Searches both directions/instances used for LSD test
        if (name1 %in% rownames(comp_df)) return (comp_df[name1,"pvalue"])
        if (name2 %in% rownames(comp_df)) return (comp_df[name2,"pvalue"])
        return(NA) #Backup default if a comparison isn't found
      }
      
      
      #Empty Plot List
      plot_list<-list()
      
      #Loop for plotting each variable
      for (v in variables){
        
        #Creating x axis labels for each graph
        GraphValues_gg<-GraphValues %>% 
          filter(!is.na(.data[[v]])) %>% 
          group_by(HMT_model,Hb) %>% 
          mutate(
            n_count=n(),
            x_label=if_else(
              HMT_model==ref_model,
              paste0("Native\nn=", n_count),
              paste0(Hb,label_prefix,"\nn=",n_count)
            )
          ) %>% 
          ungroup()
        
        #Caculating the dynamic y-positions
        y_max<-max(GraphValues_gg[[v]],na.rm=TRUE)
        y_range<-y_max-min(GraphValues_gg[[v]],na.rm=TRUE)
        
        #Dynamic position for the astrics
        star_y_pos_fwb<-y_max+(y_range*0.20)
        star_y_pos_hb<-y_max+(y_range*0.10)
        
        #Fitting Anova
        Anova_Object<-as.formula(paste0("`",v,"`~stat_group"))
        model<-aov(Anova_Object,data=GraphValues_gg)
        
        #Fischer's LSD Test
        fit<-LSD.test(model,"stat_group",console=FALSE,group=FALSE)
        comp_df<-fit$comparison
        unique_groups<-as.character(unique(GraphValues_gg$stat_group))
        
        #Comparison 1: Models vs Based Reference
        fwb_sig_list<-list()
        
        #Checks if a reference model exists 
        if(has_ref_model){
          
          other_models<-setdiff(unique_groups,fwb_stat_group)
          
          #Gets the p-val for the pairwise comparison
          for (og in other_models){
            pval<-get_p_val(fwb_stat_group,og,comp_df)
            
            if(!is.na(pval) && pval<0.05){
              stars<-case_when(pval<0.001~"***",pval<0.01~"**",pval<0.05~"*",TRUE~"")
              fwb_sig_list[[og]]<-data.frame(stat_group=og,p_val=pval,label=stars)
            }
          }
        }
        fwb_sig_df<-bind_rows(fwb_sig_list)
        
        #Prevents overlapping astricks
        if (nrow(fwb_sig_df)> 0) {
          pos_df<-GraphValues_gg %>% 
            group_by(stat_group,HMT_model,x_label) %>% 
            summarise(.groups="drop") %>% 
            mutate(y_pos=star_y_pos_fwb)
          
          fwb_sig_df<-fwb_sig_df %>% 
            inner_join(pos_df,by="stat_group") %>% 
            mutate(HMT_model=factor(HMT_model,levels=Defined_Grouping))
        }
        #Comparison 1: Hb=4 vs Hb=8
        hb_sig_list<-list()
        models<-as.character(unique(GraphValues_gg$HMT_model))
        
        for (m in models){
          if(m==ref_model) next
          
          g4<-paste(m,val_low,sep="_")
          g8<-paste(m,val_high,sep="_")
          
          #Gets the Pval
          if (g4 %in% unique_groups && g8 %in% unique_groups){
            pval<-get_p_val(g4,g8,comp_df)
            
            #Star allocation
            if(!is.na(pval) && pval<0.05){
              stars<-case_when(pval<0.001~"***",pval<0.01~"**",pval<0.05~"*",TRUE~"")
              
              x_g4<-unique(GraphValues_gg$x_label[GraphValues_gg$stat_group==g4])
              x_g8<-unique(GraphValues_gg$x_label[GraphValues_gg$stat_group==g8])
              
              #Gets plotting postion for Hb comparisons annotations
              hb_sig_list[[m]]<-data.frame(
                HMT_model=factor(m,levels=Defined_Grouping),
                x_start=x_g4,
                x_end=x_g8,
                label=stars,
                y_pos=star_y_pos_hb,
                y_pos_text=star_y_pos_hb+(y_range*0.03)
              )
            }
          }
        }
        
        hb_sig_df<-bind_rows(hb_sig_list)
        
        #Generating Plots
        if (ADetection(sub_data)){
          p<-ggplot(GraphValues_gg,aes(x=x_label, y=.data[[v]]))+
            geom_boxplot(fill="lightgrey",outlier.shape=NA)+
            stat_summary(fun.min=min,fun.max=max,geom="errorbar",width=0.5)+
            geom_point(color="black",fill="lightgrey",shape=21)+
            facet_grid(~HMT_model,scales="free_x",space="free_x",switch="x",drop=TRUE,
                       labeller=as_labeller(function(x)paste0(x, "_A")))+
            labs(x=NULL,y=v)+
            theme_classic()+
            theme(
              strip.text=element_text(face="bold",size=12),
              strip.background=element_rect(fill="lightgrey"),
              legend.position="none",
              panel.border=element_rect(color="grey50",fill=NA,linetype="dotted"),
              panel.spacing=unit(1,"lines")
            )
          
        } else{
          p<-ggplot(GraphValues_gg,aes(x=x_label, y=.data[[v]]))+
            geom_boxplot(fill="lightgrey",outlier.shape=NA)+
            stat_summary(fun.min=min,fun.max=max,geom="errorbar",width=0.5)+
            geom_point(color="black",fill="lightgrey",shape=21)+
            facet_grid(~HMT_model,scales="free_x",space="free_x",switch="x",drop=TRUE,
                       labeller=as_labeller(function(x)paste0(x," ")))+
            labs(x=NULL,y=v)+
            theme_classic()+
            theme(
              strip.text=element_text(face="bold",size=12),
              strip.background=element_rect(fill="lightgrey"),
              legend.position="none",
              panel.border=element_rect(color="grey50",fill=NA,linetype="dotted"),
              panel.spacing=unit(1,"lines")
            )
        }
        
        if (nrow(fwb_sig_df)>0){
          p<-p+geom_text(data=fwb_sig_df,aes(x=x_label,y=y_pos,label=label),
                         inherit.aes=FALSE,color="black",size=6,vjust=0.5)
        }
        #
        if(nrow(hb_sig_df)>0){
          p<-p+geom_segment(data=hb_sig_df, aes(x=x_start,xend=x_end,y=y_pos,yend=y_pos), inherit.aes=FALSE,color="red",linewidth=0.8)+
            geom_text(data=hb_sig_df,aes(x=x_start,y=y_pos_text,label=label),
                      position = position_nudge(x=0.5),inherit.aes=FALSE,color="red",size=6,vjust=0.5)
        }
        
        #Stores plot into a list
        plot_name<-if(nchar(list_suffix)>0) paste0(v,"_",list_suffix) else v
        plot_list[[plot_name]]<-p
      }
      
      #Returns final list
      return(plot_list)
    }
    
    #Had to make the helper function so that I can run this comparison
    
    if (ADetection(data)){
      data_with_A<-data %>%  filter(grepl("A",Alb))
      data_With_NoA<- data %>% filter(!grepl("A",Alb)| is.na(Alb))
      
      #Generates seperate plot list
      plots_No_A <-core_plot_helper(data_With_NoA,"No_A")
      plots_With_A <-core_plot_helper(data_with_A,"With_A")
      
      # Generates separate plot lists
      plots_No_A <- core_plot_helper(data_With_NoA, "No_A")
      plots_With_A <- core_plot_helper(data_with_A, "With_A")
      
      #Page 1: R(Min) and K(Min)
      page_1<-(
        plots_No_A[["R(min)_No_A"]]+plots_With_A[["R(min)_With_A"]]
      )/
        (plots_No_A[["K(min)_No_A"]]+plots_With_A[["K(min)_With_A"]])
      
      #Page 2:
      page_2<-(plots_No_A[["MA(mm)_No_A"]]+plots_With_A[["MA(mm)_With_A"]]
      )/
        (plots_No_A[["Angle(deg)_No_A"]]+plots_With_A[["Angle(deg)_With_A"]])
      
      #Titles
      page_1<-page_1 + plot_annotation(title='Page 1: R(min) and K(min) Comparisons')
      page_2<-page_2 + plot_annotation(title='Page 2: MA(mm) and Angle(Deg) Comparisons')
      
      return(list(page_1=page_1,page_2=page_2))
    }
    else{
      standard_plots<-core_plot_helper(data,"")
      
      page_1<-(standard_plots[["R(min)"]]+standard_plots[["K(min)"]])/(standard_plots[["MA(mm)"]]+standard_plots[["Angle(deg)"]])
      page_2<-NULL
      
      return(list(page_1=page_1,page_2=page_2))
    }
  }
  
                                                                              ##################################
                                                                              #             Round 1            #
                                                                              ##################################
  

print("Loading Round 1 Data")

  #Removes the unneccesary 
  Round1_Df <- Cleaned_df %>%
    filter(Subject %in% round1)
  
  #Detects Outliers
  Round1_Outliers<-DetectOutliers(Round1_Df)$CleanedDF
  Round1_OutTable<-DetectOutliers(Round1_Df)$Out_Tab
  

  
  #Generates Plots
  plots_R1_all <- generate_hmt_plots(Round1_Df)
  plots_R1_clean<- generate_hmt_plots(Round1_Outliers)
  
  #Assigns Plots
  
  #With outliers:
  p1_1_page1<-plots_R1_all$page_1
  p1_1_page2<-plots_R1_all$page_2
  
  #Without outliers
  p2_1_page1<-plots_R1_clean$page_1
  p2_1_page2<-plots_R1_clean$page_2



print(Round1_OutTable)



                                                                              ##################################
                                                                              #             Round 2            #
                                                                              ##################################

      
print("Loading Round 2 Data")

  #Picks only the subjects defined in Round 2: 5-8
  Round2_Df <- Cleaned_df %>%
    filter(Subject %in% round2)
  
  
  
  #Detects Outliers
  Round2_Outliers<-DetectOutliers(Round2_Df)$CleanedDF
  Round2_OutTable<-DetectOutliers(Round2_Df)$Out_Tab
  
  
  
  #Generates Plots
  plots_R2_all <- generate_hmt_plots(Round2_Df)
  plots_R2_clean<- generate_hmt_plots(Round2_Outliers)
  
  #Assigns Plots
  
  #With outliers:
  p1_2_page1<-plots_R2_all$page_1
  p1_2_page2<-plots_R2_all$page_2
  
  #Without outliers
  p2_2_page1<-plots_R2_clean$page_1
  p2_2_page2<-plots_R2_clean$page_2

print(Round2_OutTable)

                                                                              ##################################
                                                                              #             Round 3            #
                                                                              ##################################

print("Loading Round 3 Data")

  #Picks only the subjects defined in Round 3: 9-12
  Round3_Df <- Cleaned_df %>%
    filter(Subject %in% round3,
           (!str_detect(HMT_model, "CFF"))
    )
  
  #Detects Outliers
  Round3_Outliers<-DetectOutliers(Round3_Df)$CleanedDF
  Round3_OutTable<-DetectOutliers(Round3_Df)$Out_Tab
  
  
  #Generates Plots
  plots_R3_all <- generate_hmt_plots(Round3_Df)
  plots_R3_clean<- generate_hmt_plots(Round3_Outliers)
  
  #Assigns Plots
  
  #With outliers:
  p1_3_page1<-plots_R3_all$page_1
  p1_3_page2<-plots_R3_all$page_2
  
  #Without outliers
  p2_3_page1<-plots_R3_clean$page_1
  p2_3_page2<-plots_R3_clean$page_2

print(Round3_OutTable)


                                                                              ##################################
                                                                              #   Saving Final Plots / Output  #
                                                                              ##################################

print("Saving Final Plots")

  #Combines plots together
  Master_Plots<-list(
    "Round 1 (With Outliers)"    =plots_R1_all,
    "Round 1 (Without Outliers)" =plots_R1_clean,
    
    "Round 2 (With Outliers)"    =plots_R2_all,
    "Round 2 (Without Outliers)" =plots_R2_clean,
    
    "Round 3 (With Outliers)"    =plots_R3_all,
    "Round 3 (Without Outliers)" =plots_R3_clean
  )
  
  #Creates a file path for the Rounds PDF
  pdf_file_path<-file.path(Results_Folder,"RoundsGraphs.pdf")
  
  pdf(pdf_file_path,width=11,height=8.50)
  
  for (name in names(Master_Plots)){
    
    plot_obj<-Master_Plots[[name]]
    
    #Skips if the plot doesn't exists or fails
    if (is.null(plot_obj)) next
    print(
      plot_obj$page_1+plot_annotation(title=paste(name), " ")
    )
    
    
    #Since page 2 is defined as null in some cases
    if(!is.null(plot_obj$page_2)){
      print(
        plot_obj$page_2+plot_annotation(title=paste(name), " ")
      )
    }
  }
  
  dev.off()
  
  ExportGroupStats(Cleaned_df)

  
cat("Finished, Files saved to:", Results_Folder, "\n")

  