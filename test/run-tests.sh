#!/usr/bin/env bash
# run-tests.sh: tests for make-manifest.ps1 and the TEST mode of make-ext4-seed.sh.
# Runs in Git Bash on Windows. Needs pwsh. Touches only the directory given as $1.
#   bash test/run-tests.sh <empty scratch dir>
set -uo pipefail

WORK=${1:?give an empty scratch directory}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -z $(ls -A "$WORK" 2>/dev/null) ]] || { echo "scratch directory is not empty: $WORK"; exit 2; }
PASS=0; FAIL=0
check() { if [[ $2 == "$3" ]]; then PASS=$((PASS+1)); echo "pass: $1"; else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected $3, got $2)"; fi; }
seed() { TEST_SRC="$WORK/src" TEST_DST="$1" TEST_STAGE="$WORK/stage" bash "$HERE/seed/make-ext4-seed.sh" > "$WORK/out.txt" 2>&1; echo $?; }

mkdir -p "$WORK/src/blocks/index" "$WORK/src/chainstate" "$WORK/stage"
: > "$WORK/src/blocks/.lock"   # the node keeps an empty lock file here
for f in blocks/blk00000.dat blocks/rev00000.dat blocks/blk00001.dat blocks/xor.dat \
         blocks/index/000003.log blocks/index/CURRENT chainstate/000005.ldb chainstate/MANIFEST-000004; do
  head -c 4096 /dev/urandom > "$WORK/src/$f"
done
echo "a doc" > "$WORK/stage/README-LINUX-NODE.txt"

pwsh -NoProfile -File "$HERE/seed/make-manifest.ps1" -BitcoinDir "$(cygpath -w "$WORK/src")" -OutDir "$(cygpath -w "$WORK/stage")" -Test > "$WORK/manifest-out.txt" 2>&1
check "manifest script exits 0" $? 0
check "chainstate.sha256 has 5 lines" "$(wc -l < "$WORK/stage/chainstate.sha256")" 5
check "blocks.sha256 has 4 lines (incl. .lock)" "$(wc -l < "$WORK/stage/blocks.sha256")" 4

# a stray file under blocks/ is refused, and refused before any hashing
mkdir -p "$WORK/odd/blocks/index" "$WORK/odd/chainstate"
: > "$WORK/odd/blocks/stray.txt"
pwsh -NoProfile -File "$HERE/seed/make-manifest.ps1" -BitcoinDir "$(cygpath -w "$WORK/odd")" -OutDir "$(cygpath -w "$WORK/oddout")" -Test > "$WORK/odd-out.txt" 2>&1
check "stray file under blocks/ is refused" $? 1
check "  before hashing starts" "$(grep -c 'hashing' "$WORK/odd-out.txt")" 0
check "manifests have no CR" "$(cat "$WORK/stage"/*.sha256 | tr -cd '\r' | wc -c)" 0
check "sha256sum accepts both manifests against the source" \
  "$(cd "$WORK/src" && sha256sum -c --quiet chainstate.sha256 --status < /dev/null 2>/dev/null; cd "$WORK/src" && cat "$WORK/stage/chainstate.sha256" "$WORK/stage/blocks.sha256" | sha256sum -c --quiet - >/dev/null 2>&1; echo $?)" 0

check "clean copy passes" "$(seed "$WORK/dst1")" 0
check "docs were copied to the drive root" "$(test -f "$WORK/dst1/README-LINUX-NODE.txt" && test -f "$WORK/dst1/blocks.sha256"; echo $?)" 0
check "second run on the same target passes (resume)" "$(seed "$WORK/dst1")" 0

# a file in the small manifest that is corrupt on the target, same size: must fail on SHA-256
mkdir -p "$WORK/dst2/chainstate" "$WORK/dst2/blocks"
cp -r "$WORK/src/." "$WORK/dst2/"
head -c 4096 /dev/urandom > "$WORK/src-corrupt.bin"
cp "$WORK/stage/chainstate.sha256" "$WORK/stage/chainstate.sha256.good"
sed -i '1s/^[0-9a-f]\{8\}/00000000/' "$WORK/stage/chainstate.sha256"
check "wrong SHA-256 in the manifest is caught" "$(seed "$WORK/dst3")" 1
check "  and the message names SHA-256" "$(grep -c 'does not match its SHA-256' "$WORK/out.txt")" 1
mv "$WORK/stage/chainstate.sha256.good" "$WORK/stage/chainstate.sha256"

