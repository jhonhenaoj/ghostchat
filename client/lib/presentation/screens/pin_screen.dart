import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class PinScreen extends StatefulWidget {
  final String mode; // 'set', 'verify'
  final String? myUserId;
  final String? username;
  const PinScreen({super.key, required this.mode, this.myUserId, this.username});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String _error = '';
  final LocalAuthentication _auth = LocalAuthentication();
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 24).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeCtrl);
    if (widget.mode == 'verify') {
      Future.delayed(const Duration(milliseconds: 500), _tryBiometric);
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    try {
      final canAuth = await _auth.canCheckBiometrics;
      if (!canAuth) return;
      final authenticated = await _auth.authenticate(
        localizedReason: 'Usa tu huella para entrar a Ghost Chat',
      );
      if (authenticated && mounted) _unlock();
    } catch (_) {}
  }

  void _addDigit(String digit) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = '';
    });
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 100), _checkPin);
    }
  }

  void _deleteDigit() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _checkPin() async {
    if (widget.mode == 'set') {
      if (!_isConfirming) {
        setState(() { _confirmPin = _pin; _pin = ''; _isConfirming = true; });
      } else {
        if (_pin == _confirmPin) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('app_pin', _pin);
          await prefs.setBool('pin_enabled', true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ PIN configurado'), backgroundColor: Colors.green),
            );
            Navigator.pop(context);
          }
        } else {
          _shakeCtrl.forward(from: 0);
          setState(() { _error = 'Los PINs no coinciden'; _pin = ''; _isConfirming = false; });
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final savedPin = prefs.getString('app_pin') ?? '';
      if (_pin == savedPin) {
        _unlock();
      } else {
        _shakeCtrl.forward(from: 0);
        setState(() { _error = 'PIN incorrecto'; _pin = ''; });
      }
    }
  }

  void _unlock() {
    if (widget.myUserId != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(myUserId: widget.myUserId!, username: widget.username!),
      ));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Logo
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                boxShadow: [BoxShadow(color: _cyan.withOpacity(0.4), blurRadius: 20)],
              ),
              child: const Icon(Icons.lock, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              widget.mode == 'set'
                  ? (_isConfirming ? 'Confirma tu PIN' : 'Crea tu PIN')
                  : 'Ingresa tu PIN',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error.isNotEmpty ? _error : (widget.mode == 'set' ? 'Elige un PIN de 4 dígitos' : 'Ghost Chat está protegido'),
              style: TextStyle(color: _error.isNotEmpty ? Colors.red : Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // Puntos del PIN
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(_shakeCtrl.isAnimating ? _shakeAnim.value * ((_shakeCtrl.value * 4).floor() % 2 == 0 ? 1 : -1) : 0, 0),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) => Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? _cyan : Colors.white12,
                    boxShadow: i < _pin.length ? [BoxShadow(color: _cyan.withOpacity(0.5), blurRadius: 8)] : null,
                  ),
                )),
              ),
            ),

            const SizedBox(height: 48),

            // Teclado
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  _buildRow(['1', '2', '3']),
                  const SizedBox(height: 16),
                  _buildRow(['4', '5', '6']),
                  const SizedBox(height: 16),
                  _buildRow(['7', '8', '9']),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (widget.mode == 'verify')
                        _buildKey(Icons.fingerprint, () => _tryBiometric(), isIcon: true)
                      else
                        const SizedBox(width: 72),
                      _buildKey('0', () => _addDigit('0')),
                      _buildKey(Icons.backspace_outlined, () => _deleteDigit(), isIcon: true),
                    ],
                  ),
                ],
              ),
            ),

            if (widget.mode == 'verify') ...[
              const SizedBox(height: 32),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
                child: const Text('¿Olvidaste tu PIN? Cerrar sesión', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildKey(d, () => _addDigit(d))).toList(),
    );
  }

  Widget _buildKey(dynamic label, VoidCallback onTap, {bool isIcon = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surface,
          border: Border.all(color: _cyan.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Center(
          child: isIcon
              ? Icon(label as IconData, color: Colors.white70, size: 26)
              : Text(label as String, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w300)),
        ),
      ),
    );
  }
}
