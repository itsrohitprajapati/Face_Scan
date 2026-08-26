import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// Guided, Face-ID-style enrollment capture that reuses the smooth look of the
/// 360° scan but produces exactly **five JPEG stills** (front, both sides, up,
/// and down) for `ApiService.registerStudent`. It deliberately does NOT compute an
/// embedding — the backend derives the biometric encodings from these photos.
///
/// Smoothness notes (kept in parity with `face_scan_screen`):
///  * The camera runs at [ResolutionPreset.medium] so per-frame ML Kit
///    detection stays fast.
///  * All heavy pixel work (YUV/BGRA → RGB, rotate, JPEG encode) runs in a
///    background isolate via [compute], so a capture never freezes the ring
///    animation or the UI thread.
///  * The progress ring is driven by a 60fps [AnimationController] "hold to
///    fill" animation rather than frame-rate-limited `setState` calls.
class EnrollmentScanScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const EnrollmentScanScreen({super.key, required this.cameras});

  @override
  State<EnrollmentScanScreen> createState() => _EnrollmentScanScreenState();
}

/// The five guided poses. Side turns and up/down tilts are intentionally mild
/// (see [_TurnBand]) so the backend's face detector still finds a single face
/// in each.
enum _Pose { front, sideA, sideB, up, down }

/// The nudge direction shown to the user for each pose. Drives the animated
/// arrow around the ring so the *next* head move is obvious at a glance
/// ("gently move your head to the left", etc.). Side detection itself stays
/// direction-agnostic (see [_poseSatisfied]) so a mirrored front camera can
/// never leave the user stuck — the arrow is guidance, not a hard gate.
enum _MoveDir { none, left, right, up, down }

_MoveDir _directionFor(_Pose pose) {
  switch (pose) {
    case _Pose.front:
      return _MoveDir.none;
    case _Pose.sideA:
      return _MoveDir.left;
    case _Pose.sideB:
      return _MoveDir.right;
    case _Pose.up:
      return _MoveDir.up;
    case _Pose.down:
      return _MoveDir.down;
  }
}

class _TurnBand {
  // Deliberately forgiving bands: the backend only needs five stills that each
  // contain exactly one detectable face, so we guide pose variety without
  // hard-gating on tight angle windows the user struggles to hold.
  static const double frontMaxYaw = 18; // |yaw| under this = "looking straight"
  static const double frontMaxPitch = 22;
  static const double sideMinYaw = 16; // turned enough to differ from front
  static const double sideMaxYaw = 50; // but not a full profile (keeps 1 face)
  static const double vertMinPitch = 10; // tilted up/down enough to differ from front
  static const double vertMaxPitch = 45; // but not so extreme the face is lost
  static const double vertMaxYaw = 26; // stay roughly centered while tilting
}

