# Troubleshooting

## The node did not start at boot

1. Check its state: `sudo service bitcoind status`.
2. If the init script refused because the block drive was missing, plug the
   drive in, check it is mounted (`mountpoint /your/mount/point`), and run
   `sudo service bitcoind start`.
3. If it says the settings file predates the drive check, rerun
   `sudo sh install-autostart.sh YOURNAME`; see
   [The block-drive check](install.md#the-block-drive-check).
4. Read the end of `~/pyblock-node/data/debug.log` for the node's own reason.

## The gateway did not start

It waits for the node's RPC before it starts, so give it a few minutes after
the node. Then `sudo service datum-gateway status`. If PATUM's panel already
started a gateway, the init script refuses to start a second one on port
23334; stop the panel's copy and start the service.

## The machine did not switch itself back on

Run the tests in [Power recovery](power-recovery.md), in order. The usual
causes:

- the firmware does not wake from off on a clock alarm, or only on AC;
- an "ErP", "EuP" or "Deep Sleep" setting cuts power to the wake circuits;
- the hardware clock was an hour off after a daylight-saving change. The
  current guard prevents this; by hand, run `sudo /sbin/hwclock --systohc`
  before `rtcwake`. See [Clock and time](clock-and-time.md);
- "Last State" instead of "Power On" in the firmware's AC-loss setting;
- the battery was at or below `WAKE_FLOOR`, so the guard set no alarm on
  purpose.

## The guard did not shut down on a low battery

Run `/usr/local/sbin/battery-guard --status`:

- `decision: cannot read the power state` means it found no readable mains
  adapter or battery under `/sys/class/power_supply`, so it does nothing.
- `decision: ok` while low: it acts only when `mains:` is not online and the
  battery status is `Discharging`. A dock or second adapter that reports
  online counts as mains.
- It acts only on the second low reading in a row, and never in the first 5
  minutes after a boot.

Check that cron runs it: `grep battery-guard /var/log/syslog | tail`.

## The miners lost the node after a hardware change

A new network adapter has a new MAC address, so a router reservation no
longer matches. Set the node's address on the machine itself; see
[Machine settings](machine-settings.md#network).

## The pool link dropped when chrony was installed

Expected once: chrony steps the clock at its first start. Install it with
the miners off or on another pool; see [Clock and time](clock-and-time.md).
