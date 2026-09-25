import 'checksum.dart';

/// Describes the code to look for: length(s), printed grouping, prefix,
/// check digit and alphabet.
class DigitCodeSpec {
  /// Creates a spec.
  ///
  /// Give [lengths], [groups] or both. With only [groups], the length is
  /// their sum. With both, the grouping sum must be one of the lengths.
  factory DigitCodeSpec({
    Set<int>? lengths,
    List<int>? groups,
    String? prefix,
    ChecksumValidator? checksum,
    String allowedCharacters = digits,
  }) {
    final groupSum = groups?.fold<int>(0, (a, b) => a + b);
    if (groups != null && groups.any((g) => g <= 0)) {
      throw ArgumentError.value(groups, 'groups', 'must be positive');
    }
    final resolved = lengths ?? (groupSum == null ? null : {groupSum});
    if (resolved == null || resolved.isEmpty) {
      throw ArgumentError('Give lengths or groups');
    }
    if (resolved.any((l) => l <= 0)) {
      throw ArgumentError.value(lengths, 'lengths', 'must be positive');
    }
    if (groupSum != null && !resolved.contains(groupSum)) {
      throw ArgumentError(
        'Grouping $groups sums to $groupSum, not one of $resolved',
      );
    }
    if (allowedCharacters.isEmpty) {
      throw ArgumentError.value(allowedCharacters, 'allowedCharacters');
    }
    return DigitCodeSpec._(
      Set.unmodifiable(resolved),
      groups == null ? null : List.unmodifiable(groups),
      prefix,
      checksum,
      allowedCharacters,
    );
  }

  const DigitCodeSpec._(
    this.lengths,
    this.groups,
    this.prefix,
    this.checksum,
    this.allowedCharacters,
  );

  /// A 15-digit IMEI with its Luhn check digit (3GPP TS 23.003).
  factory DigitCodeSpec.imei() =>
      DigitCodeSpec(lengths: const {15}, checksum: const LuhnChecksum());

  /// The ten decimal digits.
  static const String digits = '0123456789';

  /// Accepted code lengths.
  final Set<int> lengths;

  /// Printed grouping, for example `[4, 4, 4, 2]`, or null when unknown.
  final List<int>? groups;

  /// Required leading characters, or null.
  final String? prefix;

  /// Check-digit validator, or null.
  final ChecksumValidator? checksum;

  /// Characters a code may contain. Look-alike letters outside this set are
  /// rewritten to digits; letters inside it are kept.
  final String allowedCharacters;

  /// Shortest accepted length.
  int get minLength => lengths.reduce((a, b) => a < b ? a : b);

  /// Longest accepted length.
  int get maxLength => lengths.reduce((a, b) => a > b ? a : b);

  /// Whether [length] is accepted.
  bool acceptsLength(int length) => lengths.contains(length);

  /// Whether [code] starts with [prefix] (true when there is none).
  bool hasPrefix(String code) => prefix == null || code.startsWith(prefix!);

  /// Check-digit result for [code], or null when there is no validator.
  bool? checksumValid(String code) => checksum?.isValid(code);

  /// Whether every character of [code] is allowed.
  bool usesOnlyAllowed(String code) {
    for (final c in code.split('')) {
      if (!allowedCharacters.contains(c)) return false;
    }
    return true;
  }

  /// Whether [code] satisfies length, alphabet, prefix and checksum.
  bool matches(String code) =>
      acceptsLength(code.length) &&
      usesOnlyAllowed(code) &&
      hasPrefix(code) &&
      (checksumValid(code) ?? true);

  /// Formats [code] with [groups], or returns it unchanged when there is no
  /// grouping or the length does not fit.
  String format(String code, {String separator = ' '}) {
    final g = groups;
    if (g == null || code.length != g.fold<int>(0, (a, b) => a + b)) {
      return code;
    }
    final parts = <String>[];
    var i = 0;
    for (final n in g) {
      parts.add(code.substring(i, i + n));
      i += n;
    }
    return parts.join(separator);
  }
}
