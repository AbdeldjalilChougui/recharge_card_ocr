import 'geometry.dart';

/// One recognised word, the smallest unit that carries a confidence.
class OcrElement {
  /// Creates an element.
  const OcrElement({required this.text, required this.box, this.confidence});

  /// Recognised text.
  final String text;

  /// Bounding box in input-image pixels.
  final OcrBox box;

  /// Recogniser confidence in `0..1`, or null when the engine gives none.
  final double? confidence;
}

/// One recognised line of text.
class OcrLine {
  /// Creates a line. When [elements] is empty, the line text is split on
  /// whitespace and every word gets the line [box] and [confidence].
  const OcrLine({
    required this.text,
    required this.box,
    this.elements = const [],
    this.confidence,
  });

  /// Recognised text of the whole line.
  final String text;

  /// Bounding box in input-image pixels.
  final OcrBox box;

  /// Words of the line, left to right.
  final List<OcrElement> elements;

  /// Line-level confidence, used for words that have none.
  final double? confidence;
}

/// A paragraph-like group of lines.
class OcrBlock {
  /// Creates a block.
  const OcrBlock({required this.text, required this.box, required this.lines});

  /// Recognised text of the block.
  final String text;

  /// Bounding box in input-image pixels.
  final OcrBox box;

  /// Lines of the block.
  final List<OcrLine> lines;
}

/// Engine-neutral OCR output, the input of the code extractor.
///
/// Adapters convert their engine's result into this shape; tests build it by
/// hand.
class OcrText {
  /// Creates OCR output.
  const OcrText({required this.blocks, this.imageWidth, this.imageHeight});

  /// Recognised blocks.
  final List<OcrBlock> blocks;

  /// Width of the image the boxes refer to, when known.
  final int? imageWidth;

  /// Height of the image the boxes refer to, when known.
  final int? imageHeight;

  /// All lines of all blocks, in reading order (top to bottom, then left to
  /// right).
  List<OcrLine> get lines {
    final all = [for (final b in blocks) ...b.lines];
    all.sort((a, b) {
      final dy = a.box.top.compareTo(b.box.top);
      return dy != 0 ? dy : a.box.left.compareTo(b.box.left);
    });
    return all;
  }

  /// The full recognised text, one line per row.
  String get text => lines.map((l) => l.text).join('\n');
}
