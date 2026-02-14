# scripts/fetch_audio_features.R
# ==============================================================================
# FETCH AUDIO FEATURES: Get ReccoBeats data for new Hot 100 tracks
# ==============================================================================
# This script:
# 1. Sources cache_management.R to identify new tracks
# 2. Fetches audio features from ReccoBeats (batches of 40 if needed)
# 3. Handles missing tracks (fill with NA)
# 4. Merges new + cached audio features
# 5. Saves updated cache for next week
# 6. Creates enriched dataset for Page 2
#
# Output: data/hot100_enriched.rds (Hot 100 + audio features)
# ==============================================================================

library(tidyverse)
library(httr2)
library(jsonlite)

# source cache management functions
source("scripts/manage_cache.R")

# fetch audio features from ReccoBeats API

fetch_audio_features <- function(spotify_ids) {

  if (length(spotify_ids) == 0) {
    cat("No new tracks to fetch from ReccoBeats\n")
    return(tibble(song_id = character(0)))
  }

  cat("Fetching audio features for", length(spotify_ids), "new tracks from ReccoBeats...\n")

  #avoids failed github workflows - if fails page 1 of the dashboard should still load
  tryCatch({
    response <- request("https://api.reccobeats.com/v1/audio-features") |> 
      req_url_query(ids = paste(spotify_ids, collapse = ",")) |>
      req_headers(Accept = "application/json") |>
      req_perform()
  
    response_content <- resp_body_json(response)
    cat("Recieved response", length(response_content$content), "tracks from API\n")

    return(response_content$content)

}, error = function(e) {
    warning("ReccoBeats API error: ", e$message)
    cat("API call failed - continuing with cached data only\n")
    return(NULL)
  })
}

# convert ReccoBeats response to tibble

convert_to_tibble <- function(content_list) {
  if (is.null(content_list) || length(content_list) == 0) {
    return(tibble(song_id = character(0)))
  }

  audio_df <- map(content_list, \(track) {
    tibble(
      reccobeats_id = track$id,
      song_id = sub("https://open.spotify.com/track/", "", track$href),
      isrc = track$isrc,
      acousticness = track$acousticness,
      danceability = track$danceability,
      energy = track$energy,
      instrumentalness = track$instrumentalness,
      key = track$key,
      liveness = track$liveness,
      loudness = track$loudness,
      mode = track$mode,
      speechiness = track$speechiness,
      tempo = track$tempo,
      valence = track$valence
    )
  }) |>
    list_rbind()
  
  return(audio_df)
}

#batch by 40 to avoid API limits if needed

fetch_in_batches <- function(spotify_ids, batch_size = 40) {
 
  if (length(spotify_ids) == 0) {
    return(tibble(song_id = character(0)))
  }
  
  # split into batches
  id_batches <- split(spotify_ids, ceiling(seq_along(spotify_ids) / batch_size))
  
  cat("Splitting into", length(id_batches), "batch(es) of up to", batch_size, "tracks\n")
  
  batch_results <- list()
  
  for (i in seq_along(id_batches)) {
    cat("\nBatch", i, "of", length(id_batches), "...\n")
    
    batch_content <- fetch_audio_features(id_batches[[i]])
    
    if (!is.null(batch_content)) {
      batch_audio_df <- convert_to_tibble(batch_content)
      batch_results[[i]] <- batch_audio_df
    }
  }
  
  # combine all batches
  if (length(batch_results) > 0) {
    combined_audio_df <- list_rbind(batch_results)
    return(combined_audio_df)
  } else {
    return(tibble(song_id = character(0)))
  }
}

# handle missing tracks (fill with NA)

