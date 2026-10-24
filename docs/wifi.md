# `flutter run -d pocket`: no adb, over the network

Built and checked 2026-10-24 on the Android emulator, Flutter 3.47.7.

## How it works

```
computer                                   phone (RR Pocket)
flutter run -d pocket
  └ build bundle (kernel + assets)
  └ pocket install ──────PUT /bundle/*──▶ control server :8100 (Kotlin)
  └ pocket run ──────────POST /run───────▶   runInView(bundle) on its own
                                              VM service, over HTTP
    prints the VM service's address  ◀───── {"vmPath": "/<auth>/"}
    streams GET /logs ◀───────────────────   tails its own log, tag flutter
  └ DDS, hot reload, devfs ─────────────▶ VM relay :8101 (Kotlin) ─▶ 127.0.0.1
  └ q: SIGTERM, POST /stop ─────────────▶   recreates the activity
```

- **Launching is a hot restart.** A fresh engine launch on Android reads
  assets only from inside the APK, but the engine's `_flutter.runInView`,
  the call behind hot restart, takes a kernel and an assets folder from the
  filesystem. RR Pocket calls it on its own VM service with a plain HTTP
  GET (the VM service answers JSON-RPC as `GET /<auth>/<method>?<params>`),
  from Kotlin, which outlives the Dart side it replaces. 196 ms.
- **The engine's snapshots stay on the phone.** The bundle carries
  `isolate_snapshot_data` and `vm_snapshot_data` for the engine it was built
  for; `runInView` uses the running engine's, so `install` skips them.
- **The VM service listens on 127.0.0.1 only.** A byte-for-byte TCP relay
  on :8101 makes it reachable; HTTP, WebSockets and DDS all go through.
- **A new run or a stop ends every relayed connection.** The VM lives as
  long as RR Pocket's process, across sessions. A computer's DDS that
  outlives its `flutter run` (killed, or the laptop asleep) keeps the VM to
  itself: the next session's DDS can't start, the VM redirects it to the
  dead one, and hot restart fails with "DevFS synchronization failed".
  Checked on a Pixel 7 by killing a session hard: the next one hot
  restarts in 1.4 s.
- **`flutter run` is stock.** `pocket pair` registers a custom device
  whose commands are `pocket ping | install | run | uninstall`, run by
  Flutter's `dart` as `dart --packages=<config> package:rr_pocket/pocket.dart`
  (0.29 s a call), with the package config of the copy that paired: an
  installed package's stays at the same path across upgrades. Not the
  snapshot pub runs, whose name changes with each Dart version, and not
  `dart pub global run`, which runs the tool in a child process that never
  hears Flutter's SIGTERM, so quitting left the app open. `run` prints "The
  Dart VM service is listening on http://<phone>:8101/<auth>/", which is how
  the tool finds it, then the app's log lines, which is how the tool shows
  them.
- **Versions.** `/hello` reports the Flutter version and engine revision
  RR Pocket was built with (stamped by `tool/build_apk.sh` through Gradle
  `resValue`s); `install` compares the engine revision with the SDK's in
  `$FLUTTER_ROOT/bin/cache/flutter.version.json` and stops with a message
  when they differ.

## Plugins

`/hello` lists the Android plugin packages and versions the build carries
(`tool/build_apk.sh` writes them into the APK's assets). Before sending a
bundle, `install` compares them with the project's `pubspec.lock`: a version
that differs stops the run with the list and "run `pocket pin`";
a plugin RR Pocket lacks is a warning. `pin` writes the project's
`pubspec_overrides.yaml` from the phone's list and runs `flutter pub get`.

The tool runs the app even when `install` failed (it only logs the
failure), which would restart the previous bundle; so `install` leaves a
marker and `run` refuses with the same message.

## Security

Anyone who can drive the control server can run code in RR Pocket, so:

- An 8-character code from a 32-letter alphabet (40 bits) guards every
  request, compared in constant time; ten wrong codes lock it for five
  minutes. It is made once and kept until the app's data is cleared.
- The relay carries the VM service, whose URL holds its own random auth
  code. The computer learns it only from `/run`, which needs the pairing
  code.
- Plain HTTP on the LAN: the code crosses the network in the clear. Fine
  for a home or office network with a dev tool; TLS with a pinned key from
  the pairing is the next step if it ships wider.

## What it took

- **FlutterJNI reports the wrong VM service once the tool attaches.**
  `FlutterJNI.getVMServiceUri()` changes to the address of the tool's DDS,
  which lives on the computer. The relay read it per connection, so after
  DDS started, every new connection went to a dead port on the phone. The
  tool's devfs uploads go over new connections, so hot reload said "Error
  while starting Kernel isolate task" (no incremental kernel arrived) and
  hot restart "Could not prepare isolate". The Dart VM lives as long as the
  process (one "listening on" per process, across activity recreates), so
  RR Pocket keeps the first address it sees, read before any DDS can exist.
- **Logs.** DDS refuses to start while another client is attached, so the
  helper can't subscribe to the VM service for output. Dart's `print` goes
  to the process's log under the `flutter` tag, and an app may read its own
  log: `/logs` runs `logcat --pid=<own pid> flutter:V *:S` and streams it.
- **Cleartext.** Android blocks plain HTTP, even to 127.0.0.1, unless the
  app allows it; RR Pocket does (`usesCleartextTraffic`), which also lets
  projects call their dev servers over HTTP.
- **A custom device is `linux-x64` or `linux-arm64` to the tool.** The
  bundle it builds is platform-neutral debug kernel, so `linux-arm64` is
  only a label here; the plugin registrant branches at run time and picks
  Android.

## Numbers

Emulator, probe app (26 plugins, 2,380 libraries, 81 MB kernel), warm
build cache; the network is `adb forward` of :8100 and :8101 only.

| | |
|---|---|
| `flutter run -d pocket` to app started | 4.7-6.6 s |
| Hot reload, one edited library | 0.34-0.50 s |
| Hot restart | 1.0-1.1 s |

## Open

- A real phone on real Wi-Fi: upload time for the 81 MB kernel (gzip level
  1 on the way), and whether phones' Wi-Fi isolation blocks :8100.
