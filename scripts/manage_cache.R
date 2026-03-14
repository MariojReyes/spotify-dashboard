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

# ------------------------------------------------------------------------------
# load cached data from last week (including snapshot_id for chart-week detection)

load_caches <- function() {

  if (!dir.exists("data/cache")) {
    dir.create("data/cache", recursive = TRUE)
    cat("Created data/cache directory\n")
  }

  ids_cache_file   <- "data/cache/hot100_ids_cache.rds"
  audio_cache_file <- "data/cache/audio_features_cache.rds"

  # load cached track IDs and snapshot_id
  # Handle both old format (character vector) and new format (list with snapshot)
  if (file.exists(ids_cache_file)) {
    cached_data <- readRDS(ids_cache_file)
    
    # Check if it's the old format (character vector) or new format (list)
    if (is.list(cached_data) && !is.null(cached_data$ids)) {
      # New format with snapshot
      cached_ids <- cached_data$ids
      cached_snapshot_id <- cached_data$snapshot_id
      cat("Loaded", length(cached_ids), "track IDs from cache (snapshot:", substr(cached_snapshot_id, 1, 8), "...)\n")
    } else {
      # Old format: character vector
      cached_ids <- cached_data
      cached_snapshot_id <- NULL
      cat("Loaded", length(cached_ids), "track IDs from legacy cache (no snapshot)\n")
    }
  } else {
    cached_ids <- character(0)
    cached_snapshot_id <- NULL
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
    ids              = cached_ids,
    snapshot_id      = cached_snapshot_id,
    audio            = cached_audio
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

# persist current track IDs and snapshot_id for chart-week detection

save_ids_cache <- function(current_ids, current_snapshot_id) {
  cache_data <- list(
    ids = current_ids,
    snapshot_id = current_snapshot_id
  )
  saveRDS(cache_data, "data/cache/hot100_ids_cache.rds")
  cat("Saved", length(current_ids), "track IDs and snapshot", substr(current_snapshot_id, 1, 8), "...\n")
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

# ==============================================================================
# MAIN: returns everything fetch_audio_features.R needs
# ==============================================================================

manage_cache <- function() {

  cat("\n", strrep("=", 70), "\n")
  cat("MANAGING HOT 100 CACHE\n")
  cat(strrep("=", 70), "\n\n")

  # Load snapshot_id from current run
  if (!file.exists("data/hot100_snapshot.rds")) {
    stop("data/hot100_snapshot.rds not found. Run fetch_hot100.R first.")
  }
  current_snapshot_id <- readRDS("data/hot100_snapshot.rds")

  hot100_df    <- load_current_hot100()
  caches       <- load_caches()                        # weeks_on_chart normalised here
  current_ids  <- hot100_df |> pull(song_id)
  track_status <- compare_track_lists(current_ids, caches$ids)

  # CRITICAL: Detect whether this is a new chart week
  # Compare current snapshot_id with cached snapshot_id
  is_new_chart_week <- is.null(caches$snapshot_id) || (caches$snapshot_id != current_snapshot_id)

  if (is_new_chart_week) {
    cat("\n✓ NEW CHART WEEK detected (snapshot changed)\n")
    cat("  Previous snapshot:", substr(caches$snapshot_id %||% "(none)", 1, 16), "...\n")
    cat("  Current snapshot: ", substr(current_snapshot_id, 1, 16), "...\n")
  } else {
    cat("\n⚠ Same chart snapshot (rerun detected)\n")
    cat("  Not incrementing weeks_on_chart\n")
  }

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

  # Increment weeks_on_chart ONLY if this is a new chart week
  # If it's a rerun of the same snapshot, use cached values as-is
  if (is_new_chart_week) {
    kept_audio <- caches$audio |>
      filter(song_id %in% track_status$kept) |>
      mutate(weeks_on_chart = weeks_on_chart + 1L)
    cat("\nIncremented weeks_on_chart for", nrow(kept_audio), "returning tracks\n")
  } else {
    kept_audio <- caches$audio |>
      filter(song_id %in% track_status$kept)
    cat("\nUsing cached weeks_on_chart (no increment for rerun)\n")
  }

  cat("\nCache management complete\n")
  cat("Ready for fetch_audio_features.R\n\n")

  return(list(
    new_track_ids       = track_status$new,
    kept_audio          = kept_audio,
    hot100_df           = hot100_df,
    is_new_chart_week   = is_new_chart_week,
    current_snapshot_id = current_snapshot_id
  ))
}
