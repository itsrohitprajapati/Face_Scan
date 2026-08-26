import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme.dart';
import 'auth_gate.dart';

/// The mobile app targets students and teachers. Admin room/camera
/// configuration lives in the web dashboard, so this screen simply confirms
/// the signed-in admin and points them there.
class AdminHomeScreen extends StatelessWidget {
  final AppUser user;
  const AdminHomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutTo(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.admin_panel_settings_outlined,
                    color: AppColors.green, size: 30),
              ),
              const SizedBox(height: 20),
              Text('Signed in as ${user.fullName}',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text(
                'Admin tools — creating rooms, managing permanent room codes '
                'and configuring cameras — run in the web dashboard. Use the '
                'mobile app as a teacher or student.',
                style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
