import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'coordinates_translator.dart';
import 'roi.dart';

/// Renders the face-guide overlay and detected faces.
///
/// Two mapping modes:
///  - Full frame (`cropMode == false`): faces are in full-image coordinates and
///    mapped with the official [translateX]/[translateY] (correct on iOS too).
///  - ROI crop (`cropMode == true`): faces are in the cropped upright space
///    ([detSize]); mapped by normalizing into the [detFraction] sub-rectangle.
class FaceOverlayPainter extends CustomPainter {
  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    required this.roi,
    required this.showGuide,
    required this.cropMode,
    required this.detSize,
    required this.detFraction,
  });

  final List<Face> faces;
  final Size imageSize; // raw buffer size (full-frame mapping)
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final Roi roi;
  final bool showGuide;
  final bool cropMode;
  final Size detSize; // cropped upright dims (crop mode)
  final Rect detFraction; // fraction of preview the detector saw (crop mode)

  @override
  void paint(Canvas canvas, Size size) {
    final roiRect = roi.toRect(size);
    final anyFaceInRoi = _drawFaces(canvas, size, roiRect);
    if (showGuide) _drawGuide(canvas, size, roiRect, active: anyFaceInRoi);
  }

  void _drawGuide(Canvas canvas, Size size, Rect roiRect,
      {required bool active}) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, scrim);
    canvas.drawOval(roiRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawOval(
      roiRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = active ? Colors.greenAccent : Colors.white70,
    );
  }

  bool _drawFaces(Canvas canvas, Size size, Rect roiRect) {
    final region = Rect.fromLTRB(
      detFraction.left * size.width,
      detFraction.top * size.height,
      detFraction.right * size.width,
      detFraction.bottom * size.height,
    );

    final inside = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.greenAccent;
    final outside = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white54;

    var any = false;
    for (final face in faces) {
      final rect = cropMode
          ? _mapCropped(face.boundingBox, region)
          : _mapFullFrame(face.boundingBox, size);
      final inRoi = isFaceInRoi(rect, roiRect);
      any = any || inRoi;
      canvas.drawRect(rect, inRoi ? inside : outside);
    }
    return any;
  }

  /// Full-frame: official translator (handles rotation + iOS/Android + mirror).
  Rect _mapFullFrame(Rect box, Size size) {
    final l = translateX(box.left, size, imageSize, rotation, lensDirection);
    final r = translateX(box.right, size, imageSize, rotation, lensDirection);
    final t = translateY(box.top, size, imageSize, rotation, lensDirection);
    final b = translateY(box.bottom, size, imageSize, rotation, lensDirection);
    return Rect.fromLTRB(
      l < r ? l : r,
      t < b ? t : b,
      l < r ? r : l,
      t < b ? b : t,
    );
  }

  /// Crop mode: normalize within the cropped detector space, place into the ROI
  /// region, flip X for the mirrored front camera.
  Rect _mapCropped(Rect box, Rect region) {
    final nx1 = box.left / detSize.width;
    final nx2 = box.right / detSize.width;
    final ny1 = box.top / detSize.height;
    final ny2 = box.bottom / detSize.height;

    final double sx1;
    final double sx2;
    if (lensDirection == CameraLensDirection.front) {
      sx1 = region.right - nx2 * region.width;
      sx2 = region.right - nx1 * region.width;
    } else {
      sx1 = region.left + nx1 * region.width;
      sx2 = region.left + nx2 * region.width;
    }
    final sy1 = region.top + ny1 * region.height;
    final sy2 = region.top + ny2 * region.height;
    return Rect.fromLTRB(sx1, sy1, sx2, sy2);
  }

  @override
  bool shouldRepaint(FaceOverlayPainter old) {
    return old.faces != faces ||
        old.imageSize != imageSize ||
        old.rotation != rotation ||
        old.cropMode != cropMode ||
        old.showGuide != showGuide;
  }
}
