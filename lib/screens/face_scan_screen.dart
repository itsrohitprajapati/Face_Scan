import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/embedding_service.dart';
import '../theme.dart';
import 'result_screen.dart';

/// Continuous 360° head-rotation capture, Face-ID style: the user slowly
/// tilts/turns their head in a circle (either clockwise or anticlockwise —
/// direction is detected automatically from the first movement) and a
/// ring fills in as they sweep through it. Haptics tick on every segment
/// and pulse harder every quarter turn and on completion.
class FaceScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FaceScanScreen({super.key, required this.cameras});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  late final FaceDetector _faceDetector;
  late final AnimationController _glowController;
  bool _busy = false;
  bool _finishing = false;
  String _hint = 'Center your face, then slowly rotate your head';

  // --- Circular rotation tracking -------------------------------------
  static const int segments = 12; // like clock positions, 30° apart
  static const double segmentDegrees = 360.0 / segments;
  // Normalizes the (elliptical) yaw/pitch range a head can comfortably
  // reach into a circle so every direction is equally reachable.
  static const double maxYaw = 38.0;
  static const double maxPitch = 26.0;
  static const double minRadiusToTrack = 0.55; // must lean toward the rim

  double? _lastRawAngleDeg; // last frame's clock angle, 0..360
  double _unwrappedDeg = 0; // signed cumulative rotation, target ±360
  int _lastSegmentTicked = 0;
  int? _direction; // +1 clockwise, -1 anticlockwise, null = not yet decided

  final List<img.Image> _capturedCrops = [];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: false,
        enableClassification: false,
        minFaceSize: 0.25,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final front = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
      Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() => _controller = controller);
    await controller.startImageStream(_onFrame);
  }

  double get _progress => (_unwrappedDeg.abs() / 360.0).clamp(0.0, 1.0);

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _finishing || _controller == null) return;
    _busy = true;
    try {
      final camera = _controller!.description;
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final inputImage = _toInputImage(image, rotation);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        setState(() => _hint = 'No face detected — center your face');
        return;
      }
      final face = faces.first;
      final yaw = face.headEulerAngleY ?? 0; // left(-)/right(+)
      final pitch = face.headEulerAngleX ?? 0; // down(-)/up(+)

      // Normalize onto an ellipse -> circle so left/right/up/down are
      // all equally reachable, then read it as a clock angle: 0° = 12
      // o'clock (up), increasing clockwise through 3 o'clock (right).
      final nx = (yaw / maxYaw).clamp(-1.5, 1.5);
      final ny = (pitch / maxPitch).clamp(-1.5, 1.5);
      final radius = math.sqrt(nx * nx + ny * ny);

      if (radius < minRadiusToTrack) {
        setState(() => _hint = _direction == null
            ? 'Lean your head toward the edge of the circle, then rotate'
            : 'Keep tracing the circle — don\'t come back to center yet');
        return;
      }

      final rawAngle = (math.atan2(nx, ny) * 180 / math.pi + 360) % 360;

      if (_lastRawAngleDeg != null) {
        var delta = rawAngle - _lastRawAngleDeg!;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        _unwrappedDeg += delta;

        // Lock in a direction once movement is unambiguous, purely so
        // we can show a clear "keep going clockwise/anticlockwise" hint.
        if (_direction == null && _unwrappedDeg.abs() > 12) {
          _direction = _unwrappedDeg > 0 ? 1 : -1;
          HapticFeedback.lightImpact();
        }
      }
      _lastRawAngleDeg = rawAngle;

      // Fire a haptic tick + capture a pose crop every time we cross a
      // new 30° segment of the sweep.
      final segmentIndex = (_unwrappedDeg.abs() / segmentDegrees).floor();
      if (segmentIndex > _lastSegmentTicked && segmentIndex <= segments) {
        _lastSegmentTicked = segmentIndex;
        if (segmentIndex % 3 == 0) {
          HapticFeedback.mediumImpact(); // every quarter turn
        } else {
          HapticFeedback.selectionClick(); // every 30°
        }
        final crop = _cropFace(image, face.boundingBox, rotation);
        if (crop != null) _capturedCrops.add(crop);
      }

      final dirWord = _direction == null
          ? ''
          : (_direction == 1 ? 'anticlockwise' : 'clockwise');
      setState(() {
        _hint = _progress >= 1.0
            ? 'Full rotation captured!'
            : 'Keep rotating $dirWord — ${(_progress * 100).round()}%';
      });

      if (_progress >= 1.0) {
        await _finishScan();
      }
    } catch (e, st) {
      debugPrint('Face detection frame error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<void> _finishScan() async {
    _finishing = true;
    HapticFeedback.heavyImpact();
    await _controller?.stopImageStream();
    await EmbeddingService.instance.load();
    final embedding =
    EmbeddingService.instance.embedFromMultiplePoses(_capturedCrops);
    EmbeddingService.instance.printEmbedding(embedding);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(embedding: embedding, poseCount: _capturedCrops.length),
      ),
    );
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Best-effort crop of the detected face region out of the raw camera
  /// frame so it can be fed to the embedding model.
  img.Image? _cropFace(CameraImage image, Rect box, InputImageRotation rotation) {
    try {
      final converted = _yuv420ToImage(image);
      if (converted == null) return null;
      final x = box.left.clamp(0, converted.width - 1).toInt();
      final y = box.top.clamp(0, converted.height - 1).toInt();
      final w = box.width.clamp(1, converted.width - x).toInt();
      final h = box.height.clamp(1, converted.height - y).toInt();
      return img.copyCrop(converted, x: x, y: y, width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  img.Image? _yuv420ToImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: plane.bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    }
    // On Android the stream is requested as NV21, which
    // camera_android_camerax delivers as a SINGLE plane (the Y bytes
    // followed by an interleaved V/U block) — NOT the three separate
    // Y/U/V planes of raw YUV_420_888. The previous code assumed three
    // planes and hit a RangeError on planes[1] for every frame, so every
    // crop came back null, _capturedCrops stayed empty, and the averaged
    // embedding was built from zero poses -> all-zeros. Handle the
    // single-plane NV21 case explicitly.
    if (image.planes.length == 1 ||
        image.format.group == ImageFormatGroup.nv21) {
      return _nv21ToImage(image);
    }

    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length < 3) {
      return null;
    }
    return _yuv420ThreePlaneToImage(image);
  }

  /// Decodes a single-plane NV21 buffer (Y plane + interleaved VU) to RGB.
  img.Image _nv21ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final bytes = image.planes.first.bytes;
    // Y rows are packed at this stride; the interleaved VU block starts
    // immediately after the Y plane.
    final yRowStride =
        image.planes.first.bytesPerRow == 0 ? width : image.planes.first.bytesPerRow;
    final uvStart = yRowStride * height;

    final out = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      final yRow = y * yRowStride;
      final uvRow = uvStart + (y >> 1) * yRowStride;
      for (var x = 0; x < width; x++) {
        final yVal = bytes[yRow + x];
        final uvIndex = uvRow + (x >> 1) * 2;
        // NV21 interleaves V before U; default to neutral chroma if the
        // buffer is shorter than expected so we never throw here.
        var vVal = 128;
        var uVal = 128;
        if (uvIndex + 1 < bytes.length) {
          vVal = bytes[uvIndex];
          uVal = bytes[uvIndex + 1];
        }
        final r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
        final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
            .clamp(0, 255)
            .toInt();
        final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  /// Fallback for genuine 3-plane YUV_420_888 frames (older camera
  /// backends that don't pre-convert to NV21).
  img.Image _yuv420ThreePlaneToImage(CameraImage image) {
    final out = img.Image(width: image.width, height: image.height);
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var yPos = 0; yPos < image.height; yPos++) {
      for (var xPos = 0; xPos < image.width; xPos++) {
        final uvIndex =
            uvPixelStride * (xPos ~/ 2) + uvRowStride * (yPos ~/ 2);
        final yIndex = yPos * yPlane.bytesPerRow + xPos;
        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];
        final r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
        final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
            .clamp(0, 255)
            .toInt();
        final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
        out.setPixelRgb(xPos, yPos, r, g, b);
      }
    }
    return out;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Face Scan', style: TextStyle(color: Colors.black, fontSize: 20)),
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator(color: AppColors.green))
          : Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraLayer(controller),
          _buildVignette(),
          _buildOverlay(),
        ],
      ),
    );
  }

  /// Fills the screen with the camera feed WITHOUT stretching it. A raw
  /// `CameraPreview` inside `StackFit.expand` gets forced to the screen's
  /// aspect ratio and looks distorted (faces stretched wide/tall). This
  /// instead scales the preview uniformly ("cover" behavior, like
  /// CSS `object-fit: cover`) so proportions stay correct and any excess
  /// is cropped off-screen instead of squashed.
  Widget _buildCameraLayer(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final previewSize = controller.value.previewSize!;
        // previewSize is reported in landscape (width > height) terms
        // even when the device is in portrait, so swap for portrait use.
        final previewAspect = previewSize.height / previewSize.width;

        var scale = screenSize.aspectRatio / previewAspect;
        if (scale < 1) scale = 1 / scale;

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: previewAspect,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Soft dark gradient at the top/bottom edges so the white progress
  /// text and hint pill sit on readable contrast instead of a raw,
  /// unedited camera feed — a small touch that reads as "product", not
  /// "debug view".
  Widget _buildVignette() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.45),
            ],
            stops: const [0.0, 0.22, 0.68, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return SafeArea(
      child: Center(
        child: Column(
          children: [
            const Spacer(),
            SizedBox(
              width: 280,
              height: 280,
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (context, _) => CustomPaint(
                  painter: _RotationRingPainter(
                    unwrappedDeg: _unwrappedDeg,
                    direction: _direction,
                    color: AppColors.green,
                    trackColor: Colors.white24,
                    pulse: _glowController.value,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line.withValues(alpha: 0.3)),
              ),
              child: Text(
                _hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a smooth, continuously flowing progress ring (no discrete
/// segments): a soft blurred glow underneath a gradient trail that fades
/// from dim at the start to a bright glowing "comet head" at the current
/// position, plus a small direction arrow once one has been picked.
/// [pulse] (0..1, looping) subtly breathes the glow so the ring feels
/// alive even between camera frames, not just when progress changes.
class _RotationRingPainter extends CustomPainter {
  final double unwrappedDeg;
  final int? direction;
  final Color color;
  final Color trackColor;
  final double pulse;

  _RotationRingPainter({
    required this.unwrappedDeg,
    required this.direction,
    required this.color,
    required this.trackColor,
    required this.pulse,
  });

  static const double _startAngle = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final progress = (unwrappedDeg.abs() / 360.0).clamp(0.0, 1.0);
    final sweepSign = unwrappedDeg >= 0 ? -1.0 : 1.0;
    final totalSweep = progress * 2 * math.pi * sweepSign;

    // Faint full-circle track underneath everything.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0) return;

    // Soft blurred glow following the whole trail — this is what gives
    // the ring a "glowing" look rather than a flat colored line.
    canvas.drawArc(
      rect,
      _startAngle,
      totalSweep,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.30 + 0.18 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16 + 5 * pulse
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 3 * pulse),
    );

    // Crisp trail on top, built from many tiny arcs whose alpha ramps
    // from dim (tail, near the 12 o'clock start) to fully bright (head,
    // the current position) — a continuous flowing fade rather than
    // fixed segments.
    const steps = 72;
    final stepSweep = totalSweep / steps;
    for (var i = 0; i < steps; i++) {
      final t = (i + 1) / steps; // 0..1 along the trail
      canvas.drawArc(
        rect,
        _startAngle + stepSweep * i,
        stepSweep * 1.02, // tiny overlap so no visible seams
        false,
        Paint()
          ..color = color.withValues(alpha: 0.18 + 0.82 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 + 2 * t
          ..strokeCap = StrokeCap.round,
      );
    }

    // Glowing comet head at the current position.
    final headAngle = _startAngle + totalSweep;
    final headCenter = Offset(
      center.dx + radius * math.cos(headAngle),
      center.dy + radius * math.sin(headAngle),
    );
    canvas.drawCircle(
      headCenter,
      9 + 3 * pulse,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + 3 * pulse),
    );
    canvas.drawCircle(
      headCenter,
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    // Face outline guide in the middle.
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radius * 0.95, height: radius * 1.25),
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (direction != null) {
      // Put the arrow just ahead of the comet head and point it
      // in the direction the ring is currently travelling.
      final arrowRadius = radius + 20;

      final arrowCenter = Offset(
        center.dx + arrowRadius * math.cos(headAngle),
        center.dy + arrowRadius * math.sin(headAngle),
      );

      // Tangent to the circle.
      final tangentAngle = headAngle +
          (direction == 1 ? -math.pi / 2 : math.pi / 2);

      canvas.save();
      canvas.translate(arrowCenter.dx, arrowCenter.dy);
      canvas.rotate(tangentAngle + math.pi / 2);

      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(0, -12)
        ..lineTo(8, 7)
        ..lineTo(0, 3)
        ..lineTo(-8, 7)
        ..close();

      canvas.drawPath(path, arrowPaint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(covariant _RotationRingPainter oldDelegate) {
    return oldDelegate.unwrappedDeg != unwrappedDeg ||
        oldDelegate.direction != direction ||
        oldDelegate.pulse != pulse;
  }
}