#!/usr/bin/env bash
# Builds RR Pocket's Android App Bundle for Google Play: Flutter's debug
# engine, not debuggable. An AAB's manifest is protobuf, so the flag goes
# protobuf -> binary (aapt2 convert), flipped by undebug_manifest.py, then
# back to protobuf, and the bundle is signed again.
#
# Usage: tool/build_aab.sh [--build-name 1.0.0] [--build-number 7]
# Signs with the debug keystore unless RR_KEYSTORE, RR_KEYSTORE_PASS and
# RR_KEY_ALIAS (and RR_KEY_PASS, if it differs) are set.
# Writes build/rr_pocket.aab.
set -euo pipefail

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
flutter build appbundle --debug "$@" \
  --dart-define="RR_FLUTTER_VERSION=$flutter_version"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp build/app/outputs/bundle/debug/app-debug.aab "$work/app.aab"
cd "$work"

# The manifest and the resources it points at, as a protobuf "APK".
unzip -q app.aab 'base/manifest/*' 'base/resources.pb' 'base/res/*' -d base
mkdir proto
cp base/base/manifest/AndroidManifest.xml base/base/resources.pb proto/
cp -r base/base/res proto/
(cd proto && zip -q -r ../proto.apk .)
"$tools/aapt2" convert --output-format binary -o binary.apk proto.apk
unzip -q binary.apk AndroidManifest.xml -d flipped
python3 -I "$root/tool/undebug_manifest.py" flipped/AndroidManifest.xml
(cd flipped && zip -q ../binary.apk AndroidManifest.xml)
"$tools/aapt2" convert --output-format proto -o flipped.apk binary.apk
manifest="$("$tools/aapt2" dump xmltree --file AndroidManifest.xml flipped.apk)"
grep -q 'debuggable(0x0101000f)=false' <<<"$manifest" ||
  { echo "the flipped manifest is still debuggable" >&2; exit 1; }

mkdir -p replace/base/manifest
unzip -q -p flipped.apk AndroidManifest.xml >replace/base/manifest/AndroidManifest.xml
(cd replace && zip -q ../app.aab base/manifest/AndroidManifest.xml)
zip -q -d app.aab 'META-INF/*' || true

out="$root/build/rr_pocket.aab"
mkdir -p "$root/build"
jarsigner -keystore "${RR_KEYSTORE:-$HOME/.android/debug.keystore}" \
  -storepass "${RR_KEYSTORE_PASS:-android}" \
  ${RR_KEY_PASS:+-keypass "$RR_KEY_PASS"} \
  -signedjar "$out" app.aab "${RR_KEY_ALIAS:-androiddebugkey}" >/dev/null
echo "Built $out (Flutter $flutter_version, not debuggable)"
