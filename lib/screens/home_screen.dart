import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';
import '../widgets/gradient_action_button.dart';
import 'face_scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required to scan.')),
        );
      }
      return;
    }
    final cameras = await availableCameras();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FaceScanScreen(cameras: cameras)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Embedding Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.face_retouching_natural, color: AppColors.green, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                '360° Face Scan',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              const Text(
                'Slowly rotate your head in a full circle — clockwise or '
                'anticlockwise, either works. We\'ll build a single '
                'identity embedding from every angle and print it to the '
                'console.',
                style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 28),
              GradientActionButton(
                label: 'Start face scan',
                onPressed: () => _start(context),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.orangeSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add a MobileFaceNet .tflite model to assets/models '
                        'for real embeddings (see README).',
                        style: TextStyle(color: AppColors.orange, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
