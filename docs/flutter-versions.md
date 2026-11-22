# Flutter versions

Why RR Pocket runs one Flutter version, what we looked at to run more, and
what we decided. Researched 2026-10-26; nothing here is built.

## Why one version

`flutter run -d pocket` compiles the project to a kernel with the
computer's Flutter. The kernel carries the framework and is built against
the engine's `dart:ui`, so it runs only on the engine its SDK was built for.
RR Pocket carries one debug engine (`libflutter.so`, 38.8 MB uncompressed
in the arm64 APK), so `pocket install` compares engine revisions exactly
(`desktop/lib/src/services/pocket_cli.dart`, `checkEngine`) and tells the
user which version to use.

## What we looked at

| Option | Verdict |
| --- | --- |
| Follow stable: rebuild and release when Flutter stable changes | Cheapest. Most users are on the latest stable. Not automated yet. |
| `pocket` sets up the matching SDK (`fvm install`, `fvm use`) | Cheap, no phone change. Not built. |
| Accept any patch of the same minor (3.47.x) | Unverified. Only with a test matrix proving kernels cross patches. |
| Several engines in one app (Play Feature Delivery) | Dropped as too risky, below. |
| Each release's APKs on GitHub Releases | Built 2026-11-22, below. |
| Download a matching engine at run time | Not allowed: Play forbids apps downloading native code outside Play. |

## Several engines with Play Feature Delivery

On-demand feature modules can carry an engine each: the app installs one
(`SplitInstallManager`), asks Play to remove one (`deferredUninstall`,
done later in the background, not at once), and restarts to switch, since a
process loads one `libflutter.so` and can't unload it. Limits:

- Only the versions built into the current release; a new Flutter version
  is still a new release.
- Play installs only, not a sideloaded APK.
- The Java side (`io.flutter.*`, the 29 plugins, the Kotlin server) exists
  once, so each module would hold only the engine, its snapshots and RR
  Pocket's own home-screen kernel for that engine.
- Flutter's Gradle plugin puts the engine in the base module; pulling it
  out is custom build work, plus a CI build per version. About 15 MB per
  version to download.

What we measured: the embedding jar (`flutter_embedding_debug`) of 3.47.7
and 3.47.8 is byte-identical; `FlutterJNI`, the class the engine registers
its natives on, is identical from 3.44.9 to 3.47.8 (42 native methods),
while the jar grew from 438 to 448 classes. Unverified: whether an older
engine runs against a newer embedding; the engine also looks up other Java
classes by name. Dropped 2026-10-26: too risky for what it gives.

## Each release on GitHub Releases

Built 2026-11-22. Each production release on Play is tagged `app-<version>`
and its APKs (arm64 and x64) are published as a GitHub release
(`.github/workflows/release_github.yml`), so a project that can't move to
the Flutter on Play can still find an RR Pocket for its version. `pocket
install` and `pocket doctor` link there when the engines differ. Before
this, 1.0.1 (Flutter 3.47.9) was published by hand from its tag; 1.0.0
(3.47.8) was not.

- **Built from the release's tag**, with its own scripts and the Flutter it
  ran, so the APK carries the same engine and plugins as Play's.
- **Its own application ID and name**: `io.sofluffy.raccoon.runtime.pocket`
  plus `.flutter3_47_9`, shown as "RR Pocket 3.47.9". Play re-signs the app,
  so an APK we sign can't replace the Play install; under its own ID it
  installs beside it, and beside other versions. Only one runs at a time:
  all use ports 8100 and 8101. Each has its own pairing code, so switching
  means `pocket pair` again.
- **Signed with the upload key**, the one CI signs Play uploads with.
- **The APKs are frozen**, so the protocol stays backward compatible for
  them: a newer `pocket` must still pair with and run on every published
  release.
- Older minors than the app's Dart constraint allows (Flutter 3.44.9 ships
  Dart 3.12.2; the app needs `^3.13.5`) don't build as is: each would mean
  lowering the constraint, dropping newer syntax, checking `sofluffy_ui`,
  every plugin and `probe/`. Not done.
