# Changelog

All notable changes to Roster are recorded here.

## [Unreleased]

## 2026-10-26

### Fixed
- **Times one hour late after the end of summer time (e.g. SB501 CDG departure 20:30 shown as 21:30).** `AIRPORT_TZ` held one fixed UTC offset per airport (`CDG:2`, `LHR:1`, `LAX:-8`, `SYD:10`, `AKL:12`…), so the CDG/LHR/LAX/SYD/MEL/AKL displays were wrong for half the year. It now maps each airport to its IANA zone (`Europe/Paris`, …) and the offset is computed **for each event's own date** with the device's tz database (`Intl.DateTimeFormat`, memoized per 15 min). This also fixes day grouping, month filters, calendar days and the "today" marker around DST changes. The timezone buttons now select by label (offsets in their tooltip are those of mid-month); an old saved selection (`schedule_display_tz_lbl` = `CDG`, offset 2) is picked up automatically, nothing to reset on the phone.

### Added
- **`tools/tzcheck.py` — weekly timezone check** (cron `/etc/cron.d/roster-tzcheck`, Mondays 06:05 UTC, as `looping`). Mails `TZCHECK_MAILTO` when: a zone in `AIRPORT_TZ` is unknown; the server tzdata is older than the latest IANA release; a tzdata update changed the offsets/DST dates of one of our airports (18-month transition fingerprint kept in `~/.local/state/roster-tzcheck.json`); the Alexis feed's own `(HH:MM LOC)` times disagree with the zone; or the feed has a station missing from `AIRPORT_TZ`. Feed URLs come from `ROSTER_ICS_URLS` in `.env`. `--dry-run` prints without mailing or saving state.

## 2026-09-28

### Fixed
- **Aircraft registration missing in LogTen Pro exports.** `buildEntity()` hardcoded `flight_selectedAircraftID`/`flight_selectedAircraftType` to empty strings although the reg is in the ICS summary (`FLT - SB501 - CDG/BKK - FONET (RFT)`). It now sends the formatted reg (`F-ONET`, from the roster, else the matched flight plan) and the aircraft model, like the PilotLog/RB exports already did.
- **Logged flight time was ~1:30 too long.** All three exports used the Alexis `TFT` line as total/PIC/SIC time, but TFT runs from **check-in** to arrival (block + the 1:30 briefing + any delay). TFT is no longer exported; flight time is now the actual block time (in − out).

