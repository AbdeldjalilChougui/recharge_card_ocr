import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/geometry.dart';
import '../core/ocr_text.dart';
import '../image/prepared.dart';
import '../port/text_recognizer_port.dart';

/// Converts ML Kit output to engine-neutral [OcrText].
///
/// Element and line confidences are copied as reported; ML Kit may leave
/// them null, in which case the extractor falls back to the line value and
/// then to `ReviewPolicy.assumedConfidence`.
OcrText ocrTextFromMlKit(
  RecognizedText recognized, {
  int? imageWidth,
  int? imageHeight,
}) {
  OcrBox box(dynamic r) => OcrBox(
    (r.left as num).toDouble(),
    (r.top as num).toDouble(),
    (r.right as num).toDouble(),
    (r.bottom as num).toDouble(),
  );

  return OcrText(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    blocks: [
      for (final b in recognized.blocks)
        OcrBlock(
          text: b.text,
          box: box(b.boundingBox),
          lines: [
            for (final l in b.lines)
              OcrLine(
                text: l.text,
                box: box(l.boundingBox),
                confidence: l.confidence,
                elements: [
                  for (final e in l.elements)
                    OcrElement(
                      text: e.text,
                      box: box(e.boundingBox),
                      confidence: e.confidence,
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

/// A [TextRecognizerPort] backed by Google ML Kit text recognition v2
/// (on-device, Latin script by default). Android and iOS only.
///
/// Each prepared zone is written to a temporary PNG file, recognised with
/// [TextRecognizer.processImage] and deleted afterwards.
class MlKitDigitReader implements TextRecognizerPort {
  /// Creates a reader. Pass [recognizer] to reuse or substitute the ML Kit
  /// recognizer, and [tempDirectory] to control where zone files are
  /// written (defaults to [Directory.systemTemp]).
  MlKitDigitReader({
    TextRecognizer? recognizer,
    TextRecognitionScript script = TextRecognitionScript.latin,
    Directory? tempDirectory,
  }) : _recognizer = recognizer ?? TextRecognizer(script: script),
       _tempDirectory = tempDirectory;

  final TextRecognizer _recognizer;
  final Directory? _tempDirectory;
  static int _counter = 0;

  @override
  Future<OcrText> recognize(PreparedZone zone) async {
    final dir = _tempDirectory ?? Directory.systemTemp;
    final file = File(
      '${dir.path}${Platform.pathSeparator}rco_${zone.name}_'
      '${DateTime.now().microsecondsSinceEpoch}_${_counter++}.png',
    );
    await file.writeAsBytes(zone.bytes, flush: true);
    try {
      final result = await _recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      return ocrTextFromMlKit(
        result,
        imageWidth: zone.width,
        imageHeight: zone.height,
      );
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Best effort: a leftover temp file must not fail the scan.
      }
    }
  }

  @override
  Future<void> close() => _recognizer.close();
}
