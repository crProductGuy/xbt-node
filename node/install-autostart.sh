#!/bin/sh
# install-autostart.sh: DEVUAN (sysvinit) ONLY. Makes the node and the DATUM gateway start
# at boot and stop cleanly at shutdown, for the PATUM layout under one user's home.
#
#   sudo sh install-autostart.sh <user> [auto|none|/mount/point]
#   e.g.  sudo sh ~/init/install-autostart.sh YOURNAME
#
# Block drive check (MNT in /etc/default/bitcoind):
#   auto (default)  if bitcoin.conf has blocksdir=<dir> and <dir> is a mount point in
#                   /etc/fstab, the node never starts without that drive mounted.
#                   Otherwise (blocks on the internal disk) there is no drive check.
#   none            no drive check
#   /mount/point    check this mount point
#
# Installs devuan-bitcoind.init as /etc/init.d/bitcoind and devuan-datum-gateway.init as
# /etc/init.d/datum-gateway (both from this script's folder), writes their settings to
# /etc/default/, and registers them. Then runs install-panel-autostart.sh for the PATUM panel. It does NOT start or stop anything now: the node and
# gateway that are already running keep running, and the scripts take over at next boot.
# Safe to run again. Undo:  update-rc.d datum-gateway remove; update-rc.d bitcoind remove
set -eu

# pick_mnt CONF FSTAB CHOICE  prints the mount point to check, or nothing for no check.
# auto: the /etc/fstab mount point (not "/") that holds bitcoin.conf's blocksdir, the
# blocksdir itself or any folder above it; the deepest one wins.
pick_mnt() {
    case $3 in
        none) return 0 ;;
        *[[:space:]\'\"\\]*) echo "bad drive choice '$3': no spaces, quotes or backslashes" >&2; return 1 ;;
        /*)   echo "$3"; return 0 ;;
        auto) ;;
        *)    echo "bad drive choice '$3': use auto, none or /mount/point" >&2; return 1 ;;
    esac
    bd=$(sed -n 's/^[[:space:]]*blocksdir[[:space:]]*=[[:space:]]*\(.*[^/[:space:]]\)[/[:space:]]*$/\1/p' "$1" 2>/dev/null | tail -n 1)
    [ -n "$bd" ] || return 0
    awk -v p="$bd" '$1 !~ /^#/ && $2 != "/" && (p == $2 || index(p, $2 "/") == 1) && length($2) > length(m) { m = $2 }
                    END { if (m != "") print m }' "$2" 2>/dev/null
    return 0
}

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
grep -q '^consensusrules=rdts' "$P/data/bitcoin.conf" || { echo "bitcoin.conf lacks consensusrules=rdts"; exit 1; }
MNT=$(pick_mnt "$P/data/bitcoin.conf" /etc/fstab "${2:-auto}") || exit 1
if [ -n "$MNT" ]; then
    echo "block drive check: the node starts only when $MNT is mounted"
else
    echo "block drive check: none (blocks on the internal disk)"
    grep -qE '^[[:space:]]*blocksdir[[:space:]]*=' "$P/data/bitcoin.conf" &&
        echo "  note: bitcoin.conf sets blocksdir, but no /etc/fstab mount point holds it. If it is on a removable drive, run again with the drive's mount point as the second argument."
fi

install -m 755 "$HERE/devuan-bitcoind.init" /etc/init.d/bitcoind
install -m 755 "$HERE/devuan-datum-gateway.init" /etc/init.d/datum-gateway
printf "BITCOIN_USER='%s'\nBITCOIND='%s'\nDATADIR='%s'\nMNT='%s'\n" "$U" "$P/bin/bitcoind" "$P/data" "$MNT" > /etc/default/bitcoind
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

# The PATUM panel, last: it starts after the gateway, on port 32999.
echo
sh "$HERE/install-panel-autostart.sh" "$U" || echo "panel autostart NOT installed (see above); the node and gateway are."
