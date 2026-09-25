import 'geometry.dart';

/// One possible code found in OCR text, with the evidence used to rank it.
class CodeCandidate {
  /// Creates a candidate.
  const CodeCandidate({
    required this.code,
    required this.rawText,
    required this.confidence,
    required this.score,
    required this.lengthMatched,
    required this.groupingMatched,
    required this.prefixMatched,
    required this.checksumValid,
    required this.substitutions,
    required this.joinedLines,
    required this.box,
  });

  /// Cleaned code (look-alikes rewritten, spaces and dashes removed).
  final String code;

  /// The OCR words the code was built from, space-separated.
  final String rawText;

  /// Mean word confidence, lowered for every rewritten look-alike and for
  /// joining lines. In `0..1`.
  final double confidence;

  /// Ranking score in `0..1` combining spec match, [confidence] and position
  /// inside the zone.
  final double score;

  /// Whether the length is one the spec accepts.
  final bool lengthMatched;

  /// Whether the printed grouping equals the spec grouping.
  final bool groupingMatched;

  /// Whether the spec prefix is present (true when the spec has none).
  final bool prefixMatched;

  /// Check-digit result, or null when the spec has no checksum.
  final bool? checksumValid;

  /// Number of look-alike letters rewritten to digits.
  final int substitutions;

  /// Whether the code was assembled from two OCR lines.
  final bool joinedLines;

  /// Bounding box of the words used, in OCR input pixels.
  final OcrBox box;

  /// Whether length, prefix and checksum all pass.
  bool get specMatched =>
      lengthMatched && prefixMatched && (checksumValid ?? true);

  @override
  String toString() =>
      'CodeCandidate($code, score: ${score.toStringAsFixed(3)}, '
      'confidence: ${confidence.toStringAsFixed(3)})';
}
