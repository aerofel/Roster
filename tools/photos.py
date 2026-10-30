#!/usr/bin/env python3
"""Server-side cache of the destination photos for the roster app (stdlib only).

Browsers used to call the Pexels search API themselves; one shared key capped
at 200 requests/hour ran out (HTTP 429) and photos stopped loading. This job
downloads a set of photos per city ONCE into roster/photos/<IATA>/ and writes
photos/index.json, which the app reads — so viewers never touch the API.

Cities = every airport in AIRPORTS / PEXELS_QUERIES of roster.html, plus every
station seen in the crew feeds (ROSTER_ICS_URLS). A city is (re)fetched when it
has no photos yet or its set is older than REFRESH_DAYS. A 429 stops the run
cleanly; the next run picks up where it left off.

Config (in the roster .env): PEXELS_API_KEY, ROSTER_ICS_URLS='<url> [<url> ...]'.
Usage: photos.py [--dry-run] [--force IATA ...]
"""
import datetime as dt, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML = os.path.join(APP_DIR, 'roster.html')
ENV = os.path.join(APP_DIR, '.env')
OUT = os.path.join(APP_DIR, 'photos')
INDEX = os.path.join(OUT, 'index.json')
PER_CITY = 80            # variety: as many different photos per city as Pexels gives
# Several searches per city (de-duplicated) give far more variety than one query.
FACETS = ['', 'landmark', 'street', 'night', 'nature', 'aerial view']
REFRESH_DAYS = 90
UA = 'looping.org-roster-photos/1.0'


def read_env():
    env = {}
    for line in open(ENV, encoding='utf-8'):
        m = re.match(r"\s*([A-Z0-9_]+)=(.*)$", line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip('\'"')
    return env


def js_map(src, name):
    i = src.index('const ' + name)
    block = src[i:src.index('};', i)]
    return dict(re.findall(r"\b([A-Z]{3})\s*:\s*'([^']+)'", block))


def feed_cities(urls):
    out = set()
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            txt = urllib.request.urlopen(req, timeout=30).read().decode('utf-8', 'replace')
        except Exception as e:
            print('feed failed:', e.__class__.__name__, file=sys.stderr)
            continue
        txt = re.sub(r'\r?\n[ \t]', '', txt)
        for s in re.findall(r'^SUMMARY:(.*)$', txt, re.M):
            out.update(re.findall(r'\b([A-Z]{3})\b', s.split(' - ', 1)[-1]))
    return out


def pexels(key, query, page):
    q = urllib.parse.urlencode({'query': query, 'orientation': 'landscape', 'per_page': 40, 'page': page})
    req = urllib.request.Request('https://api.pexels.com/v1/search?' + q, headers={'Authorization': key, 'User-Agent': UA})
    return json.load(urllib.request.urlopen(req, timeout=30))


def download(url, path):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    data = urllib.request.urlopen(req, timeout=60).read()
    if len(data) < 5000:
        raise ValueError('too small')
    tmp = path + '.part'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)


def main():
    dry = '--dry-run' in sys.argv
    force = {a.upper() for a in sys.argv[1:] if re.fullmatch(r'[A-Za-z]{3}', a)} if '--force' in sys.argv else set()
    env = read_env()
    key = env.get('PEXELS_API_KEY', '')
    if not key:
        sys.exit('PEXELS_API_KEY missing in .env')
    src = open(HTML, encoding='utf-8').read()
    airports, queries = js_map(src, 'AIRPORTS'), js_map(src, 'PEXELS_QUERIES')
    known = set(airports) | set(queries)
    cities = known | (feed_cities(env.get('ROSTER_ICS_URLS', '').replace(',', ' ').split()) & set(js_map(src, 'AIRPORT_TZ')))
    try:
        index = json.load(open(INDEX, encoding='utf-8'))
    except Exception:
        index = {}
    now = time.time()
    changed = False
    for iata in sorted(cities):
        cur = index.get(iata) or {}
        fresh = len(cur.get('photos') or []) >= PER_CITY * 0.75 and now - cur.get('at', 0) < REFRESH_DAYS * 86400
        if fresh and iata not in force:
            continue
        base = queries.get(iata) or re.split(r'\s+[—–-]\s+', airports.get(iata, iata + ' city'))[0]
        place = re.split(r'\s+[—–-]\s+', airports.get(iata, base))[0]
        print(f'{iata}: searching "{base}" + {len(FACETS) - 1} facets')
        if dry:
            continue
        results, seen, quota = [], set(), False
        for facet in FACETS:
            if len(results) >= PER_CITY:
                break
            try:
                res = pexels(key, (place + ' ' + facet) if facet else base, 1)
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    quota = True
                    break
                print(f'{iata}: HTTP {e.code}', file=sys.stderr)
                continue
            for p in res.get('photos', []):
                if p.get('id') not in seen:
                    seen.add(p.get('id')); results.append(p)
            time.sleep(1)
        if quota and len(results) < PER_CITY * 0.75:
            print('Pexels quota reached (429) — stopping, next run continues.')
            break
        os.makedirs(os.path.join(OUT, iata), exist_ok=True)
        got = []
        for p in results:
            if len(got) >= PER_CITY:
                break
            url = (p.get('src') or {}).get('landscape')
            if not url:
                continue
            name = f"{iata}/{int(p['id'])}.jpg"
            path = os.path.join(OUT, name)
            try:
                if not os.path.exists(path):
                    download(url, path)
                got.append({'f': name, 'by': p.get('photographer', ''), 'page': p.get('url', '')})
            except Exception as e:
                print(f'  skip {p.get("id")}: {e.__class__.__name__}', file=sys.stderr)
        if got:
            # drop files of photos no longer in the set
            keep = {g['f'] for g in got}
            for old in (cur.get('photos') or []):
                if old['f'] not in keep:
                    try:
                        os.remove(os.path.join(OUT, old['f']))
                    except OSError:
                        pass
            index[iata] = {'at': int(now), 'photos': got}
            changed = True
            print(f'{iata}: {len(got)} photos')
        if quota:
            print('Pexels quota reached (429) — stopping, next run continues.')
            break
    if changed:
        index['_updated'] = dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%MZ')
        tmp = INDEX + '.part'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(index, f, separators=(',', ':'), ensure_ascii=False)
        os.replace(tmp, INDEX)


if __name__ == '__main__':
    main()
