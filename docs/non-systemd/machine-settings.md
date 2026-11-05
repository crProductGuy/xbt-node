# Machine settings

The settings outside the scripts: firmware, lid, power, network, the block
drive and the PATUM panel. They come from setting up one laptop between
October and November 2026 (see [Tested on](README.md#tested-on)). Other
machines name things differently.

The goal behind every setting: the node must never stop uncleanly. That means
no suspend, no hibernate, and no battery running flat while the node is up.
After an outage it should come back with nobody at the keyboard.

## Firmware (BIOS or UEFI)

- **Power on when AC returns.** Set it to "Power On" if your machine has it,
  not "Last State". [Power recovery](power-recovery.md#part-b-other-ways-to-come-back-on)
  lists the usual names and how to test it. Many consumer laptops, including
  the tested one, do not have it.
- **Wake from off by the clock alarm.** The battery guard uses it when there
  is no AC power-on. Test it:
  [Power recovery](power-recovery.md#part-a-the-battery-guards-wake-alarm),
  Part A.
- **Halt means power off.** Check that `/etc/default/halt` has
  `HALT=poweroff`, so `shutdown -h` switches the machine fully off instead of
  leaving it halted with power on. A machine left halted never sees a wake
  alarm or a power-on.

## Laptop lid

Closing the lid must never suspend the machine. In
`/etc/elogind/logind.conf`, under the `[Login]` section:

```
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
```

To add them one line at a time, after checking that `[Login]` is the last
section of the file (`grep -n '^\[' /etc/elogind/logind.conf`):

```
F=/etc/elogind/logind.conf
echo HandleLidSwitch=ignore | sudo tee -a $F
echo HandleLidSwitchExternalPower=ignore | sudo tee -a $F
```

Then reboot, or restart elogind, and check with
`grep ^HandleLid /etc/elogind/logind.conf`.

In the Xfce power manager, set "When laptop lid is closed" to "Switch off
display", both on battery and plugged in.

## Power and battery

- Install the [battery guard](battery-guard.md), and set the desktop's own
  critical-battery action to Shutdown below the guard's level.
- No suspend or hibernate from anywhere else. The screensaver and display
  power settings should blank the screen only. Leave the power-button action
  at its default, or set it to "Ask", so a bump does not suspend the machine.
- A small UPS for the router, the switch and any dock keeps the miners
  connected to the node through short outages. Without one, the network drops
  even while the laptop keeps running on its battery.

## Clock

Run an NTP client, and take care with the hardware clock if the machine dual
boots Windows: [Clock and time](clock-and-time.md).

## Network

- **Wired Ethernet, with a fixed address set on the machine itself.** The
  miners point at the node's address, so it must not change. A router
  reservation is tied to the network adapter's MAC address: when the tested
  laptop's USB Ethernet adapter was swapped, it got a new address and the
  miners lost the node. Setting the address on the machine as well
  (NetworkManager, `ipv4.method manual`) fixes that.
- **Give each miner a second pool.** While the node or gateway is down, for a
  reboot, an update or an outage, the miners fail over to it instead of
  stopping.
- **SSH, key-only.** Managing the node from another machine is easier than
  working at it. Use keys, and turn off password login.

## External block drive

Skip this with the blocks on the internal disk.

- **Mount it with `nofail`.** Give it an ext4 entry in `/etc/fstab` with
  `noatime,nofail`, so a missing drive does not stop the boot.
  [The block-drive check](install.md#the-block-drive-check) then keeps the
  node from starting until the drive is there.
- **Plug it into the machine's own USB port,** not a dock or a hub, so a dock
  losing power cannot pull the drive from under a running node.

## The PATUM panel

On Devuan nothing starts the panel at boot. Start it by hand when needed,
with a fixed port so its address stays the same from one start to the next:

```
~/pyblock-node/bin/patum -port 32999
```

Add `-no-open` when working over SSH.

## What software cannot cover

None of these get a clean stop:

- holding the power button for 4 seconds, which forces the machine off;
- pulling the block drive's cable while the node runs;
- a kernel hang.