# the source gained a file after the manifests were made: must refuse before copying
head -c 4096 /dev/urandom > "$WORK/src/blocks/blk00002.dat"
check "source newer than the manifests is refused" "$(seed "$WORK/dst4")" 1
check "  and nothing was copied" "$(test -e "$WORK/dst4/blocks"; echo $?)" 1
rm "$WORK/src/blocks/blk00002.dat"

# CRLF manifest: must refuse
sed -i 's/$/\r/' "$WORK/stage/blocks.sha256"
check "CRLF manifest is refused" "$(seed "$WORK/dst5")" 1
sed -i 's/\r$//' "$WORK/stage/blocks.sha256"

# outside TEST mode the Windows user and the drive serial must be given; refused before stage 0
real() { env -u TEST_SRC -u TEST_DST -u WIN_USER -u EXPECT_SERIAL "$@" bash "$HERE/seed/make-ext4-seed.sh" > "$WORK/real.txt" 2>&1; echo $?; }
check "no WIN_USER is refused" "$(real)" 1
check "  and the message names WIN_USER" "$(grep -c 'WIN_USER=<name>' "$WORK/real.txt")" 1
check "no EXPECT_SERIAL is refused" "$(real WIN_USER=someone)" 1
check "  and the message names EXPECT_SERIAL" "$(grep -c 'EXPECT_SERIAL=<serial>' "$WORK/real.txt")" 1
check "  before stage 0" "$(grep -c 'Stage 0' "$WORK/real.txt")" 0

# hex form of the serial, as a WD USB bridge reports it
check "hex_of matches the known hex of the serial" \
  "$(bash -c "$(sed -n '/^hex_of()/p' "$HERE/seed/make-ext4-seed.sh"); hex_of WD0000TEST01")" 574430303030544553543031

# battery-guard.sh against a fake power_supply tree; the "shutdown" only appends to a file
BG="$WORK/bg"; mkdir -p "$BG/ps/ACAD" "$BG/ps/BAT0"
echo Mains > "$BG/ps/ACAD/type"; echo Battery > "$BG/ps/BAT0/type"
printf '#!/bin/sh\necho "$*" >> "%s/shutdown-calls"\n' "$BG" > "$BG/fake-shutdown"; chmod +x "$BG/fake-shutdown"
power() { echo "$1" > "$BG/ps/ACAD/online"; echo "$2" > "$BG/ps/BAT0/status"; echo "$3" > "$BG/ps/BAT0/capacity"; }
# Devuan runs /bin/sh = dash; use it when present so the tests run the shell that matters.
GSH=$(command -v dash || echo sh)
printf '#!/bin/sh\necho "$*" >> "%s/wake-calls"\necho wake >> "%s/order"\n' "$BG" "$BG" > "$BG/fake-rtcwake"; chmod +x "$BG/fake-rtcwake"
printf '#!/bin/sh\necho "no RTC" >&2\nexit 1\n' > "$BG/failing-rtcwake"; chmod +x "$BG/failing-rtcwake"
printf '#!/bin/sh\necho "$*" >> "%s/hwclock-calls"\necho hwclock >> "%s/order"\n' "$BG" "$BG" > "$BG/fake-hwclock"; chmod +x "$BG/fake-hwclock"
printf '#!/bin/sh\necho "no RTC" >&2\nexit 1\n' > "$BG/failing-hwclock"; chmod +x "$BG/failing-hwclock"
printf '#!/bin/sh\necho shutdown >> "%s/order"\n' "$BG" >> "$BG/fake-shutdown"
guard() { BG_POWER_SUPPLY="$BG/ps" BG_STATE_DIR="$BG/state" BG_CONFIG="$BG/conf" BG_SHUTDOWN="${FAKE_SD:-$BG/fake-shutdown}" \
          BG_RTCWAKE="${FAKE_WAKE:-$BG/fake-rtcwake}" BG_HWCLOCK="${FAKE_HWC:-$BG/fake-hwclock}" BG_UPTIME="${FAKE_UP:-$BG/uptime}" "$GSH" "$HERE/node/battery-guard.sh" "$@" 2>>"$BG/log"; }
