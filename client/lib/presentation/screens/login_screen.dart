import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_setup_screen.dart';
import 'home_screen.dart';
import 'pin_screen.dart';
import 'register_screen.dart';
import '../../../utils/decoy_profile.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = true;
  bool _obscurePass = true;
  String? _error;

  late AnimationController _glowController;
  late AnimationController _floatController;
  late Animation<double> _glowAnim;
  late Animation<double> _floatAnim;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF111827);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _blue = Color(0xFF0066FF);

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _floatAnim = Tween<double>(begin: -8, end: 8).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));
    _checkSession();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final username = prefs.getString('username');
    if (userId != null && username != null) {
      if (!mounted) return;
      final pinEnabled = prefs.getBool('pin_enabled') ?? false;
      if (pinEnabled) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => PinScreen(mode: 'verify', myUserId: userId, username: username),
        ));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => HomeScreen(myUserId: userId, username: username),
        ));
      }
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.post(
        Uri.parse("http://162.243.174.252:9090/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": _userController.text.trim(), "password": _passController.text.trim()}),
      );
      final data = jsonDecode(response.body);

      // Verificar contraseña de emergencia
      if (await DecoyProfile.isEmergencyPassword(_passController.text.trim())) {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id') ?? '';
        await DecoyProfile.executeEmergency(userId);
        if (!mounted) return;
        setState(() => _error = 'Dispositivo limpiado');
        return;
      }

      // Verificar contraseña trampa - mostrar perfil falso
      if (await DecoyProfile.isDecoyPassword(_userController.text.trim(), _passController.text.trim())) {
        final decoy = await DecoyProfile.getDecoyProfile();
        if (decoy != null && mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => HomeScreen(myUserId: decoy['user_id']!, username: decoy['username']!),
          ));
          return;
        }
      }

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', data["user_id"]);
        await prefs.setString('username', data["username"]);
        if (!mounted) return;
        final prefs2 = await SharedPreferences.getInstance();
        await prefs2.setString('user_id', data["user_id"]);
        await prefs2.setString('username', data["username"]);
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(myUserId: data["user_id"], username: data["username"])));
      } else {
        setState(() => _error = data["error"] ?? "Error desconocido");
      }
    } catch (e) {
      setState(() => _error = "No se pudo conectar al servidor");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF))),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Partículas de fondo
          ...List.generate(20, (i) => _Particle(i)),

          // Círculo de fondo glow
          Positioned(
            top: -100,
            left: -100,
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) => Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    _blue.withOpacity(0.15 * _glowAnim.value),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo flotante
                  AnimatedBuilder(
                    animation: _floatAnim,
                    builder: (_, __) => Transform.translate(
                      offset: Offset(0, _floatAnim.value),
                      child: AnimatedBuilder(
                        animation: _glowAnim,
                        builder: (_, __) => Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0066FF), Color(0xFF00D4FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(color: _cyan.withOpacity(0.6 * _glowAnim.value), blurRadius: 40, spreadRadius: 10),
                              BoxShadow(color: _blue.withOpacity(0.4 * _glowAnim.value), blurRadius: 60, spreadRadius: 20),
                            ],
                          ),
                          child: const Icon(Icons.whatshot, size: 60, color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Título
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF0066FF)],
                    ).createShader(bounds),
                    child: const Text(
                      "GHOST CHAT",
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text("MESSAGING REIMAGINED", style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4), letterSpacing: 3)),

                  const SizedBox(height: 48),

                  // Campo usuario
                  _buildField(
                    controller: _userController,
                    hint: "Username",
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),

                  // Campo contraseña
                  _buildField(
                    controller: _passController,
                    hint: "Password",
                    icon: Icons.lock_outline,
                    isPassword: true,
                    onSubmit: (_) => _login(),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Botón login
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AnimatedBuilder(
                      animation: _glowAnim,
                      builder: (_, __) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                          boxShadow: [BoxShadow(color: _cyan.withOpacity(0.4 * _glowAnim.value), blurRadius: 20, spreadRadius: 2)],
                        ),
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _loading
                              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                              : const Text("LOG IN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Boton registro
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: RichText(
                      text: TextSpan(
                        text: "¿Eres nuevo? ",
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                        children: const [
                          TextSpan(
                            text: "Regístrate aquí",
                            style: TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text("👻 Ghost Chat — Secure & Private", style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    Function(String)? onSubmit,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.2)),
        boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.05), blurRadius: 10)],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePass : false,
        onSubmitted: onSubmit,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: const Color(0xFF00D4FF), size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: Colors.white30, size: 20),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }
}

class _Particle extends StatefulWidget {
  final int index;
  const _Particle(this.index);
  @override
  State<_Particle> createState() => _ParticleState();
}

class _ParticleState extends State<_Particle> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late double x, y, size, opacity;

  @override
  void initState() {
    super.initState();
    final rng = Random(widget.index * 42);
    x = rng.nextDouble();
    y = rng.nextDouble();
    size = rng.nextDouble() * 3 + 1;
    opacity = rng.nextDouble() * 0.5 + 0.1;
    _ctrl = AnimationController(vsync: this, duration: Duration(seconds: 3 + rng.nextInt(4)))..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x * MediaQuery.of(context).size.width,
      top: y * MediaQuery.of(context).size.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: opacity * _ctrl.value,
          child: Container(
            width: size, height: size,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00D4FF)),
          ),
        ),
      ),
    );
  }
}
