import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

const _layout = ZoneLayout.rechargeCard;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TextDirection dir = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Directionality(textDirection: dir, child: child));
}

void main() {
  group('CardScanGeometry', () {
    const g = CardScanGeometry(layout: _layout);

    test('centres a card of the layout aspect ratio', () {
      final f = g.cardFrame(const Size(400, 800));
      expect(f.width, closeTo(352, 1e-9));
      expect(f.height, closeTo(352 / 1.7, 1e-9));
      expect(f.left, closeTo(24, 1e-9));
      expect(f.center.dy, closeTo(400, 1e-9));
    });

    test('shrinks the card when it would be too tall', () {
      final f = g.cardFrame(const Size(800, 300));
      expect(f.height, closeTo(240, 1e-9));
      expect(f.width, closeTo(240 * 1.7, 1e-9));
      expect(f.center, const Offset(400, 150));
    });

    test('maps zones into the card frame', () {
      final f = g.cardFrame(const Size(400, 800));
      final code = g.zoneRect(const Size(400, 800), 'code');
      final z = _layout.zones['code']!;
      expect(code.left, closeTo(f.left + z.left * f.width, 1e-9));
      expect(code.top, closeTo(f.top + z.top * f.height, 1e-9));
      expect(code.right, closeTo(f.left + z.right * f.width, 1e-9));
      expect(code.bottom, closeTo(f.top + z.bottom * f.height, 1e-9));
      expect(g.zoneRects(const Size(400, 800)).keys, ['code', 'serial']);
    });

    test('card region in preview is the frame over the size', () {
      final r = g.cardRegionInPreview(const Size(400, 800));
      expect(r.left, closeTo(0.06, 1e-9));
      expect(r.right, closeTo(0.94, 1e-9));
    });

    test('cover mode: camera wider than preview crops the sides', () {
      final r = CardScanGeometry.previewToImage(
        const NormRect(0.06, 0.4, 0.94, 0.6),
        previewAspect: 0.5,
        cameraAspect: 0.75,
      );
      const vis = 0.5 / 0.75;
      const off = (1 - vis) / 2;
      expect(r.left, closeTo(off + 0.06 * vis, 1e-9));
      expect(r.right, closeTo(off + 0.94 * vis, 1e-9));
      expect(r.top, closeTo(0.4, 1e-9));
      expect(r.bottom, closeTo(0.6, 1e-9));
    });

    test('cover mode: camera taller than preview crops top and bottom', () {
      final r = CardScanGeometry.previewToImage(
        const NormRect(0, 0.25, 1, 0.75),
        previewAspect: 0.75,
        cameraAspect: 0.5,
      );
      const vis = 0.5 / 0.75;
      const off = (1 - vis) / 2;
      expect(r.left, 0);
      expect(r.right, 1);
      expect(r.top, closeTo(off + 0.25 * vis, 1e-9));
      expect(r.bottom, closeTo(off + 0.75 * vis, 1e-9));
    });

    test('cardRegionInImage combines both steps', () {
      final r = g.cardRegionInImage(
        previewSize: const Size(400, 800),
        cameraAspect: 0.5,
      );
      // Same aspect: no crop, image region equals preview region.
      final p = g.cardRegionInPreview(const Size(400, 800));
      expect(r.left, closeTo(p.left, 1e-9));
      expect(r.top, closeTo(p.top, 1e-9));
    });

    test('labels sit at the start edge: left in LTR, right in RTL', () {
      const zone = Rect.fromLTRB(100, 200, 300, 240);
      const label = Size(50, 16);
      final ltr = CardScanGeometry.labelOffset(
        zone: zone,
        labelSize: label,
        textDirection: TextDirection.ltr,
      );
      final rtl = CardScanGeometry.labelOffset(
        zone: zone,
        labelSize: label,
        textDirection: TextDirection.rtl,
      );
      expect(ltr, const Offset(104, 180));
      expect(rtl, const Offset(246, 180));
    });

    test('a label with no room above goes below the zone', () {
      final o = CardScanGeometry.labelOffset(
        zone: const Rect.fromLTRB(0, 5, 100, 30),
        labelSize: const Size(40, 16),
        textDirection: TextDirection.ltr,
      );
      expect(o, const Offset(4, 34));
    });
  });

  group('CardScanOverlay', () {
    testWidgets('paints mask, frame, zones and labels at the geometry', (
      tester,
    ) async {
      await _pump(
        tester,
        const CardScanOverlay(
          layout: _layout,
          labels: {'code': 'Code', 'serial': 'Serial'},
        ),
      );
      const size = Size(400, 800);
      const g = CardScanGeometry(layout: _layout);
      final frame = g.cardFrame(size);
      final code = g.zoneRect(size, 'code');
      final serial = g.zoneRect(size, 'serial');

      expect(
        find.byType(CardScanOverlay),
        paints
          ..path()
          ..rrect(
            rrect: RRect.fromRectAndRadius(frame, const Radius.circular(14)),
            style: PaintingStyle.stroke,
          )
          ..rrect(
            rrect: RRect.fromRectAndRadius(code, const Radius.circular(6)),
            style: PaintingStyle.fill,
          )
          ..rrect(
            rrect: RRect.fromRectAndRadius(code, const Radius.circular(6)),
            style: PaintingStyle.stroke,
          )
          ..paragraph()
          ..rrect(
            rrect: RRect.fromRectAndRadius(serial, const Radius.circular(6)),
            style: PaintingStyle.fill,
          )
          ..rrect(
            rrect: RRect.fromRectAndRadius(serial, const Radius.circular(6)),
            style: PaintingStyle.stroke,
          )
          ..paragraph(),
      );
    });

    testWidgets('mask path leaves the card frame clear', (tester) async {
      await _pump(tester, const CardScanOverlay(layout: _layout));
      const g = CardScanGeometry(layout: _layout);
      final frame = g.cardFrame(const Size(400, 800));
      expect(
        find.byType(CardScanOverlay),
        paints..path(
          includes: [const Offset(5, 5), const Offset(395, 795)],
          excludes: [frame.center],
        ),
      );
    });

    testWidgets('zones without a label paint no text', (tester) async {
      await _pump(tester, const CardScanOverlay(layout: _layout, labels: {}));
      expect(find.byType(CardScanOverlay), isNot(paints..paragraph()));
    });

    testWidgets('picks up RTL from Directionality', (tester) async {
      await _pump(
        tester,
        dir: TextDirection.rtl,
        const CardScanOverlay(layout: _layout, labels: {'code': 'الرمز'}),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(CardScanOverlay),
          matching: find.byType(CustomPaint),
        ),
      );
      final painter = paint.painter! as CardScanPainter;
      expect(painter.textDirection, TextDirection.rtl);
      expect(painter.geometry.layout, same(_layout));
    });

    testWidgets('explicit textDirection wins over Directionality', (
      tester,
    ) async {
      await _pump(
        tester,
        dir: TextDirection.rtl,
        const CardScanOverlay(
          layout: _layout,
          textDirection: TextDirection.ltr,
        ),
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(CardScanOverlay),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as CardScanPainter;
      expect(painter.textDirection, TextDirection.ltr);
    });

    for (final dir in TextDirection.values) {
      testWidgets('label is painted at the start edge in ${dir.name}', (
        tester,
      ) async {
        await _pump(
          tester,
          dir: dir,
          const CardScanOverlay(layout: _layout, labels: {'code': 'Code'}),
        );
        const g = CardScanGeometry(layout: _layout);
        final zone = g.zoneRect(const Size(400, 800), 'code');
        Offset? at;
        expect(
          find.byType(CardScanOverlay),
          paints..something((method, args) {
            if (method != #drawParagraph) return false;
            at = args[1] as Offset;
            return true;
          }),
        );
        if (dir == TextDirection.ltr) {
          expect(at!.dx, closeTo(zone.left + 4, 1e-9));
        } else {
          // The label paragraph is laid out with the zone width as its box
          // and RTL text is right-aligned in it, so the visible label ends
          // at the box's right edge: the zone's start edge minus the inset.
          expect(at!.dx + zone.width, closeTo(zone.right - 4, 1e-3));
        }
        expect(at!.dy, lessThan(zone.top));
      });
    }

    test('shouldRepaint only when something visible changes', () {
      const g = CardScanGeometry(layout: _layout);
      CardScanPainter p({Map<String, String> labels = const {}}) =>
          CardScanPainter(
            geometry: g,
            labels: labels,
            textDirection: TextDirection.ltr,
          );
      expect(p().shouldRepaint(p()), isFalse);
      expect(p(labels: {'code': 'x'}).shouldRepaint(p()), isTrue);
    });
  });
}
