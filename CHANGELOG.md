# Changelog

All notable changes to Roster are recorded here.

## [Unreleased]

## 2026-11-01 — iPhone keyboard over the shared flight forms

### Fixed
- **Takeoff/landing times and approach/runway forms hidden by the iPhone keyboard.** Safari didn't scroll them into view, so crews had to scroll by hand to see what they typed. Now the page scrolls by itself so the open form sits between the sticky bars at the top (time-zone bar, plus the date row on phones) and the keyboard. It does this when the form opens, when a field gets focus, and again once the keyboard has slid in (`visualViewport` resize). It only scrolls when the form is actually covered. `fdReveal()` / `fdRevealSoon()`. Tested at 390 px with the visible area cut to 500 px: the whole form, Save button included, ends 10 px above the keyboard edge and starts below the date row.

## 2026-11-01 — security audit fixes

No change for users: same app, no login, no password.

### Security (app)
- **Stored XSS through the shared tips file (critical).** Anyone can PUT the tips file, and a tip's `id` went raw into an `onclick`. A crafted id ran code in every crew member's browser on page load, without a click, with access to all stored roster links and passports. Tips are now validated on load (`tipsClean`: id `t_[a-z0-9]`, known category, string fields cut to their limits, crew code `[A-Z0-9]{1,8}`). Malformed entries are dropped, and the next save writes the cleaned file back.
- **XSS through roster-feed values.** A hotel city like `x')">…` broke out of the tips handlers. `esc()` now escapes `'`. The new `jsq()` (JS escaping, then HTML escaping) is used for every data value in an inline handler: tips, expiries, calendar warnings, sources, timezone buttons, landings stepper and recent runways. The tips card id is letters and digits only (`tipCid`).
- **A broken shared file no longer blanks the app.** Tips and flight-data files that aren't objects (`[1,2,null]`, `{"CDG":{"tips":"x"}}`…) read as empty. A corrupt flight file is rewritten on the next save instead of blocking it.
- **Roster link no longer sent to corsproxy.io** for the Aircalin portal. The app now tries direct → our relay `/roster/ics` → corsproxy.io (only when the relay answers 404/403, i.e. isn't deployed, or for other portals).
- **Pexels key removed from the page.** The browser Pexels lookup is gone; photos come only from the server cache, which already covers every airport in `AIRPORTS`. `build.sh` no longer injects anything, and its dead Jeppesen lines are gone.
- **CSV export**: cells starting with `= + @`, tab or a non-numeric `-` get a leading `'`, so a spreadsheet won't run them as formulas. **LogTen link**: `% # & + ?` in the package are percent-encoded.
- Service worker: the runtime cache (photos, fonts) is capped at 400 entries.
- Tested in headless Chromium with a hostile tips file and a hostile feed. The old build ran the injected code from both (tip id and city); the new one ran none and showed the hostile text as text. Add / edit / delete tip, timezone switch, relay and fallback all work, with no CSP violation under the new policy.

### Security (server) — `tools/harden-20261101.sh`, run once as root
- Tips file names are `tips_[a-z0-9-]{1,40}.json`: no dots, so `tips_x.var.json` can't become an Apache type-map serving HTML on looping.org. `RemoveHandler .var` for the roster too.
- WebDAV folders: `Content-Security-Policy: default-src 'none'; sandbox` + nosniff. Tips uploads are capped at 1 MB.
- App page: CSP, HSTS, Referrer-Policy. `*.md`, `tools/`, `build.sh`, `sw.template.js`, `roster.html` and `.env*` are no longer served.
- Port 80: any Host (bare IP included) now redirects to HTTPS. Before, `http://<ip>/roster/data/…` served the flight plans with no gate.
- ICS relay: `ProxyPass` to the Aircalin portal only, GET only, app requests only, cookies stripped, not logged.
- Backups copy a file only when it changed. A daily mail goes out if tips + flights + sync pass 200 MB.
- Stale `*.bak` vhosts moved out of `sites-enabled/` (Apache was loading them).
- `cari.py` is owned by root. A second script (`tools/harden-cari-20261101.sh`) moves the CARI-7 binary to a root-only `cari7/bin/` and the lock file to `cari7/run/`, and makes `cari7/` no longer group-writable, so the web user (every PHP site) can't change code that `looping` runs. Sticky folders were tried first and dropped: with `fs.protected_regular=2` they block appending to the logs (the first script's self-test caught this and reverted it).
- The first server script also rolled back once by itself: Apache checks upstream certificate chains only one level deep by default (`SSLProxyVerifyDepth 1`), and the portal's chain has an intermediate. Fixed with `SSLProxyVerifyDepth 5`. Verified live: the relay returns the real feed (47 events, HTTP 200). The Jeppesen login moved to `cari7/jeppesen.env`. The roster `.env` is now `600`, so www-data no longer reads the feed URLs.

