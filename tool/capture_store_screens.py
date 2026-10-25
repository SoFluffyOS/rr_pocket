"""Captures the raw screens for the Play listing and the README picture into
store/captures/.

Needs a device or emulator with RR Pocket installed and paired
(pocket pair ...), and Pillow. Sets the display to a 1080x2400 phone and
a clean status bar while it works, and puts both back after. Saves the
address and code the phone shows in pairing.json, for the terminal drawn
next to it.

Usage: python3 tool/capture_store_screens.py [device id]   (default emulator-5554)
"""
import io
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "store/captures"
DEMO = ROOT / "store/demo"
APP = "io.sofluffy.raccoon.runtime.pocket"
device = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
SDKS = [os.environ.get("ANDROID_HOME", ""), "~/Android/Sdk", "~/Library/Android/sdk"]
adb_path = next(path for path in (os.path.join(os.path.expanduser(sdk), "platform-tools/adb") for sdk in SDKS if sdk)
                if os.path.exists(path))


def adb(*args, **kw):
    return subprocess.run([adb_path, "-s", device, *args], check=True, capture_output=True, **kw)


def shell(command):
    adb("shell", command)


def screen():
    return Image.open(io.BytesIO(adb("exec-out", "screencap", "-p").stdout)).convert("RGB")


def capture(name):
    time.sleep(1.5)
    screen().save(OUT / f"{name}.png")
    print("captured", name)


def save_pairing():
    """The address and code RR Pocket shows, from its log line."""
    log = adb("logcat", "-d", "-s", "RRPocket", text=True).stdout
    found = re.findall(r"pair with: (\S+) (\S+)", log)
    if not found:
        sys.exit("RR Pocket logged no pairing line")
    address, code = found[-1]
    (OUT / "pairing.json").write_text(json.dumps({"address": address, "code": code}))


def differs(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) > 18


def scroll_to_build_card():
    """Scrolls the home screen so the card listing the plugins starts just
    below the status bar, not cut off by it. Slow swipes, so nothing flings;
    then checks the card's rounded corner, and scrolls on past a cut card."""
    density = 420 / 160
    image = screen()
    background = image.getpixel((10, image.height // 2))  # the page margin
    left = round(24 * density) + 3  # inside a card's left edge, at its corner
    tops = [y for y in range(1, image.height)
            if differs(image.getpixel((540, y)), background)
            and not differs(image.getpixel((540, y - 1)), background)
            and not differs(image.getpixel((left, y)), background)]
    logo, build = tops[0], tops[-1]  # the logo, the last card on screen
    safe_top = logo - round(48 * density)
    # Flutter's touch slop (18 dp) is lost from a drag.
    distance = build - safe_top - round(16 * density) + round(18 * density)
    shell(f"input swipe 540 1900 540 {1900 - distance} 1500")
    for _ in range(3):
        time.sleep(1)
        image = screen()
        y = next(y for y in range(safe_top, image.height) if differs(image.getpixel((540, y)), background))
        if not differs(image.getpixel((left, y)), background):
            return  # a card's rounded top: nothing cut
        bottom = next(y2 for y2 in range(y, image.height) if not differs(image.getpixel((540, y2)), background))
        shell(f"input swipe 540 1900 540 {1900 - (bottom - safe_top) - round(34 * density)} 1500")


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
    # The status bar redraws a moment later: the first capture missed the
    # Wi-Fi icon without this (emulator, 2026-10-25).
    time.sleep(2)


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
    save_pairing()
    open_pocket(night=True)
    capture("home_dark")
    scroll_to_build_card()
    capture("plugins_dark")
    open_pocket(night=False)
    run_demo()
finally:
    shell("cmd uimode night no")
    demo_status_bar(False)
    shell("wm size reset")
    shell("wm density reset")
