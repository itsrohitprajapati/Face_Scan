import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_gate.dart';
import 'enrollment_scan_screen.dart';

enum RegisterRole { student, teacher }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  RegisterRole _role = RegisterRole.student;

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _rollNumber = TextEditingController();
  final _inviteCode = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;
  List<File> _photos = [];

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _rollNumber.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  bool get _isStudent => _role == RegisterRole.student;

  Future<void> _capturePhotos() async {
    setState(() => _error = null);
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = 'Camera permission is required to enroll your face.');
      return;
    }
    final cameras = await availableCameras();
    if (!mounted) return;
    final result = await Navigator.of(context).push<List<File>>(
      MaterialPageRoute(builder: (_) => EnrollmentScanScreen(cameras: cameras)),
    );
    if (result != null && mounted) {
      setState(() => _photos = result);
    }
  }

  String? _validate() {
    if (_fullName.text.trim().length < 2) return 'Enter your full name.';
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (_isStudent) {
      if (_rollNumber.text.trim().isEmpty) return 'Enter your roll number.';
      if (_photos.length != 5) return 'Scan your face to capture 5 photos.';
    } else {
      if (_inviteCode.text.trim().isEmpty) return 'Enter the teacher invite code.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = _isStudent
          ? await ApiService.instance.registerStudent(
              fullName: _fullName.text,
              rollNumber: _rollNumber.text,
              email: _email.text,
              password: _password.text,
              photos: _photos,
            )
          : await ApiService.instance.registerTeacher(
              fullName: _fullName.text,
              email: _email.text,
              password: _password.text,
              inviteCode: _inviteCode.text,
            );
      if (!mounted) return;
      goHome(context, session.user);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<RegisterRole>(
                segments: const [
                  ButtonSegment(
                    value: RegisterRole.student,
                    label: Text('Student'),
                    icon: Icon(Icons.school_outlined),
                  ),
                  ButtonSegment(
                    value: RegisterRole.teacher,
                    label: Text('Teacher'),
                    icon: Icon(Icons.co_present_outlined),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: _loading
                    ? null
                    : (selection) => setState(() => _role = selection.first),
              ),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Full name',
                controller: _fullName,
                hintText: 'Ada Lovelace',
                keyboardType: TextInputType.name,
                enabled: !_loading,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email',
                controller: _email,
                hintText: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                enabled: !_loading,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Password',
                controller: _password,
                hintText: 'At least 8 characters',
                obscureText: _obscure,
                enabled: !_loading,
                textInputAction:
                    _isStudent ? TextInputAction.next : TextInputAction.done,
                suffix: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.muted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 16),
              if (_isStudent) ..._studentFields() else ..._teacherFields(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                InlineNotice(_error!, isError: true),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Create account'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('I already have an account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _teacherFields() {
    return [
      AppTextField(
        label: 'Teacher invite code',
        controller: _inviteCode,
        hintText: 'SMART-TEACHER-DEMO',
        textInputAction: TextInputAction.done,
        enabled: !_loading,
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 6),
      const Padding(
        padding: EdgeInsets.only(left: 2),
        child: Text(
          'Ask your admin for the invite code configured on the server.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
      ),
    ];
  }

  List<Widget> _studentFields() {
    return [
      AppTextField(
        label: 'Roll number',
        controller: _rollNumber,
        hintText: 'e.g. 21CS042',
        textInputAction: TextInputAction.done,
        enabled: !_loading,
      ),
      const SizedBox(height: 18),
      const SectionLabel('Face enrollment'),
      const SizedBox(height: 8),
      const Text(
        'A quick guided scan captures 5 photos — looking straight ahead, to each '
        'side, then up and down. The server builds your recognition profile from '
        'them, so make sure only your face is in frame.',
        style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 12),
      _PhotoStrip(photos: _photos),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _loading ? null : _capturePhotos,
        icon: Icon(_photos.isEmpty ? Icons.face_retouching_natural : Icons.replay),
        label: Text(_photos.isEmpty ? 'Scan my face' : 'Rescan'),
      ),
    ];
  }
}

class _PhotoStrip extends StatelessWidget {
  final List<File> photos;
  const _PhotoStrip({required this.photos});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final hasPhoto = i < photos.length;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasPhoto ? AppColors.green : AppColors.line,
                    width: hasPhoto ? 1.6 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? Image.file(photos[i], fit: BoxFit.cover)
                    : const Center(
                        child: Icon(Icons.person_outline,
                            color: AppColors.line, size: 28),
                      ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