## 2026-10-30

### Added (server photo cache)
- **`tools/photos.py`** (stdlib) downloads the destination photos once into `roster/photos/<IATA>/<id>.jpg` and writes `photos/index.json` (file, photographer, Pexels page). Cities = `AIRPORTS` + `PEXELS_QUERIES` + every station in the crew feeds known to `AIRPORT_TZ`. For variety it targets **80 photos per city** from six searches (base query, then landmark, street, night, nature, aerial view), de-duplicated, refreshed every 90 days. A 429 stops the run and the next one resumes. It runs hourly from the `looping` user's crontab (`17 * * * *`, log `~/.local/state/roster-photos.log`); once every city is complete it makes no API call. First run: 8 cities × 24 photos (28 MB) before the quota ran out.
- **App reads the server cache first**: `photos/index.json` (kept in localStorage for offline), images same-origin and cache-first in the service worker. **Each card of the same city gets a different photo**: a per-city, per-month offset, then stride 7 through the set in card order, stable across re-renders. On your real October roster that's 9 tiles, 9 different photos, 0 Pexels calls. The browser Pexels lookup stays only as a fallback for a city the server doesn't have, and only after the index has loaded.

### Changed (route label)
- Flight cards: "Flight plan route" → **"Route"**.

### Fixed (photos)
- **Destination photos sometimes missing.** Every render called the Pexels search API again for every photo card, with a random page. Every user shares one key capped at 200 requests/hour, and renders are now frequent (sync, shared flight data, typing), so the key hit **HTTP 429** and photos stopped loading (confirmed live). Now each browser asks once per city and keeps the 15 results for 30 days (`schedule_photos_v2`). Each card picks a stable photo from that list (by city + date), so the photo no longer changes on every render. A known photo is set inline at render time, so there's no blank flash. A 429 backs off for 1 hour, and requests for the same city are de-duplicated. Images are preloaded and only fade in once loaded; a broken image URL falls back to the next one. Tested with a stubbed Pexels: 24 renders = 1 API call, reload = 0.

### Changed (flight meta)
- Crew summary line ("Captain Frank · First Officer Vaea · Relief Crew Philippe"): roles are now small caps labels in a dim colour and first names are bold in the text colour. **Your own name is in the card's accent colour.** Dots are dim separators and "+n" is a small mono badge. Names are now HTML-escaped (they weren't before).
- Flight cards: the crew-count chip shows just the people icon and the figure (`3/0`); the redundant word "crew" is gone. The tooltip still says "Crew on board".

### Changed (History export)
- **History › "Export all data" is now a full backup (format v2)**: `roster-<code>-<date>.json`. It holds a readable `flights` list (date, flight, ICAO airports, role, aircraft/type, status, scheduled out/in, out, takeoff, landing, in, block, night, PF, approach, runway, route, cosmic dose, crew), `simSessions` with landing counts, `expiries`, and the raw `stores` for a lossless re-import (snapshots, event archive, scheduled times, PF/landings, expiries, shared flight-data records for your flights, fetched fresh before export). The ICS link is never included.
- **Import** reads v1 and v2 files and merges everything: snapshots by timestamp, archive by event key, scheduled times only where missing, PF/landings and expiries newest-wins (then synced to your devices), and shared takeoff/landing/approach only for fields nobody has filled yet (then uploaded). It reports what came back. The History panel stats now also count flights, PF/sim entries and expiries.

