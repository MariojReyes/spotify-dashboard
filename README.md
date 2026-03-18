# Billboard Hot 100 (Spotify Dashboard)

A personal end-to-end analytics project built with Quarto that tracks songs from Spotify's "Billboard Hot 100" playlist. The site includes an interactive chart table, a Spotify embed player, and a mood analysis page driven by Spotify audio features.

 **Live site:** https://mariojreyes.github.io/spotify-dashboard/

## Pages

### Hot 100 Chart (`dashboard.qmd`)
- Interactive table showing current Hot 100 tracks with album art, artist, duration, and Spotify popularity rendered as a color-coded bubble
- Song dropdown and embedded Spotify iframe player that stays fixed while scrolling through the chart
- Chart scrolls independently of the player panel

### Mood Snapshot (`mood-of-the-week.qmd`)
- Composite Mood Index (0–100) derived from valence, energy, danceability, and tempo
    - danceability: How easy the track is to dance to based on rhythm and beat (0 = not danceable, 1 = very danceable) 
    - energy: How intense and active the track feels (0 = calm, 1 = high energy) 
    - tempo: Speed of the track in beats per minute (BPM) 
    - valence: Emotional positivity of the track (0 = sad/dark, 1 = happy/uplifting) 
- KPI cards showing track-average and popularity-weighted scores
- Energy × Valence scatter plot with mood archetype coloring
- Valence and energy distribution histograms
- Archetype composition bar charts (track count + popularity-weighted share)
- Top 5 happiest, most energetic, and most melancholic tracks
- Song preview embed player

### About Me (`about.qmd`)
- Project background and data pipeline description
- Links to GitHub and LinkedIn

## How it works

- Uses the Spotify Web API with **Client Credentials** flow (no user login required)
- Fetches the Billboard Hot 100 Spotify playlist and writes JSON for OJS interactivity
- Cache-aware pipeline detects new chart entries and only fetches missing audio features
- Audio feature enrichment pulled from ReccoBeats, written to `data/hot100_enriched.rds` for mood analysis
- GitHub Actions workflow runs daily at 13:00 UTC, re-fetches chart data, re-renders, and deploys to GitHub Pages

## Repo Layout

```
spotify-dashboard/
├── README.md
├── _quarto.yml
├── about.qmd
├── custom.scss
├── dashboard.qmd
├── mood-of-the-week.qmd
├── mood-of-the-week.css
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

## Credits

Layout and styling inspiration from Melissa Van Bussel's Posit 2024 Table Contest dashboard:
- https://melissavanbussel.github.io/spotify-dashboard
- https://github.com/melissavanbussel/spotify-dashboard
