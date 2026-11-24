Sys.setenv(OMP_THREAD_LIMIT = "1")

##############################
#         Libaries           #
##############################

required_packages <- c("dplyr", "tidyr", "stringr", "tibble",
                       "openxlsx", "pdftools", "magick", "tesseract")

missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages) > 0) install.packages(missing_packages)

suppressPackageStartupMessages(
  invisible(lapply(required_packages, library, character.only = TRUE))
)

##############################
#         Settings           #
##############################


OCR_DPI <- 300 #OCR Resolution (DPI)

ROW_TOLERANCE <- 0.6 #Maximum Vertical row tolerance (Text Heights)

MAX_GAP_HEIGHTS <- 25 #Maximum label to value search distance (text heights)

MIN_WORD_CONFIDENCE <- 75 #Minimum OCR confidence (%), judged on the MEDIAN of the agreeing reads
TEG_MIN_CONFIDENCE <- 60 #Lower threshold for TEG pages (faint print scores lower even when right)

TIMEPOINTS <- c("Baseline", "EOS", "EOR", "20%", "15%", "10%", "EOB", "1HR", "24HR") #Filled in row order

OUTLIER_FACTOR <- 8 #Pink highlight for values this many times above/below the subject's median (was 10)

REREAD_VALUES <- TRUE #Re-read values from individual crops and vote

ALWAYS_OCR_TYPES <- c("ABG", "TEG") #Page Types always OCR'd from images

SKIP_PAGES <- c(1) #Pages to skip in every PDF

DARKEN_TYPES <- c("TEG", "ABG") #Page types also read from a darkened copy (more confident word kept)

DARKEN_LEVELS <- c(TEG = 65, ABG = 50) #Darkening strength per page type (% grey that becomes black)
#TEG 65: faint print. ABG 50: crisp print - at 50 the darkened pass read
#7.512 / 7.504 right where plain OCR read 7.612 / 7.604

BELOW_MATCH_TYPES <- c("TEG") #Checks only TEG for below values

# ------------ Re-reads & Voting ------------

EXTRA_READS_WHEN_DISPUTED <- TRUE #Extra reads (3x, darkened, wider crop) when reads disagree
DISSENT_FLAG_VARIABLES <- c("pO2", "LAC") #Flag these whenever any read disagrees (nothing else can check them)
CRITICAL_MIN_CONFIDENCE <- 85 #Stricter threshold (median of agreeing reads) for the variables above
FIND_DECIMAL_POINTS <- TRUE #Look for the decimal point in the image itself (fixes "154" -> 15.4, leaves a real 19 alone)

# ------------ Blood Gas Check (ABG) ------------

FIX_BLOOD_GAS <- TRUE #Correct pH / pCO2 / HCO3 misreads using the analyser's own equations
FLAG_BLOOD_GAS_FIXES <- FALSE #Also flag values BOTH equations confirmed (listed in the Correction column either way;
#corrections from one equation alone are always flagged)
BLOOD_GAS_PK <- 6.095 #pK the ABL90 uses (measured on 14 correctly read pages: 6.093-6.097)
PH_TOLERANCE <- 0.006 #Allowed gap between printed pH and the pH implied by pCO2 & HCO3
BE_TOLERANCE <- 0.3 #Allowed gap between printed and calculated base excess (mmol/L)
DIGIT_CONFUSIONS <- list(c("5", "6"), c("1", "4")) #Digit pairs this font confuses

# ------------ OCR Debugging ------------ 

SAVE_OCR_DEBUG <- TRUE #Save an annotated picture of every lab page (any page type) and of page 1
DEBUG_BOX_PADDING <- 0.2 #Space between a word and its box, as a share of the text height (0.15-0.25)

# ------------ Page Orientation ------------

MAX_TILT_DEGREES <- 20 #Maximum page tilt to correct (degrees)
MIN_TILT_TO_FIX <- 0.3 #Minimum tilt to correct (degrees)
TILT_CHECK_DPI <- 75 #Resolution for tilt detection (DPI)
ORIENTATION_CHECK_DPI <- 100 #Resolution for orientation detection (DPI)

##############################
#         Settings           #
##############################

#Finds the PDF files
if(PDF_File_Path != " "){
  Folder_Path <- normalizePath(gsub('"',"",PDF_File_Path),winslash ="/",mustWork=TRUE)
} else{ 
  Folder_Path <- choose.dir() 
} 

#Gets the folder of the previous
Parent_Directory<-dirname(Directory)

#Final Results folder
Results_Folder<-file.path(Parent_Directory,paste("Processed PDFs"))
OCR_Debug_Folder<- file.path(Results_Folder, "OCR Scanned Sheets")

if(!dir.exists(Results_Folder)){
  dir.create(Results_Folder,recursive = TRUE, showWarnings = FALSE)
}

if(!dir.exists(OCR_Debug_Folder)){
  dir.create(OCR_Debug_Folder,recursive = TRUE, showWarnings = FALSE)
}


#==============================================================================
# 4. OCR engines
#==============================================================================
null_device <- if (.Platform$OS.type == "windows") "NUL" else "/dev/null"

# Whole pages: automatic layout. tessedit_do_invert = 0 skips a pointless
# "is this white text on black?" pass.
page_engine <- tesseract("eng", options = list(
  tessedit_do_invert = "0",
  user_defined_dpi   = as.character(OCR_DPI),
  debug_file         = null_device
))

# Orientation test: "one uniform block of text" (page-seg mode 6). Unlike the
# automatic layout mode, this mode does NOT quietly read sideways text, so a
# page only scores well when it is the right way up.
block_engine <- tesseract("eng", options = list(
  tessedit_do_invert     = "0",
  tessedit_pageseg_mode  = "6",   # REQUIRED: without it sideways pages score as upright
  user_defined_dpi       = as.character(ORIENTATION_CHECK_DPI),
  debug_file             = null_device
))

# Single value crops: "treat the image as one line of text" (page-seg mode 7).
# No character whitelist on purpose: a whitelist forces "s" in "17.3s" to
# become a digit, which is exactly how PT 7.3s turned into 7.38.
line_engine <- tesseract("eng", options = list(
  tessedit_do_invert     = "0",
  tessedit_pageseg_mode  = "7",
  user_defined_dpi       = as.character(OCR_DPI),
  debug_file             = null_device
))


# Digits-only read of the NUMBER part of a "U/L" value, with the unit cut off.
# Next to the letters "U/L", Tesseract tends to read the digits as letters
# too (41U/L -> "A1U/L"); without the letters in view, and limited to digits,
# it can't. Only used on crops that contain no unit, so a whitelist can't
# turn a unit letter into a digit (the "7.3s" -> 7.38 problem).
digit_engine <- tesseract("eng", options = list(
  tessedit_do_invert      = "0",
  tessedit_pageseg_mode   = "7",
  tessedit_char_whitelist = "0123456789.",
  user_defined_dpi        = as.character(OCR_DPI),
  debug_file              = null_device
))


#==============================================================================
# 5. Dictionaries
#==============================================================================

# How each lab label can appear after OCR. Matched case-insensitively against
# the cleaned token; the first matching row wins, so order matters
# (pCO2 must come before pO2).
LABEL_PATTERNS <- tribble(
  ~standard,    ~pattern,                      # spellings seen in real output
  # Blood gas
  "pH",         "^[po][hl]$",                  # pH, oH, pl
  "pCO2",       "^p[co][o0][,.;:2z]*$",        # pCO2, pCO, pco, poo, pC02, pCOZ
  "pO2",        "^p[o0d][,.;:2z]*$|^00,$",     # pO2, pO, po, p0., pd, po;, pOZ
  "LAC",        "^[coe]?l{1,2}\\.?ac$|^nae$",  # LAC, cLac, oLac, eLac, cl.ac, clLac
  "HCO3",       "^[coe6]?hco",                 # cHCO3-(P)c, 6HCO3  (used for checking only)
  "ctHb",       "^[ceo6]t?hb$",                # ctHb, etHb, otHb   (used for checking only)
  "ABE",        "^abe",                        # ABEc, ABEg         (used for checking only)
  # CBC
  "WBC",        "^w[bea]c$",                   # WBC, WaC, wec
  "RBC",        "^rbc$",
  "HGB",        "^(hgb|hb)$",
  "HCT",        "^hct$",
  "PLT",        "^p[l1i]t$",
  "MCV",        "^mcv$",                       # checking only
  "MCHC",       "^mchc$",                      # checking only
  # Chemistry
  "GGT",        "^ggt$",
  "AST",        "^a[s5]t$",                    # AST, A5T
  "ALT",        "^a[l1i|]t$",                  # ALT, AIT, A1T
  "AMY",        "^amy$",
  "LDH",        "^l[od]h$",                    # LDH, LOH
  "CREA",       "^crea$",
  "BUN",        "^bu[nm]$",                    # BUN, BUM
  "BUN.CREA",   "^bun/crea$",                  # checking only
  "GLU",        "^[co]?gl[uh]$|^ogh$",         # GLU, cGlu, oGh
  "TG",         "^tg$",
  # TEG
  "R.Time",     "^r:?$",
  "K.Time",     "^ki?:?$",                     # K, K:, Ki:
  "Angle",      "^an[gqo][l1]e:?$",            # Angle, Anole, Anqle
  "MA.Min",     "^ma:?$",
  # Coagulation
  "APTT",       "^aptt$",
  "PT",         "^pt$",
  "TT",         "^tt$",
  "Fib",        "^fib$"
)

# Hard-coded label misreads from the stress test (exact match, any case).
# Unlike LABEL_PATTERNS these are short, odd spellings ("te", "Pi", "Ww")
# that could appear elsewhere on a page, so each one only counts on the page
# type it was seen on: "te" means TT on a Coag page and nothing anywhere else.
# To add one: copy a line and change the three values.
LABEL_ALIASES <- tribble(
  ~page_type, ~alias,  ~standard,
  # Blood gas
  "ABG",      "pcoO,", "pCO2",
  "ABG",      "po,",   "pO2",
  "ABG",      "pa,",   "pO2",
  # CBC
  "CBC",      "weee",  "WBC",
  "CBC",      "HCcT",  "HCT",
  # Chemistry
  "CMP",      "1G",    "TG",
  "CMP",      "AUT",   "ALT",
  "CMP",      "GST",   "GGT",
  "CMP",      "Gar",   "GGT",
  # Coagulation
  "Coag",     "PF",    "PT",
  "Coag",     "Py",    "PT",
  "Coag",     "PI",    "PT",    # also Pi, pI (matching ignores case)
  "Coag",     "TH",    "TT",
  "Coag",     "Ww",    "TT",
  "Coag",     "EG",    "TT",
  "Coag",     "Fid",   "Fib",
  "Coag",     "fio",   "Fib",
  "Coag",     "fi0",   "Fib"
)

# One-off OCR misreads seen in earlier runs (exact token -> replacement).
# Most are probably no longer needed now that values are re-read from crops;
# they are kept so nothing that used to work stops working.
LEGACY_TOKEN_FIXES <- c(
  "go?" = "67", "pll" = "2", "pul" = "2", "suyl" = "5", "sul" = "5",
  "agual" = "6", "zit" = "2.7", "a.f" = "8.7", "su/l" = "5U/L",
  "su/l%" = "5U/L", "l0%" = "10%"
)

# Which variables belong on which page type
VALID_TARGETS <- list(
  ABG  = c("pH", "pCO2", "pO2", "LAC"),
  CBC  = c("WBC", "RBC", "HGB", "HCT", "PLT"),
  CMP  = c("GGT", "AST", "ALT", "AMY", "LDH", "CREA", "BUN", "GLU", "TG"),
  TEG  = c("R.Time", "K.Time", "Angle", "MA.Min"),
  Coag = c("APTT", "PT", "TT", "Fib")
)

# Helper values that are read only to cross-check the targets
CHECK_ONLY_VARIABLES <- c("HCO3", "ctHb", "ABE", "MCV", "MCHC", "BUN.CREA")

# Labels that identify each kind of printout, and how many of them must be read
# before a page is given that type. Counting (instead of requiring every label)
# means ONE misread label no longer throws away the whole page.
PAGE_FINGERPRINTS <- list(
  ABG  = c("pH", "pCO2", "pO2", "LAC", "HCO3"),
  CBC  = c("WBC", "RBC", "HGB", "HCT", "PLT", "MCV", "MCHC"),
  CMP  = c("GGT", "AST", "ALT", "AMY", "LDH", "CREA", "BUN", "BUN.CREA", "GLU", "TG"),
  Coag = c("APTT", "PT", "TT", "Fib")
)
MIN_FINGERPRINT_LABELS <- c(ABG = 2, CBC = 3, CMP = 3, Coag = 3)

