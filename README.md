# Billboard Hot 100 (Spotify Dashboard)

A Quarto dashboard that tracks songs from Spotify’s “Billboard Hot 100” playlist and displays them in an interactive table with album art, duration, and Spotify popularity, plus a track embed player.

## What it shows
- Current playlist tracks (song, artist, duration, release date in source data)
- Spotify popularity (0–100) as a bubble in the table
- Track embed player (Spotify iframe)
- Cached enrichment pipeline for audio features used in downstream analysis data

## How it works (quick)
- Uses the Spotify Web API with **Client Credentials** (no user login).
- Fetches the Billboard Hot 100 Spotify playlist and writes JSON output for dashboard interactivity.
- Uses cache-aware scripts to detect new chart entries and only fetch missing audio features.
- Pulls audio-feature enrichment from ReccoBeats and writes `data/hot100_enriched.rds` for extended analysis workflows.

Repo Layout:
```
spotify-dashboard/
├── README.md
├── _quarto.yml
├── about.qmd
├── custom.scss
├── dashboard.qmd
├── data/
│   ├── hot100_ojs.json
│   ├── hot100_enriched.rds
│   └── cache/
│       ├── audio_features_cache.rds
│       └── hot100_ids_cache.rds
├── scripts/
│   ├── fetch_hot100.R
│   ├── manage_cache.R
│   └── fetch_audio_analysis.R
├── images/
│   ├── headshot.jpg
│   ├── logo.png
│   └── spotify-logo-png-7069.png
├── renv.lock
├── renv/
│   ├── .gitignore
│   ├── activate.R
│   └── settings.json
└── spotify-dashboard.Rproj
```


Credits:

Layout and styling inspiration from Melissa Van Bussel’s Posit 2024 Table Contest dashboard + tutorial:
https://melissavanbussel.github.io/spotify-dashboard
https://github.com/melissavanbussel/spotify-dashboard
