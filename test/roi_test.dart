import 'dart:ui';

import 'package:facecamera/src/roi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const roi = Rect.fromLTWH(100, 100, 200, 200); // 100..300 on both axes

  group('isFaceInRoi (RN AABB port)', () {
    test('face fully inside the ROI is detected', () {
      expect(isFaceInRoi(const Rect.fromLTWH(150, 150, 50, 50), roi), isTrue);
    });

    test('face partially overlapping the ROI is detected', () {
      expect(isFaceInRoi(const Rect.fromLTWH(280, 280, 60, 60), roi), isTrue);
    });

    test('touching edges counts as inside (non-strict inequality)', () {
      // Right edge of face == left edge of ROI.
      expect(isFaceInRoi(const Rect.fromLTWH(50, 150, 50, 50), roi), isTrue);
    });

    test('face fully to the left is rejected', () {
      expect(isFaceInRoi(const Rect.fromLTWH(0, 150, 40, 40), roi), isFalse);
    });

    test('face fully to the right is rejected', () {
      expect(isFaceInRoi(const Rect.fromLTWH(400, 150, 40, 40), roi), isFalse);
    });

    test('face fully above is rejected', () {
      expect(isFaceInRoi(const Rect.fromLTWH(150, 0, 40, 40), roi), isFalse);
    });

    test('face fully below is rejected', () {
      expect(isFaceInRoi(const Rect.fromLTWH(150, 400, 40, 40), roi), isFalse);
    });
  });

  group('Roi.toRect', () {
    test('resolves fractional bounds against the canvas size', () {
      const r = Roi(left: 0.1, top: 0.2, width: 0.5, height: 0.4);
      final rect = r.toRect(const Size(1000, 500));
      expect(rect, const Rect.fromLTWH(100, 100, 500, 200));
    });
  });
}