# Generous physiological limits. Anything outside is almost surely a misread
# (usually a lost or extra decimal point). Widen if your model needs it.
PLAUSIBLE_RANGE <- tribble(
  ~variable, ~low,  ~high,
  "pH",       0,   8.0,
  "pCO2",     0,     150,
  "pO2",      0,    700,
  "LAC",      0,     30,
  "WBC",      0,   100,
  "RBC",      0,   15,
  "HGB",      0,     25,
  "HCT",      0,     75,
  "PLT",      0,     2500,
  "GGT",      0,     1000,
  "AST",      0,     10000,
  "ALT",      0,     10000,
  "AMY",      0,     5000,
  "LDH",      0,     10000,
  "CREA",     0,     30,
  "BUN",      0,     300,
  "GLU",      0,     1500,
  "TG",       0,     3000,
  "R.Time",   0,     120,
  "K.Time",   0,     60,
  "Angle",    0,     90,
  "MA.Min",   0,     100,
  "APTT",     5,     400,
  "PT",       3,     200,
  "TT",       3,     300,
  "Fib",      0,     15
)

MAX_DECIMALS <- c(APTT=2, PT=2, TT=2, Fib=2)

trim_decimals <- function(variable, value){
  keep <- unname(MAX_DECIMALS[variable])
  if(length(keep)==0 || is.na(keep)) return(value)
  sub(sprintf("^(-?\\d*\\.\\d{%d})\\d+$", keep), "\\1", value)
}

# How each value is printed. A read that doesn't fit is thrown out before the
# vote: "7.62" for pH (a dropped digit), "47" for HGB 4.7, "08" for pO2 108.
# Values printed as "< x" / "> x" (detection limits) are exempt.
VALUE_FORMATS <- c(
  pH   = "^[67]\\.\\d{3}$",             # 7.536 (an "8.532" is a misread 7)
  pCO2 = "^\\d{2}\\.\\d$|^\\d{3}$",     # 35.2 (100 and up print without a decimal)
  pO2  = "^\\d{2}\\.\\d$|^\\d{3}$",     # 96.1, 108
  LAC  = "^\\d{1,2}(\\.\\d)?$",         # 1.5, 13.1, 19 (whole numbers do occur)
  HCO3 = "^\\d{1,2}\\.\\d$",            # 24.2
  HGB  = "^\\d{1,2}\\.\\d{1,2}$"        # 4.7
)

# Arithmetic the analysers themselves do. If the printed numbers don't
# satisfy it, at least one of them was misread.
CONSISTENCY_CHECKS <- list(
  list(
    page_type = "CBC",
    needs     = c("HGB", "HCT", "MCHC"),
    flag      = c("HGB", "HCT"),
    passes    = function(v) abs(v[["HGB"]] / v[["HCT"]] * 100 - v[["MCHC"]]) <= 1.0,
    message   = "HGB / HCT doesn't match the printed MCHC - check both"
  ),
  list(
    page_type = "CBC",
    needs     = c("HCT", "RBC", "MCV"),
    flag      = c("HCT", "RBC"),
    passes    = function(v) abs(v[["HCT"]] * 10 / v[["RBC"]] - v[["MCV"]]) <= 1.5,
    message   = "HCT / RBC doesn't match the printed MCV - check both"
  ),
  list(
    page_type = "CMP",
    setting   = "CHECK_BUN_CREA_RATIO",
    needs     = c("BUN", "CREA", "BUN.CREA"),
    flag      = c("BUN", "CREA"),
    passes    = function(v) abs(v[["BUN"]] / v[["CREA"]] - v[["BUN.CREA"]]) <= 0.02 * v[["BUN.CREA"]],
    message   = "BUN / CREA doesn't match the printed ratio - check both"
  )
)

# Words that only appear on the hand-filled experiment forms. Those forms
# contain printed "APTT: PT: TT: Fib:" boxes, so without this they were
# being mistaken for coag reports.
FORM_MARKERS <- c("Buprenorphine", "Hemorrhage", "USDA", "Scenario",
                  "Experiment", "Experimental", "Tele")

# Model / subject ID from a PDF file name: everything before the first
# separated number, then a space, then that number.
#   "AWBAEM-16_Digitized Chart (Example)_ACR_12122024.pdf" -> "AWBAEM 16"
#   "B-LR 12.pdf"                                          -> "B-LR 12"
#   "TA-EMv6.0.3-IV-ALB-11.pdf"                            -> "TA-EMv6.0.3-IV-ALB 11"
# A "number" here must sit between separators (- _ space) and end at a
# separator, "(", "." or the end of the name - so "v6.0.3" or the date
# "12122024" further along are never mistaken for the model number.
make_subject_id <- function(source_file) {
  stem  <- sub("\\.pdf$", "", basename(source_file), ignore.case = TRUE)
  parts <- str_match(stem, "^(.+?)[-_ ]+(\\d+)(?=$|[-_ .(])")
  ifelse(is.na(parts[, 1]), stem, paste(parts[, 2], parts[, 3]))
}


#==============================================================================
# 6. Small text helpers
#==============================================================================

# Units printed straight after a value on the analyser reports
VALUE_UNITS <- "(U/L|IU/L|mg/dL|g/dL|umol/L|mmol/L|mEq/L|K/uL|M/uL|10\\^?3/[A-Za-z]+|%)"

# "U/L" values: a 1-4 character number straight before "U/L" (or "UL").
# Letters OCR put in place of digits there, from the stress test, and the
# digit(s) each one stands for. Some are ambiguous, so they list every
# possibility: T was 1 in "T1U/L" (11) but 7 in "ATU/L" (47); S was 5 in
# "SU/L" but 9 in "ASU/L" (49); Q was 9 in "QU/L" but just noise in "2QU/L"
# ("" = drop the letter).
UL_PATTERN    <- "^([<>]?\\s*)(\\S{1,4}?)\\s*[Uu]/?[Ll]$"
UL_LOOKALIKES <- list(
  A = "4", S = c("5", "9"), "\u00a7" = "5", O = "0", o = "0", B = "8", J = "7",
  I = "1", l = "1", i = "1", Z = "2",
  T = c("1", "7"),
  Q = c("9", "")
)

# Every number a "U/L" token could stand for, e.g. "ATU/L" -> c("41", "47").
# Returns nothing if the token isn't a U/L value or has a letter not in the
# table above (so words are never turned into numbers).
ul_candidates <- function(token) {
  parts <- str_match(token, UL_PATTERN)
  if (is.na(parts[1, 1])) return(character(0))
  
  options <- lapply(strsplit(parts[1, 3], "")[[1]], function(ch) {
    if (grepl("^[0-9]$", ch)) ch else UL_LOOKALIKES[[ch]]
  })
  if (any(vapply(options, is.null, logical(1)))) return(character(0))
  
  combos     <- do.call(expand.grid, c(options, stringsAsFactors = FALSE))
  candidates <- unique(do.call(paste0, combos))
  candidates[grepl("^\\d{1,4}$", candidates)]
}

# Fixes letters OCR swaps for digits in value+unit tokens. In the chemistry
# analyser's font a "5" looks like "S", and the "g" of g/dL can read as "9":
#   "SU/L" -> "5U/L"     "OU/L" -> "0U/L"     "5.59/dL" -> "5.5g/dL"
# Only tokens that END in a known unit are touched, so words such as
# "Sample" or "BUN" are left alone.
fix_value_lookalikes <- function(x) {
  # U/L values: use the first candidate (ambiguous ones are settled by the re-read)
  for (k in which(grepl(UL_PATTERN, x))) {
    candidates <- ul_candidates(x[k])
    if (length(candidates) > 0) {
      x[k] <- paste0(str_match(x[k], UL_PATTERN)[, 2], candidates[1], "U/L")
    }
  }
  
  x <- sub("^([<>]?\\s*\\d*\\.?\\d+)9/dL$", "\\1g/dL", x)   # "5.59/dL"  -> "5.5g/dL"
  x <- sub("m9/dL$", "mg/dL", x)                                    # "0.0m9/dL" -> "0.0mg/dL"
  
  parts <- str_match(x, paste0("^([<>]?\\s*)([0-9SOoIlZB.]+)", VALUE_UNITS, "$"))
  has_letters <- !is.na(parts[, 3]) & grepl("[SOoIlZB]", parts[, 3])
  digits <- chartr("SOoIlZB", "5001128", parts[has_letters, 3])
  x[has_letters] <- paste0(parts[has_letters, 2], digits, parts[has_letters, 4])
  x
}

# Tidy one OCR/PDF token without changing what it means
clean_token <- function(text) {
  x <- trimws(as.character(text))
  x <- gsub("[–—_]", "-", x)                 # en/em dash, underscore -> "-"
  x <- gsub("^[(\\[|{]+", "", x, perl = TRUE)          # leading  ( [ | {
  x <- gsub("[)\\]|}]+$", "", x, perl = TRUE)          # trailing ) ] | }
  x <- sub("\\.$", "", x)                              # "30.7."   -> "30.7"
  x <- sub("^(\\d+),(\\d+)$", "\\1.\\2", x)            # "6,13"    -> "6.13"
  x <- sub("^(-?\\d+\\.\\d+)\\.\\d+$", "\\1", x)       # "3.1.4"   -> "3.1"
  x <- fix_value_lookalikes(x)
  
  fix <- LEGACY_TOKEN_FIXES[tolower(x)]
  x[!is.na(fix)] <- fix[!is.na(fix)]
  x
}

# Standard variable name for a label token, or NA if it isn't a known label
# Standard variable name for a label token, or NA if it isn't a known label.
#   page_type = NULL: while the page type is still being worked out, every
#                     alias counts (helps a Coag page with misread labels
#                     reach its 3-label minimum)
#   page_type = "Coag" etc.: only that page type's aliases count
standardize_label <- function(clean_text, page_type = NULL) {
  result <- rep(NA_character_, length(clean_text))
  for (i in seq_len(nrow(LABEL_PATTERNS))) {
    still_unknown <- is.na(result)
    hit <- still_unknown & grepl(LABEL_PATTERNS$pattern[i], clean_text, ignore.case = TRUE)
    result[hit] <- LABEL_PATTERNS$standard[i]
  }
  
  # Hard-coded misreads (exact match, ignoring case)
  aliases <- if (is.null(page_type)) LABEL_ALIASES else
    LABEL_ALIASES[LABEL_ALIASES$page_type == page_type, ]
  alias_row <- match(tolower(trimws(clean_text)), tolower(aliases$alias))
  use_alias <- is.na(result) & !is.na(alias_row)
  result[use_alias] <- aliases$standard[alias_row[use_alias]]
  result
}

# The number a token starts with ("17.3s" -> "17.3", "<2U/L" -> "2"),
# or NA for things that look numeric but aren't values
# (times 06:28, dates 11/12/2024, units 10^3/mm3, ranges 2.5-13.8).
parse_number_text <- function(clean_text) {
  number <- str_match(clean_text, "^[<>]?\\s*(-?\\d*\\.?\\d+)")[, 2]
  not_a_value <- grepl("^\\d+\\s*[:/³^]", clean_text) |
    grepl("^\\d*\\.?\\d+\\s*-\\s*\\d", clean_text)
  number[not_a_value] <- NA_character_
  number
}

# Append a review reason to whatever reasons a cell already has
add_reason <- function(existing, new_reason) {
  ifelse(is.na(existing) | existing == "", new_reason,
         paste(existing, new_reason, sep = "; "))
}

# Column name used in the final Excel sheet for each variable
display_name <- function(standard_variable) {
  recode(standard_variable,
         "R.Time" = "CKHR time", "K.Time" = "CKH K",
         "Angle"  = "CKH angle", "MA.Min" = "CKH MA",
         "Time"   = "Clock Time")
}


#==============================================================================
# 7. Getting words (with positions) off a page
#==============================================================================

# Render one page as a gray image
render_page <- function(file_path, page_number) {
  bitmap <- suppressWarnings(pdf_render_page(file_path, page = page_number, dpi = OCR_DPI))
  image_read(bitmap) |> image_convert(colorspace = "gray")
}

# Words from the PDF's text layer, converted from points to pixels at OCR_DPI
# so they line up with a rendered image of the same page
tokens_from_text_layer <- function(page_words) {
  scale <- OCR_DPI / 72
  tibble(
    x = page_words$x * scale,
    y = page_words$y * scale,
    w = page_words$width * scale,
    h = page_words$height * scale,
    text = page_words$text,
    confidence = NA_real_,
    extraction_method = "PDF"
  )
}

# Words from Tesseract
tokens_from_ocr <- function(img) {
  words <- ocr_data(img, engine = page_engine)
  if (nrow(words) == 0) return(tibble())
  
  box <- str_split_fixed(words$bbox, ",", 4)
  storage.mode(box) <- "numeric"
  tibble(
    x = box[, 1],
    y = box[, 2],
    w = box[, 3] - box[, 1],
    h = box[, 4] - box[, 2],
    text = words$word,
    confidence = words$confidence,
    extraction_method = "OCR"
  )
}