### Changed (photos)
- **Days off (OFF) and JD tiles now get the destination photo background** like hotel rest: the same Pexels city photo, fade and gradient, fetched only when online.

### Changed (later)
- LogTen export of `RFT` sectors: the pilot's own name now goes in the **Relief** crew slot (`flight_selectedCrewRelief`) instead of Observer. PIC/SIC stay unticked at `0:00`. PilotLog still sends capacity `OBS`.

### Added
- **Takeoff & landing times, shared by the crew.** A blue **T/O · LDG** chip sits left of the export button on every flown or live sector (pilots only). It opens an editor with two large numeric fields. You type 4 digits ("0942"), the colon is added for you, a complete takeoff jumps straight to landing, and Enter saves. Quick buttons fill off-block +5/+10/+15 and on-block −3/−5/−8, with the block times shown as reference. Times are always typed, shown and stored in **UTC**, whatever time zone the roster is displaying. Validation: takeoff not before off-block, landing not after on-block (2 min tolerance), landing after takeoff. iOS opens the number pad (`inputmode=numeric`) and shows Next/Done. The draft and caret survive background re-renders.
- **Approach + runway on the flight-plan route line.** An **Approach** chip opens a type grid (ILS, RNP, RNP AR, LOC, VOR, NDB, GLS, LPV, RNAV, VISUAL), a 2-digit runway field and L/C/R toggles, plus one-tap "Recent" runways already logged at that airport. Flights without a flight plan get a compact "Arrival XXX" row instead. Values are stored in capitals.
- **Apache `/roster/flights` (vhost `00b-looping.org-ssl`)**: WebDAV GET/HEAD/PUT only, gated like `data/` (same-origin or `/roster/` Referer), `noindex`, `no-store`, strong ETags, whitelisted `flt_<company>_<YYYY-MM>.json`, script-extension deny, 512 KB cap. Daily backup in `/etc/cron.d/roster-tips`, 30 days kept. Vhost backup: `/root/00b-looping.org-ssl.bak-rosterflights-20261030`.
- **Shared storage `/roster/flights/flt_<company>_<YYYY-MM>.json`** (script-less WebDAV like the tips), keyed `FLIGHT_FROMTO_<UTC sched-dep date>`, so whatever one pilot enters shows for everyone on the flight. It holds operational data only (no names or crew codes). Edits apply locally at once and are queued (`schedule_fltdata_queue_<company>`). Each flush GETs the freshest file and patches only the edited fields before the PUT, and queued edits retry on reload and when back online. Records read from the file are sanitized before use.
- **Exports**: LogTen `flight_takeoffTime` / `flight_landingTime` and `flight_selectedApproach1` = `1;ILS;11R;NZAA` (LogTen's count;type;runway;place). PilotLog `TIME_TO`, `TIME_LDG`, `APP_1`, `RWY_ARR`. RB Logbook `Off` / `On` plus the approach in `Notes3` (`Off`/`On` column names unverified against CAE's template). All in capitals.

### Changed
- Flight export button: "Block times" → **"Actuals"** once actual times are in (the other states, "Scheduled" and "Actuals pending", are unchanged).

