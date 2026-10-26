#!/usr/bin/env python3
"""Weekly timezone sanity check for the roster app (stdlib only).

The app converts times with the viewer's own IANA tz database (Intl), using the
airport → zone map AIRPORT_TZ in roster.html. This job warns by e-mail when:
  1. a zone in AIRPORT_TZ is unknown to the tz database;
  2. the server's tzdata is older than the latest IANA release;
  3. a tzdata update changed the UTC offsets / DST dates of an airport we use
     (fingerprint of the next 18 months of transitions, kept in STATE);
  4. the crew feed's own "(HH:MM LOC)" times disagree with the zone's offset;
  5. the feed has a station that AIRPORT_TZ does not know.

Config (in the roster .env): ROSTER_ICS_URLS='<url> [<url> ...]',
TZCHECK_MAILTO='<address>'. Usage: tzcheck.py [--dry-run]  (prints, never mails)
"""
import datetime as dt, json, os, re, subprocess, sys, urllib.request
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML = os.path.join(APP_DIR, 'roster.html')
ENV = os.path.join(APP_DIR, '.env')
STATE = os.path.expanduser('~/.local/state/roster-tzcheck.json')
IANA_VERSION_URL = 'https://data.iana.org/time-zones/tzdb/version'
UTC = dt.timezone.utc


