# Battery guard

A laptop node on battery must shut down cleanly before the battery runs flat.
A battery that runs out stops the node without a clean stop, and the node may
then spend a long time checking or rebuilding its databases at the next
start.

The desktop's power manager can do this, but only while someone is logged in.
After a reboot nobody is, unless the display manager logs in automatically.
`battery-guard.sh` does not depend on the desktop: it runs from root's cron
every minute, logged in or not.

## Install

From the folder holding the scripts, on the node machine:

```
sudo sh install-battery-guard.sh
/usr/local/sbin/battery-guard --status
```

The installer copies the guard to `/usr/local/sbin/battery-guard`, writes
`/etc/cron.d/battery-guard` (every minute, as root), and writes
`/etc/default/battery-guard` with `THRESHOLD=25` unless that file exists. It
starts and stops nothing. Run it again after updating `battery-guard.sh`.
To undo: `sudo sh install-battery-guard.sh remove`.

`--status` prints what the guard reads and what it would do, and never acts:

```
mains: online
battery: status=Full capacity=100
threshold: 25 %
wake alarm: 60 min after a guard shutdown, unless at or below 10 %
decision: ok, does nothing
```

## How it decides

It shuts down only when all of these hold on two runs in a row, one minute
apart:

- no mains adapter reports online;
- the battery reports `Discharging`;
- the battery is at or below the threshold.

Anything it cannot read means "do nothing". It does nothing in the first 5
minutes after a boot, so a node that is still starting is never stopped
half-way. Back on mains, the count starts again from zero. Batteries in
wireless mice and keyboards are ignored.

"Cleanly" means the normal shutdown path: the gateway's init script stops
first, then the node's, which gives the node up to 15 minutes to flush. See
[Install the init scripts](install.md).

## The wake alarm

Many laptops have no "power on when AC returns" setting. So before it shuts
down, the guard saves the system time into the hardware clock
(`hwclock --systohc`) and sets the clock's wake alarm (`rtcwake -m no`) for
`WAKE_MINUTES` later. If the power is back by then, the machine boots and the
node and gateway start as usual. If not, it boots on battery, and the guard
shuts it down again two checks after the 5-minute grace, setting the next
alarm. At or below `WAKE_FLOOR` it sets no alarm, so repeated boots never run
the battery flat; the power button is then the only way on.

Saving the time first matters on a machine whose hardware clock keeps local
time: see [Clock and time](clock-and-time.md). A failed or missing `hwclock`
or `rtcwake` never stops the shutdown.

Whether the alarm works depends on the firmware. Test it on your machine:
[Power recovery and the wake test](power-recovery.md), Part A. If your
machine has a better way back on, such as power-on with AC, use that; the
same page, Part B, lists them.

## Settings

In `/etc/default/battery-guard`, one per line. The guard reads the file each
minute, so no restart is needed. The file is parsed, never run: only plain
`NAME=<number>` lines count, and out-of-range values fall back to the
default.

| Setting | Default | Range | Meaning |
|---|---|---|---|
| `THRESHOLD` | 25 | 5 to 50 | Shut down at or below this %. |
| `WAKE_MINUTES` | 60 | 0, or 10 to 1440 | Wake alarm this long after a guard shutdown. 0 turns it off. |
| `WAKE_FLOOR` | 10 | 3 to 50 | No wake alarm at or below this %. Keep it below `THRESHOLD`. |

Turn the alarm off:

```
echo WAKE_MINUTES=0 | sudo tee -a /etc/default/battery-guard
```

## Set the desktop's own action below the guard

Also set the desktop's critical-battery action to Shutdown, at a lower level
than the guard (the tested laptop uses 15 %). The default is often Suspend,
and a suspended laptop that runs flat loses the node without a clean stop.
In Xfce: Settings > Power Manager > System. Then the guard acts first and
sets the wake alarm, and the desktop is a second line.

`upowerd` has a separate last-resort action in `/etc/UPower/UPower.conf`:

```
grep -E '^(PercentageAction|CriticalPowerAction)' /etc/UPower/UPower.conf
```

On the tested laptop it is `HybridSleep` at 2 %. The guard acts long before
that, so it should never fire; `CriticalPowerAction=PowerOff` is the safer
value if you change it.

## Logs

The guard logs to syslog with the tag `battery-guard`:

```
grep battery-guard /var/log/syslog
```
