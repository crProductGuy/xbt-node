#!/bin/sh
# install-battery-guard.sh: DEVUAN (sysvinit, cron) ONLY. Installs battery-guard.sh so the
# laptop shuts down cleanly on low battery even when nobody is logged in.
#
#   sudo sh install-battery-guard.sh            install (safe to run again)
#   sudo sh install-battery-guard.sh remove     undo
#
# Installs /usr/local/sbin/battery-guard, writes /etc/cron.d/battery-guard (every minute,
# as root), and writes /etc/default/battery-guard with THRESHOLD=25 unless that file
# already exists. Starts and stops nothing now.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = "remove" ]; then
    rm -f /etc/cron.d/battery-guard /usr/local/sbin/battery-guard
    rm -rf /run/battery-guard
    echo "removed. /etc/default/battery-guard was kept."
    exit 0
fi

[ -f "$HERE/battery-guard.sh" ] || { echo "missing: $HERE/battery-guard.sh"; exit 1; }
[ -x /sbin/shutdown ] || { echo "missing: /sbin/shutdown"; exit 1; }
[ -d /etc/cron.d ] || { echo "missing: /etc/cron.d (is cron installed?)"; exit 1; }

install -m 755 -o root -g root "$HERE/battery-guard.sh" /usr/local/sbin/battery-guard
printf '%s\n' \
  '# battery-guard: clean shutdown on low battery (from xbt-node install-battery-guard.sh)' \
  'SHELL=/bin/sh' \
  'PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin' \
  '* * * * * root /usr/local/sbin/battery-guard' > /etc/cron.d/battery-guard
chmod 644 /etc/cron.d/battery-guard
[ -e /etc/default/battery-guard ] || printf 'THRESHOLD=25\n' > /etc/default/battery-guard
chown root:root /etc/default/battery-guard
chmod 644 /etc/default/battery-guard

echo "installed. What it reads now:"
S=$(/usr/local/sbin/battery-guard --status)
echo "$S"
case $S in
    *"cannot read"*) echo "WARNING: it cannot read this machine's battery or AC state, so it will never act. Check /sys/class/power_supply." ;;
esac
