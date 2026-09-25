import 'geometry.dart';

/// Named regions on a card, in coordinates normalised to the card itself.
class ZoneLayout {
  /// Creates a layout.
  const ZoneLayout({required this.cardAspectRatio, required this.zones});

  /// Card width divided by card height.
  final double cardAspectRatio;

  /// Zone rectangles keyed by name, relative to the card.
  final Map<String, NormRect> zones;

  /// A layout for landscape scratch cards with the code line above a
  /// serial/barcode block, tuned on cards used in production apps. Measure
  /// your own cards and pass a custom layout when they differ.
  static const ZoneLayout rechargeCard = ZoneLayout(
    cardAspectRatio: 1.7,
    zones: {
      'code': NormRect(0.08, 0.28, 0.92, 0.46),
      'serial': NormRect(0.05, 0.50, 0.95, 0.86),
    },
  );

  /// Maps every zone into the coordinate space of [cardRegion], the card's
  /// position inside a photo (normalised to the photo).
  Map<String, NormRect> resolve(NormRect cardRegion) => {
    for (final e in zones.entries) e.key: e.value.within(cardRegion),
  };
}
