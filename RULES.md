# Rules

How we work on RR Pocket. For people and for coding agents alike;
`AGENTS.md` points here. What the project is and how to use it: `README.md`.

## The project in one breath

Two halves that must agree:

- **The phone**: `app/`, a Flutter Android app carrying Flutter's debug
  engine and a fixed set of plugins. Its Kotlin side
  (`app/android/.../pocket/`) is the control server, the pairing code and
  the VM service relay.
- **The computer**: `desktop/`, the `rr_pocket` package. Its `pocket`
  command stands behind the `pocket` custom device, so a stock
  `flutter run -d pocket` works with no adb and no Android SDK. The same
  package is a Lumide plugin (`plugin.yaml`, `bin/main.dart`) for pairing
  and pinning from the IDE.

Everything else checks or ships those two: `probe/` (calls every bundled
plugin), `store/` (Play listing and graphics), `tool/*.sh` and `tool/*.py`
(build, check, capture), `docs/` (decisions and how things work).

## Commands

```sh
tool/check.sh              # every check that needs no phone; run before each commit
tool/build_apk.sh [x64]    # build/rr_pocket-<abi>.apk (arm64 by default)
tool/build_aab.sh          # the Play bundle
tool/run_probe.sh [device] # after changing the plugin set; fails on any MISSING
dart pub global activate --source path desktop   # the pocket command from this checkout
```

## Invariants

Break one of these and a user's project stops running, often silently.

- **Debug engine, not debuggable.** RR Pocket runs a project's kernel, which
  needs the debug engine; Play rejects a debuggable app. Build with
  `tool/build_apk.sh` or `tool/build_aab.sh` (which run
  `tool/undebug_manifest.py`), never `flutter build appbundle --release`.
- **One Flutter version on both sides.** A project's kernel runs only on the
  engine its SDK was built for. `pocket install` checks the engine revision;
  keep that check, and keep its message telling the user which version to use.
- **Plugin versions match exactly.** A plugin's Dart side in the project and
  its Kotlin side in RR Pocket must be the same version (Pigeon messages are
  positional; jnigen calls fail as `NoSuchMethodError`). `pocket pin`, the
  Lumide command and `tool/pin_plugins.py` write the same
  `pubspec_overrides.yaml` header so each can replace the others'; change
  them together.
- **The plugin list lives in `app/pubspec.yaml`.** Adding or removing a
  plugin means: update `BuildInfo` (a test keeps it in step), add a call to
  `probe/`, run `tool/run_probe.sh`, record why and the size cost in
  `docs/plugins.md`.
- **The pairing code gates every request.** Each control-server endpoint
  checks it (`CodeGate`); a new endpoint does too. Never write the code to a
  file or log on the computer beyond `device.json`, which stays 0600.
- **Nothing secret crosses the network in the clear.** The phone's servers
  speak only TLS (`TlsIdentity`), and the computer trusts only the
  certificate it pinned when it paired: never a certificate authority, never
  `badCertificateCallback` returning true without the fingerprint check
  (`pinned_tls.dart`). The one plain post, the phone's answer to a QR code,
  carries no code (docs/pairing.md).
- **The `pocket` command needs only the Dart SDK.** No adb, no Android SDK,
  and it must work on macOS, Linux and Windows (`Platform.pathSeparator`,
  `flutter.bat`). Flutter calls it on every run, so keep its startup light.
- **Flutter runs `pocket` itself, in one process.** The device's commands
  are `dart --packages=<config> package:rr_pocket/pocket.dart`
  (`helperCommand`). Never `dart pub global run`: its child process misses
  Flutter's SIGTERM, so a stopped run stays open on the phone
  (`test/stop_test.dart`). Never a snapshot path: it is named after the Dart
  version and replaced on upgrade.
