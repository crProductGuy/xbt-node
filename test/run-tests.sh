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

for f in "$HERE/seed/make-ext4-seed.sh" "$HERE"/node/*.sh "$HERE"/node/*.init "$HERE"/test/*.sh; do
  [[ -f $f ]] || continue
  check "syntax and LF endings: $(basename "$f")" "$(bash -n "$f" 2>&1; tr -cd '\r' < "$f" | wc -c)" 0
done

echo; echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
