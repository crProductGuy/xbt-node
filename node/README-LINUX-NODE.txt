README-LINUX-NODE.txt
Bring up an XBT node (Bitcoin Knots, Blake2b fork, rdts rules) on Linux from this drive
Written 2026-10-04 on the Windows PC (Ryzen2), revised 2026-10-11 for ext4, and rewritten
2026-10-17 after the bring-up on the HP 14 actually ran.

STATUS (2026-10-17): DONE AND RUNNING on the HP 14 (Devuan 6, sysvinit) under PATUM 0.5.3.
Everything below marked "verified" was run there. The Ubuntu files are untested.

The chain: XBT = Bitcoin with Blake2b proof of work, a strict spam-hostile chain with
rules taken from BIP-110. Every node here MUST run  consensusrules=rdts.
This drive is ext4 (one GPT partition, label knots-blocks). Windows cannot read it.


========================================================================
1. WHAT IS ON THIS DRIVE
========================================================================

  blocks/                  868 GB of block files (blk*.dat, rev*.dat, xor.dat). The node
                           reads and writes these here, through  blocksdir=/mnt/passport.
  blocks/index/            the snapshot's block index. A COPY goes to the data directory
                           on the SSD; Knots never uses this one (see the note below).
  chainstate/              11.5 GB snapshot of the UTXO database. A COPY goes to the SSD.
                           blocks/index/ and chainstate/ here are the RESTORE POINT.
                           Never change them.
  chainstate.sha256        SHA-256 of chainstate/, blocks/index/ and blocks/xor.dat.
                           Stays valid for good, because the node never writes them.
  blocks.sha256            SHA-256 of every blk/rev file as copied. Valid only until a
                           node first runs (it appends to the newest files). Passed in full
                           on the HP 14, 2026-10-17 (seed-node.full-check-passed).
  snapshot-info.txt        file counts, sizes and the source node's last tip lines
  make-ext4-seed.log       log of the run that formatted and filled this drive
  seed-node.*              markers written by seed-node.sh

  README-LINUX-NODE.txt    this file
  seed-node.sh             the bring-up script                       [verified, Devuan]
  install-autostart.sh     installs both start-at-boot scripts        [Devuan only]
  devuan-bitcoind.init     node: start at boot, clean stop            [Devuan only]
  devuan-datum-gateway.init  DATUM gateway: start at boot             [Devuan only]
  ubuntu-bitcoind.service  node as a systemd unit                     [Ubuntu, untested]

  NOTE: Knots keeps blocks/index in the DATA DIRECTORY even when blocksdir is set
  (Bitcoin Core doc/files.md: "-blocksdir option does not affect this path"). An earlier
  version of this file and of seed-node.sh left the index on the drive; that was wrong.

The snapshot:
  taken          2026-10-15 22:29 UTC, from one clean shutdown of the PC's node
  height         977438
  block hash     0000000000000000480223f956923f33bd415771a33e7ccb404a591d3c260660
  source         Bitcoin Knots v29.4.2.knots20260508, Blake2b fork build, Windows
  rules          consensusrules=rdts (the PC keeps it in settings.json)
  not included   wallets (they stay on the PC), peers, mempool, txindex
  blake2b_headline, which the PC's bitcoin.conf also has, is regtest-only in this build
  and is not needed on the real network.


========================================================================
2. THE HP 14 AS BUILT (verified 2026-10-17)
========================================================================

  PATUM folder     ~/pyblock-node/
    program        pyblock-datum-installer-linux-amd64   (current; older ones kept as -0.5.x)
    node           bin/bitcoind, bin/bitcoin-cli          (Knots v29.4.2.knots20260508)
    data dir       data/   (bitcoin.conf, chainstate/, blocks/index/, indexes/txindex)
  gateway          ~/pyblock-gateway/datum_gateway -c wavicles.json   (log wavicles.log)
  drive            /mnt/passport, from /etc/fstab by UUID, options noatime,nofail
  bitcoin.conf     PATUM writes it and edits it in place; ours are the last lines:
                     blocksdir=/mnt/passport
                     consensusrules=rdts
                   PATUM also sets txindex=1 (built from scratch; ~70 GB, many hours).
  miners           stratum+tcp://<HP 14 address>:23334   (the gateway listens on all
                   interfaces). Keep the old pool as pool 2 for failover.
  gateway status   http://127.0.0.1:7152 on the HP 14 only.

  Everyday commands (the cli needs -datadir, because the data is not in ~/.bitcoin):
    C="$HOME/pyblock-node/bin/bitcoin-cli -datadir=$HOME/pyblock-node/data"
    $C getblockchaininfo        $C getindexinfo        $C stop


========================================================================
3. BRING-UP ON A NEW MACHINE OR A REINSTALL (what was done on the HP 14)
========================================================================

Do everything as the normal user who will own the node, not as root.

3.1  Devuan packages, as root:  apt install sudo chrony   then  adduser YOURNAME sudo
     For PATUM's gateway build:  apt install curl git cmake build-essential pkgconf
                                 libcurl4-openssl-dev libjansson-dev libsodium-dev
                                 libmicrohttpd-dev

