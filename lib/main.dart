import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';
import 'services/api_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the persisted API base URL + auth token before the first frame so
  // the app can decide whether to show the login screen or a role home.
  await ApiService.instance.init();
  runApp(const FaceScanApp());
}

class FaceScanApp extends StatelessWidget {
  const FaceScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}
