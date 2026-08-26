import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'admin_home_screen.dart';
import 'login_screen.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';

/// Returns the correct landing screen for a signed-in user's role.
Widget homeForUser(AppUser user) {
  if (user.isStudent) return StudentHomeScreen(user: user);
  if (user.isTeacher) return TeacherHomeScreen(user: user);
  return AdminHomeScreen(user: user);
}

/// Replaces the entire navigation stack with the role home for [user].
void goHome(BuildContext context, AppUser user) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => homeForUser(user)),
    (route) => false,
  );
}

/// Signs out and returns to the login screen, clearing the stack.
Future<void> signOutTo(BuildContext context) async {
  await ApiService.instance.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

/// Decides the first screen on cold start: if a token is persisted it is
/// validated with `/auth/me` (and dropped if stale), otherwise the login
/// screen is shown.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<AppUser?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<AppUser?> _resolve() async {
    if (!ApiService.instance.isAuthenticated) return null;
    try {
      return await ApiService.instance.me();
    } catch (_) {
      // Token expired/invalid or server unreachable — fall back to login.
      await ApiService.instance.signOut();
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return homeForUser(user);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined, color: AppColors.green, size: 40),
            SizedBox(height: 16),
            CircularProgressIndicator(color: AppColors.green),
          ],
        ),
      ),
    );
  }
}