3.2  Install PATUM (pyblock.xyz, check the download against its SHA256SUMS.txt) and let
     it install its node. If it starts syncing, STOP THE NODE, not just the panel:
       ~/pyblock-node/bin/bitcoin-cli -datadir=$HOME/pyblock-node/data stop
     (PATUM before 0.5.3 left bitcoind running when you pressed Stop.)
     Then delete its partial sync:  rm -r ~/pyblock-node/data/{blocks,chainstate,indexes}

3.3  Add the two lines to ~/pyblock-node/data/bitcoin.conf:
       blocksdir=/mnt/passport
       consensusrules=rdts

3.4  Plug in this drive, copy the script off it and run it:
       cp /mnt/WHEREVER/seed-node.sh ~/
       DATADIR=$HOME/pyblock-node/data BITCOIND=$HOME/pyblock-node/bin/bitcoind \
         BITCOIN_CLI=$HOME/pyblock-node/bin/bitcoin-cli bash ~/seed-node.sh
     Run it inside tmux (tmux new -s seed), because stage 2a takes hours.

     Stage 0  checks: x86-64, Knots version, no node running, clock not in the past
     Stage 1  mounts the drive at /mnt/passport, adds it to /etc/fstab (asks first,
              backs fstab up to /etc/fstab.before-seed-node), hands the files to you
     Stage 2a SHA-256 of every block file (about 2.5 h at 92 MB/s on the HP 14).
              Skipped once a node has run against the drive.
     Stage 2  checks chainstate/, blocks/index/ and xor.dat on the drive
     Stage 3  copies chainstate/ AND blocks/index/ to the data directory, checks the
              copy. It refuses while the data directory has chainstate/, blocks/ or
              indexes/ from an earlier sync.
     Stage 4  checks bitcoin.conf has blocksdir=/mnt/passport and consensusrules=rdts
     Stage 5  starts the node with no network, confirms height 977438 and its hash,
              stops it again

3.5  Start the node:  ~/pyblock-node/bin/bitcoind -datadir=$HOME/pyblock-node/data -daemon
     It fetches only the blocks since the snapshot, then builds txindex for hours.

3.6  Start PATUM again; it keeps its saved answers and builds the DATUM gateway.

3.7  Start at boot: section 4.


========================================================================
4. START AT BOOT  [DEVUAN]   files: install-autostart.sh and the two .init files
========================================================================

PATUM's own start-at-boot files are systemd units, so on Devuan nothing it sets up
starts at boot. These two scripts do it:

  bitcoind        waits up to 90 s for the drive, never starts without it, stops the
                  node with TERM and waits up to 15 min for a clean exit (never kills)
  datum-gateway   starts after bitcoind, waits in the background (up to 1 h) until the
                  node answers RPC, then runs the gateway; stops BEFORE the node

  Install (copy the three files to ~/init first):
    sudo sh ~/init/install-autostart.sh YOURNAME
  It changes nothing that is running; the scripts take over at the next boot.

  Everyday:   sudo service bitcoind status|start|stop    (same for datum-gateway)
  Remove:     sudo update-rc.d datum-gateway remove ; sudo update-rc.d bitcoind remove

  Test it once: sudo reboot, then check both services, that the miners are back on
  this node, and that in debug.log the line before the newest start is "Shutdown: done".
  Also set the BIOS to power on when AC returns, or a power cut leaves it off.

  The PATUM panel itself is not started at boot. Start it by hand when you need it.


========================================================================
5. RULES FOR RUNNING ON THIS DRIVE
========================================================================

  - Stop the node before shutting down by hand, and before unplugging the drive.
  - Never start the node if /mnt/passport is not mounted. (The empty mount point is
    made immutable, so this fails loudly instead of filling the SSD.)
  - Leave chainstate/, blocks/index/ and chainstate.sha256 on the drive untouched.
  - Updating PATUM: download the new file, check it against SHA256SUMS.txt, rename the
    current one to ...-<old version>, move the new one in, chmod +x, run it. Afterwards
    check that bitcoin.conf still has blocksdir and consensusrules=rdts.


========================================================================
6. IF SOMETHING GOES WRONG
========================================================================

  The SSD copy of chainstate or blocks/index is damaged
      Stop the node. Move away data/chainstate, data/blocks, data/indexes and
      data/seed-node.copied. Run seed-node.sh again: it restores the snapshot from the
      drive. The node then fetches from the network the blocks since 977438 (the block
      files on the drive written after the snapshot are simply reused or overwritten)
      and rebuilds txindex.

  Stage 5 fails
      Read the end of data/debug.log. Do NOT add -reindex because a message suggests
      it. Likely causes: the wrong binary, or a missing line in bitcoin.conf.

  The drive was unplugged or lost power while the node ran
      sudo umount /mnt/passport ; sudo fsck.ext4 -f /dev/sdX1 ; mount ; start.

  Last resort: rebuild chainstate from the blocks:  bitcoind ... -reindex-chainstate
      Several days on the HP 14. Everything above is cheaper.

WARNING about syncing from the PC again: once a Linux node has run against this drive,
its block files differ from the PC's. Refilling from the PC means a FULL restore from a
live USB session on the PC: stop Bitcoin there, run make-manifest.ps1, boot the live USB,
and run make-ext4-seed.sh (it keeps the format). Both are in the seed/
folder of the xbt-node repo.
