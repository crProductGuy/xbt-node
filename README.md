# xbt-node

Can a spare laptop run its own XBT node, so the miners stop depending on
someone else's? This repo holds the scripts that seeded a Devuan laptop's
node from a Windows PC's already-synced copy of the chain (about 880 GB moved
over a USB drive and checked file by file with SHA-256) and the init scripts
that keep the node and its DATUM gateway running across reboots. It enables a
home mining setup that builds its own block templates. Example: after a
reboot, the node and gateway come back before anyone logs in, and the miners
return to them on their own within about ten minutes.

## What is here

| Folder | Runs on | What it does |
|---|---|---|
| `seed/` | Windows PC, then a Linux live USB on the same PC | `make-manifest.ps1` hashes the stopped node's data. `make-ext4-seed.sh` formats the external drive as ext4 and fills it, checking every file it can. |
| `node/` | The node machine | `seed-node.sh` brings the node up from the drive and runs the full block check. `install-autostart.sh` installs the Devuan (sysvinit) start-and-stop scripts. `README-LINUX-NODE.txt` is the as-built runbook; a copy lives on the drive. |
| `test/` | Windows PC, Git Bash | `run-tests.sh` tests the manifest script and the drive fill in a safe TEST mode, and checks syntax and line endings of every Linux script. |
| `docs/` | | `plan-before-build.md`, the plan as written before anything ran. |

## How it fits together

```
Windows PC (synced node, stopped)
  make-manifest.ps1  ->  SHA-256 manifests
  live USB session   ->  make-ext4-seed.sh  ->  USB drive (ext4): blocks, chainstate, manifests
                                                   |
Node machine (Devuan)                              v
  seed-node.sh: copy chainstate and block index to the SSD, keep blocks on the drive,
                verify every block file, start the node
  init scripts: node, then gateway at boot; gateway, then node at shutdown
                                                   |
Miners  ---- stratum ---->  DATUM gateway  ---->  node
```

## The chain

XBT is Bitcoin with Blake2b proof of work and spam-hostile rules. Every node
here runs `consensusrules=rdts`. Regular-Bitcoin defaults do not apply.

## Running the tests

In Git Bash on Windows, with PowerShell 7 (`pwsh`) installed:

```
bash test/run-tests.sh <empty scratch directory>
```

## Status

Running since 2026-10-17. Autostart installed and reboot-tested 2026-10-21.
The full story, with the decisions and the mistakes, is in
`xbt-node-EVOLUTION.md`.
