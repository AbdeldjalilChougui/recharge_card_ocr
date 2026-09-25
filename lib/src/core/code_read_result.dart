import 'code_candidate.dart';

/// Why a read result needs a human to check it.
enum ReviewReason {
  /// No code-like text was found.
  noCandidate,

  /// The best code does not have an accepted length or prefix.
  specMismatch,

  /// The best code fails its check digit.
  checksumFailed,

  /// The best code's confidence is under the threshold.
  lowConfidence,

  /// Another valid code scored almost as well as the best one.
  ambiguous,
}

/// Thresholds that decide when a read needs review.
class ReviewPolicy {
  /// Creates a policy.
  const ReviewPolicy({
    this.minConfidence = 0.7,
    this.ambiguityMargin = 0.1,
    this.assumedConfidence = 1.0,
  });

  /// Codes below this confidence need review.
  final double minConfidence;

  /// A second valid code whose score is within this margin of the best one
  /// makes the read ambiguous.
  final double ambiguityMargin;

  /// Confidence used for words when the OCR engine reports none.
  final double assumedConfidence;
}

/// The outcome of reading one zone.
class CodeReadResult {
  /// Creates a result.
  const CodeReadResult({
    required this.best,
    required this.alternatives,
    required this.reasons,
    this.formatted,
  });

  /// The highest-ranked candidate, or null when nothing was found.
  final CodeCandidate? best;

  /// Other candidates, best first.
  final List<CodeCandidate> alternatives;

  /// Why the result needs review; empty when it can be trusted.
  final Set<ReviewReason> reasons;

  /// The best code formatted with the spec grouping, or null.
  final String? formatted;

  /// The best code, or null.
  String? get code => best?.code;

  /// Confidence of the best code, 0 when there is none.
  double get confidence => best?.confidence ?? 0;

  /// Whether a human should confirm or correct the code.
  bool get needsReview => reasons.isNotEmpty;
}
