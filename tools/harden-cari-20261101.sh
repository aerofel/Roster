#!/usr/bin/env bash
# cari7 lockdown, 2026-11-01 — run once as root:
#   sudo bash /home/looping/looping.org/roster/tools/harden-cari-20261101.sh
# Goal: the web user (www-data, every PHP site) must not be able to change code that
# looping runs by hand. Sticky folders can't do it here (fs.protected_regular=2 then
# blocks appending to the logs), so instead:
#   - CARI7 binary → cari7/bin/ (root-only folder); cari.py still runs it in engine/
#   - the lock file → cari7/run/ (the only place a run creates/deletes files)
#   - cari7/ itself no longer group-writable: cari.py can't be swapped out
# Avoid running it at :17 (hourly cari cron). Rolls back by itself if the test run fails.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
C=/home/looping/cari7
grep -q '"bin", "CARI7"' "$C/cari.py" && { echo "already applied"; exit 1; }
BK=/root/cari-hardening-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"; cp -p "$C/cari.py" "$BK/"
stat -c '%a %U:%G %n' "$C" "$C/engine" "$C/cari.py" "$C/engine/CARI7" > "$BK/perms.txt"

rollback() {
  echo "!! rolling back"
  cp -p "$BK/cari.py" "$C/cari.py"
  [ -e "$C/bin/CARI7" ] && mv "$C/bin/CARI7" "$C/engine/CARI7"
  chmod g+w "$C"
  exit 1
}

install -d -o root -g root -m 755 "$C/bin"
mv "$C/engine/CARI7" "$C/bin/CARI7"
chown root:root "$C/bin/CARI7"; chmod 755 "$C/bin/CARI7"
install -d -o looping -g www-data -m 2770 "$C/run"
python3 -I - "$C/cari.py" <<'PY' || rollback
import sys
p = sys.argv[1]; s = open(p).read()
for a, b in [('BINARY    = os.path.join(ENGINE, "CARI7")',
              'BINARY    = os.path.join(BASE, "bin", "CARI7")       # root-only folder; still run with cwd=ENGINE'),
             ('LOCKFILE  = os.path.join(BASE, "cari.lock")',
              'LOCKFILE  = os.path.join(BASE, "run", "cari.lock")   # run/ is the only folder www-data creates files in')]:
    if s.count(a) != 1: sys.exit('cari.py: anchor not found: ' + a)
    s = s.replace(a, b)
open(p, 'w').write(s)
PY
rm -rf "$C/__pycache__"          # left by a www-data import test on 2026-11-01
chmod g-w "$C"                   # 2775 → 2755: setgid kept, no more create/rename/delete by www-data

echo "Checks:"
fail=0
if sudo -u www-data touch "$C/probe" 2>/dev/null; then echo "  FAIL www-data can still create files in $C"; rm -f "$C/probe"; fail=1
else echo "  ok   www-data can't create, rename or replace files in $C"; fi
if sudo -u www-data sh -c ": >> '$C/bin/CARI7'" 2>/dev/null; then echo "  FAIL www-data can write the CARI7 binary"; fail=1
else echo "  ok   CARI7 binary is root-only"; fi
[ $fail = 0 ] || rollback

out=$(mktemp)
before=$(tail -n 1 "$C/cari.log")
if sudo -u www-data /usr/bin/python3 "$C/cari.py" fetch > "$out" 2>&1 && [ "$(tail -n 1 "$C/cari.log")" != "$before" ]; then
  cat "$out" >> "$C/cron.log"
  echo "  ok   cari.py fetch as www-data (same as the hourly cron):"; tail -n 3 "$C/cari.log" | sed 's/^/         /'
  rm -f "$out"
else
  cat "$out" >> "$C/cron.log"
  echo "  FAIL cari.py fetch — output:"; sed 's/^/         /' "$out" | tail -n 15; rm -f "$out"
  rollback
fi
echo "Done. Backup in $BK"
