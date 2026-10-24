#!/usr/bin/env bash
# Every check that needs no phone: analysis, the app's Flutter tests, the
# desktop package's tests (pocket command, Lumide plugin), the Kotlin tests
# (pairing code, control server). Exits non-zero on any failure,
# read from the results, not from a pipeline's exit code.
#
# Usage: tool/check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
if [[ -z "${JAVA_HOME:-}" && -d "$HOME/.local/share/jdk" ]]; then
  JAVA_HOME="$(ls -d "$HOME"/.local/share/jdk/* | head -1)"
  export JAVA_HOME
fi

cd "$root/app"
flutter analyze
flutter test --reporter expanded
(cd "$root/desktop" && dart pub get >/dev/null && dart analyze && dart test)
(cd "$root/probe" && flutter analyze)

rm -rf build/app/test-results/testDebugUnitTest
(cd android && ./gradlew -q :app:testDebugUnitTest) || true
python3 -I - build/app/test-results/testDebugUnitTest <<'PY'
import glob, re, sys
total = failed = 0
for path in glob.glob(f"{sys.argv[1]}/*.xml"):
    m = re.search(r'tests="(\d+)" skipped="\d+" failures="(\d+)" errors="(\d+)"', open(path).read())
    total += int(m.group(1))
    failed += int(m.group(2)) + int(m.group(3))
print(f"Kotlin tests: {total} run, {failed} failed")
sys.exit(1 if failed or not total else 0)
PY
echo "All checks passed."
