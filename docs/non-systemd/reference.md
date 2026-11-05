# Reference

## Files

| Script | Installed as | Installed by |
|---|---|---|
| `devuan-bitcoind.init` | `/etc/init.d/bitcoind` | `install-autostart.sh` |
| `devuan-datum-gateway.init` | `/etc/init.d/datum-gateway` | `install-autostart.sh` |
| `devuan-patum-panel.init` | `/etc/init.d/patum-panel` | `install-panel-autostart.sh`, which `install-autostart.sh` runs |
| `install-autostart.sh` | not installed; run once, and again after updates | |
| `install-panel-autostart.sh` | not installed; run by `install-autostart.sh`, or alone | |
| `battery-guard.sh` | `/usr/local/sbin/battery-guard`, run by `/etc/cron.d/battery-guard` | `install-battery-guard.sh` |
| `install-battery-guard.sh` | not installed; run once, and again after updates | |

All seven are POSIX `sh` scripts with LF line endings. Read a script before
running it as root.

## Settings files

| File | Written by | Holds |
|---|---|---|
| `/etc/default/bitcoind` | `install-autostart.sh` | `BITCOIN_USER`, `BITCOIND`, `DATADIR`, `MNT` (empty = no drive check) |
| `/etc/default/datum-gateway` | `install-autostart.sh` | `GW_USER` |
| `/etc/default/patum-panel` | `install-panel-autostart.sh` | `PANEL_USER`, `PANEL_PORT` (default 32999) |
| `/etc/cron.d/patum-check` | `install-panel-autostart.sh` | PATUM's daily update check; result in `~/pyblock-node/patum-check.log` |
| `/etc/default/battery-guard` | `install-battery-guard.sh`, if missing | `THRESHOLD`, `WAKE_MINUTES`, `WAKE_FLOOR`; see [Battery guard](battery-guard.md#settings) |

## Commands

| To | Run |
|---|---|
| See the node's and gateway's state | `sudo service bitcoind status` and `sudo service datum-gateway status` |
| Stop the node cleanly | `sudo service bitcoind stop` |
| See or restart the panel | `sudo service patum-panel status` or `sudo service patum-panel restart` |
| Open the panel from another machine | `ssh -L 32999:127.0.0.1:32999 YOURNAME@<node>`, then `http://127.0.0.1:32999/` |
| See what the guard would do | `/usr/local/sbin/battery-guard --status` |
| Read the guard's log | `grep battery-guard /var/log/syslog` |
| Check the last clean node stop | `grep "Shutdown: done" ~/pyblock-node/data/debug.log \| tail -1` |
| See the boot order | `ls /etc/rc2.d /etc/rc0.d \| grep -E 'bitcoind\|datum\|patum'` |
| Read the last update check | `tail -2 ~/pyblock-node/patum-check.log` |
| Set a test wake alarm | `sudo /sbin/hwclock --systohc`, then `sudo /usr/sbin/rtcwake -m no -s 600` |

## Checksums

SHA-256 of the scripts these docs describe. To check a copy, save these lines
as `SHA256SUMS` in the scripts folder and run `sha256sum -c SHA256SUMS`.

```
7d5f9a3b7913968f24d6f45c86e26ef051e84e401cd850f8d2812e0d051c6a66  devuan-bitcoind.init
8900fdaf320f8ccf247878400439a9bb742e1e82ed12130d3fcc27ded3239e66  devuan-datum-gateway.init
059d6c7d5f9015f8e105e1353f1b7684d8b61696d88295e3c3392e3aaa4b4dfa  devuan-patum-panel.init
9885859220a40c6fe34303792c63f123698f07444a656cff94368f3503ba13d3  install-autostart.sh
7c00a7e17282ce3d5263604be899b325d1a268fde9322e4ee78679dbbb3f0de5  install-panel-autostart.sh
9a65c3fb7fe99b2855930de4cf54cf0f01ffb0ce6ad79d824719b40126848234  battery-guard.sh
2b68f83ca6e92324f05a93e98d80b2ba6e7cfdaff6c233ff92b2621860c4b152  install-battery-guard.sh
```
