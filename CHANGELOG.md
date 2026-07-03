# Changelog

All notable changes to Roster are recorded here.

## [Unreleased]

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
