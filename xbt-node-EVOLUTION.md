# xbt-node: construction and evolution log

## 2026-10-11 to 2026-10-12, session A (14ebca09)

**Goal, in the owner's words:** "copy root-dir files on d: drive to a working space on C: ...
Next: reformat d: as EXT4. Then make blocks and chainstate dirs there and copy over from
local Windows C drive Knots files for blocksdir, index, and chainstate. The re-formatted
D drive will become the source for a new PATUM Knots 29.4 node plus DATUM gateway to be
run on Devuan Linux."

**Finding that shaped everything:** Windows cannot create or write ext4, and this PC had
no WSL, hypervisor or ext4 tooling. The agent proposed WSL2; the owner refused to install it.
The agent then proposed a LAN pull from a Linux box; the owner asked for a way without the
network. Decision (agent proposed, the owner agreed): boot the Windows PC itself from an
Ubuntu live USB, mount the internal disk read-only, format the USB drive and copy disk
to disk. One copy, no installs on Windows, and the node is certainly stopped. Rejected:
a spare drive as go-between (two copies), a third-party ext4 driver for Windows
(corruption history), a VM.

**Questions and answers:** PATUM is pyblock.xyz's bundle of the Blake2b Knots build and
a DATUM gateway, pointed at a Pyblock pool. Chainstate goes on the target's internal
SSD, blocks stay on the ext4 drive. One copy of the chain during the job is acceptable.
Hash check: partial at copy time (chainstate, block index, xor.dat, all file sizes),
full on the target before the node first runs. The owner's choice, on the agent's suggestion,
to cut PC downtime by about 2.5 hours.

**Built:** `make-manifest.ps1` (two sha256sum-format manifests), `make-ext4-seed.sh`
(finds the drive by serial, refuses unless USB, about 2 TB and not the Windows disk,
asks for a typed confirmation, formats, copies with rsync, verifies, resumes after an
interruption), a revised `seed-node.sh` and README for ext4, and `test/run-tests.sh`.

**Verified:** 17 tests pass on Windows, covering manifest format, copy and verify logic,
resume, and three refusals. The tests caught two real bugs: relative paths skewed by an
8.3 short path, and a line-ending check that passed for the wrong reason. Not verified:
disk detection, the format and rsync, which cannot run on Windows.

**Side track, target machine networking:** the target laptop is Wi-Fi only with a
Realtek RTL8821CE. Three of the owner's adapters were read on the PC: two were Thunderbolt
devices that a plain USB-C port cannot use; the third, a USB-C hub with an RTL8153, is
a plain USB device and linked at gigabit. Agent's OS recommendation: Devuan, fallback
Ubuntu 24.04, pending a glibc check of PATUM's binary.

**Corrections by the agent to itself:** it first said the run log could be read from
C: afterwards; C: is read-only in the live session, so the log lives on the drive.

**Left open:** PATUM's data directory, config and service paths. The drive job itself
has not started; the owner deferred it to a day when he can attend it.

## 2026-10-12 to 2026-10-14, session A (14ebca09), continued: the target laptop

**Scope change, the owner's:** keep the laptop's existing 512 GB disk and dual-boot Windows
and Devuan 6, instead of fitting a separate 128 GB disk. The agent pushed back once on
dual boot (Windows updates can take back the boot order; the Windows and Linux clocks
disagree; the node is down whenever Windows runs). The owner kept dual boot; all three were
handled or checked.

**Findings that changed the plan:** Windows could not shrink its partition past the
master file table, so the shrink was done with GParted from a live stick, followed by a
clean disk check in Windows. The first installer stick hung at its boot loader on this
laptop; rewritten in Rufus's DD mode it booted at once. The USB-C hub ran at USB 2 speed
until its plug was turned over, which pointed to one worn high-speed path. The live
session's clock was hours off because Windows keeps the hardware clock in local time,
which blocked the package manager until its date check was skipped.

**Agent mistakes:** a clock-setting command that fed an empty value to `date` and set
the clock to midnight; a guess that the installer would make a 1 GB swap (it made 5.9
GB, so the planned swap file was dropped); multi-line and long commands that broke when
pasted into the Linux terminal. The owner asked for a standing rule after the third paste
failure: one short command per line.

**Result, as the owner reported it:** Devuan 6 with sysvinit, GRUB lists Windows and boots
both, Devuan is the default and comes back by itself after a restart from Windows,
wired gigabit through the hub, 5.9 GB swap, lid and idle sleep off at both desktop and
system level (lid test passed with nobody logged in). glibc 2.41 means PATUM binaries
built on current Ubuntu or Debian releases will run.

