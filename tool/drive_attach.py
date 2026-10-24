"""Attaches to RR Pocket from a project, restarts into it, edits, hot reloads.

Usage: drive_attach.py <project dir> <vm service url> [device id, default emulator-5554]
"""
import json
import os
import re
import subprocess
import sys
import time

app_dir, url = sys.argv[1], sys.argv[2]
device = sys.argv[3] if len(sys.argv) > 3 else "emulator-5554"
SDKS = [os.environ.get("ANDROID_HOME", ""), "~/Android/Sdk", "~/Library/Android/sdk"]
adb = next((path for path in (os.path.join(os.path.expanduser(sdk), "platform-tools/adb") for sdk in SDKS if sdk)
            if os.path.exists(path)), "adb")
main = f"{app_dir}/lib/main.dart"

# attach compiles before it writes the plugin registrant, so a project's first
# run (or its first after a plugin change) would miss plugins; build bundle
# writes the registrant first.
registrant = f"{app_dir}/.dart_tool/flutter_build/dart_plugin_registrant.dart"
if not os.path.exists(registrant) or (
        os.path.getmtime(registrant) < os.path.getmtime(f"{app_dir}/pubspec.lock")):
    subprocess.run(["flutter", "build", "bundle"], cwd=app_dir, check=True)


def logcat(pattern):
    out = subprocess.run([adb, "logcat", "-d"], capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if pattern in l]


p = subprocess.Popen(
    ["flutter", "attach", "-d", device, "--app-id", "io.sofluffy.raccoon.runtime.pocket",
     "--debug-url", url, "--machine"],
    cwd=app_dir, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

app_id, next_id = None, 1


def call(method, **params):
    global next_id
    req = {"id": next_id, "method": method, "params": {"appId": app_id, **params}}
    next_id += 1
    t0 = time.time()
    p.stdin.write(json.dumps([req]) + "\n")
    p.stdin.flush()
    for line in p.stdout:
        if line.startswith("[") and f'"id":{req["id"]}' in line:
            return json.loads(line)[0], time.time() - t0


for line in p.stdout:
    m = re.search(r'"event":"app.started","params":\{"appId":"([^"]+)"', line)
    if m:
        app_id = m.group(1)
        break

subprocess.run([adb, "logcat", "-c"])
res, dt = call("app.restart", fullRestart=True)
print(f"restart {dt*1000:.0f} ms -> {res.get('result') or res.get('error')}")
time.sleep(3)
print("\n".join(logcat("USER_APP")) or "no USER_APP line")

src = open(main).read()
open(main, "w").write(src.replace("USER APP v1", "USER APP v2"))
time.sleep(0.5)
res, dt = call("app.restart", fullRestart=False)
print(f"reload {dt*1000:.0f} ms -> {res.get('result') or res.get('error')}")
open(main, "w").write(src)

os.makedirs(f"{app_dir}/build", exist_ok=True)
subprocess.run([adb, "exec-out", "screencap", "-p"],
               stdout=open(f"{app_dir}/build/after_reload.png", "wb"))
# Stop, not detach: a detached app keeps its DDS, which holds the phone's VM
# through this adb forward, and the next session is redirected to it.
p.stdin.write(json.dumps([{"id": 99, "method": "app.stop", "params": {"appId": app_id}}]) + "\n")
p.stdin.flush()
# Let flutter attach end by itself: killed, it leaves its DDS running.
try:
    p.wait(timeout=20)
except subprocess.TimeoutExpired:
    p.terminate()
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        p.kill()
