#!/usr/bin/env bash
# Builds RR Pocket: Flutter's debug engine (JIT, hot reload) in an APK that is
# not debuggable, as Play requires. Flutter's Gradle plugin ties the engine to
# the debuggable flag, so this builds debug and turns the flag off after.
#
# Usage: tool/build_apk.sh [arm64|x64]        (default arm64)
# Signs with the debug keystore unless RR_KEYSTORE, RR_KEYSTORE_PASS and
# RR_KEY_ALIAS are set. Writes build/rr_pocket-<abi>.apk.
set -euo pipefail

abi="${1:-arm64}"
case "$abi" in
  arm64 | x64) ;;
  *) echo "usage: $0 [arm64|x64]" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
tools="$sdk/build-tools/$(ls "$sdk/build-tools" | sort -V | tail -1)"
if [[ -z "${JAVA_HOME:-}" && -d "$HOME/.local/share/jdk" ]]; then
  JAVA_HOME="$(ls -d "$HOME"/.local/share/jdk/* | head -1)"
fi
export ANDROID_HOME="$sdk" JAVA_HOME PATH="${JAVA_HOME:+$JAVA_HOME/bin:}$PATH"

versions="$(flutter --version --machine)"
flutter_version="$(python3 -I -c 'import json, sys; print(json.load(sys.stdin)["frameworkVersion"])' <<<"$versions")"
engine_revision="$(python3 -I -c 'import json, sys; print(json.load(sys.stdin)["engineRevision"])' <<<"$versions")"
export RR_FLUTTER_VERSION="$flutter_version" RR_ENGINE_REVISION="$engine_revision"

cd "$root/app"
flutter pub get >/dev/null
python3 -I "$root/tool/write_plugin_list.py" "$root/app"
flutter build apk --debug --target-platform "android-$abi" \
  --dart-define="RR_FLUTTER_VERSION=$flutter_version"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp build/app/outputs/apk/debug/app-debug.apk "$work/app.apk"
(cd "$work" && unzip -q app.apk AndroidManifest.xml)
python3 -I "$root/tool/undebug_manifest.py" "$work/AndroidManifest.xml"
(cd "$work" && zip -q app.apk AndroidManifest.xml && zip -q -d app.apk 'META-INF/*')
"$tools/zipalign" -f -p 4 "$work/app.apk" "$work/aligned.apk"

out="$root/build/rr_pocket-$abi.apk"
mkdir -p "$root/build"
"$tools/apksigner" sign \
  --ks "${RR_KEYSTORE:-$HOME/.android/debug.keystore}" \
  --ks-pass "pass:${RR_KEYSTORE_PASS:-android}" \
  ${RR_KEY_ALIAS:+--ks-key-alias "$RR_KEY_ALIAS"} \
  --out "$out" "$work/aligned.apk"
echo "Built $out (Flutter $flutter_version, not debuggable)"
