import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class DecoyProfile {
  static const String _serverUrl = 'http://162.243.174.252:9090';

  // Guardar contraseña trampa y contraseña de emergencia
  static Future<void> setup({
    required String realPassword,
    required String decoyPassword,
    required String emergencyPassword,
    required String decoyUserId,
    required String decoyUsername,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('decoy_password', decoyPassword);
    await prefs.setString('emergency_password', emergencyPassword);
    await prefs.setString('decoy_user_id', decoyUserId);
    await prefs.setString('decoy_username', decoyUsername);
  }

  // Verificar si es contraseña trampa
  static Future<bool> isDecoyPassword(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final decoyPass = prefs.getString('decoy_password');
    return decoyPass != null && password == decoyPass;
  }

  // Verificar si es contraseña de emergencia
  static Future<bool> isEmergencyPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final emergencyPass = prefs.getString('emergency_password');
    return emergencyPass != null && password == emergencyPass;
  }

  // Ejecutar borrado de emergencia
  static Future<void> executeEmergency(String userId) async {
    try {
      // Borrar del servidor
      await http.delete(Uri.parse('$_serverUrl/delete-all?user_id=$userId'));
    } catch (_) {}

    // Borrar todo local
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Obtener datos del perfil falso
  static Future<Map<String, String>?> getDecoyProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('decoy_user_id');
    final username = prefs.getString('decoy_username');
    if (userId == null || username == null) return null;
    return {'user_id': userId, 'username': username};
  }
}