#==============================================================================
# 7a. Page orientation: sideways, upside down, or tilted
#------------------------------------------------------------------------------
# Every page that gets OCR'd goes through two steps:
#   1. Straighten any tilt up to +/- MAX_TILT_DEGREES. Always done (~0.2 s).
#      This replaces image_deskew(), which was slower (2-3 s per page) and
#      misjudged tilts above about 7 degrees.
#   2. If the first OCR pass shows the page is sideways or upside down, try
#      all four quarter-turns on a small copy, keep the one Tesseract reads
#      best, rotate, and OCR again. Only those pages pay for this (~2-3 s).
#==============================================================================

# Rotate clockwise by `degrees`, filling the new corners with white
rotate_page <- function(img, degrees) {
  img |>
    image_background("white", flatten = FALSE) |>
    image_rotate(degrees) |>
    # Rotating by an odd angle leaves a hidden "page offset" on the image
    # (e.g. -102,-78 for a 3.6 degree turn). Tesseract ignores it, but
    # image_crop() measures from it - so re-read crops landed in the wrong
    # place on rotated pages (TEG crops read the range row below the value).
    image_repage()
}

# How many degrees the text lines are tilted (positive = running downhill to
# the right).
#
# How it works: text lines are horizontal bands of ink with white gaps between
# them. For each candidate angle we tip the ink pixels back by that angle and
# count the ink in each row. At the true angle the rows are crisp (full lines,
# empty gaps); at a wrong angle the lines smear across rows. The crispest
# angle wins: first to the nearest degree, then to the nearest 0.1 degree.
find_tilt_angle <- function(img) {
  small  <- image_resize(img, geometry_size_percent(TILT_CHECK_DPI / OCR_DPI * 100))
  pixels <- image_raster(small)                          # one row per pixel: x, y, col
  is_ink <- grDevices::col2rgb(pixels$col)[1, ] < 160    # dark pixels
  ink_x  <- pixels$x[is_ink]
  ink_y  <- pixels$y[is_ink]
  if (length(ink_x) < 500) return(0)                     # (nearly) blank page
  
  crispness <- function(angle) {
    row    <- round(ink_y - ink_x * tan(angle * pi / 180))
    counts <- tabulate(row - min(row) + 1)
    sum(diff(counts)^2)                                  # big jumps = crisp lines and gaps
  }
  crispest <- function(angles) angles[which.max(vapply(angles, crispness, numeric(1)))]
  
  nearest_degree <- crispest(seq(-MAX_TILT_DEGREES, MAX_TILT_DEGREES, by = 1))
  crispest(seq(nearest_degree - 1, nearest_degree + 1, by = 0.1))
}

straighten_page <- function(img) {
  tilt <- find_tilt_angle(img)
  if (abs(tilt) < MIN_TILT_TO_FIX) return(list(img = img, tilt = 0))
  
  straightened <- rotate_page(img, -tilt)
  
  # Safety check: the straightened page should now measure about 0 degrees.
  # If it measures worse, we turned the wrong way, so turn the other way.
  if (abs(find_tilt_angle(straightened)) > abs(tilt) / 2) {
    straightened <- rotate_page(img, tilt)
  }
  list(img = straightened, tilt = tilt)
}

# Looks at the words from an OCR pass and says whether the page seems to be
# the wrong way round. Returns NA when the page looks fine.
#   Sideways:    most words come back taller than they are wide.
#   Upside down: Tesseract still "finds" words, but almost none confidently.
orientation_problem <- function(tokens) {
  if (nrow(tokens) == 0) return(NA_character_)
  words <- tokens[nchar(tokens$text) >= 3, ]
  if (nrow(words) < 10) return(NA_character_)            # too little text to judge
  
  if (mean(words$h > words$w) > 0.4)          return("sideways")
  if (mean(words$confidence >= 60) < 0.3)     return("upside down or unreadable")
  NA_character_
}

# Tries 0, 90, 180 and 270 degrees (clockwise) on a small copy of the page and
# returns the turn whose text Tesseract reads most confidently.
find_quarter_turn <- function(img) {
  small <- image_resize(img, geometry_size_percent(ORIENTATION_CHECK_DPI / OCR_DPI * 100))
  
  readability <- function(turn) {
    words <- ocr_data(rotate_page(small, turn), engine = block_engine)
    good  <- words$confidence >= 60 & nchar(words$word) >= 3 & grepl("[A-Za-z]", words$word)
    sum(words$confidence[good])
  }
  
  turns <- c(0, 90, 180, 270)
  turns[which.max(vapply(turns, readability, numeric(1)))]
}

# The one function the rest of the script calls: returns the upright,
# straightened image, its OCR words, and a note saying what was fixed.
ocr_upright_page <- function(img) {
  straight <- straighten_page(img)
  img      <- straight$img
  tilt     <- straight$tilt
  tokens   <- tokens_from_ocr(img)
  turn     <- 0
  
  if (!is.na(orientation_problem(tokens))) {
    turn <- find_quarter_turn(img)
    if (turn != 0) {
      straight <- straighten_page(rotate_page(img, turn))
      img      <- straight$img
      tilt     <- straight$tilt
      tokens   <- tokens_from_ocr(img)
    }
  }
  
  note <- c(if (turn != 0) sprintf("turned %d deg", turn),
            if (tilt != 0) sprintf("straightened %+.1f deg", tilt))
  list(img = img, tokens = tokens, orientation = paste(note, collapse = ", "))
}

# A PDF text layer can also be sideways (the TEG graph pages). Their word
# boxes are taller than wide; such pages are sent to OCR instead.
text_layer_is_sideways <- function(page_words) {
  words <- page_words[nchar(page_words$text) >= 3, ]
  nrow(words) >= 10 && mean(words$height > words$width) > 0.4
}


#==============================================================================
# 8. Page classification
#==============================================================================
detect_page_type <- function(page_text) {
  if (length(page_text) == 0) return("UNKNOWN")
  
  # Hand-filled forms are never lab printouts
  form_marker_pattern <- paste0("^(", paste(FORM_MARKERS, collapse = "|"), ")")
  if (any(grepl(form_marker_pattern, page_text, ignore.case = TRUE))) return("UNKNOWN")
  
  labels   <- unique(standardize_label(clean_token(page_text)))
  all_text <- toupper(paste(page_text, collapse = " "))
  
  # Blood-gas analyser header: one blood-gas label is enough
  if (grepl("RADIOMETER|ABL90", all_text) && any(c("pH", "pCO2", "pO2") %in% labels)) return("ABG")
  
  # TEG labels are single letters (R, K, MA), so "Angle" must be there too
  # (or three of the four, since the faint labels are often misread)
  teg_labels <- c("R.Time", "K.Time", "Angle", "MA.Min")
  if (("Angle" %in% labels && any(c("R.Time", "MA.Min") %in% labels)) ||
      sum(teg_labels %in% labels) >= 3) return("TEG")
  
  # Everything else: count each panel's labels that were read and pick the
  # panel with the most, provided it reached its minimum
  found  <- vapply(PAGE_FINGERPRINTS, function(fp) sum(fp %in% labels), numeric(1))
  enough <- found >= MIN_FINGERPRINT_LABELS[names(found)]
  if (!any(enough)) return("UNKNOWN")
  names(found)[which.max(ifelse(enough, found, -1))]
}


#==============================================================================
# 9. Pairing each label with its value
#==============================================================================

# Splits tokens like "Hgb:13.8" into a label token and a value token
split_fused_tokens <- function(tokens, page_type = NULL) {
  parts <- str_match(tokens$clean, "^([A-Za-z][A-Za-z.]*)[:=]?\\s*([<>]?-?\\d*\\.?\\d+\\S*)$")
  label_part <- standardize_label(parts[, 2], page_type)
  fused <- which(is.na(tokens$label) & !is.na(label_part))
  if (length(fused) == 0) return(tokens)
  
  label_share <- nchar(parts[fused, 2]) / nchar(tokens$clean[fused])
  
  label_rows <- tokens[fused, ]
  label_rows$clean <- parts[fused, 2]
  label_rows$label <- label_part[fused]
  label_rows$w     <- tokens$w[fused] * label_share
  
  value_rows <- tokens[fused, ]
  value_rows$clean  <- parts[fused, 3]
  value_rows$number <- parse_number_text(parts[fused, 3])
  value_rows$x      <- tokens$x[fused] + label_rows$w
  value_rows$w      <- tokens$w[fused] - label_rows$w
  
  bind_rows(tokens[-fused, ], label_rows, value_rows)
}

# TRUE for numbers that are one end of a reference range printed as separate
# words, e.g. "55" "—" "78", "4.6K" "—10.9K" or "2—" "8". Without this, a
# label whose value OCR missed (faint TEG text) grabbed the range printed
# underneath it ("Variable / Value / Range" columns).
#
# Kept deliberately strict, because Tesseract also invents tall "=" marks
# between ABG values and their units: only real dash characters count, the
# dash must be thin (a real dash is a fraction of the text height), and a
# separate dash needs a number on BOTH sides. Checked on all 65 test pages:
# only range numbers are marked.
mark_range_parts <- function(tokens) {
  dash_chars <- "[-\u2013\u2014]"
  dash_only  <- grepl(paste0("^", dash_chars, "+$"), tokens$text)                 # "—"
  dash_num   <- grepl(paste0("^", dash_chars, "\\s*\\d"), tokens$text)            # "—10.9K"
  num_dash   <- grepl(paste0("^\\(?\\d*\\.?\\d+K?", dash_chars, "$"), tokens$text)  # "2—"
  is_number  <- !is.na(tokens$number)
  
  in_range <- is_number & num_dash
  
  for (d in which(dash_only | dash_num)) {
    same_row  <- is_number & seq_len(nrow(tokens)) != d &
      abs(tokens$center_y - tokens$center_y[d]) <= ROW_TOLERANCE * pmax(tokens$h, tokens$h[d])
    gap_left  <- tokens$x[d] - (tokens$x + tokens$w)
    gap_right <- tokens$x - (tokens$x[d] + tokens$w[d])
    left  <- which(same_row & gap_left  >= -2 & gap_left  <= 2 * tokens$h)
    right <- which(same_row & gap_right >= -2 & gap_right <= 2 * tokens$h)
    nearest_left  <- left[which.max(tokens$x[left])]
    nearest_right <- right[which.min(tokens$x[right])]
    
    if (dash_only[d]) {
      if (length(left) == 0 || length(right) == 0) next                      # needs both ends
      if (tokens$h[d] > 0.5 * max(tokens$h[c(left, right)])) next            # too tall for a dash
      in_range[c(nearest_left, nearest_right)] <- TRUE
    } else if (length(left) > 0) {
      # "—10.9K" with a number in front is the top of a range; on its own
      # (e.g. "-3.3") it's just a negative value
      in_range[c(nearest_left, d)] <- TRUE
    }
  }
  in_range
}

pair_labels_to_values <- function(tokens, page_type = NULL) {
  tokens <- tokens |>
    mutate(candidates = vapply(text, function(t) paste(ul_candidates(trimws(t)), collapse = "|"),
                               character(1), USE.NAMES = FALSE),
           clean  = clean_token(text),
           label  = standardize_label(clean, page_type),
           number = parse_number_text(clean)) |>
    split_fused_tokens(page_type) |>
    mutate(center_y = y + h / 2)   # (used by mark_range_parts below too)
  
  labels <- tokens |> filter(!is.na(label))
  # Numbers that are one end of a "2 — 8" reference range are never values
  tokens$in_range <- mark_range_parts(tokens)
  values <- tokens |> filter(is.na(label), !is.na(number), !in_range)
  if (nrow(labels) == 0 || nrow(values) == 0) return(tibble())
  
  pairs <- vector("list", nrow(labels))
  
  for (i in seq_len(nrow(labels))) {
    lab        <- labels[i, ]
    label_end  <- lab$x + lab$w
    gap        <- values$x - label_end
    row_height <- pmax(values$h, lab$h)
    
    # 1st choice: nearest number to the RIGHT on the same row
    same_row <- abs(values$center_y - lab$center_y) <= ROW_TOLERANCE * row_height
    to_right <- gap > -0.5 * lab$h & gap <= MAX_GAP_HEIGHTS * lab$h
    candidates <- which(same_row & to_right)
    method <- "same row"
    
    # 2nd choice: number directly BELOW the label (e.g. TEG summary strip)
    if (length(candidates) == 0) {
      if (is.null(page_type) || !page_type %in% BELOW_MATCH_TYPES) next 
      overlaps <- values$x < label_end + lab$h & values$x + values$w > lab$x - lab$h
      below    <- values$y > lab$y + lab$h / 2 & values$y - (lab$y + lab$h) <= 3 * lab$h
      candidates <- which(overlaps & below)
      method <- "below"
      if (length(candidates) == 0) next
      best <- candidates[which.min(values$y[candidates])]
    } else {
      best <- candidates[which.min(values$x[candidates])]
    }
    val <- values[best, ]
    
    
    pairs[[i]] <- tibble(
      Variable              = lab$text,
      Standardized_Variable = lab$label,
      Page_Read             = trim_decimals(lab$label, val$number),
      Value_Text            = val$text,
      Variable_X = lab$x, Variable_Y = lab$y, Variable_H = lab$h,
      Value_X = val$x, Value_Y = val$y, Value_W = val$w, Value_H = val$h,
      Page_Confidence   = val$confidence,
      Page_Candidates   = val$candidates,   # e.g. "41|47" when a letter was ambiguous
      Match_Method      = method,
      extraction_method = val$extraction_method
    )
  }
  
  pairs <- bind_rows(pairs)
  if (nrow(pairs) == 0) return(tibble())
  
  pairs |>
    # If a label appears twice on a page, prefer the same-row match, then the topmost
    arrange(Match_Method != "same row", Variable_Y) |>
    distinct(Standardized_Variable, .keep_all = TRUE)
}


