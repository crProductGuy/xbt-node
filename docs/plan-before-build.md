# Runbook: full Knots (BLAKE2b) node + PATUM on Devuan 6.1.1

Written 2026-10-11. **Nothing in this file has been run on the laptop.** Commands are
written from the documentation and from how Knots and Devuan behave in general. Each phase
ends with a check; do not start the next phase until the check passes.

## Goal and done-when

- **Goal:** the Athlon laptop runs a full, unpruned Knots 29.4.2 node on the BLAKE2b chain,
  with `chainstate` and the block index on the internal SSD and the block files on the
  external exFAT HDD, plus the PATUM gateway and the Blake2b ASIC Control tuner.
- **Done when:** after a cold power-on with nobody logging in, the node reports
  `"pruned": false` at the current height, the gateway accepts a miner, and the tuner page
  opens.

## Things that are still unknown

| Unknown | Where it bites | How it gets settled |
|---|---|---|
| Does PATUM's Linux installer need systemd? | Phase 6 and 8 | The author's answer, or the `grep` in step 6.1 |
| Does PATUM set prune on the launch command as well as in `bitcoin.conf`? | Phase 6 | The read-only first start in step 6.5 |
| Which user PATUM runs the node as | Phases 4 and 5 | `ps` in step 6.6 |
| Where PATUM puts its binaries and `bitcoin.conf` | Phases 6 and 8 | The `find` in step 6.3 |
| Folder layout on the HDD | Phases 4 and 5 | `ls` in step 4.4 |
| Whether Devuan boots with Secure Boot on | Phase 2 | Try it; turn it off if the USB will not boot |
| P2P port of the BLAKE2b chain (assumed 8333) | Phase 9 | `bitcoin-cli getnetworkinfo` |

Placeholders used below. Replace them everywhere:

- `nodeuser` is the Linux user name.
- `/srv/knots` is the node's data directory on the SSD.
- `/mnt/chain` is where the HDD mounts. Block files are expected at `/mnt/chain/blocks/`.
- `XXXX-XXXX` is the HDD's exFAT UUID.
- `192.168.X.0/24` is the home LAN.

---

## Phase 1: prepare on the Windows machine

1. Stop the Windows node and refresh the HDD copy one last time, the same way as before, so
   the laptop has less to catch up.
2. Note the Windows node's block height at the moment it stopped. Phase 7 compares
   against it.
3. Download the Devuan 6.1.1 amd64 **desktop installer** ISO and its `SHA256SUMS` from
   `https://files.devuan.org/devuan_excalibur/installer-iso/`.
4. Check the download in PowerShell and compare the hash with the line in `SHA256SUMS`:

   ```powershell
   Get-FileHash .\devuan_excalibur_6.1.1_amd64_desktop.iso -Algorithm SHA256
   ```

5. Write the ISO to a USB stick with Rufus in DD image mode.

**Check:** the hash matches and the stick is written.

## Phase 2: install Devuan

Decide the disk first:

- **Option A (recommended): swap in the 128 GB SSD.** The 480 GB Windows drive goes on a
  shelf untouched. Devuan takes the whole disk.
- **Option B: dual boot on the 480 GB drive.** Before installing, in Windows: save the
  BitLocker recovery key, run `powercfg /h off` in an admin prompt to disable Fast Startup,
  and shrink C: in Disk Management by at least 60 GB.

Then:

1. In the firmware setup, set USB first in the boot order. If the stick does not boot,
   turn Secure Boot off.
2. Boot the stick and choose the graphical install.
3. At the network step, pick the Wi-Fi adapter and join the network. **This is the Wi-Fi
   test. If no wireless adapter is offered, stop here**; nothing has been written to disk.
4. Leave the root password empty so that `nodeuser` gets `sudo`. (This is Debian installer
   behaviour and Devuan's installer is derived from it. If `sudo` does not work after
   install, log in as root and run `adduser nodeuser sudo`.)
5. Partitioning: "Guided, use entire disk" for option A, or "Guided, use the largest
   continuous free space" for option B. **Do not choose encryption**, or the node cannot
   restart unattended.
