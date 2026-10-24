import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:rr_pocket/src/code_scan.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// RR Pocket's own QR scanner, for phones where Google's can't run (no Play
/// services). Unlike Google's, it needs the camera permission.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  /// Asks for the camera, then scans.
  static Future<ScanOutcome> open(BuildContext context) async {
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      return const ScanFailed(
        'RR Pocket needs the camera to scan. Allow it in Settings, '
        'or type the address and code on your computer.',
      );
    }
    if (!context.mounted) return const ScanCancelled();
    final text = await context.navigator.push(
      PageRouteBuilder<String>(
        pageBuilder: (context, _, _) => const QrScannerPage(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    return switch (text) {
      final scanned? => Scanned(scanned),
      null => const ScanCancelled(),
    };
  }

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _viewKey = GlobalKey(debugLabel: 'qr');
  StreamSubscription<Barcode>? _scans;
  bool _done = false;

  @override
  void dispose() {
    unawaited(_scans?.cancel());
    super.dispose();
  }

  void _listen(QRViewController controller) {
    _scans = controller.scannedDataStream.listen((barcode) {
      if (_done || !mounted) return;
      if (barcode.code case final text? when text.isNotEmpty) {
        // A computer's Allow question may have opened over the scanner:
        // closing that instead would answer it.
        if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
        _done = true;
        unawaited(HapticFeedback.mediumImpact());
        context.navigator.pop(text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.fluffyTheme;
    final cutOut = Spacing.d280;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: RrColors.slate,
        child: Stack(
          children: [
            QRView(
              key: _viewKey,
              onQRViewCreated: _listen,
              formatsAllowed: const [BarcodeFormat.qrcode],
              overlay: QrScannerOverlayShape(
                borderColor: RrColors.amber,
                overlayColor: FluffyColors.barrier,
                borderRadius: Spacing.d16,
                borderLength: Spacing.d32,
                borderWidth: Spacing.d6,
                cutOutSize: cutOut,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(Spacing.d24),
                child: Column(
                  children: [
                    Text(
                      'Scan the QR code on your computer',
                      textAlign: TextAlign.center,
                      style: theme.typography.base1.copyWith(
                        color: FluffyColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Button(
                      variant: ButtonVariant.secondary,
                      color: FluffyColors.white,
                      label: 'Cancel',
                      tooltip: 'Cancel',
                      onPressed: () => context.navigator.pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