class _EnrollmentScanScreenState extends State<EnrollmentScanScreen>
    with TickerProviderStateMixin {
  static const int _required = 5;

  CameraController? _controller;
  late final FaceDetector _detector;
  late final AnimationController _glow; // ambient breathing pulse
  late final AnimationController _hold; // fills as the user holds a pose

  bool _busy = false; // a detection frame is in flight
  bool _capturing = false; // encoding/saving a still
  bool _finishing = false;
  bool _wantCapture = false; // hold animation completed -> grab next good frame
  bool _manualWanted = false; // user tapped the manual shutter

  final List<File> _saved = [];
  int? _firstTurnSign; // sign of yaw captured for sideA; sideB must be opposite
  String _hint = 'Center your face in the oval';

  _Pose get _pose => _Pose.values[_saved.length.clamp(0, _required - 1)];

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _hold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_capturing && !_finishing) {
          _wantCapture = true; // captured on the next valid frame
        }
      });
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        // Detect smaller faces too: the cover-cropped preview shows only part
        // of the sensor frame, so a face that looks large on screen can be a
        // modest fraction of the full image ML Kit actually sees.
        minFaceSize: 0.1,
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

  // ---- Per-frame pose tracking (light work only) --------------------------

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _capturing || _finishing || _controller == null) return;
    _busy = true;
    try {
      final rotation = InputImageRotationValue.fromRawValue(
              _controller!.description.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final input = _toInputImage(image, rotation);
      if (input == null) return;

      final faces = await _detector.processImage(input);
      final oneFace = faces.length == 1;

      // Manual shutter: as soon as exactly one face is in frame, snap it for
      // the current slot regardless of head pose. This guarantees enrollment
      // can always be completed even when a guided pose is hard to hit.
      if (_manualWanted) {
        if (oneFace) {
          _manualWanted = false;
          await _capture(image, faces.first);
        } else {
          _setHint(_promptFor(faces));
        }
        return;
      }

      final valid = oneFace && _poseSatisfied(faces.first);

      if (!valid) {
        if (_hold.value != 0) _hold.reverse();
        _wantCapture = false;
        _setHint(_promptFor(faces));
        return;
      }

      // Pose is valid. If the hold just completed, snap this frame; otherwise
      // start/resume filling the ring.
      if (_wantCapture) {
        await _capture(image, faces.first);
      } else if (_hold.status != AnimationStatus.forward &&
          _hold.status != AnimationStatus.completed) {
        if (_hold.value == 0) HapticFeedback.selectionClick();
        _hold.forward(); // resumes from the current value if partly filled
        _setHint('Hold still…');
      } else {
        _setHint('Hold still…');
      }
    } catch (e, st) {
      debugPrint('Enrollment frame error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  bool _poseSatisfied(Face face) {
    final yaw = face.headEulerAngleY ?? 0; // left(-)/right(+)
    final pitch = face.headEulerAngleX ?? 0; // ML Kit: up(+)/down(-)
    switch (_pose) {
      case _Pose.front:
        return yaw.abs() <= _TurnBand.frontMaxYaw &&
            pitch.abs() <= _TurnBand.frontMaxPitch;
      case _Pose.sideA:
        return yaw.abs() >= _TurnBand.sideMinYaw &&
            yaw.abs() <= _TurnBand.sideMaxYaw;
      case _Pose.sideB:
        return yaw.abs() >= _TurnBand.sideMinYaw &&
            yaw.abs() <= _TurnBand.sideMaxYaw &&
            (_firstTurnSign == null || yaw.sign.toInt() == -_firstTurnSign!);
      case _Pose.up:
        return yaw.abs() <= _TurnBand.vertMaxYaw &&
            pitch >= _TurnBand.vertMinPitch &&
            pitch <= _TurnBand.vertMaxPitch;
      case _Pose.down:
        return yaw.abs() <= _TurnBand.vertMaxYaw &&
            pitch <= -_TurnBand.vertMinPitch &&
            pitch >= -_TurnBand.vertMaxPitch;
    }
  }

  String _promptFor(List<Face> faces) {
    if (faces.isEmpty) return 'No face detected — center your face';
    if (faces.length > 1) return 'Only you should be in frame';
    return _instructionFor(_pose);
  }

  String _instructionFor(_Pose pose) {
    switch (pose) {
      case _Pose.front:
        return 'Look straight at the camera';
      case _Pose.sideA:
        return 'Now gently move your head to the left';
      case _Pose.sideB:
        return 'Now gently move your head to the right';
      case _Pose.up:
        return 'Now gently move your head upward';
      case _Pose.down:
        return 'Now gently move your head downward';
    }
  }

  void _setHint(String hint) {
    if (mounted && hint != _hint) setState(() => _hint = hint);
  }

  /// Arms a manual capture: the next frame containing exactly one face is saved
  /// for the current slot, bypassing the guided pose gate.
  void _triggerManualCapture() {
    if (_capturing || _finishing || !mounted) return;
    if (_hold.value != 0) _hold.reverse();
    setState(() {
      _manualWanted = true;
      _hint = 'Hold still — capturing…';
    });
  }

  // ---- Capture (heavy work offloaded to a background isolate) -------------

  Future<void> _capture(CameraImage image, Face face) async {
    _capturing = true;
    _wantCapture = false;
    try {
      // Extract the raw planes synchronously (cheap byte copy) so the
      // CameraImage buffer can be recycled while the isolate works.
      final frame = _extractFrame(image);
      final yawSign = (face.headEulerAngleY ?? 0).sign.toInt();

      final file = await _encodeUprightFace(frame);
      if (!mounted) return;

      if (file == null) {
        _hold.reverse();
        _setHint('Could not get a clear shot — try again');
        return;
      }

      if (_pose == _Pose.sideA) _firstTurnSign = yawSign;
      _saved.add(file);
      HapticFeedback.mediumImpact();
      _hold.reset();

      if (_saved.length >= _required) {
        await _finish();
      } else {
        setState(() => _hint = _instructionFor(_pose));
      }
    } finally {
      _capturing = false;
    }
  }

  /// Produces an upright JPEG containing exactly one detectable face. Encoding
  /// happens in a background isolate. The sensor orientation is tried first
  /// (correct on virtually all devices); the other quarter-turns are a rare
  /// self-correcting fallback so we never upload a sideways photo.
  Future<File?> _encodeUprightFace(_FrameData frame) async {
    final dir = await getTemporaryDirectory();
    final sensor = _controller!.description.sensorOrientation;
    final tried = <int>{};
    for (final angle in [sensor, 0, 90, 180, 270]) {
      if (!tried.add(angle)) continue;
      final bytes =
          await compute(_encodeUprightJpeg, _EncodeRequest(frame, angle));
      final path =
          '${dir.path}/enroll-${_saved.length + 1}-${DateTime.now().microsecondsSinceEpoch}.jpg';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      final faces =
          await _detector.processImage(InputImage.fromFilePath(path));
      if (faces.length == 1) return file;
      try {
        await file.delete();
      } catch (_) {}
    }
    return null;
  }

  _FrameData _extractFrame(CameraImage image) {
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    final isNv21 = !isBgra &&
        (image.planes.length == 1 || image.format.group == ImageFormatGroup.nv21);
    final format = isBgra ? 1 : (isNv21 ? 0 : 2);
    final p0 = image.planes.first;
    if (format != 2) {
      return _FrameData(
        format: format,
        width: image.width,
        height: image.height,
        plane0: Uint8List.fromList(p0.bytes),
        rowStride0: p0.bytesPerRow,
      );
    }
    final u = image.planes[1];
    final v = image.planes[2];
    return _FrameData(
      format: 2,
      width: image.width,
      height: image.height,
      plane0: Uint8List.fromList(p0.bytes),
      rowStride0: p0.bytesPerRow,
      plane1: Uint8List.fromList(u.bytes),
      plane2: Uint8List.fromList(v.bytes),
      uvRowStride: u.bytesPerRow,
      uvPixelStride: u.bytesPerPixel ?? 1,
    );
  }

  Future<void> _finish() async {
    _finishing = true;
    HapticFeedback.heavyImpact();
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(List<File>.of(_saved));
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          (Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888);
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

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    _glow.dispose();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Text('Enroll your face (${_saved.length}/$_required)'),
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator(color: AppColors.green))
          : Stack(
              fit: StackFit.expand,
              children: [
                _CoverCameraPreview(controller: controller),
                _buildVignette(),
                _buildOverlay(),
              ],
            ),
    );
  }

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
              Colors.black.withValues(alpha: 0.5),
            ],
            stops: const [0.0, 0.22, 0.66, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(),
          SizedBox(
            width: 280,
            height: 280,
            child: AnimatedBuilder(
              animation: Listenable.merge([_glow, _hold]),
              builder: (context, _) => CustomPaint(
                painter: _PoseRingPainter(
                  captured: _saved.length,
                  total: _required,
                  holdProgress: _finishing ? 1.0 : _hold.value,
                  active: !_finishing,
                  pulse: _glow.value,
                  color: AppColors.green,
                  trackColor: Colors.white24,
                  direction: _finishing ? _MoveDir.none : _directionFor(_pose),
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.line.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _finishing ? 'All set!' : _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_capturing || _finishing)
                        ? null
                        : _triggerManualCapture,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Capture photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Follow the guide to auto-capture, or tap to grab a shot.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Background-isolate image encoding -----------------------------------
// These run via `compute`, so they must be top-level and only touch sendable
// data ([_FrameData]/[_EncodeRequest] fields are ints + Uint8List).

class _FrameData {
  final int format; // 0 = NV21, 1 = BGRA8888, 2 = YUV_420 (3-plane)
  final int width;
  final int height;
  final Uint8List plane0;
  final int rowStride0;
  final Uint8List? plane1;
  final Uint8List? plane2;
  final int uvRowStride;
  final int uvPixelStride;

  const _FrameData({
    required this.format,
    required this.width,
    required this.height,
    required this.plane0,
    required this.rowStride0,
    this.plane1,
    this.plane2,
    this.uvRowStride = 0,
    this.uvPixelStride = 1,
  });
}

class _EncodeRequest {
  final _FrameData frame;
  final int angle; // clockwise degrees to rotate to upright
  const _EncodeRequest(this.frame, this.angle);
}

Uint8List _encodeUprightJpeg(_EncodeRequest req) {
  var image = _frameToImage(req.frame);
  // Keep uploads small; medium preview is already <= ~720px so this is usually
  // a no-op, but guards against unexpectedly large frames.
  final longest = math.max(image.width, image.height);
  if (longest > 1080) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 1080)
        : img.copyResize(image, height: 1080);
  }
  if (req.angle != 0) image = img.copyRotate(image, angle: req.angle);
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

img.Image _frameToImage(_FrameData f) {
  switch (f.format) {
    case 1:
      return img.Image.fromBytes(
        width: f.width,
        height: f.height,
        bytes: f.plane0.buffer,
        order: img.ChannelOrder.bgra,
      );
    case 2:
      return _yuv420ThreePlaneToImage(f);
    default:
      return _nv21ToImage(f);
  }
}

img.Image _nv21ToImage(_FrameData f) {
  final width = f.width;
  final height = f.height;
  final bytes = f.plane0;
  final yRowStride = f.rowStride0 == 0 ? width : f.rowStride0;
  final uvStart = yRowStride * height;

  final out = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final yRow = y * yRowStride;
    final uvRow = uvStart + (y >> 1) * yRowStride;
    for (var x = 0; x < width; x++) {
      final yVal = bytes[yRow + x];
      final uvIndex = uvRow + (x >> 1) * 2;
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

img.Image _yuv420ThreePlaneToImage(_FrameData f) {
  final out = img.Image(width: f.width, height: f.height);
  final yBytes = f.plane0;
  final uBytes = f.plane1!;
  final vBytes = f.plane2!;
  for (var yPos = 0; yPos < f.height; yPos++) {
    for (var xPos = 0; xPos < f.width; xPos++) {
      final uvIndex =
          f.uvPixelStride * (xPos ~/ 2) + f.uvRowStride * (yPos ~/ 2);
      final yIndex = yPos * f.rowStride0 + xPos;
      final yVal = yBytes[yIndex];
      final uVal = uBytes[uvIndex];
      final vVal = vBytes[uvIndex];
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

/// Fills the screen with the camera feed without distorting it (object-fit:
/// cover), matching the standalone scan screen.
class _CoverCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _CoverCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Size(constraints.maxWidth, constraints.maxHeight);
        final preview = controller.value.previewSize!;
        final previewAspect = preview.height / preview.width;
        var scale = screen.aspectRatio / previewAspect;
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
}

/// A three-segment progress ring (one arc per required pose). Completed arcs
/// glow solid green; the active arc fills smoothly from 0..1 as the user holds
/// the pose (with a glowing comet head at the fill tip), echoing the flowing
/// look of the 360° scan ring. A face-oval guide sits in the middle.
class _PoseRingPainter extends CustomPainter {
  final int captured;
  final int total;
  final double holdProgress; // 0..1 fill of the active segment
  final bool active;
  final double pulse;
  final Color color;
  final Color trackColor;
  final _MoveDir direction; // which way to nudge the head next

  _PoseRingPainter({
    required this.captured,
    required this.total,
    required this.holdProgress,
    required this.active,
    required this.pulse,
    required this.color,
    required this.trackColor,
    this.direction = _MoveDir.none,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const gap = 0.28; // radians between segments
    final segment = (2 * math.pi / total) - gap;

    for (var i = 0; i < total; i++) {
      final start = -math.pi / 2 + gap / 2 + i * (segment + gap);
      final done = i < captured;
      final isActive = i == captured && active;

      // Faint base track for every segment.
      canvas.drawArc(
        rect,
        start,
        segment,
        false,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );

      if (done) {
        canvas.drawArc(
          rect,
          start,
          segment,
          false,
          Paint()
            ..color = color.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 15
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawArc(
          rect,
          start,
          segment,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round,
        );
      } else if (isActive && holdProgress > 0) {
        final sweep = segment * holdProgress.clamp(0.0, 1.0);
        canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..color = color.withValues(alpha: 0.35 + 0.2 * pulse)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
        // Glowing comet head at the fill tip.
        final headAngle = start + sweep;
        final head = Offset(
          center.dx + radius * math.cos(headAngle),
          center.dy + radius * math.sin(headAngle),
        );
        canvas.drawCircle(
            head, 5, Paint()..color = Colors.white.withValues(alpha: 0.95));
      }
    }

    // Face outline guide in the middle.
    canvas.drawOval(
      Rect.fromCenter(
          center: center, width: radius * 0.95, height: radius * 1.25),
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Animated "go this way" arrow nudging toward the next pose.
    _drawDirectionArrow(canvas, center, radius);
  }

  /// Draws a gently pulsing double-chevron between the face oval and the ring,
  /// pointing in the direction the user should move their head next.
  void _drawDirectionArrow(Canvas canvas, Offset center, double radius) {
    if (direction == _MoveDir.none) return;

    double dx = 0;
    double dy = 0;
    switch (direction) {
      case _MoveDir.left:
        dx = -1;
        break;
      case _MoveDir.right:
        dx = 1;
        break;
      case _MoveDir.up:
        dy = -1;
        break;
      case _MoveDir.down:
        dy = 1;
        break;
      case _MoveDir.none:
        return;
    }

    // Sit in the gap between the oval guide and the ring, drifting outward a
    // touch with the pulse so it reads as a nudge in the travel direction.
    final nudge = 3 + 4 * pulse;
    final dist = radius * 0.66 + nudge;
    final travel = math.atan2(dy, dx);

    canvas.save();
    canvas.translate(center.dx + dx * dist, center.dy + dy * dist);
    canvas.rotate(travel); // +x now points the way to move

    final glow = Paint()
      ..color = color.withValues(alpha: 0.35 + 0.25 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path chevron(double ox) => Path()
      ..moveTo(ox - 6, -8)
      ..lineTo(ox + 4, 0)
      ..lineTo(ox - 6, 8);

    for (final ox in const [0.0, 9.0]) {
      canvas.drawPath(chevron(ox), glow);
      canvas.drawPath(chevron(ox), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PoseRingPainter old) {
    return old.captured != captured ||
        old.holdProgress != holdProgress ||
        old.active != active ||
        old.pulse != pulse ||
        old.direction != direction;
  }
}