### Added
- **Expiries tab (4th view: List / Calendar / Changes / Expiries).** Track Medical (date), Type ratings (type + date, any number), Passports (number + date, any number) and Instructor ratings (type + date). Add with a kind picker (icon tiles), edit or delete by tapping a card. The list is sorted soonest first and coloured with the same levels as the landing currency (green ≥ 30 days, yellow < 30, orange < 10, red once expired). It shows days left under ~100 days, then months, then years. The tab gets a coloured dot when something is due within 30 days. Cabin crew see only Medical and Passport.
- **Expiry banners + bottom dock.** On the expiry date, the list shows a banner styled like the 90-day one, with its own icon (medical cross, rating medal, passport, mortarboard), "Valid until dd/mm/yyyy", the days-left box and an Edit link. The calendar day is outlined in the level colour. The single currency pill became a **dock**: one pill per warning whose banner is off screen. The landing currency always gets one; expiries get one from 30 days before. The 2 most urgent show, the rest fold into "+n more · Expiries", and tapping a pill jumps to its banner. Passport numbers are masked to the last 4 digits on banners and pills. The dock is hidden on the Expiries tab.
- **Expiries are stored and synced like the PF ticks**: `schedule_expiries_<source>` = `{ id: { k, a, d, t } }`, with deletions kept as `{ del:1, t }`. They travel in the same end-to-end encrypted blob (`expiries` next to `landings`) with a newest-wins merge per item. A device still on the old build re-uploads without `expiries`, and the next new-build sync pushes them back. Sync now runs for cabin crew too, since they can store expiries.
- **Pilot or cabin crew, detected from the feed.** Each flight's summary names the owner's own role (`… (F/O)`). Pilot codes (`CPT…`, `F/O`, `RFT`, `CDB`, `OPL`) and cabin codes (`SFP`, `F/P`, `HST`, `CCP`, `CCA`, `PNC`…) decide directly. Any other code is placed by where the owner's seat group sits in the crew list (cockpit groups always come before cabin ones). The majority over all flights in the history wins, and with no flights yet the pilot features stay. Cabin crew get no PF button, no sim landings counter, no 90-day banner or pill, and no sync request.
- **RFT (relief pilot) flights export as Observer.** LogTen Pro: the owner's name goes in the `flight_selectedCrewObserver` slot, PIC/SIC capacity false and PIC/SIC time `0:00` so Typical-Role auto-fill doesn't add SIC time. PilotLog: new `CAPACITY` column = `OBS` (imported as DH, no function time). RB Logbook has no observer field, so PIC/SIC simply stay empty, as before.

### Fixed
- LogTen export: total time was sent as `flight_TotalTime`, but the API key is `flight_totalTime` (Coradine logten-api appendix). `flight_picCapacity` / `flight_sicCapacity` are Booleans in the API and are now sent as `true`/`false` instead of the block time string.
- Owner crew-code detection (`computeMyCode`) now weights the seat named in the summary's own role ×10, so a regular crewmate appearing as often as the owner can't be picked by mistake.
- **PF / landings sync across devices, end-to-end encrypted, no passphrase.** The encryption key and the file name are derived separately (HKDF-SHA-256) in the browser from the roster's own ICS URL (host + `hash=` token, 128-bit), plus a fixed app value, so every device holding the same URL reaches the same file with no setup. Data is encrypted with AES-GCM; the file name is bound in as additional authenticated data. The server stores only `roster/sync/s_<64 hex>.bin` blobs, with no name, crew code or URL, and can't read them. Merge is per leg, newest change wins. A removed tick is kept as a tombstone (`n: 0`) so the removal syncs too. Every sync is GET → merge → PUT, and any device that still holds a newer entry re-pushes it, so devices editing at the same time converge. Sync runs after each roster load, 1.5 s after a tick, and on tab return, focus or coming back online (throttled to every 30 s). Status ("Synced hh:mm" / "Sync pending" / "Not synced") is shown in the currency banner. Local format changed from `{legId: n}` to `{legId: {n, t}}`; old values are read transparently.
- **Apache `/roster/sync` (vhost `00b-looping.org-ssl`)** — script-less WebDAV like `/roster/tips`: GET/HEAD/PUT only, whitelist `s_<64 hex>.bin` (bare directory denied, nothing to list), separate script-extension deny, `LimitRequestBody 65536`, `Cache-Control: no-store`, strong ETags. Backup of the previous vhost: `/root/00b-looping.org-ssl.bak-rostersync-20261030`. Directory `roster/sync/` owned by www-data, setgid.

- **`/roster/data/` is now app-only and not indexed** (Apache, `00b-looping.org-ssl`; backup `/root/00b-looping.org-ssl.bak-rosterdata-20261030`). `flightplans.json` is served only to the app's own requests (`Sec-Fetch-Site: same-origin`, or a `https://(www.)looping.org/roster/` Referer for browsers without Fetch Metadata). Typing the URL, curl and hot-linking from other sites get 403. `X-Robots-Tag: noindex, nofollow, noarchive` is sent on every response. This is obscurity, not access control: the headers can be forged. Verified live: the app loads it on first visit and through the service worker.

