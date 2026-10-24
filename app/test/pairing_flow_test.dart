import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rr_pocket/main.dart';
import 'package:rr_pocket/src/src.dart';

const _phone = Pairing(
  address: '192.168.1.20',
  code: 'H79GN4XS',
  name: 'Pixel 7',
);
const _link =
    'rrpocket://pair?v=1&hosts=192.168.1.5&port=4000&token=t&name=Simon%27s+Mac';

void main() {
  group('on the home screen', () {
    String? link;

    setUp(() => link = null);

    Future<void> start(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        Pairing.channel,
        (call) async => switch (call.method) {
          'info' => {
            'address': '192.168.1.20',
            'port': 8100,
            'code': 'H79GN4XS',
            'name': 'Pixel 7',
          },
          'takeLink' => link,
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          Pairing.channel,
          null,
        ),
      );
      await tester.pumpWidget(const RrPocketApp());
      await tester.pump();
    }

    /// What the Kotlin server's ScreenPrompt sends, and Dart's reply.
    Future<Object?> fromKotlin(
      WidgetTester tester,
      String method,
      Object? arguments,
    ) {
      const codec = StandardMethodCodec();
      final reply = Completer<Object?>();
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          Pairing.channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (data) => reply.complete(switch (data) {
            final bytes? => codec.decodeEnvelope(bytes),
            null => null,
          }),
        ),
      );
      return reply.future;
    }

    testWidgets('offers scanning first and typing as the fallback', (
      tester,
    ) async {
      await start(tester);

      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Or type it on your computer'), findsOneWidget);
      expect(find.text('H79G N4XS'), findsOneWidget);
      expect(find.text('pocket pair 192.168.1.20 H79GN4XS'), findsOneWidget);
    });

    testWidgets('gives a computer the code when the user allows it', (
      tester,
    ) async {
      await start(tester);

      final reply = fromKotlin(tester, 'askPair', {
        'id': 1,
        'computer': "Simon's Mac",
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text("Pair with Simon's Mac?"), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(await reply, isTrue);
      expect(find.text("Pair with Simon's Mac?"), findsNothing);
      expect(
        find.text("Sent the pairing code to Simon's Mac."),
        findsOneWidget,
      );
    });

    testWidgets('refuses when the user does not allow it', (tester) async {
      await start(tester);

      final reply = fromKotlin(tester, 'askPair', {'id': 1, 'computer': 'Mac'});
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text("Don't allow"));
      await tester.pump(const Duration(milliseconds: 500));

      expect(await reply, isFalse);
    });

    testWidgets('takes the question down when the server gives up', (
      tester,
    ) async {
      await start(tester);

      final reply = fromKotlin(tester, 'askPair', {'id': 7, 'computer': 'Mac'});
      await tester.pump(const Duration(milliseconds: 500));
      unawaited(fromKotlin(tester, 'withdrawPair', {'id': 7}));
      await tester.pump(const Duration(milliseconds: 500));

      expect(await reply, isFalse);
      expect(find.text('Pair with Mac?'), findsNothing);
      expect(find.text('Scan QR code'), findsOneWidget);
    });

    testWidgets('asks one question at a time', (tester) async {
      await start(tester);

      final first = fromKotlin(tester, 'askPair', {'id': 1, 'computer': 'A'});
      await tester.pump(const Duration(milliseconds: 500));
      link = _link;
      unawaited(fromKotlin(tester, 'linkArrived', null));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Pair with A?'), findsOneWidget);
      expect(find.text("Pair with Simon's Mac?"), findsNothing);

      await tester.tap(find.text("Don't allow"));
      await tester.pump(const Duration(milliseconds: 500));

      expect(await first, isFalse);
      expect(find.text("Pair with Simon's Mac?"), findsOneWidget);
      // The first dialog may still be fading out.
      await tester.tap(find.text("Don't allow").last);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('asks about a link that opened the app', (tester) async {
      link = _link;
      await start(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text("Pair with Simon's Mac?"), findsOneWidget);
      await tester.tap(find.text("Don't allow"));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Paired'), findsNothing);
    });
  });

  group('a scanned code', () {
    late _FakeQuestion question;
    late _FakeSender sender;
    var inApp = 0;

    setUp(() {
      question = _FakeQuestion();
      sender = _FakeSender();
      inApp = 0;
    });

    PairingFlow flow(ScanOutcome google, {ScanOutcome? own}) => PairingFlow(
      question: question,
      sender: sender,
      loadPairing: () async => _phone,
      scanWithPlayServices: () async => google,
      scanInApp: () async {
        inApp++;
        return own ?? const ScanCancelled();
      },
    );

    test('is sent only after the user allows it', () async {
      final pairing = flow(const Scanned(_link));

      await pairing.scan();

      expect(question.asked, ["Simon's Mac"]);
      expect(question.where.single, contains('192.168.1.5'));
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single.token, 't');
      expect(pairing.note?.text, "Paired with Simon's Mac.");
      expect(pairing.note?.kind, PairingNoteKind.done);
    });

    test('is not sent when the user refuses', () async {
      question.allow = false;
      final pairing = flow(const Scanned(_link));

      await pairing.scan();

      expect(sender.sent, isEmpty);
      expect(pairing.note, isNull);
    });

    test("shows the computer's error", () async {
      sender.result = const PairFailed('Not paired: scan it again');
      final pairing = flow(const Scanned(_link));

      await pairing.scan();

      expect(pairing.note?.text, 'Not paired: scan it again');
      expect(pairing.note?.kind, PairingNoteKind.failed);
    });

    test('that is not a pairing link is not asked about', () async {
      final pairing = flow(const Scanned('https://flutter.dev'));

      await pairing.scan();

      expect(question.asked, isEmpty);
      expect(pairing.note?.text, contains('not for pairing'));
    });

    test("comes from RR Pocket's own scanner without Play services", () async {
      final pairing = flow(const ScanUnavailable(), own: const Scanned(_link));

      await pairing.scan();

      expect(inApp, 1);
      expect(sender.sent, hasLength(1));
    });

    test('cancelled is not unavailable', () async {
      final pairing = flow(const ScanCancelled());

      await pairing.scan();

      expect(inApp, 0);
      expect(pairing.note, isNull);
    });
  });
}

class _FakeQuestion implements PairQuestion {
  bool allow = true;
  final asked = <String>[];
  final where = <String?>[];

  @override
  Future<bool> ask(String computer, {required Object tag, String? where}) async {
    asked.add(computer);
    this.where.add(where);
    return allow;
  }

  @override
  void withdraw(Object tag) {}
}

class _FakeSender implements PairSender {
  PairResult result = const Paired("Simon's Mac");
  final sent = <PairLink>[];

  @override
  Duration get answerTimeout => Duration.zero;

  @override
  Duration get connectTimeout => Duration.zero;

  @override
  Future<PairResult> send(PairLink link, Pairing phone) async {
    sent.add(link);
    return result;
  }
}
