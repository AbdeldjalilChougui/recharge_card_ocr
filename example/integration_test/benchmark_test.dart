// On-device accuracy benchmark for recharge_card_ocr with real ML Kit.
//
// Do not run this file directly: start it with
//   dart run tool/benchmark/run_on_device.dart --dataset <dir> --out <file>
// which installs the example app, pushes the dataset into the app's private
// files directory, and pulls the results back. See tool/benchmark/README.md.
//
// For every image listed in labels.json, the full pipeline runs:
// CardCodeReader (EXIF fix, zone crops, upscale, contrast) + MlKitDigitReader
// (ML Kit text recognition v2, Latin) + CodeExtractor. The prediction,
// confidence, needsReview, reasons, raw OCR text and time are recorded.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

const _appId = 'biz.abdeldjalilchougui.recharge_card_ocr_example';

/// Waits until the host runner creates [file] (it answers `@@BENCH@@` lines).
Future<void> _waitFor(File file, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (!file.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'The host did not answer (${file.path}). Start this test with '
        'tool/benchmark/run_on_device.dart.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

DigitCodeSpec _spec(Map<String, dynamic> j) => DigitCodeSpec(
  lengths: {for (final l in j['lengths'] as List<dynamic>) l as int},
  groups: (j['groups'] as List<dynamic>?)?.map((g) => g as int).toList(),
  prefix: j['prefix'] as String?,
);

NormRect _rect(List<dynamic> r) => NormRect.fromLTRB(
  (r[0] as num).toDouble(),
  (r[1] as num).toDouble(),
  (r[2] as num).toDouble(),
  (r[3] as num).toDouble(),
);

/// One benchmark configuration: package defaults unless overridden.
class _Variant {
  _Variant(this.name, Map<String, dynamic> j)
    : prepare = (j['prepare'] as Map<String, dynamic>?) ?? const {},
      policy = (j['policy'] as Map<String, dynamic>?) ?? const {},
      layout = (j['layout'] as Map<String, dynamic>?) ?? const {},
      raw = j;

  final String name;
  final Map<String, dynamic> prepare;
  final Map<String, dynamic> policy;
  final Map<String, dynamic> layout;
  final Map<String, dynamic> raw;

  PrepareOptions options() {
    const d = PrepareOptions();
    double num_(String k, double v) => (prepare[k] as num?)?.toDouble() ?? v;
    return PrepareOptions(
      minShortSide: (prepare['minShortSide'] as int?) ?? d.minShortSide,
      maxUpscale: num_('maxUpscale', d.maxUpscale),
      grayscale: (prepare['grayscale'] as bool?) ?? d.grayscale,
      contrastStretch:
          (prepare['contrastStretch'] as bool?) ?? d.contrastStretch,
      lowPercentile: num_('lowPercentile', d.lowPercentile),
      highPercentile: num_('highPercentile', d.highPercentile),
    );
  }

  ReviewPolicy reviewPolicy() {
    const d = ReviewPolicy();
    double num_(String k, double v) => (policy[k] as num?)?.toDouble() ?? v;
    return ReviewPolicy(
      minConfidence: num_('minConfidence', d.minConfidence),
      ambiguityMargin: num_('ambiguityMargin', d.ambiguityMargin),
      assumedConfidence: num_('assumedConfidence', d.assumedConfidence),
    );
  }

  ZoneLayout zoneLayout() {
    const base = ZoneLayout.rechargeCard;
    if (layout.isEmpty) return base;
    return ZoneLayout(
      cardAspectRatio: base.cardAspectRatio,
      zones: {
        ...base.zones,
        for (final e in layout.entries) e.key: _rect(e.value as List<dynamic>),
      },
    );
  }
}

Map<String, dynamic> _box(OcrBox b) => {
  'l': b.left.round(),
  't': b.top.round(),
  'r': b.right.round(),
  'b': b.bottom.round(),
};

double? _round(double? v) => v == null ? null : (v * 1000).round() / 1000;

/// Serialises the OCR output so failures can be inspected (and replayed on
/// the host) without re-running ML Kit.
Map<String, dynamic> _ocrJson(OcrText t) => {
  'w': t.imageWidth,
  'h': t.imageHeight,
  'blocks': [
    for (final b in t.blocks)
      {
        'text': b.text,
        'box': _box(b.box),
        'lines': [
          for (final l in b.lines)
            {
              'text': l.text,
              'box': _box(l.box),
              'c': _round(l.confidence),
              'el': [
                for (final e in l.elements)
                  {
                    'text': e.text,
                    'box': _box(e.box),
                    'c': _round(e.confidence),
                  },
              ],
            },
        ],
      },
  ],
};

/// Wraps ML Kit and keeps the last OCR output per zone.
class _RecordingPort implements TextRecognizerPort {
  _RecordingPort(this.inner);

  final TextRecognizerPort inner;
  final last = <String, OcrText>{};
  final zoneSizes = <String, List<int>>{};

  @override
  Future<OcrText> recognize(PreparedZone zone) async {
    final t = await inner.recognize(zone);
    last[zone.name] = t;
    zoneSizes[zone.name] = [zone.width, zone.height];
    return t;
  }

  @override
  Future<void> close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recharge_card_ocr benchmark', (tester) async {
    final files = Directory('/data/data/$_appId/files');
    final bench = Directory('${files.path}/bench');
    // ignore: avoid_print
    print('@@BENCH@@ready@@${files.path}');
    await _waitFor(File('${bench.path}/.pushed'), const Duration(minutes: 15));

    final labels =
        jsonDecode(File('${bench.path}/labels.json').readAsStringSync())
            as Map<String, dynamic>;
    final specJson = labels['spec'] as Map<String, dynamic>;
    final specs = {
      for (final e in specJson.entries)
        e.key: _spec(e.value as Map<String, dynamic>),
    };
    final configFile = File('${bench.path}/config.json');
    final variantsJson = configFile.existsSync()
        ? (jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>)
        : {
            'variants': [
              {'name': 'default'},
            ],
          };
    final variants = [
      for (final v in variantsJson['variants'] as List<dynamic>)
        _Variant((v as Map<String, dynamic>)['name'] as String, v),
    ];
    final images = (labels['images'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final port = _RecordingPort(MlKitDigitReader());
    final out = <Map<String, dynamic>>[];
    try {
      for (final variant in variants) {
        final reader = CardCodeReader(
          recognizer: port,
          layout: variant.zoneLayout(),
          specs: specs,
          options: variant.options(),
          policy: variant.reviewPolicy(),
        );
        // Warm-up: loads the ML Kit model so it is not counted in timings.
        await reader.read(
          File('${bench.path}/${images.first['file']}').readAsBytesSync(),
        );
        final results = <Map<String, dynamic>>[];
        for (final item in images) {
          final bytes = File('${bench.path}/${item['file']}').readAsBytesSync();
          port.last.clear();
          final sw = Stopwatch()..start();
          Map<String, dynamic> row;
          try {
            final r = await reader.read(bytes);
            sw.stop();
            row = {
              'file': item['file'],
              'ms': sw.elapsedMilliseconds,
              'image': [r.imageWidth, r.imageHeight],
              'zones': {
                for (final e in r.zones.entries)
                  e.key: {
                    'code': e.value.code,
                    'formatted': e.value.formatted,
                    'confidence': _round(e.value.confidence),
                    'needsReview': e.value.needsReview,
                    'reasons': [for (final x in e.value.reasons) x.name],
                    'rawText': e.value.best?.rawText,
                    'alternatives': [
                      for (final a in e.value.alternatives)
                        {
                          'code': a.code,
                          'score': _round(a.score),
                          'confidence': _round(a.confidence),
                        },
                    ],
                    'score': _round(e.value.best?.score),
                    'zoneSize': port.zoneSizes[e.key],
                    'ocrText': port.last[e.key]?.text,
                    'ocr': port.last[e.key] == null
                        ? null
                        : _ocrJson(port.last[e.key]!),
                  },
              },
            };
          } on Object catch (e) {
            sw.stop();
            row = {
              'file': item['file'],
              'ms': sw.elapsedMilliseconds,
              'error': '$e',
            };
          }
          results.add(row);
          final z = (row['zones'] as Map<String, dynamic>?)?['code'];
          // ignore: avoid_print
          print(
            '@@BENCHROW@@${variant.name} ${item['file']} '
            '${z?['code']} review=${z?['needsReview']} ${row['ms']}ms',
          );
        }
        out.add({
          'name': variant.name,
          'config': variant.raw,
          'results': results,
        });
      }
    } finally {
      await port.close();
    }

    File('${bench.path}/results.json').writeAsStringSync(
      jsonEncode({
        'device': {
          'os': Platform.operatingSystemVersion,
          'processors': Platform.numberOfProcessors,
        },
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'labels': labels,
        'variants': out,
      }),
    );
    // ignore: avoid_print
    print('@@BENCH@@done@@${bench.path}/results.json');
    await _waitFor(File('${bench.path}/.pulled'), const Duration(minutes: 5));
  }, timeout: Timeout.none);
}
