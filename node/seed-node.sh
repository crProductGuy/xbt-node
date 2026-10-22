#!/usr/bin/env bash
# seed-node.sh: bring up a Bitcoin Knots node on Linux from the snapshot on this drive.
# FOR BOTH DEVUAN AND UBUNTU. Full instructions: README-LINUX-NODE.txt on the drive.
#
# The drive holds blocks/, chainstate/ and chainstate.sha256, all taken from one clean
# shutdown at height 977438 (2026-10-15 22:29 UTC). This script leaves the block files on the
# drive, copies chainstate/ and blocks/index/ to the internal disk, and proves the node opens them.
#
# HOW TO RUN (as the user who will run the node, NOT as root):
#   1. Install the SAME Blake2b-fork build of Bitcoin Knots the source PC runs
#      (v29.4.2.knots20260508 or newer). Stock Knots reports the same version string
#      and this script cannot tell them apart. Do not start it.
#   2. Plug in the drive. Copy this script off it:   cp /path/to/drive/seed-node.sh ~/
#   3. bash ~/seed-node.sh
#
# It stops at the first failure and is safe to run again: finished stages are skipped.
# It never deletes anything on the drive and never overwrites an existing chainstate
# or bitcoin.conf. It was written on Windows and has NOT been run on Linux yet.
#
# The drive is ext4, labelled knots-blocks. Its files were written by root, so stage 1
# hands them to the user running this script.
#
# Optional overrides:  DEV=/dev/sdX1  BITCOIND=/path/bitcoind  BITCOIN_CLI=/path/bitcoin-cli
#                      DATADIR=/path/to/datadir   (default ~/.bitcoin)
#                      SKIP_FULL_CHECK=1          (skip the SHA-256 check of all block files)

set -euo pipefail

MNT=/mnt/passport
LABEL=knots-blocks
DATADIR=${DATADIR:-$HOME/.bitcoin}
MANIFEST="$MNT/chainstate.sha256"
BLOCKS_MANIFEST="$MNT/blocks.sha256"
MARKER="$MNT/seed-node.node-has-run"
FULL_CHECK_DONE="$MNT/seed-node.full-check-passed"
COPIED="$DATADIR/seed-node.copied"
EXPECT_HEIGHT=977438
EXPECT_HASH=0000000000000000480223f956923f33bd415771a33e7ccb404a591d3c260660
MIN_VERSION=29.4.2
SNAPSHOT_EPOCH=1792022400   # 2026-10-15 00:00 UTC
DBCACHE=1500

say()     { printf '\n== %s\n' "$*"; }
ok()      { printf '   ok: %s\n' "$*"; }
die()     { printf '\nSTOPPED: %s\n' "$*" >&2; exit 1; }
confirm() { local a; read -r -p "   $1 [y/N] " a; [[ $a == y || $a == Y ]] || die "stopped at your request"; }
node_running() { pgrep -x bitcoind >/dev/null 2>&1 || pgrep -x bitcoin-qt >/dev/null 2>&1; }

# ---------------------------------------------------------------- stage 0: preflight
say "Stage 0: preflight"

[[ $(id -u) -ne 0 ]] || die "run this as the user who will run the node, not as root"

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ ! -f "$SELF_DIR/chainstate.sha256" ]] || die "this script is running from the drive. Copy it to your home directory first: cp '$SELF_DIR/seed-node.sh' ~/ && bash ~/seed-node.sh"

[[ $(uname -m) == x86_64 ]] || die "this machine reports $(uname -m), expected x86_64"
ok "architecture x86_64"

for t in sha256sum lsblk findmnt mount pgrep sort; do
  command -v "$t" >/dev/null || die "missing tool: $t"
done
command -v sudo >/dev/null || die "sudo is not installed. Install it and add this user to it (as root: apt install sudo; adduser $USER sudo; then log out and in)"

BITCOIND=${BITCOIND:-$(command -v bitcoind || true)}
BITCOIN_CLI=${BITCOIN_CLI:-$(command -v bitcoin-cli || true)}
[[ -x $BITCOIND ]]    || die "bitcoind not found. Put it on PATH or set BITCOIND=/path/to/bitcoind"
[[ -x $BITCOIN_CLI ]] || die "bitcoin-cli not found. Put it on PATH or set BITCOIN_CLI=/path/to/bitcoin-cli"

