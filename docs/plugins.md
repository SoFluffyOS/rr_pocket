# Which plugins RR Pocket bundles

Researched 2026-10-24. Downloads are pub.dev's 30-day counts that day
(`pub.dev/api/packages/<name>/score`). Mechanisms, permissions and sizes come
from each package's latest pubspec, plugin manifest and Gradle file.
"Unverified" means read or inferred, not tried.

## The finding that changes the plan

flutter/packages is moving its Android implementations to JNI.
`path_provider_android` 2.3 has no Android code at all (jnigen calling
framework classes), and `shared_preferences_android` 2.5 is "Pigeon JNI".
**So `jni` and `jni_flutter` are the most valuable things RR Pocket carries.**
A jnigen package that calls only Android framework classes works at any
version once `jni` is in the app. Packages calling their own Kotlin or
third-party classes still need that code bundled, and a version mismatch
shows up as `NoSuchMethodError` instead of a missing channel.

## Tiers

Tier 1: common, no sensitive permission. Tier 2: common, asks at run time.
Tier 3: needs per-app config or a Play declaration. Skip: can't work in a
shared app.

| Package | Mechanism | 30d downloads | Permissions, policy | Size, config | Tier |
|---|---|---|---|---|---|
| path_provider | jnigen, no Android code | 9.8M | | `jni` only | 1, in |
| shared_preferences | Pigeon JNI + DataStore | 8.5M | | | 1, in |
| url_launcher | Pigeon (Kotlin) | 8.8M | | androidx.browser | 1 |
| package_info_plus | MethodChannel | 7.1M | | reports RR Pocket's name and version | 1 |
| image_picker | Pigeon | 5.6M | none (photo picker) | | 1 |
| flutter_secure_storage | MethodChannel | 5.6M | | Tink | 1 |
| share_plus | MethodChannel | 4.9M | | | 1 |
| file_picker | MethodChannel (unverified) | 4.7M | none (SAF) | | 1 |
| device_info_plus | MethodChannel | 4.7M | | | 1 |
| connectivity_plus | MethodChannel | 4.4M | ACCESS_NETWORK_STATE | | 1 |
| webview_flutter | Pigeon ProxyApi | 4.0M | | androidx.webkit | 1 |
| video_player | Pigeon | 3.7M | | media3 ExoPlayer | 1 |
| sqflite | MethodChannel | 3.2M | | | 1 |
| wakelock_plus | Pigeon | 2.6M | | | 1 |
| sensors_plus | EventChannel | 0.77M | | | 1 |
| file_selector | Pigeon | 0.93M | | | 1 |
| in_app_review, vibration, battery_plus, fluttertoast, flutter_timezone, flutter_tts, android_intent_plus, app_settings, printing, gal | MethodChannel | 0.33-1.4M each | vibration: VIBRATE | in_app_review opens RR Pocket's own listing | 1 |
| permission_handler | MethodChannel | 3.9M | grants only what RR Pocket's manifest declares | | 2 |
| flutter_local_notifications | MethodChannel | 3.5M | POST_NOTIFICATIONS, VIBRATE; not the exact-alarm ones | desugaring, receivers | 2 |
| geolocator, geocoding | MethodChannel, Pigeon | 2.9M, 0.75M | fine and coarse location; **never background** (Play declaration) | play-services-location | 2 |
| local_auth | Pigeon | 1.8M | USE_BIOMETRIC | **MainActivity must become FlutterFragmentActivity** | 2 |
| mobile_scanner | MethodChannel | 2.0M | CAMERA | bundled ML Kit model, several MB (unverified) | 2 |
| camera | Pigeon ProxyApi (CameraX) | 0.97M | CAMERA, RECORD_AUDIO | CameraX, Guava; **32 releases a year, highest skew risk** | 2 |
| just_audio + audio_session, audioplayers | MethodChannel | 1.5M, 1.5M | | media3 | 2 |
| record, speech_to_text | MethodChannel | 1.45M, 0.8M | RECORD_AUDIO | | 2 |
| app_links | MethodChannel | 3.5M | | the user's domains and schemes can't be declared (Expo Go: same) | 3, partial |
| google_maps_flutter | Pigeon | 1.1M | | needs an API key; RR Pocket can ship its own, as Expo Go does | 3 |
| firebase_* | MethodChannel, Pigeon | core 5.6M, messaging 4.1M | | app id registered to the user's package; the user adds RR Pocket's package to their Firebase project (unverified). Large. Expo Go has no Firebase | 3 |
| photo_manager, open_filex | MethodChannel | 0.5M, 0.69M | READ_MEDIA_* forces Play's Photo and Video declaration | strip with `tools:node="remove"` or skip | 3, skip |
| workmanager, flutter_background_service | MethodChannel | 0.34M, 0.1M | foreground service types need a declaration | background engines likely run RR Pocket's kernel, not the user's (unverified) | skip |
| google_sign_in | Pigeon | 2.4M | | an Android OAuth client's package + SHA-1 is unique across all of GCP | skip |
| in_app_purchase, purchases_flutter, google_mobile_ads, flutter_stripe | | 0.5-1.0M | | billing is tied to the package; AdMob needs an app id | skip |

