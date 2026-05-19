# Roster

A personal crew schedule viewer that fetches and displays ICS calendar feeds from a crew roster portal in an enhanced, user-friendly format. It runs entirely in the browser — no server, no accounts, no data leaves your device.

## What it does

Roster parses your crew ICS feed and presents your schedule with richer context than the default portal view:

- **Flight events** — departure/arrival times, crew assignments, aircraft type, total flight time
- **Hotel rest, days off, positioning, and ground activities** — all parsed and color-coded
- **List view** — month-by-month chronological event cards
- **Calendar view** — traditional monthly grid with event indicators and modal preview
- **Changes tracking** — snapshot history that highlights roster updates since your last check
- **Timezone switching** — display times in UTC or your home base / destination timezone
- **Crew panel** — expandable list of crew members per flight (Captain, F/O, Flight Attendants, etc.)
- **LogTen Pro export** — one-click flight log export
- **Dark / Light theme**
- **Mobile-friendly** responsive layout

## How to use

### Without background photos

1. Open `roster.html` in any modern browser — no build step needed.
2. On first launch, enter your ICS feed URL in the URL panel.
3. The app caches the feed locally; use the refresh button to pull updates.

### With Pexels background photos (optional)

1. Copy `.env.example` to `.env` and add your [Pexels API key](https://www.pexels.com/api/).
2. Run `./build.sh` — it injects the key and writes `roster.built.html`.
3. Open `roster.built.html` in your browser.

All data is stored in browser LocalStorage — nothing is sent to any external server beyond fetching your ICS feed (with a CORS proxy fallback if needed) and the optional Pexels photo API.

## Tech stack

| Layer | Choice |
|-------|--------|
| Runtime | Vanilla JS (ES6+), HTML5, CSS3 |
| Data | ICS / iCalendar parsing |
| Storage | Browser LocalStorage |
| Dependencies | None — single self-contained HTML file |

## Files

```
roster.html        — source application (~2 600 lines of HTML/CSS/JS)
build.sh           — injects secrets from .env → roster.built.html
.env.example       — template for required secrets
.gitignore         — excludes .env and roster.built.html
```
