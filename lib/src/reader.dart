import 'dart:typed_data';

import 'core/code_extractor.dart';
import 'core/code_read_result.dart';
import 'core/digit_code_spec.dart';
import 'core/geometry.dart';
import 'core/zone_layout.dart';
import 'image/card_image_preparer.dart';
import 'image/prepared.dart';
import 'port/text_recognizer_port.dart';

/// Results for every zone of one photo.
class CardReadResult {
  /// Creates a result.
  const CardReadResult({
    required this.zones,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Per-zone results keyed by zone name.
  final Map<String, CodeReadResult> zones;

  /// Photo width after orientation correction.
  final int imageWidth;

  /// Photo height after orientation correction.
  final int imageHeight;

  /// The result for zone [name], or null.
  CodeReadResult? operator [](String name) => zones[name];

  /// Whether any zone needs review.
  bool get needsReview => zones.values.any((r) => r.needsReview);
}

/// Photo in, codes out: prepares the zones, sends each one through a
/// [TextRecognizerPort] and extracts the code with its [DigitCodeSpec].
class CardCodeReader {
  /// Creates a reader. Every key of [specs] must be a zone of [layout];
  /// zones without a spec are not read.
  CardCodeReader({
    required this.recognizer,
    required this.layout,
    required Map<String, DigitCodeSpec> specs,
    this.options = const PrepareOptions(),
    this.policy = const ReviewPolicy(),
    this.useIsolate = true,
  }) : specs = Map.unmodifiable(specs) {
    for (final name in specs.keys) {
      if (!layout.zones.containsKey(name)) {
        throw ArgumentError.value(name, 'specs', 'not a zone of the layout');
      }
    }
  }

  /// OCR engine.
  final TextRecognizerPort recognizer;

  /// Zones on the card.
  final ZoneLayout layout;

  /// Code spec per zone name.
  final Map<String, DigitCodeSpec> specs;

  /// Image preparation settings.
  final PrepareOptions options;

  /// Review thresholds.
  final ReviewPolicy policy;

  /// Prepare images on a background isolate.
  final bool useIsolate;

  /// Reads every zone that has a spec from the encoded photo [bytes].
  ///
  /// [cardRegion] is where the card sits in the photo (see
  /// `CardScanGeometry.cardRegionInImage` for a camera overlay).
  Future<CardReadResult> read(
    Uint8List bytes, {
    NormRect cardRegion = NormRect.full,
  }) async {
    final only = specs.keys.toSet();
    final card = useIsolate
        ? await prepareInIsolate(
            bytes,
            layout,
            cardRegion: cardRegion,
            options: options,
            only: only,
          )
        : prepareCard(
            bytes,
            layout,
            cardRegion: cardRegion,
            options: options,
            only: only,
          );
    final results = <String, CodeReadResult>{};
    for (final zone in card.zones.values) {
      final text = await recognizer.recognize(zone);
      results[zone.name] = CodeExtractor(
        specs[zone.name]!,
        policy: policy,
      ).read(text);
    }
    return CardReadResult(
      zones: results,
      imageWidth: card.width,
      imageHeight: card.height,
    );
  }

  /// Closes the recognizer.
  Future<void> close() => recognizer.close();
}
