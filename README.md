# Billboard Hot 100 (Spotify Dashboard)

A small Quarto dashboard that pulls tracks from Spotify’s “Billboard Hot 100” playlist and displays them in a table with album art + Spotify popularity, plus a track embed on the right.

## What it shows
- Playlist tracks (name, artist, duration)
- Spotify popularity (0–100) as a bubble
- Track embed player (Spotify iframe)

## How it works (quick)
- Uses the Spotify Web API with **Client Credentials** (no user login).
- Fetches the playlist + tracks.
- Writes the track data to `hot100_ojs.json` so the Observable JS dropdown can drive the embed.

Future features:
Add a visual displaying how long a song has been on the hot 100.


Credits:

Layout and styling inspiration from Melissa Van Bussel’s Posit 2024 Table Contest dashboard + tutorial:
https://melissavanbussel.github.io/spotify-dashboard
https://github.com/melissavanbussel/spotify-dashboard
