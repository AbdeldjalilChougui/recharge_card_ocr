import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/zone_layout.dart';
import 'card_scan_geometry.dart';

/// A camera-preview overlay that dims everything outside the card frame and
/// outlines each zone of a [ZoneLayout], with optional labels.
///
/// It draws only; it does not depend on any camera package. Stack it over
/// your preview and use [CardScanGeometry.cardRegionInImage] with the same
/// settings to know where the card is in the captured photo.
class CardScanOverlay extends StatelessWidget {
  /// Creates an overlay.
  const CardScanOverlay({
    super.key,
    required this.layout,
    this.labels = const {},
    this.textDirection,
    this.cardWidthFraction = 0.88,
    this.maxCardHeightFraction = 0.8,
    this.frameColor = const Color(0xFFFFFFFF),
    this.zoneColor = const Color(0xFF4DD0E1),
    this.maskColor = const Color(0x73000000),
    this.labelStyle,
  });

  /// Card aspect ratio and zones.
  final ZoneLayout layout;

  /// Label per zone name; zones without an entry are drawn unlabelled.
  final Map<String, String> labels;

  /// Direction for labels; defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  /// See [CardScanGeometry.cardWidthFraction].
  final double cardWidthFraction;

  /// See [CardScanGeometry.maxCardHeightFraction].
  final double maxCardHeightFraction;

  /// Card frame outline colour.
  final Color frameColor;

  /// Zone outline and label background colour.
  final Color zoneColor;

  /// Colour of the dimmed area outside the card.
  final Color maskColor;

  /// Label text style, merged over the default white bold 12 px.
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final dir =
        textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;
    return CustomPaint(
      size: Size.infinite,
      painter: CardScanPainter(
        geometry: CardScanGeometry(
          layout: layout,
          cardWidthFraction: cardWidthFraction,
          maxCardHeightFraction: maxCardHeightFraction,
        ),
        labels: labels,
        textDirection: dir,
        frameColor: frameColor,
        zoneColor: zoneColor,
        maskColor: maskColor,
        labelStyle: labelStyle,
      ),
    );
  }
}

/// Paints a [CardScanOverlay]. Public so it can be reused in other
/// [CustomPaint]s and inspected in tests.
class CardScanPainter extends CustomPainter {
  /// Creates a painter.
  CardScanPainter({
    required this.geometry,
    required this.labels,
    required this.textDirection,
    this.frameColor = const Color(0xFFFFFFFF),
    this.zoneColor = const Color(0xFF4DD0E1),
    this.maskColor = const Color(0x73000000),
    this.labelStyle,
  });

  /// Frame and zone geometry.
  final CardScanGeometry geometry;

  /// Label per zone name.
  final Map<String, String> labels;

  /// Direction used to lay out and align labels.
  final TextDirection textDirection;

  /// Card frame outline colour.
  final Color frameColor;

  /// Zone outline and label background colour.
  final Color zoneColor;

  /// Colour of the dimmed area outside the card.
  final Color maskColor;

  /// Label text style override.
  final TextStyle? labelStyle;

  static const _frameRadius = Radius.circular(14);
  static const _zoneRadius = Radius.circular(6);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = geometry.cardFrame(size);
    final frameRRect = RRect.fromRectAndRadius(frame, _frameRadius);
    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addRRect(frameRRect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = maskColor,
    );
    canvas.drawRRect(
      frameRRect,
      Paint()
        ..color = frameColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final e in geometry.zoneRects(size).entries) {
      _zone(canvas, e.value, labels[e.key]);
    }
  }

  void _zone(Canvas canvas, Rect rect, String? label) {
    final rrect = RRect.fromRectAndRadius(rect, _zoneRadius);
    canvas.drawRRect(rrect, Paint()..color = zoneColor.withValues(alpha: 0.18));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = zoneColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (label == null || label.isEmpty) return;
    final style = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      backgroundColor: zoneColor.withValues(alpha: 0.9),
    ).merge(labelStyle);
    final tp = TextPainter(
      text: TextSpan(text: ' $label ', style: style),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    tp.paint(
      canvas,
      CardScanGeometry.labelOffset(
        zone: rect,
        labelSize: tp.size,
        textDirection: textDirection,
      ),
    );
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant CardScanPainter old) =>
      old.geometry.layout != geometry.layout ||
      old.geometry.cardWidthFraction != geometry.cardWidthFraction ||
      old.geometry.maxCardHeightFraction != geometry.maxCardHeightFraction ||
      !mapEquals(old.labels, labels) ||
      old.textDirection != textDirection ||
      old.frameColor != frameColor ||
      old.zoneColor != zoneColor ||
      old.maskColor != maskColor ||
      old.labelStyle != labelStyle;
}