6. Software: Xfce desktop, SSH server, standard system utilities.
7. Init system: keep the default, `sysvinit`.
8. Finish and reboot into Devuan.

**Check:**

```sh
cat /etc/devuan_version      # excalibur, 6.x
ps -p 1 -o comm=             # init
ip -4 addr show              # the Wi-Fi interface has an address
sudo true && echo sudo-ok
```

## Phase 3: base system

1. Update and install tools:

   ```sh
   sudo apt update && sudo apt full-upgrade -y
   sudo apt install -y curl wget rsync jq htop ufw chrony exfatprogs hdparm \
       smartmontools netcat-openbsd
   ```

2. Stop the laptop from sleeping when the lid closes:

   ```sh
   sudo sed -i \
     -e 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' \
     -e 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' \
     -e 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' \
     /etc/elogind/logind.conf
   grep -n '^HandleLid' /etc/elogind/logind.conf
   ```

3. In Xfce, open Settings, Power Manager. On both the "On battery" and "Plugged in" tabs
   set "When laptop lid is closed" to "Switch off display" and system sleep to "Never".
4. Turn off USB autosuspend for the HDD. Edit `/etc/default/grub` and add
   `usbcore.autosuspend=-1` inside the quotes of `GRUB_CMDLINE_LINUX_DEFAULT`, then:

   ```sh
   sudo update-grub
   ```

5. If NetworkManager manages the Wi-Fi (`nmcli -v` prints a version), turn off Wi-Fi power
   saving:

   ```sh
   printf '[connection]\nwifi.powersave = 2\n' | \
     sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf
   ```

6. On the router, give the laptop a fixed address (a DHCP reservation). The miners will
   point at it.
7. In the firmware setup, turn on "power on when AC is restored" if the laptop offers it.
8. Reboot.

**Check:**

```sh
cat /sys/module/usbcore/parameters/autosuspend    # -1
chronyc tracking | head -3                        # clock is synchronised
```

Close the lid for a minute, open it, and confirm the session is still there.

## Phase 4: mount the HDD

1. Plug in the HDD and find the exFAT partition and its UUID:

   ```sh
   lsblk -f
   ```

2. Create the mount point and note your user and group numbers:

   ```sh
   sudo mkdir -p /mnt/chain
   id -u; id -g
   ```

3. Add one line to `/etc/fstab` with `sudoedit /etc/fstab`. Use the numbers from `id`:

   ```
   UUID=XXXX-XXXX  /mnt/chain  exfat  uid=1000,gid=1000,umask=022,noatime,nofail  0  0
   ```

   exFAT has no file ownership of its own. The `uid` and `gid` here decide who can write,
   so if step 6.6 shows PATUM running the node as another user, come back and change them.

4. Mount and look at the layout:

   ```sh
   sudo mount -a
   mountpoint /mnt/chain
   ls /mnt/chain
   ls /mnt/chain/blocks | head
   ls /mnt/chain/blocks/index | head -3
   ls /mnt/chain/chainstate | head -3
   touch /mnt/chain/.write-test && rm /mnt/chain/.write-test && echo writable
   ```

   The rest of this runbook assumes `blk*.dat` and `rev*.dat` are in `/mnt/chain/blocks/`.
   If they sit somewhere else, `blocksdir` in step 6.4 must be the folder that **contains**
   the `blocks` folder, not the `blocks` folder itself.

5. Stop the drive from spinning down. Many USB enclosures ignore this; it does no harm to
   try:

   ```sh
   sudo hdparm -B 254 -S 0 /dev/sdX      # the disk from lsblk, not the partition
   ```

   To make it stick, add to `/etc/hdparm.conf`:

   ```
   /dev/disk/by-uuid/XXXX-XXXX {
       apm = 254
       spindown_time = 0
   }
   ```

**Check:** `mountpoint /mnt/chain` says it is a mount point, the three `ls` commands show
files, and `writable` printed.

## Phase 5: copy chainstate and the block index to the SSD

1. Create the data directory:

   ```sh
   sudo mkdir -p /srv/knots/blocks
   sudo chown -R nodeuser:nodeuser /srv/knots
   ```

