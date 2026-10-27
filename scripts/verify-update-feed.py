#!/usr/bin/env python3
"""Check architecture isolation, metadata, archive signature, and tamper rejection."""
import pathlib
import plistlib
import tempfile
import subprocess
import sys
import xml.etree.ElementTree as ET

feed, archive, arch, version, signer, account = sys.argv[1:]
path = pathlib.Path(archive)
# Inspect the actual disk image payload rather than trusting its filename.
with tempfile.TemporaryDirectory(prefix="feathersweep-inspect-") as mount:
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, archive], check=True)
    try:
        apps = list(pathlib.Path(mount).glob("*.app"))
        assert len(apps) == 1, "expected one app payload"
        app = apps[0]
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == "io.github.zimuoo.FeatherSweep"
        assert info["CFBundleShortVersionString"] == version
        assert info["CFBundleVersion"] == "3"
        assert info["SUFeedURL"] == f"https://github.com/zimuoo/FeatherSweep/releases/latest/download/appcast-{arch}.xml"
        assert info["SURequireSignedFeed"] is True
        actual = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/FeatherSweep")], text=True).strip()
        assert actual == arch, f"wrong payload architecture: {actual}"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    finally:
        subprocess.run(["hdiutil", "detach", mount], check=True)
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items = ET.parse(feed).findall("./channel/item")
assert len(items) == 1, "feed must contain exactly this release"
item = items[0]
enclosure = item.find("enclosure")
assert enclosure is not None
assert enclosure.attrib["url"] == f"https://github.com/zimuoo/FeatherSweep/releases/download/v{version}/{path.name}"
assert int(enclosure.attrib["length"]) == path.stat().st_size
assert item.findtext(ns + "version") == "3"
assert item.findtext(ns + "shortVersionString") == version
assert item.findtext(ns + "minimumSystemVersion") == "14.0"
assert item.find(ns + "releaseNotesLink") is None
signature = enclosure.attrib[ns + "edSignature"]
subprocess.run([signer, "--account", account, "--verify", archive, signature], check=True)
# Verify the actual signed archive bytes are protected, without copying a large DMG.
with tempfile.TemporaryDirectory(prefix="feathersweep-tamper-") as scratch:
    tampered = pathlib.Path(scratch) / "modified.dmg"
    tampered.write_bytes(path.read_bytes() + b"tamper")
    result = subprocess.run([signer, "--account", account, "--verify", str(tampered), signature])
    assert result.returncode != 0, "modified archive must fail signature verification"
print(f"Verified {arch} release metadata, archive signature, and tamper rejection")