### Added
- **Scheduled + actual times in every logbook export.** Alexis publishes a single set of leg times: the schedule until the flight is flown, then it silently overwrites Departure/Arrival with the actual block times (Checkin is never updated). The app now remembers each flight's pre-departure times (per device, per roster source; back-filled once from saved snapshots) so exports carry **both** scheduled out/in and actual out/in. Each flight is classified as *scheduled* (not yet landed → scheduled times only, no flight time), *actual* (landed and the feed differs from the remembered schedule → both sets + block time) or *pending* (landed < 72 h ago but the feed still equals the schedule → Alexis hasn't published actuals; export asks for confirmation and sends scheduled times only — re-export later). Flights flown before this feature get their scheduled departure from the flight plan (or check-in + the station's briefing offset); their scheduled arrival stays blank. Night time is only exported for actual flights. The per-flight export button reads *Scheduled* / *Actuals pending* / *Block times* accordingly.

## 2026-09-05

### Fixed
- **iOS home-screen shortcut kept showing the old build.** The page was served with no `Cache-Control`, so Safari applied heuristic freshness (based on a months-old `Last-Modified`) and kept an old copy of the single-file app for weeks — offline viewing "worked" only by this accident. Apache now sends `Cache-Control: no-cache, must-revalidate` for `/roster/`, `index.html` and `sw.js` (ETag revalidation → cheap 304 when unchanged).

### Added
- **Service worker (`sw.js`, generated from `sw.template.js` by `build.sh`)** — real offline support for inflight use, without ever serving a stale build when online: the page and `data/flightplans.json` are **network-first** (4 s timeout, then the cached copy); Google Fonts and destination photos are cache-first; the roster ICS, CORS proxy, Pexels API and tips JSON are not intercepted (the app keeps its own localStorage caches; tips are PUT). `build.sh` stamps the build hash into the worker so each deploy installs a fresh worker and drops old caches. Registered with `updateViaCache:'none'` so Safari re-checks the worker on every open.
- Home-screen / tab icons (`icon.svg`, `apple-touch-icon.png`, `icon-512.png`) matching the new brand mark.

### Changed
- **New "Flight Deck" theme — complete visual redesign, no information removed.** Manrope for UI text and JetBrains Mono for every time, IATA code, flight number and figure (tabular numerals line up in columns). Glass-like layered cards on a deep navy ground with a soft aurora gradient; light theme is a proper white/paper variant (photos get a whitewash so text stays readable). Compact spacing throughout: the September list is ~30 % shorter on a phone and ~33 % shorter on desktop than before, without dropping a single field.
- **Timeline layout** — the list is now a vertical timeline: a sticky date node (day number in a circle, weekday) on the left with a hairline rail, the day's blocks on the right. Today's node is highlighted. On phones the node collapses into a compact sticky date row that stays visible under the timezone bar while you scroll that day's duties.
- **Exactly two block sizes.** Flights are the only large block; *everything else* — positioning (MEP, with or without a flight number), hotel rest, REST, days off, simulator/ground training, standby and unknown duties — uses one uniform compact "tile": tinted icon chip, kind label, title, one line of times, duration pill on the right. Extras (unrecognised description lines, crew panel, stopover tips) fold under the tile without changing its base height. MEP tiles keep the route (codes + city names), dep→arr, check-in/out and the UTC pair with day tags.
- **Flight block** — flight number + role tag + LIVE tag on the left, aircraft registration on the right; big IATA codes with a route line in between carrying the block duration and a plane pointing in the direction of travel. **While airborne the line fills from the origin to the aircraft's live position** (dep→arr from the duty times); completed flights show a solid line, scheduled ones a dotted line. The four duty times always sit on **one row of four cells** (even on phones): display-timezone time on top, UTC + UTC day tag below (single row in UTC mode); Departure/Arrival cells are emphasised, Check-in/out dimmed. Meta chips (crew on board, TFT, cosmic dose, night block) and the logbook export button on one row; flight-plan route and crew list fold below. Crew list is a 2-column grid on wide screens.
- **Stats** — a single glass strip instead of big boxes (wraps into a 3-up grid on phones so nothing hides behind a scroll); colour-coded values; view switcher gained a colour legend on desktop.
- **Calendar** — chips carry a colour dot + mono label, weekend columns tinted, today ringed; on phones chips become slim colour bars. Bottom-sheet event preview and disclaimer modal restyled to match. Header buttons, timezone bar, panels (sources / logbook import / history), status screens and change-diff rows all restyled in the same language.
- Emoji glyphs in UI chrome (stopover-tips toggle, flight-plan enroute clock) replaced with inline SVG so they render identically on every platform.

### Internal
- Rendering refactor: shared `legTimes()` / `timeStripHTML()` helpers replace the duplicated flight/MEP time-grid code; all non-flight cards go through one `tileHTML()` template; inline SVG icon set (`ICON`) replaces emoji/glyph icons. Past events use a `.past` class instead of inline opacity. All element ids/classes used by the JS (crew/tips/route toggles, photo loader, sticky month label, panels) are unchanged.
- Verified with headless Chromium at 390 / 820 / 1440 px, dark and light, list / calendar / modal / panels, UTC and NOU display modes, scheduled / live / completed flights.

## 2026-09-05

### Added
- **RB Logbook (CAE / RosterBuster) export** — third option in the logbook-app selector. RB Logbook's `rblogbook://` scheme carries no data (navigation-only), so export downloads a CSV using the exact column names of CAE's official `rb_logbook_flights-1.9` template (Date, Flight #, ICAO Departure/Arrival, Aircraft ID/Type, Sched Out/In vs actual Out/In in UTC, Total Block, PIC/SIC, Night, cockpit crew, route + cosmic dose as notes) for maximum auto-mapping in More › Import & Export › Import Logbooks. CSV serialization shared with the PilotLog export via a common `downloadCSV()` helper.
- **CrewLounge PilotLog export** — the import panel now has a logbook-app selector (LogTen Pro / PilotLog, remembered per device in `schedule_logbook_app`). With PilotLog selected, every import button produces a CSV in PilotLog's **native Import-Wizard format** (~24 columns incl. the mandatory `PILOTLOG_DATE`, `AF_DEP/AF_ARR` (ICAO), `TIME_TOTAL`, `AC_MODEL`, `AC_REG`) — share the downloaded file to the PILOTLOG app or upload it at My CrewLounge › Import. PilotLog exposes **no URL scheme** (unlike LogTen), so a file hand-off is the minimum-step path that exists; rows also carry scheduled vs actual UTC times, PIC/SIC times from your role, night time, crew (PILOT1–4), planned route, and the CARI-7 cosmic dose as a remark. Aircraft model/registration are filled from the matched flight plan (with a reg→model fallback across all known plans).
- **Monthly import button** — a second button in the import panel imports all flights of the **displayed month** in one tap (label shows month name + flight count, follows month navigation), complementing the existing from-date import. Works for both logbook apps.

### Changed
- Import plumbing unified: bulk, monthly and per-flight-card buttons all route through one `exportFlights()` dispatcher that opens LogTen Pro (`logtenprox://`) or downloads a PilotLog CSV according to the saved selection; the top-bar trigger and panel labels follow the selected app.

## 2026-07-25

### Added
- **"Today" button** in the month navigation — appears whenever you're viewing another month; one tap returns to the current month and scrolls to the next upcoming duty.
- **Keyboard month navigation** — ← / → arrow keys switch months on desktop (ignored while typing in a form or when the calendar modal is open).
- **Today highlight in list view** — the current day's date label is shown in blue with a "· Today" suffix, so it's easy to spot your place in the month.
- **Stale-roster auto-refresh** — returning to a tab whose roster cache is older than 1 hour now silently re-fetches the ICS (throttled to one attempt per 5 minutes), instead of showing outdated duties until a manual Refresh.
- **OS theme preference** — first visit now follows the system light/dark preference (`prefers-color-scheme`) instead of always starting light; a manual toggle still wins and is remembered.
- **`theme-color` meta** synced with the active theme, so mobile browser chrome matches the page background.
- **Reduced-motion support** — `prefers-reduced-motion` disables the LIVE pulse, card hover lift, photo fade and modal animations.
- **Accessibility labels** — aria-labels/tooltips on the icon-only month arrows and top-bar buttons (Refresh, LogTen Pro).

### Fixed
- **Undefined CSS variable `--bg3`** — the timezone-button hover, the source-code chip and the code input referenced a variable that was never defined, so they rendered with no background. Now use the existing `--surf2` token.
- **Invisible MEP/unknown dots in the mobile calendar** — on small screens calendar chips collapse to dots, but only FLT/HOT/OFF had solid dot colours; positioning (orange) and other duties (lavender) were nearly invisible. All five event types now get solid dots.

## 2026-07-18

### Added
- **Simulator / training session cards** — ground-training events (`SIMU`, `ENTM3`, `OPSM3`, …) are now recognized and labelled ("Simulator Session"), and show the **participating crew** (trainees & instructor) in the same expandable crew panel as flights. The portal lists sim crews as `*** ELV ***` / `*** INS ***` sections without the `Crew:` header used on flights — the parser now detects those sections directly. New role labels: ELV → Trainee, INS → Instructor, INS-C, EXM.
- **Dedicated MEP (positioning) card for every leg** — all positioning legs now use the orange MEP card: monochrome seat icon (matching the flight cards' plane glyph) in the header and in the middle of the standard gradient route line, "MEP · Positioning" heading, and the full times grid. Previously only MEP legs carrying a flight number (e.g. `MEP - SB410 - NOU/AKL - FONEA`) got that card; legs like `MEP - AKL/NAN` fell through to the generic purple card — which made a two-leg positioning day (16/08) look like the same MEP displayed twice in two different styles.
- **Nothing is ever dropped** — any description line the parser doesn't recognize is collected and displayed in a dim "extra info" block on the card (all card types), so new/unknown portal data is always visible to the crew member.

### Added (later same day)
- **Off Days stat** — the top stats bar now shows the month's total days off (green), counting every display-timezone day covered by `OFF` events (multi-day blocks included, clamped to the shown month).

### Changed
- **Calendar view: multi-day events fill every day they cover** — a 5-day `OFF` block, a 4-day hotel layover, or a flight crossing local midnight now shows a chip on each covered day (DTEND exclusive), not just its start day. The day map is built from all known events, so an event starting late in the previous month still fills the first days of the displayed month.
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