add_missing_tracks <- function(requested_ids, fetched_audio_df) {
  
  fetched_ids <- fetched_audio_df$song_id
  missing_ids <- setdiff(requested_ids, fetched_ids)
  
  if (length(missing_ids) > 0) {
    cat("ReccoBeats missing data for", length(missing_ids), "track(s)\n")
    
    # create NA rows for missing tracks
    missing_audio_df <- tibble(
      reccobeats_id = NA_character_,
      song_id = missing_ids,
      isrc = NA_character_,
      acousticness = NA_real_,
      danceability = NA_real_,
      energy = NA_real_,
      instrumentalness = NA_real_,
      key = NA_integer_,
      liveness = NA_real_,
      loudness = NA_real_,
      mode = NA_integer_,
      speechiness = NA_real_,
      tempo = NA_real_,
      valence = NA_real_
    )
    
    complete_audio_df <- bind_rows(fetched_audio_df, missing_audio_df)
    return(complete_audio_df)
  }
  
  return(fetched_audio_df)
}

# save audio features for next weeks cache

save_audio_cache <- function(audio_df) {
  
  if (!dir.exists("data/cache")) {
    dir.create("data/cache", recursive = TRUE)
  }
  
  saveRDS(audio_df, "data/cache/audio_features_cache.rds")
  cat("Saved", nrow(audio_df), "audio features to cache\n")
  
  return(invisible(TRUE))
}

#write to enriched dataset for page 2 (Hot 100 + audio features called "hot100_enriched.rds")

create_enriched_dataset <- function(hot100_df, audio_df) {
  
  enriched_df <- hot100_df |>
    left_join(audio_df, by = "song_id")
  
  # save enriched dataset for Page 2
  if (!dir.exists("data")) {
    dir.create("data")
  }
  
  saveRDS(enriched_df, "data/hot100_enriched.rds")
  cat("Saved enriched dataset:", nrow(enriched_df), "tracks\n")
  
  # summary stats
  tracks_with_audio <- enriched_df |> filter(!is.na(danceability)) |> nrow()
  tracks_without_audio <- enriched_df |> filter(is.na(danceability)) |> nrow()
  
  cat("\n Enriched Dataset Summary:\n")
  cat("  - Total tracks:", nrow(enriched_df), "\n")
  cat("  - With audio features:", tracks_with_audio, "\n")
  cat("  - Missing audio features:", tracks_without_audio, "\n")
  
  return(enriched_df)
}

#============================================================================
# MAIN FUNCTION: Manage cache and fetch audio features
#============================================================================

cat("\n", strrep("=", 70), "\n")
cat("FETCHING AUDIO FEATURES\n")
cat(strrep("=", 70), "\n\n")

# step 1: run cache management
cache_info <- manage_cache()

# step 2: fetch audio features for new tracks
if (length(cache_info$new_track_ids) > 0) {
  
  cat("\n Fetching from ReccoBeats API...\n")
  
  # batch if needed (>40 tracks)
  new_audio_df <- fetch_in_batches(cache_info$new_track_ids, batch_size = 40)
  
  # add NA rows for missing tracks
  new_audio_df <- add_missing_tracks(cache_info$new_track_ids, new_audio_df)
  
} else {
  cat("\n No new tracks - skipping API calls\n")
  new_audio_df <- tibble(song_id = character(0))
}

# step 3: merge new + cached audio features
cat("\n Merging audio features...\n")

all_audio_df <- bind_rows(cache_info$kept_audio, new_audio_df)

cat("  - Kept from cache:", nrow(cache_info$kept_audio), "\n")
cat("  - Fetched new:", nrow(new_audio_df), "\n")
cat("  - Total audio features:", nrow(all_audio_df), "\n")

# step 4: save updated cache for next week
cat("\n Saving cache...\n")
save_audio_cache(all_audio_df)

# step 5: create enriched dataset for dashboard
cat("\n Creating enriched dataset...\n")
enriched_df <- create_enriched_dataset(cache_info$hot100_df, all_audio_df)

cat("\n Audio features workflow complete!\n")
cat(" Next: Render dashboard with data/hot100_enriched.rds\n\n")