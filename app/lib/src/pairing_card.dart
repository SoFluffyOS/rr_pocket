import 'package:flutter/widgets.dart';
import 'package:rr_pocket/src/pairing.dart';
import 'package:rr_pocket/src/pairing_flow.dart';
import 'package:rr_pocket/src/pairing_note_line.dart';
import 'package:rr_pocket/src/rr_theme.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

/// How a computer pairs with this phone: once, then `flutter run -d pocket`.
/// Allowing or scanning first; the address and code to type as the fallback.
class PairingCard extends StatefulWidget {
  const PairingCard({super.key, required this.flow});

  final PairingFlow flow;

  @override
  State<PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends State<PairingCard> {
  late final Future<Pairing?> _pairing = Pairing.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Pairing?>(
      future: _pairing,
      builder: (context, snapshot) => switch (snapshot.data) {
        final pairing? => ListenableBuilder(
          listenable: widget.flow,
          builder: (context, _) => _PairingDetails(pairing, widget.flow),
        ),
        null => const SizedBox.shrink(),
      },
    );
  }
}

class _PairingDetails extends StatelessWidget {
  const _PairingDetails(this.pairing, this.flow);

  final Pairing pairing;
  final PairingFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = context.fluffyTheme;
    final labelStyle = theme.typography.base1.copyWith(color: theme.muted);
    final valueStyle = theme.typography.base1.copyWith(
      fontWeight: FontWeight.w800,
    );
    final command = switch (pairing.address) {
      final address? => 'pocket pair $address ${pairing.code}',
      null => 'Connect this phone to Wi-Fi first.',
    };
    Widget row(String label, String value) => Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.d4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(value, style: valueStyle),
        ],
      ),
    );
    return RoundCard(
      borderRadius: Spacing.d24,
      padding: EdgeInsets.all(Spacing.d20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pair your computer',
            style: theme.typography.base1.copyWith(fontWeight: FontWeight.w800),
          ),
          Spacing.v4,
          Text(
            'Allow it here when your computer asks, or scan the QR code '
            'it shows.',
            style: theme.typography.base2,
          ),
          Spacing.v16,
          Button(
            variant: ButtonVariant.primary,
            label: 'Scan QR code',
            tooltip: 'Scan the QR code your computer shows',
            enable: !flow.busy,
            onPressed: flow.scan,
          ),
          if (flow.note case final note?) ...[
            Spacing.v12,
            PairingNoteLine(note),
          ],
          Spacing.v24,
          Text('Or type it on your computer', style: labelStyle),
          Spacing.v4,
          row('Address', pairing.address ?? 'no Wi-Fi'),
          row('Code', pairing.displayCode),
          if (pairing.shortFingerprint case final certificate?)
            row('Certificate', certificate),
          Spacing.v12,
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(Spacing.d12),
            decoration: ShapeDecoration(
              color: theme.background,
              shape: const RoundedSuperellipseBorder(borderRadius: Spacing.r12),
            ),
            child: Text(
              command,
              style: theme.typography.base2.copyWith(fontFamily: 'monospace'),
            ),
          ),
          Spacing.v8,
          Text(
            'Once. Then run any project with flutter run -d pocket.',
            style: theme.typography.base2.copyWith(color: theme.muted),
          ),
        ],
      ),
    );
  }
}
