#!/usr/bin/env bash
# Roster security hardening, 2026-11-01 — run once as root:
#   sudo bash /home/looping/looping.org/roster/tools/harden-20261101.sh
# Backs everything up to /root/roster-hardening-20261101-<time>/ first and rolls the Apache
# changes back by itself if the config test or a live check fails. No change for users:
# no login, no password, same URLs.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

BK=/root/roster-hardening-20261101-$(date +%H%M%S)   # one folder per run
SSL=/etc/apache2/sites-enabled/00b-looping.org-ssl
P80=/etc/apache2/sites-available/001-looping.org
TIPCRON=/etc/cron.d/roster-tips
ROSTER=/home/looping/looping.org/roster
CARI=/home/looping/cari7
grep -q 'roster_ics_nolog' "$SSL" && { echo "already applied (roster_ics_nolog in $SSL)"; exit 1; }
mkdir -p "$BK/sites-enabled-bak"
cp -p "$SSL" "$P80" "$TIPCRON" "$BK/"
stat -c '%a %U:%G %n' "$CARI" "$CARI/engine" "$CARI/cari.py" "$CARI/engine/CARI7" > "$BK/cari-perms.txt"

rollback() {
  echo "!! rolling back the Apache changes"
  cp -p "$BK/00b-looping.org-ssl" "$SSL"; cp -p "$BK/001-looping.org" "$P80"
  mv "$BK"/sites-enabled-bak/* /etc/apache2/sites-enabled/ 2>/dev/null || true
  apache2ctl configtest && systemctl reload apache2
  exit 1
}

# ── 1. Stale vhost copies: Apache loads every file in sites-enabled/, .bak included ──
mv /etc/apache2/sites-enabled/*.bak* "$BK/sites-enabled-bak/" 2>/dev/null || true

# ── 2. looping.org HTTPS vhost ──
python3 -I - "$SSL" <<'PY' || rollback
import sys
p = sys.argv[1]; s = open(p).read()
def R(old, new):
    global s
    if s.count(old) != 1: sys.exit('vhost: anchor not found once: ' + old[:70])
    s = s.replace(old, new)

CSP_APP = ("default-src 'self'; script-src 'self' 'unsafe-inline'; "
           "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; "
           "img-src 'self' data: blob:; connect-src 'self' https:; worker-src 'self'; manifest-src 'self'; "
           "object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'self'")
DAV_HDRS = ('\t\t# Data, never a page: nothing in here may run as HTML/script on this origin.\n'
            '\t\tHeader always set Content-Security-Policy "default-src \'none\'; sandbox"\n'
            '\t\tHeader always set X-Content-Type-Options "nosniff"\n')

# 2a. headers + .var handler off + internal files hidden
R('''	<LocationMatch "^/roster/(index\\.html|sw\\.js)?$">
		Header set Cache-Control "no-cache, must-revalidate"
	</LocationMatch>
''', '''	<LocationMatch "^/roster/(index\\.html|sw\\.js)?$">
		Header set Cache-Control "no-cache, must-revalidate"
	</LocationMatch>

	# ── Security headers + lockdown (hardening 2026-11-01) ──
	Header always set Strict-Transport-Security "max-age=31536000"
	Header always set Referrer-Policy "strict-origin-when-cross-origin"
	# The app is one file with inline script and inline handlers, hence 'unsafe-inline';
	# connect-src stays open to https: because each crew member's own portal is fetched.
	<LocationMatch "^/roster/(index\\.html)?$">
		Header always set Content-Security-Policy "''' + CSP_APP + '''"
	</LocationMatch>
	# mime.conf maps .var to the type-map handler server-wide; nothing in the roster
	# is a type-map, and with anonymous uploads it would serve attacker HTML here.
	<Directory /home/looping/looping.org/roster>
		RemoveHandler .var
	</Directory>
	# Internal docs, sources and build files are not for the public.
	<LocationMatch "^/roster/(.*\\.md|build\\.sh|sw\\.template\\.js|roster\\.html|\\.env.*|tools(/.*)?)$">
		Require all denied
	</LocationMatch>
''')

# 2b. tips: size cap, data-only headers, strict file names (no dots: no .var.json tricks)
R('''	<Location /roster/tips>
		Dav On
''', '''	<Location /roster/tips>
		Dav On
		# A tips file is a few KB; cap uploads at 1 MB (2026-11-01).
		LimitRequestBody 1048576
''' + DAV_HDRS)
R('<LocationMatch "^/roster/tips/(?!tips_[A-Za-z0-9._-]+\\.json$).">',
  '<LocationMatch "^/roster/tips/(?!tips_[a-z0-9-]{1,40}\\.json$).">')
R('''	<Location /roster/sync>
		Dav On
''', '''	<Location /roster/sync>
		Dav On
''' + DAV_HDRS)
R('''	<Location /roster/flights>
		Dav On
''', '''	<Location /roster/flights>
		Dav On
''' + DAV_HDRS)

# 2c. same-origin ICS relay (replaces corsproxy.io for the Aircalin portal)
R('''	AliasMatch (?i)/Autodiscover/Autodiscover.xml''', '''	# ── Roster ICS relay (2026-11-01) ──
	# The Aircalin crew portal sends no CORS headers, so the app had to read the feed
	# through corsproxy.io — handing the secret roster link to a third party. This
	# same-origin pass-through replaces it: one fixed upstream, GET only, app requests
	# only, cookies stripped, and NOT logged (the query string is the secret).
	SSLProxyEngine on
	SSLProxyVerify require
	# the portal's chain is leaf + intermediate; the default depth (1) rejects it
	SSLProxyVerifyDepth 5
	SSLProxyCheckPeerName on
	SSLProxyCACertificateFile /etc/ssl/certs/ca-certificates.crt
	SetEnvIf Request_URI "^/roster/ics" roster_ics_nolog
	<Location /roster/ics>
		ProxyPass "https://alexis.aircalin.nc/crew-web/ics" timeout=25
		ProxyAddHeaders Off
		RequestHeader unset Cookie
		RequestHeader unset Referer
		RequestHeader unset Origin
		Header always unset Set-Cookie
		Header always set Cache-Control "no-store"
		Header always set X-Robots-Tag "noindex, nofollow, noarchive"
		<RequireAll>
			Require method GET HEAD
			<RequireAny>
				Require expr "%{HTTP:Sec-Fetch-Site} == 'same-origin'"
				Require expr "%{HTTP_REFERER} =~ m#^https://(www\\.)?looping\\.org/roster/#"
			</RequireAny>
		</RequireAll>
	</Location>
	<LocationMatch "^/roster/ics/">
		Require all denied
	</LocationMatch>

	AliasMatch (?i)/Autodiscover/Autodiscover.xml''')
R('''	CustomLog ${APACHE_LOG_DIR}/looping.org-ssl_access.log combined
''', '''	CustomLog ${APACHE_LOG_DIR}/looping.org-ssl_access.log combined env=!roster_ics_nolog
''')
open(p, 'w').write(s)
PY

# ── 3. Port 80: every Host goes to HTTPS (the bare IP / unknown names served the site,
#       data/ and flights/ included, ungated over plain HTTP) ──
python3 -I - "$P80" <<'PY' || rollback
import sys
p = sys.argv[1]; s = open(p).read()
old = '''RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>'''
if s.count(old) != 1: sys.exit('port-80 vhost: anchor not found')
s = s.replace(old, '''RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
# Any other Host (bare IP, unknown names): HTTPS too, never the site over plain HTTP (2026-11-01)
RewriteCond %{REQUEST_URI} !^/\\.well-known/acme-challenge/
RewriteRule ^ https://looping.org%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>''')
open(p, 'w').write(s)
PY

apache2ctl configtest || rollback
systemctl reload apache2
sleep 2

# ── 4. Live checks (rollback on failure) ──
fail=0
chk() { local want=$1 got; shift; got=$(curl -s -o /dev/null -w '%{http_code}' "$@" || true)
        if [ "$got" = "$want" ]; then echo "  ok   $want  ${*: -1}"; else echo "  FAIL got $got want $want  ${*: -1}"; fail=1; fi; }
echo "Live checks:"
chk 200 https://looping.org/roster/
chk 403 https://looping.org/roster/MEMORY.md
chk 403 https://looping.org/roster/tools/photos.py
chk 403 https://looping.org/roster/roster.html
chk 200 https://looping.org/roster/tips/tips_aircalin.json
chk 403 https://looping.org/roster/tips/tips_x.var.json
chk 403 https://looping.org/roster/ics
chk 301 -H 'Host: x' http://87.98.250.102/roster/data/flightplans.json
chk 301 http://looping.org/roster/
chk 403 https://looping.org/roster/data/flightplans.json
chk 200 -H 'Sec-Fetch-Site: same-origin' https://looping.org/roster/data/flightplans.json
# relay: fetch the real feed from .env through it (nothing printed, and the relay isn't logged)
feed=$(grep -m1 '^ROSTER_ICS_URLS=' "$ROSTER/.env" | sed -E "s/^ROSTER_ICS_URLS=['\"]?//; s/['\"]?$//" | awk '{print $1}')
n=$(curl -s --max-time 30 -H 'Sec-Fetch-Site: same-origin' "https://looping.org/roster/ics?${feed#*\?}" | grep -c 'BEGIN:VEVENT' || true)
if [ "${n:-0}" -gt 0 ]; then echo "  ok   relay returned the roster feed ($n events)"
else   # the portal itself is sometimes down (503): only fail if a direct fetch works right now
  d=$(curl -s --max-time 30 "$feed" | grep -c 'BEGIN:VEVENT' || true)
  if [ "${d:-0}" -gt 0 ]; then echo "  FAIL relay returned no events but the portal works"; fail=1
  else echo "  WARN portal down right now — relay not verified (the app falls back by itself)"; fi
fi
curl -sI https://looping.org/roster/ | grep -qi '^content-security-policy:' || { echo "  FAIL no CSP"; fail=1; }
curl -s https://looping.org/roster/tips/tips_aircalin.json -o /dev/null -D - | grep -qi "sandbox" || { echo "  FAIL no sandbox CSP on tips"; fail=1; }
[ $fail = 0 ] || rollback

# ── 5. Backups: only keep a copy when the file changed (was: 30 full copies/month each) ──
cat > "$TIPCRON" <<'CRON'
# Daily backup of the roster's shared WebDAV files (tips, flight data). Script-less storage → keep recoverable copies.
# A copy is made only when the file changed since its newest backup (that one is touched so the 30-day prune keeps it).
# Plain cp, not -p: the copy needs today's mtime, else the -mtime +30 prune deletes it at once.
SHELL=/bin/bash
MAILTO=looping@looping.org
30 3 * * * www-data d=$(date +\%Y\%m\%d); for f in /home/looping/looping.org/roster/tips/tips_*.json; do [ -e "$f" ] || continue; b=/home/looping/looping.org/roster/tips/.backups/$(basename "$f" .json); last=$(ls -t "$b"-*.json 2>/dev/null | head -1); if [ -n "$last" ] && cmp -s "$f" "$last"; then touch "$last"; else cp "$f" "$b-$d.json"; fi; done; find /home/looping/looping.org/roster/tips/.backups -name '*.json' -mtime +30 -delete
35 3 * * * www-data d=$(date +\%Y\%m\%d); for f in /home/looping/looping.org/roster/flights/flt_*.json; do [ -e "$f" ] || continue; b=/home/looping/looping.org/roster/flights/.backups/$(basename "$f" .json); last=$(ls -t "$b"-*.json 2>/dev/null | head -1); if [ -n "$last" ] && cmp -s "$f" "$last"; then touch "$last"; else cp "$f" "$b-$d.json"; fi; done; find /home/looping/looping.org/roster/flights/.backups -name '*.json' -mtime +30 -delete
# Anonymous uploads are size-capped per file but not in number: mail if the shared folders pass 200 MB.
45 3 * * * www-data s=$(du -sm /home/looping/looping.org/roster/tips /home/looping/looping.org/roster/flights /home/looping/looping.org/roster/sync | awk '{t+=$1} END{print t}'); [ "$s" -le 200 ] || echo "Roster shared storage (tips + flights + sync) is ${s} MB — check for abuse."
CRON
chmod 644 "$TIPCRON"

# ── 6. cari7: the web user (all PHP sites run as www-data) must not be able to change
#       code that looping runs by hand. Root owns it; sticky dirs stop delete+recreate. ──
chown root:root "$CARI/cari.py" "$CARI/engine/CARI7"
chmod 755 "$CARI/cari.py" "$CARI/engine/CARI7"
chmod +t "$CARI" "$CARI/engine"
echo "cari.py test run as www-data (same as the hourly cron):"
if sudo -u www-data /usr/bin/python3 "$CARI/cari.py" fetch >> "$CARI/cron.log" 2>&1; then
  echo "  ok   cari.py fetch"; tail -n 3 "$CARI/cari.log" | sed 's/^/    /'
else
  echo "  FAIL cari.py fetch — removing the sticky bits again (ownership change kept)"; chmod -t "$CARI" "$CARI/engine"
  tail -n 5 "$CARI/cron.log" | sed 's/^/    /'
fi

echo
echo "Done. Backups in $BK"
