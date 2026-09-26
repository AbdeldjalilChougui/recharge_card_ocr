// Re-runs the package's text logic (CodeExtractor) on the OCR output saved
// in a results JSON, without the device. Use it to try clean-up, ranking or
// review-threshold changes in seconds; image-preparation changes (zones,
// upscaling, contrast) still need a new device run.
//
// Usage, from the example directory:
//   dart run tool/benchmark/replay.dart <results.json> <out.json>
//       [--min-confidence 0.7] [--ambiguity-margin 0.1]
//
// The output has the same shape as the input, with every zone's prediction
// replaced by the one the current package code makes, so report.py reads it.

// The core is plain Dart; importing it directly keeps this tool runnable
// with `dart run` (the package's main library needs Flutter).
// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:recharge_card_ocr/src/core/code_extractor.dart';
import 'package:recharge_card_ocr/src/core/code_read_result.dart';
import 'package:recharge_card_ocr/src/core/digit_code_spec.dart';
import 'package:recharge_card_ocr/src/core/geometry.dart';
import 'package:recharge_card_ocr/src/core/ocr_text.dart';

void main(List<String> argv) {
  if (argv.length < 2) {
    stderr.writeln(
      'usage: dart run tool/benchmark/replay.dart <results.json> <out.json> '
      '[--min-confidence X] [--ambiguity-margin X]',
    );
    exit(64);
  }
  const d = ReviewPolicy();
  var minConfidence = d.minConfidence;
  var margin = d.ambiguityMargin;
  for (var i = 2; i + 1 < argv.length; i += 2) {
    switch (argv[i]) {
      case '--min-confidence':
        minConfidence = double.parse(argv[i + 1]);
      case '--ambiguity-margin':
        margin = double.parse(argv[i + 1]);
    }
  }
  final policy = ReviewPolicy(
    minConfidence: minConfidence,
    ambiguityMargin: margin,
  );
  final data =
      jsonDecode(File(argv[0]).readAsStringSync()) as Map<String, dynamic>;
  final labels = data['labels'] as Map<String, dynamic>;
  final specs = {
    for (final e in (labels['spec'] as Map<String, dynamic>).entries)
      e.key: DigitCodeSpec(
        lengths: {
          for (final l
              in (e.value as Map<String, dynamic>)['lengths'] as List<dynamic>)
            l as int,
        },
      ),
  };
  for (final v in data['variants'] as List<dynamic>) {
    final variant = v as Map<String, dynamic>;
    variant['name'] = '${variant['name']}+replay';
    for (final r in variant['results'] as List<dynamic>) {
      final zones =
          (r as Map<String, dynamic>)['zones'] as Map<String, dynamic>?;
      if (zones == null) continue;
      for (final e in zones.entries) {
        final z = e.value as Map<String, dynamic>;
        final ocr = z['ocr'] as Map<String, dynamic>?;
        final spec = specs[e.key];
        if (ocr == null || spec == null) continue;
        final res = CodeExtractor(spec, policy: policy).read(_ocr(ocr));
        z['code'] = res.code;
        z['formatted'] = res.formatted;
        z['confidence'] = res.confidence;
        z['needsReview'] = res.needsReview;
        z['reasons'] = [for (final x in res.reasons) x.name];
      }
    }
  }
  File(argv[1]).writeAsStringSync(jsonEncode(data));
}

OcrBox _box(Map<String, dynamic> b) => OcrBox(
  (b['l'] as num).toDouble(),
  (b['t'] as num).toDouble(),
  (b['r'] as num).toDouble(),
  (b['b'] as num).toDouble(),
);

OcrText _ocr(Map<String, dynamic> j) => OcrText(
  imageWidth: j['w'] as int?,
  imageHeight: j['h'] as int?,
  blocks: [
    for (final b in (j['blocks'] as List<dynamic>).cast<Map<String, dynamic>>())
      OcrBlock(
        text: b['text'] as String,
        box: _box(b['box'] as Map<String, dynamic>),
        lines: [
          for (final l
              in (b['lines'] as List<dynamic>).cast<Map<String, dynamic>>())
            OcrLine(
              text: l['text'] as String,
              box: _box(l['box'] as Map<String, dynamic>),
              confidence: (l['c'] as num?)?.toDouble(),
              elements: [
                for (final e
                    in (l['el'] as List<dynamic>).cast<Map<String, dynamic>>())
                  OcrElement(
                    text: e['text'] as String,
                    box: _box(e['box'] as Map<String, dynamic>),
                    confidence: (e['c'] as num?)?.toDouble(),
                  ),
              ],
            ),
        ],
      ),
  ],
);
