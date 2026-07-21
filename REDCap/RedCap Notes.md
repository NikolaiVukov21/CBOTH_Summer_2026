RedCap Notes:



* Accessing UMB REDCap:

  * UMB REDCap Link: https://umbredcap.umaryland.edu/

    * No VPN required
    * Sign in with UMID
    * Approved for projects that do not contain highly sensitive information



* Accessing UMB SRE REDCap:

  * UMB SRE REDCap link: https://umbredcapsre.umaryland.edu/

    * Only accessible in the UMB SRE
    * SRE access can be request by emailing: redcap@umaryland.edu
    * Once connected: sign in with UMID



* Record Information Including:

  * deidentified UMMS Epic Data:

    * (Data pulls and/or chart reviews)
  * other sensitive information
* Must be stored in the UMB Secure Research Environment (SRE)



* SRE:

  * Data can be manually entered into a REDCap project via data entry forms, surveys or data imports
  * Data can be analyzed in the SRE virtual desktop with statistical tools available in the SRE



* Entering Data:

  * Record ID field must be the first field in the first instrument in the project
  * Keep forms short
  * Limit free text response fields
  * Validate fields whenever possible
  * Ensure Variables names are short and meaningful

    * (Record\_id)
    * (f\_name)
    * (l\_name)
    * (email)
    * (city)
    * (state)
  * Flag fields that are identifiers (Name, Subject ID, etc.)

    * Like keys in SQL



* Project Lifecycle:

  * Test the Project Thoroughly
  * Move the project to production before data collection begins
  * Once data collection is completed, transition the project to analysis/cleanup to preserve the data
  * Remove the project from REDCap when no longer needed (Not a long-term storage solution)



* Project Migration Guidelines:

  * Thoroughly think through the project's data collection plan. **All SRE projects will need to be migrated by a REDCap admin**
  * All active projects should be migrated immediately or as soon as feasible.

    * if immediate migration is not possible, provide the REDCap team with an estimated date for the transition



* Development Projects:

  * Projects still in development (and doesn't require SRE) can be self-migrated by navigating to:

    * Project Setup -> Other Functionality -> Download or Back up the Project -> select "Download the metadata only (XML)
  * To move the project:

    * Select "New Project" in the UMB RedCap ->upload this XML file





* Active Projects:

  * Active projects can be moved when they can be paused
  * Key Considerations when moving an active project to the new UMB REDCap environment

    * Active survey Data Collection:

      * Public Survey Links or QR Code
      * Previously sent or scheduled survey invitations
    * Alerts:

      * Future Notifications
    * Randomization

      * Active randomization
  * consult the guide: https://redcap.umaryland.edu/surveys/?s=WNTNN8FRHWDPF9T8
  * or work with the REDCap team on your project's migration.



* Non-Active Projects (Paused or in Analysis):

  * If a project is Paused or in Analysis, but continues to collect data in the future, it can be migrated now:

    * Use File Repository in the new project to retain files:

      * Data Export File
      * Data Dictionary File
      * Logging History
      * PDFS/ File Uploads
      * Consents/ PDF snapshot archive



* Completed Migrations:

  * Allow yourself time to review the projects, confirm all project metadata and data successfully transferred.
  * Important to remove user accessed and delete the original project to prevent new edits or data collection



* For Assistances, reach out to: redcap@umaryland.edu



**Project Specific Notes:**

* Events:

  * There are 3 scenarios / arms in the project with multiple events:

    * Arm 1: Scenario A

      * Baseline (baseline\_arm\_1)
      * EOS (eos\_arm\_1)
      * EOR (eor\_arm\_1)
      * 1H (1h\_arm\_1)
      * 3H (3h\_arm\_1)
      * 6H (6h\_arm\_1)
      * 24H (24h\_arm\_1)
    * Arm 2: Scenario B

      * Base Line (base\_line\_arm\_2)
      * EOS (eos\_arm\_2)
      * EOR (eor\_arm\_2)
      * 10% / First Bleed (10\_arm\_2)
      * 7.50% / Second Bleed (750\_arm\_2)
      * 5% / Third Bleed (5\_arm\_2)
      * 2.5% / fourth Bleed  (250\_arm\_2)
      * End of Bleed (end\_of\_bleed\_arm\_2)
      * 24H (24h\_arm\_2)
      * 48H (48h\_arm\_2)
      * 72H (72h\_arm\_2)
    * Arm 3: Scenario C

      * Base Line (base\_line\_arm\_3)
      * EOS (eos\_arm\_3)
      * EOR (eor\_arm\_3)
      * EOD (eod\_arm\_3)
      * 1H Post Damp (1h\_post\_damp\_arm\_3)
      * 24H Post Damp (24h\_post\_damp\_arm\_3)
      * 48H Post Damp (48h\_post\_damp\_arm\_3)
      * 72H Post Damp (72h\_post\_damp\_arm\_3)



* And 7 Instruments for Collecting Data

  * Baseline:

    * Subject\_id (Identifier - Required)
    * digitize Charts (Let's the user upload the chart scan)
    * rabbit\_weight (kg)
    * transfusion\_date (date)
    * Bleed Volume / bld\_volume (mL)
    * Transfusion Volume / transf\_vol (mL)
    * Exclude (Yes/No)
    * Reason for exclusion (only appears if Exclude == "Yes")
  * Baseline\_C:

    * Similar to "Baseline" with following additions:
    * Damp Loading Info (mL, for both Loading dose/5 minutes and gTT/4 hours)
    * Brain Tissue Vol (mL, for both Loading dose/5 minutes and gTT/4 hours)
    * Total Damp (mL, for both Loading dose/5 minutes and gTT/4 hours)
    * M Vol (mL, for both Loading dose/5 minutes and gTT/4 hours)
    * bleed volume (mL, for both Loading dose/5 minutes and gTT/4 hours)
  * For each Event:
  * Clinical Vitals:

    * Time (Clock time)
    * MAP (mmHG)
    * BPM (bpm)
    * body\_temp (°C)
* ABG

  * pH level
  * pCO2 level (mmHg)
  * pO2 level (mmHg)
  * LAC (mm0l/L)
* CBC

  * WBC (10^3/uL)
  * RBC (M/ml)
  * HGB (mg/dL)
  * HCT (mmHg)
  * PLT (10^3/uL)
* CMP

  * GGT (U/L)
  * AST (U/L)
  * ALT (U/L)
  * AMY (U/L)
  * IDH (U/L)
  * CREA (mg/dL)
  * BUN (mg/dL)
  * GLU (mg/dL)
  * TH (mg/dL)
* Coag-Teg

  * R (min)
  * K (min)
  * angle (deg)
  * MA (mm)

