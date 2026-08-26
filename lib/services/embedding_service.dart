import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps a MobileFaceNet-style TFLite model (112x112 RGB in,
/// 128-d L2-normalized embedding out) and prints the resulting
/// vector to the console.
///
/// Drop a compatible model at `assets/models/mobilefacenet.tflite`
/// (see README for where to get one) and it will be picked up
/// automatically. Any single-input / single-output face-embedding
/// model works as long as you adjust [inputSize] and [outputSize].
class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  Interpreter? _interpreter;
  static const int inputSize = 112;

  /// The embedding width this service emits.
  ///
  /// NOTE: the bundled mobilefacenet.tflite NATIVELY outputs 192 dims, so
  /// when that model is used the 192-d vector is reduced to this size (see
  /// [_reduceToOutputSize]). Drop in a model trained to emit [outputSize]
  /// dims directly for best accuracy.
  static const int outputSize = 128;

  /// The loaded model's real output width, read from the interpreter in
  /// [load]. Stays at [outputSize] until (and unless) a model is loaded.
  int _modelOutputSize = outputSize;
  static const String modelAsset = 'assets/models/mobilefacenet.tflite';

  bool get isLoaded => _interpreter != null;

  Future<void> load() async {
    if (_interpreter != null) return;
    try {
      final interpreter = await Interpreter.fromAsset(modelAsset);
      _interpreter = interpreter;
      // The .tflite model has a fixed output width baked in. Read it so the
      // run buffer is sized to match (a mismatch throws at runtime) and so
      // we know whether the native vector must be reduced to [outputSize].
      final outShape = interpreter.getOutputTensor(0).shape; // e.g. [1, 192]
      _modelOutputSize = outShape.isEmpty ? outputSize : outShape.last;
      if (_modelOutputSize > outputSize) {
        developer.log(
          'Model natively outputs $_modelOutputSize dims; reducing to '
          '$outputSize by truncation + re-normalization. For best accuracy '
          'use a model trained to emit $outputSize dims directly.',
          name: 'EmbeddingService',
        );
      } else if (_modelOutputSize < outputSize) {
        developer.log(
          'Model outputs only $_modelOutputSize dims (< requested $outputSize); '
          'the embedding will be zero-padded to $outputSize.',
          name: 'EmbeddingService',
        );
      }
    } catch (e) {
      developer.log(
        'Could not load $modelAsset — add a MobileFaceNet/FaceNet '
        '.tflite file there. Falling back to a hash-based stub '
        'embedding so the rest of the pipeline is still testable.',
        name: 'EmbeddingService',
        error: e,
      );
      _interpreter = null;
      _modelOutputSize = outputSize;
    }
  }

  /// Preprocess an aligned face crop into the model's expected
  /// float32 NHWC tensor, normalized to [-1, 1].
  Float32List _preprocess(img.Image face) {
    final resized = img.copyResize(
      face,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );
    final input = Float32List(inputSize * inputSize * 3);
    var i = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        input[i++] = (p.r / 127.5) - 1.0;
        input[i++] = (p.g / 127.5) - 1.0;
        input[i++] = (p.b / 127.5) - 1.0;
      }
    }
    return input;
  }

  List<double> _l2Normalize(List<double> v) {
    double sumSq = 0;
    for (final x in v) {
      sumSq += x * x;
    }
    final norm = sumSq > 0 ? _sqrt(sumSq) : 1.0;
    return v.map((x) => x / norm).toList();
  }

  double _sqrt(double x) {
    // Local alias to avoid importing dart:math just for one call site.
    double guess = x;
    for (var i = 0; i < 20; i++) {
      guess = 0.5 * (guess + x / guess);
    }
    return guess;
  }

  /// Runs one face crop through the model and returns its embedding.
  List<double> embedSingle(img.Image faceCrop) {
    if (_interpreter == null) {
      return _stubEmbedding(faceCrop);
    }
    final input = _preprocess(faceCrop).reshape([1, inputSize, inputSize, 3]);
    // Size the run buffer to the model's NATIVE output width to avoid a
    // shape mismatch, then reduce to [outputSize] before normalizing.
    final output = List.generate(1, (_) => List.filled(_modelOutputSize, 0.0));
    _interpreter!.run(input, output);
    return _l2Normalize(_reduceToOutputSize(output[0]));
  }

  /// Coerces a raw model vector to exactly [outputSize] dims: truncates a
  /// longer vector (e.g. the bundled 192-d model -> 128) or zero-pads a
  /// shorter one. Truncation drops trailing features, so a model that emits
  /// [outputSize] dims natively is preferable for recognition accuracy.
  List<double> _reduceToOutputSize(List<double> v) {
    if (v.length == outputSize) return v;
    if (v.length > outputSize) return v.sublist(0, outputSize);
    return [...v, ...List<double>.filled(outputSize - v.length, 0.0)];
  }

  /// Runs every captured pose crop through the model and averages the
  /// (re-normalized) vectors into a single identity embedding — this is
  /// what a 360° capture buys you over a single frontal shot: the final
  /// vector is robust to pose because it was built from every angle.
  List<double> embedFromMultiplePoses(List<img.Image> faceCrops) {
    if (faceCrops.isEmpty) {
      // Nothing was captured (e.g. every crop failed to decode), so there
      // is no identity to average. Returning here would hand back an
      // all-zero vector; log it so the cause is obvious instead of
      // silently showing zeros on the result screen.
      developer.log(
        'embedFromMultiplePoses called with 0 crops — returning an '
        'all-zero embedding. Check that face crops are being captured.',
        name: 'EmbeddingService',
      );
      return List<double>.filled(outputSize, 0.0);
    }
    final vectors = faceCrops.map(embedSingle).toList();
    final avg = List<double>.filled(outputSize, 0.0);
    for (final v in vectors) {
      for (var i = 0; i < outputSize; i++) {
        avg[i] += v[i] / vectors.length;
      }
    }
    return _l2Normalize(avg);
  }

  /// Deterministic fallback so the app is still runnable/testable
  /// before you've dropped in a real .tflite model — NOT for
  /// production identity matching.
  List<double> _stubEmbedding(img.Image faceCrop) {
    final resized = img.copyResize(faceCrop, width: 16, height: 12);
    final vec = List<double>.filled(outputSize, 0.0);
    var seed = 0;
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final p = resized.getPixel(x, y);
        seed = (seed * 31 + p.r.toInt() + p.g.toInt() * 3 + p.b.toInt() * 7) &
            0x7fffffff;
      }
    }
    for (var i = 0; i < outputSize; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      vec[i] = (seed % 2000 - 1000) / 1000.0;
    }
    return _l2Normalize(vec);
  }

  /// Prints the embedding to the debug console in a copy-pasteable form.
  void printEmbedding(List<double> embedding, {String label = 'FACE_EMBEDDING'}) {
    final formatted = embedding.map((v) => v.toStringAsFixed(6)).join(', ');
    // ignore: avoid_print
    print('=== $label (dim=${embedding.length}) ===');
    // ignore: avoid_print
    print('[$formatted]');
  }
}
