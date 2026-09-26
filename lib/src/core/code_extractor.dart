import 'code_candidate.dart';
import 'code_read_result.dart';
import 'digit_code_spec.dart';
import 'geometry.dart';
import 'normalizer.dart';
import 'ocr_text.dart';

class _Token {
  _Token(this.norm, this.raw, this.box, this.confidence);

  final NormalizedToken norm;
  final String raw;
  final OcrBox box;
  final double confidence;
}

/// Finds, cleans and ranks codes matching a [DigitCodeSpec] in OCR output.
class CodeExtractor {
  /// Creates an extractor for [spec].
  CodeExtractor(
    this.spec, {
    this.policy = const ReviewPolicy(),
    this.normalizer = const DigitNormalizer(),
    this.substitutionPenalty = 0.05,
    this.joinPenalty = 0.05,
    this.minCandidateLength = 4,
    this.maxAlternatives = 5,
  });

  /// The code being looked for.
  final DigitCodeSpec spec;

  /// Review thresholds.
  final ReviewPolicy policy;

  /// Look-alike correction.
  final DigitNormalizer normalizer;

  /// Confidence removed per rewritten look-alike.
  final double substitutionPenalty;

  /// Confidence removed when a code is joined from two lines.
  final double joinPenalty;

  /// Shorter digit runs are ignored.
  final int minCandidateLength;

  /// At most this many alternatives are returned by [read].
  final int maxAlternatives;

  static const _wSpec = 0.6;
  static const _wConfidence = 0.25;
  static const _wPosition = 0.15;

  /// All candidates in [text], best first, one per distinct code.
  ///
  /// [zone] is the region, in the same pixels as the OCR boxes, where the
  /// code is expected; candidates near its vertical centre rank higher. When
  /// null, the image bounds are used if [OcrText.imageWidth] and
  /// [OcrText.imageHeight] are known.
  List<CodeCandidate> extract(OcrText text, {OcrBox? zone}) {
    final area =
        zone ??
        (text.imageWidth != null && text.imageHeight != null
            ? OcrBox(
                0,
                0,
                text.imageWidth!.toDouble(),
                text.imageHeight!.toDouble(),
              )
            : null);

    final lines = text.lines;
    final runsPerLine = [for (final l in lines) _runs(l)];
    final found = <String, CodeCandidate>{};

    void keep(CodeCandidate c) {
      final prev = found[c.code];
      if (prev == null || c.score > prev.score) found[c.code] = c;
    }

    for (final runs in runsPerLine) {
      for (final run in runs) {
        final full = _build(run, area, joined: false);
        if (full.code.length >= minCandidateLength) keep(full);
        if (!spec.acceptsLength(full.code.length)) {
          for (var i = 0; i < run.length; i++) {
            for (var j = i + 1; j <= run.length; j++) {
              if (i == 0 && j == run.length) continue;
              final len = run
                  .sublist(i, j)
                  .fold<int>(0, (a, t) => a + t.norm.value.length);
              if (spec.acceptsLength(len)) {
                keep(_build(run.sublist(i, j), area, joined: false));
              }
            }
          }
        }
      }
    }

    for (var i = 0; i + 1 < lines.length; i++) {
      if (!_adjacent(lines[i], lines[i + 1])) continue;
      final a = runsPerLine[i];
      final b = runsPerLine[i + 1];
      if (a.isEmpty || b.isEmpty) continue;
      final seq = [...a.last, ...b.first];
      final len = seq.fold<int>(0, (s, t) => s + t.norm.value.length);
      if (spec.acceptsLength(len)) keep(_build(seq, area, joined: true));
    }

    // OCR sometimes returns the tail of a tilted or widely spaced code as a
    // separate line on the same row, and sorts it before or after the rest.
    for (var i = 0; i < lines.length; i++) {
      for (var j = 0; j < lines.length; j++) {
        if (i == j || !_sameRow(lines[i], lines[j])) continue;
        final a = runsPerLine[i];
        final b = runsPerLine[j];
        if (a.isEmpty || b.isEmpty) continue;
        final seq = [...a.last, ...b.first];
        final len = seq.fold<int>(0, (s, t) => s + t.norm.value.length);
        if (spec.acceptsLength(len)) keep(_build(seq, area, joined: true));
      }
    }

    final list = found.values.toList()
      ..sort((x, y) => y.score.compareTo(x.score));
    return list;
  }

