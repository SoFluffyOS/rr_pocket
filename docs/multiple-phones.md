# Several phones at once

One `flutter run` on many phones, each reload landing on all of them: a
speaker changes code and the room's phones change with it. Researched
2026-10-26 on macOS, Flutter 3.47.8; nothing here is built.

## What Flutter gives

`flutter run -d all` runs on every device Flutter sees and sends each `r`
and `R` to all of them. `-d` takes one value, and a prefix that matches
several devices makes Flutter ask which one, not run on all
(`flutter_tools/lib/src/runner/target_devices.dart`). So `-d all` is the
only stock way, and it also picks up macOS, Chrome, simulators and adb
devices.

## What stops it in `desktop/`

- One pairing: everything reads `~/.config/rr_pocket/device.json`.
- One custom device, id `pocket` (`constants.dart`, `deviceConfig`).
- One "install failed" marker for all runs (`installFailedFile`), so one
  phone's failure would stop the others' run.

The VM tunnel binds a free port each run (`vm_tunnel.dart`), so runs side
by side don't clash.

## The plan

- A pairing file per phone, each 0600; one custom device per phone
  (`pocket-pixel-7`) whose helper command names the phone; a marker per
  phone. `flutter run -d pocket-pixel-7` still runs one.
- `pocket run`: runs `flutter run -d all` with a temporary Flutter settings
  folder whose only devices are the paired phones. Flutter builds once; the
  keys go straight to Flutter; the user's own settings stay untouched.
- For a workshop, `pocket pair --qr --many`: one QR code on the projector
  that keeps taking phones. The QR route checks each phone's certificate,
  which matters on a shared Wi-Fi. `pocket forget --all` afterwards.

## The temporary settings folder

Flutter reads its settings and `custom_devices.json` from
`$XDG_CONFIG_HOME/` directly, with no `flutter/` folder, on macOS and Linux,
unless `~/.flutter_settings` exists (`flutter_tools/lib/src/base/config.dart`,
`_configPath`). On Windows it reads `%APPDATA%\.flutter_settings`, so
`APPDATA` would be the variable there, and the helper would need the
pairing folder passed in, since `pocket` also keeps it under `APPDATA`.

Tried 2026-10-26, a copy of the settings with every platform flag off and
`enable-custom-devices` on:

- `flutter config --list` showed the flags off.
- Chrome and macOS left `flutter devices`.
- iOS simulators and a wireless iPhone stayed, with `enable-ios: false`.
  Not understood yet. `flutter run` targets them only when the project has
  `ios/`, which most do. If they can't be hidden, the fallback is to read
  `flutter devices --machine` and pass the phones some other way.
- Not tried: a real `flutter run` this way, Windows, Linux.

## The other way: one device for many phones

A single `pocket` device whose helper fans out: install to every phone, and
a VM service proxy that copies writes (devfs, `reloadSources`, reassemble,
restart) to each phone, mapping isolate IDs. It would work from IDE run
buttons too, but it imitates Flutter's private debug protocol: several
hundred lines that a Flutter update could break. Not chosen.

## Risks at a talk

- Venue Wi-Fi often keeps devices from reaching each other: bring a router.
  A phone hotspot takes about 10 devices.
- The first launch sends the whole bundle to every phone; start before the
  talk. Reloads are small.
- One `pocket` process and one DDS per phone on the laptop: 10 should be
  fine, 30 is untried.
- Every phone needs the Play version's Flutter, and so does the laptop.
- A paired laptop can run code on the phone until the pairing goes; tell the
  audience to unpair.

Worth it for two phones (phone and tablet) on its own; the workshop parts
when a talk is booked.
