import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_user.dart';
import '../services/face_embedder.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Profile page that lets the user add a single face photo — either taken with
/// the camera or picked from the gallery — and turns it into a face embedding
/// using the same on-device pipeline as the 360° face scan
/// (see [FaceEmbedder] / `face_scan_screen.dart`).
///
/// The backend integration is intentionally left as a hook ([_saveEmbedding]);
/// swap that in once the profile-photo endpoint is ready.
class ProfileScreen extends StatefulWidget {
  final AppUser user;
  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _photo;
  bool _processing = false;
  bool _saving = false;
  FaceEmbeddingResult? _result;
  String? _error;

  bool get _busy => _processing || _saving;

  Future<void> _pickFrom(ImageSource source) async {
    if (_busy) return;
    setState(() => _error = null);

    // The gallery uses the system photo picker (no permission needed on modern
    // Android); the camera requires the CAMERA permission that the manifest
    // declares, so request it explicitly first.
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() => _error = 'Camera permission is required to take a photo.');
        return;
      }
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        // Keep the still small so face detection + decode stay fast, while
        // leaving enough resolution for the 112x112 embedding model.
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );
      if (picked == null) return; // user cancelled
      setState(() {
        _photo = File(picked.path);
        _result = null;
      });
      await _generateEmbedding();
    } catch (e) {
      setState(() => _error = 'Could not open ${source == ImageSource.camera ? 'the camera' : 'the gallery'}: $e');
    }
  }

  Future<void> _generateEmbedding() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    final result = await FaceEmbedder.instance.embedFromFile(photo);
    if (!mounted) return;
    setState(() {
      _processing = false;
      _result = result;
      if (!result.isValid) {
        _error = result.error ?? 'Could not create a face embedding.';
      }
    });
  }

  /// Placeholder for the (to-be-added) backend call. The embedding + photo are
  /// ready here; wire them to your new endpoint.
  Future<void> _saveEmbedding() async {
    final result = _result;
    if (result == null || !result.isValid || _busy) return;
    setState(() => _saving = true);
    try {
      // TODO(backend): upload `_photo` and/or `result.embedding` to the server.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo embedding ready.'),
          backgroundColor: AppColors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSourceSheet() {
    if (_busy) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const _SheetIcon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Use the camera'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickFrom(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const _SheetIcon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Pick an existing photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickFrom(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final canSave = result != null && result.isValid && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _IdentityCard(user: widget.user),
            const SizedBox(height: 24),
            const SectionLabel('Profile photo'),
            const SizedBox(height: 10),
            const Text(
              'Add one clear, front-facing photo — take it with the camera or '
              'pick one from your gallery. It is turned into a face embedding '
              'on your device using the same model as the face scan.',
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            _PhotoPreview(photo: _photo, processing: _processing),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _showSourceSheet,
              icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.replay),
              label: Text(_photo == null ? 'Add photo' : 'Change photo'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              InlineNotice(_error!, isError: true),
            ],
            if (result != null && result.isValid) ...[
              const SizedBox(height: 16),
              _EmbeddingCard(embedding: result.embedding),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSave ? _saveEmbedding : null,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save profile photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {
  final IconData icon;
  const _SheetIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: AppColors.green, size: 20),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final AppUser user;
  const _IdentityCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.greenSoft,
            child: Text(
              user.initials,
              style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  user.rollNumber == null
                      ? user.email
                      : 'Roll ${user.rollNumber} · ${user.email}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final File? photo;
  final bool processing;
  const _PhotoPreview({required this.photo, required this.processing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.paper,
                shape: BoxShape.circle,
                border: Border.all(
                  color: photo == null ? AppColors.line : AppColors.green,
                  width: photo == null ? 1 : 1.8,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: photo == null
                  ? const Center(
                      child: Icon(Icons.person_outline,
                          color: AppColors.line, size: 56),
                    )
                  : Image.file(photo!, fit: BoxFit.cover),
            ),
            if (processing)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmbeddingCard extends StatelessWidget {
  final List<double> embedding;
  const _EmbeddingCard({required this.embedding});

  @override
  Widget build(BuildContext context) {
    final preview =
        embedding.take(12).map((v) => v.toStringAsFixed(4)).join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Face embedding ready (${embedding.length}-d)',
                style: const TextStyle(
                    color: AppColors.ink, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '[$preview, …]',
            style: const TextStyle(
              fontFamily: 'monospace',
              color: AppColors.ink,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
