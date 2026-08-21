import 'dart:ui';

/// Region Of Interest, expressed as fractions (0..1) of the preview so it is
/// resolution-independent. Only faces overlapping this region are treated as
/// "detected" — the Flutter counterpart of the RN `roi = {x, y, width, height}`
/// used to restrict processing to a sub-region of the frame.
class Roi {
  const Roi({
    this.left = 0.175,
    this.top = 0.25,
    this.width = 0.65,
    this.height = 0.45,
  });

  /// Left edge as a fraction of the preview width.
  final double left;

  /// Top edge as a fraction of the preview height.
  final double top;

  /// Width as a fraction of the preview width.
  final double width;

  /// Height as a fraction of the preview height.
  final double height;

  /// Resolves this fractional ROI to an absolute [Rect] for [canvasSize].
  Rect toRect(Size canvasSize) => Rect.fromLTWH(
        left * canvasSize.width,
        top * canvasSize.height,
        width * canvasSize.width,
        height * canvasSize.height,
      );
}

/// Faithful port of the RN `isFaceInROI` axis-aligned bounding-box overlap
/// test. Returns `true` when [face] intersects [roi] (touching counts as
/// inside), and `false` only when the two boxes are fully disjoint.
///
/// ```
/// return !(faceRight < roiLeft ||
///          faceLeft  > roiRight ||
///          faceBottom < roiTop  ||
///          faceTop   > roiBottom);
/// ```
bool isFaceInRoi(Rect face, Rect roi) {
  return !(face.right < roi.left ||
      face.left > roi.right ||
      face.bottom < roi.top ||
      face.top > roi.bottom);
}
