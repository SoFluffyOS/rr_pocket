## Unreleased

### 🚀 New Features

- Screenshots: `s` in `flutter run -d pocket` saves what the phone shows.
  Needs the RR Pocket release after 1.0.0; run `pocket pair` again so
  Flutter learns the new command (Lumide does it by itself).
- A phone the Wi-Fi gave a new address is found again on the network, by
  the certificate pinned when pairing: no new pairing needed.

### 🐛 Fixes

- `pocket doctor` notices a `pocket` device whose Dart or package config is
  gone (a removed Flutter SDK), so Flutter stopped listing it.
- A phone that doesn't answer in time: the message says to unlock it and
  open RR Pocket.

## 1.0.0

### 🚀 New Features

- The `pocket` command: `pocket pair` and `pocket pin`, and the `pocket`
  device behind `flutter run -d pocket`.
- Lumide plugin: pair with the phone, match plugin versions, and the paired
  phone in the status bar.
- TLS to the phone, pinned to its certificate when pairing; the pairing
  file is readable by its owner only. A pairing made before this has no
  certificate to pin: run `pocket pair` again.
