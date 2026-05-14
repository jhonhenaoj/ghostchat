import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _userCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;
  bool _obscure = true;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  Future<void> _resetPassword() async {
    final user = _userCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (user.isEmpty || code.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Todos los campos son requeridos');
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
        Uri.parse('http://162.243.174.252:9090/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'code': code, 'new_password': pass}),
      );
      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        setState(() => _success = 'Contraseña actualizada. Inicia sesión.');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        });
      } else {
        setState(() => _error = data['error'] ?? 'Error al resetear');
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
        title: const Text('Recuperar contraseña', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _cyan.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _cyan.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Color(0xFF00D4FF)),
                SizedBox(width: 12),
                Expanded(child: Text('Contacta al administrador para obtener tu código de recuperación de 6 dígitos.', style: TextStyle(color: Colors.white70))),
              ]),
            ),
            const SizedBox(height: 24),
            const Text('Usuario', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _userCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true, fillColor: _surface,
                hintText: 'Tu nombre de usuario',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.person, color: Color(0xFF00D4FF)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Código de recuperación', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _codeCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true, fillColor: _surface,
                hintText: '000000',
                hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Nueva contraseña', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true, fillColor: _surface,
                hintText: 'Mínimo 6 caracteres',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.lock, color: Color(0xFF00D4FF)),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white38), onPressed: () => setState(() => _obscure = !_obscure)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Confirmar contraseña', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _pass2Ctrl,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true, fillColor: _surface,
                hintText: 'Repite la contraseña',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF00D4FF)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ],
            if (_success != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(_success!, style: const TextStyle(color: Colors.green)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _loading ? const CircularProgressIndicator(color: Colors.black) : const Text('Restablecer contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
