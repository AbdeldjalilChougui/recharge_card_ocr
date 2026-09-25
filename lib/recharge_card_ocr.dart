/// Read recharge-card and other digit codes from photos: orientation fix,
/// zoned crops, OCR digit clean-up, checksums and confidence gating.
library;

export 'src/core/checksum.dart';
export 'src/core/code_candidate.dart';
export 'src/core/code_extractor.dart';
export 'src/core/code_read_result.dart';
export 'src/core/digit_code_spec.dart';
export 'src/core/geometry.dart';
export 'src/core/normalizer.dart';
export 'src/core/ocr_text.dart';
export 'src/core/zone_layout.dart';
export 'src/image/card_image_preparer.dart';
export 'src/image/prepared.dart';
export 'src/port/text_recognizer_port.dart';
export 'src/reader.dart';
export 'src/mlkit/mlkit_digit_reader.dart';
export 'src/widget/card_scan_geometry.dart';
export 'src/widget/card_scan_overlay.dart';
