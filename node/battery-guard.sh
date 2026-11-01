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
# Wake-up after an outage: this laptop's BIOS has no "power on when AC returns" setting.
# So before shutting down, the guard sets the RTC wake alarm (rtcwake -m no) for
# WAKE_MINUTES later. If the power is back by then, the machine boots and the node and
# gateway start as usual; if not, it boots on battery and the guard shuts it down again
# two checks later, setting the next alarm. Below WAKE_FLOOR % it sets no alarm, so the
# battery is never run flat by repeated boots; the power button is then the only way on.
# A failed or missing rtcwake never stops the shutdown.
#
# Settings: /etc/default/battery-guard may hold these lines (others are ignored):
#   THRESHOLD=<5..50>        shut down at or below this %       (default 25)
#   WAKE_MINUTES=<0|10..1440> wake alarm after shutdown, 0 = off (default 60)
#   WAKE_FLOOR=<3..50>       no wake alarm at or below this %    (default 10)
# For tests only, these environment variables replace the system paths:
#   BG_POWER_SUPPLY  (default /sys/class/power_supply)
#   BG_STATE_DIR     (default /run/battery-guard)
#   BG_CONFIG        (default /etc/default/battery-guard)
#   BG_SHUTDOWN      (default "/sbin/shutdown -h now")
#   BG_RTCWAKE       (default /usr/sbin/rtcwake)
#   BG_UPTIME        (default /proc/uptime; the guard does not act in the first 5 minutes)
set -u

PS=${BG_POWER_SUPPLY:-/sys/class/power_supply}
STATE=${BG_STATE_DIR:-/run/battery-guard}
CONFIG=${BG_CONFIG:-/etc/default/battery-guard}
SHUTDOWN=${BG_SHUTDOWN:-/sbin/shutdown -h now}
RTCWAKE=${BG_RTCWAKE:-/usr/sbin/rtcwake}
UPTIME_FILE=${BG_UPTIME:-/proc/uptime}
MIN_UPTIME=300

log() { logger -t battery-guard -- "$*" 2>/dev/null || echo "battery-guard: $*" >&2; }

# The config file is parsed, never sourced: only a plain NAME=<number> line counts.
# read_setting NAME DEFAULT MIN MAX  prints the value, or DEFAULT if missing or out of range.
read_setting() {
    v=""
    [ -r "$CONFIG" ] && v=$(sed -n "s/^$1=\([0-9][0-9]*\)[[:space:]]*\$/\1/p" "$CONFIG" | tail -n 1)
    case $v in
        ''|*[!0-9]*) echo "$2"; return ;;
    esac
    v=${v#"${v%%[!0]*}"}; [ -n "$v" ] || v=0   # drop leading zeros: $(( )) would read 010 as octal
    if [ "$v" -ge "$3" ] && [ "$v" -le "$4" ]; then echo "$v"; else echo "$2"; fi
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

THRESHOLD=$(read_setting THRESHOLD 25 5 50)
WAKE_MINUTES=$(read_setting WAKE_MINUTES 60 0 1440)
[ "$WAKE_MINUTES" -gt 0 ] && [ "$WAKE_MINUTES" -lt 10 ] && WAKE_MINUTES=60
WAKE_FLOOR=$(read_setting WAKE_FLOOR 10 3 50)
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
    if [ "$WAKE_MINUTES" -eq 0 ]; then echo "wake alarm: off"
    elif [ "$WAKE_FLOOR" -ge "$THRESHOLD" ]; then
        echo "wake alarm: never set, because WAKE_FLOOR $WAKE_FLOOR % is not below THRESHOLD $THRESHOLD %"
    else echo "wake alarm: $WAKE_MINUTES min after a guard shutdown, unless at or below $WAKE_FLOOR %"
    fi
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

# Just after a boot (for example one woken by the alarm, still on battery) the node may
# still be starting: its pidfile may not exist yet, and a stop then could miss it. So
# nothing counts until the machine has been up MIN_UPTIME seconds.
up=$(cut -d. -f1 "$UPTIME_FILE" 2>/dev/null | cut -d' ' -f1)
case $up in ''|*[!0-9]*) up=0 ;; esac
if [ "$up" -lt "$MIN_UPTIME" ]; then
    rm -f "$STATE/low" 2>/dev/null
    exit 0
fi

if [ ! -e "$STATE/low" ]; then
    # touch, not ": >": dash exits on a failed redirect of a special builtin
    touch "$STATE/low" 2>/dev/null || { log "cannot write $STATE/low; cannot count low readings"; exit 0; }
    log "on battery at ${BAT_CAP}% (threshold ${THRESHOLD}%); shutting down next minute if still low"
    exit 0
fi

touch "$STATE/fired" 2>/dev/null || log "cannot write $STATE/fired; shutting down anyway"
if [ "$WAKE_MINUTES" -eq 0 ]; then
    :
elif [ "$BAT_CAP" -le "$WAKE_FLOOR" ]; then
    log "battery at ${BAT_CAP}%, at or below the wake floor ${WAKE_FLOOR}%: no wake alarm, it stays off until the power button"
elif w=$("$RTCWAKE" -m no -s $((WAKE_MINUTES * 60)) </dev/null 2>&1); then
    log "wake alarm set for ${WAKE_MINUTES} min from now"
else
    log "wake alarm FAILED ($w); shutting down anyway, it stays off until the power button"
fi
log "on battery at ${BAT_CAP}% for two checks in a row; shutting down cleanly now"
# shellcheck disable=SC2086  # SHUTDOWN is a command line and is split on purpose
if ! out=$($SHUTDOWN "battery-guard: battery at ${BAT_CAP}%, clean shutdown to protect the node" </dev/null 2>&1); then
    log "shutdown FAILED ($out); will try again next minute"
    rm -f "$STATE/fired" 2>/dev/null
fi
exit 0
