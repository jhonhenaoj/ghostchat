import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'call_screen.dart';
import '../../utils/socket_manager.dart';
import 'login_screen.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String _status = '';
  bool _isSettingUp = false;
  String _firstPin = '';
  String _setupStep = 'real'; // 'real' o 'decoy'
  bool _hasPin = false;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _checkPin();
  }

  Future<void> _checkPin() async {
    final prefs = await SharedPreferences.getInstance();
    final realPin = prefs.getString('real_pin');
    
    // Verificar si hay llamada entrante activa - saltar PIN
    try {
      // Verificar flag de llamada nativa
      final incomingCall = prefs.getBool("incoming_call_active") ?? false;
      if (incomingCall) {
        await prefs.remove("incoming_call_active");
        await prefs.remove("flutter.go_to_call");
        final userId = prefs.getString("user_id") ?? "";
        final username = prefs.getString("username") ?? "";
        // Usar datos del background service si están disponibles (más rápido)
        final fromUser = prefs.getString("flutter.pending_call_from") ?? 
                         prefs.getString("bg_call_from") ?? "";
        final isVideo = prefs.getBool("flutter.pending_call_video") ?? 
                        prefs.getBool("bg_call_video") ?? false;
         if (userId.isNotEmpty && mounted) {
           // Conectar socket y esperar conexion real
           SocketManager().connect(userId);
           // Esperar hasta que el socket conecte (max 5 segundos)
           int waitMs = 0;
           while (!SocketManager().isConnected && waitMs < 5000) {
             await Future.delayed(const Duration(milliseconds: 100));
             waitMs += 100;
           }
           if (!mounted) return;
           // Enviar receiver_reconnected cuando socket ya está conectado
           SocketManager().send({"type": "receiver_reconnected", "to": fromUser});
           await Future.delayed(const Duration(milliseconds: 100));
           if (!mounted) return;
           WidgetsBinding.instance.addPostFrameCallback((_) {
             if (!mounted) return;
             Navigator.pushReplacement(context, MaterialPageRoute(
               builder: (_) => CallScreen(
                 callType: "receiver",
                 remoteUserId: fromUser,
                 isVideo: isVideo,
                 pendingOffer: SocketManager().pendingOffer,
                 sendSignal: (msg) => SocketManager().send(msg),
               ),
             ));
           });
           return;
         }
      }
      // Verificar Flutter Callkit
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls != null && activeCalls.isNotEmpty) {
        final userId = prefs.getString("user_id") ?? "";
        final username = prefs.getString("username") ?? "";
        if (userId.isNotEmpty && mounted) {
          OneSignal.login("ghostchat_user_$userId");
          OneSignal.User.addTagWithKey("user_id", userId);
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => HomeScreen(myUserId: userId, username: username),
          ));
          return;
        }
      }
    } catch (_) {}
    
    setState(() {
      _hasPin = realPin != null;
      if (!_hasPin) {
        _isSettingUp = true;
        _status = 'Configura tu PIN real (4 dígitos)';
      } else {
        _status = 'Ingresa tu PIN';
      }
    });
  }

  Future<void> _handlePin() async {
    if (_pin.length < 4) return;
    final prefs = await SharedPreferences.getInstance();

    if (_isSettingUp) {
      if (_firstPin.isEmpty) {
        // Primer PIN ingresado
        if (_setupStep == 'real') {
          setState(() {
            _firstPin = _pin;
            _pin = '';
            _status = 'Confirma tu PIN real';
          });
        } else {
          setState(() {
            _firstPin = _pin;
            _pin = '';
            _status = 'Confirma tu PIN señuelo';
          });
        }
      } else {
        // Confirmar PIN
        if (_pin == _firstPin) {
          if (_setupStep == 'real') {
            await prefs.setString('real_pin', _pin);
            setState(() {
              _firstPin = '';
              _pin = '';
              _setupStep = 'decoy';
              _status = 'Ahora configura tu PIN señuelo\n(para mostrar app falsa)';
            });
          } else {
            await prefs.setString('decoy_pin', _pin);
            // Guardar datos falsos
            await _setupDecoyData(prefs);
            setState(() {
              _firstPin = '';
              _pin = '';
              _isSettingUp = false;
              _hasPin = true;
              _status = '✅ PIN configurado\nIngresa tu PIN';
            });
          }
        } else {
          setState(() {
            _firstPin = '';
            _pin = '';
            _status = 'PINs no coinciden. Intenta de nuevo';
          });
        }
      }
      return;
    }

    // Verificar PIN
    final realPin = prefs.getString('real_pin');
    final decoyPin = prefs.getString('decoy_pin');

    if (_pin == realPin) {
      // PIN real - cargar datos reales
      final userId = prefs.getString('user_id') ?? '';
      final username = prefs.getString('username') ?? '';
      if (userId.isEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        // Registrar en OneSignal al entrar con PIN
        OneSignal.login("ghostchat_user_$userId");
        OneSignal.User.addTagWithKey('user_id', userId);
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => HomeScreen(myUserId: userId, username: username),
        ));
      }
    } else if (_pin == decoyPin) {
      // PIN señuelo - cargar perfil falso
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => HomeScreen(
          myUserId: 'decoy_user',
          username: 'decoy',
          isDecoy: true,
        ),
      ));
    } else {
      setState(() {
        _pin = '';
        _status = '❌ PIN incorrecto';
      });
    }
  }

  Future<void> _setupDecoyData(SharedPreferences prefs) async {
    // Guardar contactos falsos
    await prefs.setStringList('contacts_decoy_user', ['fake1', 'fake2', 'fake3']);
    await prefs.setString('display_name_fake1', 'Mamá');
    await prefs.setString('display_name_fake2', 'Trabajo');
    await prefs.setString('display_name_fake3', 'Daniel');
  }

  void _addDigit(String digit) {
    if (_pin.length < 4) {
      setState(() => _pin += digit);
      if (_pin.length == 4) _handlePin();
    }
  }

  void _removeDigit() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
              ),
              child: const Icon(Icons.lock, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            const Text('GHOST CHAT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 40),
            // Puntos PIN
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? _cyan : Colors.white24,
                ),
              )),
            ),
            const SizedBox(height: 48),
            // Teclado
            ...[
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', '⌫'],
            ].map((row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row.map((digit) => GestureDetector(
                  onTap: () {
                    if (digit == '⌫') _removeDigit();
                    else if (digit.isNotEmpty) _addDigit(digit);
                  },
                  child: Container(
                    width: 75, height: 75,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: digit.isEmpty ? Colors.transparent : _surface,
                      border: digit.isEmpty ? null : Border.all(color: Colors.white12),
                    ),
                    child: Center(
                      child: Text(digit, style: TextStyle(
                        color: digit == '⌫' ? Colors.red.shade300 : Colors.white,
                        fontSize: digit == '⌫' ? 20 : 24,
                        fontWeight: FontWeight.w300,
                      )),
                    ),
                  ),
                )).toList(),
              ),
            )),
            const SizedBox(height: 20),
            if (_hasPin)
              TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Usar contraseña', style: TextStyle(color: Colors.white38)),
              ),
          ],
        ),
      ),
    );
  }
}