#==============================================================================
# 10. Re-reading values and flagging doubtful ones
#==============================================================================

# OCR one small image as a single line; returns the number and min confidence
read_number_from_crop <- function(crop, engine = line_engine) {
  words <- ocr_data(crop, engine = engine)
  if (nrow(words) == 0) return(list(number = NA_character_, confidence = 0))
  list(
    number     = parse_number_text(clean_token(paste(words$word, collapse = ""))),
    confidence = min(words$confidence)
  )
}

# TRUE where a value is inside the plausible range for its variable
# (variables without a range always count as plausible)
is_plausible <- function(variable, value) {
  number <- suppressWarnings(as.numeric(value))
  row    <- match(variable, PLAUSIBLE_RANGE$variable)
  low    <- PLAUSIBLE_RANGE$low[row]
  high   <- PLAUSIBLE_RANGE$high[row]
  !is.na(number) & (is.na(row) | (number >= low & number <= high))
}

# TRUE where a read is usable: plausible AND printed the way that variable is
# printed (VALUE_FORMATS)
is_valid_read <- function(variable, value) {
  format <- unname(VALUE_FORMATS[variable])
  fits   <- if (length(format) == 0 || is.na(format)) TRUE else grepl(format, value)
  is_plausible(variable, value) & fits
}

# A lost decimal point is the commonest misread ("77.4" -> "774"). For a
# whole-number read that is outside the plausible range, tries putting the
# point back one or two digits from the end and returns the first usable
# result, or NA.
restore_decimal <- function(variable, value) {
  if (is.na(value) || !grepl("^\\d{2,}$", value)) return(NA_character_)
  n <- nchar(value)
  for (decimals in 1:2) {
    if (decimals >= n) break
    candidate <- paste0(substr(value, 1, n - decimals), ".", substr(value, n - decimals + 1, n))
    if (is_valid_read(variable, candidate)) return(candidate)
  }
  NA_character_
}

# Where the digits of a "123U/L" crop end, measured from the image: printed
# characters are separated by thin white gaps, so counting the dark
# "clusters" and taking off the unit's characters ("U", "/", "L") gives the
# number of digits. Small marks (specks, the dot of a "<") are ignored.
# Returns the x position to cut at, or NA when the gaps don't add up.
# (On the test chemistry pages this read 20 of 22 U/L values correctly.)
find_digit_end <- function(crop, line_h, unit_chars) {
  pixels <- image_raster(crop)
  is_ink <- grDevices::col2rgb(pixels$col)[1, ] < 160
  ink_x  <- pixels$x[is_ink]
  ink_y  <- pixels$y[is_ink]
  if (length(ink_x) == 0) return(NA_real_)
  
  columns  <- sort(unique(ink_x))
  run_id   <- cumsum(c(1, diff(columns) > 1))          # runs of touching columns
  clusters <- do.call(rbind, lapply(split(columns, run_id), function(xs) {
    ys <- ink_y[ink_x %in% xs]
    c(start = min(xs), end = max(xs), height = max(ys) - min(ys) + 1)
  }))
  clusters <- clusters[clusters[, "height"] >= 0.4 * line_h, , drop = FALSE]
  
  n_digits <- nrow(clusters) - unit_chars
  if (n_digits < 1) return(NA_real_)
  (clusters[n_digits, "end"] + clusters[n_digits + 1, "start"]) / 2 + 1
}

# Looks for a decimal point in a value's crop: a small mark sitting on the
# baseline with a digit on each side. Returns how many characters come before
# it, or NA when there is none. Checked on 171 numbers from 11 test pages: it
# found every printed decimal point, never one that isn't there, and the
# decimal point in 16 numbers OCR had read without one (2.7 read as "27",
# 77.8 as "778", 1.8 as "18").
find_decimal_point <- function(crop, line_h) {
  pixels <- image_raster(crop)
  is_ink <- grDevices::col2rgb(pixels$col)[1, ] < 160
  ink_x  <- pixels$x[is_ink]
  ink_y  <- pixels$y[is_ink]
  if (length(ink_x) == 0) return(NA_integer_)
  
  columns <- sort(unique(ink_x))
  run_id  <- cumsum(c(1, diff(columns) > 1))          # runs of touching columns = marks
  shapes  <- do.call(rbind, lapply(split(columns, run_id), function(xs) {
    ys <- ink_y[ink_x %in% xs]
    c(left = min(xs), right = max(xs), top = min(ys), bottom = max(ys))
  }))
  height  <- shapes[, "bottom"] - shapes[, "top"] + 1
  width   <- shapes[, "right"] - shapes[, "left"] + 1
  is_char <- height >= 0.5 * line_h
  if (sum(is_char) < 2) return(NA_integer_)
  
  baseline <- max(shapes[is_char, "bottom"])
  is_dot   <- !is_char & height <= 0.3 * line_h & width <= 0.4 * line_h &
    abs(shapes[, "bottom"] - baseline) <= 0.15 * line_h
  for (d in which(is_dot)) {
    before <- sum(is_char & shapes[, "right"] < shapes[d, "left"])
    after  <- sum(is_char & shapes[, "left"]  > shapes[d, "right"])
    if (before >= 1 && after >= 1) return(as.integer(before))
  }
  NA_integer_
}

# Puts the decimal point the image shows into reads that lost it:
# "154" with a point after 2 characters -> "15.4". Reads that already have a
# point, or whose length doesn't allow it, are left alone.
add_decimal_point <- function(number, digits_before) {
  if (is.na(digits_before)) return(number)
  fix <- !is.na(number) & grepl("^\\d+$", number) & nchar(number) > digits_before
  number[fix] <- paste0(substr(number[fix], 1, digits_before), ".",
                        substring(number[fix], digits_before + 1))
  number
}

# Decides a value from its reads (a tibble: source, number, confidence),
# all already checked with is_valid_read(). Returns the value (or NA) and the
# review reason ("" = no flag).
#   2+ reads agree        -> that value; flagged only if none of them was confident
#   only one usable read  -> that value; flagged only if not confident
#   no majority           -> blank, "nothing agrees" (a lone digits-only read
#                            can't cause this on its own: it is set aside first)
#   strict = TRUE (pO2, LAC): judged against CRITICAL_MIN_CONFIDENCE instead,
#   since nothing else can check these values. TEG pages use TEG_MIN_CONFIDENCE.
vote_on_reads <- function(reads, strict = FALSE, page_type = "") {
  threshold <- if (strict) CRITICAL_MIN_CONFIDENCE else MIN_WORD_CONFIDENCE
  if (identical(page_type, "TEG")) threshold <- min(threshold, TEG_MIN_CONFIDENCE)
  if (nrow(reads) == 0) return(list(value = NA_character_, reason = "value could not be read"))
  
  votes <- table(reads$number)
  if (max(votes) < 2 && length(votes) > 1) {
    without_digits <- reads[reads$source != "digits only", ]
    if (nrow(without_digits) > 0 && length(unique(without_digits$number)) == 1) {
      reads <- without_digits
      votes <- table(reads$number)
    }
  }
  
  if (max(votes) >= 2) {
    winner <- names(votes)[which.max(votes)]
    # Median of the agreeing reads: one low read (the darkened or digits-only
    # read usually scores low even when right) doesn't flag the value; most
    # of the agreeing reads being unsure does.
    conf   <- median(reads$confidence[reads$number == winner])
    reason <- if (conf < threshold) sprintf("reads agree but low confidence (median %.0f)", conf) else ""
    return(list(value = winner, reason = reason))
  }
  if (length(votes) == 1) {
    reason <- if (reads$confidence[1] < threshold) sprintf("only one read (confidence %.0f)", reads$confidence[1]) else ""
    return(list(value = reads$number[1], reason = reason))
  }
  list(value = NA_character_,
       reason = sprintf("nothing agrees: %s", paste(unique(reads$number), collapse = " / ")))
}

# Re-reads each value from its own crop and votes with the page-level read.
#   Reads: page, 1x crop, 2nd read (2x crop; for U/L values the number part
#   only, read digits-only), darkened crop on TEG pages.
#   Reads that aren't plausible or don't fit the printed format are dropped.
#   If the reads are disputed, 3 extra reads are made (3x, darkened, wider
#   crop) and the vote is redone - see vote_on_reads() for the rules.
#   pO2 and LAC (DISSENT_FLAG_VARIABLES) are flagged whenever any usable read
#   disagrees, since nothing else on the page can check them.
reread_values <- function(pairs, page_img, dark_img = NULL, page_type = "") {
  pairs$Reread_1x   <- NA_character_
  pairs$Reread_2x   <- NA_character_
  pairs$Reread_dark <- NA_character_
  pairs$Extra_Reads <- NA_character_
  pairs$Correction  <- ""
  pairs$Value <- pairs$Page_Read
  pairs$Review_Reason <- ""
  
  page_img <- image_repage(page_img)               # crops must use OCR's coordinates
  if (!is.null(dark_img)) dark_img <- image_repage(dark_img)
  info <- image_info(page_img)
  
  for (i in seq_len(nrow(pairs))) {
    variable <- pairs$Standardized_Variable[i]
    
    #---- where to crop: exactly one text line
    # The height comes from the LABEL (a clean one-line box): OCR sometimes
    # returns value boxes two rows tall, and centring on such a box lands
    # between rows.
    #   same-row match: centre on the label's row
    #   below match:    start at the top of the value box
    line_h <- min(pairs$Variable_H[i], pairs$Value_H[i])
    center_y <- if (pairs$Match_Method[i] == "same row") {
      pairs$Variable_Y[i] + pairs$Variable_H[i] / 2
    } else {
      pairs$Value_Y[i] + line_h / 2
    }
    pad_y <- round(line_h * 0.35)
    pad_x <- round(line_h * 0.5)
    
    left <- max(0, round(pairs$Value_X[i] - pad_x))
    top  <- max(0, round(center_y - line_h / 2 - pad_y))
    w    <- min(info$width  - left, round(pairs$Value_W[i] + 2 * pad_x))
    h    <- min(info$height - top,  round(line_h + 2 * pad_y))
    if (w <= 0 || h <= 0) {
      pairs$Review_Reason[i] <- "not re-read (value lies outside the page image)"
      next
    }
    
    crop_raw <- image_crop(page_img, geometry_area(w, h, left, top))
    decimal_at <- if (FIND_DECIMAL_POINTS) find_decimal_point(crop_raw, line_h) else NA_integer_
    with_border <- function(img) image_border(img, "white", "10x10")
    crop <- with_border(crop_raw)
    
    #---- the re-reads
    read_1x <- read_number_from_crop(crop)
    
    # Second read. For "U/L" values: only the number part (unit cut off), read
    # digits-only, so the unit's letters can't drag the digits into being read
    # as letters. The cut is found from the gaps between characters; if they
    # don't add up, it falls back to an estimate from the character count.
    unit <- str_extract(pairs$Value_Text[i], "[Uu]/?[Ll]$")
    if (!is.na(unit)) {
      cut_x <- find_digit_end(crop_raw, line_h, unit_chars = nchar(unit))
      if (is.na(cut_x)) {
        n_digits    <- max(1, nchar(trimws(pairs$Value_Text[i])) - nchar(unit))
        digit_share <- 0.556 * n_digits / (0.556 * n_digits + 0.52 * nchar(unit))
        cut_x       <- pad_x + pairs$Value_W[i] * digit_share + 0.1 * line_h
      }
      number_crop <- image_crop(crop_raw, geometry_area(max(1, min(w, round(cut_x))), h, 0, 0)) |>
        with_border() |>
        image_resize("200%")
      read_2x <- read_number_from_crop(number_crop, engine = digit_engine)
      second_source <- "digits only"
    } else {
      read_2x <- read_number_from_crop(image_resize(crop, "200%"))
      second_source <- "2x"
    }
    pairs$Reread_1x[i] <- read_1x$number
    pairs$Reread_2x[i] <- read_2x$number
    
    read_dark <- list(number = NA_character_, confidence = 0)
    if (!is.null(dark_img)) {
      read_dark <- read_number_from_crop(with_border(image_crop(dark_img, geometry_area(w, h, left, top))))
      pairs$Reread_dark[i] <- read_dark$number
    }
    
    if (ANNOATE_SAVE_CROPS) {
      crop_dir <- file.path(OCR_Debug_Folder, "crops")
      dir.create(crop_dir, recursive = TRUE, showWarnings = FALSE)
      image_write(crop, file.path(crop_dir, sprintf("%s_y%d_%s.png",
                                                    safe_name(variable), round(pairs$Value_Y[i]), safe_name(coalesce(pairs$Page_Read[i], "NA")))))
    }
    
    #---- the page read, if a letter in it was ambiguous ("ATU/L" = 41 or 47):
    # it counts as whichever possibility a re-read confirms; if none does, it
    # stays "41 or 47", which isn't a number and so can't win on its own.
    page_read  <- pairs$Page_Read[i]
    candidates <- strsplit(coalesce(pairs$Page_Candidates[i], ""), "|", fixed = TRUE)[[1]]
    if (length(candidates) > 1) {
      confirmed <- intersect(candidates, c(read_1x$number, read_2x$number, read_dark$number))
      page_read <- if (length(confirmed) > 0) confirmed[1] else paste(candidates, collapse = " or ")
    }
    
    #---- collect usable reads
    all_reads <- tibble(
      source     = c("page", "1x", second_source, "darkened"),
      number     = c(page_read, read_1x$number, read_2x$number, read_dark$number),
      confidence = c(coalesce(pairs$Page_Confidence[i], 100),   # text-layer words have none
                     read_1x$confidence, read_2x$confidence, read_dark$confidence)
    ) |>
      filter(!is.na(number)) |>
      mutate(number = trim_decimals(variable, add_decimal_point(number, decimal_at)))
    usable <- function(r) r[is_valid_read(variable, r$number), ]
    reads  <- usable(all_reads)
    strict <- variable %in% DISSENT_FLAG_VARIABLES
    result <- vote_on_reads(reads, strict, page_type)
    
    #---- disputed? read a few more times before deciding
    disputed <- is.na(result$value) && nrow(reads) > 0 ||
      variable %in% DISSENT_FLAG_VARIABLES && length(unique(reads$number)) > 1
    if (EXTRA_READS_WHEN_DISPUTED && disputed) {
      wide_left <- max(0, left - pad_x)
      wide_crop <- with_border(image_crop(page_img,
                                          geometry_area(min(info$width - wide_left, w + 2 * pad_x), h, wide_left, top)))
      extra <- list(
        "3x"         = read_number_from_crop(image_resize(crop, "300%")),
        "darkened"   = read_number_from_crop(darken_faint_text(crop, DARKEN_LEVELS[["TEG"]])),
        "wider crop" = read_number_from_crop(wide_crop)
      )
      extra_reads <- tibble(
        source     = names(extra),
        number     = vapply(extra, function(r) r$number, character(1)),
        confidence = vapply(extra, function(r) r$confidence, numeric(1))
      ) |>
        filter(!is.na(number)) |>
        mutate(number = trim_decimals(variable, add_decimal_point(number, decimal_at)))
      pairs$Extra_Reads[i] <- paste(extra_reads$number, collapse = " / ")
      all_reads <- bind_rows(all_reads, extra_reads)
      reads     <- usable(all_reads)
      result    <- vote_on_reads(reads, strict, page_type)
    }
    
    #---- nothing usable: last try, the page read with its decimal point put back
    if (nrow(reads) == 0) {
      restored <- restore_decimal(variable, pairs$Page_Read[i])
      if (!is.na(restored)) {
        result <- list(value = restored,
                       reason = sprintf("decimal point restored (%s -> %s)", pairs$Page_Read[i], restored))
      } else if (nrow(all_reads) > 0) {
        result$reason <- sprintf("no usable read (%s)", paste(unique(all_reads$number), collapse = " / "))
      }
    }
    
    #---- pO2 / LAC: any disagreement is flagged (nothing else can check them)
    if (variable %in% DISSENT_FLAG_VARIABLES && !is.na(result$value) &&
        length(unique(reads$number)) > 1) {
      result$reason <- add_reason(result$reason,
                                  sprintf("reads disagree: %s", paste(unique(reads$number), collapse = " / ")))
    }
    
    #---- note when the decimal point came from the image rather than the OCR text
    if (!is.na(result$value) && !is.na(pairs$Page_Read[i]) &&
        !grepl(".", pairs$Page_Read[i], fixed = TRUE) && grepl(".", result$value, fixed = TRUE) &&
        !is.na(decimal_at)) {
      pairs$Correction[i] <- sprintf("%s -> %s (decimal point seen in image)", pairs$Page_Read[i], result$value)
    }
    
    pairs$Value[i]         <- result$value
    pairs$Review_Reason[i] <- result$reason
  }
  pairs
}


