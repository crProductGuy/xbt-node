#!/usr/bin/env bash
# make-ext4-seed.sh: reformat the WD My Passport as ext4 and fill it from the Windows
# disk. Run from an Ubuntu LIVE USB session on the Windows PC, with Windows shut down.
#
# It reads the Windows disk (mounted read-only) and writes only to the Passport:
#   <drive>/blocks/        all block files, blocks/index/ and xor.dat
#   <drive>/chainstate/    seed copy of the UTXO database
#   <drive>/*              everything in to-drive/ beside this script (docs, manifests)
#
# to-drive/ is not in git. Fill it before the run: make-manifest.ps1 writes the manifests
# there, then copy the node files in with  cp ../node/* to-drive/
#
# HOW TO RUN (in the live session, Passport plugged in):
#   One command per line; each is short so it survives a paste.
#   1. Find the Windows partition: the ntfs one of about 1.8T.
#        lsblk -o NAME,SIZE,FSTYPE
#   2. Mount it read-only (replace nvme0n1p3 if step 1 shows another name):
#        sudo mkdir -p /mnt/win
#        sudo mount -o ro /dev/nvme0n1p3 /mnt/win
#   3. Go to this script and run it:
#        cd /mnt/win/<path to this repo>
#        cd seed
#        W=<Windows user>
#        S=<drive serial>
#        sudo WIN_USER=$W EXPECT_SERIAL=$S bash make-ext4-seed.sh
#
# It stops at the first failure. Safe to run again after an interruption: a drive that
# is already formatted is not formatted twice, and the copy resumes where it stopped.
# Written on Windows; only the copy and verify logic has been tested (in TEST mode).
#
# Required:  WIN_USER  the Windows account that holds AppData\Roaming\Bitcoin
#            EXPECT_SERIAL  the Passport's serial (Get-Disk on Windows shows it)
# Optional overrides:  WIN=/mnt/win   DISK=/dev/sdX   (DISK skips the serial match only)
# TEST mode, no disk and no root:  TEST_SRC=<fake Bitcoin dir> TEST_DST=<empty dir> bash make-ext4-seed.sh

set -euo pipefail

EXPECT_SERIAL=${EXPECT_SERIAL:-} # the target drive; required outside TEST mode
MIN_BYTES=1900000000000         # the Passport is 2,000,365,289,472 bytes
MAX_BYTES=2100000000000
LABEL=knots-blocks
MNT=/mnt/seed
WIN=${WIN:-/mnt/win}
WIN_USER=${WIN_USER:-}           # required outside TEST mode

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAGE="$SELF_DIR/to-drive"
LOG=""

