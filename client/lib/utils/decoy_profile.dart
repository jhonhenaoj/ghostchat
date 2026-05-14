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
    final realUser = prefs.getString('username') ?? '';
    // Solo activar si el username es el real y la contraseña es la trampa
    return decoyPass != null && password == decoyPass && username == realUser;
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
      await http.delete(Uri.parse('$_serverUrl/delete-all?user_id=$userId'));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    // Guardar contrasenas de seguridad antes de borrar
    final decoyPass = prefs.getString('decoy_password');
    final emergencyPass = prefs.getString('emergency_password');
    final decoyUserId = prefs.getString('decoy_user_id');
    final decoyUsername = prefs.getString('decoy_username');
    await prefs.clear();
    // Restaurar contrasenas de seguridad
    if (decoyPass != null) await prefs.setString('decoy_password', decoyPass);
    if (emergencyPass != null) await prefs.setString('emergency_password', emergencyPass);
    if (decoyUserId != null) await prefs.setString('decoy_user_id', decoyUserId);
    if (decoyUsername != null) await prefs.setString('decoy_username', decoyUsername);
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
