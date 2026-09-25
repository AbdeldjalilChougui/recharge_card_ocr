import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/geometry.dart';
import '../core/zone_layout.dart';
import 'prepared.dart';

/// Converts a normalised rectangle to pixels of a `width` x `height` image,
/// clamped so the result is inside the image and at least 1x1.
PixelRect pixelRectFor(NormRect r, int width, int height) {
  final x = (r.left * width).round().clamp(0, width - 1);
  final y = (r.top * height).round().clamp(0, height - 1);
  final w = (r.width * width).round().clamp(1, width - x);
  final h = (r.height * height).round().clamp(1, height - y);
  return PixelRect(x, y, w, h);
}

/// Decodes [bytes], applies the EXIF orientation, crops every zone of
/// [layout] and prepares each crop for OCR.
///
/// [cardRegion] is where the card sits in the photo, normalised to the
/// orientation-corrected photo; the default assumes the photo is the card.
/// [only] limits the work to some zone names. Throws [FormatException] when
/// the bytes are not a supported image.
PreparedCard prepareCard(
  Uint8List bytes,
  ZoneLayout layout, {
  NormRect cardRegion = NormRect.full,
  PrepareOptions options = const PrepareOptions(),
  Set<String>? only,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (e) {
    // Some decoders throw (for example RangeError) on truncated input
    // instead of returning null.
    throw FormatException('Unsupported or corrupt image: $e');
  }
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image');
  }
  final photo = img.bakeOrientation(decoded);
  final zones = <String, PreparedZone>{};
  for (final e in layout.resolve(cardRegion).entries) {
    if (only != null && !only.contains(e.key)) continue;
    zones[e.key] = _prepareZone(e.key, photo, e.value, options);
  }
  return PreparedCard(width: photo.width, height: photo.height, zones: zones);
}

/// Runs [prepareCard] on a background isolate so decoding and resizing do
/// not block the UI thread.
Future<PreparedCard> prepareInIsolate(
  Uint8List bytes,
  ZoneLayout layout, {
  NormRect cardRegion = NormRect.full,
  PrepareOptions options = const PrepareOptions(),
  Set<String>? only,
}) {
  return Isolate.run(
    () => prepareCard(
      bytes,
      layout,
      cardRegion: cardRegion,
      options: options,
      only: only,
    ),
  );
}

PreparedZone _prepareZone(
  String name,
  img.Image photo,
  NormRect zone,
  PrepareOptions o,
) {
  final rect = pixelRectFor(zone, photo.width, photo.height);
  var crop = img.copyCrop(
    photo,
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height,
  );
  if (o.grayscale) crop = img.grayscale(crop);
  if (o.contrastStretch) {
    crop = stretchContrast(
      crop,
      lowPercentile: o.lowPercentile,
      highPercentile: o.highPercentile,
    );
  }
  var scale = 1.0;
  final shortSide = math.min(crop.width, crop.height);
  if (o.minShortSide > 0 && shortSide < o.minShortSide) {
    scale = math.min(o.maxUpscale, o.minShortSide / shortSide);
    if (scale > 1) {
      crop = img.copyResize(
        crop,
        width: (crop.width * scale).round(),
        height: (crop.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    } else {
      scale = 1;
    }
  }
  return PreparedZone(
    name: name,
    bytes: img.encodePng(crop),
    width: crop.width,
    height: crop.height,
    sourceRect: rect,
    scale: scale,
  );
}

/// Linearly stretches [image] so that the luminance at [lowPercentile] maps
/// to 0 and the one at [highPercentile] maps to 255, applying the same map
/// to every colour channel. A flat image is returned unchanged (as a copy).
img.Image stretchContrast(
  img.Image image, {
  double lowPercentile = 0.01,
  double highPercentile = 0.99,
}) {
  final out = image.clone();
  final histogram = List<int>.filled(256, 0);
  var n = 0;
  for (final p in out) {
    final l = img.getLuminanceRgb(p.r, p.g, p.b).round().clamp(0, 255);
    histogram[l]++;
    n++;
  }
  if (n == 0) return out;
  int valueAt(double q) {
    final target = (q.clamp(0.0, 1.0) * (n - 1)).round();
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += histogram[v];
      if (seen > target) return v;
    }
    return 255;
  }

  final lo = valueAt(lowPercentile);
  final hi = valueAt(highPercentile);
  if (hi <= lo) return out;
  final k = 255 / (hi - lo);
  num map(num c) => ((c - lo) * k).round().clamp(0, 255);
  for (final p in out) {
    p
      ..r = map(p.r)
      ..g = map(p.g)
      ..b = map(p.b);
  }
  return out;
}
