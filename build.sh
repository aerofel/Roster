#!/usr/bin/env bash
# Injects secrets from .env into roster.html → roster.built.html
set -euo pipefail

if [ ! -f .env ]; then
  echo "Error: .env not found. Copy .env.example and fill in your keys." >&2
  exit 1
fi

source .env

sed \
  -e "s|__PEXELS_API_KEY__|${PEXELS_API_KEY:-}|g" \
  -e "s|__JEPPESEN_USER__|${JEPPESEN_USER:-}|g" \
  -e "s|__JEPPESEN_PASS__|${JEPPESEN_PASS:-}|g" \
  roster.html > index.html
echo "Built index.html"
