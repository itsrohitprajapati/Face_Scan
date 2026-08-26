import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// Lets the user point the app at a different backend. Returns `true` when the
/// base URL was changed so callers can refresh any URL they display.
Future<bool> showServerSettingsDialog(BuildContext context) async {
  final controller = TextEditingController(text: ApiService.instance.baseUrl);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Server settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Base URL of the attendance API. The "/api/v1" suffix is added '
            'automatically if you leave it out.\n\n'
            'Use http://10.0.2.2:8000 from an Android emulator, or your '
            "machine's LAN IP from a physical device.",
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'http://10.0.2.2:8000'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (result == true && controller.text.trim().isNotEmpty) {
    await ApiService.instance.setBaseUrl(controller.text);
    return true;
  }
  return false;
}
