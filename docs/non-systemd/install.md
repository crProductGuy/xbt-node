# Install the init scripts

PATUM sets up its node and DATUM gateway for systemd. On Devuan, or any
Debian-family system that boots with sysvinit, nothing it sets up starts at
boot. Two init scripts do that job, and stop both processes cleanly at
shutdown.

## What the scripts do

- **`/etc/init.d/bitcoind`** (from `devuan-bitcoind.init`) starts the node as
  its user. At shutdown it sends TERM, the same clean stop as
  `bitcoin-cli stop`, and waits up to 15 minutes for the node to exit. It
  never force-kills the node.
- **`/etc/init.d/datum-gateway`** (from `devuan-datum-gateway.init`) starts
  the gateway once the node answers RPC. It waits in the background, so the
  boot does not stall. It stops before the node at shutdown. If PATUM already
  started a gateway, it refuses to start a second one on port 23334.

## Before you install

The scripts assume:

- **PATUM's layout under one user's home:** `~/pyblock-node` (with
  `bin/bitcoind`, `bin/bitcoin-cli` and `data/`) and `~/pyblock-gateway`
  (with `datum_gateway` and `wavicles.json`).
- **The XBT chain rules:** `install-autostart.sh` refuses to run unless
  `bitcoin.conf` contains `consensusrules=rdts`.
- **The node has synced at least once:** the installer checks that
  `data/chainstate` exists.

The PATUM panel is not started by any of these; see
[Machine settings](machine-settings.md#the-patum-panel).

## Install

Copy the scripts folder to the node machine. Then, from that folder, with
your own user name in place of `YOURNAME`:

```
sudo sh install-autostart.sh YOURNAME
```

The installer:

1. copies the two init scripts to `/etc/init.d/`;
2. writes their settings to `/etc/default/bitcoind` and
   `/etc/default/datum-gateway`;
3. registers both with `update-rc.d`;
4. prints which block-drive check it chose, the two services' status, and
   the boot order.

It starts and stops nothing. A node and gateway that are already running keep
running, and the init scripts take over at the next boot. In the boot order
it prints, the node should start before the gateway and stop after it.

It is safe to run again. Run it again whenever you update either init script
by hand, so the settings file matches.

To undo:

```
sudo update-rc.d datum-gateway remove
sudo update-rc.d bitcoind remove
```

## The block-drive check

If the node's blocks are on an external drive, the node must never start
without it. Otherwise it would start rebuilding its blocks on the internal
disk. So `devuan-bitcoind.init` can wait up to 90 seconds at boot for a
mount point, and refuse to start the node if the drive is not there.

The installer picks the check from its second argument:

| Second argument | Check |
|---|---|
| (none) or `auto` | If `bitcoin.conf` has `blocksdir=<dir>`, and a mount point in `/etc/fstab` holds that directory, check that mount point. Otherwise no check. |
| `none` | No check. |
| `/mount/point` | Check this mount point. |

For example, with the blocks on the internal disk, the plain command above is
all you need. With blocks on a drive that is not in `/etc/fstab`:

```
sudo sh install-autostart.sh YOURNAME /media/blocks
```

Mount points with spaces, quotes or backslashes are refused.

The choice is saved as `MNT=` in `/etc/default/bitcoind`. A settings file
written by an older installer has no `MNT` line. With such a file and a
`blocksdir` set, the init script refuses to start the node and says why, so
that a drive check is never silently dropped; rerun the installer to fix it.

For the drive's own `/etc/fstab` entry, see
[Machine settings](machine-settings.md#external-block-drive).

## Starting and stopping by hand

```
sudo service bitcoind status
sudo service bitcoind stop
sudo service datum-gateway restart
```

Stopping the node by hand: use `service bitcoind stop`, or the PATUM panel's
stop button. Never kill the process, and never unplug the block drive while
the node runs.

Do not use the PATUM panel's start buttons for the node or the gateway while
the init scripts manage them. Let the init scripts own both processes, so
there is one way they start and one way they stop.
