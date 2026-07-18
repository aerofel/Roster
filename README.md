# Roster

A personal crew schedule viewer built for crew members using the **Alexis** crew management portal. It reads the iCalendar (ICS) feed that Alexis exposes for each crew member, and presents your schedule in a richer, more readable format than the default portal view. It runs entirely in the browser — no server, no accounts, no data leaves your device.

> **What is Alexis?** Alexis is the crew web portal (at `alexis.[domainname]`) where crew members view their roster. It provides a personal ICS feed URL (found in the portal under your account settings) that this app subscribes to.

## What it does

Roster parses your crew ICS feed and presents your schedule with richer context than the default portal view:

- **Flight events** — departure/arrival times, crew assignments, aircraft type, total flight time
- **Hotel rest & rest periods, days off** — colour-coded cards; rest periods (`REST`) display like hotel rest, with destination photo, duration and stopover tips
- **Positioning (MEP)** — a dedicated deadhead card (💺 icon, dashed route line, "mise en place" note) for every positioning leg, with or without a flight number, including the full check-in/departure/arrival times grid
- **Simulator & ground training** — sessions such as `SIMU`/`ENTM3`/`OPSM3` are labelled and show the participating trainees and instructors in the same expandable crew panel as flights
- **No information dropped** — description lines the parser doesn't recognize are still displayed on the card in an "extra info" block, so nothing from the portal is ever hidden
- **List view** — month-by-month chronological event cards
- **Calendar view** — traditional monthly grid with event indicators and modal preview
- **Changes tracking** — snapshot history that highlights roster updates since your last check
- **Persistent history** — every event ever seen is kept in the browser, so past months are never lost when the portal's rolling feed drops them
- **Flight plan routes** — planned flight-plan routes (retrieved server-side) shown colour-coded (SID, STAR, airways, waypoints, speed/level) with alternates above the crew list on matching flights; foldable, collapsed by default
- **Cosmic-radiation dose** — per-flight galactic-cosmic-radiation **ICRP-103 effective dose** (the EASA/Euratom aircrew quantity), computed server-side with the FAA **CARI-7** program; shown as a badge on each flight plus **per-month and per-year totals**
- **Stopover tips** — crew-shared, categorized notes (activities, food, getting around, money…) on each hotel-rest card. Foldable; each tip has a category, title and description with auto-linked URLs. A give-to-get gate means you see others' tips once you've shared at least one; admins moderate
- **Timezone switching** — display times in UTC or your home base / destination timezone
- **Crew panel** — expandable list of crew members per flight (Captain, F/O, Flight Attendants, etc.)
- **LogTen Pro export** — one-click flight log export (includes the planned route when available)
- **Dark / Light theme**
- **Mobile-friendly** responsive layout

## How to use

### Without background photos

1. Open `roster.html` in any modern browser — no build step needed.
2. On first launch, enter your ICS feed URL in the URL panel. Your personal ICS link is available in the Alexis portal under your account — it looks like `https://alexis.[domainname]/crew-web/ics?trig=AIR&…`.
3. The app caches the feed locally; use the refresh button to pull updates.

### Build (Pexels photos + flight-plan credentials)

1. Copy `.env.example` to `.env` and fill in the values you want (an optional
   [Pexels API key](https://www.pexels.com/api/) for background photos, and the
   optional flight-plan provider login — see `.env.example` for the variable names).
2. Run `./build.sh` — it injects the values from `.env` into `roster.html` and writes `index.html` (the served file).
3. Open / deploy `index.html`.

Secrets never live in tracked source: `roster.html` carries only `__PLACEHOLDER__` tokens, and both `.env` and the generated `index.html` are gitignored.

All data is stored in browser LocalStorage — nothing is sent to any external server beyond fetching your ICS feed (with a CORS proxy fallback if needed), the optional flight-plan feed, and the optional Pexels photo API.

## Optional server-side helpers

The core app runs in the browser. Three optional features are prepared by small server-side
helpers (outside this repo) so that no provider credentials ever reach the browser:

### Flight plan routes + cosmic-radiation dose

A stdlib-only Python job (`cari.py`) fetches the flight-plan provider feed **hourly** using
credentials in `.env`, accumulates the plans (so an entry that briefly drops out of the provider's
rolling window is never lost), runs the FAA **CARI-7** program to compute each flight's ICRP-103
effective dose, and writes a static `data/flightplans.json` the app reads. A monthly pass refreshes
the finalized solar-modulation data and upgrades provisional doses to final. The browser only reads
the JSON — the in-browser fetch and the old same-origin reverse proxy were removed.

### Stopover tips

Tips are stored as JSON under `/<app>/tips/` served by **Apache WebDAV** (`mod_dav`) — the browser
`GET`/`PUT`s the file directly, no server script. The location allows only `GET`/`PUT` (no
`DELETE`/`PROPFIND`) and isn't listed; a daily cron backs the files up. One shared pool per airline
(keyed by company). All access rules (the give-to-get view gate, admin moderation) are enforced in
the app UI.

```apache
DavLockDB /var/lib/apache2/dav/lockdb
<Location /roster/tips>
    Dav On
    Options -Indexes
    <Limit GET HEAD OPTIONS PUT>   Require all granted </Limit>
    <LimitExcept GET HEAD OPTIONS PUT> Require all denied </LimitExcept>
</Location>
```

## Tech stack

| Layer | Choice |
|-------|--------|
| Runtime | Vanilla JS (ES6+), HTML5, CSS3 |
| Data | ICS / iCalendar parsing |
| Storage | Browser LocalStorage |
| Dependencies | None — single self-contained HTML file |

## Files

```
roster.html        — source application (~2 700 lines of HTML/CSS/JS)
build.sh           — injects secrets from .env → index.html
.env.example       — template for required secrets
.gitignore         — excludes .env, index.html, roster.built.html
```
