/* Roster service worker — offline shell + always-fresh-when-online.
 *
 * Strategy
 *   page (/roster/) + data/flightplans.json : NETWORK-FIRST with a short timeout.
 *       Online  → the freshest copy is fetched and the cache updated, so a new build
 *                 (new CSS/JS) shows up on the very next open — no stale-cache problem.
 *       Offline / slow → the last cached copy is served (inflight use).
 *   Google Fonts + destination photos (Pexels CDN and our photos/ cache) : CACHE-FIRST.
 *   Roster ICS (relay or CORS proxy), tips, flight data : not intercepted (the app has
 *                                              its own localStorage caches and PUTs).
 *
 * `__BUILD__` is replaced by build.sh with a hash of index.html, so every deploy
 * installs a new worker and starts a fresh cache (old ones are deleted on activate).
 */
const BUILD     = '__BUILD__';
const SHELL     = 'roster-shell-' + BUILD;
const RUNTIME   = 'roster-runtime-v1';
const SHELL_URL = new URL('./', self.location).href;          // /roster/
const DATA_URL  = new URL('data/flightplans.json', self.location).href;
const NET_TIMEOUT_MS = 4000;

const CACHE_FIRST_HOSTS = ['fonts.googleapis.com', 'fonts.gstatic.com', 'images.pexels.com'];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(SHELL)
      .then(function (c) { return c.addAll([SHELL_URL, DATA_URL]); })
      .catch(function () { /* offline at install time: runtime fetches will fill the cache */ })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (k) {
        if (k !== SHELL && k !== RUNTIME) return caches.delete(k);
      }));
    }).then(function () { return self.clients.claim(); })
  );
});

// fetch() that gives up after `ms` so a dead inflight Wi-Fi doesn't hang the app.
function fetchWithTimeout(req, ms) {
  return new Promise(function (resolve, reject) {
    var t = setTimeout(function () { reject(new Error('timeout')); }, ms);
    fetch(req).then(function (r) { clearTimeout(t); resolve(r); },
                    function (e) { clearTimeout(t); reject(e); });
  });
}

function networkFirst(req, cacheKey) {
  return fetchWithTimeout(req, NET_TIMEOUT_MS).then(function (res) {
    if (res && res.ok) {
      var copy = res.clone();
      caches.open(SHELL).then(function (c) { c.put(cacheKey, copy); });
    }
    return res;
  }).catch(function () {
    return caches.match(cacheKey).then(function (hit) {
      if (hit) return hit;
      return new Response('Offline and no cached copy yet.', { status: 503, headers: { 'Content-Type': 'text/plain' } });
    });
  });
}

// Photos and fonts pile up over months: keep the newest RUNTIME_MAX entries.
var RUNTIME_MAX = 400;
function trimRuntime(c) {
  return c.keys().then(function (keys) {
    return Promise.all(keys.slice(0, Math.max(0, keys.length - RUNTIME_MAX)).map(function (k) { return c.delete(k); }));
  });
}

function cacheFirst(req) {
  return caches.match(req).then(function (hit) {
    if (hit) return hit;
    return fetch(req).then(function (res) {
      if (res && (res.ok || res.type === 'opaque')) {
        var copy = res.clone();
        caches.open(RUNTIME).then(function (c) { return c.put(req, copy).then(function () { return trimRuntime(c); }); });
      }
      return res;
    });
  });
}

self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return;                       // tips PUT etc. go straight through
  var url = new URL(req.url);

  // The app page itself (any query string / hash) — one cache entry.
  if (req.mode === 'navigate' && url.origin === self.location.origin && url.href.split('?')[0].replace(/index\.html$/, '') === SHELL_URL) {
    event.respondWith(networkFirst(req, SHELL_URL));
    return;
  }
  if (url.href === DATA_URL) {
    event.respondWith(networkFirst(req, DATA_URL));
    return;
  }
  // Destination photos cached on our server (tools/photos.py): immutable files.
  if (url.origin === self.location.origin && /\/photos\/[A-Z]{3}\/\d+\.jpg$/.test(url.pathname)) {
    event.respondWith(cacheFirst(req));
    return;
  }
  if (CACHE_FIRST_HOSTS.indexOf(url.hostname) >= 0) {
    event.respondWith(cacheFirst(req));
    return;
  }
  // Everything else (roster ICS relay/proxy, tips + flight JSON, sw.js): network as usual.
});
