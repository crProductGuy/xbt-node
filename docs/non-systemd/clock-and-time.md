# Clock and time

A node needs a correct system clock, and a laptop that uses the battery
guard's wake alarm also needs a correct hardware clock. This page covers
both.

## Run an NTP client, installed at a quiet moment

Install `chrony` and check that it starts at boot:

```
sudo apt install chrony
chronyc tracking                 # "System time" should be under 1 s
ls /etc/rc2.d | grep chrony
```

Install it when the miners are off or on another pool. On the tested laptop
the clock was 19 seconds fast with no NTP client, and chrony stepped it back
19 seconds the moment `apt` started it. The DATUM gateway lost its pool link
for about a second, the pool declined to resume, and the shares queued in
that second were discarded. The Debian and Devuan `chrony.conf` has
`makestep 1 3`: chrony steps the clock only in its first three updates, and
only if it is more than a second out; after that it adjusts gradually. So
the risky moment is the install, and each boot if the clock is far out.

## The hardware clock: UTC or local time

The computer's real-time clock (RTC) keeps time while the machine is off.
Linux reads it at boot. `/etc/adjtime` says whether it holds UTC or local
time; check with:

```
tail -1 /etc/adjtime              # UTC or LOCAL
```

- **Linux only:** UTC is the default and the simplest. Nothing on this page
  needs changing.
- **Dual boot with Windows:** Windows keeps the RTC in local time, so the
  RTC is usually set to `LOCAL` on the Linux side too, and Windows then shows
  the right time.

### With a local-time RTC

Comment out `rtcsync` in `/etc/chrony/chrony.conf` and restart chrony.
`rtcsync` makes the kernel copy the system time into the RTC every 11
minutes; the tested laptop has it off so that nothing but Linux's own
shutdown, and the battery guard, writes the local-time RTC.

Without `rtcsync`, Linux writes the RTC only at shutdown. So a machine that
stays up across a daylight-saving change has an RTC an hour off until its
next shutdown. Most of the time that does not matter, because the shutdown
puts it right.

It matters for wake alarms. `rtcwake` counts from the RTC's own time, so an
alarm set "60 minutes from now" with the RTC an hour off lands an hour late
(autumn) or an hour early, often already in the past (spring), and the
machine never wakes. This happened on the tested laptop on 4 November 2026,
three days after the change; [Results so far](power-recovery.md#results-so-far)
has the detail.

The [battery guard](battery-guard.md) handles this: it runs
`hwclock --systohc` just before it sets its alarm. That follows
`/etc/adjtime`, so a local-time RTC stays local and a UTC one stays UTC. When
you set an alarm by hand, as in the [wake tests](power-recovery.md#part-a-the-battery-guards-wake-alarm),
run the same line first:

```
sudo /sbin/hwclock --systohc
```
