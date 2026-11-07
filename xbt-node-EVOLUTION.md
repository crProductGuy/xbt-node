# xbt-node: construction and evolution log

This is the story of how a spare laptop became a full XBT node for a small home mining setup, built over
four weeks by the owner and a coding agent (Claude Code). It records what was asked, what the agent
proposed, what the owner decided and why, what went wrong, and how each step was checked. Git holds the
line-by-line changes; this file holds the reasoning.

## The story in brief

The owner's miners pointed at someone else's node. He had a fully synced node on a Windows PC and a spare
HP laptop, and wanted the laptop to run its own node, so the miners could build their own block templates.
Downloading the chain from scratch would have taken weeks, so the plan was to copy the PC's synced chain to
an external drive and seed the laptop from it. Windows cannot write the Linux file system the drive needed,
so the PC was booted from a Linux USB stick for the copy. The laptop got Devuan, a Linux without systemd.
On 17 October the node came up from the drive with every file checked, and the miners moved to it that
evening. Because the PyBLOCK tools it runs (PATUM) expect systemd, the rest of the work was making the
laptop look after itself without one: start and stop cleanly at every boot, shut down before the battery
dies, and wake again after an outage. Those scripts and guides were shared with PyBLOCK so they could
publish them for other people running PATUM on Linux without systemd, and this repository holds them.

## Who and what

- **The owner:** runs the miners and made every decision recorded here. **The agent:** Claude Code, which wrote the
  scripts and this log, and ran the read-only checks.
- **The PC:** the owner's Windows PC, which held the synced node and served as the agent's workstation.
- **The laptop, or HP 14:** an HP Laptop 14 that runs the node. It dual-boots Windows and Devuan 6.
- **The seed drive, or Passport:** a 2 TB external USB drive, formatted ext4, that carried the chain from the PC to
  the laptop. The laptop's block files still live on it.
- **XBT:** Bitcoin with Blake2b proof of work and spam-hostile rules. Every node runs Bitcoin Knots with
  `consensusrules=rdts`; regular-Bitcoin reasoning does not apply.
- **PyBLOCK and PATUM:** PyBLOCK publishes PATUM, a bundle of the Blake2b Knots build, a DATUM gateway and a small
  web panel. **DATUM** is the protocol that lets a miner build its own block templates against its own node; the
  gateway speaks stratum, the usual miner protocol, to the miners and talks to the node and to the pool (WAVICLES).
- **The miners and gbox:** at first two Goldshell miners (the SC-BOX and an HS-BOX), three by November. gbox is the
  owner's separate watchdog for them.
- **D-numbers** (such as D-041) are rows in the owner's decision register, kept outside this repo; the log quotes
  his answer where it matters. **Sessions** are named by a letter and the first eight characters of the agent
  session's ID, so each entry can be traced to its transcript.

---

## Part 1: Seeding the laptop (11 to 17 October)

### 2026-10-11 to 10-12, session A (14ebca09): how to get the chain onto ext4

The owner set the goal: "copy root-dir files on d: drive to a working space on C: ... Next: reformat
d: as EXT4. Then make blocks and chainstate dirs there and copy over from local Windows C drive Knots files
for blocksdir, index, and chainstate. The re-formatted D drive will become the source for a new PATUM Knots
29.4 node plus DATUM gateway to be run on Devuan Linux."

The first obstacle decided the method. Windows cannot create or write ext4, and the PC had no WSL,
hypervisor or ext4 tools. The agent proposed WSL2; the owner did not want it installed. The agent then
proposed pulling the files over the network from a Linux machine; the owner asked for a way without the
network. The agent's third proposal was accepted: boot the PC itself from an Ubuntu live USB, mount the
internal disk read-only, format the USB drive and copy disk to disk. That meant one copy, nothing installed
on Windows, and a node that was certainly stopped. Rejected along the way were a spare drive as a go-between
(two copies), a third-party ext4 driver for Windows (a history of corruption), and a virtual machine.

