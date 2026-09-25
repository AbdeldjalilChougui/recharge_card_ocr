import 'dart:math' as math;
import 'dart:ui';

import '../core/geometry.dart';
import '../core/zone_layout.dart';

/// Where the card frame and its zones sit on a camera preview, and how that
/// maps back to the captured photo.
class CardScanGeometry {
  /// Creates the geometry for [layout].
  const CardScanGeometry({
    required this.layout,
    this.cardWidthFraction = 0.88,
    this.maxCardHeightFraction = 0.8,
  });

  /// Card aspect ratio and zones.
  final ZoneLayout layout;

  /// Card frame width as a fraction of the preview width.
  final double cardWidthFraction;

  /// The frame is shrunk, keeping its aspect ratio, so that its height stays
  /// within this fraction of the preview height.
  final double maxCardHeightFraction;

  /// The card frame in preview pixels, centred.
  Rect cardFrame(Size size) {
    var w = size.width * cardWidthFraction;
    var h = w / layout.cardAspectRatio;
    final maxH = size.height * maxCardHeightFraction;
    if (h > maxH) {
      h = maxH;
      w = h * layout.cardAspectRatio;
    }
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  /// Zone [name] in preview pixels.
  Rect zoneRect(Size size, String name) {
    final z = layout.zones[name];
    if (z == null) throw ArgumentError.value(name, 'name', 'unknown zone');
    return _inFrame(cardFrame(size), z);
  }

  /// All zones in preview pixels, in layout order.
  Map<String, Rect> zoneRects(Size size) {
    final f = cardFrame(size);
    return {for (final e in layout.zones.entries) e.key: _inFrame(f, e.value)};
  }

  /// The card frame normalised to the preview.
  NormRect cardRegionInPreview(Size size) {
    final f = cardFrame(size);
    return NormRect(
      (f.left / size.width).clamp(0.0, 1.0),
      (f.top / size.height).clamp(0.0, 1.0),
      (f.right / size.width).clamp(0.0, 1.0),
      (f.bottom / size.height).clamp(0.0, 1.0),
    );
  }

  /// The card frame normalised to the captured photo, for a preview of
  /// [previewSize] showing a camera image of [cameraAspect] (width/height,
  /// in the same orientation as the preview) in `BoxFit.cover` mode.
  NormRect cardRegionInImage({
    required Size previewSize,
    required double cameraAspect,
  }) => previewToImage(
    cardRegionInPreview(previewSize),
    previewAspect: previewSize.width / previewSize.height,
    cameraAspect: cameraAspect,
  );

  /// Maps a preview-normalised rectangle to image-normalised coordinates,
  /// accounting for the part of the camera image a `BoxFit.cover` preview
  /// cuts off.
  static NormRect previewToImage(
    NormRect r, {
    required double previewAspect,
    required double cameraAspect,
  }) {
    double visW = 1, visH = 1, offL = 0, offT = 0;
    if (cameraAspect > previewAspect) {
      visW = previewAspect / cameraAspect;
      offL = (1 - visW) / 2;
    } else {
      visH = cameraAspect / previewAspect;
      offT = (1 - visH) / 2;
    }
    double c(double v) => v.clamp(0.0, 1.0);
    return NormRect(
      c(offL + r.left * visW),
      c(offT + r.top * visH),
      c(offL + r.right * visW),
      c(offT + r.bottom * visH),
    );
  }

  /// Top-left corner for a label of [labelSize] naming [zone]: just above
  /// the zone (below it when there is no room), aligned to the zone's start
  /// edge, which is the right edge for [TextDirection.rtl].
  static Offset labelOffset({
    required Rect zone,
    required Size labelSize,
    required TextDirection textDirection,
    double gap = 4,
    double inset = 4,
  }) {
    final x = textDirection == TextDirection.rtl
        ? zone.right - inset - labelSize.width
        : zone.left + inset;
    final above = zone.top - gap - labelSize.height;
    final y = above >= 0 ? above : zone.bottom + gap;
    return Offset(math.max(x, zone.left), y);
  }

  static Rect _inFrame(Rect f, NormRect z) => Rect.fromLTRB(
    f.left + z.left * f.width,
    f.top + z.top * f.height,
    f.left + z.right * f.width,
    f.top + z.bottom * f.height,
  );
}