### Changed
- **Currency banner shows the next limits.** "Limit dd/mm/yyyy · 3 landings in 90 days" is replaced by what the next PF landings would give: "Next **14/12** then **30/12**" (2nd and 3rd most recent landings + 90 days, i.e. the limit after 1 and after 2 more PF landings). A duplicate is shown once (landings on the same day, or a date equal to the current limit). If all three landings are on one day: "Limit moves after 3 new PF landings".
- Banner title, bottom pill and calendar tooltip read "90 days from **dd/mm**" (no year).
- Simulator **− n +** stepper resized to match the other pills (22 px buttons, 12 px count, tile-kind-style label) instead of 30 px buttons.

### Fixed
- **Editing a tip didn't save the new title or text when the same city appeared on two stopover cards in the month** (e.g. BKK outbound and inbound). The inline editor was drawn on every card showing that city's tips, and its inputs were named only after the tip (`tipetitle_<tipId>`). `tipSaveEdit` therefore read the first form on the page, the one inside the other, collapsed card, which still held the old values. The save went through (the tip got an "edited" stamp) but with unchanged content. Now the editor opens only on the card where Edit was tapped (`tipEditingCid`) and its ids include the card (`<cid>_<tipId>`), like the add-tip form already did. Reproduced with Playwright on the old build (2 forms, hidden first one) and verified on the new one (1 form, new title saved).
- **Daily tips backups were deleted as soon as they were made.** `/etc/cron.d/roster-tips` copied with `cp -p`, which keeps the live file's modification date (unchanged since 18 Sep). The `find -mtime +30 -delete` prune on the same line then removed the fresh copy, so `tips/.backups/` stayed empty. Now a plain `cp` (old cron saved as `/root/cron.roster-tips.bak-20261030`). Verified by running the line as www-data: today's copy is kept and identical to the live file.
- The bottom currency pill could flash over a visible banner until the IntersectionObserver fired; its initial state is now set synchronously.

## 2026-10-28

### Added
- **Pilot-flying landing currency (3 landings in 90 days).** Every flight card has a **PF** button (green "Pilot flying" when on); a ticked sector counts as one landing at its arrival time. Simulator sessions (`SIMU`/`ENTM`/`OPSM`/`LOFT`/`OPC`/`LPC`/`UPRT`/`ATQP`) get a **− n +** landings stepper. The limit is the 3rd most recent landing + 90 days. Planned (future) PF sectors and sims count, but only when they fall before the running limit, so a gap of more than 90 days still shows as a lapse. A banner reading **"90 days from dd/mm/yyyy"** (the 3rd most recent landing), with the limit date, a days-left counter and chips for the three landings that count, sits on the limit date in the list view, with its own day node even on a day without duties. Colours: green ≥ 30 days, yellow 10–29, orange 0–9 (pulsing), red when expired ("n days ago"). In the calendar the limit day is outlined in the same colour. A bottom pill shows the currency whenever the banner is off screen (another month, calendar view, scrolled away); tap it to jump to the banner. If fewer than 3 landings are recorded, the pill shows "n/3 landings recorded". Stored in localStorage per roster source (`schedule_landings_<source>`, keyed by `legId()`, so aircraft swaps keep the tick).
- **PF in logbook exports.** LogTen Pro `flight_pilotFlyingCapacity` (was always `false`), PilotLog `PF` column (`PF` when ticked, blank otherwise, per CrewLounge import article 24000034487), RB Logbook `PF` column (`Yes` when ticked; not in CAE's template, so map it once in the importer if it isn't picked up).

## 2026-10-26 (2)

### Changed
- **Sticky timezone bar after scrolling past the month title** — now one line: `Month Year` + **‹ Today ›** month buttons on the left (Today only when another month is shown), timezone buttons right-justified. When there are too many buttons the line no longer wraps: swipe it sideways to reach the hidden ones; any vertical page scroll (> 8 px) slides it back to the left so the month is visible again. The bar's ‹ › land at the top of the new month (current month in list view: the usual auto-scroll to today's duty). At the top of the page the bar is unchanged (centered buttons, no label).

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
