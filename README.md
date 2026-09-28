# Roster

A personal crew schedule viewer built for crew members using the **Alexis** crew management portal. It reads the iCalendar (ICS) feed that Alexis exposes for each crew member, and presents your schedule in a richer, more readable format than the default portal view. It runs entirely in the browser — no server, no accounts, no data leaves your device.

> **What is Alexis?** Alexis is the crew web portal (at `alexis.[domainname]`) where crew members view their roster. It provides a personal ICS feed URL (found in the portal under your account settings) that this app subscribes to.

## What it does

Roster parses your crew ICS feed and presents your schedule with richer context than the default portal view:

- **Flight events** — departure/arrival times, crew assignments, aircraft type, total flight time
- **Hotel rest & rest periods, days off** — colour-coded cards; rest periods (`REST`) display like hotel rest, with destination photo, duration and stopover tips
- **Positioning (MEP)** — a dedicated deadhead card for every positioning leg, with or without a flight number: the same route display as flights but with a seat icon in place of the plane, plus the full check-in/departure/arrival times grid
- **Simulator & ground training** — sessions such as `SIMU`/`ENTM3`/`OPSM3` are labelled and show the participating trainees and instructors in the same expandable crew panel as flights
- **No information dropped** — description lines the parser doesn't recognize are still displayed on the card in an "extra info" block, so nothing from the portal is ever hidden
- **List view** — month-by-month chronological event cards
- **Monthly stats bar** — flights, block time, night block, duty days, days off, and cosmic dose totals at a glance
- **Calendar view** — traditional monthly grid with event indicators and modal preview; multi-day events (days off, layovers, rest) appear on every day they cover
- **Changes tracking** — snapshot history that highlights roster updates since your last check
- **Persistent history** — every event ever seen is kept in the browser, so past months are never lost when the portal's rolling feed drops them
- **Flight plan routes** — planned flight-plan routes (retrieved server-side) shown colour-coded (SID, STAR, airways, waypoints, speed/level) with alternates above the crew list on matching flights; foldable, collapsed by default
- **Cosmic-radiation dose** — per-flight galactic-cosmic-radiation **ICRP-103 effective dose** (the EASA/Euratom aircrew quantity), computed server-side with the FAA **CARI-7** program; shown as a badge on each flight plus **per-month and per-year totals**
- **Stopover tips** — crew-shared, categorized notes (activities, food, getting around, money…) on each hotel-rest card. Foldable; each tip has a category, title and description with auto-linked URLs. A give-to-get gate means you see others' tips once you've shared at least one; admins moderate
- **Timezone switching** — display times in UTC or your home base / destination timezone
- **Crew panel** — expandable list of crew members per flight (Captain, F/O, Flight Attendants, etc.)
- **Logbook export (LogTen Pro / CrewLounge PilotLog / RB Logbook)** — pick your logbook app once (remembered per device), then export per flight, per displayed month, or from any date. LogTen Pro opens directly via its `logtenprox://` URL scheme; PilotLog and RB Logbook (neither has a data-carrying URL scheme) get a CSV in their own native import format — share it to the PILOTLOG app / upload at My CrewLounge, or import it in RB Logbook under More › Import & Export. All include the planned route when available. Every export carries the aircraft registration/type and both **scheduled and actual block times**: the app remembers each flight's schedule before the crew portal overwrites it with actuals, and flight time is the actual block time (out → in), never the portal's TFT (which counts from check-in)
- **"Flight Deck" theme** — compact timeline layout (sticky date node + hairline rail), glass-like layered cards, Manrope UI text with JetBrains Mono for every time/code/figure. **Two block sizes only**: flights are the large block (route line that fills to the aircraft's live position while airborne, one-row four-cell time strip, meta chips, foldable route + crew); every other duty (MEP, hotel/REST, days off, sim, standby, unknown) is one uniform compact tile
- **Dark / Light theme** — follows the OS preference on first visit; manual toggle remembered
- **Offline / inflight** — a service worker keeps the last build of the page, the flight-plan data, fonts and destination photos; when online the page is always fetched fresh first (new builds appear on the next open, nothing stale), when offline the cached copy is served and the roster comes from the browser's local cache
- **Responsive** — phone, tablet and desktop layouts; the date row stays sticky on phones, the time strip never wraps
- **Quick navigation** — "Today" button when viewing another month, ← / → keyboard month switching, auto-refresh of a stale roster when returning to the tab

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
3. Open / deploy `index.html` together with the generated `sw.js` (the build stamps its hash into the worker so clients pick up every deploy).

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
sw.template.js     — service worker source (offline shell); build.sh → sw.js
icon.svg / apple-touch-icon.png / icon-512.png — app icons
.gitignore         — excludes .env, index.html, sw.js, roster.built.html
```
