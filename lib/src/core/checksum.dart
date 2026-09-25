/// Decides whether a code's check digit is correct.
abstract class ChecksumValidator {
  /// Const constructor for subclasses.
  const ChecksumValidator();

  /// Short name, used in logs and debugging output.
  String get name;

  /// Whether [code] carries a valid check digit.
  bool isValid(String code);
}

bool _allDigits(String s) {
  if (s.isEmpty) return false;
  for (final c in s.codeUnits) {
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

/// The Luhn (mod-10, "double every second digit") check, as used by IMEI
/// numbers (3GPP TS 23.003) and payment card numbers (ISO/IEC 7812-1).
class LuhnChecksum extends ChecksumValidator {
  /// Creates the validator.
  const LuhnChecksum();

  @override
  String get name => 'luhn';

  @override
  bool isValid(String code) {
    if (code.length < 2 || !_allDigits(code)) return false;
    return _sum(code, checkIncluded: true) % 10 == 0;
  }

  /// The Luhn check digit to append to [payload].
  int checkDigit(String payload) {
    if (!_allDigits(payload)) {
      throw ArgumentError.value(payload, 'payload', 'digits only');
    }
    return (10 - _sum(payload, checkIncluded: false) % 10) % 10;
  }

  static int _sum(String s, {required bool checkIncluded}) {
    var total = 0;
    var doubleIt = !checkIncluded;
    for (var i = s.length - 1; i >= 0; i--) {
      var d = s.codeUnitAt(i) - 0x30;
      if (doubleIt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      total += d;
      doubleIt = !doubleIt;
    }
    return total;
  }
}

/// A weighted mod-10 check: digits are multiplied by [weights], cycled from
/// the rightmost digit (the check digit takes the first weight), and the sum
/// must be a multiple of 10.
class WeightedMod10Checksum extends ChecksumValidator {
  /// Creates a validator with custom [weights].
  const WeightedMod10Checksum({required this.weights});

  /// The GS1 check used by EAN-8, EAN-13, UPC-A and GTIN codes: weights 1
  /// and 3 alternating from the check digit.
  const WeightedMod10Checksum.gs1() : weights = const [1, 3];

  /// Weights applied from the right, cycled.
  final List<int> weights;

  @override
  String get name => 'mod10${weights.join()}';

  @override
  bool isValid(String code) {
    if (weights.isEmpty) throw ArgumentError('weights must not be empty');
    if (code.length < 2 || !_allDigits(code)) return false;
    var total = 0;
    for (var i = 0; i < code.length; i++) {
      final d = code.codeUnitAt(code.length - 1 - i) - 0x30;
      total += d * weights[i % weights.length];
    }
    return total % 10 == 0;
  }
}

/// A checksum defined by a callback, for issuer-specific schemes.
class CustomChecksum extends ChecksumValidator {
  /// Wraps [test] as a validator.
  const CustomChecksum(this._test, {this.name = 'custom'});

  final bool Function(String code) _test;

  @override
  final String name;

  @override
  bool isValid(String code) => _test(code);
}
