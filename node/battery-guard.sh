#!/bin/sh
# battery-guard.sh: DEVUAN laptop node. Shuts the machine down cleanly when it is running
# on battery and the battery is low, whether or not anyone is logged in to the desktop.
#
# Runs every minute from /etc/cron.d/battery-guard (see install-battery-guard.sh).
# "Cleanly" means the normal shutdown path: /etc/init.d/datum-gateway and
# /etc/init.d/bitcoind stop first, and the node gets up to 15 minutes to flush.
#
# It acts only when ALL of these hold, on two runs in a row (one bad reading never acts):
#   - no mains adapter reports online=1
#   - the battery reports status Discharging
#   - the battery capacity is a number at or below THRESHOLD (default 25 %)
# Anything it cannot read means "do nothing".
#
#   battery-guard            check once (what cron runs)
#   battery-guard --status   print what it reads and what it would do; never acts
#
# Settings: /etc/default/battery-guard may hold one line THRESHOLD=<5..50>.
# For tests only, these environment variables replace the system paths:
#   BG_POWER_SUPPLY  (default /sys/class/power_supply)
#   BG_STATE_DIR     (default /run/battery-guard)
#   BG_CONFIG        (default /etc/default/battery-guard)
#   BG_SHUTDOWN      (default "/sbin/shutdown -h now")
set -u

PS=${BG_POWER_SUPPLY:-/sys/class/power_supply}
STATE=${BG_STATE_DIR:-/run/battery-guard}
CONFIG=${BG_CONFIG:-/etc/default/battery-guard}
SHUTDOWN=${BG_SHUTDOWN:-/sbin/shutdown -h now}
DEFAULT_THRESHOLD=25

log() { logger -t battery-guard -- "$*" 2>/dev/null || echo "battery-guard: $*" >&2; }

# The config file is parsed, never sourced: only a plain THRESHOLD=<number> line counts.
read_threshold() {
    t=""
    [ -r "$CONFIG" ] && t=$(sed -n 's/^THRESHOLD=\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$CONFIG" | tail -n 1)
    case $t in
        ''|*[!0-9]*) echo "$DEFAULT_THRESHOLD"; return ;;
    esac
    if [ "$t" -ge 5 ] && [ "$t" -le 50 ]; then echo "$t"; else echo "$DEFAULT_THRESHOLD"; fi
}

# Prints "online", "offline", or "unknown" (no mains adapter found or none readable).
mains_state() {
    found=no
    for d in "$PS"/*; do
        [ -r "$d/type" ] || continue
        [ "$(cat "$d/type" 2>/dev/null)" = "Mains" ] || continue
        o=$(cat "$d/online" 2>/dev/null) || continue
        found=yes
        [ "$o" = "1" ] && { echo online; return; }
    done
    [ $found = yes ] && echo offline || echo unknown
}

# Sets BAT_STATUS and BAT_CAP from the first battery found; both empty if none.
read_battery() {
    BAT_STATUS=""; BAT_CAP=""
    for d in "$PS"/*; do
        [ -r "$d/type" ] || continue
        [ "$(cat "$d/type" 2>/dev/null)" = "Battery" ] || continue
        # wireless mice, keyboards and controllers report as Battery with scope Device
        [ "$(cat "$d/scope" 2>/dev/null)" = "Device" ] && continue
        BAT_STATUS=$(cat "$d/status" 2>/dev/null)
        BAT_CAP=$(cat "$d/capacity" 2>/dev/null)
        return
    done
}

THRESHOLD=$(read_threshold)
MAINS=$(mains_state)
read_battery

# Decide: "act" only for a clean low-battery reading; everything else is "ok" or "unsure".
DECISION=ok
case $BAT_CAP in ''|*[!0-9]*) CAP_OK=no ;; *) CAP_OK=yes ;; esac
if [ "$MAINS" = online ]; then
    DECISION=ok
elif [ "$MAINS" = unknown ] || [ -z "$BAT_STATUS" ] || [ $CAP_OK = no ]; then
    DECISION=unsure
elif [ "$BAT_STATUS" = Discharging ] && [ "$BAT_CAP" -le "$THRESHOLD" ]; then
    DECISION=low
fi

if [ "${1:-}" = "--status" ]; then
    echo "mains: $MAINS"
    echo "battery: status=${BAT_STATUS:-none} capacity=${BAT_CAP:-none}"
    echo "threshold: $THRESHOLD %"
    case $DECISION in
        low) echo "decision: LOW (would shut down if this holds on two runs in a row)" ;;
        unsure) echo "decision: cannot read the power state, does nothing" ;;
        *) echo "decision: ok, does nothing" ;;
    esac
    exit 0
fi

mkdir -p "$STATE" 2>/dev/null || { log "cannot create $STATE; doing nothing"; exit 0; }

if [ "$DECISION" != low ]; then
    rm -f "$STATE/low" "$STATE/fired" 2>/dev/null   # a new low spell starts counting afresh
    exit 0
fi

[ -e "$STATE/fired" ] && exit 0      # shutdown already requested; /run is cleared at boot

if [ ! -e "$STATE/low" ]; then
    # touch, not ": >": dash exits on a failed redirect of a special builtin
    touch "$STATE/low" 2>/dev/null || { log "cannot write $STATE/low; cannot count low readings"; exit 0; }
    log "on battery at ${BAT_CAP}% (threshold ${THRESHOLD}%); shutting down next minute if still low"
    exit 0
fi

touch "$STATE/fired" 2>/dev/null || log "cannot write $STATE/fired; shutting down anyway"
log "on battery at ${BAT_CAP}% for two checks in a row; shutting down cleanly now"
# shellcheck disable=SC2086  # SHUTDOWN is a command line and is split on purpose
if ! out=$($SHUTDOWN "battery-guard: battery at ${BAT_CAP}%, clean shutdown to protect the node" </dev/null 2>&1); then
    log "shutdown FAILED ($out); will try again next minute"
    rm -f "$STATE/fired" 2>/dev/null
fi
exit 0
