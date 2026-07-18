# Changelog

All notable changes to Roster are recorded here.

## [Unreleased]

## 2026-07-18

### Added
- **Simulator / training session cards** — ground-training events (`SIMU`, `ENTM3`, `OPSM3`, …) are now recognized and labelled ("Simulator Session"), and show the **participating crew** (trainees & instructor) in the same expandable crew panel as flights. The portal lists sim crews as `*** ELV ***` / `*** INS ***` sections without the `Crew:` header used on flights — the parser now detects those sections directly. New role labels: ELV → Trainee, INS → Instructor, INS-C, EXM.
- **Dedicated MEP (positioning) card for every leg** — all positioning legs now use the orange MEP card: 💺 deadhead-seat icon, "MEP · Positioning" heading, a "Positioning flight (mise en place)" note, a dashed route line, and the full times grid. Previously only MEP legs carrying a flight number (e.g. `MEP - SB410 - NOU/AKL - FONEA`) got that card; legs like `MEP - AKL/NAN` fell through to the generic purple card — which made a two-leg positioning day (16/08) look like the same MEP displayed twice in two different styles.
- **Nothing is ever dropped** — any description line the parser doesn't recognize is collected and displayed in a dim "extra info" block on the card (all card types), so new/unknown portal data is always visible to the crew member.

### Changed
- **REST events display like Hotel Rest** — same gold card with destination photo, duration and stopover tips, labelled "Rest" (e.g. the 24 h `REST - NAN` between the positioning and the sim block).
- Calendar-view chips follow the same rules: REST is gold like hotel rest, and all MEP legs are orange and labelled with their route when they have no flight number.

### Added
- **Cosmic-radiation dose (CARI-7)** — each flight now shows its galactic-cosmic-radiation **ICRP-103 effective dose** (µSv, the EASA/Euratom aircrew quantity), with **per-month and per-year totals** in the stats bar. Doses are computed **server-side** by a Python job (`/home/looping/cari7/cari.py`) that runs the FAA CARI-7 program over the flight plans (step-climb profile from the route's cruise levels, same method as the legacy `cari.inc.php`) and publishes a small JSON the app reads. A later monthly pass refreshes the finalized solar data (`MV-DATES`) and upgrades provisional doses to final.
- **Stopover tips** — crew-shared, categorized notes per stopover (Activities, Food & Drink, Getting Around, Money & Shopping, Hotel & Rest, Safety & Health, Other) on each hotel-rest card. Each tip has a **category, title and description**; URLs are auto-linked. Foldable per stopover (collapsed by default). A **give-to-get** gate: you only see others' tips once you've posted at least one; admins moderate any tip and authors edit/delete their own via an inline edit form. Stored server-side via **Apache WebDAV** (no server script), one shared pool per airline, with a daily backup.
- **Foldable flight-plan route** — the route line (label, enroute time, alternates) is shown collapsed; tap to expand the full token list.

### Changed
- **Flight-plan retrieval moved fully server-side.** A Python job fetches the provider feed hourly (accumulating/merging so a plan that briefly drops out of the volatile feed is never lost) and writes a static JSON the browser reads. The in-browser fetch, the settings panel, and all provider credentials were **removed from the frontend** — nothing sensitive ships to the browser.
- Timezone bar: when scrolled, the shrunk month/year fades in at the left and the timezone buttons **right-justify** (and tighten on mobile) so the year never overlays them, even with 5+ zones.
- Auto-scroll to today's duty now fires only on load / month change, not on background refreshes.

### Removed
- The same-origin Apache reverse proxy to the flight-plan provider (retrieval is now server-side).

## 2026-07-03

### Added
- **Flight Plan Routes** — fetches planned flight plans from an external provider in the background and shows the planned route above the crew list on matching flights (matched on flight number + origin + departure date). The route is colour-coded: SID, STAR, airways, waypoints, coordinates, speed/flight-level (`/N0481F380`) and DCT. Planned alternate(s) shown as chips, plus planned enroute time.
- Fetched flight plans are saved in browser storage (like the roster cache) and reloaded on open and offline. The plans are re-checked in the background whenever the page is loaded, refreshed, or re-displayed (tab focus, PWA/mobile resume, bf-cache back/forward, regained connectivity) — throttled to 90s and gated on configured credentials + connectivity.
- **Route in LogTen Pro export** — `flight_route` is included in the LogTen payload when a matching plan exists (single and bulk import).
- **Persistent event archive** — every event ever seen is kept per source in browser storage, so past months are never lost when the crew portal's rolling ICS window drops them. Seeded once from snapshot history so recently-dropped months can be recovered; the live API window stays authoritative so reschedules don't create duplicates.

### Changed
- `build.sh` now writes the served `index.html` (was `roster.built.html`) and injects the flight-plan credentials from `.env`.
- Settings gained a **Flight Plan Routes** panel with a single **Filter** field (the airline flight-number prefix); the proxy path lives in code. Auto-presets when a matching Alexis roster is detected.
- Timezone selector now wraps onto two lines when there are many destinations, instead of overflowing off-screen.

### Security
- Flight-plan login/password kept out of version control via `__PLACEHOLDER__` tokens in `roster.html`, real values in `.env` (gitignored), injected into `index.html` (gitignored) at build time.
- A same-origin Apache reverse proxy bypasses CORS; the browser's Basic-auth is forwarded to the provider and rejected there if missing/invalid. No credentials are stored server-side or in the Apache config.
- `.gitignore` now also excludes `index.html` and `roster.built.html`.

## 2026-05-19

### Added
- `README.md` describing the project purpose, features, usage, and tech stack
- `CHANGELOG.md` (this file) for tracking changes going forward

### Added
- `build.sh` — injects secrets from `.env` into `roster.html` → `roster.built.html`
- `.env.example` — template for required secrets
- `.gitignore` — excludes `.env` and `roster.built.html` from version control

### Security
- Removed hardcoded Pexels API key from source (`roster.html`); replaced with `__PEXELS_API_KEY__` placeholder
- Key lives in `.env` (gitignored) and is injected at build time via `build.sh`
