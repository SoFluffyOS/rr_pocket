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
  └ DDS, hot reload, devfs
      ─▶ 127.0.0.1 tunnel (pocket run) ──▶ VM relay :8101 (Kotlin) ─▶ 127.0.0.1
  └ q: SIGTERM, POST /stop ─────────────▶   recreates the activity
```

Everything between the computer and the phone is TLS, pinned to the
phone's own certificate (Security, below).

- **Launching is a hot restart.** A fresh engine launch on Android reads
  assets only from inside the APK, but the engine's `_flutter.runInView`,
  the call behind hot restart, takes a kernel and an assets folder from the
  filesystem. RR Pocket calls it on its own VM service with a plain HTTP
  GET (the VM service answers JSON-RPC as `GET /<auth>/<method>?<params>`),
  from Kotlin, which outlives the Dart side it replaces. 196 ms.
- **The engine's snapshots stay on the phone.** The bundle carries
  `isolate_snapshot_data` and `vm_snapshot_data` for the engine it was built
  for; `runInView` uses the running engine's, so `install` skips them.
- **The VM service listens on 127.0.0.1 only.** A byte-for-byte relay on
  :8101 makes it reachable inside TLS; HTTP, WebSockets and DDS all go
  through. Flutter and DDS expect a plain VM service, so `pocket run`
  listens on the computer's 127.0.0.1 and carries each connection to the
  relay inside TLS (`VmTunnel`).
- **A new run or a stop ends every relayed connection.** The VM lives as
  long as RR Pocket's process, across sessions. A computer's DDS that
  outlives its `flutter run` (killed, or the laptop asleep) keeps the VM to
  itself: the next session's DDS can't start, the VM redirects it to the
  dead one, and hot restart fails with "DevFS synchronization failed".
  Checked on a Pixel 7 by killing a session hard: the next one hot
  restarts in 1.4 s.
- **`flutter run` is stock.** `pocket pair` registers a custom device
  whose commands are `pocket ping | install | run | uninstall | screenshot`,
  run by
  Flutter's `dart` as `dart --packages=<config> package:rr_pocket/pocket.dart`
  (0.29 s a call), with the package config of the copy that paired: an
  installed package's stays at the same path across upgrades. Not the
  snapshot pub runs, whose name changes with each Dart version, and not
  `dart pub global run`, which runs the tool in a child process that never
  hears Flutter's SIGTERM, so quitting left the app open. `run` prints "The
  Dart VM service is listening on http://127.0.0.1:<tunnel>/<auth>/", which
  is how the tool finds it, then the app's log lines, which is how the tool
  shows them.
- **Uninstall stops only a running project.** Flutter calls `uninstall`
  before every install; with nothing running, `/stop` leaves RR Pocket's
  own screen alone instead of starting a new engine during the upload.
- **The log stream holds the session.** `pocket run` keeps `/logs` open for
  the whole run, so when it closes from the computer's side the phone stops
  the project, even when the tool was killed before sending `/stop` (Flutter
  on Windows has no SIGTERM to send). A stream whose session a later `/run`
  or `/stop` already ended stops nothing.
- **Screenshots.** `s` in `flutter run` runs `pocket screenshot`, which
  prints `GET /screenshot` as base64, as Flutter's custom devices expect.
  The phone draws the Flutter view's last frame into a bitmap
  (`FlutterRenderer.getBitmap`); platform views, such as a camera preview,
  are not in it. Not yet tried on a phone (2026-10-27).
- **A phone at a new address.** When the phone doesn't answer where it
  paired (connection refused or failed, or another certificate there),
  `ping`, `install`, `run`, `pin`, `doctor` and the Lumide plugin look for
  it by mDNS; a phone that shows the pinned certificate is the same one,
  and the pairing moves to its address. A timeout doesn't start a search:
  that phone is more likely asleep, and Flutter pings on every poll.
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

- **TLS, pinned.** RR Pocket makes a P-256 key and a self-signed
  certificate once (`TlsIdentity`, kept with the app's data like the code)
  and serves :8100 and :8101 only over TLS. The computer pins the
  certificate's SHA-256 when it pairs (`device.json`, `fingerprint`) and
  trusts nothing else: no certificate authorities, no other certificate.
  So nobody on the Wi-Fi can read the code, the project or the VM
  service's address, change the project on the way, or pass for the phone.
  How the computer learns the fingerprint safely is in
  [pairing.md](pairing.md).
- **The code.** 8 characters from a 32-letter alphabet (40 bits) guard every
  request, compared in constant time. Ten wrong codes from one sender (an
  IPv4 address, or an IPv6 /64) lock that sender out for five minutes;
  other senders, the paired computer among them, keep working. Made once
  and kept until the app's data is cleared.
- **The VM service's own auth code** in its URL guards the relay. The
  computer learns it only from `/run`, which needs the pairing code.
- **Connections.** Each port holds at most 32 connections, 16 per sender;
  the control server ends one that sends nothing for 30 s, the relay one
  that doesn't finish its handshake in 10 s. A failure ends only its own
  connection.
- **On the computer**, `device.json` is readable by its owner only (0600).

Checked on a Pixel 7, 2026-10-25: plain HTTP to either port gets an empty
reply; a computer pinned to another certificate refuses the phone before
sending the code; a full `flutter run -d pocket` of the probe through the
tunnel started in 11.3 s, hot reload 0.43 s, hot restart 2.49 s.

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
  log: `/logs` runs `logcat -v tag --pid=<own pid> flutter:V *:E` and
  streams it, `print` lines bare and errors under other tags with their tag
  (`E/CameraX: ...`), so a plugin's native failures show in `flutter run`.
- **Cleartext.** Android blocks plain HTTP, even to 127.0.0.1, unless the
  app allows it; RR Pocket does (`usesCleartextTraffic`): projects call
  their dev servers over HTTP, and RR Pocket calls its own VM service on
  127.0.0.1 and posts a QR pairing to the computer that way. Its own
  servers don't speak it.
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
