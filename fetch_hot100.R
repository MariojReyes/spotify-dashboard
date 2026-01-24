library(httr2)
library(jsonlite)
library(tidyverse)
library(purrr)

#createaccesstoken
client_id <- Sys.getenv("SPOTIFY_CLIENT_ID")
client_secret <- Sys.getenv("SPOTIFY_CLIENT_SECRET")

token_resp <- request("https://accounts.spotify.com/api/token") |>
  req_method("POST") |>
  req_auth_basic(client_id, client_secret) |>
  req_body_form(grant_type = "client_credentials") |>
  req_perform() |>
  resp_body_json()

spotify_access_token <- token_resp$access_token

#gethot100playlist
hot100_id <- "6UeSakyzhiEt4NB3UAd6NQ"

hot100 <- request(paste0("https://api.spotify.com/v1/playlists/", hot100_id)) |>
  req_method("GET") |>
  req_headers(Authorization = paste0("Bearer ", spotify_access_token)) |>
  req_url_query(market = "US") |>
  req_perform() |>
  resp_body_json()

hot100_df <- tibble(
  song_name = purrr::map_chr(hot100$tracks$items, ~ .x$track$name %||% NA_character_),
  song_id = purrr::map_chr(hot100$tracks$items, ~ .x$track$id %||% NA_character_),
  artist_name = purrr::map_chr(hot100$tracks$items, ~ .x$track$album$artists[[1]]$name %||% NA_character_),
  album_art = purrr::map_chr(hot100$tracks$items, ~ .x$track$album$images[[1]]$url %||% NA_character_),
  track_duration = purrr::map_dbl(hot100$tracks$items, ~ .x$track$duration_ms %||% NA_real_),
  popularity = purrr::map_int(hot100$tracks$items, ~ .x$track$popularity %||% NA_integer_)
  #,sparkline = ""  # placeholder column (blank) - want to add historical average later (days on bbh100)
) |>
  filter(!is.na(song_id), song_id != "")

# Save data for Observable JS (replacement for ojs_define)
write_json(hot100_df, "hot100_ojs.json", auto_unbox = TRUE, null = "null")