VERLINE=$("$BITCOIND" -version | head -n1)
echo "   $VERLINE"
[[ $VERLINE == *Knots* ]] || die "this is not Bitcoin Knots. The snapshot came from Knots with consensusrules=rdts; another client may accept it and then leave this chain"
VER=$(sed -n 's/.*v\([0-9][0-9.]*\)\.knots.*/\1/p' <<<"$VERLINE")
[[ -n $VER ]] || die "could not read a version number from: $VERLINE"
[[ $(printf '%s\n%s\n' "$MIN_VERSION" "$VER" | sort -V | head -n1) == "$MIN_VERSION" ]] || die "Knots $VER is older than $MIN_VERSION. An older version cannot open this chainstate"
ok "Knots $VER is $MIN_VERSION or newer"

node_running && die "bitcoind or bitcoin-qt is already running. Stop it first"
ok "no node running"

[[ $(date +%s) -ge $SNAPSHOT_EPOCH ]] || die "the system clock says $(date -u), which is before the snapshot was taken. Fix the clock (install an NTP client) and run again"
ok "clock is $(date -u)"

# ---------------------------------------------------------------- stage 1: mount the drive
say "Stage 1: mount the drive at $MNT"

if [[ $(findmnt -n -o FSTYPE "$MNT" 2>/dev/null || true) == ext4 ]]; then
  ok "already mounted"
