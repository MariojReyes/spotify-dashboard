# ==============================================================================
# CACHE MANAGEMENT: Compare Hot 100 tracks & manage audio features cache
# ==============================================================================
# This script:
# 1. Loads current Hot 100 from hot100_ojs.json
# 2. Compares with cached track IDs from last week
# 3. Identifies NEW tracks (need ReccoBeats), KEPT tracks (use cache), DROPPED tracks
# 4. Returns info needed for fetch_audio_features.R
#
# Cache files (GitHub Actions Cache):
#   - data/cache/hot100_ids_cache.rds: Last week's track IDs
#   - data/cache/audio_features_cache.rds: Audio features keyed by song_id
# ==============================================================================

library(tidyverse)
library(jsonlite)

# load current Hot 100 (from fetch_hot100.R output)

load_current_hot100 <- function(json_path = "hot100_ojs.json") {
  
  if (!file.exists(json_path)) {
    stop("hot100_ojs.json not found. Run fetch_hot100.R first.")
  }
  
  hot100_df <- read_json(json_path, simplifyVector = TRUE) |>
    as_tibble()
  
  cat("loaded current Hot 100:", nrow(hot100_df), "tracks\n")
  
  return(hot100_df)
}


# load cached data from last week

load_caches <- function() {
  
  # ensure cache directory exists
  if (!dir.exists("data/cache")) {
    dir.create("data/cache", recursive = TRUE)
    cat("Created data/cache directory\n")
  }
  
  ids_cache_file <- "data/cache/hot100_ids_cache.rds"
  audio_cache_file <- "data/cache/audio_features_cache.rds"
  
  # load cached track IDs
  if (file.exists(ids_cache_file)) {
    cached_ids <- readRDS(ids_cache_file)
    cat("✓ Loaded", length(cached_ids), "track IDs from last week\n")
  } else {
    cached_ids <- character(0)
    cat("ℹ No cached track IDs (first run)\n")
  }
  
  # Load cached audio features
  if (file.exists(audio_cache_file)) {
    cached_audio <- readRDS(audio_cache_file)
    cat("loaded audio features for", nrow(cached_audio), "tracks\n")
  } else {
    cached_audio <- tibble(song_id = character(0))
    cat("No cached audio features (first run)\n")
  }
  
  return(list(
    ids = cached_ids,
    audio = cached_audio
  ))
}

# ============================================================================
# Compare track IDs & identify new/kept/dropped
# ============================================================================

compare_track_lists <- function(current_ids, cached_ids) {
  
  cat("\n📋 Comparing track lists:\n")
  
  new_ids <- setdiff(current_ids, cached_ids)
  kept_ids <- intersect(current_ids, cached_ids)
  dropped_ids <- setdiff(cached_ids, current_ids)
  
  cat("  - NEW tracks (need ReccoBeats):", length(new_ids), "\n")
  cat("  - KEPT tracks (use cache):", length(kept_ids), "\n")
  cat("  - DROPPED tracks (remove):", length(dropped_ids), "\n")
  
  return(list(
    new = new_ids,
    kept = kept_ids,
    dropped = dropped_ids
  ))
}


# save updated track IDs cache (for next week's comparison)


save_ids_cache <- function(current_ids) {
  
  saveRDS(current_ids, "data/cache/hot100_ids_cache.rds")
  cat("Saved", length(current_ids), "track IDs for next week\n")
  
  return(invisible(TRUE))
}

# ============================================================================
# MAIN FUNCTION: returns info needed for audio features fetching
# ============================================================================

manage_cache <- function() {
  
  cat("\n", strrep("=", 70), "\n")
  cat("MANAGING HOT 100 CACHE\n")
  cat(strrep("=", 70), "\n\n")
  
  # ;oad current Hot 100
  hot100_df <- load_current_hot100()
  
  # load cached data from last week
  caches <- load_caches()
  
  # compare current vs cached
  current_ids <- hot100_df |> pull(song_id)
  track_status <- compare_track_lists(current_ids, caches$ids)
  
  # save current track IDs for next week's comparison
  save_ids_cache(current_ids)
  
  # prepare info for audio features fetching
  new_tracks_df <- hot100_df |>
    filter(song_id %in% track_status$new) |>
    select(song_id, song_name, artist_name)
  
  if (nrow(new_tracks_df) > 0) {
    cat("\n New tracks to fetch from ReccoBeats:\n")
    print(new_tracks_df, n = min(5, nrow(new_tracks_df)))
  } else {
    cat("\n No new tracks - no ReccoBeats API calls needed\n")
  }
  
  # Filter cached audio to only keep tracks still on chart
  kept_audio <- caches$audio |>
    filter(song_id %in% track_status$kept)
  
  cat("\n Cache management complete\n")
  cat(" Ready for fetch_audio_features.R\n\n")
  
  # Return everything needed for next step
  return(list(
    new_track_ids = track_status$new,       # IDs to fetch from ReccoBeats
    kept_audio = kept_audio,                 # Audio features to reuse
    hot100_df = hot100_df                   # Current Hot 100 for final merge
  ))
}

# uncomment to run as a standalone script

#if (!interactive()) {
#  result <- manage_cache()
#  cat("New track IDs:", paste(result$new_track_ids, collapse = ", "), "\n")
#}