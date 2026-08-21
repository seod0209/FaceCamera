import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'roi.dart';

/// A rectangle in the native (pre-rotation) camera-buffer coordinate space.
/// All fields are even, so the region is valid for NV21 chroma subsampling.
class NativeCrop {
  const NativeCrop(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is NativeCrop &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'NativeCrop($x, $y, $width, $height)';
}

/// Cropped frame bytes plus the metadata ML Kit needs to interpret them.
class CroppedFrame {
  const CroppedFrame({
    required this.bytes,
    required this.bytesPerRow,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int bytesPerRow;
  final int width;
  final int height;
}

/// Maps an upright-space point back into the native buffer, inverting the
/// clockwise rotation ML Kit applies to make the frame upright.
Offset _uprightToNative(
  double x,
  double y,
  int w,
  int h,
  InputImageRotation rotation,
) {
  switch (rotation) {
    case InputImageRotation.rotation0deg:
      return Offset(x, y);
    case InputImageRotation.rotation90deg:
      return Offset(y, h - x);
    case InputImageRotation.rotation180deg:
      return Offset(w - x, h - y);
    case InputImageRotation.rotation270deg:
      return Offset(w - y, x);
  }
}

/// Computes the native-buffer rectangle that, after rotation, corresponds to
/// [roi] on the upright preview. Returns `null` when the resolved region is
/// degenerate (so the caller can fall back to full-frame detection).
///
/// The result is even-aligned and clamped to the buffer, satisfying NV21's
/// requirement that crop origin and size be multiples of two.
NativeCrop? computeNativeCrop(
  Roi roi,
  int imageWidth,
  int imageHeight,
  InputImageRotation rotation,
) {
  final swap = rotation == InputImageRotation.rotation90deg ||
      rotation == InputImageRotation.rotation270deg;
  final uw = (swap ? imageHeight : imageWidth).toDouble();
  final uh = (swap ? imageWidth : imageHeight).toDouble();

  final ul = roi.left * uw;
  final ut = roi.top * uh;
  final ur = (roi.left + roi.width) * uw;
  final ub = (roi.top + roi.height) * uh;

  final p1 = _uprightToNative(ul, ut, imageWidth, imageHeight, rotation);
  final p2 = _uprightToNative(ur, ub, imageWidth, imageHeight, rotation);

  final nx1 = math.min(p1.dx, p2.dx);
  final ny1 = math.min(p1.dy, p2.dy);
  final nx2 = math.max(p1.dx, p2.dx);
  final ny2 = math.max(p1.dy, p2.dy);

  var x = nx1.floor();
  var y = ny1.floor();
  var w = (nx2 - nx1).round();
  var h = (ny2 - ny1).round();

  // Even-align origin (round down) and clamp to the buffer.
  x -= x & 1;
  y -= y & 1;
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x >= imageWidth || y >= imageHeight) return null;
  if (x + w > imageWidth) w = imageWidth - x;
  if (y + h > imageHeight) h = imageHeight - y;
  // Even-align extents (round down).
  w -= w & 1;
  h -= h & 1;
  if (w <= 0 || h <= 0) return null;

  return NativeCrop(x, y, w, h);
}

/// Upright dimensions of a native [w]x[h] buffer after [rotation] is applied.
Size uprightSize(int w, int h, InputImageRotation rotation) {
  final swap = rotation == InputImageRotation.rotation90deg ||
      rotation == InputImageRotation.rotation270deg;
  return swap ? Size(h.toDouble(), w.toDouble()) : Size(w.toDouble(), h.toDouble());
}

/// Crops an NV21 buffer (Y plane followed by interleaved VU) to [crop].
///
/// Output layout is again NV21: `width*height` luma bytes followed by
/// `width*height/2` chroma bytes, with row stride == width.
CroppedFrame cropNv21(
  Uint8List src,
  int width,
  int height,
  NativeCrop crop,
) {
  final cw = crop.width;
  final ch = crop.height;
  final out = Uint8List(cw * ch + cw * ch ~/ 2);

  var o = 0;
  // Luma.
  for (var row = 0; row < ch; row++) {
    final srcStart = (crop.y + row) * width + crop.x;
    out.setRange(o, o + cw, src, srcStart);
    o += cw;
  }
  // Interleaved VU: half the rows, chroma subsampled 2x vertically.
  final vuBase = width * height;
  for (var row = 0; row < ch ~/ 2; row++) {
    final srcStart = vuBase + (crop.y ~/ 2 + row) * width + crop.x;
    out.setRange(o, o + cw, src, srcStart);
    o += cw;
  }

  return CroppedFrame(bytes: out, bytesPerRow: cw, width: cw, height: ch);
}

/// Crops a BGRA8888 buffer to [crop]. Output row stride == width*4.
CroppedFrame cropBgra8888(
  Uint8List src,
  int srcBytesPerRow,
  NativeCrop crop,
) {
  final cw = crop.width;
  final ch = crop.height;
  final rowBytes = cw * 4;
  final out = Uint8List(rowBytes * ch);

  var o = 0;
  for (var row = 0; row < ch; row++) {
    final srcStart = (crop.y + row) * srcBytesPerRow + crop.x * 4;
    out.setRange(o, o + rowBytes, src, srcStart);
    o += rowBytes;
  }

  return CroppedFrame(bytes: out, bytesPerRow: rowBytes, width: cw, height: ch);
}