#==============================================================================
# 10a. Blood gas check (ABG pages)
#------------------------------------------------------------------------------
# The ABL90 calculates HCO3 and base excess from what it measures and prints
# them, so pH, pCO2 and HCO3 must satisfy two equations:
#   Henderson-Hasselbalch:  pH = pK + log10(HCO3 / (0.0307 * pCO2))
#   Van Slyke base excess:  ABE = (1 - 0.014*ctHb) *
#                                 (HCO3 - 24.8 + (1.43*ctHb + 7.7) * (pH - 7.4))
# On the 14 correctly read test pages: pK 6.093-6.097, base excess within 0.17.
# A 5<->6 misread in pH (7.632 for 7.532) is ~0.1 off - impossible to miss.
#
# So instead of voting alone, every combination of the reads (plus 5<->6 and
# 1<->4 swaps of them) is tested against both equations, and the combination
# that fits while changing the fewest values is used. This fixes misreads that
# EVERY read got wrong, which no vote can. If no combination fits, or two
# different ones fit equally well, nothing is changed and pH / pCO2 are flagged.
#==============================================================================

# Every value that differs from `value` by one confusable digit (DIGIT_CONFUSIONS)
digit_variants <- function(value) {
  chars <- strsplit(value, "")[[1]]
  out   <- character(0)
  for (k in seq_along(chars)) for (pair in DIGIT_CONFUSIONS) {
    if (chars[k] %in% pair) {
      swapped    <- chars
      swapped[k] <- setdiff(pair, chars[k])
      out        <- c(out, paste(swapped, collapse = ""))
    }
  }
  unique(out)
}

resolve_blood_gas <- function(pairs) {
  core <- c("pH", "pCO2", "HCO3")
  if (!all(core %in% pairs$Standardized_Variable)) return(pairs)   # HCO3 not read: can't check
  if (!"Value" %in% names(pairs)) pairs$Value <- pairs$Page_Read
  if (!"Review_Reason" %in% names(pairs)) pairs$Review_Reason <- ""
  if (!"Correction" %in% names(pairs)) pairs$Correction <- ""
  
  row_of   <- function(v) which(pairs$Standardized_Variable == v)[1]
  value_of <- function(v) if (v %in% pairs$Standardized_Variable)
    suppressWarnings(as.numeric(pairs$Value[row_of(v)])) else NA_real_
  ctHb <- value_of("ctHb")
  ABE  <- value_of("ABE")
  use_base_excess <- !is.na(ctHb) && !is.na(ABE)
  
  # The values each of pH / pCO2 / HCO3 could be, with a cost for how far each
  # is from what the vote chose: 0 = the voted value, 1 = another read,
  # +2 for a confusable-digit swap
  read_columns <- intersect(c("Page_Read", "Reread_1x", "Reread_2x", "Reread_dark"), names(pairs))
  options_for <- function(v) {
    i     <- row_of(v)
    voted <- pairs$Value[i]
    reads <- unlist(pairs[i, read_columns], use.names = FALSE)
    if ("Extra_Reads" %in% names(pairs) && !is.na(pairs$Extra_Reads[i])) {
      reads <- c(reads, strsplit(pairs$Extra_Reads[i], " / ", fixed = TRUE)[[1]])
    }
    reads <- setdiff(unique(reads[!is.na(reads) & reads != ""]), voted)
    base  <- tibble(value = c(voted, reads), cost = c(0, rep(1, length(reads)))) |>
      filter(!is.na(value))
    swaps <- bind_rows(lapply(seq_len(nrow(base)), function(k)
      tibble(value = digit_variants(base$value[k]), cost = base$cost[k] + 2)))
    bind_rows(base, swaps) |>
      filter(is_valid_read(v, value)) |>
      group_by(value) |>
      summarise(cost = min(cost), .groups = "drop")
  }
  options <- lapply(setNames(core, core), options_for)
  if (any(vapply(options, nrow, integer(1)) == 0)) return(pairs)
  
  combos <- expand.grid(pH = seq_len(nrow(options$pH)), pCO2 = seq_len(nrow(options$pCO2)),
                        HCO3 = seq_len(nrow(options$HCO3)))
  pH   <- as.numeric(options$pH$value[combos$pH])
  pCO2 <- as.numeric(options$pCO2$value[combos$pCO2])
  HCO3 <- as.numeric(options$HCO3$value[combos$HCO3])
  cost <- options$pH$cost[combos$pH] + options$pCO2$cost[combos$pCO2] + options$HCO3$cost[combos$HCO3]
  
  fits_hh <- abs(pH - (BLOOD_GAS_PK + log10(HCO3 / (0.0307 * pCO2)))) <= PH_TOLERANCE
  fits_be <- if (use_base_excess) {
    abs((1 - 0.014 * ctHb) * (HCO3 - 24.8 + (1.43 * ctHb + 7.7) * (pH - 7.4)) - ABE) <= BE_TOLERANCE
  } else TRUE
  # When base excess is available BOTH equations must fit. (Falling back to
  # one equation let a misread pCO2 "correct" a right pH: B-EPS 09 p20.)
  fits <- fits_hh & fits_be
  
  flag_core <- function(reason) {
    for (v in c("pH", "pCO2")) {
      pairs$Review_Reason[row_of(v)] <<- add_reason(pairs$Review_Reason[row_of(v)], reason)
    }
  }
  
  if (!any(fits)) {
    flag_core("pH, pCO2 and HCO3 don't fit together - one was misread")
    return(pairs)
  }
  
  best   <- which(fits & cost == min(cost[fits]))
  chosen <- unique(paste(pH[best], pCO2[best], HCO3[best]))
  if (length(chosen) > 1) {
    flag_core("pH, pCO2 and HCO3 could be corrected more than one way")
    return(pairs)
  }
  if (!FIX_BLOOD_GAS) {
    if (cost[best[1]] > 0) flag_core("pH, pCO2 and HCO3 don't fit together - one was misread")
    return(pairs)
  }
  
  # Apply. Values left as they were keep their own flags: the equations only
  # check pH to ~0.005 and pCO2 to ~0.3, so a low-confidence last digit is
  # still worth a look. Values that were changed or filled in get a note:
  #   both equations agree -> listed in Correction (flagged only if FLAG_BLOOD_GAS_FIXES)
  #   only one available   -> always flagged
  checks <- if (use_base_excess) "pCO2, HCO3 and base excess" else "pCO2 and HCO3 only"
  for (v in core) {
    i   <- row_of(v)
    new <- options[[v]]$value[combos[[v]][best[1]]]
    old <- pairs$Value[i]
    if (is.na(old) || old != new) {
      pairs$Value[i]      <- new
      pairs$Correction[i] <- sprintf("%s -> %s (fits %s)", coalesce(old, "blank"), new, checks)
      pairs$Review_Reason[i] <- if (!use_base_excess) {
        paste("corrected using one equation only:", pairs$Correction[i])
      } else if (FLAG_BLOOD_GAS_FIXES) {
        paste("corrected by blood-gas check:", pairs$Correction[i])
      } else ""
    }
  }
  pairs
}

flag_problems <- function(pairs, page_type) {
  if (!"Review_Reason" %in% names(pairs)) {
    pairs$Value <- pairs$Page_Read
    pairs$Review_Reason <- ""
  }
  numeric_value <- suppressWarnings(as.numeric(pairs$Value))
  
  
  # Plausible range
  range_row <- match(pairs$Standardized_Variable, PLAUSIBLE_RANGE$variable)
  low  <- PLAUSIBLE_RANGE$low[range_row]
  high <- PLAUSIBLE_RANGE$high[range_row]
  out_of_range <- !is.na(low) & !is.na(numeric_value) & (numeric_value < low | numeric_value > high)
  pairs$Review_Reason[out_of_range] <- add_reason(pairs$Review_Reason[out_of_range],
                                                  sprintf("outside plausible range %s-%s", low[out_of_range], high[out_of_range]))
  
  # Report arithmetic
  v <- setNames(numeric_value, pairs$Standardized_Variable)
  for (check in CONSISTENCY_CHECKS) {
    if (!is.null(check$setting) && !isTRUE(get(check$setting))) next
    if (check$page_type != page_type) next
    if (!all(check$needs %in% names(v)) || anyNA(v[check$needs])) next
    if (!isTRUE(check$passes(v))) {
      rows <- pairs$Standardized_Variable %in% check$flag
      pairs$Review_Reason[rows] <- add_reason(pairs$Review_Reason[rows], check$message)
    }
  }
  pairs
}


# Every grey at or darker than `level` % becomes black; white stays white
darken_faint_text <- function(img, level) {
  image_level(img, black_point = level, white_point = 100)
}

