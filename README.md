# xbt-node

Why does this repo exist? 

It enables an XBT Bitcoin node-runner and miner, who wants to run the PATUM combined Bitcoin Knots node and DATUM gateway software from pyblock.xyz, on Devuan Linux from devuan.org, or other lightweight Linux distros that use sysvinit instead of systemd for boot-up process initialization.

It also shows how a pre-owned or new low-end laptop with 8GB RAM and a small internal SSD, plus an external USB HDD, can cost-effectively run a lightweight Linux OS, Bitcoin Knots node and DATUM gateway software, AND provide battery backup to maximize up-time in case of power interruptions.

This approach can save hundreds of dollars vs. buying a new mini-PC with a 2TB SSD and a Windows license, or loading StartOS or Umbrel home server software. 


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

# Details:

This repo answers "Yes" to: can a spare laptop on a lightweight Linux distribution run its own XBT node (Bitcoin Knots with Blake2b PoW algorithm) and a DATUM Gateway? 

A Bitcoin Knots node client, plus a DATUM gateway, enables decentralized Bitcoin mining, where each node runner determines what transactions they will accept into blocks they mine from their ASIC hashing machines, via individual block templates they create. The node software also controls which transactions will be forwarded (relay policy) to other nodes across the XBT Bitcoin network.

This is the opposite of centralized pool mining, with potentially hundreds of hashing machines and a single pool-managed node & block template controlling what transactions can be mined or excluded across all of those ASIC machines, and relayed to other centralized miners.

Can such a laptop auto-start node and gateway processes, and shut them down safely when power drops and the battery is low?  Yes!

## What's in the repo, what does it do:

It holds the scripts and guides that enable XBT node and DATUM gateway automatic boot-time process startup and management on a Devuan Linux-based laptop or desktop that does not support "systemd" boot-time `init` code. 
It also manages safe shutdown of the Knots node and gateway, including auto-shutdown when laptop battery power drops below a threshold, and auto-checking hourly whether AC and battery power is adequate to restart the node and gateway processes. 
This facilitates maximum DATUM-based mining uptime on the owner's node, and minimizes ASIC miner fallback time to Stratum V1 hashing directly to a mining pool. 

Background on Linux Init software: systemd is used in Ubuntu, Debian, Fedora, and other commodity Linux distros, and was introduced around 2010. Devuan linux uses the older and simpler sysvinit from System V Unix, which manages processes by sequential scripts.

Why would someone want to run Devuan (a lighter implementation of Debian from devuan.org) instead of a more typical Linux like Ubuntu or System76? 
 - smaller and cheaper machine, even used, especially with rising PC component prices
 - lighter Xfce desktop UI for adequate management without bloat
 - reduced security and privacy risk
 - tighter admin control of processes, etc.
 - See https://linuxvox.com/blog/devuan-linux/
   
Why does systemd vs. sysvinit matter for a node-running machine?

Some XBT node packages, like PyBLOCK's PATUM from https://b.pyblock.xyz:8443/patum.php, that deliver Bitcoin node and DATUM gateway software, assume the presence of `systemd` to manage startup and background processes, such as Knots bitcoind and datum_gateway.

Running PATUM or other node software on Linux distros without systemd requires extra config steps that may not be familiar to many users.  This repo exists to fill that gap.

It also shows how Bitcoin block and chainstate data files can be migrated from an existing Knots node on Windows to a new Linux-based node, without a full Initial Block Download (IBD) which can take days

Finally, it shows how to (optionally) run Bitcoin Knots on a full (unpruned) node, with a small low-cost internal SSD, and a 1-2 TB external USB hard disk drive for block storage.
A $150 external 2.5" HDD for block storage (blocksdir) plus a $60 internal 256GB NVME2 can save $200 vs. purchasing an internal SSD large enough to hold chainstate, index, and full blocksdir.
 
# The setup process:
A Devuan Linux laptop's node was seeded from a Windows PC's already-synced copy of the XBT bitcoin chain (about 870 GB of block files, plus the chainstate and block index, moved over
a USB drive and checked file by file with SHA-256).
Init scripts keep the node, its DATUM gateway and the PATUM panel running
across reboots, and a battery guard shuts the laptop down cleanly before its
battery runs flat. It enables a home mining setup that builds its own block
templates. Example: after a power-off, the node, gateway and panel come back
before anyone logs in, and the miners return to them on their own within about
ten minutes.

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
| Battery guard | 2026-10-31 | In automated tests with simulated battery readings; not yet on a real drained battery |
| Wake alarm after a guard shutdown | 2026-11-04 | Woke the laptop from off, on AC and on battery |
| Panel at boot, daily update check | 2026-11-04 | Panel came back by itself after a power-off, 2026-11-07 |

## License

MIT, for the whole repository. See [LICENSE](LICENSE).
