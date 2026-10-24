# Google Play listing

Paste into Play Console → Grow → Store presence → Main store listing.
Graphics are in `play/` (remake with `tool/capture_store_screens.py`, then
`tool/make_store_assets.py`).

## Before publishing (Simon)

- **Where users get `pocket.dart`.** The listing tells them to run it; today
  it lives in this private repo. Publish it (a pub package, or a public
  repo), then put the link where the description says `<link>`.
- **Host the privacy policy** (`privacy-policy.md`) and give Play its URL.
- **First upload by hand:** Play's API can't create the app, so the first
  bundle goes up in the Play Console (from the workflow's artifact or
  `tool/build_aab.sh`); later releases can come from the workflow.

## App name (30 max)

RR Pocket

## Short description (80 max, this is 74)

Run your Flutter project on your phone over Wi-Fi. No Android SDK, no adb.

## Full description (4000 max)

RR Pocket runs the Flutter project you're working on, on your Android phone, straight from your computer. No Android SDK, no Gradle build, no adb: just the Flutter SDK you already have.

HOW IT WORKS
1. Open RR Pocket. It shows its address and a pairing code.
2. On your computer, pair once: dart pocket.dart pair <address> <code>
   (get pocket.dart from <link>)
3. In any Flutter project: flutter run -d pocket

Your app opens inside RR Pocket. Change your code, press r, and hot reload shows it in under a second. Hot restart, DevTools, breakpoints and your print output work like on any other device. Press q and the phone is back to RR Pocket.

26 PLUGINS BUILT IN
Your app can use camera, geolocator, flutter_local_notifications, local_auth, image_picker, file_picker, url_launcher, share_plus, shared_preferences, path_provider, sqflite, flutter_secure_storage, video_player, just_audio, audio_session, record, webview_flutter, permission_handler, connectivity_plus, device_info_plus, package_info_plus, battery_plus, sensors_plus, vibration, wakelock_plus and in_app_review. Plain Dart packages work as they are.

GOOD TO KNOW
• Your project must use the same Flutter version as RR Pocket; the home screen shows which. flutter run tells you when it differs.
• Plugin versions must match the ones built in: dart pocket.dart pin sets them for you.
• A plugin RR Pocket doesn't carry throws MissingPluginException when called; build your app the usual way for that one.
• Your phone and computer need to be on the same network.

WHY "RR"
Raccoon Runtime, the Flutter runtime underneath. And r and R: the keys that hot reload and hot restart your app.

RR Pocket is a development tool: it runs the code a paired computer sends it. Pair only computers you trust.

PRIVACY
RR Pocket collects nothing and sends nothing to any server. It talks only to the computer you pair it with, on your network. Camera, microphone, location, notifications and biometrics are there for the app you run in it, and are asked for only when that app asks.

## Category and details

- App category: **Tools**
- Tags: Developer tools
- Content rating: answer the questionnaire as a developer tool with no user content, no ads, no purchases; expect "Everyone".
- Target audience: 18 and over (developers).
- Ads: no. In-app purchases: no.

## Data safety form

- Does the app collect or share user data? **No.**
- Is data encrypted in transit? The pairing traffic is plain HTTP on the
  local network; answer accordingly (no user data is sent).
- The only stored value is the pairing code, kept on the device.

## Permissions, if Play asks why

| Permission | Why |
|---|---|
| Camera, microphone | For the app being developed (camera, record, speech plugins) |
| Fine and coarse location | For the app being developed (geolocator); foreground only, never background |
| Notifications | For the app being developed (flutter_local_notifications) |
| Biometrics | For the app being developed (local_auth) |
| Internet, network state | Pairing and running projects over the local network |
| Boot completed | Restoring notifications the app being developed scheduled |

## What's new (first release)

In `distribution/whatsnew/whatsnew-en-US`, which the workflow uploads.

## Graphics

| File | Play Console slot |
|---|---|
| `play/icon-512.png` | App icon (512×512) |
| `play/feature-graphic.png` | Feature graphic (1024×500) |
| `play/1-your-app.png` … `play/5-plugins.png` | Phone screenshots (1080×1920), in this order |