- **The package is private until the app is live.** Don't `dart pub
  publish` or make the repo public without Simon's go-ahead; a published
  version can't be deleted.

## Phones and emulators

- Never uninstall RR Pocket or clear its data on someone's phone to test:
  that resets the pairing code and unpairs their computer. Use the emulator
  or a build with a different application ID.
- Checks that need a device are not in `tool/check.sh`. When a change needs
  one, say which you ran (emulator or real phone, Flutter version) in the
  commit or the doc. "Not yet tried on a real phone" is a fine thing to write.

## Dart

- **Dart 3.13 features** in `app/` (`desktop/` stays on 3.4, below):
  records, patterns, `switch` expressions, dot shorthands, collection
  `if`/`for`. Use descriptive names in patterns (`final theirs?`, not
  `final t?`).
- **`switch` over `? :`** in widget code, e.g. `switch (theme.isDark)
  { true => ..., false => ... }`.
- **Avoid `!`.** Prefer `if (x case final v?)`, `?? fallback`, or promotion
  with an early return. A regex group known to exist is the one tolerated
  case.
- **Early returns** over `else`. Handle the edge cases first and keep the
  main path flat.
- **`const` constructors** wherever possible.
- **Package imports**, never relative. Outside `lib/src/`, import the
  barrel (`package:rr_pocket/src/src.dart` in `app/`,
  `package:rr_pocket/rr_pocket.dart` in `desktop/`); a new file gets an
  export in its folder's barrel.
- **One widget per file**, small and focused. Split by responsibility before
  a file grows past one screen of logic.
- **`unawaited(...)`** for a Future left running on purpose; dispose every
  controller, listener and subscription.
- **Errors the user sees** say what happened and what to do next
  (`'not paired yet: pocket pair <address> <code>'`). In `desktop/`, throw
  `PocketException`; the CLI prints it, the plugin shows it.

## UI

- Build with `sofluffy_ui` (pinned to the commit Lumide uses) on
  `WidgetsApp` and `flutter/widgets.dart`, not Material widgets.
- Sizes come from `Spacing` (`Spacing.d16`, `Spacing.v8`, `Spacing.r12`),
  never bare numbers. Colours come from `context.fluffyTheme` or `RrColors`
  in `rr_theme.dart`, never inline `Color(...)` in a widget.
- Check light and dark. The README screenshot and the Play graphics show
  both; remake them (`tool/capture_store_screens.py`, then
  `tool/make_store_assets.py`) when the home screen changes visibly.

## The desktop package and Lumide

`desktop/` follows Lumide's plugin workflow
(`../plugin-creation-workflow.md` in the Lumide workspace).

- **SDK `>=3.4.0`** (package:qr's floor), so users on older Flutter can
  install it: no dot shorthands or null-aware elements there
  (`if (x case final v?) v`).
- **Pairing follows `docs/pairing.md`** on both sides: found on the network,
  then a QR code, then typed, each the fallback for the one before. A
  protocol change updates the doc, `desktop/` and `app/` together.
- **`lumide_api` pinned exactly** to the published version Lumide ships
  with; state the Lumide version in `desktop/README.md` when it changes.
- **Stdout belongs to Lumide** in the plugin: it carries JSON-RPC. Log with
  `log()`; never call code that prints to stdout (the CLI's `PocketCli`).
- **Commands** are listed in `plugin.yaml` with the titles in
  `commands.dart`, and run through `_guard` (log plus message, never throw
  to Lumide). `test/commands_manifest_test.dart` checks both lists.
- **Host calls** are awaited, or `unawaited(...)` with their errors caught:
  an uncaught async error ends the plugin.
- **The shell permission** lists every executable the plugin runs.

## Kotlin and scripts

- Kotlin lives in `app/android/.../pocket/` with tests beside it under
  `src/test/`; `tool/check.sh` runs them. New server behaviour gets a test.
- Shell scripts start with a comment saying what they do and a `Usage:`
  line, and use `set -euo pipefail`. Python scripts open with a docstring
  that does the same, and use only the standard library unless it says
  otherwise (Pillow for the icons and graphics).
- Anything generated stays out of git (`.gitignore`): APKs, `build/`,
  `rr_plugins.json`, raw captures, keystores.

## Comments and docs

- Comments say **why**, or what a reader can't see from the code (the tool
  runs the app even when install failed, so install records its outcome).
  Don't narrate what the next line does.
- Write plainly: short sentences, concrete nouns, no buzzwords. Numbers
  carry their conditions and date ("4.7-6.6 s on the emulator, Flutter
  3.47.7, 2026-10-24"). Say what's unverified.
- Update docs when a change is worth explaining, changes how RR Pocket is
  used, or breaks something: `README.md` for use and status, `docs/` for how
  and why, `store/listing.md` and `distribution/whatsnew/` for what users
  see on Play. Not for every small change.

## Git

- **Conventional commits**, lower case, saying the outcome in plain words:
  `feat: home screen shows how to pair`, `fix: Play shows RR Pocket on
  devices without a camera`, `docs: plugin check and pin`. Types we use:
  `feat`, `fix`, `perf`, `test`, `docs`, `chore`, `ci`, `refactor`.
- **One logical change per commit.** Commit when a task is done; leave
  unrelated working-tree edits out.
- `tool/check.sh` passes before you commit.

## Before you commit

- [ ] `tool/check.sh` passes (analysis, Flutter tests, Kotlin tests)
- [ ] Changed the plugin set? `BuildInfo`, `probe/`, `tool/run_probe.sh`,
      `docs/plugins.md`
- [ ] Changed the protocol? Both `desktop/` and the Kotlin server, with a
      Kotlin test and a `desktop/` test against `FakePhone`
- [ ] Device-only behaviour: said what you ran it on
- [ ] No `!` (beyond regex groups), no bare sizes or colours, package imports
- [ ] Docs touched only where they help; one change per commit
