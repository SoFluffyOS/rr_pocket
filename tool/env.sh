# Sourced by the scripts in tool/: finds the Android SDK and a JDK where
# Linux and macOS usually keep them, unless ANDROID_HOME and JAVA_HOME say.
if [[ -z "${ANDROID_HOME:-}" ]]; then
  for candidate in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [[ -d "$candidate" ]]; then ANDROID_HOME="$candidate"; break; fi
  done
fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in "$HOME"/.local/share/jdk/* /opt/homebrew/opt/openjdk@17 \
      "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [[ -x "$candidate/bin/java" ]]; then JAVA_HOME="$candidate"; break; fi
  done
fi
if [[ -n "${JAVA_HOME:-}" ]]; then export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"; fi
