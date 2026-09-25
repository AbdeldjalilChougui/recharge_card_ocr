import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';
import 'package:recharge_card_ocr_example/main.dart';
import 'package:recharge_card_ocr_example/result_view.dart';

OcrText _line(String text, double confidence) => OcrText(
  blocks: [
    OcrBlock(
      text: text,
      box: const OcrBox(0, 0, 300, 24),
      lines: [
        OcrLine(
          text: text,
          box: const OcrBox(0, 0, 300, 24),
          confidence: confidence,
        ),
      ],
    ),
  ],
);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('home page starts empty with a scan button', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Scan a card to read its code.'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('a trusted result shows OK and the code', (tester) async {
    final r = CodeExtractor(
      exampleSpecs['code']!,
    ).read(_line('123456789012345', 0.95));
    await tester.pumpWidget(_wrap(ZoneResultCard(name: 'code', result: r)));
    expect(find.text('123456789012345'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('a doubtful result asks for a check and lists reasons', (
    tester,
  ) async {
    final r = CodeExtractor(
      exampleSpecs['code']!,
    ).read(_line('123456789012345', 0.4));
    await tester.pumpWidget(_wrap(ZoneResultCard(name: 'code', result: r)));
    expect(find.text('Check'), findsOneWidget);
    expect(find.textContaining('lowConfidence'), findsOneWidget);
  });

  testWidgets('the overlay renders in the scan layout without a camera', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CardScanOverlay(
            layout: ZoneLayout.rechargeCard,
            labels: {'code': 'الرمز'},
          ),
        ),
      ),
    );
    expect(find.byType(CardScanOverlay), findsOneWidget);
  });
}
