#!/usr/bin/env python3
"""Build the Devuan (non-systemd) bundle sent to PyBLOCK.

Usage: python tools/make-pyblock-bundle.py YYYY-MM-DD OUTDIR

Writes into OUTDIR (which must not already hold these files):
  devuan-patum-scripts-YYYY-MM-DD.zip  the 7 scripts, the 9 guides and
                                       SHA256SUMS, in one folder
  SHA256SUMS                           the scripts' checksums, also in the zip
  devuan-patum-scripts-YYYY-MM-DD.zip.sha256

The zip is reproducible: same repo files and same date give the same bytes.
Every entry carries the date at 12:00, and the scripts are mode 755, the guides
and SHA256SUMS 644. Files go in byte for byte, so LF endings stay LF.
"""
import hashlib
import io
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# Order as published in reference.md and the first bundle's SHA256SUMS.
SCRIPTS = [
    "devuan-bitcoind.init",
    "devuan-datum-gateway.init",
    "devuan-patum-panel.init",
    "install-autostart.sh",
    "install-panel-autostart.sh",
    "battery-guard.sh",
    "install-battery-guard.sh",
]
GUIDES = [
    "README.md",
    "battery-guard.md",
    "build-tools.md",
    "clock-and-time.md",
    "install.md",
    "machine-settings.md",
    "power-recovery.md",
    "reference.md",
    "troubleshooting.md",
]
FOLDER = "devuan-patum-scripts"


def read(path):
    with open(path, "rb") as f:
        return f.read()


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    date, out = argv[1], argv[2]
    try:
        y, m, d = (int(x) for x in date.split("-"))
        assert len(date) == 10 and 1980 <= y <= 2107 and 1 <= m <= 12 and 1 <= d <= 31
    except (ValueError, AssertionError):
        sys.stderr.write("date must be YYYY-MM-DD\n")
        return 2

    files = {}
    for n in SCRIPTS:
        files[n] = read(os.path.join(REPO, "node", n))
    for n in GUIDES:
        files[n] = read(os.path.join(REPO, "docs", "non-systemd", n))
    for n, data in files.items():
        if b"\r" in data:
            sys.stderr.write("%s has CR line endings; refusing\n" % n)
            return 1
    sums = "".join(
        "%s  %s\n" % (hashlib.sha256(files[n]).hexdigest(), n) for n in SCRIPTS
    ).encode()
    files["SHA256SUMS"] = sums

    zname = "%s-%s.zip" % (FOLDER, date)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for n in sorted(files):
            zi = zipfile.ZipInfo("%s/%s" % (FOLDER, n), (y, m, d, 12, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if n in SCRIPTS else 0o644
            zi.external_attr = (0o100000 | mode) << 16
            zi.create_system = 3
            z.writestr(zi, files[n])
    zdata = buf.getvalue()
    zsum = hashlib.sha256(zdata).hexdigest()

    os.makedirs(out, exist_ok=True)
    outputs = [
        (zname, zdata),
        ("SHA256SUMS", sums),
        (zname + ".sha256", ("%s  %s\n" % (zsum, zname)).encode()),
    ]
    for n, _ in outputs:
        if os.path.exists(os.path.join(out, n)):
            sys.stderr.write("%s already exists in %s; not overwriting\n" % (n, out))
            return 1
    for n, data in outputs:
        with open(os.path.join(out, n), "xb") as f:
            f.write(data)
    print("%s  %s" % (zsum, zname))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
