# RR Pocket

Run your Flutter app on your Android phone with just the Flutter SDK. No
Android SDK, no Gradle build. Like Expo Go, for Flutter.

RR Pocket is an Android app with a Flutter debug engine and a set of
plugins built in. The Flutter tool compiles your project and sends it over;
the app restarts into it. Hot reload works as usual.

Private for now. Design and decisions: note 025 in `project_raccoon`.

## Status

Spike passed on the Android emulator (Flutter 3.47.7, 2026-10-24):

- A project with no `android/` folder runs in the prebuilt app.
  Launch 579-636 ms, hot reload 173-211 ms.
- Plugins the app carries (`shared_preferences`, `path_provider`) answer,
  once the plugin registrant runs after the restart.
- **The app ships non-debuggable, as Play requires, and the debug engine
  still runs.** Flutter's Gradle plugin can't build that, so
  `tool/undebug_manifest.py` flips the flag in the built APK, then it is
  re-signed.

Next: reach the phone over Wi-Fi with no adb, as a custom device
(`flutter run -d pocket`).

## Layout

- `app/`: the Android app.
- `tool/undebug_manifest.py`: sets `android:debuggable` to false in an
  APK's binary manifest.
- `tool/drive_attach.py`: the spike's driver. Attaches from a project,
  restarts into it, edits, hot reloads.

## Try the spike

```sh
cd app && flutter build apk --debug --target-platform android-x64
cd build/app/outputs/apk/debug && unzip -o app-debug.apk AndroidManifest.xml
python3 ../../../../../../tool/undebug_manifest.py AndroidManifest.xml
zip app-debug.apk AndroidManifest.xml && zip -d app-debug.apk 'META-INF/*'
zipalign -f -p 4 app-debug.apk aligned.apk
apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android --out rr_pocket.apk aligned.apk
adb install rr_pocket.apk && adb shell am start -n io.sofluffy.raccoon.runtime.pocket/.MainActivity
```

Then, from any Flutter project whose `main` calls
`DartPluginRegistrant.ensureInitialized()` first:

```sh
python3 tool/drive_attach.py <project> <VM service URL from logcat>
```
