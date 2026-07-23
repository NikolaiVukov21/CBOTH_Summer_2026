#This is the script needed to establish and set a local API. 
#API is needed to connect and upload data to the REDCap project

#Needed Packages
required_packages<-c("rstudioapi")
new_packages<-required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages) > 0) {install.packages(new_packages)}

invisible(lapply(required_packages,library,character.only = TRUE))

#Checks if the key is already established
if(Sys.getenv("REDCAP_API_TOKEN")!=""){
  message("Your API key is already setup and ready to go.")
  
  #Prompts for key
} else{
  new_key<-rstudioapi::askForPassword("First-time setup: Please enter your API key")
  
  #If the key is saved, save it to the private local file:
  if(!is.null(new_key) && new_key!=""){
    env_text<-paste0('REDCAP_API_TOKEN="',new_key,'"\n')
    cat(env_text,file=".Renviron",append=TRUE)
    
    #load into current session
    Sys.setenv(REDCAP_API_TOKEN=new_key)
    
    #Dynamic Messaging
    message("Key has been saved to your computer")
    message("You will not be asked for it again for this project")
  } else{
    message("No key entered. Setup cancelled.")
  }
}