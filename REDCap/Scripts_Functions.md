**Setup Script "R\_Setup\_Script" - API Setup Script: 

**Core Purpose:**
* *Purpose:* This R script asks, and stores the API key used in REDCap to directly parse / upload data.
* *Method:* checks the local system environment for an API key (Via. *REDCAP\_API\_TOKEN*, 
	* if none is returned ask user to type / upload the key
		* Saves upload key to a private local system environment called "*.Renviron*"	 
* *End goal:* Securely helps the user establish and save their API to be use


**Script 1: "R\_Script\_PDF" -Clinical PDF OCR & Extraction Pipeline**



**Core Purpose:**

* *Purpose:* This R script automates the extraction of biomedical laboratory data (ABG, CBC, CMP, TEG, and Coagulation panels) from multi-page PDFs. 
* *Method:* It uses spatial coordinate mapping and Optical Character Recognition (OCR) to pair variables with their numeric values
* *End goal:* structuring the data into a formatted, multi-sheet Excel workbook.



**1. Ingestion \& Pre-Processing**



* *Package Dependencies:* Relies heavily on -

  * ***pdftools*** (native text extraction)
  * ***tesseract*** / ***magick*** (OCR and image processing)
  * ***tidyverse*** packages for data manipulation.



* *Hybrid Extraction:* 

  * *First: at*tempts to read native PDF text.
  * *If a page is scanned or blank:* falls back to rendering the page as a high-DPI image

    * enhances the page (grayscale, high contrast, deskewing)
    * Runs `tesseract` OCR to extract text alongside precise X/Y bounding box coordinates. (OCR \& Spatial Coordinate Mapping)



**2. Normalization \& Classification**



* Text Normalization (*Normalize\_Cell*): Cleans up common OCR artifacts and corrects known misread variables

  * e.g.:

    * fixing commas to decimals 
    * correcting `pC02` to `pCO2`, or 
    * `oH` to `pH`



* Page Fingerprinting (*detect\_page\_type*): Classifies the specific lab panel type on each page

  * Method: by scanning for required trigger variables 

    * (e.g., finding WBC, RBC, HGB, and HCT designates a page as a "CBC" report)



**3. Spatial Pairing Logic**



* *Coordinate Matching:* Since lab reports are laid out visually rather than sequentially in text:

  * the script relies on X/Y coordinates to pair a numeric value with its correct variable label.



* *Search Hierarchy:* For every identified number, the script looks for text elements:

  1. Immediately to the **left** (tight vertical alignment).
  2. Directly **above** (same column).
  3. Matching the **exact Y-axis** across the row.



* *Confidence Scoring*: Assigns a match confidence (High, Medium, Low) based on:

  * &#x20;the absolute **horizontal** and **vertical** **distance** **between** the **value** and the **matched label**.



**4. Data Structuring**



* *Subject \& Time Identification:* Uses Regular Expressions (Regex) to:

  * Pull specific test subjects (Rabbit IDs) 
  * isolate the date and time of the transfusion/event from the ABG pages.



* *Pivoting:* Transforms the matched coordinate pairs from a long dataset into a wide format 

  * Aggravates the data by *Subject\_ID* and chronological *Event\_ID*



**5. Export \& Quality Control**



* *Excel Workbook Generation:* Uses **openxlsx** to output a master file containing:

  * raw extraction logs 
  * pairwise master sheet 
  * individual sheets dedicated to each specific subject.



* *Automated Anomaly Detection:*

  * *Extreme Outliers:* Calculates the Median Absolute Deviation (MAD) for each column. 

    * Values exceeding a 6x MAD threshold are highlighted in red (*#FFC7CE*).
  * *"Sandwich" Missing Data:* if cells are empty and surrounded by valid data points:

    * Highlights empty cells in yellow (*#FFE536*) 
    * does this across timepoints or related assay groups

      * flags potential extraction failures for manual review.







**Script 2: "R\_Script\_Excel" - Excel-to-REDCap Integration Pipeline**



**Core Purpose:**

* *Purpose:* This R script acts as the bridge between the processed Excel sheets and the REDCap database. 
* *Method:* dynamically reads raw clinical data from various experimental rabbit models, standardizes the variables

  * Maps them to their specific REDCap events (based on the experimental arm)
  * Automates the database upload via the REDCap API
* *End Goal:* automates the uploading of data to the REDCap project 



**1. Dynamic File \& Range Discovery**

* Package Dependencies: Relies on -

  * **readxl** for importing 
  * **tidyverse** for data manipulation
  * **REDCapR** for the final API push.



* Smart Range Finder (*find\_long\_data\_range*): Finds the range of rows and columns of the sheet by:

  * Actively scans Column A to locate the "Timepoint/Event" header.
  * 'Runs' alongside the *'Measurment>'* column till it reaches a empty header 
  * Determines the exact bounding box of the valid data dynamically.



2\. **Metadata Extraction \& Cleaning**

* *Targeted Cell Extraction:* Pulls baseline metadata (Subject ID, weight, transfusion volumes, telemetry ID) from specific static cells (e.g., B4:B9, F4:F5).



* *Date Normalization:* Contains robust error-handling to standardize dates into REDCap’s required YYYY-MM-DD format.

  * Actively catches and fixes Excel's known date formatting issues 

    * like converting days elapsed since January 1, 1900.



* *Header Mapping:* Converts messy or inconsistent Excel column names into the standardized REDCap variable dictionary 

  * e.g.:

    * converting "heartrate" to bpm
    * converting "appt" to aptt.



**3. Experimental Arm Routing**

* *Scenario Logic:* The script looks at the filename to determine the experimental arm (Scenario A, B, or C).



* *Scenario C Specifics:* If it detects Scenario C:

  * triggers a specialized extraction block to pull targeted baseline data like:

    * DAMP load info, brain tissue volume
    * 4-hour/5-min metrics 

      * Uses: columns K, O, P, S, and T.



* *Timepoint Standardization:* Unifies inconsistent timepoint naming. 

  * Uses numeric conversion to accurately map bleed percentages (e.g., 10%, 0.1) into standard REDCap event names:

    * first\_bleed 
    * second\_bleed
    * third\_bleed
    * fourth\_bleed
  * accounts for different naming conventions across procedures.



**4. REDCap Payload Construction**

* *Event Mapping:* Generates the crucial *redcap\_event\_name* column required for longitudinal REDCap databases 

  * (e.g., appending \_arm\_1, \_arm\_2, or \_arm\_3 based on the scenario).



* *Completion Flags:* Evaluates each row of data and automatically calculates REDCap form completion statuses 

  * (e.g., abg\_complete, cbc\_complete). 

    * If data is present in the required fields for that panel, flags the form with a 1 (unverified)



**5. Automated Export \& API Upload**

* *Local Backup:* Saves a compiled CSV of the cleaned payload to an *"Output Sheets"* folder with the current date.



* *Direct API Integration:* Uses a locally stored environment variable (REDCAP\_API\_TOKEN) to:
* Authenticate and securely push the structured dataframe directly to the university's REDCap server:

  * (\[https://umbredcap.umaryland.edu/api/](https://umbredcap.umaryland.edu/api/))

    * eliminating the need for manual data entry.





