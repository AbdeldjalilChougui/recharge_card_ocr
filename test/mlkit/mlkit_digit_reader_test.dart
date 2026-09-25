import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

TextElement _el(String text, Rect box, double? confidence) => TextElement(
  text: text,
  symbols: const [],
  boundingBox: box,
  recognizedLanguages: const ['en'],
  cornerPoints: const <Point<int>>[],
  confidence: confidence,
  angle: 0,
);

RecognizedText _recognized() {
  final line = TextLine(
    text: '1234 5678 9012 34',
    elements: [
      _el('1234', const Rect.fromLTRB(0, 0, 80, 24), 0.9),
      _el('5678', const Rect.fromLTRB(92, 0, 172, 24), 0.8),
      _el('9012', const Rect.fromLTRB(184, 0, 264, 24), null),
      _el('34', const Rect.fromLTRB(276, 0, 316, 24), 0.7),
    ],
    boundingBox: const Rect.fromLTRB(0, 0, 316, 24),
    recognizedLanguages: const ['en'],
    cornerPoints: const <Point<int>>[],
    confidence: 0.85,
    angle: 0,
  );
  return RecognizedText(
    text: line.text,
    blocks: [
      TextBlock(
        text: line.text,
        lines: [line],
        boundingBox: line.boundingBox,
        recognizedLanguages: const ['en'],
        cornerPoints: const <Point<int>>[],
      ),
    ],
  );
}

/// Stands in for ML Kit's recognizer: no platform channel is touched.
class _CannedRecognizer implements TextRecognizer {
  _CannedRecognizer(this.result);

  final RecognizedText result;
  final paths = <String>[];
  final existedDuringCall = <bool>[];
  var closed = false;

  @override
  String get id => 'fake';

  @override
  TextRecognitionScript get script => TextRecognitionScript.latin;

  @override
  Future<RecognizedText> processImage(InputImage inputImage) async {
    final path = inputImage.filePath!;
    paths.add(path);
    existedDuringCall.add(File(path).existsSync());
    return result;
  }

  @override
  Future<void> close() async => closed = true;
}

PreparedZone _zone() => PreparedZone(
  name: 'code',
  bytes: Uint8List.fromList(const [137, 80, 78, 71]),
  width: 320,
  height: 40,
  sourceRect: const PixelRect(0, 0, 320, 40),
  scale: 1,
);

void main() {
  group('ocrTextFromMlKit', () {
    test('keeps blocks, lines, element boxes and confidences', () {
      final t = ocrTextFromMlKit(
        _recognized(),
        imageWidth: 320,
        imageHeight: 40,
      );
      expect(t.imageWidth, 320);
      expect(t.imageHeight, 40);
      expect(t.blocks, hasLength(1));
      final line = t.blocks.single.lines.single;
      expect(line.text, '1234 5678 9012 34');
      expect(line.confidence, 0.85);
      expect(line.box, const OcrBox(0, 0, 316, 24));
      expect(line.elements.map((e) => e.text), ['1234', '5678', '9012', '34']);
      expect(line.elements.map((e) => e.confidence), [0.9, 0.8, null, 0.7]);
      expect(line.elements[1].box, const OcrBox(92, 0, 172, 24));
    });

    test('feeds the extractor end to end', () {
      final t = ocrTextFromMlKit(_recognized());
      final r = CodeExtractor(
        DigitCodeSpec(groups: const [4, 4, 4, 2]),
      ).read(t);
      expect(r.code, '12345678901234');
      // 0.9, 0.8, line fallback 0.85, 0.7.
      expect(r.confidence, closeTo(0.8125, 1e-9));
    });
  });

  group('MlKitDigitReader', () {
    test(
      'writes the zone to a temp file, maps the result, cleans up',
      () async {
        final fake = _CannedRecognizer(_recognized());
        final tmp = await Directory.systemTemp.createTemp('rco_test');
        addTearDown(() => tmp.delete(recursive: true));
        final reader = MlKitDigitReader(recognizer: fake, tempDirectory: tmp);

        final t = await reader.recognize(_zone());

        expect(fake.paths.single, startsWith(tmp.path));
        expect(fake.paths.single, endsWith('.png'));
        expect(fake.existedDuringCall.single, isTrue);
        expect(File(fake.paths.single).existsSync(), isFalse);
        expect(t.imageWidth, 320);
        expect(t.imageHeight, 40);
        expect(t.blocks.single.lines.single.elements, hasLength(4));
      },
    );

    test('is a TextRecognizerPort and closes the recognizer', () async {
      final fake = _CannedRecognizer(_recognized());
      final TextRecognizerPort port = MlKitDigitReader(recognizer: fake);
      await port.close();
      expect(fake.closed, isTrue);
    });
  });
}
