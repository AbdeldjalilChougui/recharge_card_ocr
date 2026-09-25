import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

import 'support/fake_ocr.dart';

/// A port that returns canned OCR output per zone and records what it saw.
class FakeRecognizer implements TextRecognizerPort {
  FakeRecognizer(this.outputs);

  final Map<String, OcrText> outputs;
  final seen = <PreparedZone>[];
  var closed = false;

  @override
  Future<OcrText> recognize(PreparedZone zone) async {
    seen.add(zone);
    return outputs[zone.name] ?? const OcrText(blocks: []);
  }

  @override
  Future<void> close() async => closed = true;
}

Uint8List _photo() {
  final im = img.Image(width: 340, height: 200);
  img.fill(im, color: img.ColorRgb8(200, 200, 200));
  return img.encodeJpg(im);
}

void main() {
  test('reads each zone through the port with its own spec', () async {
    final port = FakeRecognizer({
      'code': fakeText([fakeLine('1234 5678 9012 34')]),
      'serial': fakeText([fakeLine('SN 0001 2345 6789')]),
    });
    final reader = CardCodeReader(
      recognizer: port,
      layout: ZoneLayout.rechargeCard,
      specs: {
        'code': DigitCodeSpec(groups: const [4, 4, 4, 2]),
        'serial': DigitCodeSpec(lengths: const {12}),
      },
      useIsolate: false,
    );
    final result = await reader.read(_photo());
    expect(result['code']!.code, '12345678901234');
    expect(result['serial']!.code, '000123456789');
    expect(result.needsReview, isFalse);
    expect(port.seen.map((z) => z.name), containsAll(['code', 'serial']));
    expect(result.imageWidth, 340);
    expect(result.imageHeight, 200);
  });

  test('zones without a spec are not sent to OCR', () async {
    final port = FakeRecognizer({
      'code': fakeText([fakeLine('1234 5678 9012 34')]),
    });
    final reader = CardCodeReader(
      recognizer: port,
      layout: ZoneLayout.rechargeCard,
      specs: {
        'code': DigitCodeSpec(groups: const [4, 4, 4, 2]),
      },
      useIsolate: false,
    );
    final result = await reader.read(_photo());
    expect(port.seen.map((z) => z.name), ['code']);
    expect(result.zones.keys, ['code']);
  });

  test('any zone needing review flags the card', () async {
    final port = FakeRecognizer({
      'code': fakeText([fakeLine('1234 5678 9012 34')]),
      'serial': fakeText([fakeLine('0001 2345', confidence: 0.3)]),
    });
    final reader = CardCodeReader(
      recognizer: port,
      layout: ZoneLayout.rechargeCard,
      specs: {
        'code': DigitCodeSpec(groups: const [4, 4, 4, 2]),
        'serial': DigitCodeSpec(lengths: const {12}),
      },
      useIsolate: false,
    );
    final result = await reader.read(_photo());
    expect(result['code']!.needsReview, isFalse);
    expect(result['serial']!.needsReview, isTrue);
    expect(result.needsReview, isTrue);
  });

  test('uses the isolate path by default', () async {
    final port = FakeRecognizer({
      'code': fakeText([fakeLine('1234 5678 9012 34')]),
    });
    final reader = CardCodeReader(
      recognizer: port,
      layout: ZoneLayout.rechargeCard,
      specs: {
        'code': DigitCodeSpec(groups: const [4, 4, 4, 2]),
      },
    );
    final result = await reader.read(_photo());
    expect(result['code']!.code, '12345678901234');
  });

  test('specs must name zones of the layout', () {
    expect(
      () => CardCodeReader(
        recognizer: FakeRecognizer({}),
        layout: ZoneLayout.rechargeCard,
        specs: {
          'nope': DigitCodeSpec(lengths: const {4}),
        },
      ),
      throwsArgumentError,
    );
  });

  test('close closes the port', () async {
    final port = FakeRecognizer({});
    final reader = CardCodeReader(
      recognizer: port,
      layout: ZoneLayout.rechargeCard,
      specs: {
        'code': DigitCodeSpec(lengths: const {4}),
      },
    );
    await reader.close();
    expect(port.closed, isTrue);
  });
}
