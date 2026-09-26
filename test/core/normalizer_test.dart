import 'package:flutter_test/flutter_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

void main() {
  const n = DigitNormalizer();
  const digits = '0123456789';

  group('DigitNormalizer.normalizeToken', () {
    test('passes clean digits through', () {
      final t = n.normalizeToken('1234', allowed: digits)!;
      expect(t.value, '1234');
      expect(t.substitutions, 0);
    });

    test('maps O->0, I/l->1, S->5, B->8, Z->2 in digit context', () {
      expect(n.normalizeToken('9O12', allowed: digits)!.value, '9012');
      expect(n.normalizeToken('l234', allowed: digits)!.value, '1234');
      expect(n.normalizeToken('I234', allowed: digits)!.value, '1234');
      expect(n.normalizeToken('S0B2', allowed: digits)!.value, '5082');
      expect(n.normalizeToken('12Z4', allowed: digits)!.value, '1224');
      expect(n.normalizeToken('o0|1', allowed: digits)!.value, '0011');
    });

    test('maps D->0 and Q->0 in digit context', () {
      // Seen in ML Kit output on scratch-panel residue: "6Q71", "D199".
      expect(n.normalizeToken('6Q71', allowed: digits)!.value, '6071');
      expect(n.normalizeToken('D199', allowed: digits)!.value, '0199');
      expect(n.normalizeToken('D199', allowed: digits)!.substitutions, 1);
    });

    test('D and Q do not turn words into numbers', () {
      expect(n.normalizeToken('DA', allowed: digits), isNull);
      expect(n.normalizeToken('500DA', allowed: digits), isNull);
      expect(n.normalizeToken('DQ', allowed: digits), isNull);
    });

    test('counts substitutions', () {
      expect(n.normalizeToken('9O1I', allowed: digits)!.substitutions, 2);
    });

    test('removes spaces and dashes inside a token', () {
      final t = n.normalizeToken('1234-5678', allowed: digits)!;
      expect(t.value, '12345678');
      expect(t.substitutions, 0);
    });

    test('leaves words alone (no digit context)', () {
      expect(n.normalizeToken('PRICE', allowed: digits), isNull);
      expect(n.normalizeToken('BOSS', allowed: digits), isNull);
      expect(n.normalizeToken('IO', allowed: digits), isNull);
      expect(n.normalizeToken('Serial:', allowed: digits), isNull);
    });

    test('rejects tokens that are mostly confusable letters', () {
      // 1 real digit against 3 look-alikes is a word, not a number.
      expect(n.normalizeToken('SOB1', allowed: digits), isNull);
    });

    test('rejects dates, prices and other punctuated numbers', () {
      expect(n.normalizeToken('12/05/2026', allowed: digits), isNull);
      expect(n.normalizeToken('100.00', allowed: digits), isNull);
      expect(n.normalizeToken('500DA', allowed: digits), isNull);
    });

    test('strips trailing label punctuation such as a colon', () {
      expect(n.normalizeToken('1234:', allowed: digits)!.value, '1234');
    });

    test('does not rewrite letters that the spec allows', () {
      const alnum = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final t = n.normalizeToken('AB12', allowed: alnum)!;
      expect(t.value, 'AB12');
      expect(t.substitutions, 0);
    });

    test('empty input yields null', () {
      expect(n.normalizeToken('', allowed: digits), isNull);
      expect(n.normalizeToken('--', allowed: digits), isNull);
    });
  });
}
