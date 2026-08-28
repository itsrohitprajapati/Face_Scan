/// A configured camera feed attached to a room, mirroring the API
/// `CameraSourceResponse`. Used to populate the "view source" selector on the
/// live session screen and to request preview frames.
class CameraSource {
  final String id;
  final String label;
  final String sourceType; // webcam | ip_stream | video_file
  final String source;
  final bool isEnabled;

  const CameraSource({
    required this.id,
    required this.label,
    required this.sourceType,
    required this.source,
    required this.isEnabled,
  });

  /// e.g. "ip stream" instead of the raw "ip_stream" enum value.
  String get sourceTypeLabel => sourceType.replaceAll('_', ' ');

  factory CameraSource.fromJson(Map<String, dynamic> json) => CameraSource(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Camera',
        sourceType: json['source_type'] as String? ?? 'webcam',
        source: json['source'] as String? ?? '',
        isEnabled: json['is_enabled'] as bool? ?? true,
      );
}
