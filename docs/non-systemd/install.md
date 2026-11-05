# Auto-start at boot

PATUM sets up its node, its DATUM gateway, its web panel and a daily update
check for systemd. On Devuan, or any Debian-family system that boots with
sysvinit, none of them runs by itself. Three init scripts and one cron entry
do that job, and stop the node and gateway cleanly at shutdown.

| What | On systemd, PATUM uses | On Devuan, these scripts use |
|---|---|---|
| Node | its own setup | `/etc/init.d/bitcoind` |
| DATUM gateway | its own setup | `/etc/init.d/datum-gateway` |
| Web panel | an always-on service | `/etc/init.d/patum-panel` |
| Daily update check | a timer | `/etc/cron.d/patum-check` |

## What the scripts do

- **`/etc/init.d/bitcoind`** (from `devuan-bitcoind.init`) starts the node as
  its user. At shutdown it sends TERM, the same clean stop as
  `bitcoin-cli stop`, and waits up to 15 minutes for the node to exit. It
  never force-kills the node.
- **`/etc/init.d/datum-gateway`** (from `devuan-datum-gateway.init`) starts
  the gateway once the node answers RPC. It waits in the background, so the
  boot does not stall. It stops before the node at shutdown. If PATUM already
  started a gateway, it refuses to start a second one on port 23334.
- **`/etc/init.d/patum-panel`** (from `devuan-patum-panel.init`) starts PATUM's
  web panel once the gateway runs, on a fixed port (32999 unless you choose
  another) bound to `127.0.0.1`. It is the Devuan stand-in for the always-on
  panel service PATUM installs on systemd; see
  [The PATUM panel](#the-patum-panel).

## Before you install

The scripts assume:

- **PATUM's layout under one user's home:** `~/pyblock-node` (with
  `bin/bitcoind`, `bin/bitcoin-cli` and `data/`) and `~/pyblock-gateway`
  (with `datum_gateway` and `wavicles.json`).
- **The XBT chain rules:** `install-autostart.sh` refuses to run unless
  `bitcoin.conf` contains `consensusrules=rdts`.
- **The node has synced at least once:** the installer checks that
  `data/chainstate` exists.

## Install

Copy the scripts folder to the node machine. Then, from that folder, with
your own user name in place of `YOURNAME`:

```
sudo sh install-autostart.sh YOURNAME
```

The installer:

1. copies the node and gateway init scripts to `/etc/init.d/`;
2. writes their settings to `/etc/default/bitcoind` and
   `/etc/default/datum-gateway`;
3. registers both with `update-rc.d`;
4. prints which block-drive check it chose, the two services' status, and
   the boot order;
5. runs `install-panel-autostart.sh` for the panel.

It starts and stops nothing. A node and gateway that are already running keep
running, and the init scripts take over at the next boot. In the boot order
it prints, the node should start before the gateway and stop after it.

It is safe to run again. Run it again whenever you update either init script
by hand, so the settings file matches.

To undo:

```
sudo rm /etc/cron.d/patum-check
sudo update-rc.d patum-panel remove
sudo update-rc.d datum-gateway remove
sudo update-rc.d bitcoind remove
```

## The PATUM panel

On systemd, PATUM installs an always-on service for its web panel. On Devuan
that service never runs, so without `/etc/init.d/patum-panel` the panel stays
off after every reboot, and the browser cannot connect, until someone starts
it by hand.

The panel's init script:

- waits in the background until `datum_gateway` runs (up to an hour, then it
  starts anyway), so the panel does not open on a half-started node;
- leaves alone a panel that is already running, for example one started by
  hand, instead of starting a second one on the same port;
- runs the panel as the node's user, with `-no-open -port 32999`;
- at shutdown stops first and asks the panel to quit. It never force-kills
  it, because the panel may be running an update.

The panel starts no node or gateway of its own; the init scripts own those.

Install it with the other two (the autostart installer runs it), or alone,
for example to pick another port:

```
sudo sh install-panel-autostart.sh YOURNAME 32999
```

Open it at `http://127.0.0.1:32999/` on the node machine. It listens on
`127.0.0.1` only, so from another machine open an SSH tunnel first, then the
same address there:

```
ssh -L 32999:127.0.0.1:32999 YOURNAME@<node>
```

The panel's log is `/var/log/patum-panel.out`. Check or restart it with
`sudo service patum-panel status` or `sudo service patum-panel restart`.

## The daily update check

On systemd, PATUM checks for updates once a day from a timer. Devuan never
runs that timer, so PATUM never looks for updates by itself.
`install-panel-autostart.sh` adds `/etc/cron.d/patum-check`, which runs
`patum -check` as the node's user once a day, at a random time between 03:00
and 05:59 so that not every node asks at once.

It only checks; it never installs anything. Each run adds a time and one line
to `~/pyblock-node/patum-check.log`, for example:

```
2026-11-05T04:17:01-05:00
PyBLØCK: up to date (PATUM v0.5.9).
```

Read the latest result:

```
tail -2 ~/pyblock-node/patum-check.log
```

When it reports an update, update as PATUM describes, as yourself and not
with `sudo`: `~/pyblock-node/bin/patum -update`. The panel does not read this
log; it is for you.

To stop the check: `sudo rm /etc/cron.d/patum-check`.

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