2. Copy only these two folders. **Do not copy `bitcoin.conf`** from the Windows data; Knots
   refuses to start if the redirected data directory holds a second conf file.

   ```sh
   rsync -a --info=progress2 /mnt/chain/chainstate    /srv/knots/
   rsync -a --info=progress2 /mnt/chain/blocks/index  /srv/knots/blocks/
   ```

3. Compare sizes and file counts with the source:

   ```sh
   du -sh /mnt/chain/chainstate /srv/knots/chainstate
   du -sh /mnt/chain/blocks/index /srv/knots/blocks/index
   find /mnt/chain/chainstate -type f | wc -l; find /srv/knots/chainstate -type f | wc -l
   ls /srv/knots
   ```

**Check:** sizes and counts match, and `/srv/knots` holds only `blocks` and `chainstate`.

## Phase 6: PATUM, with the pause

1. Download the installer script and read it before running it. It takes your payout
   address.

   ```sh
   curl -fsSL https://b.pyblock.xyz:8443/setup -o ~/patum-setup.sh
   less ~/patum-setup.sh
   grep -n -i -E 'systemctl|systemd|\.service|prune|datadir|useradd|sudo' ~/patum-setup.sh
   ```

   If `systemctl` appears, the installer expects systemd. It may still install the
   binaries and fail only at the service step; Phase 8 replaces that step on Devuan. If it
   refuses to run at all, stop and ask the author for the manual setup.

