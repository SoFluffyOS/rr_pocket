"""Writes the Android plugins and versions RR Pocket carries into the APK's
assets, where /hello reads them; a computer checks a project against them.

Usage: write_plugin_list.py <app dir>   (after flutter pub get)
"""
import json
import re
import sys
from pathlib import Path

app = Path(sys.argv[1])
lock = dict(re.findall(r'\n  (\w+):\n(?:    .*\n)*?    version: "([^"]+)"',
                       (app / "pubspec.lock").read_text()))
android = json.loads((app / ".flutter-plugins-dependencies").read_text())["plugins"]["android"]
out = app / "android/app/src/main/assets/rr_plugins.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({p["name"]: lock[p["name"]] for p in android}, indent=1, sort_keys=True) + "\n")
