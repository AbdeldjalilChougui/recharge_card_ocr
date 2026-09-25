import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/src/core imports neither Flutter, dart:ui, ML Kit nor image', () {
    final forbidden = RegExp(
      r'''import\s+['"](package:flutter/|dart:ui|package:google_mlkit|package:image/)''',
    );
    final files = Directory('lib/src/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(forbidden.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}
