import 'package:flutter/material.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

/// Shows one zone's result: the code, its confidence, review reasons and
/// alternatives.
class ZoneResultCard extends StatelessWidget {
  /// Creates the card.
  const ZoneResultCard({super.key, required this.name, required this.result});

  /// Zone name.
  final String name;

  /// Zone result.
  final CodeReadResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = result.needsReview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                const Spacer(),
                Chip(
                  key: const Key('status'),
                  avatar: Icon(
                    review ? Icons.warning_amber : Icons.check_circle,
                    color: review ? Colors.orange : Colors.green,
                  ),
                  label: Text(review ? 'Check' : 'OK'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              result.formatted ?? '—',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textDirection: TextDirection.ltr,
            ),
            Text('Confidence ${(result.confidence * 100).toStringAsFixed(0)}%'),
            if (result.reasons.isNotEmpty)
              Text(
                'Review: ${result.reasons.map((r) => r.name).join(', ')}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (result.alternatives.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Alternatives', style: theme.textTheme.labelLarge),
              for (final alt in result.alternatives)
                Text(
                  alt.code,
                  key: ValueKey('alt-${alt.code}'),
                  textDirection: TextDirection.ltr,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
