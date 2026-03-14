# scripts/fetch_audio_features.R
# ==============================================================================
# FETCH AUDIO FEATURES: Get ReccoBeats data for new Hot 100 tracks
# ==============================================================================
# This script:
# 1. Sources cache_management.R to identify new tracks
# 2. Fetches audio features from ReccoBeats (batches of 40 if needed)
# 3. Handles missing tracks (fill with NA)
# 4. Merges new + cached audio features & saves updated cache for next week
# 5. Creates enriched dataset for Page 2
#
# Data flow:
#   cache_info$hot100_df   - current Hot 100 chart (100 rows, chart columns only)
#   cache_info$kept_audio  - audio features for returning tracks (weeks_on_chart already incremented)
#   new_tracks_audio_df    - audio features just fetched for brand-new tracks (weeks_on_chart = 1)
#   audio_features_df           - merged audio features for all 100 current tracks (saved to cache)
#   merged_df              - hot100_df left-joined with audio_features_df (saved for dashboard)
#
# Output: data/hot100_enriched.rds (Hot 100 + audio features)
# ==============================================================================

library(tidyverse)
library(httr2)
library(jsonlite)

# source cache management functions
source("scripts/manage_cache.R")

# ------------------------------------------------------------------------------
# fetch audio features from ReccoBeats API

fetch_audio_features <- function(spotify_ids) {

  if (length(spotify_ids) == 0) {
    cat("No new tracks to fetch from ReccoBeats\n")
    return(tibble(song_id = character(0)))
  }

  cat("Fetching audio features for", length(spotify_ids), "new tracks from ReccoBeats...\n")

  # avoids failed github workflows - if fails page 1 of the dashboard should still load
  tryCatch({
    response <- request("https://api.reccobeats.com/v1/audio-features") |>
      req_url_query(ids = paste(spotify_ids, collapse = ",")) |>
      req_headers(Accept = "application/json") |>
      req_perform()

    response_content <- resp_body_json(response)
    cat("Received response for", length(response_content$content), "tracks from API\n")

    return(response_content$content)

  }, error = function(e) {
    warning("ReccoBeats API error: ", e$message)
    cat("API call failed - continuing with cached data only\n")
    return(NULL)
  })
}

# ------------------------------------------------------------------------------
# convert ReccoBeats response to tibble

convert_to_tibble <- function(content_list) {
  if (is.null(content_list) || length(content_list) == 0) {
    return(tibble(song_id = character(0)))
  }

  audio_df <- map(content_list, \(track) {
    tibble(
      reccobeats_id    = track$id,
      song_id          = sub("https://open.spotify.com/track/", "", track$href),
      isrc             = track$isrc,
      acousticness     = track$acousticness,
      danceability     = track$danceability,
      energy           = track$energy,
      instrumentalness = track$instrumentalness,
      key              = track$key,
      liveness         = track$liveness,
      loudness         = track$loudness,
      mode             = track$mode,
      speechiness      = track$speechiness,
      tempo            = track$tempo,
      valence          = track$valence
    )
  }) |>
    list_rbind()

  return(audio_df)
}

# ------------------------------------------------------------------------------
# batch fetching to stay within API limits (max 40 ids per request)

fetch_in_batches <- function(spotify_ids, batch_size = 40) {

  if (length(spotify_ids) == 0) {
    return(tibble(song_id = character(0)))
  }

  id_batches <- split(spotify_ids, ceiling(seq_along(spotify_ids) / batch_size))
  cat("Splitting into", length(id_batches), "batch(es) of up to", batch_size, "tracks\n")

  batch_results <- list()

  for (i in seq_along(id_batches)) {
    cat("\nBatch", i, "of", length(id_batches), "...\n")
    batch_content <- fetch_audio_features(id_batches[[i]])
    if (!is.null(batch_content)) {
      batch_results[[i]] <- convert_to_tibble(batch_content)
    }
  }

  if (length(batch_results) > 0) {
    return(list_rbind(batch_results))
  } else {
    return(tibble(song_id = character(0)))
  }
}

