"""Captures the raw screens for the Play listing into store/captures/.

Needs a device or emulator with RR Pocket installed and paired
(dart tool/pocket.dart pair ...). Sets the display to a 1080x2400 phone and
a clean status bar while it works, and puts both back after.

Usage: python3 tool/capture_store_screens.py [device id]   (default emulator-5554)
"""
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "store/captures"
DEMO = ROOT / "store/demo"
APP = "io.sofluffy.raccoon.runtime.pocket"
device = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
adb_path = os.path.join(os.environ.get("ANDROID_HOME", os.path.expanduser("~/Android/Sdk")),
                        "platform-tools/adb")


def adb(*args, **kw):
    return subprocess.run([adb_path, "-s", device, *args], check=True, capture_output=True, **kw)


def shell(command):
    adb("shell", command)


def capture(name):
    time.sleep(1.5)
    data = adb("exec-out", "screencap", "-p").stdout
    (OUT / f"{name}.png").write_bytes(data)
    print("captured", name)


def demo_status_bar(on):
    if not on:
        shell("am broadcast -a com.android.systemui.demo -e command exit")
        return
    shell("settings put global sysui_demo_allowed 1")
    for command in [
        "-e command enter",
        "-e command clock -e hhmm 0941",
        "-e command battery -e level 100 -e plugged false",
        "-e command network -e wifi show -e level 4 -e fully true",
        "-e command network -e mobile hide",
        "-e command notifications -e visible false",
    ]:
        shell(f"am broadcast -a com.android.systemui.demo {command}")


def open_pocket(night):
    shell(f"cmd uimode night {'yes' if night else 'no'}")
    shell("input keyevent KEYCODE_HOME")
    shell(f"am force-stop {APP}")
    shell(f"am start -W -n {APP}/.MainActivity")
    time.sleep(3)


def run_demo():
    """flutter run -d pocket on the demo, a hot reload in the middle."""
    main = DEMO / "lib/main.dart"
    source = main.read_text()
    tool = subprocess.Popen(["flutter", "run", "-d", "pocket", "--machine"], cwd=DEMO,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    started, replies, app = threading.Event(), {}, {}

    def read():
        for line in tool.stdout:
            if not line.startswith("["):
                continue
            for message in json.loads(line):
                if message.get("event") == "app.start":
                    app["id"] = message["params"]["appId"]
                if message.get("event") == "app.started":
                    started.set()
                if "id" in message and "event" not in message:
                    replies[message["id"]] = message

    def call(number, method, **params):
        request = {"id": number, "method": method, "params": {"appId": app["id"], **params}}
        tool.stdin.write(json.dumps([request]) + "\n")
        tool.stdin.flush()
        while number not in replies:
            time.sleep(0.05)
        return replies[number]

    threading.Thread(target=read, daemon=True).start()
    try:
        if not started.wait(600):
            sys.exit("the demo never started")
        capture("demo")
        main.write_text(source.replace("Color(0xFF2E7D6B)", "Color(0xFFE8622C)"))
        print("hot reload:", call(1, "app.restart", fullRestart=False).get("result"))
        capture("demo_reloaded")
        call(2, "app.stop")
    finally:
        main.write_text(source)
        tool.kill()


OUT.mkdir(parents=True, exist_ok=True)
shell("wm size 1080x2400")
shell("wm density 420")
demo_status_bar(True)
try:
    open_pocket(night=False)
    capture("home_light")
    open_pocket(night=True)
    shell("input swipe 540 1900 540 500 400")
    capture("plugins_dark")
    open_pocket(night=False)
    run_demo()
finally:
    shell("cmd uimode night no")
    demo_status_bar(False)
    shell("wm size reset")
    shell("wm density reset")