**Left for tomorrow:** the drive job on the PC, deliberately scheduled as one unbroken
sequence (stop Bitcoin, build manifests, copy, restart Bitcoin) because the manifests
only match files that have not moved since. Then PATUM's paths, and SSH hardening.

## 2026-10-15 to 10-17, session A (14ebca09), continued: drive filled, seed script fixed, move to SSH

**Goal (the owner):** "Bitcoin is stopped, build the manifests", then fill the Passport, then
"plug in the WD drive and set the bitcoin.conf to point at the right places".

- Manifests built (second run; the first failed after a full 820 GB hash on the node's
  `blocks/.lock`, so the file-set check was moved ahead of hashing and a test added).
- The owner asked to keep his browser and terminals open, so Ryzen2 was **hibernated** instead
  of shut down. The agent flagged the real risk: Windows resuming onto a Passport that had
  changed from exFAT to ext4 underneath it. The fix was to eject it first and keep it
  unplugged at resume. The read-only mount of hibernated C: worked. The copy took 2 h 52 min,
  all 11,604 files arrived at the right sizes, and the 189 small files matched SHA-256.
- **Finding that changed the design:** Bitcoin keeps `blocks/index` in the data directory
  even when `blocksdir` is set (confirmed against doc/files.md). `seed-node.sh` copied only
  the chainstate, so the node would have found no matching index. Two more bugs turned up in
  the same read: `-datadir` was never passed to the node, and a missing space in `touch`
  would have stopped Stage 1. All three were fixed. The script now refuses to run while a
  partial sync is in the data directory.
- PATUM facts read from the owner's files:
  - its node was still running after its wizard said "stopped", and had nearly filled the
    SSD (agent caught it from `pgrep` output);
  - it turns on `txindex=1` (the owner: keep it; Windows never had it, so it builds from scratch);
  - it does not carry the source node's `consensusrules=rdts` or `blake2b_headline`.

  The last point is open, pending the build's own `-help` output.
- The owner approved deleting PATUM's partial download (about 98 GB), which there was no room to
  keep.
- **Process change (the owner):** the USB-stick relay of commands and output was too slow for him
  ("I'm a slow admin assistant to you with this USB sneakernet method"). The agent proposed
  key-only SSH from Ryzen2 into the HP 14, with two sudo options:
  - a temporary passwordless-sudo rule;
  - the owner typing the sudo password in a shared tmux session.

  The owner chose the tmux option: "I need to learn to use TMUX". A dedicated key was made, and
  a setup file with a short tmux guide was written to the stick.

## 2026-10-17, session A (14ebca09), continued: SSH, seeding, PATUM, miners live

**Goal (the owner):** "Do your next magic", then get PATUM running and the miners on the new node.

