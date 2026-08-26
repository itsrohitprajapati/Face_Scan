import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/gradient_action_button.dart';
import 'face_scan_screen.dart';
import 'package:camera/camera.dart';

class ResultScreen extends StatelessWidget {
  final List<double> embedding;
  final int poseCount;
  const ResultScreen({super.key, required this.embedding, required this.poseCount});

  @override
  Widget build(BuildContext context) {
    final preview = embedding.take(50).map((v) => v.toStringAsFixed(12)).join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text('Scan complete')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Captured $poseCount poses across a full 360° head '
                        'turn and generated a ${embedding.length}-d embedding. '
                        'Printed to the debug console.',
                        style: const TextStyle(color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Embedding preview (first 50 of ${'${embedding.length}'} dims)',
                style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  '[$preview, ...]',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.ink,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              GradientActionButton(
                label: 'Scan again',
                icon: Icons.replay,
                onPressed: () async {
                  final cameras = await availableCameras();
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => FaceScanScreen(cameras: cameras),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
