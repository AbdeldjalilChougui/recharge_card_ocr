import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

const _red = [220, 20, 20];
const _blue = [20, 20, 220];

/// A 40x20 landscape JPEG, left half red and right half blue, carrying the
/// given EXIF orientation tag.
Uint8List _halves({int orientation = 1}) {
  final im = img.Image(width: 40, height: 20);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 40; x++) {
      final c = x < 20 ? _red : _blue;
      im.setPixelRgb(x, y, c[0], c[1], c[2]);
    }
  }
  im.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(im, quality: 100);
}

img.Image _decode(PreparedZone z) => img.decodePng(z.bytes)!;

bool _isRed(img.Pixel p) => p.r > 150 && p.b < 100;
bool _isBlue(img.Pixel p) => p.b > 150 && p.r < 100;

const _whole = ZoneLayout(
  cardAspectRatio: 2,
  zones: {'all': NormRect(0, 0, 1, 1)},
);

const _raw = PrepareOptions(
  grayscale: false,
  contrastStretch: false,
  minShortSide: 0,
);

void main() {
  group('EXIF orientation', () {
    test('orientation 1 keeps the image as stored', () {
      final card = prepareCard(_halves(), _whole, options: _raw);
      expect(card.width, 40);
      expect(card.height, 20);
      final im = _decode(card.zones['all']!);
      expect(_isRed(im.getPixel(5, 10)), isTrue);
      expect(_isBlue(im.getPixel(35, 10)), isTrue);
    });

    test('orientation 6 (rotate 90) puts the left half on top', () {
      final card = prepareCard(_halves(orientation: 6), _whole, options: _raw);
      expect(card.width, 20);
      expect(card.height, 40);
      final im = _decode(card.zones['all']!);
      expect(_isRed(im.getPixel(10, 5)), isTrue);
      expect(_isBlue(im.getPixel(10, 35)), isTrue);
    });

    test('orientation 3 (rotate 180) swaps left and right', () {
      final card = prepareCard(_halves(orientation: 3), _whole, options: _raw);
      expect(card.width, 40);
      expect(card.height, 20);
      final im = _decode(card.zones['all']!);
      expect(_isBlue(im.getPixel(5, 10)), isTrue);
      expect(_isRed(im.getPixel(35, 10)), isTrue);
    });

    test('orientation 8 (rotate 270) puts the left half at the bottom', () {
      final card = prepareCard(_halves(orientation: 8), _whole, options: _raw);
      expect(card.width, 20);
      expect(card.height, 40);
      final im = _decode(card.zones['all']!);
      expect(_isBlue(im.getPixel(10, 5)), isTrue);
      expect(_isRed(im.getPixel(10, 35)), isTrue);
    });

    test('undecodable bytes throw a FormatException', () {
      expect(
        () => prepareCard(Uint8List.fromList([1, 2, 3]), _whole),
        throwsFormatException,
      );
    });
  });

  group('crop coordinates', () {
    test('pixelRectFor maps normalised rects to pixels', () {
      final r = pixelRectFor(const NormRect(0.25, 0.5, 0.75, 1.0), 200, 100);
      expect([r.x, r.y, r.width, r.height], [50, 50, 100, 50]);
    });

    test('pixelRectFor never returns an empty or out-of-bounds rect', () {
      final r = pixelRectFor(const NormRect(1, 1, 1, 1), 200, 100);
      expect(r.width, greaterThanOrEqualTo(1));
      expect(r.height, greaterThanOrEqualTo(1));
      expect(r.x + r.width, lessThanOrEqualTo(200));
      expect(r.y + r.height, lessThanOrEqualTo(100));
    });

    test('zones are cropped from the oriented image', () {
      const layout = ZoneLayout(
        cardAspectRatio: 2,
        zones: {
          'left': NormRect(0, 0, 0.5, 1),
          'right': NormRect(0.5, 0, 1, 1),
        },
      );
      final card = prepareCard(_halves(), layout, options: _raw);
      final left = card.zones['left']!;
      final right = card.zones['right']!;
      expect(left.sourceRect.x, 0);
      expect(left.sourceRect.width, 20);
      expect(right.sourceRect.x, 20);
      expect(left.width, 20);
      expect(left.height, 20);
      expect(_isRed(_decode(left).getPixel(10, 10)), isTrue);
      expect(_isBlue(_decode(right).getPixel(10, 10)), isTrue);
    });

    test('card region maps card zones into the photo', () {
      const layout = ZoneLayout(
        cardAspectRatio: 2,
        zones: {'right': NormRect(0.5, 0, 1, 1)},
      );
      // The card covers only the left half of the photo, so the card's right
      // half is the photo's second quarter: still red.
      final card = prepareCard(
        _halves(),
        layout,
        cardRegion: const NormRect(0, 0, 0.5, 1),
        options: _raw,
      );
      final z = card.zones['right']!;
      expect(z.sourceRect.x, 10);
      expect(z.sourceRect.width, 10);
      expect(_isRed(_decode(z).getPixel(5, 10)), isTrue);
    });

    test('only prepares the requested zones', () {
      final card = prepareCard(
        _halves(),
        ZoneLayout.rechargeCard,
        only: {'code'},
      );
      expect(card.zones.keys, ['code']);
    });
  });

  group('upscale', () {
    test('small crops are upscaled to the minimum short side', () {
      final card = prepareCard(
        _halves(),
        _whole,
        options: const PrepareOptions(minShortSide: 60, maxUpscale: 4),
      );
      final z = card.zones['all']!;
      expect(z.scale, 3);
      expect(z.width, 120);
      expect(z.height, 60);
      final im = _decode(z);
      expect([im.width, im.height], [120, 60]);
    });

    test('upscale is capped by maxUpscale', () {
      final card = prepareCard(
        _halves(),
        _whole,
        options: const PrepareOptions(minShortSide: 200, maxUpscale: 2),
      );
      final z = card.zones['all']!;
      expect(z.scale, 2);
      expect(z.height, 40);
    });

    test('large crops are left alone', () {
      final card = prepareCard(
        _halves(),
        _whole,
        options: const PrepareOptions(minShortSide: 10),
      );
      expect(card.zones['all']!.scale, 1);
      expect(card.zones['all']!.width, 40);
    });
  });

  group('grayscale and contrast', () {
    test('grayscale makes channels equal', () {
      final card = prepareCard(
        _halves(),
        _whole,
        options: const PrepareOptions(
          grayscale: true,
          contrastStretch: false,
          minShortSide: 0,
        ),
      );
      final p = _decode(card.zones['all']!).getPixel(5, 10);
      expect(p.r, p.g);
      expect(p.g, p.b);
    });

    test('contrast stretch spreads a dull image to the full range', () {
      final im = img.Image(width: 10, height: 10);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          final v = x < 5 ? 100 : 140;
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      final out = stretchContrast(im, lowPercentile: 0, highPercentile: 1);
      expect(out.getPixel(0, 0).r, 0);
      expect(out.getPixel(9, 0).r, 255);
    });

    test('contrast stretch leaves a flat image unchanged', () {
      final im = img.Image(width: 4, height: 4);
      img.fill(im, color: img.ColorRgb8(90, 90, 90));
      final out = stretchContrast(im);
      expect(out.getPixel(1, 1).r, 90);
    });
  });

  group('prepareInIsolate', () {
    test('gives the same result as prepareCard', () async {
      final bytes = _halves(orientation: 6);
      final a = prepareCard(bytes, _whole, options: _raw);
      final b = await prepareInIsolate(bytes, _whole, options: _raw);
      expect([b.width, b.height], [a.width, a.height]);
      expect(b.zones['all']!.bytes, a.zones['all']!.bytes);
    });
  });
}
