import 'package:flutter_test/flutter_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

void main() {
  group('DigitCodeSpec', () {
    test('length comes from grouping when lengths are omitted', () {
      final spec = DigitCodeSpec(groups: const [4, 4, 4, 2]);
      expect(spec.lengths, {14});
      expect(spec.acceptsLength(14), isTrue);
      expect(spec.acceptsLength(13), isFalse);
    });

    test('accepts several lengths', () {
      final spec = DigitCodeSpec(lengths: const {12, 16});
      expect(spec.acceptsLength(12), isTrue);
      expect(spec.acceptsLength(16), isTrue);
      expect(spec.minLength, 12);
      expect(spec.maxLength, 16);
    });

    test('rejects a grouping that contradicts the lengths', () {
      expect(
        () => DigitCodeSpec(lengths: const {12}, groups: const [4, 4, 4, 2]),
        throwsArgumentError,
      );
    });

    test('rejects a spec with no length information', () {
      expect(() => DigitCodeSpec(), throwsArgumentError);
    });

    test('formats a code with its grouping', () {
      final spec = DigitCodeSpec(groups: const [4, 4, 4, 2]);
      expect(spec.format('12345678901234'), '1234 5678 9012 34');
      expect(
        spec.format('12345678901234', separator: '-'),
        '1234-5678-9012-34',
      );
      // Wrong length: returned unchanged.
      expect(spec.format('123'), '123');
    });

    test('checks prefix, characters and checksum', () {
      final spec = DigitCodeSpec(
        lengths: const {15},
        prefix: '49',
        checksum: const LuhnChecksum(),
      );
      expect(spec.hasPrefix('490154203237518'), isTrue);
      expect(spec.hasPrefix('350154203237518'), isFalse);
      expect(spec.checksumValid('490154203237518'), isTrue);
      expect(spec.checksumValid('490154203237517'), isFalse);
      expect(spec.usesOnlyAllowed('4901'), isTrue);
      expect(spec.usesOnlyAllowed('49A1'), isFalse);
      expect(spec.matches('490154203237518'), isTrue);
      expect(spec.matches('490154203237517'), isFalse);
    });

    test('checksumValid is null when there is no validator', () {
      final spec = DigitCodeSpec(lengths: const {4});
      expect(spec.checksumValid('1234'), isNull);
    });

    test('imei preset is 15 digits with Luhn', () {
      final spec = DigitCodeSpec.imei();
      expect(spec.lengths, {15});
      expect(spec.matches('490154203237518'), isTrue);
      expect(spec.matches('490154203237517'), isFalse);
    });
  });

  group('ZoneLayout', () {
    test('resolves card zones into image coordinates', () {
      const layout = ZoneLayout(
        cardAspectRatio: 2,
        zones: {'code': NormRect(0.1, 0.2, 0.9, 0.4)},
      );
      final r = layout.resolve(const NormRect(0.25, 0.5, 0.75, 1.0))['code']!;
      expect(r.left, closeTo(0.30, 1e-9));
      expect(r.top, closeTo(0.60, 1e-9));
      expect(r.right, closeTo(0.70, 1e-9));
      expect(r.bottom, closeTo(0.70, 1e-9));
    });

    test('the default recharge-card layout has code and serial zones', () {
      expect(
        ZoneLayout.rechargeCard.zones.keys,
        containsAll(<String>['code', 'serial']),
      );
    });

    test('NormRect rejects coordinates outside 0..1 or inverted', () {
      expect(() => NormRect.fromLTRB(-0.1, 0, 1, 1), throwsArgumentError);
      expect(() => NormRect.fromLTRB(0.5, 0, 0.4, 1), throwsArgumentError);
    });
  });
}
