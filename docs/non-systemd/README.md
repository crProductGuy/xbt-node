# PATUM on Linux without systemd

A guide and seven small scripts for running a PATUM node (Bitcoin Knots with
the XBT chain rules, `consensusrules=rdts`) and its DATUM gateway on Devuan,
or any Debian-family system that boots with sysvinit instead of systemd.

PATUM sets its services up for systemd. Without systemd, nothing it sets up
starts at boot, and nothing stops the node cleanly at shutdown. The scripts
here do both jobs, and add a battery guard for laptop nodes:

1. Start the node, the gateway and PATUM's web panel at boot, and stop them
   cleanly at shutdown.
2. Shut a laptop node down cleanly when its battery runs low, whether or not
   anyone is logged in, and set an alarm so the laptop switches itself back
   on later.

## The guide

Read in this order:

0. [Build tools for the DATUM gateway](build-tools.md): the packages to
   install before PATUM's own setup, which a stock Devuan does not have.
1. [Auto-start at boot](install.md): what they assume, the install
   command, the block-drive check, the panel and the daily update check.
2. [Battery guard](battery-guard.md): laptops only. How it decides, its
   settings, and the wake alarm.
3. [Machine settings](machine-settings.md): firmware, lid, power, network,
   the block drive and the PATUM panel.
4. [Clock and time](clock-and-time.md): NTP, and the hardware clock on a
   Windows dual boot.
5. [Power recovery and the wake test](power-recovery.md): how the machine
   comes back on after an outage, the exact tests, and other methods for
   desktops, servers and single-board computers.
6. [Troubleshooting](troubleshooting.md).
7. [Reference](reference.md): files, settings, commands and checksums.

## Quick start

On the node machine, from the folder holding the scripts, with your user
name in place of `YOURNAME`:

```
sudo sh install-autostart.sh YOURNAME
sudo sh install-battery-guard.sh
/usr/local/sbin/battery-guard --status
```

The second line is for laptops only. Neither installer starts or stops
anything now; the scripts take over at the next boot. Then run the wake test
in [Power recovery](power-recovery.md#part-a-the-battery-guards-wake-alarm).

## Tested on

One machine, set up between October and November 2026:

- HP Laptop 14-fq0xxx, AMI BIOS F.52, dual boot with Windows;
- Devuan 6 with sysvinit, Xfce on slim, elogind and upowerd;
- PATUM 0.5.9, Bitcoin Knots 29.4.3 with `consensusrules=rdts`, and the DATUM
  gateway on WAVICLES (the DATUM pool PATUM sets up), with three miners
  pointed at it;
- block files on an external USB drive.

| Part | Status |
|---|---|
| Init scripts | In use since 21 October 2026, through several reboots. Every stop in the node's log ends `Shutdown: done` within seconds. |
| Panel at boot | Added 4 November 2026, after a reboot left the panel off. Automated tests under `dash`. Installed on that machine the same day. Started by itself after a clean shutdown and a power-button start, 7 November 2026. |
| Optional block-drive check | Automated tests under `dash`. Not yet installed on that machine, which runs the earlier init script with a fixed drive check. |
| Battery guard | In use since 31 October 2026. Automated tests under `dash`, and a simulated low-battery run by the PyBLOCK team. Not yet seen shutting down on a real drained battery. |
| Wake alarm | Woke the machine from off on AC and on battery, 4 November 2026. See [Results so far](power-recovery.md#results-so-far). |

## Requirements

- `sh` (`dash` on Devuan), `cron`, `logger`, and `util-linux` for `rtcwake`
  and `hwclock`.
- `sudo` or root, to install.

Shared as-is, with no warranty. Read a script before running it as root.
