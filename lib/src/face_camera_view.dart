import 'dart:async';
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
    required this.cropMode,
    required this.imageSize,
    required this.rotation,
    required this.detSize,
    required this.detFraction,
    required this.cropSize,
  });

  final InputImage input;
  final bool cropMode;
  final Size imageSize; // raw buffer size
  final InputImageRotation rotation;
  final Size detSize; // cropped upright dims (crop mode)
  final Rect detFraction; // fraction of preview the detector saw
  final Size? cropSize; // cropped region dims, null on full frame
}

/// Live front-camera preview with a face guide and throttled face detection.
///
/// Ported from the RN (vision-camera) optimization write-up:
///  - Frequency throttling — detection runs at most once per
///    [_detectionInterval] (the Flutter analog of `frameProcessorFps`).
///  - ROI crop (toggle) — feeds only the guide region to ML Kit, cutting the
///    per-inference time. The effect is visible in the "감지 Nms" readout, not
///    in preview FPS (detection runs async and never blocks the preview).
///  - In-ROI detection — [isFaceInRoi] highlights faces inside the guide.
class FaceCameraView extends StatefulWidget {
  const FaceCameraView({super.key});

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView>
    with WidgetsBindingObserver {
  static const Roi _roi = Roi();

  /// Detection cadence. Short enough to track a moving face smoothly while
  /// still throttling well below the ~30fps camera stream.
  static const Duration _detectionInterval = Duration(milliseconds: 100);

  static const Rect _fullFraction = Rect.fromLTRB(0, 0, 1, 1);

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
  bool _starting = false;

  // Feature toggles.
  bool _showGuide = true;
  bool _useCrop = false;

  // Detection state.
  List<Face> _faces = const [];
  bool _cropMode = false;
  Size _imageSize = const Size(1, 1);
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  Size _detSize = const Size(1, 1);
  Rect _detFraction = _fullFraction;
  Size? _cropSize;

  // Metrics.
  int _frameCount = 0;
  double _fps = 0;
  double _detMs = 0;
  Timer? _fpsTimer;

  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _startFpsMeter();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      await _disposeController();

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
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream(_onFrame);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // Publish only once fully live, so CameraPreview never sees an
      // uninitialized or disposed controller.
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '카메라 초기화 실패: $e');
    } finally {
      _starting = false;
    }
  }

  /// Samples the camera frame-arrival rate twice a second (camcorder-style).
  void _startFpsMeter() {
    _fpsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final fps = _frameCount * 2; // frames in 500ms -> per second
      _frameCount = 0;
      setState(() => _fps = fps.toDouble());
    });
  }

  Future<void> _onFrame(CameraImage image) async {
    _frameCount++;
    if (_isBusy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDetectionMs < _detectionInterval.inMilliseconds) return;
    _lastDetectionMs = now;

    final prepared = _prepare(image);
    if (prepared == null) return;

    _isBusy = true;
    try {
      final sw = Stopwatch()..start();
      final faces = await _faceDetector.processImage(prepared.input);
      sw.stop();
      if (!mounted) return;
      final ms = sw.elapsedMicroseconds / 1000.0;
      setState(() {
        _faces = faces;
        _cropMode = prepared.cropMode;
        _imageSize = prepared.imageSize;
        _rotation = prepared.rotation;
        _detSize = prepared.detSize;
        _detFraction = prepared.detFraction;
        _cropSize = prepared.cropSize;
        // Exponential moving average smooths the readout.
        _detMs = _detMs == 0 ? ms : _detMs * 0.7 + ms * 0.3;
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

    if (_useCrop) {
      try {
        final crop =
            computeNativeCrop(_roi, image.width, image.height, rotation);
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
            cropMode: true,
            imageSize: sourceSize,
            rotation: rotation,
            detSize: uprightSize(cropped.width, cropped.height, rotation),
            detFraction:
                Rect.fromLTWH(_roi.left, _roi.top, _roi.width, _roi.height),
            cropSize: Size(cropped.width.toDouble(), cropped.height.toDouble()),
          );
        }
      } catch (_) {
        // Fall through to full-frame.
      }
    }

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
      cropMode: false,
      imageSize: sourceSize,
      rotation: rotation,
      detSize: uprightSize(image.width, image.height, rotation),
      detFraction: _fullFraction,
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
    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  /// Tears down the active controller. Nulls + rebuilds FIRST so the old
  /// CameraPreview leaves the tree before dispose() fires its value
  /// notification (which would otherwise rebuild a disposed controller).
  Future<void> _disposeController() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    if (mounted) setState(() {});
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fpsTimer?.cancel();
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('FaceCamera'),
        actions: [
          IconButton(
            tooltip: 'ROI 크롭(성능)',
            icon: Icon(_useCrop ? Icons.crop : Icons.crop_free),
            onPressed: () => setState(() => _useCrop = !_useCrop),
          ),
          IconButton(
            tooltip: '얼굴 가이드 표시',
            icon: Icon(
              _showGuide
                  ? Icons.face_retouching_natural
                  : Icons.face_retouching_off,
            ),
            onPressed: () => setState(() => _showGuide = !_showGuide),
          ),
        ],
      ),
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
                imageSize: _imageSize,
                rotation: _rotation,
                lensDirection:
                    _camera?.lensDirection ?? CameraLensDirection.front,
                roi: _roi,
                showGuide: _showGuide,
                cropMode: _cropMode,
                detSize: _detSize,
                detFraction: _detFraction,
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: _MetricsHud(
              fps: _fps,
              detMs: _detMs,
              useCrop: _useCrop,
              cropSize: _cropSize,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: _StatsBanner(
              faceCount: _faces.length,
              intervalMs: _detectionInterval.inMilliseconds,
            ),
          ),
        ],
      ),
    );
  }
}

/// Camcorder-style HUD: camera FPS plus the per-inference time (the metric the
/// ROI optimization actually moves).
class _MetricsHud extends StatelessWidget {
  const _MetricsHud({
    required this.fps,
    required this.detMs,
    required this.useCrop,
    required this.cropSize,
  });

  final double fps;
  final double detMs;
  final bool useCrop;
  final Size? cropSize;

  @override
  Widget build(BuildContext context) {
    final crop = cropSize;
    final mode = useCrop
        ? (crop != null
            ? 'ROI 크롭 ${crop.width.toInt()}×${crop.height.toInt()}'
            : 'ROI 크롭')
        : '전체 프레임';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${fps.toStringAsFixed(0)} FPS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '감지 ${detMs.toStringAsFixed(1)}ms'
            '${detMs > 0 ? ' (~${(1000 / detMs).round()} fps)' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Text(
            mode,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({required this.faceCount, required this.intervalMs});

  final int faceCount;
  final int intervalMs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '얼굴 $faceCount · ${intervalMs}ms 주기',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