calls() { if [[ -f $BG/shutdown-calls ]]; then wc -l < "$BG/shutdown-calls" | tr -d ' '; else echo 0; fi; }
echo "86400.50 100.00" > "$BG/uptime"
wakes() { if [[ -f $BG/wake-calls ]]; then wc -l < "$BG/wake-calls" | tr -d ' '; else echo 0; fi; }
reset_bg() { rm -rf "$BG/state" "$BG/shutdown-calls" "$BG/wake-calls" "$BG/hwclock-calls" "$BG/order" "$BG/conf"; }
hwcs() { if [[ -f $BG/hwclock-calls ]]; then wc -l < "$BG/hwclock-calls" | tr -d ' '; else echo 0; fi; }

reset_bg; power 1 Charging 10; guard; guard
check "guard: on AC at 10 % never shuts down" "$(calls)" 0
reset_bg; power 0 Discharging 60; guard; guard
check "guard: on battery at 60 % does nothing" "$(calls)" 0
reset_bg; power 0 Discharging 20; guard
check "guard: first low reading does not act" "$(calls)" 0
guard
check "guard: second low reading in a row shuts down once" "$(calls)" 1
check "  with a reason naming the battery level" "$(grep -c 'battery at 20%' "$BG/shutdown-calls")" 1
guard; guard
check "guard: does not ask for shutdown again after firing" "$(calls)" 1
reset_bg; power 0 Discharging 20; guard; power 1 Charging 20; guard; power 0 Discharging 20; guard
check "guard: AC returning in between resets the count" "$(calls)" 0
reset_bg; power 0 Discharging 25; guard; guard
check "guard: exactly at the default threshold 25 % acts" "$(calls)" 1
reset_bg; power 0 Discharging 26; guard; guard
check "guard: just above the threshold does nothing" "$(calls)" 0
reset_bg; power 0 Discharging abc; guard; guard
check "guard: unreadable capacity does nothing" "$(calls)" 0
reset_bg; power 0 Discharging ''; guard; guard
check "guard: empty capacity does nothing" "$(calls)" 0
reset_bg; power 0 Full 10; guard; guard
check "guard: battery not discharging does nothing" "$(calls)" 0
reset_bg; power 0 Discharging 40; echo THRESHOLD=45 > "$BG/conf"; guard; guard
check "guard: THRESHOLD from the config file is used" "$(calls)" 1
reset_bg; power 0 Discharging 40; printf 'THRESHOLD=99\n' > "$BG/conf"; guard; guard
check "guard: out-of-range THRESHOLD falls back to 25" "$(calls)" 0
reset_bg; power 0 Discharging 40; printf 'THRESHOLD=45; touch %s/pwned\n' "$BG" > "$BG/conf"; guard; guard
check "guard: config file is parsed, not run" "$(test -e "$BG/pwned"; echo $?)" 1
check "  and a malformed line falls back to 25" "$(calls)" 0
reset_bg; power 0 Discharging 5; guard --status > "$BG/status.txt"; guard --status >> "$BG/status.txt"
check "guard --status never shuts down" "$(calls)" 0
check "  and reports LOW" "$(grep -c 'decision: LOW' "$BG/status.txt")" 2
reset_bg; rm -rf "$BG/ps/ACAD"; power2() { echo Discharging > "$BG/ps/BAT0/status"; echo 5 > "$BG/ps/BAT0/capacity"; }; power2; guard; guard
check "guard: no mains adapter found does nothing" "$(calls)" 0
mkdir -p "$BG/ps/ACAD"; echo Mains > "$BG/ps/ACAD/type"
reset_bg; power 0 Discharging 20; guard; guard; power 1 Charging 30; guard; power 0 Discharging 20; guard; guard
check "guard: a second low spell after AC returned fires again" "$(calls)" 2
reset_bg; power 0 Discharging 20; guard; echo xx > "$BG/ps/BAT0/capacity"; guard; power 0 Discharging 20; guard
check "guard: an unreadable reading between two lows resets the count" "$(calls)" 0
reset_bg; mkdir -p "$BG/ps/0mouse"; echo Battery > "$BG/ps/0mouse/type"; echo Device > "$BG/ps/0mouse/scope"
echo Discharging > "$BG/ps/0mouse/status"; echo 3 > "$BG/ps/0mouse/capacity"; power 0 Discharging 90; guard; guard
check "guard: a wireless-device battery is ignored" "$(calls)" 0
rm -rf "$BG/ps/0mouse"
printf '#!/bin/sh\necho "$*" >> "%s/shutdown-calls"\nexit 1\n' "$BG" > "$BG/failing-shutdown"; chmod +x "$BG/failing-shutdown"
reset_bg; : > "$BG/log"; power 0 Discharging 20; FAKE_SD="$BG/failing-shutdown" guard; FAKE_SD="$BG/failing-shutdown" guard; FAKE_SD="$BG/failing-shutdown" guard
check "guard: a failed shutdown is retried next minute" "$(calls)" 2
check "  and the failure is logged" "$(grep -c 'shutdown FAILED' "$BG/log")" 2
# wake alarm before a guard shutdown (the BIOS has no power-on-after-AC-loss setting)
reset_bg; power 0 Discharging 20; guard; guard
check "wake: a guard shutdown sets the alarm once, 60 min by default" "$(wakes) $(cat "$BG/wake-calls")" "1 -m no -s 3600"
check "  and saves the time to the RTC first, then the alarm, then the shutdown" "$(tr '\n' ' ' < "$BG/order")" "hwclock wake shutdown "
check "  with hwclock --systohc (keeps the local or UTC choice in /etc/adjtime)" "$(cat "$BG/hwclock-calls")" "--systohc"
guard
check "  and not again once fired" "$(wakes)" 1
reset_bg; power 0 Discharging 60; guard; guard; power 1 Charging 5; guard; guard
check "wake: no alarm when not shutting down" "$(wakes)" 0
reset_bg; power 0 Discharging 20; guard
check "wake: no alarm on the first low reading" "$(wakes)" 0
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=120\n' > "$BG/conf"; guard; guard
check "wake: WAKE_MINUTES from the config file is used" "$(cat "$BG/wake-calls")" "-m no -s 7200"
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=5\n' > "$BG/conf"; guard; guard
check "wake: WAKE_MINUTES below 10 falls back to 60" "$(cat "$BG/wake-calls")" "-m no -s 3600"
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=0\n' > "$BG/conf"; guard; guard
check "wake: WAKE_MINUTES=0 sets no alarm" "$(wakes)" 0
check "  and still shuts down" "$(calls)" 1
reset_bg; : > "$BG/log"; power 0 Discharging 10; guard; guard
check "wake: at the floor (10 %) sets no alarm" "$(wakes)" 0
check "  and still shuts down" "$(calls)" 1
check "  and says why in the log" "$(grep -c 'wake floor' "$BG/log")" 1
reset_bg; power 0 Discharging 11; guard; guard
check "wake: just above the floor sets the alarm" "$(wakes)" 1
reset_bg; power 0 Discharging 20; printf 'THRESHOLD=40\nWAKE_FLOOR=30\n' > "$BG/conf"; guard; guard
check "wake: WAKE_FLOOR from the config file is used" "$(wakes) $(calls)" "0 1"
reset_bg; : > "$BG/log"; power 0 Discharging 20; FAKE_WAKE="$BG/failing-rtcwake" guard; FAKE_WAKE="$BG/failing-rtcwake" guard
check "wake: a failing rtcwake does not stop the shutdown" "$(calls)" 1
check "  and the failure is logged" "$(grep -c 'wake alarm FAILED' "$BG/log")" 1
reset_bg; power 0 Discharging 20; FAKE_WAKE="$BG/no-such-rtcwake" guard; FAKE_WAKE="$BG/no-such-rtcwake" guard
check "wake: a missing rtcwake does not stop the shutdown" "$(calls)" 1
reset_bg; : > "$BG/log"; power 0 Discharging 20; FAKE_HWC="$BG/failing-hwclock" guard; FAKE_HWC="$BG/failing-hwclock" guard
check "rtc: a failing hwclock still sets the alarm and shuts down" "$(wakes) $(calls)" "1 1"
check "  and the failure is logged" "$(grep -c 'saving the time to the RTC FAILED' "$BG/log")" 1
reset_bg; power 0 Discharging 20; FAKE_HWC="$BG/no-such-hwclock" guard; FAKE_HWC="$BG/no-such-hwclock" guard
check "rtc: a missing hwclock still sets the alarm and shuts down" "$(wakes) $(calls)" "1 1"
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=0\n' > "$BG/conf"; guard; guard
check "rtc: no hwclock write when the alarm is off" "$(hwcs) $(calls)" "0 1"
reset_bg; power 0 Discharging 10; guard; guard
check "rtc: no hwclock write at the wake floor" "$(hwcs) $(calls)" "0 1"
reset_bg; power 0 Discharging 20; guard
check "rtc: no hwclock write on the first low reading" "$(hwcs)" 0
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=60; touch %s/pwned2\n' "$BG" > "$BG/conf"; guard; guard
check "wake: config is parsed, not run" "$(test -e "$BG/pwned2"; echo $?) $(cat "$BG/wake-calls")" "1 -m no -s 3600"
reset_bg; power 1 Charging 90; guard --status > "$BG/status.txt"
check "wake: --status names the alarm setting" "$(grep -c 'wake alarm: 60 min' "$BG/status.txt")" 1
reset_bg; power 1 Charging 90; printf 'WAKE_MINUTES=0\n' > "$BG/conf"; guard --status > "$BG/status.txt"
check "  and says off when it is off" "$(grep -c 'wake alarm: off' "$BG/status.txt")" 1
echo "120.00 50.00" > "$BG/uptime-early"
reset_bg; power 0 Discharging 20; FAKE_UP="$BG/uptime-early" guard; FAKE_UP="$BG/uptime-early" guard; FAKE_UP="$BG/uptime-early" guard
check "boot: no shutdown in the first 5 minutes after boot" "$(calls) $(wakes)" "0 0"
guard
check "  and counting starts afresh once up 5 minutes" "$(calls)" 0
guard
check "  then the second reading acts" "$(calls)" 1
reset_bg; power 0 Discharging 20; FAKE_UP="$BG/no-such-uptime" guard; FAKE_UP="$BG/no-such-uptime" guard
check "boot: unreadable uptime counts as just booted" "$(calls)" 0
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=010\n' > "$BG/conf"; guard; guard
check "wake: a leading zero is decimal, not octal" "$(cat "$BG/wake-calls")" "-m no -s 600"
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=090\n' > "$BG/conf"; guard; guard
check "  and 090 is 90, not an error" "$(cat "$BG/wake-calls")" "-m no -s 5400"
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=2000\n' > "$BG/conf"; guard; guard
check "wake: WAKE_MINUTES above 1440 falls back to 60" "$(cat "$BG/wake-calls")" "-m no -s 3600"
reset_bg; power 0 Discharging 20; printf 'WAKE_MINUTES=120\r\nTHRESHOLD=30\r\n' > "$BG/conf"; guard; guard
check "wake: a CRLF config file still reads" "$(cat "$BG/wake-calls")" "-m no -s 7200"
reset_bg; power 1 Charging 90; printf 'THRESHOLD=10\nWAKE_FLOOR=10\n' > "$BG/conf"; guard --status > "$BG/status.txt"
check "wake: --status warns when the floor is not below the threshold" "$(grep -c 'never set' "$BG/status.txt")" 1
reset_bg; power 0 Discharging 20; FAKE_SD="$BG/failing-shutdown" guard; FAKE_SD="$BG/failing-shutdown" guard; FAKE_SD="$BG/failing-shutdown" guard
check "wake: a retried shutdown sets the alarm again" "$(wakes)" 2
check "dash -n: battery-guard.sh and its installer" "$(for s in battery-guard.sh install-battery-guard.sh; do "$GSH" -n "$HERE/node/$s" 2>&1; done)" ""