# ------------------------------------------------------------------------------
# fill in NA rows for any tracks the API didn't return

add_missing_tracks <- function(requested_ids, fetched_audio_df) {

  missing_ids <- setdiff(requested_ids, fetched_audio_df$song_id)

  if (length(missing_ids) > 0) {
    cat("ReccoBeats missing data for", length(missing_ids), "track(s) - filling with NA\n")

    missing_rows <- tibble(
      reccobeats_id    = NA_character_,
      song_id          = missing_ids,
      isrc             = NA_character_,
      acousticness     = NA_real_,
      danceability     = NA_real_,
      energy           = NA_real_,
      instrumentalness = NA_real_,
      key              = NA_integer_,
      liveness         = NA_real_,
      loudness         = NA_real_,
      mode             = NA_integer_,
      speechiness      = NA_real_,
      tempo            = NA_real_,
      valence          = NA_real_
    )

    return(bind_rows(fetched_audio_df, missing_rows))
  }

  return(fetched_audio_df)
}

# ------------------------------------------------------------------------------
# join audio features onto Hot 100 chart data and save for dashboard

create_enriched_dataset <- function(hot100_df, audio_features_df) {

  merged_df <- hot100_df |>
    left_join(audio_features_df, by = "song_id")

  if (!dir.exists("data")) dir.create("data")
  saveRDS(merged_df, "data/hot100_enriched.rds")

  tracks_with_audio    <- sum(!is.na(merged_df$danceability))
  tracks_without_audio <- sum(is.na(merged_df$danceability))

  cat("\n Enriched Dataset Summary:\n")
  cat("  - Total tracks:", nrow(merged_df), "\n")
  cat("  - With audio features:", tracks_with_audio, "\n")
  cat("  - Missing audio features:", tracks_without_audio, "\n")

  return(merged_df)
}

# ==============================================================================
# MAIN
# ==============================================================================

cat("\n", strrep("=", 70), "\n")
cat("FETCHING AUDIO FEATURES\n")
cat(strrep("=", 70), "\n\n")

# step 1: identify new vs kept tracks; increment weeks_on_chart for kept tracks
cache_info <- manage_cache()

# step 2: fetch ReccoBeats audio features for new tracks only
if (length(cache_info$new_track_ids) > 0) {

  cat("\n Fetching from ReccoBeats API...\n")
  new_tracks_audio_df <- fetch_in_batches(cache_info$new_track_ids, batch_size = 40)
  new_tracks_audio_df <- add_missing_tracks(cache_info$new_track_ids, new_tracks_audio_df)

} else {
  cat("\n No new tracks - skipping API calls\n")
  new_tracks_audio_df <- tibble(song_id = character(0))
}

cat("  - Kept from cache:", nrow(cache_info$kept_audio), "\n")
cat("  - Fetched new:", nrow(new_tracks_audio_df), "\n")

# step 3: merge kept (weeks_on_chart already incremented) + new (weeks_on_chart = 1),
#         then save updated cache for next week
# result is the full audio features table for all 100 current tracks
audio_features_df <- merge_and_save_audio_cache(cache_info$kept_audio, new_tracks_audio_df)

cat("  - Total audio features:", nrow(audio_features_df), "\n")

# step 4: join audio features onto Hot 100 chart data and save enriched dataset
cat("\n Creating enriched dataset...\n")
merged_df <- create_enriched_dataset(cache_info$hot100_df, audio_features_df)


# Now that all data is validated and saved, persist the cache tracking with snapshot_id
source("scripts/manage_cache.R")  # Load the function (already done in manage_cache() call but explicit here)
save_ids_cache(cache_info$hot100_df$song_id, cache_info$current_snapshot_id)
cat("\n Audio features workflow complete!\n")
cat(" Next: Render dashboard with data/hot100_enriched.rds\n\n")
