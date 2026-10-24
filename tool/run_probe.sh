#!/usr/bin/env bash
# Starts RR Pocket fresh on a device, restarts it into probe/ and prints the
# probe's results. The APK must already be installed (tool/build_apk.sh).
#
# Usage: tool/run_probe.sh [device id]      (default emulator-5554)
set -euo pipefail

device="${1:-emulator-5554}"
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tool/env.sh"
adb=("$ANDROID_HOME/platform-tools/adb" -s "$device")
app=io.sofluffy.raccoon.runtime.pocket

"${adb[@]}" shell input keyevent KEYCODE_HOME
"${adb[@]}" shell am force-stop "$app"
"${adb[@]}" logcat -c
"${adb[@]}" shell am start -W -n "$app/.MainActivity" >/dev/null
url=""
for _ in $(seq 1 20); do
  url="$("${adb[@]}" logcat -d | grep -o 'http://127.0.0.1:[0-9]*/[^ ]*/' | tail -1 || true)"
  [[ -n "$url" ]] && break
  sleep 0.5
done
[[ -n "$url" ]] || { echo "no VM service URL from $app" >&2; exit 1; }

mkdir -p "$root/probe/build"
python3 -I "$root/tool/drive_attach.py" "$root/probe" "$url" "$device" >"$root/probe/build/attach.log" 2>&1 &
driver=$!
for _ in $(seq 1 120); do
  "${adb[@]}" logcat -d | grep -q 'PROBE done' && break
  sleep 1
done
"${adb[@]}" logcat -d | grep -o 'PROBE .*' | cut -c1-120
wait "$driver" || true
"${adb[@]}" shell input keyevent KEYCODE_BACK
grep -E '^(restart|reload)' "$root/probe/build/attach.log" || true
"${adb[@]}" logcat -d | grep -o 'PROBE .*' | grep -qE 'MISSING|answered with' && exit 1
exit 0
