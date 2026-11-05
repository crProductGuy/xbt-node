# Power recovery and the wake test

How a node machine comes back on by itself after a power outage, and how to
test that on your own hardware.

A node that shuts down cleanly in an outage is safe, but it is also off.
Unless something switches it back on, it stays off until someone presses the
power button, and the miners pointed at it use their backup pool for that
whole time. Every method on this page is a way to make that "something"
automatic. None of them replaces a clean shutdown; they only bring the
machine back after one.

> Never test any of this by pulling the power while the node is running.
> Every test here starts from a clean shutdown.

- [Part A: the battery guard's wake alarm, exact test steps](#part-a-the-battery-guards-wake-alarm)
- [Part B: other ways to come back on, by kind of hardware](#part-b-other-ways-to-come-back-on)
- [Part C: which to use](#part-c-which-to-use)
- [Results so far](#results-so-far)

## Part A: the battery guard's wake alarm

Before [battery-guard.sh](battery-guard.md) shuts a laptop down on low
battery, it saves the system time into the computer's real-time clock (RTC)
and sets the RTC's alarm:

```
hwclock --systohc
rtcwake -m no -s 3600
```

That asks the firmware to switch the machine on 60 minutes later. Most x86
machines can do this, but not all, and some only on AC power. These tests
find out what your machine does. Run them in order.

### Before you start

- The node and gateway are running normally, and you are at the machine.
- Keep the lid open for the first runs. Some laptops do not power on with
  the lid closed. If you normally run lid-closed, repeat Test 2 lid-closed
  afterwards.
- Your miners use their backup pool while the machine is off, about 10
  minutes per test.
- Have a clock or phone handy to note times.

### Check 0: the machine has an RTC with a wake alarm

Read-only:

```
ls /sys/class/rtc/rtc0/wakealarm
```

Pass: the file exists. If it does not, this method cannot work here; go to
[Part B](#part-b-other-ways-to-come-back-on).

### Test 1: wake from off, on AC power

1. Plug the AC adapter in.
2. Save the system time into the RTC, then set an alarm 10 minutes ahead:

   ```
   sudo /sbin/hwclock --systohc
   sudo /usr/sbin/rtcwake -m no -s 600
   ```

   Do not skip the `hwclock` line. `rtcwake` counts from the RTC's own time,
   and Linux writes the RTC only at shutdown. On a machine whose RTC keeps
   local time (usual with a Windows dual boot) that stayed up across a
   daylight-saving change, the RTC is an hour off, and the alarm lands an
   hour late or in the past. See [Clock and time](clock-and-time.md).
   The time `rtcwake` prints should be 10 minutes from now. If it is not,
   stop and look at the clock first.
3. Check the alarm:

   ```
   sudo /usr/sbin/rtcwake -m show
   ```

   Expect a line starting `alarm: on`. If the RTC keeps local time, the time
   shown here can be off by your UTC offset; trust the time printed in step 2.
4. Write down the time. Shut down cleanly:

   ```
   sudo shutdown -h now
   ```

   The node's init script stops the gateway, then the node, then powers off.
   Wait until the machine is fully off, with lights and fan off.
5. Do not touch it. Note when it switches itself on.
6. After it has booted, confirm:

   ```
   uptime -s
   ```

   The boot time should be within a minute or two of the alarm time.

   ```
   cat /sys/class/rtc/rtc0/wakealarm
   ```

   Empty output means the alarm fired and cleared.

   ```
   pgrep -x bitcoind ; pgrep -x datum_gateway
   ```

   Both print a number. The gateway can take a few minutes, because it
   waits for the node.

   ```
   grep -B1 "Shutdown: done" ~/pyblock-node/data/debug.log | tail -2
   ```

   The last stop before this boot ended cleanly. That path is PATUM's data
   folder; use your node's own `debug.log` if it lives elsewhere.

Pass: it switched itself on about 10 minutes after the alarm was set.
Fail: it stayed off for 20 minutes past the alarm time. Press the power
button, then see [If it does not wake](#if-it-does-not-wake).

### Test 2: wake from off, on battery

This is the case the guard exists for.

1. Unplug the AC adapter. Leave the battery well above 25 %, so the guard
   does not act during the test.
2. Repeat steps 2 to 6 of Test 1.
3. Plug the AC adapter back in afterwards.

Pass: as Test 1. Some laptops wake from an alarm only on AC. If yours passed
Test 1 and fails this one, the guard's alarm does not help on this machine:
set `WAKE_MINUTES=0` (see [Battery guard](battery-guard.md#settings)) so it
does not promise a wake-up that never comes, and use Part B.

### Test 3: the whole guard path on a real drain

Optional; it takes hours. It runs the real thing: the guard shuts the machine
down at the threshold, sets the alarm, and the machine comes back.

1. Unplug the AC adapter and leave the node running. Check now and then:

   ```
   sudo /usr/local/sbin/battery-guard --status
   ```

2. At or below the threshold (default 25 %), on two checks a minute apart,
   the guard shuts down cleanly. Its log lines read, in order:

   ```
   on battery at N% (threshold 25%); shutting down next minute if still low
   wake alarm set for 60 min from now
   on battery at N% for two checks in a row; shutting down cleanly now
   ```

3. Leave it unplugged. About 60 minutes later it should switch itself on. It
   waits 5 minutes after boot, sees it is still low, and shuts down again
   with a new alarm. This repeats until the battery reaches the wake floor
   (default 10 %), when it sets no alarm and stays off.
4. To end the test, plug the AC adapter in. If the machine is off, it comes
   back at its next alarm, within 60 minutes, or press the power button.
5. Read what happened:

   ```
   grep battery-guard /var/log/syslog
   ```

   No `/var/log/syslog`? Try `journalctl -t battery-guard` or `logread`.

   ```
   grep -B1 "Shutdown: done" ~/pyblock-node/data/debug.log | tail -6
   ```

   Every stop should end `Shutdown: done`.

### If it does not wake

- Look in the BIOS or UEFI setup for a setting that allows RTC wake. Typical
  names, which vary by maker and model: "Wake on RTC", "RTC Alarm Power On",
  "Resume by Alarm", "Power On by RTC", "Wake on Alarm". Some firmware needs
  it set to "By OS" or "Enabled".
- Turn off "ErP", "EuP", "Deep Sleep" or "S5 low power" if present. These cut
  power to the wake circuits when the machine is off.
- Check that the `hwclock` line ran, and that the time `rtcwake` printed was
  10 minutes ahead.
- Rerun Check 0 and Test 1. If it still does not wake, this firmware does not
  support RTC wake from off. Set `WAKE_MINUTES=0` and use Part B.

## Part B: other ways to come back on

The setting names below are typical, collected from common makers; they are
not checked against any one model. Look in your own BIOS or UEFI setup
(usually F2, F10, F12, Del or Esc at power-on) and your maker's manual.

### B1. Desktops and mini PCs: power on after AC loss

The simplest and most reliable method. The firmware powers the machine on
whenever mains power comes back.

Typical names: "Restore on AC Power Loss", "AC Power Recovery", "After Power
Failure", "AC Back", "Power On After Power Fail", "State After G3". Choose
"Power On" or "Always On".

Not "Last State": after a clean shutdown, by a UPS or by a guard like this
one, the last state is off, so the machine stays off when power returns.

Test it:

1. Shut down cleanly: `sudo shutdown -h now`
2. When it is off, switch off or unplug the mains for 30 seconds.
3. Restore the mains. Pass: it powers on by itself within a minute.

### B2. Business laptops: power on when AC is connected

Many business laptops can power on when the AC adapter is plugged in, or when
it comes back after an outage. Typical names: "Power on when AC detected" (HP
business models), "Power On with AC Attach" (Lenovo ThinkPad), "Wake on AC"
or "AC Behavior" (Dell Latitude). Consumer laptops usually do not have it.

With this setting, a laptop the battery guard shut down comes back as soon as
the mains returns; the wake alarm is then only a backup.

Test it as B1, but unplug and replug the AC adapter after a clean shutdown.

### B3. A UPS with shutdown signalling

For desktops and servers. A UPS with a USB or network data port can tell the
machine to shut down cleanly before the UPS battery runs out. On Linux the
usual tools are NUT (Network UPS Tools, package `nut`) and `apcupsd` for APC
units.

For automatic recovery, pair it with B1 set to "Power On": the UPS cuts its
outlets after the clean shutdown, and when mains returns it powers them
again, which the firmware sees as AC coming back. Most UPS software has a
setting for that final outlet power-off; read its manual.

Test it with the UPS software's own test mode, never by pulling power from a
running node.

### B4. Wake on LAN

Another machine on the network switches this one on. It needs wired
Ethernet (Wi-Fi wake from off is rare), firmware support for wake from off
(S5), and a second machine that is on and can send the "magic packet" when
power returns. After an outage that second machine must itself come back
first, so this suits a site where one always-on box (a router running
OpenWrt, a Raspberry Pi, a NAS) restarts the others.

Typical BIOS names: "Wake on LAN", "Power On by PCI-E/PCI", "PME Event Wake
Up", "Remote Wake Up". Turn off ErP and Deep Sleep, as in Part A.

On the node:

```
ip -br link                          # find the wired interface, e.g. enp3s0
sudo ethtool enp3s0 | grep Wake      # "Supports Wake-on: ...g..." = magic packet
sudo ethtool -s enp3s0 wol g         # turn it on for this boot
```

With NetworkManager, make it stick:

```
nmcli -g NAME connection show
sudo nmcli con mod "<name>" 802-3-ethernet.wake-on-lan magic
```

Write down the interface's MAC address: `ip link show enp3s0`. From the
other machine: `wakeonlan <MAC>` or `etherwake <MAC>`.

Caveats: many USB Ethernet adapters cannot wake a machine from off. Some
network cards do not arm Wake on LAN after a full mains loss until the
operating system has booted once. Test exactly the outage case:

1. Shut down cleanly.
2. Cut mains for 30 seconds, restore it, and leave the machine off.
3. Send the magic packet. Pass: it boots.

### B5. Servers with a management controller

IPMI, iDRAC, iLO, XClarity and other BMCs run whenever mains is present. They
can power the server on over the network, and usually also hold a
power-restore policy, the same idea as B1. With `ipmitool`, for example:

```
ipmitool -I lanplus -H <bmc-address> -U <user> -P <password> chassis power on
ipmitool chassis policy always-on          # run on the server itself
```

Set the controller's own network address and password first, and keep it on
a trusted network: it controls the machine below the operating system.

### B6. Raspberry Pi and similar single-board computers

These boot whenever power is applied; there is no setting to change. After a
clean shutdown they stay halted until power is removed and restored (or, on a
Pi 5, its power button is pressed). In an outage the power is removed, so
they boot when it returns. A Pi 5 has an RTC and can also wake by alarm while
it stays powered, as in Part A; older Pis have no RTC. Keep the block drive
on the same supply, or on a powered hub on the same UPS, so it is ready when
the Pi boots.

### B7. A smart plug, as a last resort

On a machine with B1 set to "Power On", switching its smart plug off and on
powers it up. Only do this when the machine is already off: switching the
plug off while the node runs is a hard power cut, the very thing every other
part of this setup avoids.

## Part C: which to use

| Machine | Use |
|---|---|
| Desktop, mini PC | B1 (Power On), plus B3 if it has a UPS. |
| Server | B1 or the B5 always-on policy, plus B3. |
| Business laptop | B2 if present; the battery guard's wake alarm (Part A) as a backup. |
| Consumer laptop | The battery guard's wake alarm (Part A), if Tests 1 and 2 pass. If they fail: B4 if the wired port can wake from off; otherwise someone presses the button. |
| Raspberry Pi | Nothing to set: B6. |

Whatever you choose, run its test once from a clean shutdown, and again after
any BIOS update, which can reset these settings to defaults.

## Results so far

Add your machine's result here, or send it to whoever gave you these docs.

**HP Laptop 14-fq0xxx, AMI BIOS F.52, Devuan 6.** RTC present. The BIOS has
no power-on-after-AC-loss setting and no Wake on LAN setting.

- 2026-11-04, Test 1 (AC): failed once. The alarm was set at 18:39:02,
  `rtcwake -m show` said it was due at 18:49:04, and the machine shut down
  cleanly at 18:42. It was still off at 18:54:47, when the power button was
  pressed. The lid was open. Cause: the RTC keeps local time (dual boot), and
  the laptop had run since before the 1 November daylight-saving change, so
  the RTC was an hour ahead. `rtcwake` printed the wakeup as 19:49:04 when it
  set it. The shutdown corrected the RTC, so the alarm was really for 19:49.
  Since then the guard, and Test 1 step 2, save the time to the RTC first.
- 2026-11-04, Test 2 (battery, lid open): passed. Alarm due 19:19:53, booted
  19:20:15.
- 2026-11-04, Test 1 retest (AC, lid open, RTC already correct): passed.
  Alarm due 19:55:07, booted 19:55:28.
- Test 3 (full drain): not yet run.