def read_env():
    env = {}
    for line in open(ENV, encoding='utf-8'):
        m = re.match(r"\s*([A-Z0-9_]+)=(.*)$", line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip('\'"')
    return env


def airport_zones():
    s = open(HTML, encoding='utf-8').read()
    i = s.index('const AIRPORT_TZ')
    block = s[i:s.index('};', i)]
    return dict(re.findall(r"\b([A-Z]{3})\s*:\s*'([^']+)'", block))


def local_tzdata_version():
    try:
        first = open('/usr/share/zoneinfo/tzdata.zi', encoding='utf-8').readline()
        return first.split()[-1]
    except OSError:
        return None


def transitions(zone, months=18):
    """UTC offset changes over the next `months`, as [iso_utc_hour, offset_min]."""
    z = ZoneInfo(zone)
    t = dt.datetime.now(UTC).replace(minute=0, second=0, microsecond=0)
    end = t + dt.timedelta(days=months * 31)
    prev, out = None, []
    while t < end:
        off = int(t.astimezone(z).utcoffset().total_seconds() // 60)
        if off != prev:
            out.append([t.strftime('%Y-%m-%dT%H:%MZ'), off])
            prev = off
        t += dt.timedelta(hours=1)
    return out


def unfold_events(ics):
    ics = re.sub(r'\r?\n[ \t]', '', ics)
    for block in re.findall(r'BEGIN:VEVENT(.*?)END:VEVENT', ics, re.S):
        ev = {}
        for line in block.strip().splitlines():
            k, _, v = line.partition(':')
            ev[k.split(';')[0]] = v
        yield ev


def next_at(after, hhmm):
    """First instant >= after whose UTC clock reads hhmm."""
    h, m = map(int, hhmm.split(':'))
    t = after.replace(hour=h, minute=m, second=0, microsecond=0)
    return t if t >= after else t + dt.timedelta(days=1)


def check_feed(url, zones):
    problems = []
    ics = urllib.request.urlopen(url, timeout=30).read().decode('utf-8', 'replace')
    for ev in unfold_events(ics):
        stations = re.search(r'\b([A-Z]{3})/([A-Z]{3})\b', ev.get('SUMMARY', ''))
        desc = ev.get('DESCRIPTION', '').replace('\\n', '\n')
        start = ev.get('DTSTART', '')
        if not stations or not start.endswith('Z'):
            continue
        cur = dt.datetime.strptime(start, '%Y%m%dT%H%M%SZ').replace(tzinfo=UTC)
        for label, idx in (('Checkin', 0), ('Departure', 0), ('Arrival', 1), ('Checkout', 1)):
            m = re.search(label + r'\s*:\s*(\d{1,2}:\d{2})\s*\((\d{1,2}:\d{2}) LOC\)', desc)
            if not m:
                continue
            cur = next_at(cur, m.group(1))
            ap = stations.group(idx + 1)
            if ap not in zones:
                problems.append(f'{ap}: station in the feed but missing from AIRPORT_TZ '
                                f'({ev.get("SUMMARY")})')
                continue
            uh, um = map(int, m.group(1).split(':'))
            lh, lm = map(int, m.group(2).split(':'))
            feed_off = ((lh * 60 + lm) - (uh * 60 + um)) % 1440
            if feed_off > 840:
                feed_off -= 1440
            zone_off = int(cur.astimezone(ZoneInfo(zones[ap])).utcoffset().total_seconds() // 60)
            if feed_off != zone_off:
                problems.append(f'{ap} {label} {cur:%Y-%m-%d %H:%MZ}: feed says UTC{feed_off/60:+g}, '
                                f'{zones[ap]} says UTC{zone_off/60:+g} ({ev.get("SUMMARY")})')
    return problems


def main():
    dry = '--dry-run' in sys.argv
    env = read_env()
    zones = airport_zones()
    problems, notes = [], []

    fingerprints = {}
    for ap, z in sorted(zones.items()):
        try:
            fingerprints[z] = transitions(z)
        except ZoneInfoNotFoundError:
            problems.append(f'{ap}: zone {z!r} does not exist in the tz database')

    local_v = local_tzdata_version()
    try:
        latest_v = urllib.request.urlopen(IANA_VERSION_URL, timeout=20).read().decode().strip()
    except Exception as e:  # network trouble is not a tz problem
        latest_v = None
        notes.append(f'could not read the IANA version: {e}')
    if local_v and latest_v and local_v < latest_v:
        problems.append(f'server tzdata {local_v} is older than IANA {latest_v} '
                        f'(apt upgrade tzdata; check iPhone iOS is up to date)')

    try:
        state = json.load(open(STATE))
    except (OSError, ValueError):
        state = {}
    old = state.get('fingerprints', {})
    for z, fp in fingerprints.items():
        if z in old:
            # Compare only the transitions inside the window both runs cover:
            # after this run's start, up to the older run's horizon.
            start, horizon = fp[0][0], state.get('horizon', '')
            a = [x for x in old[z] if start < x[0] <= horizon]
            b = [x for x in fp if start < x[0] <= horizon]
            if a != b:
                problems.append(f'{z}: offsets/DST dates changed (tzdata {state.get("tzdata")} → '
                                f'{local_v}): was {a}, now {b}')

    for url in env.get('ROSTER_ICS_URLS', '').split():
        try:
            problems += check_feed(url, zones)
        except Exception as e:
            notes.append(f'feed check failed: {e}')

    report = [f'tzdata server={local_v} iana={latest_v}; {len(zones)} airports; '
              f'{len(problems)} problem(s)'] + ['PROBLEM: ' + p for p in problems] + \
             ['note: ' + n for n in notes]
    print(f'{dt.datetime.now(UTC):%Y-%m-%d %H:%MZ} ' + '\n  '.join(report))

    if dry:
        return
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    horizon = dt.datetime.now(UTC) + dt.timedelta(days=18 * 31 - 1)
    json.dump({'tzdata': local_v, 'checked': dt.datetime.now(UTC).isoformat(),
               'horizon': horizon.strftime('%Y-%m-%dT%H:%MZ'),
               'fingerprints': fingerprints}, open(STATE, 'w'))
    mailto = env.get('TZCHECK_MAILTO')
    if problems and mailto:
        msg = (f'To: {mailto}\nSubject: [roster] timezone check: {len(problems)} problem(s)\n'
               f'Content-Type: text/plain; charset=utf-8\n\n' + '\n'.join(report) + '\n')
        subprocess.run(['/usr/sbin/sendmail', '-t'], input=msg.encode(), check=True)


if __name__ == '__main__':
    main()
