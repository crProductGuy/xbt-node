# Build tools for the DATUM gateway

A supplement to PATUM's own install instructions. PATUM builds the DATUM
gateway from source on your machine. A stock Devuan install does not have the
compiler, build tools or libraries for that, so the build fails until they
are added. Other minimal Debian-family installs are likely to be the same.

Install them all before you start PATUM's gateway setup, so you do not meet
each missing piece one failed build at a time.

## The packages

These nine were missing on a fresh Devuan 6 desktop install, and are exactly
what the tested laptop needed (from its `apt` history, 17 October 2026):

| Package | What it is for |
|---|---|
| `curl` | Downloading files from the command line |
| `git` | Fetching the gateway's source code |
| `cmake` | The gateway's build system |
| `build-essential` | The C compiler, `make` and the standard headers |
| `pkgconf` | Lets the build find the libraries below |
| `libcurl4-openssl-dev` | HTTP library, for talking to the node and the pool |
| `libjansson-dev` | JSON library |
| `libsodium-dev` | Cryptography library, for the DATUM protocol |
| `libmicrohttpd-dev` | Small web server library, for the gateway's status page |

## Install them

As root, or with `sudo`, one line at a time:

```
sudo apt update
sudo apt install curl git cmake build-essential pkgconf
sudo apt install libcurl4-openssl-dev libjansson-dev
sudo apt install libsodium-dev libmicrohttpd-dev
```

No `sudo` yet? On a fresh Devuan install, become root with `su -`, then run
`apt install sudo` and `adduser YOURNAME sudo`, and log in again.

## Check what you already have

This prints only the packages that are missing; no output means all are
installed:

```
for p in curl git cmake build-essential pkgconf libcurl4-openssl-dev libjansson-dev libsodium-dev libmicrohttpd-dev; do dpkg -s $p >/dev/null 2>&1 || echo "missing: $p"; done
```

## Also useful

Not needed for the build, but installed on the tested laptop:

- `tmux`: keeps a terminal session running when an SSH connection drops,
  handy for a long sync or build over SSH.
- `chrony`: keeps the clock right. Install it at a quiet moment; see
  [Clock and time](clock-and-time.md).

## Other distributions

The names above are Debian and Devuan package names. On other distributions
look for the same libraries under their own names: libcurl, jansson,
libsodium and libmicrohttpd, each with its development headers (often a
`-dev` or `-devel` package), plus a C compiler, `make`, `cmake`, `pkg-config`
and `git`. These are untested; the list was checked only on Devuan 6.
