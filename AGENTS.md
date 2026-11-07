# AGENTS.md: xbt-node

Instructions for any coding agent working in this repository. Claude Code
reads this file through `CLAUDE.md`, which holds the single line
`@AGENTS.md`. Nothing here is secret; the repo starts private and may go
public, so write every file as if it already were.

## What this project is

The tools and runbooks that brought up an XBT full node (Bitcoin Knots,
Blake2b fork, `consensusrules=rdts`) on a small Devuan laptop, seeded from a
Windows PC's synced node instead of a weeks-long download, with a DATUM
gateway the owner's miners point at. `README.md` is the front door;
`node/README-LINUX-NODE.txt` is the as-built runbook that also lives on the
seed drive.

## Ground truth and the two logs

Read these before acting, in this order:

- `STATUS.md`: checkpoint, newest block at the bottom wins. Gitignored;
  exists only on the machine where the work happens. If it is missing, say
  so and work from the evolution log and `node/README-LINUX-NODE.txt`.
- `xbt-node-EVOLUTION.md`: the construction and evolution log, committed.
  One entry per session: the goal in the owner's words, questions and
  answers, proposals and decisions with reasoning, findings that changed the
  design, what was built and how it was verified, pushback, what was left
  out. Append an entry at every checkpoint.
- `docs/plan-before-build.md`: the plan written before anything ran. Kept
  for the record; where it disagrees with the as-built runbook, the runbook
  wins.

## Layout

- `node/`: runs on the node machine. `seed-node.sh` (bring-up from the
  seeded drive), the sysvinit scripts and `install-autostart.sh` (Devuan),
  an untested systemd unit (Ubuntu), the as-built runbook.
- `seed/`: runs on the Windows PC. `make-manifest.ps1` hashes the stopped
  node's data; `make-ext4-seed.sh` formats and fills the drive from a live
  USB session. `seed/to-drive/` is the gitignored staging folder.
- `tools/make-pyblock-bundle.py`: builds the dated zip of the Devuan scripts
  and `docs/non-systemd` guides sent to PyBLOCK, reproducibly, into the
  gitignored `dist/<date>/`, which keeps the exact bytes sent.
- `test/run-tests.sh`: the test suite. Run it in Git Bash with an empty
  scratch directory: `bash test/run-tests.sh <empty dir>`. Needs `pwsh`.

## Identity rules: this repo belongs to the crProductGuy side

This is the owner's crypto-side identity, kept separate from any real-name
account. Nothing in this repo, its commit messages or its tags may carry:

- the owner's name, surname or real-name GitHub handle; write "the owner";
- a Windows user path (`C:\Users\<name>`), a Linux user name or a home path
  that contains one; use `<user>`, `YOURNAME` or `nodeuser`;
- LAN addresses, MAC addresses, wallet addresses, drive serials;
- RPC credentials, `bitcoin.conf`, `settings.json`.

Set the repo-local identity before the first commit and check it before
every commit: `git config user.name` must be `crProductGuy`, and
`git config user.email` the crProductGuy no-reply address. Before any push,
run a leak grep over the whole tree and over `git log -p`, and show the
owner the result.

## Rules that bound every change

- The chain is XBT, not regular Bitcoin. Every node runs
  `consensusrules=rdts`. Never reason from regular-Bitcoin defaults.
- Scripts that run on Linux keep LF endings; the tests check this.
- Every non-trivial change ships with tests, and the tests are run.
- The node machine is live and mines for the owner. Read-only checks over
  SSH are fine; anything that needs `sudo`, restarts the node or the
  gateway, or touches the seed drive is the owner's to run. Hand over one
  short command per line, about 60 characters at most, with no backslash
  continuations; the owner pastes them into a Linux terminal.
- PATUM's panel starts at boot from `/etc/init.d/patum-panel`, after the
  gateway (the owner's decision, 2026-11-04; until then it was started by
  hand). Its node and gateway start buttons are not used; the init scripts
  own both processes.

## Done-when discipline

Every task states Goal, Context, Constraints, and Done-when before work
starts. "Verified" means a command and its output, not a sentence.
