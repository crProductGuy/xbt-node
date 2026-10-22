#!/bin/sh
# install-autostart.sh: DEVUAN (sysvinit) ONLY. Makes the node and the DATUM gateway start
# at boot and stop cleanly at shutdown, for the PATUM layout under one user's home.
#
#   sudo sh install-autostart.sh <user>        e.g.  sudo sh ~/init/install-autostart.sh YOURNAME
#
# Installs devuan-bitcoind.init as /etc/init.d/bitcoind and devuan-datum-gateway.init as
# /etc/init.d/datum-gateway (both from this script's folder), writes their settings to
# /etc/default/, and registers them. It does NOT start or stop anything now: the node and
# gateway that are already running keep running, and the scripts take over at next boot.
# Safe to run again. Undo:  update-rc.d datum-gateway remove; update-rc.d bitcoind remove
set -eu

U=${1:?give the user that runs the node, e.g. YOURNAME}
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
getent passwd "$U" >/dev/null || { echo "no such user: $U"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
H=$(getent passwd "$U" | cut -d: -f6)
P=$H/pyblock-node

for f in "$HERE/devuan-bitcoind.init" "$HERE/devuan-datum-gateway.init" \
         "$P/bin/bitcoind" "$P/bin/bitcoin-cli" "$P/data/chainstate" "$H/pyblock-gateway/datum_gateway"; do
  [ -e "$f" ] || { echo "missing: $f"; exit 1; }
done
grep -q '^blocksdir=/mnt/passport' "$P/data/bitcoin.conf" || { echo "bitcoin.conf lacks blocksdir=/mnt/passport"; exit 1; }
grep -q '^consensusrules=rdts' "$P/data/bitcoin.conf" || { echo "bitcoin.conf lacks consensusrules=rdts"; exit 1; }

install -m 755 "$HERE/devuan-bitcoind.init" /etc/init.d/bitcoind
install -m 755 "$HERE/devuan-datum-gateway.init" /etc/init.d/datum-gateway
printf 'BITCOIN_USER=%s\nBITCOIND=%s\nDATADIR=%s\n' "$U" "$P/bin/bitcoind" "$P/data" > /etc/default/bitcoind
printf 'GW_USER=%s\n' "$U" > /etc/default/datum-gateway

update-rc.d bitcoind defaults
update-rc.d datum-gateway defaults

echo
echo "installed. Check (both should say running):"
service bitcoind status || true
service datum-gateway status || true
echo
echo "boot order (S = start, K = stop):"
ls /etc/rc2.d /etc/rc0.d | grep -E 'bitcoind|datum' || true
