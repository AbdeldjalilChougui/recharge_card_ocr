/// A rectangle in normalised coordinates, each edge in `0..1` of a
/// reference size (a card, a photo or a screen).
class NormRect {
  /// Creates a rectangle from its edges. Edges must satisfy
  /// `0 <= left <= right <= 1` and `0 <= top <= bottom <= 1`; this is only
  /// asserted, so use [NormRect.fromLTRB] for untrusted input.
  const NormRect(this.left, this.top, this.right, this.bottom)
    : assert(left >= 0 && right <= 1 && left <= right),
      assert(top >= 0 && bottom <= 1 && top <= bottom);

  /// Creates a rectangle from its edges and throws [ArgumentError] when they
  /// fall outside `0..1` or are inverted.
  factory NormRect.fromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    if (left < 0 || top < 0 || right > 1 || bottom > 1) {
      throw ArgumentError('NormRect edges must lie in 0..1');
    }
    if (left > right || top > bottom) {
      throw ArgumentError('NormRect edges are inverted');
    }
    return NormRect(left, top, right, bottom);
  }

  /// The whole reference area.
  static const NormRect full = NormRect(0, 0, 1, 1);

  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Right edge.
  final double right;

  /// Bottom edge.
  final double bottom;

  /// Width as a fraction of the reference width.
  double get width => right - left;

  /// Height as a fraction of the reference height.
  double get height => bottom - top;

  /// Maps this rectangle, taken as relative to [outer], into the coordinate
  /// space that [outer] itself is expressed in.
  NormRect within(NormRect outer) => NormRect(
    outer.left + left * outer.width,
    outer.top + top * outer.height,
    outer.left + right * outer.width,
    outer.top + bottom * outer.height,
  );

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'NormRect($left, $top, $right, $bottom)';
}

/// An axis-aligned box in the pixel coordinates of an OCR input image.
class OcrBox {
  /// Creates a box from its edges.
  const OcrBox(this.left, this.top, this.right, this.bottom);

  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Right edge.
  final double right;

  /// Bottom edge.
  final double bottom;

  /// Width in pixels.
  double get width => right - left;

  /// Height in pixels.
  double get height => bottom - top;

  /// Horizontal centre.
  double get centerX => (left + right) / 2;

  /// Vertical centre.
  double get centerY => (top + bottom) / 2;

  /// Whether the point lies inside or on the edge of this box.
  bool containsPoint(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  /// The smallest box containing both this box and [other].
  OcrBox union(OcrBox other) => OcrBox(
    left < other.left ? left : other.left,
    top < other.top ? top : other.top,
    right > other.right ? right : other.right,
    bottom > other.bottom ? bottom : other.bottom,
  );

  @override
  bool operator ==(Object other) =>
      other is OcrBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'OcrBox($left, $top, $right, $bottom)';
}
