# Project Overview

The overall purpose of this project is to intake excel files processed from the TEG machine, clean and transform the data, and finally produce outputs, both visual and informative.

## Files:
The following project has two script files:

- Teg_Master_Script

- Tegs_Function_Script

The "Teg_Master_Script" is the overall master script, this is the script that runs "Tegs_Function_Script". For the master script, 
all that's needed is to change the subject's ID/ Numbers for each round and the reference model presetned in the excel sheet. Upon running the script the program will run the "Tegs_Function_Script",
upon activation, the script will ask the user to pick a file, this is where the user should select the excel sheet they want to process.

<br>

The "Tegs_Function_Script" is the main meat of the project, this is where the pipeline is performed. This script follows a standard ETL process (<u>E</u>xtract, <u>T</ins>ransform, <ins>L</ins>oad). 
With the final outputs being saved in a folder called **_"Output Files"_**, just outside the folder of the script. 

<u>Test</u>
