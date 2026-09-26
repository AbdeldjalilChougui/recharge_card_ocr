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
  ///
  /// The code zone reaches past the scratch panel (the panel sat at about
  /// 0.29..0.45 of the height) so a card held a few degrees off, or framed
  /// a little off-centre, does not lose its first or last digits. Text that
  /// the wider zone picks up is filtered out by the `DigitCodeSpec`. The
  /// serial zone has the same kind of margin.
  static const ZoneLayout rechargeCard = ZoneLayout(
    cardAspectRatio: 1.7,
    zones: {
      'code': NormRect(0.02, 0.22, 0.98, 0.52),
      'serial': NormRect(0.01, 0.47, 0.99, 0.90),
    },
  );

  /// Maps every zone into the coordinate space of [cardRegion], the card's
  /// position inside a photo (normalised to the photo).
  Map<String, NormRect> resolve(NormRect cardRegion) => {
    for (final e in zones.entries) e.key: e.value.within(cardRegion),
  };
}
