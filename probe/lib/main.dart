import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:camera/camera.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MaterialApp(home: Probe()));
}

/// Calls each bundled plugin once. MISSING means its native side is not in
/// RR Pocket; anything else means the platform answered.
final checks = <String, Future<Object?> Function()>{
  'battery_plus': () => Battery().batteryLevel,
  'connectivity_plus': () => Connectivity().checkConnectivity(),
  'device_info_plus': () async => (await DeviceInfoPlugin().androidInfo).model,
  'file_picker': () async {
    await FilePicker.clearTemporaryFiles();
    return 'cleared';
  },
  'flutter_secure_storage': () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'probe', value: 'secret');
    return storage.read(key: 'probe');
  },
  'image_picker': () async => (await ImagePicker().retrieveLostData()).isEmpty,
  'in_app_review': () => InAppReview.instance.isAvailable(),
  'package_info_plus': () async =>
      (await PackageInfo.fromPlatform()).packageName,
  'path_provider': () async => (await getApplicationDocumentsDirectory()).path,
  'sensors_plus': () async => (await accelerometerEventStream().first.timeout(
    const Duration(seconds: 3),
  )).z.toStringAsFixed(1),
  'shared_preferences': () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('probe', 'kept');
    return prefs.getString('probe');
  },
  'sqflite': () async {
    final db = await openDatabase(inMemoryDatabasePath);
    final rows = await db.rawQuery('select sqlite_version() as v');
    await db.close();
    return rows.first['v'];
  },
  'url_launcher': () => canLaunchUrl(Uri.parse('https://flutter.dev')),
  'vibration': () => Vibration.hasVibrator(),
  'video_player': () async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      ),
    );
    await controller.initialize().timeout(const Duration(seconds: 20));
    final size = controller.value.size;
    await controller.dispose();
    return '${size.width.toInt()}x${size.height.toInt()}';
  },
  'wakelock_plus': () async {
    await WakelockPlus.enable();
    final enabled = await WakelockPlus.enabled;
    await WakelockPlus.disable();
    return enabled;
  },
  'webview_flutter': () async {
    await WebViewController().loadHtmlString('<p>probe</p>');
    return 'loaded';
  },
  'permission_handler': () async => (await Permission.camera.status).name,
  'flutter_local_notifications': () async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    return 'launched by a notification: ${launch?.didNotificationLaunchApp}';
  },
  'geolocator': () async =>
      'service ${await Geolocator.isLocationServiceEnabled()}, '
      '${(await Geolocator.checkPermission()).name}',
  'local_auth': () async {
    final auth = LocalAuthentication();
    return 'supported ${await auth.isDeviceSupported()}, '
        '${await auth.getAvailableBiometrics()}';
  },
  'camera': () async =>
      (await availableCameras()).map((c) => c.lensDirection.name).join(', '),
  'just_audio': () async {
    final player = AudioPlayer();
    final duration = await player
        .setUrl(
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
        )
        .timeout(const Duration(seconds: 20));
    await player.dispose();
    return duration;
  },
  'audio_session': () async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    return 'configured';
  },
  'record': () async {
    final recorder = AudioRecorder();
    final allowed = await recorder.hasPermission(request: false);
    await recorder.dispose();
    return 'permission $allowed';
  },
  'share_plus': () async {
    // Opens the share sheet; answering at all is the check.
    unawaited(SharePlus.instance.share(ShareParams(text: 'probe')));
    await Future<void>.delayed(const Duration(seconds: 2));
    return 'sheet opened';
  },
};

class Probe extends StatefulWidget {
  const Probe({super.key});

  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  final results = <String, String>{};
  late final web = WebViewController()
    ..loadHtmlString('<h1 style="font-size:64px">webview in RR Pocket</h1>');

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (final MapEntry(key: name, value: check) in checks.entries) {
      String result;
      try {
        result = 'ok ${await check()}';
      } on MissingPluginException catch (e) {
        result = 'MISSING $e';
      } on Object catch (e) {
        result = 'answered with ${e.runtimeType}: $e';
      }
      debugPrint('PROBE $name $result');
      setState(() => results[name] = result);
    }
    debugPrint('PROBE done');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: 120, child: WebViewWidget(controller: web)),
            Expanded(
              child: ListView(
                children: [
                  for (final MapEntry(key: name, value: result)
                      in results.entries)
                    ListTile(
                      dense: true,
                      title: Text(name),
                      subtitle: Text(result),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
