#!/usr/bin/env bash
# roster.html → index.html (served) + sw.js. No secret is injected into the page:
# the Pexels key and Jeppesen login are used only by the server jobs in tools/.
set -euo pipefail
cd "$(dirname "$0")"

cp roster.html index.html
echo "Built index.html"

# Service worker: stamp the build hash so every deploy installs a fresh worker/cache.
BUILD=$(md5sum index.html | cut -c1-12)
sed -e "s|__BUILD__|${BUILD}|g" sw.template.js > sw.js
echo "Built sw.js (build ${BUILD})"
