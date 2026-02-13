# Improved Cache Management Script

# Load required libraries
library(jsonlite)  
library(dplyr)  
library(tidyr)  
library(fs)

# Function to load cache data
load_cache <- function() {  
  # Load hot100_ojs.json data
  hot100_data <- fromJSON("data/hot100_ojs.json")  

  # Create data/cache directory if it doesn't exist
  if (!dir_exists("data/cache")) {  
    dir_create("data/cache")  
  }

  # Extract new track IDs and other relevant data
  new_track_ids <- hot100_data$new_track_ids  
  kept_audio <- hot100_data$kept_audio  
  hot100_df <- hot100_data$hot100_df  

  # Return results as a list
  return(list(new_track_ids = new_track_ids, kept_audio = kept_audio, hot100_df = hot100_df))
}

# Usage
# cache_data <- load_cache()  
