##################################
#      Loading Packages          #
##################################


required_packages <- c("dplyr", "tidyr", "tidyverse", "openxlsx", "data.table", "stringr", "pdftools","magick", "tesseract")

invisible(new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])])
invisible(if(length(new_packages) > 0) {install.packages(new_packages)})

invisible(lapply(required_packages, library, character.only = TRUE))

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#    File Path Configuration     #
##################################

OCR_RENDER_DPI <- 600

if(PDF_File_Path != " "){
  Folder_Path <- gsub("\\\\", "/", PDF_File_Path, ignore.case=FALSE)
} else{ 
  Folder_Path <- choose.dir() 
} 

Parent_Directory<-dirname(Directory)

#Final Results folder
Results_Folder<-file.path(Parent_Directory,paste("Processed PDFs"))

if(!dir.exists(Results_Folder)){
  dir.create(Results_Folder,recursive = TRUE, showWarnings = FALSE)
}

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#        Helper Functions        #
##################################


#Silence C-level prints
quiet_run<- function(expr){
  capture.output(capture.output(
    suppressMessages(suppressWarnings(expr)),
    file=nullfile(), type="message"
  ),
  file=nullfile(),type="output")
}

#Base Normalization + OCR Specific Corrections
Normalize_Cell <- function(x){
  
  if(is.na(x) || length(x) == 0)
    return(NA_character_)
  
  x_clean <- x %>%
    as.character() %>%
    trimws() %>%
    gsub("_", "-", .) %>%
    gsub("\\s+", " ", .) %>%
    gsub("–", "-", .) %>%
    gsub("^\\s+|\\s+$", "", .)
  
  if(grepl("^[^A-Za-z0-9]+$",x_clean)){
    return(NA_character_)
  }
  
  #OCR Corrections
  
  #Strips surrounding characters
  x_clean <- gsub("^[\\(\\[\\|]+", "", x_clean)  # Removes leading (, [, or |
  x_clean <- gsub("[\\)\\]\\|]+$", "", x_clean)  # Removes trailing ), ], or |
  
  #Removes leading <>
  x_clean <- gsub("^[<>]+", "", x_clean)
  
  x_clean <- gsub("\\.$","",x_clean)
  
  x_clean <- gsub("^([-+]?\\d+\\.\\d+)\\.\\d+$", "\\1",x_clean)
  
  #Comma to Decimal Fix (e.g., 6,13 -> 6.13)
  x_clean <- gsub("^(\\d+),(\\d+)$", "\\1.\\2", x_clean)
  
  #Blood gas variables
  x_clean <- gsub("^pCO[,\\.]+$", "pCO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^pC0[,\\.]+$", "pCO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^pC02$", "pCO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^pCOZ$", "pCO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^pco,$", "pCO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^poo,$", "pCO2", x_clean, ignore.case = TRUE)
  
  x_clean <- gsub("^pO[,\\.]+$", "pO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^po,$", "pO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^p0[,\\.]+$", "pO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^00,$", "pO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^p02$", "pO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^pOZ$", "pO2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^po;$","pO2", x_clean, ignore.case=TRUE)
  x_clean <- gsub("^pd,$","pO2", x_clean, ignore.case=TRUE)
  
  #pH
  x_clean <- gsub("^oH$", "pH", x_clean, ignore.case = TRUE)
  
  #LAC Corrections
  x_clean <- gsub("^nae$", "LAC", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^oLac$", "LAC", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^cLac$", "LAC", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^cl.ac$", "LAC", x_clean,ignore.case = TRUE)
  
  #CBC
  x_clean <- gsub("^wec$", "WBC", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^WaC$", "WBC", x_clean, ignore.case = TRUE)
  
  #Chemistry
  x_clean <- gsub("^LOH$", "LDH", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^oGlu$", "GLU", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^oGh$", "GLU", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^BUM$", "BUN", x_clean, ignore.case = TRUE)
  
  #Hardcoded Value/Unit Merges (Will be split later on)
  x_clean <- gsub("^GO\\?$", "67", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^PLL$", "2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^PUL$", "2", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^SUYL$", "5", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^SUL$", "5", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^AGUAL$", "6", x_clean, ignore.case = TRUE)
  
  #ABL90
  x_clean <- gsub("^otHb$", "HGB", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^ctHb$", "HGB", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^Hele$", "HCT", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^\\.o,$", "sO2", x_clean, ignore.case = TRUE)
  
  #Percent
  x_clean <- gsub("^l0%$", "10%", x_clean, ignore.case = TRUE)
  
  #Numbers & Specific TEG Corrections
  x_clean <- gsub("^Zit$", "2.7", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^Ki:$", "K", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^a\\.F$", "8.7", x_clean, ignore.case = TRUE)
  x_clean <- gsub("^SU/L%","5",x_clean,ignore.case=TRUE)
  x_clean <- gsub("SU/L","5",x_clean,ignore.case=TRUE)
  x_clean <- gsub("<2U/L","2",x_clean,ignore.case=TRUE)
  x_clean <- gsub("3.33)","3.33",x_clean,ignore.case=TRUE)
  
  
  return(x_clean)
}



fix_ocr_number_confusion <- function(token) {
  if(is.na(token) || token == "") return(token)
  
  #Avoids mangling a token that is already a recognized dictionary term
  if(toupper(token) %in% toupper(names(Variable_Dic))) return(token)
  
  #Only attempt recovery on short, value-shaped tokens
  if(nchar(token) > 6) return(token)
  
  digit_lookalikes <- c(
    "O" = "0", "o" = "0", "D" = "0",
    "I" = "1", "l" = "1", "i" = "1", "|" = "1",
    "Z" = "2", "z" = "2",
    "S" = "5", "s" = "5",
    "G" = "6", "b" = "6",
    "T" = "7",
    "B" = "8",
    "g" = "9", "q" = "9"
  )
  
  candidate <- token
  for(letter in names(digit_lookalikes)) {
    candidate <- gsub(letter, digit_lookalikes[[letter]], candidate, fixed = TRUE)
  }

  #Only accepts the fix if the result reads as a clean number
  if(grepl("^[-+]?[0-9]*\\.?[0-9]+$", candidate)) {
    return(candidate)
  }
  
  return(token)
}

#General Page Classifier
detect_page_type <- function(page_grid) {
  if(is.null(page_grid) || nrow(page_grid) == 0) return("UNKNOWN")
  
  normalized <- sapply(
    page_grid$raw_value,
    Normalize_Cell
  )
  
  has <- function(pattern) {
    any(grepl(pattern,normalized,ignore.case = TRUE))
  }
  
  #ABG fingerprint
  if(
    has("^pH$") &&
    has("^pCO2$") &&
    has("^pO2$")
  ) {
    return("ABG")
  }
  
  #CBC fingerprint
  if(
    has("^WBC$") &&
    has("^RBC$") &&
    has("^HGB$") &&
    has("^HCT$")
  ) {
    return("CBC")
  }
  
  #CMP fingerprint
  if(
    has("^AST$") &&
    has("^ALT$") &&
    has("^CREA$")
  ) {
    return("CMP")
  }
  
  #TEG fingerprint
  if(
    has("^r\\.Time$") ||
    has("^k\\.Time$") ||
    has("^ma\\.Min$") ||
    has("^angle$")
  ) {
    return("TEG")
  }
  if(
    has("^APTT$") ||
    has("^PT$") ||
    has("^TT$") ||
    has("^Fib$")
  ) {
    return("Coag")
  }
  
  return("UNKNOWN")
}

#Smart Matcher
match_term <- function(val, dict){
  if(is.na(val) || val == "") return(NA_character_)
  
  for (raw_term in names(dict)){
    #Base R way to escape regex characters
    safe_term <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", raw_term) 
    pattern <- paste0("\\b", safe_term, "\\b")
    
    if (str_detect(tolower(val), regex(pattern, ignore_case=TRUE))){
      return(dict[[raw_term]])
    }
  }
  return(NA_character_)
}

rabbit_regex <- "(KC|B[-_ ]?LR|B[-_ ]?B|B[-_ ]?PRC|BEA|Rabbit)[-_ ]?[A-Za-z0-9]+"

#Regex Extractor for IDs
extract_rabit <- function(val){
  match <- str_extract(val, regex(rabbit_regex, ignore_case=TRUE))
  return(match)
}


if (Sys.info()["sysname"] == "Windows"){
eng <- tesseract("eng", options=list(debug_file="NUL"))

} else if (Sys.info()["sysname"] == "Darwin"){
eng <- tesseract("eng", options=list(debug_file="/dev/null"))  
}
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#         Dictionaries           #
##################################

Variable_Dic <- c(
  "MAP"="MAP",
  "bpm"="bpm",
  "temp"="temp",
  "RBC"="RBC",
  "Hb"="HGB",
  "HGB"="HGB",
  "HCT"="HCT",
  "hct"="HCT",
  "PLT"="PLT",
  "WBC"="WBC",
  "X._Free_Hb"="X._Free_Hb",
  "LAC"="LAC",
  "pH"="pH",
  "pCO2"="pCO2",
  "pO2"="pO2",
  "AST"="AST",
  "ALT"="ALT",
  "LDH"="LDH",
  "CREA"="CREA",
  "BUN"="BUN",
  "AMY"="AMY",
  "TG"="TG",
  "GLU"="GLU",
  "GGT"="GGT",
  "R"="R.Time","CK R time"="R.Time","R.Time"="R.Time","R:"="R.Time",
  "CK K time"="K.Time","K"="K.Time","K:"="K.Time","K.Time"="K.Time",
  "MA.Min"="MA.Min","CK MA"="MA.Min","MA"="MA.Min","MA:"="MA.Min",
  "Angle"="Angle","Angle:"="Angle",
  "APTT"="APTT","aptt"="APTT",
  "PT"="PT","pt"="PT",
  "TT"="TT","tt"="TT","Tt"="TT","tT"="TT",
  "Fib"="Fib","fib"="Fib","FIB"="Fib",
  
  #ABL90 variables
  "ctHb"="HGB",
  "otHb"="HGB",
  "FO2Hb"="FO2Hb",
  "FCOHb"="FCOHb",
  "FHHb"="FHHb",
  "FMetHb"="FMetHb"
)

Group_Dict <- list(
  "ABG" = c("pH", "pCO2", "pO2", "LAC"),
  "CBC" = c("WBC", "RBC", "HGB", "HCT", "PLT"),
  "CMP" = c("GGT", "AST", "ALT", "AMY", "LDH", "CREA", "BUN", "GLU", "TG"),
  "TEG" = c("R.Time", "K.Time", "Angle", "MA.Min"),
  "Coag" = c("APTT","PT","TT","Fib")
)


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#      Extracting PDF Logic      #
##################################

extract_pdf_data <- function(file_paths) {
  
  total_pdfs <- length(file_paths)
  cat(sprintf("\nFound %d PDF(s) to process \n\n", total_pdfs))
  
  #Empty Lists to track the data of pdf's and their pages
  all_pdfs_data<- list()
  pdf_page_counts <- list()
  
  for (p in seq_along(file_paths)){
    file_path<- file_paths[[p]]
    
    native_pages <- pdf_data(file_path)
    total_pages <- length(native_pages )
    
    #Logs the page count for the summary later on
    pdf_page_counts[[p]] <- list(file_name = basename(file_path),pages=total_pages)
    
    all_pages <- list()
    
    for (i in seq_along(native_pages )){
      
      #Progress bar
      pdf_w <- if(total_pdfs >0) round(20*(p/total_pdfs)) else 20
      page_w <- if (total_pages >0) round(20*(i/total_pages)) else 20
      
      cat(sprintf("\r Processing PDF %d/%d [%-20s] | page %d/%d [%-20s]    ",
                  p, total_pdfs, strrep("=",pdf_w),
                  i, total_pages,strrep("=",page_w)))
      flush.console()
      
      page_data <- native_pages[[i]]
      
      temp_text_grid <- data.frame(raw_value = character(), stringsAsFactors = FALSE)
      
      enhanced_img <- NULL
      first_pass_ocr_df <- NULL
      used_ocr_for_first_pass <- FALSE
      
      # First Pass: Gathers text to detect page type
      if(nrow(page_data) > 0) {
        temp_text_grid <- data.frame(raw_value = page_data$text, stringsAsFactors = FALSE)
      } else {
        used_ocr_for_first_pass <- TRUE
        
        tryCatch({
          quiet_run({
            rendered_page <- pdf_render_page(file_path, page = i, dpi = OCR_RENDER_DPI)
            img <- image_read(rendered_page)
            
            enhanced_img <- img %>%
              image_trim() %>% 
              image_convert(colorspace = "gray") %>% 
              image_contrast(sharpen = 1) %>%
              image_normalize() %>%
              image_threshold(type = "black", threshold = "50%") 
            first_pass_ocr_df <- ocr_data(enhanced_img, engine = eng)
          })
          
          if(nrow(first_pass_ocr_df) > 0) {
            temp_text_grid <- data.frame(raw_value = first_pass_ocr_df$word, stringsAsFactors = FALSE)
          }
        }, error = function(e) {NULL})
      }
      
      # Page Classification
      page_type <- detect_page_type(temp_text_grid)
      
      # Extraction
      clean_df <- data.frame()
      
      # Ensure enhanced_img is reset if it's a leftover from a previous loop iteration
      if (!used_ocr_for_first_pass) {
        enhanced_img <- NULL 
      }
      
      if(page_type == "ABG") {
        tryCatch({
          quiet_run({
            # Render if we haven't already
            if(!used_ocr_for_first_pass || is.null(enhanced_img)) {
              rendered_page <- pdf_render_page(file_path, page = i, dpi = 600)
              img <- image_read(rendered_page)
              enhanced_img <- img |> 
                image_trim() |> 
                image_convert(colorspace = "gray") |> 
                image_contrast(sharpen = 1) |> 
                image_normalize() |> 
                image_threshold(type = "black", threshold = "50%") 
            }
            
            # Deskew image
            deskewed_img <- enhanced_img |> image_deskew(threshold = 40)
            
            # Final OCR 
            final_ocr <- ocr_data(deskewed_img, engine = eng)
          })
          
          if(nrow(final_ocr) > 0) {
            box_mat <- do.call(rbind, strsplit(as.character(final_ocr$bbox), ","))
            clean_df <- data.frame(
              pdf_index = p,
              file_name = basename(file_path),
              page = i,
              page_type = page_type,
              x = as.numeric(box_mat[, 1]),
              y = as.numeric(box_mat[, 2]),
              width = as.numeric(box_mat[, 3]) - as.numeric(box_mat[, 1]),
              height = as.numeric(box_mat[, 4]) - as.numeric(box_mat[, 2]),
              raw_value = trimws(final_ocr$word),
              extraction_method = "OCR_DESKEWED",
              stringsAsFactors = FALSE
            ) |> 
              filter(!is.na(raw_value), raw_value != "", !is.na(x), !is.na(y))
          }
        }, error = function(e) {NULL})
        
      } else {
        if(nrow(page_data) > 0) {
          # Rely on Native PDF text
          clean_df <- page_data |> 
            transmute(
              pdf_index = p,
              file_name = basename(file_path),
              page = i,
              page_type = page_type,
              x = as.numeric(x),
              y = as.numeric(y),
              width = as.numeric(width),
              height = as.numeric(height),
              raw_value = trimws(text),
              extraction_method = "PDF"
            ) |> 
            filter(!is.na(raw_value), raw_value != "", !is.na(x), !is.na(y))
        } else if(used_ocr_for_first_pass && !is.null(first_pass_ocr_df) && nrow(first_pass_ocr_df) > 0) {
          
          box_mat <- do.call(rbind, strsplit(as.character(first_pass_ocr_df$bbox), ","))
          
          clean_df <- data.frame(
            pdf_index = p,
            file_name = basename(file_path),
            page = i,
            page_type = page_type,
            x = as.numeric(box_mat[, 1]),
            y = as.numeric(box_mat[, 2]),
            width = as.numeric(box_mat[, 3]) - as.numeric(box_mat[, 1]),
            height = as.numeric(box_mat[, 4]) - as.numeric(box_mat[, 2]),
            raw_value = trimws(first_pass_ocr_df$word),
            extraction_method = "OCR",
            stringsAsFactors = FALSE
          ) |> 
            filter(!is.na(raw_value), raw_value != "", !is.na(x), !is.na(y))
        } 
      }
      all_pages[[i]] <- clean_df
    }
    
    # Combines all pages for the current PDF
    all_pages <- all_pages[vapply(all_pages, function(x) nrow(x) > 0, logical(1))]
    if(length(all_pages) > 0) {
      all_pdfs_data[[p]] <- bind_rows(all_pages)
    }
  }
  
  # Combine data across all PDFs
  all_pdfs_data <- all_pdfs_data[vapply(all_pdfs_data, function(x) !is.null(x) && nrow(x) > 0, logical(1))]
  
  if(length(all_pdfs_data) == 0) {
    grid <- data.frame()
  } else {
    grid <- bind_rows(all_pdfs_data)
  }
  
  #Output: Collective Summary
  
  cat("\n\n============================================\n")
  cat("RAW EXTRACTION SUMMARY\n")
  cat("============================================\n")
  cat(sprintf("Total PDF's Found:   %d\n\n",total_pdfs))
  cat("--- Pages Per PDF ---\n")
  total_pages_all<-0
  for (info in pdf_page_counts){
    cat(sprintf("- %s: %d pages\n", info$file_name, info$pages))
    total_pages_all <-total_pages_all + info$pages
  }
  cat("-------------------\n\n")
  
  if (nrow(grid)>0){
   
  #Caculates uniqely extracted pages by combining the pdf index and page number
  extracted_unique_pages <- length(unique(paste(grid$pdf_index, grid$page, sep="_")))
    
  cat(sprintf("Total pages processed: %d\n", total_pages_all))
  cat(sprintf("Pages with extraction: %d\n", extracted_unique_pages))
  cat(sprintf("Total text elements:   %d\n", nrow(grid)))
  cat(sprintf("Native PDF elements:   %d\n", sum(grid$extraction_method == "PDF")))
  cat(sprintf("Standard OCR elements: %d\n", sum(grid$extraction_method == "OCR")))
  cat(sprintf("Deskewed OCR elements: %d\n", sum(grid$extraction_method == "OCR_DESKEWED")))
  } else{
    cat("No text elements could be extracted from any PDF.\n")
  }
  cat("============================================\n")
  
  return(grid)
}

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#   Identifies Possible Pairs    #
##################################

extract_possible_pairs <- function(raw_grid) {
  
  working_grid <- raw_grid %>%
    mutate(
      normalized_value = sapply(raw_value, Normalize_Cell),
      clean_text = normalized_value %>%
        gsub(",", "", .) %>%
        trimws(),
      
      is_pure_num = grepl("^[-+]?[0-9]*\\.?[0-9]+$", clean_text),
      
      #Safely identifies complex fused units like "185.43mg/dL" or "2.510^3/mm^3"
      is_val_unit = grepl("^[-+]?[0-9]*\\.?[0-9]+[A-Za-z%\\/\\^\\*]+.*$", clean_text),
      is_var_val = grepl("^[^0-9\\.]+[-+]?[0-9]*\\.?[0-9]+$", clean_text),
      
      #Protect known variables (as defined in the dictionary)
      is_known_var = clean_text %in% names(Variable_Dic) | clean_text %in% Variable_Dic,
      
      possible_value = (is_pure_num | is_val_unit | is_var_val) & !is_known_var,
      
      actual_numeric = case_when(
        is_val_unit & !is_known_var ~ str_extract(clean_text, "^[-+]?[0-9]*\\.?[0-9]+"),
        is_var_val & !is_known_var  ~ str_extract(clean_text, "[-+]?[0-9]*\\.?[0-9]+$"),
        is_pure_num & !is_known_var ~ clean_text,
        TRUE ~ NA_character_
      ),
      
      embedded_unit = case_when(
        is_val_unit & !is_known_var ~ str_remove(clean_text, "^[-+]?[0-9]*\\.?[0-9]+"),
        TRUE ~ NA_character_
      ),
      
      embedded_var = case_when(
        is_var_val & !is_known_var ~ str_remove(clean_text, "[-+]?[0-9]*\\.?[0-9]+$"),
        TRUE ~ NA_character_
      )
    )
  
  values <- working_grid %>% filter(possible_value)
  
  text_elements <- working_grid %>% filter(!possible_value)
  
  pair_list <- vector("list", nrow(values))
  
  #Process every numeric value
  for(i in seq_len(nrow(values))) {
    
    value <- values[i, ]

    #Works with combined / embedded pairs like (HGB12.5) and seperates the paris automatically
    #Bypasses Spatial Search
    if(!is.na(value$embedded_var) && value$embedded_var != "") {
      pair_list[[i]] <- data.frame(
        Source_File= value$Source_File,
        page = value$page,
        Variable = value$embedded_var,
        Value = value$actual_numeric,
        Unit = NA_character_, 
        Variable_X = value$x,
        Variable_Y = value$y,
        Value_X = value$x,
        Value_Y = value$y,
        Unit_X = NA_real_,
        Unit_Y = NA_real_,
        Horizontal_Distance = 0,
        Vertical_Distance = 0,
        Match_Confidence = "High (Self-Contained)",
        stringsAsFactors = FALSE
      )
      next
    }
    
#Finds Spatial Candidates to the left, Above, and exact y-axis
    candidates <- text_elements %>%
      filter(
        page == value$page,
        (
          #Condition 1: Text is to the LEFT (same row, tight vertical alignment)
          (x < (value$x + 50) & abs(y - value$y) <= 25 & (value$x - x) <= 900)
          |
            #Condition 2: Text is ABOVE (same column, row immediately above)
            (abs(x - value$x) <= 80 & y < value$y & (value$y - y) <= 50)
          |
            #Condition 3: Exact Y-Axis match across the row (Variable's Y = Value's Y)
            (abs(y - value$y) <= 5 & x < value$x)
        )
      )

    
#Sequential Fallback & Closest Match Selector
    
    if(nrow(candidates) == 0) {
      same_line_texts <- text_elements %>%
        filter(
          page == value$page, 
          abs(y - value$y) <= 20, 
          x < value$x
        ) %>%
        arrange(desc(x)) #Grabs the closest preceding text element to the left
      
      if(nrow(same_line_texts) > 0) {
        best <- same_line_texts[1, ]
      } else {
        pair_list[[i]] <- data.frame(
          Source_File= value$Source_File,
          page = value$page,
          Variable = NA_character_,
          Value = value$actual_numeric, 
          Unit = NA_character_,
          Variable_X = NA_real_,
          Variable_Y = NA_real_,
          Value_X = value$x,
          Value_Y = value$y,
          Unit_X = NA_real_,
          Unit_Y = NA_real_,
          Horizontal_Distance = NA_real_,
          Vertical_Distance = NA_real_,
          Match_Confidence = "Unmatched",
          stringsAsFactors = FALSE
        )
        next
      }
    } else {
    
      #Caculates the combined distance to find the most logical pairing
      candidates <- candidates %>%
        mutate(
          horizontal_distance = abs(value$x - x),
          vertical_distance = abs(value$y - y),
          total_distance = horizontal_distance + (vertical_distance * 3)
        )
      
      best <- candidates[which.min(candidates$total_distance), ]
    }
    
    distance <- abs(value$x - best$x)
    vertical <- abs(value$y - best$y)
    
    #Confidence scoring,
    #Handles all alingments
    confidence <- case_when(
      vertical <= 5 & distance <= 900 ~ "High (Y-Axis Match)", #Condition C Hit
      vertical <= 15 & distance <= 250 ~ "High",
      vertical <= 25 & distance <= 500 ~ "Medium",
      vertical > 15 & vertical <= 50 & distance <= 100 ~ "High (Above Match)", 
      vertical <= 35 & distance <= 900 ~ "Low",
      TRUE ~ "Possible"
    )
    
    
#Finds Possible Pairs to the Right 
    if (!is.na(value$embedded_unit) && value$embedded_unit != "") {
      
      #Assigns fused units (like 2U/L) automatically
      unit_text <- value$embedded_unit
      unit_x <- value$x
      unit_y <- value$y
      
    } else {
      # Search right for the unit natively
      unit_candidates <- text_elements %>%
        filter(
          page == value$page,
          x > value$x,
          abs(y - value$y) <= 20,
          (x - value$x) <= 300
        )
      
      if(nrow(unit_candidates) > 0) {
        best_unit <- unit_candidates[which.min(unit_candidates$x - value$x), ]
        unit_text <- best_unit$normalized_value
        unit_x <- best_unit$x
        unit_y <- best_unit$y
      } else {
        unit_text <- NA_character_
        unit_x <- NA_real_
        unit_y <- NA_real_
      }
    }
    
    #Saves result pair
    pair_list[[i]] <- data.frame(
      Source_File = value$Source_File,
      page = value$page,
      Variable = best$normalized_value,
      Value = value$actual_numeric,
      Unit = unit_text,
      Variable_X = best$x,
      Variable_Y = best$y,
      Value_X = value$x,
      Value_Y = value$y,
      Unit_X = unit_x,
      Unit_Y = unit_y,
      Horizontal_Distance = distance,
      Vertical_Distance = vertical,
      Match_Confidence = confidence,
      stringsAsFactors = FALSE
    )
  }
  
  result <- bind_rows(pair_list)
  return(result)
}

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#         Core Executor          #
##################################

parse_pdf <- function(file_path, filename = "Unknown_File", pdf_idx=1, total_pdfs=1) {
  raw_grid <- extract_pdf_data(file_path)
  
  if(is.null(raw_grid) || nrow(raw_grid) == 0) {
    return(NULL)
  }
  
  raw_grid <- raw_grid %>%
    mutate(
      Source_File = filename,
      normalized_value = sapply(raw_value, Normalize_Cell) 
    ) %>%
    #Filters ghost characters and UNKNOWN pages
    filter(!is.na(normalized_value) & normalized_value != "") %>%
    filter(page_type != "UNKNOWN") 
  
  #Safety Net: If the document had zero valid lab pages
  if(nrow(raw_grid) == 0) {
    return(NULL)
  }
  
  raw_grid <- raw_grid %>%
    select(
      Source_File, page, page_type, x, y, width, height,
      raw_value, normalized_value, extraction_method
    )
  
  possible_pairs <- extract_possible_pairs(raw_grid)
  
  possible_pairs <- possible_pairs %>%
    mutate(Source_File = filename) %>%
    relocate(Source_File)
  
  list(
    raw_grid = raw_grid,
    possible_pairs = possible_pairs
  )
}

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#   Retrieval & Master Sheets    #
##################################

if (file.exists(Folder_Path) && !dir.exists(Folder_Path)) {
  pdf_files <- c(Folder_Path)
} else if (dir.exists(Folder_Path)) {
  pdf_files <- list.files(
    path = Folder_Path, 
    pattern = "\\.pdf$",
    full.names = TRUE,
    recursive = TRUE
  )
} else {
  pdf_files <- character(0)
}

 total_pdfs<- length(pdf_files)

 #Extracts all pdf's at once
 if(total_pdfs >0){
   raw_master_dataset <- extract_pdf_data(pdf_files)
   
   if(!is.null(raw_master_dataset) && nrow(raw_master_dataset)>0){
     #Cleans the collective dataset
     raw_master_dataset <- raw_master_dataset %>% 
       rename(Source_File = file_name) %>% 
       mutate( normalized_value=sapply(raw_value, Normalize_Cell)) %>% 
       #Filters out ghost characters and UNKNOWN pages
       filter(!is.na(normalized_value) & normalized_value != " ") %>% 
       filter(page_type != "UNKNOWN") %>% 
       select(Source_File, page, page_type,x,y,width,height, raw_value, normalized_value, extraction_method)
     
     #Applying pairing logic
     #Split by Source_File to avvoid cross-contaminate spatial
     possible_pairs_master<- raw_master_dataset %>% 
       split(.$Source_File) %>% 
       lapply(extract_possible_pairs) %>% 
       bind_rows() %>% 
       relocate(Source_File)
   } else{
     raw_master_dataset <- data.frame()
     possible_pairs_master <- data.frame()
   }
 } else {
   raw_master_dataset <- data.frame()
   possible_pairs_master <- data.frame()
 }

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#Safety Net if no pairs are found
if (is.null(possible_pairs_master) || nrow(possible_pairs_master) == 0 || !"Variable" %in% names(possible_pairs_master)) {
  stop("\nPIPELINE HALTED: No pairs were extracted. All pages may have been skipped as UNKNOWN, or OCR failed to detect numbers.")
}

##################################
#  9. Dictionary Integration     #
##################################

#Creates a version of the dictionary with uppercase keys for matching
upper_dict <- setNames(Variable_Dic, toupper(names(Variable_Dic)))

possible_pairs_master <- possible_pairs_master %>%
  mutate(
    Standardized_Variable = upper_dict[toupper(Variable)]
  ) %>%
  filter(!is.na(Standardized_Variable)) %>%
  group_by(Source_File, page, Standardized_Variable, Variable_Y) %>% 
  slice_min(order_by = Horizontal_Distance, n = 1, with_ties = FALSE) %>% 
  ungroup()

possible_pairs_master<- possible_pairs_master %>% 
  group_by(Source_File,page,Standardized_Variable,Variable_Y) %>% 
  slice_min(order_by=Horizontal_Distance,n=1,with_ties=FALSE) %>% 
  ungroup() %>% 
  arrange(Source_File,page,Variable_Y)

#Filters by Groups
page_type_map<-raw_master_dataset %>% 
  select(Source_File,page,page_type) %>% 
  distinct()

#Joins, filters, and cleanups
page_type_map <- raw_master_dataset %>% 
  select(Source_File, page, page_type) %>% 
  distinct()

valid_targets <- list(
  "ABG" = c("pH", "pCO2", "pO2", "LAC"),
  "CBC" = c("WBC", "RBC", "HGB", "HCT", "PLT"),
  "CMP" = c("GGT", "AST", "ALT", "AMY", "LDH", "CREA", "BUN", "GLU", "TG"),
  "TEG" = c("R.Time", "K.Time", "Angle", "MA.Min"),
  "Coag" = c("APTT","PT","TT","Fib")
)

possible_pairs_master <- possible_pairs_master %>% 
  left_join(page_type_map, by = c("Source_File", "page")) %>% 
  filter(
    (page_type == "ABG" & Standardized_Variable %in% valid_targets$ABG) |
      (page_type == "CBC" & Standardized_Variable %in% valid_targets$CBC) |
      (page_type == "CMP" & Standardized_Variable %in% valid_targets$CMP) |
      (page_type == "TEG" & Standardized_Variable %in% valid_targets$TEG) |
      (page_type == "Coag" & Standardized_Variable %in% valid_targets$Coag)
  ) %>%
  relocate(Source_File, page, page_type, Standardized_Variable)


##################################
#      Time Integration          #
##################################

#Extracts the first instance of time per page
time_rows<- raw_master_dataset %>% 
  group_by(Source_File, page, page_type) %>% 
  summarize(
    Value = na.omit(str_extract(raw_value,"\\b\\d{1,2}:\\d{2}(:\\d{2})?\\s*([AaPp][Mm])?\\b"))[1],
    .groups = 'drop'
  ) %>% 
  filter(!is.na(Value)) %>% 
  mutate(
    Standardized_Variable= "Time",
    Varialbe = "Time",
    Unit = NA_character_,
    Variable_X = NA_real_, Variable_Y = NA_real_,
    Value_X = NA_real_, Value_Y = NA_real_,
    Unit_X = NA_real_, Unit_Y = NA_real_,
    Horizontal_Distance = 0, Vertical_Distance = 0,
    Match_Confidence = "Regex Extracted"
  )

#Extracting Date from only the first ABG page per document
date_rows <- raw_master_dataset %>% 
  filter(page_type=="ABG") %>% 
  group_by(Source_File) %>% 
  mutate(min_abg_page=min(page,na.rm=TRUE)) %>% 
  filter(page==min_abg_page) %>% 
  summarize(
    Value=na.omit(str_extract(raw_value, "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b"))[1],
    page=first(page),
    page_type = "ABG",
    .groups = 'drop'
  ) %>% 
  filter(!is.na(Value)) %>% 
  mutate(
    Standardized_Variable= "Date",
    Varialbe = "Date",
    Unit = NA_character_,
    Variable_X = NA_real_, Variable_Y = NA_real_,
    Value_X = NA_real_, Value_Y = NA_real_,
    Unit_X = NA_real_, Unit_Y = NA_real_,
    Horizontal_Distance = 0, Vertical_Distance = 0,
    Match_Confidence = "Regex Extracted"
  )

#Injecting into the final pairs dataframe

possible_pairs_master <- bind_rows(possible_pairs_master, time_rows, date_rows) %>% 
  mutate(Subject_ID= extract_rabit(Source_File),
         Subject_ID=ifelse(is.na(Subject_ID), Source_File, Subject_ID)
         ) %>% 
  relocate(Subject_ID,Source_File, page,page_type,Standardized_Variable) %>% 
  arrange(Source_File, page, desc(Standardized_Variable == "Date"), desc(Standardized_Variable == "Time"),Variable_Y)

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#        Long Formatting         #
##################################

target_vars<-c('MAP',	'bpm',	'temp',	'RBC',	'HGB',	'HCT',	'PLT',	'WBC',	'Free Hb',	'% Free Hb',	'LAC',	'pH',	'pCO2',	'pO2',	'AST',	'ALT',	'LDH',	'CREA',	'BUN',	'AMY',	'TG',	'GLU',	'GGT',	'CKHR time',	'CKH K',	'CKH angle',	'CKH MA','APTT','PT','TT','Fib'
)

assay_groups <- c('MAP', 'Heart rate', 'Body temp', 'CBC', 'CBC', 'CBC', 'CBC', 'CBC', 'Drabkin\'s', '% Free Hb', 'ABG', 'ABG', 'ABG', 'ABG', 
                  'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 
                  'TEG 5000', 'TEG 5000', 'TEG 5000', 'TEG 5000','Coag Panel','Coag Panel','Coag Panel','Coag Panel')

units_row <- c('mmHg',	'bpm',	'°C',	
               'M/mL',	'mg/dL ',	'mmHg',	'10^3/uL',	'10^3/uL',	
               'uM',	'%',	'mmol/L',	'value',	'mmHg',	'mmHg',	
               'U/L',	'U/L',	'U/L',	'mg/dL',	'mg/dL',	'U/L',	'mg/dL',	'mg/dL',	'U/L',
               'min',	'min',	'degree',	'mm',	
               'sec',	'sec',	'sec',	'g/L')

event_mapping<- possible_pairs_master %>% 
  select(Source_File, page, page_type) %>% 
  distinct() %>% 
  arrange(Source_File,page) %>% 
  group_by(Source_File) %>% 
  mutate(Event_ID = cumsum(page_type=="ABG")) %>% 
  
  #Failsafe just in case a file has no ABG page
  mutate(Event_ID = ifelse(Event_ID==0,1,Event_ID)) %>% 
  ungroup()


  #Extracts dates and metadate header
  subject_dates <- possible_pairs_master %>% 
    filter(Standardized_Variable == "Date") %>% 
    group_by(Subject_ID) %>% 
    summarize(Transfusion_date=first(Value),.groups="drop")

 #Pivots the Dataset
 wide_master <- possible_pairs_master %>% 
   filter(Standardized_Variable != "Date") %>% 
   left_join(event_mapping, by= c("Source_File","page","page_type")) %>% 
   mutate(
     Standardized_Variable= recode(Standardized_Variable,
                                            "Hct"     = "HCT",
                                            "R.Time"  = "CKHR time",
                                            "K.Time"  = "CKH K",
                                            "Angle"   = "CKH angle",
                                            "MA.Min"  = "CKH MA",
                                            "Time"    = "Clock Time"
     )
   ) %>% 
   select(Subject_ID,Event_ID,Standardized_Variable,Value) %>% 
   group_by(Subject_ID,Event_ID,Standardized_Variable) %>% 
   summarise(Value=first(Value),.groups="drop") %>% 
   pivot_wider(names_from=Standardized_Variable,values_from=Value)
 
 if(!"Clock Time" %in% names(wide_master)) wide_master$`Clock Time` <- NA_character_
 if(!"Measurement >" %in% names(wide_master)) wide_master$`Measurement >` <- NA_character_
 
 wide_master <- wide_master %>% 
   mutate(
     Timepoint="" ,
     `Measurement >` ="R1")
 
 #Fills in missing target columns to ensure conistent structure
 for(var in target_vars){
   if(!var %in% names(wide_master)) wide_master[[var]] <- NA_character_
 }
 
 #Cleans, Reorder, and Converts to Character
 wide_master <- wide_master %>% 
   select(Subject_ID, Timepoint, `Clock Time`, `Measurement >`, any_of(target_vars)) %>%
   arrange(Subject_ID) %>%
   mutate(across(everything(), ~ ifelse(is.na(.), "", as.character(.))))
 

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##################################
#            Export              #
##################################

#This creates the final export / excel sheet for editing and comparison

 
#Global Create Workbook
wb <- createWorkbook()

addWorksheet(wb,"Raw Extraction")
writeData(wb,"Raw Extraction", raw_master_dataset) 
 
addWorksheet(wb,"Pairwise Master")
writeData(wb,"Pairwise Master", possible_pairs_master)

#Creates Formatting for the excels

#Styles for top header (Rows 1-2)
Main_Head_Style <- createStyle(textDecoration = "bold",halign="center",valign="Bottom",fontSize = 20, fontName = "Calibri",border="TopBottomLeftRight",borderStyle="medium")

#Styles for MetaData (Rows 4-9)
Meta_Labels <- createStyle(textDecoration = "bold",halign="left",valign="center",fontSize = 12)
meta_fill <- createStyle(halign="center",valign="Bottom",fgFill="#e2efd9",border="TopBottomLeftRight", fontSize=12, fontName = "Calibri",borderStyle="medium")
style_meta<- createStyle(fontName="Aptos Narrow",textDecoration = "bold",halign="center", numFmt= "TEXT")

#Styles for the main body: Rows 12 and down
bold_center<- createStyle(textDecoration = "bold",halign="center",valign="center",fontSize = 11, fontName= "Aptos Narrow")
header_fill <- createStyle(textDecoration = "bold",halign="center",valign="center", fgFill="#c0e4f5", border="bottom", fontSize=11, fontName = "Calibri",borderStyle="medium")
style_num<- createStyle(fontName= "Aptos Narrow", numFmt="Number", halign="center")

#For Testing
#area_effected<- createStyle(halign="center",valign="center",fgFill="#8B0000")

#Gets every list of models
list_of_models<- split(wide_master,wide_master$Subject_ID)

#Loops through every subject name in the list of models
for (subj in names(list_of_models)){
  
  #Ensures the sheetname doesn't exceed excel's limit of 31 characters
  sheet_name <- substr(subj,1,31)
  addWorksheet(wb, sheet_name)
  
  df<- list_of_models[[subj]]
  export_df <- df %>% select(-Subject_ID) #ID is already in headers
  
  num_cols <- setdiff(1:ncol(export_df), c(1, 3))
  export_df[num_cols] <- lapply(export_df[num_cols], as.numeric)
  
  #Writes Top header
  writeData(wb,sheet_name," ", xy=c(1,1))
  addStyle(wb, sheet_name,Main_Head_Style,cols=1:6,rows=1:2,gridExpand=TRUE)
  mergeCells(wb, sheet_name, col= 1:6, rows=1:2)
  
  writeData(wb,sheet_name,"Please insert data from only 1 unit per Round", xy=c(7,1))
  addStyle(wb, sheet_name,Main_Head_Style,cols=7:13,rows=1:2,gridExpand=TRUE)
  mergeCells(wb, sheet_name, col= 7:13, rows=1:2)
  
  #Writes the Meta data Labels
  writeData(wb,sheet_name,"Rabbit ID",xy=c(1,4))
  writeData(wb,sheet_name,"Rabbit weight: kg",xy=c(1,5))
  writeData(wb,sheet_name,"Transfusion date:",xy=c(1,6))
  writeData(wb,sheet_name,"Bleed volume (mL) & %:",xy=c(1,7))
  writeData(wb,sheet_name,"Transfusion volume (mL):",xy=c(1,8))
  writeData(wb,sheet_name,"Tele ID",xy=c(1,9))
  writeData(wb,sheet_name,"Exclude rabbit?",xy=c(5,4))
  writeData(wb,sheet_name,"Reason:",xy=c(5,5))
  
  setColWidths(wb,sheet_name, cols= 1:7, widths=c(28.22,9.33, 13.56, 10.89,15.33, 26.56, 10.89))
  setRowHeights(wb, sheet_name, rows= 1:9, heights=c(25.80,27.00,25.80, 25.80, 26.40, 27.00, 25.80, 25.80, 15.60))
  
#Applying Styles to excels
  
  #Bold Center to labels
  addStyle(wb, sheet_name, Meta_Labels,rows=4:9,cols=1, gridExpand = TRUE)
  addStyle(wb, sheet_name, Meta_Labels,rows=4:5,cols=5,gridExpand=TRUE)
  
  #Write Values and Extract correct date
  writeData(wb,sheet_name,subj,xy=c(2,4))
  date_val<-subject_dates$Transfusion_date[subject_dates$Subject_ID==subj]
  
  #Writes date if it exists
  if(length(date_val)>0 && !is.na(date_val)){
    writeData(wb, sheet_name, date_val, xy=c(2,6))
  }
  
  #Creates cells B4:C4- B9:C9 & F4:G4 - F5:G5 and apply the 'meta' fill
  for (r in 4:8){
    mergeCells(wb,sheet_name, cols=2:3,rows=r)
    addStyle(wb, sheet_name, meta_fill, rows=r, cols=2:3, gridExpand=TRUE)
  }
  
  #Just for Telemetry formatting
  addStyle(wb, sheet_name, meta_fill, rows=9, cols=2, gridExpand=TRUE)
  
  for (r in 4:5){
    mergeCells(wb,sheet_name, cols=6:7,rows=r)
    addStyle(wb, sheet_name, meta_fill, rows=r, cols=6:7, gridExpand=TRUE)
  }
  
  #Writes Assay & Units Rows (Row 12 & 13)
    writeData(wb, sheet_name, "Assay >",xy=c(3,12))
    writeData(wb, sheet_name, t(assay_groups), xy=c(4,12), colNames= FALSE)
    writeData(wb, sheet_name, "Units >",xy=c(3,13))
    writeData(wb, sheet_name, t(units_row), xy=c(4,13), colNames= FALSE)
    
    runs<- rle(assay_groups)
    start_col <- 4
    
    for (i in seq_along(runs$lengths)){
      end_col <- start_col + runs$lengths[i] - 1
      
      if(runs$lengths[i] >1){
        mergeCells(wb, sheet_name, cols=start_col:end_col, rows=12)
      }
      
      start_col <- end_col+1
    }
    
    addStyle(wb,sheet_name, bold_center, rows=12:13, cols=3:(3+length(target_vars)), gridExpand = TRUE)
    
    #Writes the main pivot table
    writeData(wb, sheet_name, export_df, xy=c(1,14),colNames= TRUE)
    addStyle(wb, sheet_name, header_fill, rows=14, cols=1:ncol(export_df), gridExpand= TRUE)
    
    addStyle(wb,sheet_name,style_num, rows= 15:(14+nrow(export_df)),cols=num_cols, gridExpand=TRUE)
    addStyle(wb,sheet_name,style_meta, rows= 15:(14+nrow(export_df)),cols=c(1, 3), gridExpand=TRUE)
  
    
}

#Saves the finished workbook
  time<- Sys.time()
  output_file <- file.path(paste0(Results_Folder,"\\","Processed_PDFs","_",format(time,"%m-%d"), ".xlsx"))
  
  saveWorkbook(wb, output_file, overwrite= TRUE)


cat("Results Saved to:\n", output_file,"\n")
