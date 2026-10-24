# RR Pocket

Run your Flutter app on your Android phone with just the Flutter SDK. No
Android SDK, no Gradle build. Like Expo Go, for Flutter.

![RR Pocket, light and dark](branding/screenshot.png)

RR Pocket is an Android app with Flutter's debug engine and a set of plugins
built in. The Flutter tool compiles your project and sends it over; the app
restarts into it. Hot reload works as usual.

Private for now. Design and decisions: note 025 in `project_raccoon`.

## Status

The spike passed on the Android emulator (Flutter 3.47.7, 2026-10-24):

- A project with no `android/` folder runs in the prebuilt app. Launch
  579-821 ms, hot reload 173-211 ms.
- The plugins the app carries answer, once the plugin registrant runs after
  the restart.
- **The app ships non-debuggable, as Play requires, and the debug engine
  still runs.**

Next: reach the phone over Wi-Fi with no adb, as a custom device
(`flutter run -d pocket`).

## Build

```sh
tool/build_apk.sh          # arm64, for a phone
tool/build_apk.sh x64      # for the emulator
```

That writes `build/rr_pocket-<abi>.apk`, signed with the debug keystore, or
with yours when `RR_KEYSTORE`, `RR_KEYSTORE_PASS` and `RR_KEY_ALIAS` are set.
Flutter's Gradle plugin ties the engine to the debuggable flag, so the script
builds debug, then `tool/undebug_manifest.py` turns the flag off and the APK
is signed again. The home screen shows the Flutter version it stamps in.

## Try it

```sh
adb install build/rr_pocket-x64.apk
adb shell am start -n io.sofluffy.raccoon.runtime.pocket/.MainActivity
adb logcat | grep 'VM service'     # copy the URL
python3 tool/drive_attach.py <project> <URL> [device]
```

The project's `main` must call `DartPluginRegistrant.ensureInitialized()`
first, until the custom device generates that wrapper.

## Layout

- `app/`: the Android app. Its plugins are the ones in `pubspec.yaml`; a test
  keeps the home screen's list in step.
- `app/fonts/`: Nunito, cut to static weights from Google Fonts' variable
  font (SIL Open Font License, `OFL.txt`).
- `branding/`: the Play icon and the screenshot.
- `tool/build_apk.sh`: the build above.
- `tool/make_icons.py`: draws the R² launcher icons from Nunito ExtraBold
  (needs Pillow).
- `tool/drive_attach.py`: attaches from a project, restarts into it, edits,
  hot reloads, and times both.
