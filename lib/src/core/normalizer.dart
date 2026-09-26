/// A token after look-alike correction and separator removal.
class NormalizedToken {
  /// Creates a token.
  const NormalizedToken({
    required this.value,
    required this.substitutions,
    required this.groups,
  });

  /// Cleaned characters.
  final String value;

  /// How many look-alike letters were rewritten.
  final int substitutions;

  /// Lengths of the dash-separated parts of the token (one entry when it had
  /// no dash).
  final List<int> groups;
}

/// Rewrites common OCR confusions to digits, only inside digit context.
///
/// A token is in digit context when every character is an allowed
/// character, a known look-alike or a separator, and allowed characters are
/// at least as many as look-alikes. So `9O12` becomes `9012` while `BOSS` or
/// `PRICE` are left out.
class DigitNormalizer {
  /// Creates a normaliser with the given look-alike table.
  const DigitNormalizer({this.confusions = defaultConfusions});

  /// O/D/Q→0, I/l/|→1, S→5, B→8, Z→2 and their lower-case forms where OCR
  /// commonly produces them. D and Q were added after ML Kit read a
  /// partly scratched 0 as them in the benchmark (`example/tool/benchmark`).
  static const Map<String, String> defaultConfusions = {
    'O': '0',
    'o': '0',
    'D': '0',
    'Q': '0',
    'I': '1',
    'l': '1',
    '|': '1',
    'S': '5',
    's': '5',
    'B': '8',
    'Z': '2',
    'z': '2',
  };

  /// Look-alike letter to digit table.
  final Map<String, String> confusions;

  static const _separators = {'-', ' ', '‐', '‑', '–'};
  static const _edgePunctuation = ':;,.#*';

  /// Cleans one OCR word, or returns null when it is not in digit context.
  ///
  /// [allowed] is the code alphabet; look-alikes that are themselves allowed
  /// are kept, and a look-alike is only rewritten when its digit is allowed.
  NormalizedToken? normalizeToken(String token, {required String allowed}) {
    var s = token.trim();
    while (s.isNotEmpty && _edgePunctuation.contains(s[0])) {
      s = s.substring(1);
    }
    while (s.isNotEmpty && _edgePunctuation.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;

    final out = StringBuffer();
    final groups = <int>[];
    var run = 0;
    var real = 0;
    var subs = 0;
    for (final ch in s.split('')) {
      if (_separators.contains(ch)) {
        if (run > 0) groups.add(run);
        run = 0;
        continue;
      }
      if (allowed.contains(ch)) {
        out.write(ch);
        real++;
        run++;
        continue;
      }
      final mapped = confusions[ch];
      if (mapped != null && allowed.contains(mapped)) {
        out.write(mapped);
        subs++;
        run++;
        continue;
      }
      return null;
    }
    if (run > 0) groups.add(run);
    if (out.isEmpty || real == 0 || real < subs) return null;
    return NormalizedToken(
      value: out.toString(),
      substitutions: subs,
      groups: groups,
    );
  }
}
