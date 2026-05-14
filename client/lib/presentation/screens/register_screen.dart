import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'pin_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'pin_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _blue = Color(0xFF0066FF);

  Future<void> _register() async {
    final user = _userCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Usuario y contraseña requeridos');
      return;
    }
    if (pass != pass2) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Contraseña mínimo 6 caracteres');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse('http://162.243.174.252:9090/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass, 'display_name': name.isEmpty ? user : name}),
      );
      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        // Guardar sesion localmente
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', data['user_id']);
        await prefs.setString('username', data['username']);
        if (data['session_token'] != null) {
          await prefs.setString('session_token', data['session_token'].toString());
        }
        OneSignal.login("ghostchat_user_${data['user_id']}"); 
        OneSignal.User.addTagWithKey('user_id', data['user_id'].toString());
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => const PinScreen(),
        ));
      } else {
        setState(() => _error = data['error'] ?? 'Error al registrar');
      }
    } catch (e) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Crear cuenta', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Logo
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                boxShadow: [BoxShadow(color: _cyan.withOpacity(0.4), blurRadius: 30)],
              ),
              child: const Icon(Icons.person_add, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 24),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(colors: [Color(0xFF00D4FF), Color(0xFF0066FF)]).createShader(b),
              child: const Text('GHOST CHAT', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4)),
            ),
            const SizedBox(height: 8),
            Text('Crea tu cuenta segura', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
            const SizedBox(height: 40),

            _buildField(_userCtrl, 'Usuario', Icons.person_outline, false),
            const SizedBox(height: 12),
            _buildField(_nameCtrl, 'Nombre en el chat (opcional)', Icons.badge_outlined, false),
            const SizedBox(height: 12),
            _buildField(_passCtrl, 'Contraseña', Icons.lock_outline, true),
            const SizedBox(height: 12),
            _buildField(_pass2Ctrl, 'Confirmar contraseña', Icons.lock_outline, true),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                ]),
              ),
            ],

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity, height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                  boxShadow: [BoxShadow(color: _cyan.withOpacity(0.4), blurRadius: 15)],
                ),
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('CREAR CUENTA', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('¿Ya tienes cuenta? Inicia sesión', style: TextStyle(color: Color(0xFF00D4FF))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, bool obscure) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cyan.withOpacity(0.2)),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure ? _obscure : false,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: _cyan, size: 20),
          suffixIcon: obscure ? IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white30, size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
