import 'package:flutter_test/flutter_test.dart';
import 'package:rr_pocket/main.dart';

void main() {
  testWidgets('shows the waiting screen', (tester) async {
    await tester.pumpWidget(const RrPocketApp());

    expect(find.textContaining('Waiting for a project'), findsOneWidget);
  });
}