# Combines two OCR passes of the same page. Where both passes found a word in
# the same place, the more confident one is kept; words only one pass found
# are kept too.
merge_ocr_passes <- function(normal, dark) {
  if (nrow(dark) == 0)   return(normal)
  if (nrow(normal) == 0) return(dark)
  
  drop_normal <- rep(FALSE, nrow(normal))
  keep_dark   <- rep(FALSE, nrow(dark))
  
  for (j in seq_len(nrow(dark))) {
    overlap_w <- pmax(0, pmin(normal$x + normal$w, dark$x[j] + dark$w[j]) - pmax(normal$x, dark$x[j]))
    overlap_h <- pmax(0, pmin(normal$y + normal$h, dark$y[j] + dark$h[j]) - pmax(normal$y, dark$y[j]))
    smaller   <- pmin(normal$w * normal$h, dark$w[j] * dark$h[j])
    same_spot <- which(overlap_w * overlap_h > 0.5 * smaller & !drop_normal)
    
    if (length(same_spot) == 0 || all(dark$confidence[j] > normal$confidence[same_spot])) {
      keep_dark[j] <- TRUE
      drop_normal[same_spot] <- TRUE
    }
  }
  
  bind_rows(normal[!drop_normal, ],
            dark[keep_dark, ] |> mutate(extraction_method = "OCR (darkened)"))
}

# The "R" label is the faintest text on the TEG strip and is sometimes not read
# at all. Its column can still be found: the strip's unit row reads
# "min  min  deg  mm" under R, K, Angle, MA. If K was read but R wasn't, a
# stand-in "R" label is placed above the "min" to the left of K's "min", and
# the normal pairing then finds the R value below it.
add_missing_teg_r_label <- function(tokens) {
  labels <- standardize_label(clean_token(tokens$text))
  if ("R.Time" %in% labels || !"K.Time" %in% labels) return(tokens)
  
  k      <- tokens[which(labels == "K.Time")[1], ]
  is_min <- tolower(clean_token(tokens$text)) == "min"
  
  k_unit <- which(is_min & tokens$y > k$y & tokens$y - (k$y + k$h) <= 2 * k$h &
                    abs((tokens$x + tokens$w / 2) - (k$x + k$w / 2)) <= 3 * k$h)
  if (length(k_unit) == 0) return(tokens)
  k_unit <- tokens[k_unit[1], ]
  
  r_unit <- which(is_min & abs(tokens$y - k_unit$y) <= ROW_TOLERANCE * k_unit$h &
                    tokens$x < k_unit$x - 2 * k_unit$h)
  if (length(r_unit) == 0) return(tokens)
  r_unit <- tokens[r_unit[which.max(tokens$x[r_unit])], ]   # nearest "min" left of K's
  
  bind_rows(tokens, tibble(
    x = r_unit$x,
    y = r_unit$y - (k_unit$y - k$y),       # same spacing as K label -> K unit
    w = r_unit$w,
    h = k$h,
    text = "R",
    confidence = 0,
    extraction_method = "inferred (TEG column)"
  ))
}


#==============================================================================
# 11. Processing one page
#==============================================================================
process_page <- function(file_path, page_number, text_layer_words) {
  
  page_img    <- NULL
  orientation <- ""
  ocr_used    <- FALSE   # TRUE once the words come from OCR of page_img
  use_text_layer <- nrow(text_layer_words) > 0 && !text_layer_is_sideways(text_layer_words)
  
  if (use_text_layer) {
    # Cheap path: the PDF already has (upright) text. Classify from it first.
    tokens    <- tokens_from_text_layer(text_layer_words)
    page_type <- detect_page_type(tokens$text)
    
    if (page_type %in% ALWAYS_OCR_TYPES) {
      upright     <- ocr_upright_page(render_page(file_path, page_number))
      page_img    <- upright$img
      tokens      <- upright$tokens
      orientation <- upright$orientation
      ocr_used    <- TRUE
    } else if (page_type != "UNKNOWN" && REREAD_VALUES) {
      # Not straightened: crops must line up with the text layer's coordinates
      page_img <- render_page(file_path, page_number)
    }
  } else {
    # Image-only page (or a sideways text layer): one OCR pass of the upright
    # page serves classification AND extraction
    upright     <- ocr_upright_page(render_page(file_path, page_number))
    page_img    <- upright$img
    tokens      <- upright$tokens
    orientation <- upright$orientation
    ocr_used    <- TRUE
    page_type   <- detect_page_type(tokens$text)
  }
  
  # A TEG printout whose faint labels plain OCR missed entirely (TA-EM page 25:
  # no labels found at all) still says "TEG" in its header. Give it the
  # darkened pass before deciding it's UNKNOWN.
  looks_like_teg <- page_type == "UNKNOWN" && ocr_used && any(grepl("^TEG", tokens$text))
  
  # TEG: read a darkened copy as well and keep the better reading of each word
  dark_img <- NULL
  if ((page_type %in% DARKEN_TYPES || looks_like_teg) && ocr_used) {
    level    <- if (page_type %in% names(DARKEN_LEVELS)) DARKEN_LEVELS[[page_type]] else DARKEN_LEVELS[["TEG"]]
    dark_img <- darken_faint_text(page_img, level)
    tokens   <- merge_ocr_passes(tokens, tokens_from_ocr(dark_img))
    if (page_type == "TEG" || looks_like_teg) tokens <- add_missing_teg_r_label(tokens)
    if (looks_like_teg) page_type <- detect_page_type(tokens$text)
    if (!page_type %in% DARKEN_TYPES) dark_img <- NULL
  }
  
  
  result <- list(page_type = page_type, tokens = tokens, pairs = tibble(),
                 orientation = orientation,
                 img = page_img)   # the exact image the words came from (for debug pictures)
  if (page_type == "UNKNOWN" || nrow(tokens) == 0) return(result)
  
  pairs <- pair_labels_to_values(tokens, page_type)
  if (nrow(pairs) == 0) return(result)
  
  # Keep this page's targets plus the check-only helpers
  pairs <- pairs |>
    filter(Standardized_Variable %in% c(VALID_TARGETS[[page_type]], CHECK_ONLY_VARIABLES))
  if (nrow(pairs) == 0) return(result)
  
  if (REREAD_VALUES && !is.null(page_img)) pairs <- reread_values(pairs, page_img, dark_img, page_type)
  if (page_type == "ABG") pairs <- resolve_blood_gas(pairs)
  result$pairs <- flag_problems(pairs, page_type)
  result
}


#==============================================================================
# 11b. OCR debug pictures
#------------------------------------------------------------------------------
# Every lab page (any page type) and page 1 of each PDF is saved with
# everything OCR found drawn on it, while the page is processed anyway - so
# this costs no extra OCR. Page 1 is never OCR'd, so its picture is the plain
# scan with the header strip.
#
#   OCR_Debug/
#     B LR 12/
#       B-LR_12_page011.png
#       B-LR_12_page014.png
#       ...
#       pages.csv          <- one line per picture: type, rotation, values read
#
# Colours: green box = recognised label   blue box = number   grey = other text
#          red line = label -> value it was paired with
#          orange = value flagged for review (reason written next to it)
#==============================================================================

safe_name <- function(x) gsub("[^A-Za-z0-9 _.-]", "_", x)

# Creates (or empties) one OCR_Debug folder per model and returns the folder
# for each PDF. Every lab page (any page type) and page 1 get a picture.
prepare_debug_folders <- function(file_paths) {
  models  <- coalesce(make_subject_id(basename(file_paths)), "Unknown model")
  folders <- file.path(OCR_Debug_Folder, safe_name(models))
  # Start each model folder fresh so old pictures from earlier runs don't mix in
  for (folder in unique(folders)) {
    unlink(folder, recursive = TRUE)
    dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  }
  setNames(folders, file_paths)
}

# Draws what OCR found on one page and saves it as a PNG.
# Returns a one-line summary for that model's pages.csv.
save_debug_page <- function(page_result, file_path, page_number, out_dir) {
  tokens <- page_result$tokens
  pairs  <- page_result$pairs
  
  # Text-layer pages that were never rendered: render now (same coordinates)
  img <- page_result$img
  if (is.null(img)) img <- render_page(file_path, page_number)
  img <- image_convert(img, colorspace = "sRGB")
  
  #---- what kind of thing each word is
  role <- rep("text", nrow(tokens))
  if (nrow(tokens) > 0) {
    clean <- clean_token(tokens$text)
    role[!is.na(parse_number_text(clean))] <- "number"
    role[!is.na(standardize_label(clean, page_result$page_type))] <- "label"
  }
  box_colour <- c(label = "#1a9850", number = "#2c7fb8", text = "#9e9e9e")[role]
  box_width  <- c(label = 4, number = 3, text = 1)[role]
  
  has_pairs <- nrow(pairs) > 0 && "Value_X" %in% names(pairs)
  flagged   <- if (has_pairs) coalesce(pairs$Review_Reason, "") != "" else logical(0)
  
  #---- draw (image_draw uses pixel coordinates, origin top-left)
  # Boxes sit DEBUG_BOX_PADDING x text height outside each word, so the
  # lines don't run through the digits
  # ANNOATE_FLAGGED_ONLY: skip the word boxes and the accepted values, and draw
  # only the flagged ones, so the pictures show just what needs checking
  summary_text    <- if (has_pairs) paste(pairs$Standardized_Variable, "=", pairs$Value, collapse = "; ") else ""
  summary_flagged <- sum(flagged)   # pages.csv still lists every value
  if (ANNOATE_FLAGGED_ONLY) {
    tokens <- tokens[0, ]
    if (has_pairs) {
      pairs     <- pairs[flagged, ]
      flagged   <- flagged[flagged]
      has_pairs <- nrow(pairs) > 0
    }
  }
  img <- image_draw(img)
  if (nrow(tokens) > 0) {
    pad <- DEBUG_BOX_PADDING * tokens$h
    rect(tokens$x - pad, tokens$y - pad, tokens$x + tokens$w + pad, tokens$y + tokens$h + pad,
         border = box_colour, lwd = box_width)
    # What OCR actually read - a grey box under a label means it was misread
    if (ANNOATE_SHOW_OCR_TEXT) {
      text(tokens$x - pad, tokens$y - pad, labels = tokens$text, adj = c(0, -0.3),
           col = "#7f7f7f", cex = 1.1)
    }
  }
  if (has_pairs) {
    pair_colour <- ifelse(flagged, "#f28e2b", "#d7301f")
    mid_y       <- pairs$Value_Y + pairs$Value_H / 2
    
    value_pad   <- DEBUG_BOX_PADDING * pairs$Value_H
    segments(pairs$Variable_X, mid_y, pairs$Value_X - value_pad, mid_y, col = pair_colour, lwd = 3)
    rect(pairs$Value_X - value_pad, pairs$Value_Y - value_pad,
         pairs$Value_X + pairs$Value_W + value_pad, pairs$Value_Y + pairs$Value_H + value_pad,
         border = pair_colour, lwd = ifelse(flagged, 6, 3))
    text(pairs$Variable_X, pairs$Value_Y,
         labels = paste0(pairs$Standardized_Variable, " = ", pairs$Value, ifelse(flagged, "  ?", "")),
         pos = 3, offset = 0.6, col = pair_colour, font = 2, cex = 2.2)
    if (any(flagged)) {
      text(pairs$Value_X[flagged] + pairs$Value_W[flagged] + value_pad[flagged], mid_y[flagged],
           labels = pairs$Review_Reason[flagged],
           pos = 4, offset = 1, col = "#f28e2b", font = 2, cex = 1.6)
    }
  }
  dev.off()
  
  #---- header strip with the page facts
  header <- sprintf("%s | page %d | type: %s | %s",
                    basename(file_path), page_number, page_result$page_type,
                    if (nzchar(page_result$orientation)) page_result$orientation else "no rotation")
  img <- image_annotate(img, header, size = 40, color = "black", boxcolor = "#FFFFCC",
                        gravity = "northwest", location = "+20+20", weight = 700)
  
  file_stem <- safe_name(tools::file_path_sans_ext(basename(file_path)))
  out_file  <- file.path(out_dir, sprintf("%s_page%03d.png", file_stem, page_number))
  image_write(img, out_file, format = "png")
  
  tibble(
    picture         = basename(out_file),
    source_file     = basename(file_path),
    page            = page_number,
    page_type       = page_result$page_type,
    orientation_fix = page_result$orientation,
    values_read     = summary_text,
    values_flagged  = summary_flagged
  )
}

# For checking a single page by hand after a run, e.g.
#   debug_page(pdf_files[1], 36)
# Saves the picture to OCR_Debug/single pages/ and prints what was read.
debug_page <- function(file_path, page_number,
                       out_dir = file.path(OCR_Debug_Folder, "single pages")) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  text_layer <- pdf_data(file_path)[[page_number]]
  result     <- process_page(file_path, page_number, text_layer)
  summary    <- save_debug_page(result, file_path, page_number, out_dir)
  
  cat(sprintf("Page type: %s   Orientation: %s\n", result$page_type,
              if (nzchar(result$orientation)) result$orientation else "no rotation"))
  if (nrow(result$pairs) > 0) {
    columns <- intersect(c("Standardized_Variable", "Value", "Page_Read", "Review_Reason"),
                         names(result$pairs))
    print(result$pairs[, columns])
  } else {
    cat("No label/value pairs found on this page.\n")
  }
  cat("Saved:", file.path(out_dir, summary$picture), "\n")
  invisible(result)
}


