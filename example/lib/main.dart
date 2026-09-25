import 'package:flutter/material.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

import 'result_view.dart';
import 'scan_screen.dart';

/// Example specs: a 15-digit code and a 15-digit serial. Change them to the
/// format printed on your cards (lengths, grouping, prefix, checksum).
final Map<String, DigitCodeSpec> exampleSpecs = {
  'code': DigitCodeSpec(lengths: const {15}),
  'serial': DigitCodeSpec(lengths: const {15}),
};

void main() => runApp(const ExampleApp());

/// Root of the demo.
class ExampleApp extends StatefulWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  bool _rtl = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'recharge_card_ocr',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      builder: (context, child) => Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: HomePage(rtl: _rtl, onRtlChanged: (v) => setState(() => _rtl = v)),
    );
  }
}

/// Start screen: scan button and the last result.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key, required this.rtl, required this.onRtlChanged});

  /// Whether labels are shown right-to-left (Arabic).
  final bool rtl;

  /// Toggles RTL.
  final ValueChanged<bool> onRtlChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CardReadResult? _result;

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<CardReadResult>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          specs: exampleSpecs,
          labels: widget.rtl
              ? const {'code': 'الرمز', 'serial': 'الرقم التسلسلي'}
              : const {'code': 'Code', 'serial': 'Serial'},
        ),
      ),
    );
    if (result != null && mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card code OCR'),
        actions: [
          Row(
            children: [
              const Text('RTL'),
              Switch(value: widget.rtl, onChanged: widget.onRtlChanged),
            ],
          ),
        ],
      ),
      body: result == null
          ? const Center(child: Text('Scan a card to read its code.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in result.zones.entries)
                  ZoneResultCard(name: e.key, result: e.value),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }
}
