# xbt-node

Can a spare laptop run its own XBT node, so the miners stop depending on
someone else's? This repo holds the scripts and guides that did it. A Devuan
laptop's node was seeded from a Windows PC's already-synced copy of the chain
(about 880 GB moved over a USB drive and checked file by file with SHA-256).
Init scripts keep the node, its DATUM gateway and the PATUM panel running
across reboots, and a battery guard shuts the laptop down cleanly before its
battery runs flat. It enables a home mining setup that builds its own block
templates. Example: after a power-off, the node, gateway and panel come back
before anyone logs in, and the miners return to them on their own within about
ten minutes.

## Who it is for

- **Anyone running PATUM on Devuan or another Linux without systemd.** PATUM
  ships systemd units only, so on these systems nothing starts the panel,
  stops the node cleanly or runs the daily update check. Start at
  [docs/non-systemd/README.md](docs/non-systemd/README.md): nine short guides
  and seven scripts, also sent to the PyBLOCK team as a zip in November 2026.
- **Anyone seeding a new node from an existing one** instead of a
  weeks-long download: see `seed/` and the runbook,
  [node/README-LINUX-NODE.txt](node/README-LINUX-NODE.txt).
- **Anyone curious how it was built with a coding agent:** the full story,
  with the decisions and the mistakes, is in
  [xbt-node-EVOLUTION.md](xbt-node-EVOLUTION.md).

## The chain

XBT is Bitcoin with Blake2b proof of work and spam-hostile rules. Every node
here runs Bitcoin Knots with `consensusrules=rdts`. Regular-Bitcoin defaults
do not apply.

## What is here

| Folder | Runs on | What it does |
|---|---|---|
| `docs/non-systemd/` | Read anywhere | The guide for PATUM without systemd: build tools for the DATUM gateway, auto-start at boot, the battery guard, machine and firmware settings, the clock, power recovery, troubleshooting, and a reference page with every script's SHA-256. |
| `node/` | The node machine | Init scripts for the node, the gateway and the panel, with their installers; the battery guard and its installer; `seed-node.sh`, which brings the node up from the seed drive; `README-LINUX-NODE.txt`, the as-built runbook. `ubuntu-bitcoind.service` is an untested systemd unit. |
| `seed/` | Windows PC, then a Linux live USB on the same PC | `make-manifest.ps1` hashes the stopped node's data. `make-ext4-seed.sh` formats the external drive as ext4 and fills it, checking every file it can. |
| `tools/` | Windows PC | `make-pyblock-bundle.py` builds the dated zip of the `docs/non-systemd` guides and scripts, byte for byte the same on every run. |
| `test/` | Windows PC, Git Bash | `run-tests.sh`: 152 checks covering the seed scripts in a safe test mode, every init script and installer under `dash`, the battery guard, the docs' links and checksums, and the zip. |
| `notes/` | | The two notes sent to the PyBLOCK team, as sent. |
| `docs/` | | `plan-before-build.md`, the plan as written before anything ran. Where it disagrees with the runbook, the runbook wins. |

## How it fits together

```
Windows PC (synced node, stopped)
  make-manifest.ps1  ->  SHA-256 manifests
  live USB session   ->  make-ext4-seed.sh  ->  USB drive (ext4): blocks, chainstate, manifests
                                                   |
Node machine (Devuan)                              v
  seed-node.sh: copy chainstate and block index to the SSD, keep blocks on the drive,
                verify every block file, start the node
  at boot:      node, then gateway, then the PATUM panel
  at shutdown:  gateway, then node (up to 15 minutes to stop, never forced)
  cron:         battery guard every minute; PATUM update check once a day
                                                   |
Miners  ---- stratum ---->  DATUM gateway  ---->  node
```

## Running the tests

In Git Bash on Windows, with PowerShell 7 (`pwsh`) and Python 3 installed:

```
bash test/run-tests.sh <empty scratch directory>
```

## Status

The node has run since 2026-10-17 on an HP laptop with Devuan 6, PATUM 0.5.9,
Bitcoin Knots 29.4.3 and the DATUM gateway, with three miners pointed at it.

| Part | Since | Seen working |
|---|---|---|
| Node and gateway start and stop | 2026-10-21 | Many reboots; every stop ends `Shutdown: done` |
| Battery guard | 2026-10-31 | In tests and a simulated low battery; not yet on a real drained battery |
| Wake alarm after a guard shutdown | 2026-11-04 | Woke the laptop from off, on AC and on battery |
| Panel at boot, daily update check | 2026-11-04 | Panel came back by itself after a power-off, 2026-11-07 |

## License

MIT, for the whole repository. See [LICENSE](LICENSE).
