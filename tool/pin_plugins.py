"""Pins a project's Android plugins to the versions RR Pocket carries.

A plugin's Dart side and its Kotlin side in RR Pocket must be the same
version (Pigeon's messages are positional). This writes the project's
pubspec_overrides.yaml with those versions; run `flutter pub get` after.

Usage: pin_plugins.py <project dir>   (RR Pocket's app/ must have had pub get)
"""
import json
import re
import sys
from pathlib import Path

HEADER = "# Written by RR Pocket's tool/pin_plugins.py"
app = Path(__file__).resolve().parent.parent / "app"
project = Path(sys.argv[1])


def locked_versions(lockfile):
    text = lockfile.read_text()
    return dict(re.findall(r'\n  (\w+):\n(?:    .*\n)*?    version: "([^"]+)"', text))


carried = locked_versions(app / "pubspec.lock")
android = json.loads((app / ".flutter-plugins-dependencies").read_text())["plugins"]["android"]
pins = {p["name"]: carried[p["name"]] for p in android}

project_lock = project / "pubspec.lock"
if project_lock.exists():
    used = locked_versions(project_lock)
    pins = {name: version for name, version in pins.items() if name in used}

overrides = project / "pubspec_overrides.yaml"
if overrides.exists() and not overrides.read_text().startswith(HEADER):
    sys.exit(f"{overrides} exists and is not ours; merge these by hand:\n"
             + "\n".join(f"  {n}: {v}" for n, v in sorted(pins.items())))

overrides.write_text(
    f"{HEADER}: the Android plugin versions it carries.\n"
    "dependency_overrides:\n"
    + "".join(f"  {name}: {version}\n" for name, version in sorted(pins.items())))
print(f"pinned {len(pins)} plugins in {overrides}")