Pure Dart, nothing to bundle: flutter_native_splash, cached_network_image
(needs sqflite and path_provider), hive, haptics (`HapticFeedback`).

## Expo Go as the yardstick

Expo Go's modules (docs.expo.dev/versions/latest) map onto the table:
Camera to camera, Location to geolocator, Sensors, Notifications (Expo Go
dropped remote push on Android from SDK 53), SecureStore, SQLite,
ImagePicker and DocumentPicker, Audio and Video, WebBrowser and Linking to
url_launcher, Sharing, Network, Device and Application, KeepAwake,
LocalAuthentication, Print, StoreReview, Maps, WebView. Its FAQ lists what
Expo Go can't do, the same limits as here: no unbundled native code, no
remote push, no app links, one SDK version per build.

## Version skew

Expo pins one set per SDK (`bundledNativeModules.json`, patch ranges) and
`npx expo install --fix` aligns a project to it. Our equivalent: before
compiling, the device writes a `pubspec_overrides.yaml` pinning every
bundled `*_android` package to RR Pocket's version. Pigeon's wire format is
positional, so Dart and Kotlin sides at different versions are unsafe.
Constraint conflicts with platform interfaces are possible (untested).

Releases in the last 12 months: camera_android_camerax 32,
flutter_local_notifications 23, google_maps_flutter_android 21,
image_picker_android 17, webview_flutter_android 16,
shared_preferences_android 16, path_provider_android 5, sqflite_android 5,
permission_handler_android 2. Several switched internals inside a minor
version (url_launcher 6.3.30 and image_picker 0.8.13+17 to Kotlin Pigeon,
path_provider 2.3.0 and shared_preferences 2.5.0 to JNI).

## First bundle

- **Tier 1:** path_provider, shared_preferences (+ jni, jni_flutter),
  url_launcher, package_info_plus, device_info_plus, connectivity_plus,
  share_plus, image_picker, file_picker, flutter_secure_storage, sqflite,
  webview_flutter, video_player, wakelock_plus, sensors_plus, in_app_review,
  vibration, battery_plus.
- **Tier 2:** permission_handler, flutter_local_notifications, geolocator,
  local_auth (with FlutterFragmentActivity), camera, just_audio +
  audio_session, record.
- **After:** mobile_scanner, google_maps_flutter with our own key,
  audioplayers.

## Tier 1, bundled and checked (2026-10-24)

All 18 Tier 1 plugins are in the app; `probe/` calls each one from a project
with no platform folders, pinned with `tool/pin_plugins.py`. On the emulator
(Android 15, x86_64) every one answered: real values from battery,
connectivity, device info, secure storage, image picker, package info,
paths, the accelerometer, shared preferences, SQLite 3.44.3, url_launcher,
video (1280x720 from the network), wake lock; the web view drew as a
platform view, the share sheet opened. Vibration and in_app_review answered
false (no vibrator on the emulator, not installed from Play).

| | arm64 APK |
|---|---|
| path_provider, shared_preferences | 82.9 MB |
| all 18 | 94.3 MB (+11.4) |

The 11.4 MB is 5.2 MB of plugin code (dex: ExoPlayer, WebKit, Tink, ...)
and 5.9 MB of RR Pocket's own kernel, which now holds the plugins' Dart
sides through the generated registrant. Users' apps never run that kernel,
so it is the first thing to trim. The debug build type also skips R8; it
can't simply be turned on, since Pigeon JNI finds Kotlin classes by name.
Permissions added: ACCESS_NETWORK_STATE, VIBRATE, WAKE_LOCK, none with a
Play declaration.

Found on the way:

- **A project's first run got no Dart-registered plugins.** `flutter
  attach` compiles before it writes `dart_plugin_registrant.dart`, so the
  first kernel has none (image_picker, path_provider, shared_preferences,
  sqflite, url_launcher, video_player, webview failed; MethodChannel
  plugins worked). The second run is fine. `tool/drive_attach.py` runs
  `flutter build bundle` first when the registrant is missing (10 s, once);
  the custom device will write the registrant itself.
- **canLaunchUrl said false for https.** Android 11's package visibility:
  the app's manifest must declare the intents it queries, and the user's
  project can't. RR Pocket declares VIEW for http and https, SENDTO for
  mailto and sms, DIAL for tel.
- `tool/pin_plugins.py` is the `expo install --fix` step: it writes the
  project's `pubspec_overrides.yaml` with the 21 Android packages RR Pocket
  carries (the 18, plus jni, jni_flutter, flutter_plugin_android_lifecycle,
  as their `*_android` implementations).

## Open

- `sqlite3` (3.2M) and drift (1.7M) now use build hooks that download a
  prebuilt `libsqlite3.so`; `sqlite3_flutter_libs` is end of life. Drift apps
  fail unless RR Pocket bundles the library and the device maps the native
  asset to it. Worth a spike.
- Plugins that start a background engine (workmanager, notification action
  callbacks, FCM background handler) probably can't run the user's code.
- Size per plugin is not measured yet.
- Not checked: MethodChannel vs Pigeon for most plus_plugins; Firebase with
  a package name that doesn't match; the Play help pages for background
  location and foreground service types.
