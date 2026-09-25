import 'package:flutter_test/flutter_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

void main() {
  group('LuhnChecksum', () {
    const luhn = LuhnChecksum();

    test('accepts the classic Luhn example and a valid IMEI', () {
      expect(luhn.isValid('79927398713'), isTrue);
      // Widely cited IMEI example; its Luhn check digit is 8.
      expect(luhn.isValid('490154203237518'), isTrue);
    });

    test('rejects a wrong check digit', () {
      expect(luhn.isValid('79927398710'), isFalse);
      expect(luhn.isValid('490154203237517'), isFalse);
    });

    test('rejects empty and non-digit input', () {
      expect(luhn.isValid(''), isFalse);
      expect(luhn.isValid('4901A4203237518'), isFalse);
    });

    test('computes the check digit', () {
      expect(luhn.checkDigit('49015420323751'), 8);
      expect(luhn.checkDigit('7992739871'), 3);
    });
  });

  group('WeightedMod10Checksum', () {
    const gs1 = WeightedMod10Checksum.gs1();

    test('accepts a valid EAN-13', () {
      expect(gs1.isValid('4006381333931'), isTrue);
    });

    test('accepts a valid UPC-A', () {
      expect(gs1.isValid('036000291452'), isTrue);
    });

    test('rejects a wrong check digit', () {
      expect(gs1.isValid('4006381333932'), isFalse);
    });

    test('custom weights are applied from the right', () {
      // Weights 1,1: the check digit makes the plain digit sum a multiple of 10.
      const plain = WeightedMod10Checksum(weights: [1]);
      expect(plain.isValid('1234'), isTrue); // 1+2+3 = 6, 6+4 = 10
      expect(plain.isValid('1235'), isFalse);
    });

    test('rejects an empty weight list', () {
      expect(
        () => const WeightedMod10Checksum(weights: []).isValid('12'),
        throwsArgumentError,
      );
    });
  });

  group('CustomChecksum', () {
    test('delegates to the callback', () {
      final even = CustomChecksum((code) => code.endsWith('0'), name: 'ends0');
      expect(even.isValid('120'), isTrue);
      expect(even.isValid('121'), isFalse);
      expect(even.name, 'ends0');
    });
  });
}
