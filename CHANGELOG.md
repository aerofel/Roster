# Changelog

All notable changes to Roster are recorded here.

## [Unreleased]

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