#==============================================================================
# 12. Processing all PDFs (with progress bar / ETA)
#==============================================================================
show_progress <- function(pdf_i, n_pdfs, page_i, n_pages, pages_done, pages_total, start_time) {
  elapsed   <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  per_page  <- if (pages_done > 0) elapsed / pages_done else NA
  remaining <- if (is.na(per_page)) NA else per_page * (pages_total - pages_done)
  eta <- if (is.na(remaining)) "--:--" else
    format(as.POSIXct(remaining, origin = "1970-01-01", tz = "UTC"),
           if (remaining >= 3600) "%H:%M:%S" else "%M:%S")
  bar <- function(fraction) sprintf("[%-20s]", strrep("=", round(20 * fraction)))
  
  cat(sprintf("\r PDF %d/%d %s | page %d/%d %s | %.1f s/page | ETA %s   ",
              pdf_i, n_pdfs, bar(pdf_i / n_pdfs),
              page_i, n_pages, bar(page_i / n_pages),
              ifelse(is.na(per_page), 0, per_page), eta))
  flush.console()
}

extract_all_pdfs <- function(file_paths) {
  page_counts <- vapply(file_paths, function(f) pdf_info(f)$pages, numeric(1))
  pages_total <- sum(page_counts)
  cat(sprintf("\nFound %d PDF(s), %d pages\n\n", length(file_paths), pages_total))
  
  all_tokens  <- list()
  all_pairs   <- list()
  page_timing <- tibble(Source_File = character(), page = integer(),
                        page_type = character(), orientation_fix = character(),
                        seconds = numeric())
  start_time  <- Sys.time()
  pages_done  <- 0
  
  debug_folders <- if (SAVE_OCR_DEBUG) prepare_debug_folders(file_paths) else NULL
  debug_summary <- list()
  
  for (p in seq_along(file_paths)) {
    file_path <- file_paths[[p]]
    file_name <- basename(file_path)
    text_layer <- pdf_data(file_path)
    
    for (i in seq_along(text_layer)) {
      show_progress(p, length(file_paths), i, length(text_layer),
                    pages_done, pages_total, start_time)
      page_start <- Sys.time()
      
      page_result <- if (i %in% SKIP_PAGES) {
        skipped <- list(page_type = "SKIPPED", tokens = tibble(), pairs = tibble(), orientation = "")
        # Page 1 is still drawn for OCR_Debug, so turn and straighten it like
        # any other page first. Its words are only used to find the right way
        # up - nothing on it is extracted.
        if (SAVE_OCR_DEBUG && i == 1) {
          upright <- tryCatch(ocr_upright_page(render_page(file_path, i)), error = function(e) NULL)
          if (!is.null(upright)) {
            skipped$img         <- upright$img
            skipped$orientation <- upright$orientation
          }
        }
        skipped
      } else tryCatch(
        process_page(file_path, i, text_layer[[i]]),
        error = function(e) {
          message(sprintf("\n  ! %s page %d failed: %s", file_name, i, conditionMessage(e)))
          list(page_type = "ERROR", tokens = tibble(), pairs = tibble(), orientation = "")
        }
      )
      
      key <- paste(file_name, i)
      this_page_type <- page_result$page_type   # pulled out so mutate() can't confuse it with the "page" column
      if (nrow(page_result$tokens) > 0) {
        all_tokens[[key]] <- page_result$tokens |>
          mutate(Source_File = file_name, page = i, page_type = this_page_type)
      }
      if (nrow(page_result$pairs) > 0) {
        all_pairs[[key]] <- page_result$pairs |>
          mutate(Source_File = file_name, page = i, page_type = this_page_type)
      }
      
      # Annotated picture for OCR_Debug: every lab page, plus page 1 (never
      # OCR'd, so its picture is the plain scan with the header strip)
      is_lab_page <- !this_page_type %in% c("UNKNOWN", "SKIPPED", "ERROR")
      if (SAVE_OCR_DEBUG && (is_lab_page || i == 1)) {
        folder <- debug_folders[[file_path]]
        debug_summary[[key]] <- tryCatch(
          save_debug_page(page_result, file_path, i, folder) |> mutate(folder = folder),
          error = function(e) {
            message(sprintf("\n  ! debug picture for %s page %d failed: %s",
                            file_name, i, conditionMessage(e)))
            NULL
          }
        )
      }
      
      pages_done  <- pages_done + 1
      page_timing <- add_row(page_timing, Source_File = file_name, page = i,
                             page_type = this_page_type,
                             orientation_fix = page_result$orientation,
                             seconds = as.numeric(difftime(Sys.time(), page_start, units = "secs")))
    }
  }
  
  tokens <- bind_rows(all_tokens)
  pairs  <- bind_rows(all_pairs)
  
  # One pages.csv per model folder, listing its debug pictures
  debug_summary <- bind_rows(debug_summary)
  if (nrow(debug_summary) > 0) {
    for (model_folder in unique(debug_summary$folder)) {
      debug_summary |>
        filter(folder == model_folder) |>
        select(-folder) |>
        arrange(source_file, page) |>
        write.csv(file.path(model_folder, "pages.csv"), row.names = FALSE)
    }
  }
  
  cat("\n\n============================================\n")
  cat("EXTRACTION SUMMARY\n")
  cat("============================================\n")
  for (k in seq_along(file_paths)) cat(sprintf("- %s: %d pages\n", basename(file_paths[k]), page_counts[k]))
  cat(sprintf("\nPages processed:        %d\n", pages_done))
  cat(sprintf("Lab pages found:        %d\n", sum(!page_timing$page_type %in% c("UNKNOWN", "ERROR", "SKIPPED"))))
  exported <- if (nrow(pairs) > 0) !pairs$Standardized_Variable %in% CHECK_ONLY_VARIABLES else logical(0)
  cat(sprintf("Values extracted:       %d\n", sum(exported)))
  cat(sprintf("Values flagged:         %d\n", sum(exported & pairs$Review_Reason != "")))
  cat(sprintf("Pages turned upright:   %d\n", sum(grepl("turned", page_timing$orientation_fix))))
  cat(sprintf("Pages straightened:     %d\n", sum(grepl("straightened", page_timing$orientation_fix))))
  cat(sprintf("Average time per page:  %.2f s\n", mean(page_timing$seconds)))
  if (nrow(debug_summary) > 0) {
    cat(sprintf("Debug pictures saved:   %d (in %s)\n", nrow(debug_summary), OCR_Debug_Folder))
  }
  cat("============================================\n")
  
  list(tokens = tokens, pairs = pairs, timing = page_timing)
}


#==============================================================================
# 13. Run
#==============================================================================
if (file.exists(Folder_Path) && !dir.exists(Folder_Path)) {
  pdf_files <- Folder_Path
} else if (dir.exists(Folder_Path)) {
  pdf_files <- list.files(Folder_Path, pattern = "\\.pdf$", full.names = TRUE,
                          recursive = TRUE, ignore.case = TRUE)
} else {
  pdf_files <- character(0)
}
if (length(pdf_files) == 0) stop("No PDFs found at: ", Folder_Path)

extraction <- extract_all_pdfs(pdf_files)

if (nrow(extraction$pairs) == 0) {
  stop("\nPIPELINE HALTED: no label/value pairs were found. ",
       "Every page may have been classified UNKNOWN, or OCR found no numbers.")
}

raw_master_dataset <- extraction$tokens |>
  group_by(page_type) |>
  mutate(
    clean_value = clean_token(text),
    Standardized_Variable = standardize_label(clean_value, page_type[1]),
    clean_number = parse_number_text(clean_value),
    read_as=case_when(
      !is.na(Standardized_Variable) ~ "label",
      !is.na(clean_number) ~ "number",
      TRUE ~ "text"
    )
  ) |> 
  select(Source_File, page, page_type, x, y, w, h, raw_value = text, clean_value, Standardized_Variable,
         clean_number,read_as,confidence, extraction_method)


#==============================================================================
# 14. Add Subject ID, clock time and date
#==============================================================================
cat("Extracting dates and times...\n")

# First clock time on each lab page
time_rows <- raw_master_dataset |>
  filter(page_type != "UNKNOWN") |>
  group_by(Source_File, page, page_type) |>
  summarize(Value = na.omit(str_extract(raw_value,
                                        "\\b\\d{1,2}:\\d{2}(:\\d{2})?\\s*([AaPp][Mm])?\\b"))[1],
            .groups = "drop") |>
  filter(!is.na(Value)) |>
  mutate(Standardized_Variable = "Time", Variable = "Time",
         Match_Method = "Regex", Review_Reason = "")

# Date from the first ABG page of each document
date_rows <- raw_master_dataset |>
  filter(page_type == "ABG") |>
  group_by(Source_File) |>
  filter(page == min(page)) |>
  summarize(Value = na.omit(str_extract(raw_value, "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b"))[1],
            page = first(page), page_type = "ABG", .groups = "drop") |>
  filter(!is.na(Value)) |>
  mutate(Standardized_Variable = "Date", Variable = "Date",
         Match_Method = "Regex", Review_Reason = "")

possible_pairs_master <- bind_rows(extraction$pairs, time_rows, date_rows) |>
  mutate(Subject_ID = make_subject_id(Source_File)) |>
  relocate(Subject_ID, Source_File, page, page_type, Standardized_Variable, Value, Review_Reason) |>
  arrange(Source_File, page, desc(Standardized_Variable == "Date"),
          desc(Standardized_Variable == "Time"), Variable_Y)


#==============================================================================
# 15. Wide format (one row per subject per event)
#==============================================================================
cat("Building wide table...\n")

target_vars <- c('MAP', 'bpm', 'temp', 'RBC', 'HGB', 'HCT', 'PLT', 'WBC', 'Free Hb', '% Free Hb',
                 'LAC', 'pH', 'pCO2', 'pO2', 'AST', 'ALT', 'LDH', 'CREA', 'BUN', 'AMY', 'TG',
                 'GLU', 'GGT', 'CKHR time', 'CKH K', 'CKH angle', 'CKH MA', 'APTT', 'PT', 'TT', 'Fib')

assay_groups <- c('MAP', 'Heart rate', 'Body temp', 'CBC', 'CBC', 'CBC', 'CBC', 'CBC',
                  "Drabkin's", '% Free Hb', 'ABG', 'ABG', 'ABG', 'ABG',
                  'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP', 'CMP',
                  'TEG 5000', 'TEG 5000', 'TEG 5000', 'TEG 5000',
                  'Coag Panel', 'Coag Panel', 'Coag Panel', 'Coag Panel')

units_row <- c('mmHg', 'bpm', '°C',
               'M/mL', 'mg/dL ', 'mmHg', '10^3/uL', '10^3/uL',
               'uM', '%', 'mmol/L', 'value', 'mmHg', 'mmHg',
               'U/L', 'U/L', 'U/L', 'mg/dL', 'mg/dL', 'U/L', 'mg/dL', 'mg/dL', 'U/L',
               'min', 'min', 'degree', 'mm',
               'sec', 'sec', 'sec', 'g/L')

# Each ABG page starts a new event (timepoint)
event_mapping <- possible_pairs_master |>
  distinct(Source_File, page, page_type) |>
  arrange(Source_File, page) |>
  group_by(Source_File) |>
  # Line 1 starts at the first lab page, whatever its type; every ABG after
  # that starts a new line (an ABG on the first lab page starts line 1 itself)
  mutate(Event_ID = 1 + cumsum(page_type == "ABG" & row_number() > 1)) |>
  ungroup()

pairs_with_events <- possible_pairs_master |>
  filter(!Standardized_Variable %in% c("Date", CHECK_ONLY_VARIABLES)) |>
  left_join(event_mapping, by = c("Source_File", "page", "page_type")) |>
  mutate(Column = display_name(Standardized_Variable))

subject_dates <- possible_pairs_master |>
  filter(Standardized_Variable == "Date") |>
  group_by(Subject_ID) |>
  summarize(Transfusion_date = first(Value), .groups = "drop")

page_dictionary <- possible_pairs_master |>
  distinct(Subject_ID, page, page_type) |>
  arrange(Subject_ID, page)

# Cells needing a human look, in the same keys as the wide table
review_queue <- pairs_with_events |>
  filter(Review_Reason != "") |>
  group_by(Subject_ID, Event_ID, Column) |>
  slice(1) |>
  ungroup() |>
  select(Subject_ID, Event_ID, Column, Value, Review_Reason,
         any_of(c("Page_Read", "Reread_1x", "Reread_2x", "Reread_dark", "Extra_Reads", "Correction")), Source_File, page, page_type)