A few questions settled the shape of the job. The
chainstate would go on the laptop's internal SSD and the blocks would stay on the ext4 drive. One copy of the
chain during the job was acceptable. On the agent's suggestion, the owner chose to check hashes in two steps:
a partial check at copy time (chainstate, block index, `xor.dat` and every file's size), and a full check on
the laptop before the node first ran. That cut the PC's downtime by about two and a half hours.

The agent then wrote the tools. `make-manifest.ps1` writes two SHA-256 manifests. `make-ext4-seed.sh` finds the
drive by its serial number, refuses unless it is a USB drive of about 2 TB and not the Windows disk, asks for a
typed confirmation, then formats, copies with rsync, verifies, and resumes after an interruption. `seed-node.sh`
and the drive's README were revised for ext4, and `test/run-tests.sh` was started. Its 17 tests passed on Windows
and caught two real bugs: relative paths skewed by a Windows short path, and a line-ending check that passed for
the wrong reason. Disk detection, formatting and rsync cannot run on Windows, so they waited for the real run.

On the laptop side, networking came first: it is Wi-Fi only. Of the owner's three adapters, two were Thunderbolt
devices that a plain USB-C port cannot use; the third, a USB-C hub with a Realtek gigabit chip, linked at
full speed. The agent recommended Devuan, with Ubuntu 24.04 as the fallback, pending a check that PATUM's
binaries would run on Devuan's C library.

One correction along the way: the agent first said the run log could be read from the PC's disk afterwards. In the
live session that disk is read-only, so the log was moved to the drive itself.

PATUM's data directory, configuration and service paths were still unknown, and the drive job waited for a day the
owner could attend it.

### 2026-10-12 to 10-14, session A (14ebca09), continued: preparing the laptop

The owner changed the scope: keep the laptop's 512 GB disk and dual-boot Windows and Devuan 6, instead of
fitting a separate 128 GB disk. The agent pushed back once on dual boot: Windows updates can take back the
boot order, the two systems disagree about the hardware clock, and the node is down whenever Windows runs.
The owner kept dual boot, and all three points were handled or checked.

Several things went differently than planned. Windows could not shrink its partition past the NTFS file
table, so the shrink was done with GParted from a live stick, followed by a clean disk check in Windows. The
first installer stick hung at its boot loader; rewritten in Rufus's DD mode, it booted at once. The USB-C hub
ran at USB 2 speed until its plug was turned over, which pointed to one worn high-speed path. The live
session's clock was hours off, because Windows keeps the hardware clock in local time, and that blocked the
package manager until its date check was skipped.

The agent made mistakes of its own. A clock-setting command fed an empty value to `date` and set the clock
to midnight. A guess that the installer would make a 1 GB swap was wrong (it made 5.9 GB, so the planned swap
file was dropped). Long and multi-line commands broke when pasted into the Linux terminal, and after the
third failure the owner asked for a standing rule: one short command per line.

The result, as the owner reported it: Devuan 6 with sysvinit, a boot menu that offers both systems with
Devuan as the default, wired gigabit through the hub, and lid and idle sleep turned off for the desktop and
the system, tested with nobody logged in. Devuan's C library (glibc 2.41) is new enough for binaries built on
current Ubuntu or Debian.

The drive job was set for the next day as one unbroken sequence (stop the node, build the manifests, copy,
restart the node), because the manifests match only files that have not changed since.

### 2026-10-15 to 10-17, session A (14ebca09), continued: the drive filled, the seed script fixed

The owner: "Bitcoin is stopped, build the manifests", then fill the Passport, then "plug in the WD drive and
set the bitcoin.conf to point at the right places".

The manifests took two runs. The first failed after hashing the whole chain, on the node's `blocks/.lock`
file, so the check of which files belong in the set was moved ahead of the hashing, with a test.

The owner wanted his browser and terminals kept open, so the PC was hibernated rather than shut down. The
agent named the real risk: Windows resuming onto a drive that had changed from exFAT to ext4 underneath it.
The fix was to eject the drive first and keep it unplugged at resume. The read-only mount of the hibernated
Windows disk worked. The copy took 2 hours 52 minutes; all 11,604 files arrived at the right sizes, and the
189 small files matched their SHA-256.

Reading the seed script again before it ran changed the design. Bitcoin keeps `blocks/index` in the data
directory even when `blocksdir` points elsewhere (confirmed in Bitcoin's own `doc/files.md`), and
`seed-node.sh` copied only the chainstate, so the node would have found no matching index. The same read
found two more bugs: the node was never given `-datadir`, and a missing space in a `touch` command would have
stopped the first stage. All three were fixed, and the script now refuses to run over a partial sync.

The owner's PATUM files showed three things. Its node was still running after its setup wizard said
"stopped", and had nearly filled the SSD; the agent caught it in the process list. It turns on `txindex=1`,
which the owner chose to keep, so the index would be built from scratch. And it does not carry the source
node's `consensusrules=rdts`. The owner approved deleting PATUM's partial download (about 98 GB), which there
was no room to keep.

The owner then changed how the work was done. Carrying commands and output on a USB stick was too slow ("I'm
a slow admin assistant to you with this USB sneakernet method"). The agent proposed key-only SSH from the PC
into the laptop, with either a temporary passwordless-sudo rule or the owner typing the sudo password in a
shared tmux session. The owner chose tmux: "I need to learn to use TMUX".

### 2026-10-17, session A (14ebca09), continued: seeded, PATUM running, miners live

The owner: "Do your next magic", then get PATUM running and the miners on the new node.

With SSH in place the agent did the checking and adjusting directly. It unmounted the Windows partition that
Devuan had mounted read-write, and proposed a rule to hide it (the owner's call, still open). It read the
PATUM build's own `-help`, which showed that `blake2b_headline`, set on the PC, applies only to a test network,
so it was dropped.

Then the agent got the chain wrong. It suggested running without `consensusrules=rdts`, reasoning from how regular
Bitcoin treats minority rule sets. The owner corrected it: the chain is XBT, with Blake2b proof of work and the
spam-hostile rules of BIP-110 (the "reduced data" soft fork that `rdts` names), and rdts is required. The agent
restored the requirement in the script, added the line to the configuration, and kept the fact as a standing rule
for every later session.

`seed-node.sh` ran in the shared tmux session, with the owner typing the sudo password. All 11,415 block files
matched their SHA-256 (about two and a half hours at 92 MB/s over USB), the chainstate and block index were
copied and verified, and an offline start opened at the snapshot's block with the expected hash. The owner
then started the node. It caught up 357 blocks and began building its transaction index.

PATUM moved quickly that day: 0.5.2 came out, then 0.5.3. Both were fetched with `wget` and checked against
PyBLOCK's published SHA-256 sums, with the older versions kept. The agent held every PATUM run until the hash
check finished, so nothing could touch the block files mid-check, and read the program's built-in text to
confirm that rerunning the installer keeps the existing node. PATUM, it turned out, edits `bitcoin.conf` in
place and keeps the lines added by hand.

Building the DATUM gateway needed curl, git, cmake, a compiler and four development libraries. The agent
checked each package first and gave the owner one batched install, instead of letting him meet each missing
piece one at a time.

Before the miners moved, a read-only review of gbox found no coupling to the pool. The one risk was its rule
that acts after five minutes without an accepted share. So the unwatched HS-BOX moved first, its share rate
was measured at the gateway (five to six a minute, no rejects), and then the SC-BOX followed. Both miners were
on the node with 210 accepted shares and none rejected in the first quarter hour, and gbox took no action.

The day ended with one gap named. PATUM's start-at-boot files are systemd units, so on Devuan nothing it
installs starts at boot. The agent wrote a sysvinit script for the gateway, which waits in the background for
the node to answer and refuses to run beside a gateway PATUM started, plus a one-command installer. Installing
it needed the owner's sudo, so it waited. The drive's README was rewritten as built.

The owner's verdict: "This was huge work. You made it possible quite robustly with all the testing-as-we-went."

---

## Part 2: A live node, and its own repository (18 to 22 October)

### 2026-10-18, session A (14ebca09), continued: the index done, the move planned

The transaction index finished at 02:05 on 18 October, inside the agent's estimate of 01:00 to 03:00. It takes
68 GB, which left 50 GB free on the laptop's SSD.

Asked to "show me the move list", the agent sorted every file by destination: a new private repository on the
owner's crypto-side account for the node, seed and start-at-boot tools; a separate real-name repository for
the dual-boot runbook and SSH kit; checksums and superseded copies kept out of git. The owner agreed to the
names and to starting both private. Author identity and history in the crypto-side repositories were cleaned
before the first push.

### 2026-10-21, session B (3a630e51): a false alarm, then start-at-boot installed

The owner: "help me get Patum running again. Looks like we had an HP 14 hard restart."

No restart had happened. Before acting, the agent read the uptime, boot history and process start times, and
everything dated from 14 and 17 October. The window list showed every app still open on workspace 1 while the
screen showed workspace 4. The kernel log had bursts of an unmapped HP key in the same minute; the owner traced
them to phones resting on the keyboard corners. A first theory, that processes had been killed for lack of
memory, was stated as a theory, checked with one command, and dropped when the log was empty.

Rather than ask for sudo every time it needed a log, the agent proposed adding the owner's account to the
log-reading group once, and the owner did.

Before handing over the install command, the agent checked the prepared scripts against the running system:
the hand-started node's own pid file, so the script could stop that node cleanly, the gateway's configuration
paths, and the RPC settings. After the install it checked the boot order in two places. The start and stop
order numbers alone are not enough on Devuan, which runs shutdown scripts in parallel, so it also read the
dependency file that decides whether the node stops before its drive is unmounted.

The reboot test passed: the node shut down cleanly in 4 seconds, and the node and gateway were back before
anyone logged in. The miners spent about ten minutes on their backup pool before returning by themselves. The
agent first said they might not return; the logs showed they did.

The panel stayed a manual start for now, after a check that starting it by hand creates no second node or
gateway. One slip: a filter meant to hide the RPC password failed and printed it into the session. It stayed
local and out of every file.

### 2026-10-22, session C (1b5183ae): the project becomes this repository

The owner: "load the Devuan Node project, then build the xbt-node repo". The plan had been approved on 18
October, so the agent restated it from that record and built it rather than reopening it.

The node-side scripts and the as-built runbook went to `node/`, the Windows-side manifest and drive scripts to
`seed/`, the tests to `test/`, and the first plan, never run as written, to `docs/plan-before-build.md`. The
checksum manifests stayed out of git in a gitignored staging folder that the drive script now reads.

Everything personal came out. A hard-coded Windows user path became a required setting, and so did the drive's
serial number, which the agent added beyond the agreed list because a serial identifies a physical device.
Example user names became placeholders, and the older entries in this log now say "the owner". Five new tests
check that a missing setting is refused before anything runs, with the setting named; the suite passed 27 of
27. A search of every staged file for names, accounts, user paths, network and hardware addresses, emails, the
serial and RPC settings found only false positives.

The owner installed the GitHub command-line tool, signed it in to the crypto-side account and said "go ahead".
The agent checked that the tool had not taken over git's own credential store, searched the full history again
including the commit message, made the first commit, and pushed to a new private repository.

---

## Part 3: Running it (28 to 31 October)

### 2026-10-28, session D (ddbba4a0): the upgrade that looked hung

The owner: "I have PATUM updated to 0.5.6 and it is updating the Knots node to 29.4.3 but it seems to have
hung... downloaded, verified the release signature, extracting, then just hung for 6+ minutes."

It had not hung. Over SSH the agent found the new 29.4.3 binary in place, the old node shut down cleanly, and
the new one loaded in ten seconds, in sync, with the fork rules still set. The gateway had kept its miners
throughout. The window that stopped at "extracting" was the panel's own console, which printed nothing
more. The agent's first reading called it the panel's progress display; the owner corrected that it was a
terminal window, and pointed out that the panel still offered to update the node.

That offer was false. A node advertises its version to its peers in a user-agent line, and PATUM writes that
line as a fixed `uaspoof` setting in the node's configuration at install time, but did not rewrite it on
update. The panel reads the advertised version, so it still saw 29.4.2. Pressing the button again would have
restarted the node for nothing. The agent offered three options: fix the line and restart the node, leave the
warning, or report it upstream. It recommended the fix, because a real rule change two to three days away made
a standing false "outdated" warning dangerous to ignore, and the owner agreed.

The agent backed up the configuration, changed the one line and checked the diff, stopped the node over RPC,
and started it with PATUM's own command so the start-at-boot script would still recognize it. The new version
was then advertised, the panel reported the node up to date, and the gateway, never restarted, went about 11
seconds without a fresh template. The owner reported the update behavior to PyBLOCK.

The agent also explained, without changing anything, the gateway's "empty work sent to 2 clients" lines: after
each new network block the gateway sends an instant job with no transactions, so the miners stop working on a
stale block before the full template is ready.

### 2026-10-31, session E (79d5edad): a health check, a fast clock, and a battery guard

The owner: "look into the HP 14", then, after the first report: "Patum page is up but static, not live...
Worried that things underneath aren't working, though the DATUM gateway console web page looks OK."

A read-only check over SSH found the node in sync with 17 peers on the same process since the upgrade, and the
gateway on its 21 October process with both miners and a fresh job about every 41 seconds. Neither log had
errors. A rule change about 65 blocks away needed Knots 29.4.3, which the node already ran. The static page was
only the panel: its process had exited at some unknown time, and since it picked a new port on each run, an old
browser tab could not find it again even after a restart.

The second finding was a clock nobody kept. The laptop's clock ran about 19 seconds fast, measured against the PC
after the PC's own clock was checked against an internet time server. Without systemd, Devuan has no built-in time
sync, and no time daemon had been installed. The owner agreed to install chrony. The agent added one change of its
own: chrony was not to write the hardware clock, because on this dual-boot machine the hardware clock keeps local
time for Windows, and the agent was not sure chrony's writes would respect that. Devuan already saves the system
time to the hardware clock at shutdown. Once running, chrony measured the drift at about one second a day, which
fits 19 seconds over the 17 days since the install. The clock then stayed within a millisecond of four time
servers.

Fixing it had a cost. The agent had warned that the one-time correction would come when chrony was told to
step the clock, and to watch the gateway then. It came earlier: Debian starts chrony as soon as it is installed,
and the default configuration corrects a large error in one jump. The clock moved back 19.08 seconds, and 3
milliseconds later the gateway logged "no data received from server in over 60 seconds", reconnected within a
second, and lost the shares it had queued for the pool, probably a few seconds of pool credit, with no effect on
any block. That the backward jump tripped the gateway's 60-second timer is an inference from the timing; the
gateway's code was not read. The lesson: on a Debian-family mining machine, installing a time daemon is itself
the moment the clock moves.

At the owner's request the agent restarted the panel. PATUM had updated its own panel program to 0.5.7 on 29
October, and the start command in the owner's notes still pointed at the old 0.5.3 installer, so the agent used the
current program, on a fixed port so the address stays the same across restarts. It checked that the node and
gateway kept their processes, and wrote the start, use and stop steps into a short page for the owner.

Next the owner turned to shutdown: "It's very important for Bitcoin nodes including Knots
nodes, to be given a clean shut-down signal... Look into what is needed to do that well. See if you can tell if
PATUM has a way to trigger it." A read-only review found the shutdown and reboot path already sound: the gateway
stops first, the node gets up to 15 minutes and is never forced, and every stop in the log had been clean within
seconds. The gap was the battery. The desktop's low-battery action was suspend, and it runs only while someone is
logged in, which after a reboot nobody is. PATUM stops the node itself only during its own wizard and updates, so
on Devuan the clean stop comes only from this repository's init scripts.

The agent wrote `battery-guard.sh`, which root runs from cron every minute. When the AC adapter is off and the
battery is discharging at or below 25 % on two checks in a row, it starts a normal shutdown. The threshold sits
above the desktop's 20 % on purpose, because a suspended machine runs no cron jobs. The system's upower daemon
was considered and not chosen, because it may not run without a desktop session and that could not be checked
cheaply. A separate review found four things worth fixing, all fixed before the commit: tests that could pass on
timing, a failed shutdown that was neither logged nor retried, a wireless mouse whose battery could be read as the
laptop's, and the settings file's permissions.

That raised the question of coming back after an outage. The owner checked the BIOS: it has no "power on when AC
returns" setting and no Wake on LAN, so a laptop the guard had shut down would stay off until someone pressed the
button. The owner chose the agent's proposal: before shutting down, the guard sets the clock's wake alarm for 60
minutes later. If the power is back, the node and gateway start as usual; if not, the guard shuts the laptop down
again with a new alarm. Below 10 % it sets no alarm, so repeated boots cannot run the battery flat, and a failed
alarm never stops the shutdown. A second review led to four more fixes, including a setting with a leading zero
that was read as an octal number, and a rule that the guard does nothing in the first five minutes after boot, so
it cannot stop a node that is still starting. In both rounds the agent broke the new code on purpose to confirm the
tests caught it, and they did. Whether this laptop actually wakes from off was still unknown; a ten-minute test
went into the runbook for the owner to run.

---

## Part 4: Making it useful to others (2 to 7 November)

### 2026-11-02, a gbox project session (25a2ab43): the materials go to PyBLOCK

Two days after the clean-shutdown review, working from a session of his gbox project, the owner shared the Devuan
scripts and the reasoning behind them with PyBLOCK, so that they could publish them for other people running PATUM
on Linux without systemd. From here on the work
aimed at a set of scripts and guides that would hold up on machines other than this one. Nothing on the node
changed that day.

### 2026-11-04, session E (79d5edad), resumed: scripts for other machines, and a wake test anyone can run

By now PATUM had updated itself to 0.5.9 (on 3 November). The node stayed on Knots 29.4.3, and PATUM now rewrote
the version line in the node's configuration by itself, which closed the false "outdated" warning of 28 October
for good.

Two changes made the scripts fit other machines. The node's init script had refused to start without the external
block drive, which is right here but wrong for a machine that keeps its blocks on the internal disk. The drive
check is now off unless a mount point is named, and the installer picks it itself from the node's `blocksdir` and
`/etc/fstab`, so a reinstall here keeps the protection and other machines need no change. The script's header,
which still said it had never run on Linux, was brought up to date. The installer's hard rdts requirement was kept,
and put to the owner as a question rather than changed silently.

A separate review found one serious gap. On a machine set up before this change, replacing only the init script
would have silently dropped the drive check, exactly the failure it exists to prevent. Now the script refuses to
start the node, and names the fix, when the settings file predates the drive setting and the node's configuration
moves its blocks. Smaller fixes covered a blocks folder inside the drive rather than at its top, spaces around "="
in the configuration, and paths with unsafe characters. All 116 tests passed.

The owner then asked for exact steps to run the wake test, "so people can see how to verify on their own systems",
made "as universal as practical". The guide covers the tests themselves (on AC, on battery, and the full guard path
on a real drain, with the log lines to expect), what to check in the firmware if the machine does not wake, and
the other ways a machine can come back after an outage: power-on-after-AC-loss on desktops (with the warning that
"last state" stays off after a clean shutdown), a UPS that signals a shutdown, Wake on LAN, server management
controllers, single-board computers, and a smart plug for a machine that is already off. BIOS setting names are
labeled as typical, not checked against any one model.

### 2026-11-04 evening, session E (79d5edad), continued: a daylight-saving bug, a doc set, a panel that starts itself

The owner ran the first two wake tests and reported: "wake test on AC failed; never woke, and the time looked right
when I checked it in step 3 ... ran test 2. That succeeded (lid was open as recommended), and uptime value was
15-20 sec after the alarm time." The agent read the logs before offering a cause. The first test's alarm had been
due six minutes before the owner pressed the button; the second woke 22 seconds after its alarm; every stop was
clean. A laptop that wakes on battery but not on AC is the reverse of the usual pattern, so the agent named no
cause and proposed repeating the first test with the lid open (D-040).

The owner's next detail settled it. When the alarm was set, `rtcwake` had printed the wake time as 19:49:04, while
`rtcwake -m show` said 18:49:04. An hour's difference pointed at the clock. The laptop's hardware clock keeps local
time for Windows, the time zone had left daylight saving on 1 November, and the laptop had run since 31 October.
Linux writes the hardware clock only at shutdown, so it was an hour ahead, and since `rtcwake` counts from the
hardware clock, the alarm was really set for 19:49. The shutdown corrected the hardware clock, which is why the
second test passed. The same flaw would hit the guard twice a year, with an autumn alarm an hour late and a spring
alarm in the past. The agent offered two fixes: save the system time to the hardware clock just before setting the
alarm, or switch the hardware clock to UTC. The owner chose: "D-041 yes, on local time, not UTC". The guard now
runs `hwclock --systohc`, which follows the system's local-time setting, before setting the alarm, and a failing or
missing `hwclock` never blocks the alarm or the shutdown. Removing that call makes three tests fail.

The owner repeated the first test that evening, on AC with the lid open. The alarm was due at 19:55:07 and the
laptop booted at 19:55:28. The owner: "self-start worked on AC! So it was the DST issue." The logs support that
reading without proving it, since the failure was not reproduced on purpose. With that, the laptop had passed both
wake tests.

The owner then asked whether the files for PyBLOCK made "a nice free-standing set of docs". The agent said they did
not: plain-text files, a setup guide written around this one laptop, two files that existed only on the USB stick
used to carry files between the machines, and the daylight-saving fix in just one of them. The owner agreed to a
Markdown doc set in the repository (D-042), now `docs/non-systemd/`: an index with a quick start and a tested-on
table, then pages for install, the battery guard, machine settings, clock and time, power recovery (the wake-test
guide, moved here so there is one copy), troubleshooting and a reference page. Writing it exposed a contradiction:
the old setup guide said to set power-on-after-AC to "On, or Last State", while the power guide said Last State
leaves a cleanly stopped machine off. The new pages say Power On. At the owner's request a page lists the
development tools Devuan needed before the gateway would build; the agent took the list from the laptop's package
history rather than memory (nine packages, installed on 17 October). New tests check that every link and anchor in
the doc set resolves and that the reference page's checksums match the scripts.

Later the owner wrote: "start the PATUM service on port 32999. The browser can't connect. What are we missing on an
auto-start? Please fix & document that". The panel was not running: the wake-test reboots had ended it, and on
Devuan nothing started it again. On systemd, PATUM installs a panel service that is always on. At the owner's word
the agent reversed the hand-start rule of 21 October and wrote a third init script for the panel, with its own
installer, which `install-autostart.sh` also runs. The panel waits until the gateway runs, so it never opens on a
half-started node; it leaves a panel that is already running alone; and it stops with a plain terminate signal and
is never killed, because it may be in the middle of an update. The owner also confirmed (D-043) that a systemctl
shim found on the laptop was his own experiment and not needed, so the docs leave it out. He installed the panel
script, and the boot order was checked: node, gateway, panel, stopping in reverse.

Finally the owner answered two open questions. The installer keeps its hard rdts requirement (D-039), since every
node on this chain must run rdts anyway, and a daily update check was wanted (D-044). For D-044 the agent first ran
`patum -check` once on the laptop: it reported "up to date (PATUM v0.5.9)" and wrote no file, so the panel does not
read its result and a daily check needs its own log. The panel installer now also writes a cron entry that runs the
check once a day as the node's user, at a random time between 03:00 and 05:59 so that nodes do not all ask PyBLOCK
in the same minute, and appends the result to a log. The install page became "Auto-start at boot", with a table of
what PATUM uses on systemd and what replaces it here. The suite stood at 142 tests, all passing.

### 2026-11-07, session E (79d5edad), continued: the real boot test, and the bundle

After running the start-at-boot installer, the owner shut the laptop down cleanly and started it with the power
button. The node, gateway and panel all came back by themselves: the panel service's first real boot test. The
gateway's log warns at every start that its 4,096 configured stratum clients exceed the system's limit of 1,024
open files. The older logs show the same warning at every start since 17 October, and with three miners the gateway
holds 21 files open, so it is harmless at this scale. The owner chose to leave it (D-045). The three miners are the
two from 17 October and a third that joined the gateway after 31 October; the day it moved is not recorded here.

The guides stayed in Markdown, and the tested-on section of `docs/non-systemd/README.md` was refreshed: PATUM
0.5.9, three miners, and the panel seen starting at a real boot. The owner asked whether a single zip file would
worry a recipient. The agent's answer: the checksums inside a zip prove only that the download is intact, not who
made it, so the zip's own SHA-256 belongs in the message sent with it. The owner chose to keep a copy of what was
sent (D-046): `tools/make-pyblock-bundle.py` builds the zip reproducibly, with fixed dates, fixed file modes and
sorted entries, and rebuilding from the repository reproduced the zip already sent byte for byte. The zip went to
PyBLOCK with a cover note the agent drafted and the owner sent, telling the recipient it was a Claude draft. The
suite stood at 152 tests.

The front-page README was rewritten for a first-time reader, and a pre-public pass began: a search of the whole
tree and every commit, author and message for anything personal came back clean.

### 2026-11-07, session F (2dbde2df): the pre-public narrative pass

The owner asked for "a final 'whole narrative' review including writing style, so it's easily consumed by someone
new and reads like a unitary story, not a bunch of pasted together snippets." Following his decisions, the
repository gained an MIT license (D-047), and the correspondence folder left the repository (D-049) and, as the
pass's last step, its history (D-051). This log was regrouped into four parts, with a short story and a cast at
the top, and the per-day notes were rewritten as prose. The runbook's header and versions were brought up to
date, and two contradictions in it were resolved. A fresh reviewer then read the log end to end, and its findings
were folded in. At the owner's word the rewritten history was force-pushed. GitHub still serves the dropped
commits to anyone who has their hashes, so the owner deleted the GitHub repository and recreated it empty
(D-054), and the cleaned history was pushed into it.

---

## Where things stand

The node has run on the laptop since 17 October 2026, now under PATUM 0.5.9 with Bitcoin Knots 29.4.3 and three
miners on its gateway. PATUM moved from 0.5.3 at bring-up through 0.5.6 and 0.5.7 to 0.5.9, the last installed on 3
November. By 7 November the node's advertised version line read PATUM 0.5.9, written by PATUM itself, so the hand
edit of 28 October is no longer needed.

What is proven: clean starts and stops at every boot since 21 October; the panel at boot, installed on 4 November
and seen at a real boot on 7 November; the wake alarm on AC and on battery; and the battery guard in automated
tests with simulated battery readings. What is not: the battery guard on a real drained battery, which only a real
outage or a deliberate drain can show. The repository went public on 7
November, after the owner added the "why" to the README. Still open: hiding the Windows partition from Devuan.
