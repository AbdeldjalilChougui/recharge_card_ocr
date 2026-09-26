import 'package:flutter_test/flutter_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

import '../support/fake_ocr.dart';

void main() {
  final card = DigitCodeSpec(groups: const [4, 4, 4, 2]);

  group('clean text', () {
    test('reads a grouped 14-digit code', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('1234 5678 9012 34', top: 40)]));
      expect(r.code, '12345678901234');
      expect(r.best!.lengthMatched, isTrue);
      expect(r.best!.groupingMatched, isTrue);
      expect(r.best!.substitutions, 0);
      expect(r.needsReview, isFalse);
      expect(r.reasons, isEmpty);
      expect(r.confidence, greaterThan(0.9));
    });

    test('reads a code printed with dashes as one element', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('1234-5678-9012-34')]));
      expect(r.code, '12345678901234');
      expect(r.needsReview, isFalse);
    });

    test('keeps the raw OCR text for display', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('PIN 1234 5678 9012 34')]));
      expect(r.best!.rawText, '1234 5678 9012 34');
    });
  });

  group('O/0 and I/1 confusions', () {
    test('normalises look-alikes inside the code only', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('BOSS I234 56O8 9O12 34')]));
      expect(r.code, '12345608901234');
      expect(r.best!.substitutions, 3);
      expect(r.best!.rawText, 'I234 56O8 9O12 34');
    });

    test('each substitution lowers confidence', () {
      final clean = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('1234 5608 9012 34')]));
      final fixed = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('I234 56O8 9O12 34')]));
      expect(fixed.code, clean.code);
      expect(fixed.confidence, lessThan(clean.confidence));
    });

    test('many substitutions push the code under the threshold', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('IZ34 S6O8 9OI2 3B', confidence: 0.9)]));
      expect(r.code, '12345608901238');
      expect(r.needsReview, isTrue);
      expect(r.reasons, contains(ReviewReason.lowConfidence));
    });
  });

  group('code split across lines', () {
    test('joins the end of one line with the start of the next', () {
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('1234 5678', top: 10),
          fakeLine('9012 34', top: 40),
        ]),
      );
      expect(r.code, '12345678901234');
      expect(r.best!.joinedLines, isTrue);
      expect(r.best!.groupingMatched, isTrue);
      expect(r.needsReview, isFalse);
    });

    test('joins lines reported in separate blocks and out of order', () {
      final second = fakeLine('9012 34', top: 40);
      final first = fakeLine('Code: 1234 5678', top: 10);
      final text = OcrText(
        blocks: [
          OcrBlock(text: second.text, box: second.box, lines: [second]),
          OcrBlock(text: first.text, box: first.box, lines: [first]),
        ],
      );
      expect(CodeExtractor(card).read(text).code, '12345678901234');
    });

    test('does not join lines that are far apart', () {
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('1234 5678', top: 10),
          fakeLine('9012 34', top: 400),
        ]),
      );
      expect(r.code, isNot('12345678901234'));
      expect(r.needsReview, isTrue);
    });
  });

  group('labels glued to the digits', () {
    final serial = DigitCodeSpec(lengths: const {12});

    test('reads digits joined to a label by a colon', () {
      // ML Kit often drops the space after "série:" and returns one word.
      final r = CodeExtractor(
        serial,
      ).read(fakeText([fakeLine('N° série:422899086894')]));
      expect(r.code, '422899086894');
      expect(r.needsReview, isFalse);
    });

    test('reads a grouped code whose first group is glued to the label', () {
      final r = CodeExtractor(
        serial,
      ).read(fakeText([fakeLine('N° série:8496 0988 1439')]));
      expect(r.code, '849609881439');
      expect(r.best!.rawText, '8496 0988 1439');
    });

    test('a glued label still separates the digits around it', () {
      final r = CodeExtractor(
        DigitCodeSpec(lengths: const {8}),
      ).extract(fakeText([fakeLine('1234 Lot:5678')]));
      expect(r.map((c) => c.code), isNot(contains('12345678')));
    });
  });

  group('noise text', () {
    test('ignores prices, dates, phone numbers and labels', () {
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('Recharge 1000 DA', top: 0),
          fakeLine('Prix: 100.00', top: 30),
          fakeLine('Exp: 12/2027', top: 60),
          fakeLine('Service client 021 45 67 89', top: 90),
          fakeLine('1234 5678 9012 34', top: 140),
          fakeLine('Lot 2026-07', top: 200),
        ]),
      );
      expect(r.code, '12345678901234');
      expect(r.needsReview, isFalse);
      for (final alt in r.alternatives) {
        expect(alt.lengthMatched, isFalse, reason: alt.code);
      }
    });

    test('picks the correctly grouped window from a longer run', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('1234 5678 9012 34 5555')]));
      expect(r.code, '12345678901234');
      expect(r.needsReview, isFalse);
    });
  });

  group('two candidates', () {
    test('two equally good codes are ambiguous', () {
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('1234 5678 9012 34', top: 10),
          fakeLine('9999 8888 7777 66', top: 200),
        ]),
      );
      expect(r.needsReview, isTrue);
      expect(r.reasons, contains(ReviewReason.ambiguous));
      expect([
        r.code,
        ...r.alternatives.map((c) => c.code),
      ], containsAll(<String>['12345678901234', '99998888777766']));
    });

    test('a spec match beats a non-match without ambiguity', () {
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('1234 5678 9012 34', top: 10),
          fakeLine('00012345678', top: 200),
        ]),
      );
      expect(r.code, '12345678901234');
      expect(r.needsReview, isFalse);
      expect(r.alternatives.map((c) => c.code), contains('00012345678'));
    });

    test('position inside the zone breaks a tie', () {
      final zone = const OcrBox(0, 100, 600, 200);
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('9999 8888 7777 66', top: 10),
          fakeLine('1234 5678 9012 34', top: 140),
        ]),
        zone: zone,
      );
      expect(r.code, '12345678901234');
      expect(r.reasons, isNot(contains(ReviewReason.ambiguous)));
    });

    test('the image bounds act as the zone when known', () {
      final r = CodeExtractor(card).read(
        fakeText(
          [
            fakeLine('9999 8888 7777 66', top: 300),
            fakeLine('1234 5678 9012 34', top: 40),
          ],
          width: 600,
          height: 100,
        ),
      );
      expect(r.code, '12345678901234');
    });

    test('alternatives are capped', () {
      final r = CodeExtractor(card, maxAlternatives: 1).read(
        fakeText([
          fakeLine('1234 5678 9012 34', top: 10),
          fakeLine('9999 8888 7777 66', top: 200),
          fakeLine('1111 2222 3333 44', top: 400),
        ]),
      );
      expect(r.alternatives, hasLength(1));
    });
  });

  group('checksum', () {
    final imei = DigitCodeSpec.imei();

    test('passing checksum is accepted', () {
      final r = CodeExtractor(
        imei,
      ).read(fakeText([fakeLine('IMEI: 490154203237518')]));
      expect(r.code, '490154203237518');
      expect(r.best!.checksumValid, isTrue);
      expect(r.needsReview, isFalse);
    });

    test('failing checksum is flagged for review', () {
      final r = CodeExtractor(
        imei,
      ).read(fakeText([fakeLine('IMEI: 490154203237517')]));
      expect(r.code, '490154203237517');
      expect(r.best!.checksumValid, isFalse);
      expect(r.needsReview, isTrue);
      expect(r.reasons, contains(ReviewReason.checksumFailed));
    });

    test('the valid one of two candidates wins without ambiguity', () {
      final r = CodeExtractor(imei).read(
        fakeText([
          fakeLine('IMEI1 490154203237517', top: 10),
          fakeLine('IMEI2 356938035643809', top: 60),
        ]),
      );
      expect(r.code, '356938035643809');
      expect(r.needsReview, isFalse);
    });

    test('checksum rescues an I/1 confusion', () {
      final r = CodeExtractor(
        imei,
      ).read(fakeText([fakeLine('49OI54203237518')]));
      expect(r.code, '490154203237518');
      expect(r.best!.checksumValid, isTrue);
    });
  });

  group('prefix', () {
    test('a missing prefix is a spec mismatch', () {
      final spec = DigitCodeSpec(lengths: const {10}, prefix: '07');
      final ok = CodeExtractor(spec).read(fakeText([fakeLine('0712345678')]));
      final bad = CodeExtractor(spec).read(fakeText([fakeLine('0812345678')]));
      expect(ok.needsReview, isFalse);
      expect(bad.needsReview, isTrue);
      expect(bad.reasons, contains(ReviewReason.specMismatch));
    });
  });

  group('confidence gating', () {
    test('low element confidence needs review', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('1234 5678 9012 34', confidence: 0.5)]));
      expect(r.code, '12345678901234');
      expect(r.needsReview, isTrue);
      expect(r.reasons, [ReviewReason.lowConfidence]);
    });

    test('one weak element drags the average down', () {
      final r = CodeExtractor(card).read(
        fakeText([
          fakeLine('1234 5678 9012 34', confidences: [0.95, 0.95, 0.1, 0.95]),
        ]),
      );
      expect(r.confidence, closeTo(0.7375, 1e-9));
    });

    test('threshold is configurable', () {
      final r = CodeExtractor(
        card,
        policy: const ReviewPolicy(minConfidence: 0.4),
      ).read(fakeText([fakeLine('1234 5678 9012 34', confidence: 0.5)]));
      expect(r.needsReview, isFalse);
    });

    test('missing confidence uses the assumed value', () {
      final unknown = fakeText([
        fakeLine('1234 5678 9012 34', confidence: null),
      ]);
      expect(CodeExtractor(card).read(unknown).confidence, 1.0);
      final strict = CodeExtractor(
        card,
        policy: const ReviewPolicy(assumedConfidence: 0.5),
      ).read(unknown);
      expect(strict.needsReview, isTrue);
    });

    test('line confidence is used when elements have none', () {
      const text = OcrText(
        blocks: [
          OcrBlock(
            text: '1234 5678 9012 34',
            box: OcrBox(0, 0, 400, 24),
            lines: [
              OcrLine(
                text: '1234 5678 9012 34',
                box: OcrBox(0, 0, 400, 24),
                confidence: 0.6,
              ),
            ],
          ),
        ],
      );
      final r = CodeExtractor(card).read(text);
      expect(r.code, '12345678901234');
      expect(r.confidence, closeTo(0.6, 1e-9));
      expect(r.needsReview, isTrue);
    });
  });

  group('edge cases', () {
    test('empty text yields no candidate', () {
      final r = CodeExtractor(card).read(fakeText([]));
      expect(r.best, isNull);
      expect(r.code, isNull);
      expect(r.confidence, 0);
      expect(r.needsReview, isTrue);
      expect(r.reasons, [ReviewReason.noCandidate]);
    });

    test('wrong length is returned but flagged', () {
      final r = CodeExtractor(card).read(fakeText([fakeLine('1234 5678')]));
      expect(r.code, '12345678');
      expect(r.needsReview, isTrue);
      expect(r.reasons, contains(ReviewReason.specMismatch));
    });

    test('extract returns candidates ranked best first', () {
      final list = CodeExtractor(card).extract(
        fakeText([
          fakeLine('1234 5678', top: 0),
          fakeLine('1234 5678 9012 34', top: 100),
        ]),
      );
      expect(list.first.code, '12345678901234');
      for (var i = 1; i < list.length; i++) {
        expect(list[i - 1].score, greaterThanOrEqualTo(list[i].score));
      }
      expect(list.map((c) => c.code).toSet(), hasLength(list.length));
    });

    test('alphanumeric vouchers keep their letters', () {
      final spec = DigitCodeSpec(
        lengths: const {8},
        allowedCharacters: 'ABCDEFGHJKMNPQRSTUVWXYZ23456789',
      );
      final r = CodeExtractor(spec).read(fakeText([fakeLine('K7QM 4XZ9')]));
      expect(r.code, 'K7QM4XZ9');
      expect(r.best!.substitutions, 0);
    });

    test('formatted code uses the spec grouping', () {
      final r = CodeExtractor(
        card,
      ).read(fakeText([fakeLine('12345678901234')]));
      expect(r.formatted, '1234 5678 9012 34');
      expect(r.best!.groupingMatched, isFalse);
      expect(r.needsReview, isFalse);
    });
  });
}