  /// Extracts candidates and decides whether the best one needs review.
  CodeReadResult read(OcrText text, {OcrBox? zone}) {
    final all = extract(text, zone: zone);
    if (all.isEmpty) {
      return const CodeReadResult(
        best: null,
        alternatives: [],
        reasons: {ReviewReason.noCandidate},
      );
    }
    final best = all.first;
    final reasons = <ReviewReason>{};
    if (!best.lengthMatched || !best.prefixMatched) {
      reasons.add(ReviewReason.specMismatch);
    }
    if (best.checksumValid == false) reasons.add(ReviewReason.checksumFailed);
    if (best.confidence < policy.minConfidence) {
      reasons.add(ReviewReason.lowConfidence);
    }
    if (best.specMatched) {
      final rival = all
          .skip(1)
          .any(
            (c) =>
                c.specMatched && best.score - c.score < policy.ambiguityMargin,
          );
      if (rival) reasons.add(ReviewReason.ambiguous);
    }
    return CodeReadResult(
      best: best,
      alternatives: all.skip(1).take(maxAlternatives).toList(),
      reasons: reasons,
      formatted: spec.format(best.code),
    );
  }

  List<List<_Token>> _runs(OcrLine line) {
    final tokens = <_Token?>[];
    if (line.elements.isNotEmpty) {
      for (final e in line.elements) {
        for (final word in _words(e.text)) {
          tokens.add(_token(word, e.box, e.confidence ?? line.confidence));
        }
      }
    } else {
      for (final word in _words(line.text)) {
        tokens.add(_token(word, line.box, line.confidence));
      }
    }
    final runs = <List<_Token>>[];
    var current = <_Token>[];
    for (final t in tokens) {
      if (t == null) {
        if (current.isNotEmpty) runs.add(current);
        current = <_Token>[];
      } else {
        current.add(t);
      }
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  static final _space = RegExp(r'\s+');
  static final _labelThenDigits = RegExp(
    r'^(\p{L}{3,})(\d[\d-]*)$',
    unicode: true,
  );

  /// Splits OCR text into words on whitespace, then splits a label off the
  /// digits glued to it, because OCR often drops the space after a label:
  ///
  /// * at a colon inside a word, as in `série:422899086894`;
  /// * after a leading word of three or more letters, as in
  ///   `série340500065896`, when none of those letters is allowed in the
  ///   code and at least one is not a digit look-alike.
  ///
  /// The label is then a word of its own, which is not in digit context and
  /// still breaks the run.
  Iterable<String> _words(String text) sync* {
    for (final word in text.split(_space)) {
      final colon = word.indexOf(':');
      final parts = colon <= 0 || colon == word.length - 1
          ? [word]
          : word.split(':').where((p) => p.isNotEmpty);
      for (final part in parts) {
        final m = _labelThenDigits.firstMatch(part);
        if (m != null && _isLabel(m.group(1)!)) {
          yield m.group(1)!;
          yield m.group(2)!;
        } else {
          yield part;
        }
      }
    }
  }

  bool _isLabel(String letters) {
    var nonLookAlike = false;
    for (final ch in letters.split('')) {
      if (spec.allowedCharacters.contains(ch)) return false;
      if (!normalizer.confusions.containsKey(ch)) nonLookAlike = true;
    }
    return nonLookAlike;
  }

  _Token? _token(String word, OcrBox box, double? confidence) {
    if (word.isEmpty) return null;
    final norm = normalizer.normalizeToken(
      word,
      allowed: spec.allowedCharacters,
    );
    if (norm == null) return null;
    return _Token(norm, word, box, confidence ?? policy.assumedConfidence);
  }

  bool _adjacent(OcrLine a, OcrLine b) {
    final h = a.box.height > b.box.height ? a.box.height : b.box.height;
    final gap = b.box.top - a.box.bottom;
    return b.box.top > a.box.top + a.box.height / 2 && gap <= 1.5 * h;
  }

  /// Whether [b] continues [a] on the same row: the two overlap vertically
  /// by at least half the smaller height, and [b] starts after the end of
  /// [a] with a gap no wider than 1.5 times the widest space between the
  /// words of [a] (or one character when [a] is a single word). A wider gap
  /// suggests OCR lost characters there, and joining would give a wrong code
  /// of an accepted length.
  bool _sameRow(OcrLine a, OcrLine b) {
    final minH = a.box.height < b.box.height ? a.box.height : b.box.height;
    final top = a.box.top > b.box.top ? a.box.top : b.box.top;
    final bottom = a.box.bottom < b.box.bottom ? a.box.bottom : b.box.bottom;
    if (bottom - top < 0.5 * minH) return false;
    final gap = b.box.left - a.box.right;
    if (gap < -0.25 * minH) return false;
    var space = 0.0;
    for (var k = 0; k + 1 < a.elements.length; k++) {
      final s = a.elements[k + 1].box.left - a.elements[k].box.right;
      if (s > space) space = s;
    }
    if (space <= 0) {
      final chars = a.text.replaceAll(_space, '').length;
      space = chars == 0 ? 0 : a.box.width / chars;
    }
    return gap <= 1.5 * space;
  }

  CodeCandidate _build(List<_Token> seq, OcrBox? area, {required bool joined}) {
    final code = seq.map((t) => t.norm.value).join();
    final subs = seq.fold<int>(0, (a, t) => a + t.norm.substitutions);
    final groups = [for (final t in seq) ...t.norm.groups];
    final meanConf =
        seq.fold<double>(0, (a, t) => a + t.confidence) / seq.length;
    final confidence =
        (meanConf - subs * substitutionPenalty - (joined ? joinPenalty : 0))
            .clamp(0.0, 1.0);
    final box = seq.map((t) => t.box).reduce((a, b) => a.union(b));

    final lengthMatched = spec.acceptsLength(code.length);
    final specGroups = spec.groups;
    final groupingMatched = specGroups != null && _sameList(groups, specGroups);
    final prefixMatched = spec.hasPrefix(code);
    final checksumValid = spec.checksumValid(code);

    double specScore;
    if (lengthMatched) {
      specScore =
          0.5 +
          (specGroups == null || groupingMatched ? 0.2 : 0) +
          (prefixMatched ? 0.1 : 0) +
          (checksumValid ?? true ? 0.2 : 0);
    } else {
      var nearest = spec.lengths.first;
      for (final l in spec.lengths) {
        if ((l - code.length).abs() < (nearest - code.length).abs()) {
          nearest = l;
        }
      }
      final off = (nearest - code.length).abs() / nearest;
      specScore = 0.25 * (1 - off).clamp(0.0, 1.0);
    }

    final score =
        _wSpec * specScore +
        _wConfidence * confidence +
        _wPosition * _position(box, area);

    return CodeCandidate(
      code: code,
      rawText: seq.map((t) => t.raw).join(' '),
      confidence: confidence,
      score: score,
      lengthMatched: lengthMatched,
      groupingMatched: groupingMatched,
      prefixMatched: prefixMatched,
      checksumValid: checksumValid,
      substitutions: subs,
      joinedLines: joined,
      box: box,
    );
  }

  static double _position(OcrBox box, OcrBox? area) {
    if (area == null) return 1;
    if (!area.containsPoint(box.centerX, box.centerY)) return 0;
    final half = area.height / 2;
    if (half <= 0) return 1;
    final off = (box.centerY - area.centerY).abs() / half;
    return (1 - 0.5 * off).clamp(0.0, 1.0);
  }

  static bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
