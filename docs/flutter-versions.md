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
| Older versions as APKs on GitHub Releases | Possible, on request only, below. |
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

## Older versions on GitHub Releases

The low-risk way to serve users who can't upgrade, built only when someone
asks:

- A different application ID (`io.sofluffy.raccoon.runtime.pocket.flutter3_44`)
  and its own signing key, so it installs beside the Play app instead of
  replacing it (an APK can't carry Play's signature). Only one runs at a
  time: both use ports 8100 and 8101.
- Older minors don't build as is: the app needs Dart `^3.13.5`; Flutter
  3.44.9 ships Dart 3.12.2. Each means lowering the constraint, dropping
  newer syntax, checking `sofluffy_ui` and every plugin, and `probe/`.
  Patches of the current minor build unchanged.
- The APKs are frozen, so the protocol stays backward compatible for them.
