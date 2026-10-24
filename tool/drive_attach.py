"""Attach to RR Pocket on the emulator from a user app, full restart into it, edit, hot reload.

Usage: drive_attach.py <user_app dir> <vm service url>
"""
import json
import re
import subprocess
import sys
import time

app_dir, url = sys.argv[1], sys.argv[2]
adb = "/home/simon/Android/Sdk/platform-tools/adb"
main = f"{app_dir}/lib/main.dart"


def logcat(pattern):
    out = subprocess.run([adb, "logcat", "-d"], capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if pattern in l]


p = subprocess.Popen(
    ["flutter", "attach", "-d", "emulator-5554", "--app-id", "io.sofluffy.raccoon.runtime.pocket",
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

subprocess.run([adb, "exec-out", "screencap", "-p"],
               stdout=open(f"{app_dir}/../after_reload.png", "wb"))
p.stdin.write(json.dumps([{"id": 99, "method": "app.detach", "params": {"appId": app_id}}]) + "\n")
p.stdin.flush()
time.sleep(2)
p.kill()
