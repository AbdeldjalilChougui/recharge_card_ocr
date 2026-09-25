import 'dart:typed_data';

/// An integer pixel rectangle.
class PixelRect {
  /// Creates a rectangle.
  const PixelRect(this.x, this.y, this.width, this.height);

  /// Left edge.
  final int x;

  /// Top edge.
  final int y;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  @override
  String toString() => 'PixelRect($x, $y, $width, $height)';
}

/// One zone cut from the photo and made ready for OCR.
class PreparedZone {
  /// Creates a prepared zone.
  const PreparedZone({
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
    required this.sourceRect,
    required this.scale,
  });

  /// Zone name from the layout.
  final String name;

  /// PNG-encoded image.
  final Uint8List bytes;

  /// Width of [bytes] in pixels.
  final int width;

  /// Height of [bytes] in pixels.
  final int height;

  /// Where the zone was cut from, in the orientation-corrected photo.
  final PixelRect sourceRect;

  /// Upscale factor applied after cropping (1 when none).
  final double scale;
}

/// A photo turned into OCR-ready zones.
class PreparedCard {
  /// Creates a prepared card.
  const PreparedCard({
    required this.width,
    required this.height,
    required this.zones,
  });

  /// Photo width after orientation correction.
  final int width;

  /// Photo height after orientation correction.
  final int height;

  /// Prepared zones keyed by name.
  final Map<String, PreparedZone> zones;
}

/// How zones are prepared for OCR.
class PrepareOptions {
  /// Creates options.
  const PrepareOptions({
    this.minShortSide = 96,
    this.maxUpscale = 4,
    this.grayscale = true,
    this.contrastStretch = true,
    this.lowPercentile = 0.01,
    this.highPercentile = 0.99,
  });

  /// Crops whose shorter side is below this many pixels are upscaled to it.
  /// 0 disables upscaling. The default is a heuristic, not a measured
  /// optimum: ML Kit asks for Latin characters of at least 16x16 pixels, and
  /// a code line crop includes margins around the characters.
  final int minShortSide;

  /// Largest upscale factor.
  final double maxUpscale;

  /// Convert crops to grayscale.
  final bool grayscale;

  /// Stretch luminance so [lowPercentile]..[highPercentile] spans 0..255.
  final bool contrastStretch;

  /// Lower percentile for [contrastStretch], in `0..1`.
  final double lowPercentile;

  /// Upper percentile for [contrastStretch], in `0..1`.
  final double highPercentile;
}