else

  if [[ -z ${DEV:-} ]]; then
    mapfile -t CAND < <(lsblk -rno PATH,FSTYPE,LABEL | awk -v l="$LABEL" '$2=="ext4" && $3==l{print $1}')
    [[ ${#CAND[@]} -gt 0 ]] || die "no ext4 partition labelled $LABEL found. Is the drive plugged in? See: lsblk -f"
    [[ ${#CAND[@]} -eq 1 ]] || die "more than one ext4 partition labelled $LABEL found (${CAND[*]}). Run again with DEV=/dev/sdX1"
    DEV=${CAND[0]}
  fi
  [[ -b $DEV ]] || die "$DEV is not a block device"
  UUID=$(lsblk -rno UUID "$DEV")
  [[ -n $UUID ]] || die "could not read a UUID from $DEV"
  echo "   drive: $DEV   size: $(lsblk -rno SIZE "$DEV")   UUID: $UUID"
  FSTAB_LINE="UUID=$UUID $MNT ext4 noatime,nofail 0 2"
  echo "   this will: unmount $DEV from wherever the desktop mounted it,"
  echo "              create $MNT and mark it immutable (so a missing drive cannot be written around),"
  echo "              back up /etc/fstab and add:  $FSTAB_LINE"
  confirm "Proceed?"

  while read -r tgt; do
    [[ -n $tgt ]] && sudo umount "$tgt"
  done < <(findmnt -rn -o TARGET -S "$DEV" || true)

  if [[ ! -d $MNT ]]; then sudo mkdir -p "$MNT"; fi
  [[ -z $(ls -A "$MNT") ]] || die "$MNT is not empty and nothing is mounted there. Move its contents away first"
  sudo chattr +i "$MNT" 2>/dev/null || echo "   note: could not mark $MNT immutable on this filesystem; continuing"

  if grep -q "UUID=$UUID" /etc/fstab; then
    ok "/etc/fstab already has an entry for this drive"
  elif grep -qE "[[:space:]]$MNT[[:space:]]" /etc/fstab; then
    die "/etc/fstab already uses $MNT for something else. Fix that by hand"
  else
    sudo cp -p /etc/fstab "/etc/fstab.before-seed-node"
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
    ok "fstab updated, backup at /etc/fstab.before-seed-node"
  fi

  sudo mount "$MNT"
  [[ $(findmnt -n -o FSTYPE "$MNT") == ext4 ]] || die "mount did not take effect"
  ok "mounted"
fi

[[ -f $MANIFEST ]]        || die "$MANIFEST is missing. Is this the right drive?"
[[ -d $MNT/blocks/index ]] || die "$MNT/blocks/index is missing"
[[ -d $MNT/chainstate ]]   || die "$MNT/chainstate is missing"
if [[ $(stat -c %u "$MNT/blocks") -ne $(id -u) || $(stat -c %u "$MNT") -ne $(id -u) ]]; then
  echo "   the files on the drive belong to another user (they were copied by root)."
  confirm "Hand everything on $MNT to $USER?"
  sudo chown -R "$(id -u):$(id -g)" "$MNT"
  ok "ownership set"
fi
touch "$MNT/.seed-write-test" && rm "$MNT/.seed-write-test" || die "$MNT is not writable by $USER"
ok "drive is writable; $(find "$MNT/blocks" -maxdepth 1 -name 'blk*.dat' | wc -l) block files present"

# ---------------------------------------------------------------- stage 2a: full check of the block files
# Only the small files were hashed when the drive was filled. This reads every block
# file once. It has to happen before the node first runs, because the node then
# appends to the newest block file and the manifest stops matching.
if [[ -f $FULL_CHECK_DONE ]]; then
  say "Stage 2a: skipped, the block files were already checked ($(cat "$FULL_CHECK_DONE"))"
elif [[ -f $MARKER ]]; then
  say "Stage 2a: skipped, a node has already run against this drive, so blocks.sha256 no longer applies"
elif [[ -n ${SKIP_FULL_CHECK:-} ]]; then
  say "Stage 2a: skipped at your request (SKIP_FULL_CHECK). The block files are NOT verified"
else
  [[ -f $BLOCKS_MANIFEST ]] || die "$BLOCKS_MANIFEST is missing"
  say "Stage 2a: SHA-256 of all $(wc -l < "$BLOCKS_MANIFEST") block files (reads about 810 GB; 2 to 3 hours on USB 3)"
  (cd "$MNT" && sha256sum -c --quiet blocks.sha256) || die "block files on the drive do not match the manifest (listed above). Do not start the node. Refill the drive from the source PC"
  date -u +'passed %Y-%m-%dT%H:%M:%SZ' > "$FULL_CHECK_DONE"
  ok "all block files match"
fi

# ---------------------------------------------------------------- stage 2 and 3: verify, copy, verify
# Knots keeps blocks/index in the data directory even when blocksdir is set (doc/files.md:
# "-blocksdir option does not affect this path"), so chainstate/ AND blocks/index/ come to
# the internal disk. Only blk, rev and xor.dat stay on the drive. The drive's own copies
# are never written by the node, so chainstate.sha256 stays valid for them forever.
SMALL='  (chainstate|blocks/index)/'
if [[ -f $COPIED ]]; then
  say "Stage 2 and 3: skipped, chainstate and blocks/index were already copied ($(cat "$COPIED"))"
else
  for d in chainstate blocks indexes; do
    [[ ! -e $DATADIR/$d ]] || die "$DATADIR/$d already exists (from a sync the node began on its own, or an interrupted run). A partial sync the node can download again; delete it:  rm -r $DATADIR/$d"
  done
  say "Stage 2: verify the drive against the manifest (reads about 11 GB)"
  (cd "$MNT" && sha256sum -c --quiet chainstate.sha256) || die "the drive does not match the manifest. Do not start the node. Re-copy from the source PC"
  ok "all $(wc -l < "$MANIFEST") files on the drive match"

  say "Stage 3: copy chainstate and blocks/index to $DATADIR and verify the copy"
  NEED_KB=$(du -sk "$MNT/chainstate" "$MNT/blocks/index" | awk '{s+=$1} END{print s}')
  mkdir -p "$DATADIR"; chmod 700 "$DATADIR"
  FREE_KB=$(df -Pk "$DATADIR" | awk 'NR==2{print $4}')
  [[ $FREE_KB -gt $((NEED_KB * 2)) ]] || die "not enough free space in $DATADIR: need $((NEED_KB*2/1048576)) GB, have $((FREE_KB/1048576)) GB"
  STAGING="$DATADIR/.seed-staging"
  [[ ! -e $STAGING ]] || die "$STAGING is left over from an interrupted run. Remove it (rm -r '$STAGING') and run again"
  mkdir -p "$STAGING/blocks"
  cp -r "$MNT/chainstate" "$STAGING/"
  cp -r "$MNT/blocks/index" "$STAGING/blocks/"
  (cd "$STAGING" && grep -E "$SMALL" "$MANIFEST" | sha256sum -c --quiet) || die "the copy on the internal disk does not match. Suspect the internal disk or RAM. $STAGING left in place for inspection"
  [[ $(find "$STAGING/chainstate" "$STAGING/blocks/index" -type f | wc -l) -eq $(grep -cE "$SMALL" "$MANIFEST") ]] || die "file count in the copy differs from the manifest"
  chmod 700 "$STAGING/chainstate" "$STAGING/blocks" "$STAGING/blocks/index"
  chmod 600 "$STAGING/chainstate"/* "$STAGING/blocks/index"/*
  mv "$STAGING/blocks" "$DATADIR/blocks"
  mv "$STAGING/chainstate" "$DATADIR/chainstate"
  rmdir "$STAGING"
  sync
  date -u +'copied %Y-%m-%dT%H:%M:%SZ' > "$COPIED"
  ok "chainstate and blocks/index copied and verified"
fi

# ---------------------------------------------------------------- stage 4: bitcoin.conf
say "Stage 4: bitcoin.conf"
CONF="$DATADIR/bitcoin.conf"
if [[ -f $CONF ]]; then
  echo "   $CONF exists and was not changed. Checking it:"
  grep -qE "^blocksdir=$MNT/?$" "$CONF"   || die "it lacks: blocksdir=$MNT"
  ok "blocksdir is set"
  # This node follows the strict Blake2b chain (XBT) under rdts rules, like the source PC
  # (which keeps it in settings.json). blake2b_headline is regtest-only and not needed.
  grep -qE '^consensusrules=rdts$|"consensusrules": *"rdts"' "$CONF" "$DATADIR/settings.json" 2>/dev/null || die "consensusrules=rdts is not set in $CONF or settings.json. Add the line consensusrules=rdts to $CONF"
  ok "consensusrules=rdts is set"
else
  cat > "$CONF" <<EOF
# Written by seed-node.sh. Block files stay on the external drive; Knots adds blocks/ itself.
blocksdir=$MNT
# Strict spam-hostile Blake2b chain (XBT), same rules as the source PC. Do not remove.
consensusrules=rdts
maxuploadtarget=1000
dbcache=$DBCACHE
EOF
  chmod 600 "$CONF"
  ok "written"
fi

# ---------------------------------------------------------------- stage 5: offline start
say "Stage 5: start once with no network and check the node opens at height $EXPECT_HEIGHT or later"
node_running && die "a node started while this script was running"
# From here on blocks/index on the drive no longer matches the manifest. Record that.
date -u +'a node was started against this drive: %Y-%m-%dT%H:%M:%SZ' >> "$MARKER"
"$BITCOIND" -datadir="$DATADIR" -connect=0 -daemonwait || { tail -n 30 "$DATADIR/debug.log" 2>/dev/null || true; die "the node did not start. The log tail is above. Do NOT add -reindex yet; read the error first"; }

HEIGHT=""
for _ in $(seq 1 120); do
  HEIGHT=$("$BITCOIN_CLI" -datadir="$DATADIR" getblockcount 2>/dev/null || true)
  [[ -n $HEIGHT ]] && break
  sleep 5
done
HASH=$("$BITCOIN_CLI" -datadir="$DATADIR" getblockhash "$EXPECT_HEIGHT" 2>/dev/null || true)
echo "   height now:             ${HEIGHT:-none}"
echo "   hash at $EXPECT_HEIGHT:  ${HASH:-none}"

"$BITCOIN_CLI" -datadir="$DATADIR" stop >/dev/null 2>&1 || true
for _ in $(seq 1 120); do node_running || break; sleep 5; done
node_running && die "the node did not stop within 10 minutes. Wait for 'Shutdown: done' in $DATADIR/debug.log before doing anything else"

[[ $HEIGHT =~ ^[0-9]+$ && $HEIGHT -ge $EXPECT_HEIGHT ]] || die "expected height $EXPECT_HEIGHT or later, got '${HEIGHT:-nothing}'. See $DATADIR/debug.log"
[[ $HASH == "$EXPECT_HASH" ]] || die "the block at height $EXPECT_HEIGHT is not the one the source PC had. See $DATADIR/debug.log"
grep -q 'Shutdown: done' "$DATADIR/debug.log" || die "no clean 'Shutdown: done' in the log"
ok "node opened the snapshot at the expected block and shut down cleanly"

# ---------------------------------------------------------------- done
say "Done. The node is ready."
cat <<EOF
   Start it:        $BITCOIND -datadir=$DATADIR -daemon
   Watch catch-up:  $BITCOIN_CLI -datadir=$DATADIR getblockchaininfo     (wait for "initialblockdownload": false)
   Stop it:         $BITCOIN_CLI -datadir=$DATADIR stop                  (wait for 'Shutdown: done' in the log)

   Always stop the node before shutting down or unplugging the drive.
   $MNT/chainstate on the drive is your restore point. If the internal copy is ever damaged,
   stop the node, move $DATADIR/chainstate, $DATADIR/blocks and $COPIED away, and run this script again.
EOF
