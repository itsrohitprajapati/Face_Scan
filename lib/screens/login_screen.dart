import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_gate.dart';
import 'home_screen.dart' show HomeScreen;
import 'register_screen.dart';
import 'server_settings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identifier = _identifier.text.trim();
    final password = _password.text;
    if (identifier.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email/roll number and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await ApiService.instance.login(identifier, password);
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

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Attendance', style: TextStyle(fontSize: 18),),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () async {
              final changed = await showServerSettingsDialog(context);
              if (changed && mounted) setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.verified_user_outlined,
                    color: AppColors.green, size: 30),
              ),
              const SizedBox(height: 20),
              const Text(
                'Welcome back',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in with your email (teachers) or roll number (students).',
                style: TextStyle(fontSize: 14.5, color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Email or roll number',
                controller: _identifier,
                hintText: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                enabled: !_loading,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Password',
                controller: _password,
                hintText: '••••••••',
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                enabled: !_loading,
                onSubmitted: (_) => _submit(),
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppColors.muted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
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
                      : const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?",
                      style: TextStyle(color: AppColors.muted)),
                  TextButton(
                    onPressed: _loading ? null : _openRegister,
                    child: const Text('Create one'),
                  ),
                ],
              ),
              const Divider(height: 32),
              _ServerCaption(
                onEdit: () async {
                  final changed = await showServerSettingsDialog(context);
                  if (changed && mounted) setState(() {});
                },
              ),
              // const SizedBox(height: 8),
              // Center(
              //   child: TextButton.icon(
              //     onPressed: () => Navigator.of(context).push(
              //       MaterialPageRoute(builder: (_) => const HomeScreen()),
              //     ),
              //     icon: const Icon(Icons.face_retouching_natural, size: 18),
              //     label: const Text('Try the face embedding demo'),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerCaption extends StatelessWidget {
  final VoidCallback onEdit;
  const _ServerCaption({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Server: ${ApiService.instance.baseUrl}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.edit_outlined, size: 15, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
