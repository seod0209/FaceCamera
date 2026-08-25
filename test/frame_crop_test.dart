import 'dart:typed_data';
import 'dart:ui';

import 'package:facecamera/src/frame_crop.dart';
import 'package:facecamera/src/roi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

void main() {
  group('computeNativeCrop', () {
    test('rotation0: ROI maps 1:1 into native buffer', () {
      const roi = Roi(left: 0.25, top: 0.25, width: 0.5, height: 0.5);
      final crop = computeNativeCrop(roi, 480, 640, InputImageRotation.rotation0deg);
      expect(crop, const NativeCrop(120, 160, 240, 320));
    });

    test('rotation90: full ROI covers the whole buffer', () {
      const roi = Roi(left: 0, top: 0, width: 1, height: 1);
      final crop = computeNativeCrop(roi, 480, 640, InputImageRotation.rotation90deg);
      expect(crop, const NativeCrop(0, 0, 480, 640));
    });

    test('rotation90: partial upright ROI rotates into a native strip', () {
      const roi = Roi(left: 0, top: 0, width: 0.5, height: 1);
      final crop = computeNativeCrop(roi, 480, 640, InputImageRotation.rotation90deg);
      // Left-half/full-height upright region -> bottom native strip.
      expect(crop, const NativeCrop(0, 320, 480, 320));
    });

    test('origin and extents are even-aligned for NV21', () {
      // Fractions chosen to produce odd pixel bounds before alignment.
      const roi = Roi(left: 0.1, top: 0.1, width: 0.3, height: 0.3);
      final crop = computeNativeCrop(roi, 481, 641, InputImageRotation.rotation0deg);
      expect(crop, isNotNull);
      expect(crop!.x.isEven, isTrue);
      expect(crop.y.isEven, isTrue);
      expect(crop.width.isEven, isTrue);
      expect(crop.height.isEven, isTrue);
      expect(crop.x + crop.width <= 481, isTrue);
      expect(crop.y + crop.height <= 641, isTrue);
    });

    test('degenerate ROI returns null (caller falls back to full frame)', () {
      const roi = Roi(left: 0.4, top: 0.4, width: 0, height: 0.2);
      expect(
        computeNativeCrop(roi, 480, 640, InputImageRotation.rotation0deg),
        isNull,
      );
    });
  });

  group('uprightSize', () {
    test('0/180 keep dimensions', () {
      expect(uprightSize(480, 640, InputImageRotation.rotation0deg),
          const Size(480, 640));
      expect(uprightSize(480, 640, InputImageRotation.rotation180deg),
          const Size(480, 640));
    });
    test('90/270 swap dimensions', () {
      expect(uprightSize(480, 640, InputImageRotation.rotation90deg),
          const Size(640, 480));
      expect(uprightSize(480, 640, InputImageRotation.rotation270deg),
          const Size(640, 480));
    });
  });

  group('cropNv21', () {
    test('crops Y and interleaved VU planes correctly', () {
      // 4x4 NV21: Y = 0..15, VU = 16..23.
      final src = Uint8List.fromList(List<int>.generate(24, (i) => i));
      final out = cropNv21(src, 4, 4, const NativeCrop(2, 2, 2, 2));
      expect(out.width, 2);
      expect(out.height, 2);
      expect(out.bytesPerRow, 2);
      // Y rows 2,3 cols 2,3 => 10,11,14,15 ; VU row 1 cols 2,3 => 22,23.
      expect(out.bytes, Uint8List.fromList([10, 11, 14, 15, 22, 23]));
    });
  });

  group('cropBgra8888', () {
    test('crops a 4-byte-per-pixel buffer with correct stride', () {
      // 3x3 BGRA: 36 bytes, stride 12.
      final src = Uint8List.fromList(List<int>.generate(36, (i) => i));
      final out = cropBgra8888(src, 12, const NativeCrop(1, 1, 2, 2));
      expect(out.width, 2);
      expect(out.height, 2);
      expect(out.bytesPerRow, 8);
      // Row1: bytes 16..23 ; Row2: bytes 28..35.
      expect(
        out.bytes,
        Uint8List.fromList([16, 17, 18, 19, 20, 21, 22, 23, 28, 29, 30, 31, 32, 33, 34, 35]),
      );
    });
  });
}