# devuan-bitcoind.init drive check and install-autostart.sh's choice of MNT (D-038)
IT="$WORK/init"; mkdir -p "$IT/drive/blocks/index"
dr() { "$GSH" -c "$(sed -n '/^drive_ready()/,/^}/p' "$HERE/node/devuan-bitcoind.init")
  mountpoint() { [ \"\$2\" = \"$IT/drive\" ]; }; mount() { return 1; }; sleep() { :; }
  MNT='$1'; MOUNT_WAIT=0; drive_ready"; echo $?; }
check "init: MNT starts as 'unset', not as a setting" "$(grep -c '^MNT=@unset@$' "$HERE/node/devuan-bitcoind.init")" 1
check "init: empty MNT means ready, no wait" "$(dr '')" 0
check "init: a set MNT that is not mounted is not ready" "$(dr "$IT/missing")" 1
check "init: a mounted MNT is ready" "$(dr "$IT/drive")" 0
rmdir "$IT/drive/blocks/index"
check "init: a mounted MNT is ready without blocks/index (Knots keeps the index in the datadir)" "$(dr "$IT/drive")" 0
# mnt_problem: an /etc/default/bitcoind from before MNT existed (no MNT line at all)
mp() { "$GSH" -c "NAME=bitcoind; DATADIR='$IT/dd'; MNT='$1'
  $(sed -n '/^mnt_problem()/,/^}/p' "$HERE/node/devuan-bitcoind.init")
  mnt_problem"; echo "rc=$?"; }
mkdir -p "$IT/dd"; printf 'txindex=1\nblocksdir=/mnt/passport\n' > "$IT/dd/bitcoin.conf"
check "init: no MNT line + blocksdir in bitcoin.conf refuses to start" "$(mp @unset@ | tail -1)" "rc=1"
check "  and says what to do" "$(mp @unset@ | grep -c 'Rerun install-autostart.sh')" 1
printf 'txindex=1\n blocksdir = /mnt/passport\n' > "$IT/dd/bitcoin.conf"
check "init: blocksdir with spaces around = also refuses" "$(mp @unset@ | tail -1)" "rc=1"
printf 'txindex=1\n#blocksdir=/mnt/passport\n' > "$IT/dd/bitcoin.conf"
check "init: no MNT line and no blocksdir starts with no check" "$(mp @unset@)" "rc=0"
printf 'blocksdir=/mnt/passport\n' > "$IT/dd/bitcoin.conf"
check "init: MNT= (empty, set by the owner) with blocksdir starts" "$(mp '')" "rc=0"
check "init: MNT set with blocksdir starts (drive_ready decides)" "$(mp /mnt/passport)" "rc=0"
ds=$(sed -n '/^do_start()/,/^}/p' "$HERE/node/devuan-bitcoind.init")
check "init: do_start checks mnt_problem before the drive" "$(( $(echo "$ds" | grep -n 'mnt_problem' | cut -d: -f1) < $(echo "$ds" | grep -n 'drive_ready' | cut -d: -f1) ))" 1
check "init: header no longer says it was never run" "$(grep -ci 'not yet run' "$HERE/node/devuan-bitcoind.init")" 0
pm() { "$GSH" -c "$(sed -n '/^pick_mnt()/,/^}/p' "$HERE/node/install-autostart.sh")"'; pick_mnt "$1" "$2" "$3"' sh "$IT/conf" "$IT/fstab" "$1"; echo "rc=$?"; }
printf 'UUID=abc /mnt/passport ext4 noatime,nofail 0 2\nUUID=def / ext4 defaults 0 1\n' > "$IT/fstab"
printf 'txindex=1\nblocksdir=/mnt/passport\nconsensusrules=rdts\n' > "$IT/conf"
check "autostart: blocksdir on an fstab mount point is checked" "$(pm auto | tr '\n' ' ')" "/mnt/passport rc=0 "
printf 'txindex=1\nconsensusrules=rdts\n' > "$IT/conf"
check "autostart: no blocksdir means no drive check" "$(pm auto | tr '\n' ' ')" "rc=0 "
printf 'blocksdir=/home/nodeuser/blocks\n' > "$IT/conf"
check "autostart: blocksdir on the internal disk means no drive check" "$(pm auto | tr '\n' ' ')" "rc=0 "
printf 'blocksdir=/mnt/passport/\r\n' > "$IT/conf"
check "autostart: trailing slash and CRLF still match" "$(pm auto | tr '\n' ' ')" "/mnt/passport rc=0 "
printf '# blocksdir=/mnt/passport\n' > "$IT/conf"
check "autostart: a commented blocksdir is ignored" "$(pm auto | tr '\n' ' ')" "rc=0 "
printf 'blocksdir=/mnt/passport\n' > "$IT/conf"; printf '#UUID=abc /mnt/passport ext4 defaults 0 2\n' > "$IT/fstab"
check "autostart: a commented fstab line does not count" "$(pm auto | tr '\n' ' ')" "rc=0 "
printf 'UUID=abc /mnt/passport ext4 noatime,nofail 0 2\n' > "$IT/fstab"
check "autostart: none turns the check off" "$(pm none | tr '\n' ' ')" "rc=0 "
check "autostart: an explicit mount point is used" "$(pm /mnt/other | tr '\n' ' ')" "/mnt/other rc=0 "
check "autostart: anything else is refused" "$(pm bogus 2>/dev/null | tr '\n' ' ')" "rc=1 "
check "autostart: no longer requires blocksdir=/mnt/passport" "$(grep -c "grep -q '^blocksdir=/mnt/passport'" "$HERE/node/install-autostart.sh")" 0
check "autostart: writes MNT, quoted, to /etc/default/bitcoind" "$(grep -c "MNT='%s'" "$HERE/node/install-autostart.sh")" 1
printf 'blocksdir=/mnt/passport/bitcoin/blocks\n' > "$IT/conf"
check "autostart: blocksdir in a folder on the drive picks the drive" "$(pm auto | tr '\n' ' ')" "/mnt/passport rc=0 "
printf 'blocksdir=/mnt/passportx\n' > "$IT/conf"
check "autostart: a look-alike path does not match" "$(pm auto | tr '\n' ' ')" "rc=0 "
printf '  blocksdir = /mnt/passport\n' > "$IT/conf"
check "autostart: spaces around = still match" "$(pm auto | tr '\n' ' ')" "/mnt/passport rc=0 "
printf 'UUID=abc /mnt ext4 defaults 0 2\nUUID=def /mnt/passport ext4 nofail 0 2\nUUID=r / ext4 defaults 0 1\n' > "$IT/fstab"
printf 'blocksdir=/mnt/passport/b\n' > "$IT/conf"
check "autostart: the deepest mount point wins" "$(pm auto | tr '\n' ' ')" "/mnt/passport rc=0 "
printf 'blocksdir=/srv/blocks\n' > "$IT/conf"
check "autostart: the root filesystem never counts" "$(pm auto | tr '\n' ' ')" "rc=0 "
check "autostart: a mount point with a space is refused" "$(pm '/mnt/my drive' 2>/dev/null | tr '\n' ' ')" "rc=1 "
check "autostart: a mount point with a quote is refused" "$(pm "/mnt/it's" 2>/dev/null | tr '\n' ' ')" "rc=1 "
printf "BITCOIN_USER='nodeuser'\nMNT='/mnt/passport'\n" > "$IT/defaults"
check "autostart: the quoted defaults file sources cleanly" "$("$GSH" -c ". '$IT/defaults'; echo \"\$BITCOIN_USER \$MNT\"")" "nodeuser /mnt/passport"
for f in "$HERE/seed/make-ext4-seed.sh" "$HERE"/node/*.sh "$HERE"/node/*.init "$HERE"/test/*.sh; do
  [[ -f $f ]] || continue
  check "syntax and LF endings: $(basename "$f")" "$(bash -n "$f" 2>&1; tr -cd '\r' < "$f" | wc -c)" 0
done

# docs/non-systemd: every relative link and #anchor resolves, and the checksums match the scripts
DOCS="$HERE/docs/non-systemd"
slugs() { grep -E '^#{1,6} ' "$1" | sed -E 's/^#+ //' | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9 -]//g; s/ /-/g'; }
bad=""
for md in "$DOCS"/*.md; do
  while IFS= read -r link; do
    file=${link%%#*}; anchor=""; [[ $link == *"#"* ]] && anchor=${link#*#}
    target=$md; [[ -n $file ]] && target="$DOCS/$file"
    if [[ ! -f $target ]]; then bad+=" $(basename "$md"):$link"; continue; fi
    if [[ -n $anchor ]] && ! slugs "$target" | grep -qx -- "$anchor"; then bad+=" $(basename "$md"):$link"; fi
  done < <(grep -oE '\]\([^)]+\)' "$md" | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^[a-z]+:')
done
check "docs: every relative link and anchor resolves" "${bad:-none}" none
check "docs: the doc set has its nine pages" "$(ls "$DOCS"/*.md | wc -l | tr -d ' ')" 9
sums=""
for f in devuan-bitcoind.init devuan-datum-gateway.init install-autostart.sh battery-guard.sh install-battery-guard.sh; do
  want=$(grep -E "^[0-9a-f]{64}  $f\$" "$DOCS/reference.md" | cut -c1-64)
  have=$(sha256sum "$HERE/node/$f" | cut -c1-64)
  [[ -n $want && $want == "$have" ]] || sums+=" $f"
done
check "docs: reference.md checksums match the scripts" "${sums:-all match}" "all match"

echo; echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
