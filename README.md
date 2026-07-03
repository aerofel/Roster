# Roster

A personal crew schedule viewer built for crew members using the **Alexis** crew management portal. It reads the iCalendar (ICS) feed that Alexis exposes for each crew member, and presents your schedule in a richer, more readable format than the default portal view. It runs entirely in the browser — no server, no accounts, no data leaves your device.

> **What is Alexis?** Alexis is the crew web portal (at `alexis.[domainname]`) where crew members view their roster. It provides a personal ICS feed URL (found in the portal under your account settings) that this app subscribes to.

## What it does

Roster parses your crew ICS feed and presents your schedule with richer context than the default portal view:

- **Flight events** — departure/arrival times, crew assignments, aircraft type, total flight time
- **Hotel rest, days off, positioning, and ground activities** — all parsed and color-coded
- **List view** — month-by-month chronological event cards
- **Calendar view** — traditional monthly grid with event indicators and modal preview
- **Changes tracking** — snapshot history that highlights roster updates since your last check
- **Persistent history** — every event ever seen is kept in the browser, so past months are never lost when the portal's rolling feed drops them
- **Flight plan routes** — optionally fetches planned flight-plan routes from an external provider and shows the colour-coded route (SID, STAR, airways, waypoints, speed/level) with alternates above the crew list on matching flights
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

### Flight plan routes (optional)

Routes come from an external flight-plan provider whose feed is cross-origin, so it's reached through a **same-origin reverse proxy** to avoid CORS. The app calls a same-origin path (e.g. `/roster/api/fp/…?filter=<FILTER>`), and the web server forwards that to the provider's endpoint. The browser sends the provider login as HTTP Basic auth, which the proxy passes straight through — invalid/missing credentials are rejected upstream, and **no credentials are stored on the server**.

Example Apache (`mod_proxy` + `mod_headers`) config, added to the vhost that serves the app:

```apache
SSLProxyEngine on
ProxyPass        /roster/api/fp/ https://<provider-host>/<provider-path>/ nocanon
ProxyPassReverse /roster/api/fp/ https://<provider-host>/<provider-path>/
```

Set the **Filter** (your airline's flight-number prefix, e.g. `XXX%`) and login in the app's **Flight Plan Routes** settings panel; it auto-presets when a matching roster is detected. Fetched plans are cached in the browser and re-checked in the background whenever the page is loaded, refreshed, or re-displayed.

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