say()  { printf '\n== %s\n' "$*"; [[ -z $LOG ]] || printf '\n== %s\n' "$*" >> "$LOG"; }
ok()   { printf '   ok: %s\n' "$*"; [[ -z $LOG ]] || printf '   ok: %s\n' "$*" >> "$LOG"; }
die()  { printf '\nSTOPPED: %s\n' "$*" >&2; [[ -z $LOG ]] || printf '\nSTOPPED: %s\n' "$*" >> "$LOG"; exit 1; }
hex_of() { printf '%s' "$1" | od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F'; }
# size and path of every file under blocks/ and chainstate/, for comparing two trees
list_tree() { (cd "$1" && find blocks chainstate -type f -printf '%s %p\n' | LC_ALL=C sort -k2); }

TEST=0
if [[ -n ${TEST_SRC:-} || -n ${TEST_DST:-} ]]; then
  [[ -n ${TEST_SRC:-} && -n ${TEST_DST:-} ]] || die "TEST mode needs both TEST_SRC and TEST_DST"
  TEST=1; SRC=$TEST_SRC; DST=$TEST_DST
  STAGE=${TEST_STAGE:-$STAGE}
else
  [[ -n $WIN_USER ]]      || die "give the Windows user: WIN_USER=<name> (see HOW TO RUN at the top)"
  [[ -n $EXPECT_SERIAL ]] || die "give the drive serial: EXPECT_SERIAL=<serial> (see HOW TO RUN at the top)"
  SRC="$WIN/Users/$WIN_USER/AppData/Roaming/Bitcoin"; DST=$MNT
fi

# ---------------------------------------------------------------- stage 0: preflight
say "Stage 0: preflight"

[[ -d $SRC/blocks/index ]] || die "$SRC/blocks/index not found. Is Windows mounted at $WIN? See step 1 at the top of this script"
[[ -d $SRC/chainstate ]]   || die "$SRC/chainstate not found"
[[ -f $STAGE/chainstate.sha256 ]] || die "$STAGE/chainstate.sha256 is missing. make-manifest.ps1 has to run on Windows first"
[[ -f $STAGE/blocks.sha256 ]]     || die "$STAGE/blocks.sha256 is missing. make-manifest.ps1 has to run on Windows first"
[[ $(cat "$STAGE/chainstate.sha256" "$STAGE/blocks.sha256" | tr -cd '\r' | wc -c) -eq 0 ]] || die "a manifest has Windows line endings; sha256sum would reject every line"

SRC_FILES=$(list_tree "$SRC" | wc -l)
MANIFEST_LINES=$(cat "$STAGE/chainstate.sha256" "$STAGE/blocks.sha256" | wc -l)
[[ $SRC_FILES -eq $MANIFEST_LINES ]] || die "the source has $SRC_FILES files but the manifests list $MANIFEST_LINES. The node ran after the manifests were made. Boot Windows and make them again"
ok "source has $SRC_FILES files, and the manifests list the same number"

if [[ $TEST -eq 1 ]]; then
  ok "TEST mode: no disk is touched, copying $SRC to $DST"
  mkdir -p "$DST"
else
  [[ $(id -u) -eq 0 ]] || die "run this with sudo"
  for t in lsblk findmnt wipefs sfdisk mkfs.ext4 rsync sha256sum udevadm; do
    command -v "$t" >/dev/null || die "missing tool: $t"
  done
  findmnt -n -o OPTIONS -T "$SRC" | tr ',' '\n' | grep -qx ro || die "$WIN is not mounted read-only. Unmount it and mount it again with -o ro"
  ok "Windows is mounted read-only"

  # ------------------------------------------------------------ stage 1: find the drive
  say "Stage 1: find the Passport"
  if [[ -z ${DISK:-} ]]; then
    WANT_HEX=$(hex_of "$EXPECT_SERIAL")
    FOUND=()
    while read -r path serial; do
      serial=${serial^^}
      # USB bridges report the serial either as text or as the hex of that text
      if [[ $serial == "$EXPECT_SERIAL" || $serial == "$WANT_HEX" ]]; then FOUND+=("$path"); fi
    done < <(lsblk -dnro PATH,SERIAL)
    if [[ ${#FOUND[@]} -ne 1 ]]; then
      lsblk -do PATH,SIZE,TRAN,MODEL,SERIAL
      die "expected one disk with serial $EXPECT_SERIAL, found ${#FOUND[@]}. If the Passport is in the list above under another serial, run again with DISK=/dev/sdX"
    fi
    DISK=${FOUND[0]}
  fi
  [[ -b $DISK ]] || die "$DISK is not a block device"
  [[ $(lsblk -dnro TYPE "$DISK") == disk ]] || die "$DISK is a partition. Give the whole disk, for example /dev/sdb"
  [[ $(lsblk -dnro TRAN "$DISK") == usb ]]  || die "$DISK is not a USB disk. Refusing"
  BYTES=$(lsblk -dnbro SIZE "$DISK")
  [[ $BYTES -ge $MIN_BYTES && $BYTES -le $MAX_BYTES ]] || die "$DISK is $BYTES bytes, which is not the size of the Passport. Refusing"
  SRC_DISK=$(lsblk -nro PKNAME "$(findmnt -n -o SOURCE -T "$SRC")" | head -n1)
  [[ "/dev/$SRC_DISK" != "$DISK" ]] || die "$DISK is the disk Windows is on. Refusing"
  ok "found $DISK"
  lsblk -o PATH,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK"

  # ------------------------------------------------------------ stage 2: format
  PART=$(lsblk -rno PATH,TYPE "$DISK" | awk '$2=="part"{print $1}' | head -n1)
  if [[ -n $PART && $(lsblk -rno FSTYPE "$PART") == ext4 && $(lsblk -rno LABEL "$PART") == "$LABEL" ]]; then
    say "Stage 2: skipped, $PART is already ext4 with the label $LABEL (resuming)"
  else
    say "Stage 2: format $DISK as ext4"
    echo "   EVERYTHING on $DISK will be erased. To go ahead, type exactly:  ERASE $EXPECT_SERIAL"
    read -r -p "   > " ANSWER < /dev/tty
    [[ $ANSWER == "ERASE $EXPECT_SERIAL" ]] || die "not confirmed, nothing was changed"
    while read -r tgt; do
      [[ -z $tgt ]] || umount "$tgt"
    done < <(lsblk -rno MOUNTPOINT "$DISK")
    wipefs -a "$DISK" >/dev/null
    # sfdisk is part of util-linux and so on every live image; parted is not always there
    printf 'label: gpt\ntype=linux, name=%s\n' "$LABEL" | sfdisk -q "$DISK"
    udevadm settle
    PART=$(lsblk -rno PATH,TYPE "$DISK" | awk '$2=="part"{print $1}' | head -n1)
    [[ -b $PART ]] || die "the new partition did not appear on $DISK"
    # largefile: the drive holds 128 MB block files, so few inodes are needed. -m 0: no root reserve.
    mkfs.ext4 -q -F -L "$LABEL" -m 0 -T largefile "$PART"
    udevadm settle
    ok "formatted $PART"
  fi

  while read -r tgt; do
    [[ -z $tgt || $tgt == "$MNT" ]] || umount "$tgt"
  done < <(lsblk -rno MOUNTPOINT "$PART")
  mkdir -p "$MNT"
  mountpoint -q "$MNT" || mount "$PART" "$MNT"
  [[ $(findmnt -n -o FSTYPE "$MNT") == ext4 ]] || die "$MNT is not an ext4 mount"
  LOG="$MNT/make-ext4-seed.log"
  date -u +'--- run started %Y-%m-%dT%H:%M:%SZ' >> "$LOG"
  ok "mounted at $MNT"
fi

# ---------------------------------------------------------------- stage 3: copy
say "Stage 3: copy blocks and chainstate (about 820 GB, 2 to 3 hours on this drive)"
mkdir -p "$DST/blocks" "$DST/chainstate"
if command -v rsync >/dev/null; then
  rsync -rt --chmod=D700,F600 --human-readable --info=progress2 "$SRC/chainstate/" "$DST/chainstate/"
  rsync -rt --chmod=D700,F600 --human-readable --info=progress2 "$SRC/blocks/" "$DST/blocks/"
elif [[ $TEST -eq 1 ]]; then
  cp -r "$SRC/chainstate/." "$DST/chainstate/"
  cp -r "$SRC/blocks/." "$DST/blocks/"
else
  die "rsync is missing"
fi
ok "copy finished"

say "Stage 4: copy the documents and manifests"
cp -r "$STAGE/." "$DST/"
ok "$(find "$STAGE" -type f | wc -l) files from to-drive/"

# ---------------------------------------------------------------- stage 5: verify
say "Stage 5: verify"
sync
diff <(list_tree "$SRC") <(list_tree "$DST") > /dev/null || {
  diff <(list_tree "$SRC") <(list_tree "$DST") | head -n 20
  die "the copy differs from the source in file names or sizes (first differences above). Run the script again; the copy resumes"
}
ok "all $SRC_FILES files are present with the right sizes"

(cd "$DST" && sha256sum -c --quiet chainstate.sha256) || die "a file in chainstate/, blocks/index/ or xor.dat does not match its SHA-256. Do not use this copy"
ok "SHA-256 matches for all $(wc -l < "$STAGE/chainstate.sha256") files in chainstate/, blocks/index/ and xor.dat"
echo "   not checked here: SHA-256 of the $(wc -l < "$STAGE/blocks.sha256") block files. seed-node.sh does that on the target machine."

# ---------------------------------------------------------------- done
if [[ $TEST -eq 0 ]]; then
  USED=$(df -h --output=used "$MNT" | tail -n1 | tr -d ' ')
  date -u +'--- run finished %Y-%m-%dT%H:%M:%SZ' >> "$LOG"
  LOG=""
  sync
  umount "$MNT"
  say "DONE. $USED written to $PART (ext4, label $LABEL). The drive is unmounted and safe to unplug."
  echo "   The log of this run is on the drive: make-ext4-seed.log"
  echo "   Next: shut this session down, remove the live USB, boot Windows."
else
  say "DONE (TEST mode)."
fi
