# Lab Data to REDCap
 
This project takes the lab printouts from the rabbit experiments (Scenarios A–C), turns them into a spreadsheet, and uploads the results to the **REDCap** online database, so nobody has to input every number by hand.
 
## How it fits together
 
| Step | Script | What it does |
|---|---|---|
| 0 | `REDCap_Master_Script` | Runs the steps below in order. |
| 1 | `R_Setup_Script` | Saves your REDCap access key (one-time setup). |
| 2 | `R_Script_PDF` | Reads the scanned PDFs and builds an Excel workbook. |
| 3 | `R_Script_Excel` | Checks the Excel workbook and uploads it to REDCap. |
 
**The usual workflow:** run the PDF reader → review the flagged (orange) cells in Excel → run the uploader.
 
---
 
## 1. Setup — `R_Setup_Script`
 
REDCap needs a private access key (an "API token") before anything can be uploaded.
 
- The script first looks for a saved key on your computer.
- If it can't find one, it asks you to paste it in, then saves it privately on your computer (in a file called `.Renviron`) so you only do this once.
- **Never share this key or put it in the scripts themselves.**
---
 
## 2. PDF Reader — `R_Script_PDF`
 
Reads the multi-page PDFs from each experiment and pulls out the lab results for **blood gas (ABG), blood count (CBC), chemistry (CMP), clotting (TEG) and coagulation (Coag)** panels.
 
### What it does, step by step
 
1. **Reads each page.** Pages are scanned images, so the script uses text recognition (OCR) to read them. Page 1 of every PDF is a handwritten summary sheet and is skipped.
2. **Fixes page orientation.** Sideways, upside-down or slightly tilted pages are turned and straightened before reading.
3. **Works out what each page is.** It looks for the variable names it expects (e.g. WBC, RBC, HGB and HCT mean a CBC page). Pages it doesn't recognise, such as forms and graphs, are ignored.
4. **Matches each variable to its value.** Most printouts list the value to the right of its name; on TEG printouts it sits underneath. Common misreadings of variable names (e.g. "Py" for PT) are corrected automatically.
5. **Double-checks every value.** Each number is re-read several times from close-up images, and the readings must agree. It also:
   - rejects values that are impossible (e.g. a pH of 1.4) or printed in the wrong format,
   - checks the image for a decimal point when one may have been missed (so "154" becomes 15.4, while a real 19 stays 19),
   - on blood gas pages, uses the analyser's own formulas (Henderson-Hasselbalch & Van Slyke base excess) to confirm that pH, pCO2 and HCO3 agree with each other, and corrects a misread digit when they don't.
6. **Flags anything it isn't sure about** instead of guessing. If the readings disagree, the cell is left blank and flagged.
### What you get
 
An Excel workbook in the **Processed PDFs** folder with:
 
- **One sheet per rabbit:** results laid out by timepoint (Baseline, EOS, EOR, 20%, 15%, 10%, EOB, 1HR, 24HR), ready for upload.
- **Review Queue:** every value that needs a human check, with the reason.
- **Supporting sheets:** everything the script read (*Raw Extraction*), every variable–value match (*Pairwise Master*), which pages were which type (*Page Dictionary*), and processing time per page.
**Cell colours on the rabbit sheets:**
 
| Colour | Meaning | What to do |
|---|---|---|
| 🟧 Orange | The script wasn't sure, or left the cell blank. Hover over the cell to see why. | Check against the printout. |
| 🟥 Pink | Value is far higher or lower than that rabbit's other values (often a misplaced decimal point). | Check against the printout. |
| 🟨 Yellow | Value is missing although the values around it were found. | Look for it on the printout. |
 
Timepoints are filled in order. If a rabbit doesn't have exactly 9 rows, its timepoints are flagged orange so you can confirm them.
 
**Optional — `Annotated_Images` folder:** a picture of every lab page with what the script read drawn on it, one folder per rabbit. Useful to quickly locate and find the missing or unsure values.
 
### Settings
 
All adjustable options are at the top of the script, each with a short note. The most useful:
 
- `SAVE_OCR_DEBUG`: turn the annotated pictures on or off (off is faster for large batches).
- `ANNOATE_FLAGGED_ONLY`: have the annotated pictures show only the uncertain values.
- `ANNOATE_SHOW_OCR_TEXT`: Show OCR text above crop boxes
---
 
## 3. REDCap Uploader — `R_Script_Excel`
 
Takes the reviewed Excel workbook and uploads it to REDCap.
 
1. **Finds the data.** It locates the results table on each rabbit's sheet automatically, along with the rabbit's details (ID, weight, transfusion volumes, telemetry ID).
2. **Cleans it up.**
   - Dates are converted to the format REDCap needs, fixing Excel's habit of turning dates into numbers.
   - Column names are matched to REDCap's variable names (e.g. "heartrate" → `bpm`).
3. **Sorts by experiment.** The file name tells it which scenario (A, B or C) the rabbit belongs to. Scenario C has extra baseline measurements (e.g. DAMP load, brain tissue volume, 4-hour and 5-minute measurements), which are collected too.
4. **Matches timepoints to REDCap.** Timepoint names are standardised (e.g. bleed percentages become `first_bleed` … `fourth_bleed`) and linked to the right REDCap event for that scenario.
5. **Marks completed forms.** Each form (ABG, CBC, …) with data in it is marked "unverified" in REDCap, ready for review there.
6. **Saves a backup and uploads.** A dated copy of everything sent is saved as a CSV in the **Output Sheets** folder, then the data is uploaded to the university's REDCap server (https://umbredcap.umaryland.edu).
---
 
## Good to know
 
- **Always review the orange cells before uploading.** The script flags what it's unsure about, but it can't fix every scan.
- **Scan quality matters most.** Clear, straight scans at 300 DPI give the best results.
- Processing takes roughly a few seconds per page. Blood gas and clotting pages take longest, because they're read twice.
 
