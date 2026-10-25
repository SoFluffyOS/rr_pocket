## 1.0.0

### 🚀 New Features

- The `pocket` command: `pocket pair` and `pocket pin`, and the `pocket`
  device behind `flutter run -d pocket`.
- Lumide plugin: pair with the phone, match plugin versions, and the paired
  phone in the status bar.
- TLS to the phone, pinned to its certificate when pairing; the pairing
  file is readable by its owner only. A pairing made before this has no
  certificate to pin: run `pocket pair` again.