2. Run it with your pool and address (the page's own form of the command), and **stop at
   the pause**:

   ```sh
   sh ~/patum-setup.sh chirp YOUR_PAYOUT_ADDRESS
   ```

3. In a second terminal, find what it installed:

   ```sh
   sudo find / -xdev -name bitcoin.conf -newer ~/patum-setup.sh 2>/dev/null
   sudo find / -xdev \( -name bitcoind -o -name 'datum_gateway*' \) -newer ~/patum-setup.sh 2>/dev/null
   ```

   Write the three paths down: `bitcoin.conf`, `bitcoind`, and the gateway. Check the Knots
   version; it must be 29.4.2 or newer:

   ```sh
   /path/to/bitcoind --version | head -1
   ```

4. Edit that `bitcoin.conf`. Delete every `prune=` line, then add:

   ```
   datadir=/srv/knots
   blocksdir=/mnt/chain
   ```

   Confirm:

   ```sh
   grep -n -i -E 'prune|datadir|blocksdir' /path/to/bitcoin.conf
   ```

5. **Make the first start harmless.** Remount the HDD read-only, so that nothing can be
   deleted or overwritten whatever the launch settings turn out to be:

   ```sh
   sudo mount -o remount,ro /mnt/chain
   ```

   Now click Continue (or press the key the installer asks for). The node is expected to
   fail or complain, because it cannot write to the blocks folder. That is the point.

6. Read what it was launched with:

   ```sh
   ps -eo user,pid,args | grep -E '[b]itcoind'
   grep -n -i -E 'prune|Using data directory|Config file arg|Command-line arg' \
       /srv/knots/debug.log | tail -20
   ```

   - If `prune` appears on the command line or in the log, **stop**. Do not remount
     read-write. Ask the author how to remove it.
   - If the data directory in the log is not `/srv/knots`, the launch command overrides the
     conf file. Stop and ask the author.
   - Note the user in the first column. If it is not `nodeuser`, fix `/etc/fstab` (step 4.3)
     and run `sudo chown -R thatuser /srv/knots`.

7. If the log is clean, stop the node if it is still running, remount read-write, and start
   it again the way PATUM starts it:

   ```sh
   sudo mount -o remount,rw /mnt/chain
   ```

**Check:** no `prune` anywhere in `ps` or `debug.log`, and the log names `/srv/knots`.

## Phase 7: confirm the node

Run this within the first minute of the real start. Add `-conf=/path/to/bitcoin.conf` if
`bitcoin-cli` cannot find the node:

```sh
bitcoin-cli -datadir=/srv/knots getblockchaininfo | \
  jq '{chain, blocks, headers, pruned, initialblockdownload, size_on_disk}'
```

- `pruned` must be `false`.
- `blocks` must be at or just above the height noted in Phase 1, never near zero.
- `size_on_disk` should be in the hundreds of gigabytes.

**If `pruned` is `true` or `blocks` is near zero, stop the node immediately**
(`bitcoin-cli -datadir=/srv/knots stop`) and do not restart it. The Windows node is the
fallback for re-copying the HDD.

Then watch it catch up, and confirm the gateway:

```sh
tail -f /srv/knots/debug.log                       # UpdateTip lines, height rising
bitcoin-cli -datadir=/srv/knots getnetworkinfo | jq '{subversion, connections, localaddresses}'
ps -eo user,pid,args | grep -E '[d]atum'
sudo ss -ltnp | grep -E 'bitcoind|datum'           # listening ports
```

Note the gateway's Stratum port from the `ss` output for Phase 9.

**Check:** `initialblockdownload` turns `false`, and the gateway process is listening.

## Phase 8: start at boot on sysvinit

Skip this phase if PATUM already starts both programs after a reboot (test: reboot, do not
log in, and run the Phase 10 checks from another machine).

Otherwise create two init scripts. Fill in the variables at the top of each from step 6.3.

`/etc/init.d/knots`:

```sh
#!/bin/sh
### BEGIN INIT INFO
# Provides:          knots
# Required-Start:    $remote_fs $network $time
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Bitcoin Knots node
### END INIT INFO

RUNAS=nodeuser
BITCOIND=/path/to/bitcoind
CONF=/path/to/bitcoin.conf
MNT=/mnt/chain
PIDFILE=/run/knots/bitcoind.pid

# USB disks can appear after the boot-time mount pass, so wait for the HDD here.
wait_mount() {
    i=0
    while ! mountpoint -q "$MNT"; do
        mount "$MNT" 2>/dev/null
        i=$((i + 1))
        [ "$i" -ge 30 ] && return 1
        sleep 2
    done
    [ -d "$MNT/blocks" ]
}

case "$1" in
start)
    if ! wait_mount; then
        echo "knots: $MNT is not mounted, not starting"
        exit 1
    fi
    mkdir -p /run/knots && chown "$RUNAS" /run/knots
    start-stop-daemon --start --quiet --chuid "$RUNAS" --pidfile "$PIDFILE" \
        --exec "$BITCOIND" -- -daemon -conf="$CONF" -pid="$PIDFILE"
    ;;
stop)
    # Knots can take minutes to flush. Never send KILL.
    start-stop-daemon --stop --quiet --retry TERM/600 --pidfile "$PIDFILE"
    ;;
status)
    start-stop-daemon --status --pidfile "$PIDFILE" && echo running || echo stopped
    ;;
restart)
    "$0" stop
    "$0" start
    ;;
*)
    echo "Usage: $0 {start|stop|status|restart}"
    exit 1
    ;;
esac
```

The script refuses to start the node when the HDD is missing. That is deliberate: a node
that starts against an empty `/mnt/chain` would begin a fresh sync onto the SSD.

`/etc/init.d/datum`:

```sh
#!/bin/sh
### BEGIN INIT INFO
# Provides:          datum
# Required-Start:    $remote_fs $network knots
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: DATUM gateway (PATUM)
### END INIT INFO

RUNAS=nodeuser
GATEWAY=/path/to/datum_gateway
CONFIG=/path/to/datum_gateway_config.json
CLI="/path/to/bitcoin-cli -conf=/path/to/bitcoin.conf"
LOG=/var/log/datum.log
PIDFILE=/run/datum.pid

case "$1" in
start)
    touch "$LOG" && chown "$RUNAS" "$LOG"
    # Wait for the node's RPC in the background so boot is not held up.
    start-stop-daemon --start --quiet --background --make-pidfile --pidfile "$PIDFILE" \
        --chuid "$RUNAS" --startas /bin/sh -- -c \
        "until $CLI getblockcount >/dev/null 2>&1; do sleep 5; done; exec $GATEWAY -c $CONFIG >>$LOG 2>&1"
    ;;
stop)
    start-stop-daemon --stop --quiet --retry TERM/30/KILL/5 --pidfile "$PIDFILE"
    ;;
status)
    start-stop-daemon --status --pidfile "$PIDFILE" && echo running || echo stopped
    ;;
restart)
    "$0" stop
    "$0" start
    ;;
*)
    echo "Usage: $0 {start|stop|status|restart}"
    exit 1
    ;;
esac
```

Copy the gateway's real launch arguments from the `ps` output in Phase 7 if they differ
from `-c config`.

Enable both. Stop the copies PATUM started first, so two nodes never run against one data
directory:

```sh
bitcoin-cli -datadir=/srv/knots stop
sudo chmod +x /etc/init.d/knots /etc/init.d/datum
sudo update-rc.d knots defaults
sudo update-rc.d datum defaults
sudo service knots start
sudo service datum start
sudo service knots status; sudo service datum status
```

**Check:** both report `running`, and the Phase 7 commands still give the same answers.

## Phase 9: firewall and router

Find the LAN range and set the rules. Replace `23334` with the Stratum port seen in
Phase 7, and `8333` if `getnetworkinfo` shows a different P2P port.

```sh
ip -4 route | grep -v default
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 8333/tcp
sudo ufw allow from 192.168.X.0/24 to any port 23334 proto tcp
sudo ufw allow from 192.168.X.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

On the router, forward the P2P port to the laptop. Without it the node validates everything
but serves blocks to almost nobody.

**Check:** after an hour, `bitcoin-cli -datadir=/srv/knots getnetworkinfo | jq .connections_in`
is above zero.

## Phase 10: the tuner

Blake2b ASIC Control already runs under plain Docker on the Ubuntu machine, so no Umbrel is
needed. Copy the `blake2b-asic-control/app` folder to the laptop, then:

```sh
sudo apt install -y docker.io
sudo adduser nodeuser docker          # log out and in again afterwards
sudo service docker status

cd ~/blake2b-asic-control/app
docker build -t blake2b-asic-control:1.10.1 .
mkdir -p data
docker run -d --name blake2b --restart unless-stopped \
  -p 127.0.0.1:8787:8787 \
  -e SCLITE_WIDGET_POLL_S=86400 \
  -v "$PWD/data:/data" \
  blake2b-asic-control:1.10.1
```

These are the commands recorded in the `blake2b-asic` project's README. `data/` must be
owned by uid 1000. The page is at `http://127.0.0.1:8787` on the laptop itself.

**Do not run this copy and the Ubuntu machine's copy against the same miner at once.**

## Phase 11: acceptance test

1. Shut the laptop down completely, then power it on. **Do not log in.**
2. From another machine on the LAN, after about five minutes:

   ```sh
   nc -zv LAPTOP_ADDRESS 23334        # Stratum port answers
   ssh nodeuser@LAPTOP_ADDRESS
   ```

3. Over SSH:

   ```sh
   mountpoint /mnt/chain
   sudo service knots status; sudo service datum status
   bitcoin-cli -datadir=/srv/knots getblockchaininfo | jq '{blocks, headers, pruned}'
   docker ps --filter name=blake2b
   ```

4. Point one miner at `LAPTOP_ADDRESS:23334` and confirm accepted shares in the gateway
   log or dashboard.

**Done when** all four pass without anyone touching the laptop's keyboard.

## If something goes wrong

| Symptom | Likely cause | Action |
|---|---|---|
| Node asks to reindex | `chainstate`, index and block files are not from the same moment | Stop. Do not reindex on this CPU; re-copy all three from the Windows node. |
| "Cannot obtain a lock" on start | A second `bitcoind` is running, or the HDD is read-only | `ps -e \| grep bitcoind`; `mount \| grep chain` |
| Node stops with a disk error | HDD dropped off USB | `dmesg \| tail -30`; check the cable and power; `sudo fsck.exfat /dev/sdX1` with the node stopped |
| Node not running after a reboot | HDD was slow to appear | `sudo service knots start`; if it recurs, raise the `30` in `wait_mount` |
| Gateway hands out no work | Node still catching up | Wait for `initialblockdownload` to turn `false` |
