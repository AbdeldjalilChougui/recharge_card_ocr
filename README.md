# recharge_card_ocr

Read scratch-card recharge codes and other printed digit codes (vouchers,
meter numbers, IMEI labels) from a photo. The package corrects the photo's
orientation, crops the zones you define, cleans up the digits, checks them
against your code format and flags doubtful reads for a person to confirm.

[![pub package](https://img.shields.io/pub/v/recharge_card_ocr.svg)](https://pub.dev/packages/recharge_card_ocr)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- **`DigitCodeSpec`**: accepted length(s), printed grouping (`4-4-4-2`),
  prefix, allowed characters, and a check digit: Luhn, weighted mod-10
  (GS1 preset for EAN/UPC) or your own function. `DigitCodeSpec.imei()` is
  included.
- **Digit clean-up** that only touches numbers: `O`→`0`, `I`/`l`→`1`,
  `S`→`5`, `B`→`8`, `Z`→`2` are rewritten inside digit groups such as
  `9O12`, never inside words such as `BOSS` or `PRICE`. Spaces and dashes
  are removed, and a code split over two lines is joined.
- **Ranking and gating**: candidates are ranked by how well they fit the
  spec, by the OCR's per-word confidence and by their position in the zone.
  The result has the best code, its alternatives, a confidence value and
  `needsReview` with reasons (`lowConfidence`, `ambiguous`,
  `checksumFailed`, `specMismatch`, `noCandidate`).
- **`ZoneLayout`**: named rectangles on the card (for example `code` and
  `serial`) in card-relative coordinates.
- **Image preparation** with `package:image`: EXIF orientation fix, zone
  crops, upscaling of small crops, grayscale and contrast stretch. It can
  run on a background isolate with `prepareInIsolate`.
- **`MlKitDigitReader`**: an on-device adapter for Google ML Kit text
  recognition, behind the `TextRecognizerPort` interface. All of the logic
  runs through the port, so you can test it with canned OCR output or use
  another engine.
- **`CardScanOverlay`**: draws the card frame and zone guides over your
  camera preview. Labels start at the right edge in RTL layouts. It has no
  camera dependency. `CardScanGeometry` maps the frame into the captured
  photo.

The core (`lib/src/core/`) is plain Dart with no Flutter, ML Kit or image
imports, and a test enforces that.

## Install

```yaml
dependencies:
  recharge_card_ocr: ^0.1.0
```

### Platform requirements

On-device recognition comes from
[`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition)
0.16.x. That plugin is maintained by the flutter-ml community, not by
Google. Version 0.16.0 was published in July 2026, and 0.17.x (August 2026)
needs Dart 3.12 and Flutter 3.44.

- **Android**: minSdk 21, compileSdk 36.
- **iOS**: deployment target 15.5 and 64-bit only. Exclude `armv7` and set
  `platform :ios, '15.5'` in your Podfile, as the plugin README describes.
- **No web or desktop support** for `MlKitDigitReader`. ML Kit only runs on
  Android and iOS. The core, the image preparation and the overlay work on
  every platform, so you can plug another OCR engine in through
  `TextRecognizerPort`.

The package itself needs Dart 3.8 and Flutter 3.32, which are the minimums
of the ML Kit plugin.

## Usage

### Read a photo

```dart
import 'dart:typed_data';

import 'package:recharge_card_ocr/recharge_card_ocr.dart';

Future<void> readCard(Uint8List jpegBytes) async {
  final reader = CardCodeReader(
    recognizer: MlKitDigitReader(),
    layout: ZoneLayout.rechargeCard,
    specs: {
      // Describe the codes printed on your cards.
      'code': DigitCodeSpec(groups: const [4, 4, 4, 2]),
      'serial': DigitCodeSpec(lengths: const {12}),
    },
  );
  try {
    final result = await reader.read(jpegBytes);
    final code = result['code']!;
    if (code.needsReview) {
      print('Please check: ${code.formatted} (${code.reasons})');
    } else {
      print('Code: ${code.formatted}');
    }
  } finally {
    await reader.close();
  }
}
```

### Only the text logic

```dart
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

void main() {
  final extractor = CodeExtractor(
    DigitCodeSpec.imei(),
    policy: const ReviewPolicy(minConfidence: 0.8),
  );
  const ocr = OcrText(
    blocks: [
      OcrBlock(
        text: 'IMEI: 49O154203237518',
        box: OcrBox(0, 0, 400, 30),
        lines: [
          OcrLine(
            text: 'IMEI: 49O154203237518',
            box: OcrBox(0, 0, 400, 30),
            confidence: 0.93,
          ),
        ],
      ),
    ],
  );
  final result = extractor.read(ocr);
  print(result.code); // 490154203237518 (O read as 0, Luhn passes)
  print(result.needsReview); // false
}
```

### Camera overlay

Put the overlay over a `BoxFit.cover` preview. Then use the same geometry
to find where the card is in the captured photo:

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

const layout = ZoneLayout.rechargeCard;

Widget overlay() => const CardScanOverlay(
  layout: layout,
  labels: {'code': 'Code', 'serial': 'Serial'},
);

Future<CardReadResult> readCapture(
  CardCodeReader reader,
  Uint8List photo,
  Size previewSize,
  double cameraAspect, // width / height, in the preview's orientation
) {
  final cardRegion = const CardScanGeometry(
    layout: layout,
  ).cardRegionInImage(previewSize: previewSize, cameraAspect: cameraAspect);
  return reader.read(photo, cardRegion: cardRegion);
}
```

`example/` is a complete camera app built with
[`camera`](https://pub.dev/packages/camera).

### Testing your app without ML Kit

Implement `TextRecognizerPort` and return canned `OcrText`:

```dart
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

class FakeRecognizer implements TextRecognizerPort {
  FakeRecognizer(this.byZone);

  final Map<String, OcrText> byZone;

  @override
  Future<OcrText> recognize(PreparedZone zone) async =>
      byZone[zone.name] ?? const OcrText(blocks: []);

  @override
  Future<void> close() async {}
}
```

## Limitations

- **On-device recognition quality has not been measured.** The tests use
  synthetic images and hand-written OCR output, and ML Kit never runs in
  them. How well codes are read depends on the device camera, lighting,
  card print and ML Kit's model.
- `ZoneLayout.rechargeCard` was tuned on the cards of apps used in
  production. Card designs differ, so measure yours and pass your own
  layout.
- No recharge-card formats for specific operators are included, because no
  public, verifiable specification for them was found. Describe your
  format with `DigitCodeSpec`.
- The confidence value is a heuristic. It is the mean of the words' OCR
  confidences, minus 0.05 for each rewritten look-alike and 0.05 for a
  join across lines. The ranking weights are fixed. The defaults
  (`minConfidence` 0.7, ambiguity margin 0.1) are starting points and need
  tuning on real scans.
- When the engine reports no confidence, the code is treated as fully
  confident (`ReviewPolicy.assumedConfidence`, default 1.0). Lower this
  value if you want those reads reviewed.
- The upscale target (`minShortSide` 96 px) is a heuristic. ML Kit asks for
  Latin characters of at least 16×16 px.
- Only one code is joined across two adjacent lines. Codes split over three
  or more lines are not joined.

## License

MIT. See [LICENSE](LICENSE).

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
