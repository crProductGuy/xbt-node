#!/bin/sh
# install-panel-autostart.sh: DEVUAN (sysvinit) ONLY. Makes PATUM's web panel start at boot,
# after the DATUM gateway, on a fixed port bound to 127.0.0.1.
#
#   sudo sh install-panel-autostart.sh <user> [port]      (port default 32999)
#   e.g.  sudo sh install-panel-autostart.sh YOURNAME
#
# Installs devuan-patum-panel.init (from this script's folder) as /etc/init.d/patum-panel,
# writes /etc/default/patum-panel and registers it. install-autostart.sh runs this too.
# It does NOT start or stop anything now; a panel that is already running keeps running.
# Safe to run again. Undo:  update-rc.d patum-panel remove
set -eu

# valid_port PORT  succeeds for a number from 1024 to 65535.
valid_port() {
    case $1 in ''|*[!0-9]*) return 1 ;; esac
    [ ${#1} -le 5 ] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}

U=${1:?give the user that runs PATUM, e.g. YOURNAME}
PORT=${2:-32999}
valid_port "$PORT" || { echo "bad port '$PORT': use a number from 1024 to 65535"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
getent passwd "$U" >/dev/null || { echo "no such user: $U"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
H=$(getent passwd "$U" | cut -d: -f6)

for f in "$HERE/devuan-patum-panel.init" "$H/pyblock-node/bin/patum"; do
  [ -e "$f" ] || { echo "missing: $f"; exit 1; }
done
[ -e /etc/init.d/datum-gateway ] || echo "note: /etc/init.d/datum-gateway is not installed; the panel then starts after a 1-hour wait for the gateway. Run install-autostart.sh first."

install -m 755 "$HERE/devuan-patum-panel.init" /etc/init.d/patum-panel
printf "PANEL_USER='%s'\nPANEL_PORT=%s\n" "$U" "$PORT" > /etc/default/patum-panel
update-rc.d patum-panel defaults

echo
echo "panel installed: starts at boot after the gateway, at http://127.0.0.1:$PORT/"
echo "from another machine:  ssh -L $PORT:127.0.0.1:$PORT $U@<this-machine>"
service patum-panel status || true
