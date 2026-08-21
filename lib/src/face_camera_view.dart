import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_overlay_painter.dart';
import 'frame_crop.dart';
import 'roi.dart';

/// Result of turning a [CameraImage] into a detector-ready input.
class _Prepared {
  const _Prepared({
    required this.input,
    required this.detSize,
    required this.detFraction,
    required this.sourceSize,
    required this.cropSize,
  });

  final InputImage input;

  /// Upright coordinate space of the region fed to the detector.
  final Size detSize;

  /// Fraction (0..1) of the preview that region covers.
  final Rect detFraction;

  /// Native buffer dimensions (for the stats banner).
  final Size sourceSize;

  /// Cropped region dimensions, or null when detection ran on the full frame.
  final Size? cropSize;
}

/// Live front-camera preview with a face guide and throttled, ROI-cropped
/// face detection.
///
/// Optimizations ported from the RN (vision-camera) implementation:
///  1. ROI restriction     — the frame is cropped to the guide region
///     ([computeNativeCrop] + [cropNv21]/[cropBgra8888]) so ML Kit scans far
///     fewer pixels. This is the real compute saver.
///  2. Frequency throttling — detection runs at most once per
///     [_detectionInterval] (the Flutter analog of `frameProcessorFps`).
///  3. In-ROI detection     — [isFaceInRoi] confirms faces sit in the guide.
class FaceCameraView extends StatefulWidget {
  const FaceCameraView({super.key});

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView>
    with WidgetsBindingObserver {
  static const Roi _roi = Roi();

  /// Detection runs at most once per this interval (blog used 500ms).
  static const Duration _detectionInterval = Duration(milliseconds: 500);

  static const Rect _fullFraction = Rect.fromLTRB(0, 0, 1, 1);

  /// Device orientation -> rotation compensation angle (Android).
  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  CameraController? _controller;
  CameraDescription? _camera;

  bool _isBusy = false;
  int _lastDetectionMs = 0;

  List<Face> _faces = const [];
  Size _detSize = const Size(1, 1);
  Rect _detFraction = _fullFraction;
  Size? _sourceSize;
  Size? _cropSize;

  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = '사용 가능한 카메라가 없습니다.');
        return;
      }
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      await controller.startImageStream(_onFrame);
      setState(() {});
    } catch (e) {
      setState(() => _error = '카메라 초기화 실패: $e');
    }
  }

  /// Per-frame callback: throttle + busy guard, then crop-and-detect.
  Future<void> _onFrame(CameraImage image) async {
    if (_isBusy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDetectionMs < _detectionInterval.inMilliseconds) return;
    _lastDetectionMs = now;

    final prepared = _prepare(image);
    if (prepared == null) return;

    _isBusy = true;
    try {
      final faces = await _faceDetector.processImage(prepared.input);
      if (!mounted) return;
      setState(() {
        _faces = faces;
        _detSize = prepared.detSize;
        _detFraction = prepared.detFraction;
        _sourceSize = prepared.sourceSize;
        _cropSize = prepared.cropSize;
      });
    } catch (_) {
      // Ignore transient decode/detection errors; next frame retries.
    } finally {
      _isBusy = false;
    }
  }

  _Prepared? _prepare(CameraImage image) {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final rotation = _resolveRotation(camera, controller);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    final sourceSize = Size(image.width.toDouble(), image.height.toDouble());

    // (b) ROI crop: feed only the guide region to ML Kit when possible.
    try {
      final crop = computeNativeCrop(_roi, image.width, image.height, rotation);
      if (crop != null) {
        final cropped = Platform.isAndroid
            ? cropNv21(plane.bytes, image.width, image.height, crop)
            : cropBgra8888(plane.bytes, plane.bytesPerRow, crop);
        return _Prepared(
          input: InputImage.fromBytes(
            bytes: cropped.bytes,
            metadata: InputImageMetadata(
              size: Size(cropped.width.toDouble(), cropped.height.toDouble()),
              rotation: rotation,
              format: format,
              bytesPerRow: cropped.bytesPerRow,
            ),
          ),
          detSize: uprightSize(cropped.width, cropped.height, rotation),
          detFraction: Rect.fromLTWH(
            _roi.left,
            _roi.top,
            _roi.width,
            _roi.height,
          ),
          sourceSize: sourceSize,
          cropSize: Size(cropped.width.toDouble(), cropped.height.toDouble()),
        );
      }
    } catch (_) {
      // Fall through to full-frame detection below.
    }

    // Fallback: full-frame detection.
    return _Prepared(
      input: InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: sourceSize,
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      ),
      detSize: uprightSize(image.width, image.height, rotation),
      detFraction: _fullFraction,
      sourceSize: sourceSize,
      cropSize: null,
    );
  }

  InputImageRotation? _resolveRotation(
    CameraDescription camera,
    CameraController controller,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    final compensation = _orientationDegrees[controller.value.deviceOrientation];
    if (compensation == null) return null;
    final rotationCompensation =
        camera.lensDirection == CameraLensDirection.front
            ? (sensorOrientation + compensation) % 360
            : (sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(rotationCompensation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('FaceCamera')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CameraPreview(
            controller,
            child: CustomPaint(
              painter: FaceOverlayPainter(
                faces: _faces,
                detSize: _detSize,
                detFraction: _detFraction,
                roi: _roi,
                lensDirection:
                    _camera?.lensDirection ?? CameraLensDirection.front,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: _StatsBanner(
              faceCount: _faces.length,
              sourceSize: _sourceSize,
              cropSize: _cropSize,
              intervalMs: _detectionInterval.inMilliseconds,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({
    required this.faceCount,
    required this.sourceSize,
    required this.cropSize,
    required this.intervalMs,
  });

  final int faceCount;
  final Size? sourceSize;
  final Size? cropSize;
  final int intervalMs;

  @override
  Widget build(BuildContext context) {
    final src = sourceSize;
    final crop = cropSize;
    final String region;
    if (crop != null && src != null) {
      final srcPx = (src.width * src.height).round();
      final cropPx = (crop.width * crop.height).round();
      final pct = srcPx == 0 ? 0 : (100 * cropPx / srcPx).round();
      region = '인식영역 ${crop.width.toInt()}×${crop.height.toInt()} '
          '(원본의 $pct%)';
    } else {
      region = '전체 프레임 인식';
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '얼굴 $faceCount · $region · ${intervalMs}ms 주기',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
