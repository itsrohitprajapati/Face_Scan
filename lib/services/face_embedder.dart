import 'dart:developer' as developer;
import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'embedding_service.dart';

/// The outcome of turning a single still photo into a face embedding.
class FaceEmbeddingResult {
  /// The L2-normalized identity vector (empty when [faceDetected] is false).
  final List<double> embedding;

  /// Whether exactly-usable face pixels were found and embedded.
  final bool faceDetected;

  /// Human-readable reason we could not produce an embedding, if any.
  final String? error;

  const FaceEmbeddingResult({
    required this.embedding,
    required this.faceDetected,
    this.error,
  });

  bool get isValid =>
      faceDetected && error == null && embedding.isNotEmpty;
}

/// Turns a single gallery/camera photo into a face embedding using the *exact
/// same pipeline* as the 360° [FaceScanScreen]: detect the face with ML Kit,
/// crop the face region out of the still, then run that crop through
/// [EmbeddingService].
///
/// The scan screen averages an embedding across many pose crops
/// ([EmbeddingService.embedFromMultiplePoses]); here we only have one photo,
/// so we embed the single crop with [EmbeddingService.embedSingle].
class FaceEmbedder {
  FaceEmbedder._();
  static final FaceEmbedder instance = FaceEmbedder._();

  // A still photo is not latency-critical (unlike the live camera stream), so
  // favour accuracy over speed here.
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableTracking: false,
      enableClassification: false,
      minFaceSize: 0.15,
    ),
  );

  /// Extra margin around the detected face box, as a fraction of the box size,
  /// so the crop keeps a little context (hairline/chin) like a real headshot.
  static const double _margin = 0.2;

  /// Detects the face in [photo], crops it, and returns its embedding.
  Future<FaceEmbeddingResult> embedFromFile(File photo) async {
    try {
      // 1. Detect the face. ML Kit reads the file's EXIF orientation itself,
      //    so its bounding box is in upright (display) coordinates.
      final faces =
          await _detector.processImage(InputImage.fromFilePath(photo.path));
      if (faces.isEmpty) {
        return const FaceEmbeddingResult(
          embedding: [],
          faceDetected: false,
          error: 'No face detected. Use a clear, front-facing photo.',
        );
      }

      // 2. Decode the still and bake EXIF orientation so its pixels line up
      //    with ML Kit's (already-upright) bounding-box coordinates.
      final decoded = img.decodeImage(await photo.readAsBytes());
      if (decoded == null) {
        return const FaceEmbeddingResult(
          embedding: [],
          faceDetected: false,
          error: 'Could not read the selected image.',
        );
      }
      final upright = img.bakeOrientation(decoded);

      // 3. Crop the largest face (with a little margin), mirroring
      //    FaceScanScreen._cropFace.
      final box = _largestFace(faces).boundingBox;
      final crop = _cropFace(
        upright,
        left: box.left,
        top: box.top,
        width: box.width,
        height: box.height,
      );

      // 4. Embed that single crop through the same model the scan screen uses.
      await EmbeddingService.instance.load();
      final embedding = EmbeddingService.instance.embedSingle(crop);
      EmbeddingService.instance.printEmbedding(embedding);

      return FaceEmbeddingResult(embedding: embedding, faceDetected: true);
    } catch (e, st) {
      developer.log(
        'embedFromFile failed',
        error: e,
        stackTrace: st,
        name: 'FaceEmbedder',
      );
      return FaceEmbeddingResult(
        embedding: const [],
        faceDetected: false,
        error: 'Could not process the photo: $e',
      );
    }
  }

  Face _largestFace(List<Face> faces) {
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    return faces.first;
  }

  img.Image _cropFace(
    img.Image src, {
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final mx = width * _margin;
    final my = height * _margin;
    final x = (left - mx).clamp(0, src.width - 1).toInt();
    final y = (top - my).clamp(0, src.height - 1).toInt();
    final w = (width + mx * 2).clamp(1, src.width - x).toInt();
    final h = (height + my * 2).clamp(1, src.height - y).toInt();
    return img.copyCrop(src, x: x, y: y, width: w, height: h);
  }

  /// Releases the underlying ML Kit detector. Safe to skip for a singleton
  /// that lives for the app's lifetime.
  Future<void> dispose() => _detector.close();
}
