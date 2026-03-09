# ==============================================================================
# CACHE MANAGEMENT: Compare Hot 100 tracks & manage audio features cache
# ==============================================================================
# This script:
# 1. Loads current Hot 100 from data/hot100_ojs.json
# 2. Compares with cached track IDs from last week
# 3. Identifies NEW tracks (need ReccoBeats), KEPT tracks (use cache), DROPPED tracks
# 4. Returns info needed for fetch_audio_features.R
#
# weeks_on_chart lifecycle:
#   - load_caches()               : normalises column to integer (backfills 1L for old caches)
#   - kept_audio (manage_cache()) : increments by 1 for returning tracks
#   - merge_and_save_audio_cache(): sets 1L for brand-new tracks entering the cache
#
# Cache files (GitHub Actions Cache):
#   - data/cache/hot100_ids_cache.rds    : last week's track IDs
#   - data/cache/audio_features_cache.rds: audio features keyed by song_id
# ==============================================================================

library(tidyverse)
library(jsonlite)

# ------------------------------------------------------------------------------
# load current Hot 100 (from fetch_hot100.R output)

load_current_hot100 <- function(json_path = "data/hot100_ojs.json") {

  if (!file.exists(json_path)) {
    stop("data/hot100_ojs.json not found. Run fetch_hot100.R first.")
  }

  hot100_df <- read_json(json_path, simplifyVector = TRUE) |>
    as_tibble()

  cat("Loaded current Hot 100:", nrow(hot100_df), "tracks\n")

  return(hot100_df)
}

# ------------------------------------------------------------------------------
# load cached data from last week

load_caches <- function() {

  if (!dir.exists("data/cache")) {
    dir.create("data/cache", recursive = TRUE)
    cat("Created data/cache directory\n")
  }

  ids_cache_file   <- "data/cache/hot100_ids_cache.rds"
  audio_cache_file <- "data/cache/audio_features_cache.rds"

  # load cached track IDs
  if (file.exists(ids_cache_file)) {
    cached_ids <- readRDS(ids_cache_file)
    cat("Loaded", length(cached_ids), "track IDs from last week\n")
  } else {
    cached_ids <- character(0)
    cat("No cached track IDs (first run)\n")
  }

  # load cached audio features
  if (file.exists(audio_cache_file)) {
    cached_audio <- readRDS(audio_cache_file)
    cat("Loaded audio features for", nrow(cached_audio), "tracks\n")
  } else {
    cached_audio <- tibble(song_id = character(0))
    cat("No cached audio features (first run)\n")
  }

  # normalise weeks_on_chart: backfill with 1L for caches that predate the column
  # (these tracks were on the chart last week, so 1 is correct before incrementing)
  if (!"weeks_on_chart" %in% names(cached_audio)) {
    cached_audio <- cached_audio |>
      mutate(weeks_on_chart = 1L)
    cat("Backfilled weeks_on_chart = 1 for", nrow(cached_audio), "cached tracks\n")
  } else {
    cached_audio <- cached_audio |>
      mutate(weeks_on_chart = as.integer(weeks_on_chart))
  }

  return(list(
    ids   = cached_ids,
    audio = cached_audio
  ))
}

# ------------------------------------------------------------------------------
# compare track IDs & identify new / kept / dropped

compare_track_lists <- function(current_ids, cached_ids) {

  cat("\nComparing track lists:\n")

  new_ids     <- setdiff(current_ids, cached_ids)
  kept_ids    <- intersect(current_ids, cached_ids)
  dropped_ids <- setdiff(cached_ids, current_ids)

  cat("  - NEW tracks (need ReccoBeats):", length(new_ids), "\n")
  cat("  - KEPT tracks (use cache):",      length(kept_ids), "\n")
  cat("  - DROPPED tracks (removed):",     length(dropped_ids), "\n")

  return(list(new = new_ids, kept = kept_ids, dropped = dropped_ids))
}

# ------------------------------------------------------------------------------
# persist current track IDs so next week's run can diff against them

save_ids_cache <- function(current_ids) {
  saveRDS(current_ids, "data/cache/hot100_ids_cache.rds")
  cat("Saved", length(current_ids), "track IDs for next week\n")
  return(invisible(TRUE))
}

# ------------------------------------------------------------------------------
# persist audio features cache

save_audio_cache <- function(audio_df) {
  saveRDS(audio_df, "data/cache/audio_features_cache.rds")
  cat("Saved audio features for", nrow(audio_df), "tracks\n")
  return(invisible(TRUE))
}

# ------------------------------------------------------------------------------
# merge kept + new audio features, assign weeks_on_chart = 1 for new tracks,
# and persist the updated cache
# called from fetch_audio_features.R after new_track_audio_df is built

merge_and_save_audio_cache <- function(kept_audio, new_track_audio_df) {

  # new tracks enter the cache for the first time: weeks_on_chart starts at 1
  new_track_audio_df <- new_track_audio_df |>
    mutate(weeks_on_chart = 1L)

  audio_features_df <- bind_rows(kept_audio, new_track_audio_df) |>
    distinct(song_id, .keep_all = TRUE) |>          # kept rows appear first so they win
    mutate(weeks_on_chart = as.integer(weeks_on_chart))

  save_audio_cache(audio_features_df)

  return(audio_features_df)
}

# ==============================================================================
# MAIN: returns everything fetch_audio_features.R needs
# ==============================================================================

manage_cache <- function() {

  cat("\n", strrep("=", 70), "\n")
  cat("MANAGING HOT 100 CACHE\n")
  cat(strrep("=", 70), "\n\n")

  hot100_df    <- load_current_hot100()
  caches       <- load_caches()                        # weeks_on_chart normalised here
  current_ids  <- hot100_df |> pull(song_id)
  track_status <- compare_track_lists(current_ids, caches$ids)

  save_ids_cache(current_ids)

  # log new tracks (capped at 5 rows to keep output readable)
  new_tracks_df <- hot100_df |>
    filter(song_id %in% track_status$new) |>
    select(song_id, song_name, artist_name)

  if (nrow(new_tracks_df) > 0) {
    cat("\nNew tracks to fetch from ReccoBeats:\n")
    print(new_tracks_df, n = min(5, nrow(new_tracks_df)))
  } else {
    cat("\nNo new tracks - no ReccoBeats API calls needed\n")
  }

  # increment weeks_on_chart for tracks returning from last week
  # weeks_on_chart is guaranteed non-NA here because load_caches() normalised it
  kept_audio <- caches$audio |>
    filter(song_id %in% track_status$kept) |>
    mutate(weeks_on_chart = weeks_on_chart + 1L)

  cat("\nCache management complete\n")
  cat("Ready for fetch_audio_features.R\n\n")

  return(list(
    new_track_ids = track_status$new,   # IDs to fetch from ReccoBeats
    kept_audio    = kept_audio,         # audio features with weeks_on_chart incremented
    hot100_df     = hot100_df           # current Hot 100 for final join
  ))
}

if (!interactive()) {
  result <- manage_cache()
  cat("New track IDs:", paste(result$new_track_ids, collapse = ", "), "\n")
}