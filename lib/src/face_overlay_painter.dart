import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'roi.dart';

/// Renders the face-guide overlay and detected faces.
///
/// Faces are reported in [detSize] coordinates (the upright ML Kit space of the
/// region that was actually fed to the detector). That region maps onto the
/// [detFraction] sub-rectangle of the preview, so a face point is placed by
/// normalizing within [detSize] and scaling into that sub-rectangle — with a
/// horizontal flip for the mirrored front camera.
class FaceOverlayPainter extends CustomPainter {
  FaceOverlayPainter({
    required this.faces,
    required this.detSize,
    required this.detFraction,
    required this.roi,
    required this.lensDirection,
  });

  final List<Face> faces;
  final Size detSize;
  final Rect detFraction; // fraction (0..1) of preview the detector saw
  final Roi roi;
  final CameraLensDirection lensDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final roiRect = roi.toRect(size);
    final anyFaceInRoi = _drawFaces(canvas, size, roiRect);
    _drawGuide(canvas, size, roiRect, active: anyFaceInRoi);
  }

  /// Dim everything outside the ROI and stroke an oval face guide inside it.
  void _drawGuide(Canvas canvas, Size size, Rect roiRect, {required bool active}) {
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

  /// Draws detected faces; returns whether any face lies within the ROI.
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
      final rect = _mapFace(face.boundingBox, region);
      final inRoi = isFaceInRoi(rect, roiRect);
      any = any || inRoi;
      canvas.drawRect(rect, inRoi ? inside : outside);
    }
    return any;
  }

  Rect _mapFace(Rect box, Rect region) {
    final nx1 = box.left / detSize.width;
    final nx2 = box.right / detSize.width;
    final ny1 = box.top / detSize.height;
    final ny2 = box.bottom / detSize.height;

    final double sx1;
    final double sx2;
    if (lensDirection == CameraLensDirection.front) {
      // Preview is mirrored; flip X so overlay tracks the visible face.
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
        old.detSize != detSize ||
        old.detFraction != detFraction;
  }
}
