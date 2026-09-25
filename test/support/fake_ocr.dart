import 'package:recharge_card_ocr/recharge_card_ocr.dart';

/// Builds one OCR line the way ML Kit reports it: the line text, one element
/// per whitespace-separated word, and a box per element laid out left to
/// right at 20 px per character.
OcrLine fakeLine(
  String text, {
  double top = 0,
  double left = 0,
  double height = 24,
  double? confidence = 0.95,
  List<double?>? confidences,
}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final elements = <OcrElement>[];
  var x = left;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final width = w.length * 20.0;
    elements.add(
      OcrElement(
        text: w,
        box: OcrBox(x, top, x + width, top + height),
        confidence: confidences != null ? confidences[i] : confidence,
      ),
    );
    x += width + 12;
  }
  return OcrLine(
    text: text,
    box: OcrBox(left, top, x - 12, top + height),
    elements: elements,
  );
}

/// Wraps lines into a single-block [OcrText], optionally with image size.
OcrText fakeText(List<OcrLine> lines, {int? width, int? height}) {
  if (lines.isEmpty) {
    return OcrText(blocks: const [], imageWidth: width, imageHeight: height);
  }
  return OcrText(
    blocks: [
      OcrBlock(
        text: lines.map((l) => l.text).join('\n'),
        box: lines.map((l) => l.box).reduce((a, b) => a.union(b)),
        lines: lines,
      ),
    ],
    imageWidth: width,
    imageHeight: height,
  );
}
