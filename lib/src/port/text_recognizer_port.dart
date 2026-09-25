import '../core/ocr_text.dart';
import '../image/prepared.dart';

/// The boundary between this package and an OCR engine.
///
/// Implement it to plug in another engine, or with canned [OcrText] in
/// tests. `MlKitDigitReader` is the ML Kit implementation.
abstract interface class TextRecognizerPort {
  /// Recognises text in one prepared zone. Boxes in the result are in the
  /// pixels of [zone]'s image.
  Future<OcrText> recognize(PreparedZone zone);

  /// Releases engine resources.
  Future<void> close();
}
