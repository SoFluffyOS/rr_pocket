# rr_pocket

[![pub package](https://img.shields.io/pub/v/rr_pocket.svg)](https://pub.dev/packages/rr_pocket) [![Powered by SoFluffy](https://img.shields.io/badge/Powered%20by-SoFluffy-orange)](https://sofluffy.io)

Run your Flutter project on your Android phone with just the Flutter SDK. No
Android SDK, no adb, no Gradle build. This package is the computer's side of
[RR Pocket](https://play.google.com/store/apps/details?id=io.sofluffy.raccoon.runtime.pocket):
the `pocket` command, and a plugin for [Lumide IDE](https://lumide.dev).

## Highlights

- `flutter run -d pocket` builds your project and sends it to the phone over
  Wi-Fi. Hot reload, hot restart, DevTools and breakpoints work as usual.
- Pair once with the address and code RR Pocket shows.
- `pocket pin` matches your project's plugin versions to the ones RR Pocket
  carries.
- In Lumide: pair and match plugin versions from the Command Palette, pick
  RR Pocket in the device list, and see the phone in the status bar.

## Requirements

- Flutter, the version RR Pocket was built with (its home screen says which).
- The RR Pocket app on an Android phone on the same network as the computer.
- For the plugin: Lumide 0.24.0 or later.

## Install

```sh
dart pub global activate rr_pocket
```

Lumide loads the plugin at its next start. You can also install it from
Lumide's Plugins pane.

## The pocket command

| Command | Purpose |
| --- | --- |
| `pocket pair <address> <code>` | Pair with the phone and add the `pocket` device to Flutter. Once. |
| `pocket pin` | In a project: pin its Android plugins to RR Pocket's versions, in `pubspec_overrides.yaml`, then `flutter pub get`. |

Then run the project:

```sh
flutter run -d pocket
```

Flutter calls `pocket ping`, `install`, `run` and `uninstall` itself. A
project whose Flutter version or plugin versions differ from RR Pocket's
stops before it is sent, with a message saying which. A plugin RR Pocket
lacks gets a warning: calls to it throw `MissingPluginException`.

## Lumide

| Command | Purpose |
| --- | --- |
| `rr_pocket.pair` | **RR Pocket: Pair with Phone**: asks for the address and the code |
| `rr_pocket.pin` | **RR Pocket: Match Plugin Versions**: for the open project, or the one you pick |
| `rr_pocket.showPhone` | **RR Pocket: Show Phone**: the phone, its Flutter version and plugins |

After pairing, RR Pocket is a device like any other: pick it in Lumide's
device list and press Run. The status bar shows the paired phone; click it
to check the phone again.

The pairing is shared with the `pocket` command, in `~/.config/rr_pocket`
(`%APPDATA%\rr_pocket` on Windows).

## Security

RR Pocket runs the code a paired computer sends it. Pair only phones and
computers you trust, on networks you trust.