wide_master <- pairs_with_events |>
  group_by(Subject_ID, Event_ID, Column) |>
  summarise(Value = first(Value[!is.na(Value)]), .groups = "drop") |>
  pivot_wider(names_from = Column, values_from = Value)

if (!"Clock Time" %in% names(wide_master)) wide_master$`Clock Time` <- NA_character_
wide_master$Timepoint       <- ""
wide_master$`Measurement >` <- "R1"
for (var in target_vars) if (!var %in% names(wide_master)) wide_master[[var]] <- NA_character_

wide_master <- wide_master |>
  select(Subject_ID, Event_ID, Timepoint, `Clock Time`, `Measurement >`, all_of(target_vars)) |>
  arrange(Subject_ID, Event_ID) |>
  mutate(across(-Event_ID, ~ ifelse(is.na(.), "", as.character(.))))

# Timepoints are filled in row order from TIMEPOINTS (Baseline, EOS, EOR, ...).
# A subject with exactly that many rows gets them as-is. Any other count means
# a row is missing or extra somewhere, so the guess is flagged for that subject.
wide_master <- wide_master |>
  group_by(Subject_ID) |>
  mutate(
    Timepoint = ifelse(row_number() <= length(TIMEPOINTS),
                       TIMEPOINTS[pmin(row_number(), length(TIMEPOINTS))],
                       paste("Extra", row_number() - length(TIMEPOINTS))),
    timepoints_guessed = n() != length(TIMEPOINTS),
    rows_found = n()
  ) |>
  ungroup()

timepoint_flags <- wide_master |>
  filter(timepoints_guessed) |>
  transmute(Subject_ID, Event_ID, Column = "Timepoint",
            Review_Reason = sprintf("timepoint guessed: %d rows found, %d expected - check the order",
                                    rows_found, length(TIMEPOINTS)))
wide_master <- wide_master |> select(-timepoints_guessed, -rows_found)


#==============================================================================
# 16. Excel export
#==============================================================================
cat("Writing workbook...\n")

wb <- createWorkbook()

addWorksheet(wb, "Review Queue")
writeData(wb, "Review Queue", bind_rows(review_queue, timepoint_flags))   # guessed timepoints listed too
addWorksheet(wb, "Raw Extraction");          writeData(wb, "Raw Extraction", raw_master_dataset)
addWorksheet(wb, "Pairwise Master");         writeData(wb, "Pairwise Master", possible_pairs_master)
addWorksheet(wb, "Page Dictionary")
addWorksheet(wb, "Average Processing Time"); writeData(wb, "Average Processing Time", extraction$timing)

# Styles
Main_Head_Style <- createStyle(textDecoration = "bold", halign = "center", valign = "bottom", fontSize = 20,
                               fontName = "Calibri", border = "TopBottomLeftRight", borderStyle = "medium")
Meta_Labels     <- createStyle(textDecoration = "bold", halign = "left", valign = "center", fontSize = 12)
meta_fill       <- createStyle(halign = "center", valign = "bottom", fgFill = "#e2efd9", border = "TopBottomLeftRight",
                               fontSize = 12, fontName = "Calibri", borderStyle = "medium")
style_meta      <- createStyle(fontName = "Aptos Narrow", textDecoration = "bold", halign = "center", numFmt = "TEXT")
bold_center     <- createStyle(textDecoration = "bold", halign = "center", valign = "center", fontSize = 11,
                               fontName = "Aptos Narrow")
header_fill     <- createStyle(textDecoration = "bold", halign = "center", valign = "center", fgFill = "#c0e4f5",
                               border = "bottom", fontSize = 11, fontName = "Calibri", borderStyle = "medium")
style_num       <- createStyle(fontName = "Aptos Narrow", numFmt = "general", halign = "center")
outlier_style   <- createStyle(fgFill = "#FFC7CE")   # pink:   OUTLIER_FACTOR x away from the median
sandwich_style  <- createStyle(fgFill = "#FFF6B3")   # yellow: missing while neighbours are filled
review_style    <- createStyle(fgFill = "#F8CBAD")   # orange: flagged by the checks above

list_of_models   <- split(wide_master, wide_master$Subject_ID)
list_of_models_p <- split(page_dictionary, page_dictionary$Subject_ID)
runs             <- rle(assay_groups)
first_data_row   <- 15        # row 14 holds the column headers
start_col_pg     <- 2
start_row        <- 3

for (subj in names(list_of_models)) {
  
  #---- Page dictionary block for this subject ----
  df_subj_pg <- list_of_models_p[[subj]] |>
    select(page, page_type) |>
    filter(!is.na(page), !is.na(page_type)) |>
    distinct()
  if (nrow(df_subj_pg) == 0) next
  
  n_cols <- ncol(df_subj_pg)
  writeData(wb, "Page Dictionary", paste("Subject", subj), startCol = start_col_pg, startRow = start_row - 1)
  addStyle(wb, "Page Dictionary", bold_center, rows = start_row - 1,
           cols = start_col_pg:(start_col_pg + n_cols - 1), gridExpand = TRUE)
  writeData(wb, "Page Dictionary", df_subj_pg, startCol = start_col_pg, startRow = start_row)
  addStyle(wb, "Page Dictionary", header_fill, rows = start_row,
           cols = start_col_pg:(start_col_pg + n_cols - 1), gridExpand = TRUE)
  addStyle(wb, "Page Dictionary", style_num, rows = (start_row + 1):(start_row + nrow(df_subj_pg)),
           cols = start_col_pg:(start_col_pg + n_cols - 1), gridExpand = TRUE)
  start_col_pg <- start_col_pg + 4
  
  #---- Subject sheet ----
  sheet_name <- substr(subj, 1, 31)   # Excel's sheet-name limit
  addWorksheet(wb, sheet_name)
  
  df        <- list_of_models[[subj]]
  events    <- df$Event_ID
  export_df <- df |> select(-Subject_ID, -Event_ID)
  num_cols  <- setdiff(seq_len(ncol(export_df)), 1:3)
  export_df[num_cols] <- lapply(export_df[num_cols], function(col) suppressWarnings(as.numeric(col)))
  
  # Header block
  writeData(wb, sheet_name, " ", xy = c(1, 1))
  addStyle(wb, sheet_name, Main_Head_Style, cols = 1:6, rows = 1:2, gridExpand = TRUE)
  mergeCells(wb, sheet_name, cols = 1:6, rows = 1:2)
  writeData(wb, sheet_name, "Please insert data from only 1 unit per Round", xy = c(7, 1))
  addStyle(wb, sheet_name, Main_Head_Style, cols = 7:13, rows = 1:2, gridExpand = TRUE)
  mergeCells(wb, sheet_name, cols = 7:13, rows = 1:2)
  
  meta_labels <- c("Rabbit ID", "Rabbit weight: kg", "Transfusion date:",
                   "Bleed volume (mL) & %:", "Transfusion volume (mL):", "Tele ID")
  for (k in seq_along(meta_labels)) writeData(wb, sheet_name, meta_labels[k], xy = c(1, 3 + k))
  writeData(wb, sheet_name, "Exclude rabbit?", xy = c(5, 4))
  writeData(wb, sheet_name, "Reason:", xy = c(5, 5))
  
  setColWidths(wb, sheet_name, cols = 1:7, widths = c(28.22, 9.33, 13.56, 10.89, 15.33, 26.56, 10.89))
  setRowHeights(wb, sheet_name, rows = 1:9, heights = c(25.8, 27, 25.8, 25.8, 26.4, 27, 25.8, 25.8, 15.6))
  addStyle(wb, sheet_name, Meta_Labels, rows = 4:9, cols = 1, gridExpand = TRUE)
  addStyle(wb, sheet_name, Meta_Labels, rows = 4:5, cols = 5, gridExpand = TRUE)
  
  writeData(wb, sheet_name, subj, xy = c(2, 4))
  date_val <- subject_dates$Transfusion_date[subject_dates$Subject_ID == subj]
  if (length(date_val) > 0 && !is.na(date_val[1])) writeData(wb, sheet_name, date_val[1], xy = c(2, 6))
  
  for (r in 4:6) {
    mergeCells(wb, sheet_name, cols = 2:3, rows = r)
    addStyle(wb, sheet_name, meta_fill, rows = r, cols = 2:3, gridExpand = TRUE)
  }
  # Bleed volume (row 7) and transfusion volume (row 8): B and C stay separate
  # cells, e.g. mL in B and % in C
  addStyle(wb, sheet_name, meta_fill, rows = 7:8, cols = 2:3, gridExpand = TRUE)
  addStyle(wb, sheet_name, meta_fill, rows = 9, cols = 2, gridExpand = TRUE)
  for (r in 4:5) {
    mergeCells(wb, sheet_name, cols = 6:7, rows = r)
    addStyle(wb, sheet_name, meta_fill, rows = r, cols = 6:7, gridExpand = TRUE)
  }
  
  # Assay & unit rows (12 & 13)
  writeData(wb, sheet_name, "Assay >", xy = c(3, 12))
  writeData(wb, sheet_name, t(assay_groups), xy = c(4, 12), colNames = FALSE)
  writeData(wb, sheet_name, "Units >", xy = c(3, 13))
  writeData(wb, sheet_name, t(units_row), xy = c(4, 13), colNames = FALSE)
  
  group_start <- 4
  for (len in runs$lengths) {
    if (len > 1) mergeCells(wb, sheet_name, cols = group_start:(group_start + len - 1), rows = 12)
    group_start <- group_start + len
  }
  addStyle(wb, sheet_name, bold_center, rows = 12:13, cols = 3:(3 + length(target_vars)), gridExpand = TRUE)
  
  # Main table
  data_rows <- first_data_row:(first_data_row + nrow(export_df) - 1)
  writeData(wb, sheet_name, export_df, xy = c(1, 14), colNames = TRUE)
  addStyle(wb, sheet_name, header_fill, rows = 14, cols = seq_len(ncol(export_df)), gridExpand = TRUE)
  addStyle(wb, sheet_name, style_num,  rows = data_rows, cols = num_cols, gridExpand = TRUE)
  addStyle(wb, sheet_name, style_meta, rows = data_rows, cols = 1:3, gridExpand = TRUE)
  
  # Pink: value OUTLIER_FACTOR x above / below this subject's median for that
  # column (a lost or extra decimal point; big real changes show up too)
  for (c in num_cols) {
    vals <- export_df[[c]]
    if (sum(!is.na(vals)) < 3) next
    med <- max(abs(median(vals, na.rm = TRUE)), 0.01)
    outliers <- which(vals > med * OUTLIER_FACTOR | vals < med / OUTLIER_FACTOR)
    if (length(outliers) > 0)
      addStyle(wb, sheet_name, outlier_style, rows = first_data_row - 1 + outliers, cols = c, stack = TRUE)
  }
  
  # Yellow: a missing value with filled neighbours, or a gap inside an assay group
  for (r in seq_len(nrow(export_df))) {
    row_vals <- unlist(export_df[r, ])
    for (c in num_cols) {
      if (!is.na(row_vals[c])) next
      if ((c - 1) %in% num_cols && (c + 1) %in% num_cols &&
          !is.na(row_vals[c - 1]) && !is.na(row_vals[c + 1])) {
        addStyle(wb, sheet_name, sandwich_style, rows = first_data_row - 1 + r, cols = c, stack = TRUE)
      }
    }
    group_start <- 4
    for (len in runs$lengths) {
      group_cols <- group_start:(group_start + len - 1)
      missing    <- group_cols[is.na(row_vals[group_cols])]
      if (length(missing) > 0 && length(missing) < len) {
        addStyle(wb, sheet_name, sandwich_style, rows = first_data_row - 1 + r, cols = missing, stack = TRUE)
      }
      group_start <- group_start + len
    }
  }
  
  # Orange + comment: flagged by the OCR / range / arithmetic checks, and
  # timepoints that had to be guessed
  subject_flags <- bind_rows(review_queue, timepoint_flags) |> filter(Subject_ID == subj)
  for (k in seq_len(nrow(subject_flags))) {
    r <- match(subject_flags$Event_ID[k], events)
    c <- match(subject_flags$Column[k], names(export_df))
    if (is.na(r) || is.na(c)) next
    addStyle(wb, sheet_name, review_style, rows = first_data_row - 1 + r, cols = c, stack = TRUE)
    writeComment(wb, sheet_name, col = c, row = first_data_row - 1 + r,
                 comment = createComment(subject_flags$Review_Reason[k], author = "OCR check", visible = FALSE))
  }
}

setColWidths(wb, "Page Dictionary", cols = 1:(start_col_pg - 1), widths = "auto")
setColWidths(wb, "Review Queue", cols = seq_len(ncol(review_queue)), widths = "auto")

output_file <- file.path(Results_Folder, paste0("Processed_PDFs_", format(Sys.time(), "%m-%d_-%H-%M"), ".xlsx"))
saveWorkbook(wb, output_file, overwrite = TRUE)
cat("Results saved to:\n", output_file, "\n")