import 'dart:io';
import 'package:flutter/material.dart';

class SecurityCheck {
  static Future<Map<String, bool>> runChecks() async {
    bool isRooted = false;
    bool isDeveloperMode = false;

    if (Platform.isAndroid) {
      // Verificar archivos tipicos de root
      final rootPaths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
        '/su/bin/su',
      ];

      for (final path in rootPaths) {
        if (await File(path).exists()) {
          isRooted = true;
          break;
        }
      }
    }

    return {
      'rooted': isRooted,
      'developer': isDeveloperMode,
    };
  }

  static Future<void> showWarningIfNeeded(BuildContext context) async {
    final checks = await runChecks();
    if (checks['rooted'] == true && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0D1321),
          title: const Row(children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Riesgo detectado', style: TextStyle(color: Colors.red)),
          ]),
          content: const Text(
            'Se detectó ROOT en este dispositivo.\n\n'
            'Esto puede comprometer la seguridad de tus comunicaciones.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido', style: TextStyle(color: Color(0xFF00D4FF))),
            ),
          ],
        ),
      );
    }
  }
}