- With key-only SSH in place, the agent did the look-and-adjust work directly:
  - unmounted the Windows partition that Devuan had mounted read-write, and proposed a udev
    rule to hide it (the owner's call, not yet applied);
  - deleted PATUM's partial download;
  - read the PATUM build's own `-help`.

  Finding: `blake2b_headline` is regtest-only in this build, so it was dropped from the
  script.
- **Pushback, agent wrong:** the agent suggested running without `consensusrules=rdts` on
  ordinary-Bitcoin reasoning about minority chains. The owner corrected it: the chain is XBT,
  Blake2b proof of work with spam-hostile rules derived from BIP-110, and rdts is required.
  The agent restored the requirement in the script, added the line to the conf, and saved
  the fact as a standing memory.
- `seed-node.sh` ran in a tmux session that the agent and the owner shared, with the owner typing the
  sudo password (his choice, also to learn tmux). Results:
  - all 11,415 block files matched their SHA-256 (about 2.5 h at 92 MB/s from USB);
  - the chainstate and block index were copied and verified;
  - the offline start opened at the snapshot block with the expected hash.

  The owner then started the node. It caught up 357 blocks and began building txindex.
- **PATUM updates:** 0.5.2 came out the same day, and `-check` reported 0.5.3. Both were
  fetched with `wget` (the HP 14 had no curl) and checked against pyblock's SHA256SUMS; older
  versions were kept beside the new one. The agent read the program's built-in text to
  answer whether rerunning the installer reinstalls ("Have a saved configuration", "keeps
  your node"). It held all PATUM runs until the hash check finished, so nothing could touch
  the block files mid-check.

  Found later: PATUM edits `bitcoin.conf` in place and kept our lines.
- **Gateway build:** it needed curl, git, cmake, a compiler and four `-dev` libraries. The
  agent checked each package over SSH and gave one batched install, instead of letting the
  user meet each missing piece one at a time.
- **Before switching the miners,** a read-only subagent reviewed the gbox watchdog. It found
  no pool coupling and no pool writes; the one risk was the 5-minute "no accepted shares"
  stall rule. Plan: switch the unwatched HS-BOX first and measure the share rate at the
  gateway (about 5 to 6 a minute, 0 rejects), then the SC-BOX. Result: both miners on the
  node, 210 accepted and 0 rejected shares in the first quarter hour, and no watchdog action.
- **Mac side:** Private Wi-Fi address turned off and IPs reserved. The first Mac key was
  hand-copied from the wrong source; fingerprints showed the mismatch, and the fix was to move
  the `.pub` as a file.
- **Left open:** nothing autostarts after an HP 14 reboot; the Windows hide rule; the old
  README and script on the Passport; Mac to Ryzen2 SSH.
- **End of the day:** PATUM's boot files are systemd units, so on Devuan nothing it sets up
  starts at boot. The agent wrote a sysvinit script for the gateway, which waits for the
  node's RPC in the background and refuses to run beside a PATUM-started gateway, plus a
  one-command installer. These are prepared but not yet installed or reboot-tested; that
  needs the owner's sudo. The drive's README was rewritten as built, and the fixed script and the
  new files were copied to the Passport.

  The owner's verdict on the session: "This was huge work. You made it possible quite robustly
  with all the testing-as-we-went."

## 2026-10-18, session A (14ebca09), continued: txindex done, the identity split planned, two repos scrubbed

Written without the owner's name, as everything on this side will be from now on; the older entries above were
scrubbed when this project moved to its crypto-side repo.

- **txindex** finished at 02:05 EDT on 10-18, inside the 01:00 to 03:00 estimate made the night before. The
  index is 68 GB; the laptop's SSD has 50 GB free. Load dropped to near zero.
- **The move list.** Asked to "show me the move list", the agent grouped every file by destination: a new
  private crypto-side repo for the node, seed and autostart tools; a new private real-name repo for the dual-boot
  runbook and the SSH kit; snapshot checksums and superseded copies kept out of git. It flagged that the laptop's
  login name points at the crypto account, so the real-name side must never print it. The owner agreed to the
  names and to starting both private.
- **A leak found on the way.** The crypto-side tuner repo had 17 commits authored under the owner's real name and
  one under a personal email, which was also this PC's global git email. The owner chose to change the global
  default to the crypto account's no-reply address (every real-name repo already set its own) and to rewrite.
- **Back-editing history.** The owner asked what it would take; the agent offered a current-files-only clean or
  a full rewrite, recommended the rewrite while both repos were young and unforked, and said plainly what a
  rewrite cannot reach (existing clones, commits GitHub still serves by hash). Wording was settled before the
  replacement table: "the owner", already the house word beside "the agent"; "the author" rejected because the
  agent wrote most of the text; pronouns kept, the owner's choice.
- **Done and verified:** both repos rewritten by rule, blob by blob, including a vendored changelog and the copy
  inside a test zip; zero hits in any commit, message or tag; every removed line contained the name; the gbox suite
  green before the force-push; quoted commit ids in current files mapped old to new.
- **A slip:** the agent's own test commands carried a time cap shorter than the suite, and a pipe hid the exit
  code, so a cut-off run first read as a pass. Caught from the missing summary line and rerun uncapped.

## 2026-10-21, session B (3a630e51): a false alarm, then autostart installed and reboot-tested

- **The ask:** "help me get Patum running again. Looks like we had an HP 14 hard restart." Then autostart, then the repo split.
- **No restart had happened.** The agent read uptime, boot history and process start times before acting: everything dated from 10-14 and 10-17. The window list showed every app still open on workspace 1 while the screen showed workspace 4. The kernel log had bursts of an unmapped HP key at the same minute; the owner traced it to phones resting on the keyboard corners. A first theory (out-of-memory kills) was stated as a theory, checked with one sudo grep, and dropped when the log was empty.
- **Log access.** Rather than ask for sudo each time, the agent proposed adding the owner's account to the log-reading group, once; the owner did. The agent had called it "my login"; the owner pointed out it is the same account, and it is.
- **Autostart.** Before handing over the sudo line the agent re-checked the prepared scripts against the running system: the hand-started node's own pid file (so the script can stop it cleanly), the gateway's config paths, the RPC settings. After install it checked not just the S/K numbers but the parallel-boot dependency file, since Devuan runs shutdown scripts concurrently and the numbers alone do not guarantee the node stops before the drive unmounts.
- **Reboot test passed:** clean node shutdown in 4 s, node and gateway back before any login. One surprise: the miners kept hashing on their backup pool for about ten minutes before returning by themselves. The agent first said they might not return; the logs then showed they did.
- **The panel stays manual.** PATUM's own boot units are systemd and do not apply on Devuan. Starting the panel by hand was checked to start no second node or gateway.
- **A slip:** a filter meant to hide the RPC password failed and printed it into the session. It is local-only and was kept out of every file.

## 2026-10-22, session C (1b5183ae): the project becomes the xbt-node repo

- **The ask:** "load the Devuan Node project, then build the xbt-node repo". The plan was settled on 10-18 (the
  move list, approved then), so the agent restated it from that session's record and built it rather than
  reopening it.
- **What moved where.** The node-side scripts and the as-built runbook went to `node/`; the Windows-side manifest
  and drive-fill scripts to `seed/`; the tests to `test/`; the never-run first plan to `docs/plan-before-build.md`;
  this log was renamed to match the new directory. The SHA-256 manifests stayed out of git (snapshot data, already
  on the drive) in a gitignored staging folder, which the fill script now reads from.
- **What was scrubbed.** A hard-coded Windows user path became a required `WIN_USER` setting; the Linux user name
  in the autostart examples became `YOURNAME`; the first plan's example user became `nodeuser`; older entries in
  this log now say "the owner". Beyond the agreed list, the agent also made the drive's serial a required setting
  instead of a constant, since a serial identifies a physical device; the test now uses a made-up one.
- **Verified:** the test suite, pointed at the new layout plus five new tests for the two required settings
  (refused before anything runs, and the message names the setting): 27 passed, 0 failed. Leak grep over every
  staged file for the name, account names, user paths, LAN and MAC addresses, emails, the serial and RPC settings:
  only false positives (an English verb in a script message, placeholder names). The repo-local git identity is the crypto account's.
- **Left for the owner:** approving the first commit, creating the empty private repository on GitHub (there is
  no GitHub CLI on this PC), and whether the old project folders go to the attic.
- **Then, the same session:** the owner installed the GitHub CLI and signed it in as the crypto account, and said
  "go ahead". The agent checked the CLI had not taken over git's own credential store (it had not, so each remote
  keeps its account in its URL), reran the leak grep over the full history including the commit message, made the
  first commit, created the repository private and pushed. The attic move of the old folders still waits for the
  owner.

## 2026-10-28, session D (ddbba4a0): the node upgrade that looked hung

- **The ask:** "I have PATUM updated to 0.5.6 and it is updating the Knots node to 29.4.3 but it seems to have
  hung... downloaded, verified the release signature, extracting, then just hung for 6+ minutes."
- **Finding: it had not hung.** Over SSH the agent found the new 29.4.3 binary in place, the old node shut down
  cleanly and the new one loaded in ten seconds, synced, with the fork rules still set. The gateway had kept
  its miners throughout. The window showing "extracting" was the panel's own console, which simply printed
  nothing more. The agent's first reading said "the panel's progress display stalled"; the owner corrected that
  it was a terminal window, and that the panel still offered a node-update button.
- **Second finding: why the panel still asked.** The panel's status API showed the update job finished ok, yet
  reported the node as 29.4.2. It takes the version from the text the node advertises to peers, and that text
  is a fixed `uaspoof` line in the node's config that PATUM writes at install time but not on update. So the
  warning was false, and pressing the button again would have restarted the node for nothing.
- **Options given:** (1) fix the one line and restart the node, (2) leave the cosmetic warning, (3) report it
  upstream. Agent recommended 1, because a real rule change two to three days out made a standing false
  "outdated" warning dangerous to ignore. The owner chose 1.
- **Done and verified:** config backed up, one line changed (diff checked), node stopped over RPC and started
  with PATUM's own command so the autostart script still recognises it. After: new version advertised, fork
  rules and index loaded, synced, panel reports up to date, gateway never restarted, about 11 seconds without a
  fresh template.
- **Explained, not changed:** the gateway's "empty work sent to 2 clients" lines are its instant coinbase-only
  job after each new network block, so miners stop working on a stale block before the full template is ready.
- **Left for the owner:** whether to report the update-skips-uaspoof behaviour to PyBLOCK.
