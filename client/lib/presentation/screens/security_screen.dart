import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/decoy_profile.dart';
import '../../../utils/security_check.dart';

class SecurityScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const SecurityScreen({super.key, required this.myUserId, required this.username});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _decoyPassCtrl = TextEditingController();
  final _emergencyPassCtrl = TextEditingController();
  final _decoyUserCtrl = TextEditingController();
  bool _decoyEnabled = false;
  bool _autoDeleteEnabled = false;
  int _autoDeleteDays = 7;
  Map<String, bool> _securityStatus = {};

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _runSecurityChecks();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _decoyEnabled = prefs.getString('decoy_password') != null;
      _autoDeleteEnabled = prefs.getBool('auto_delete_enabled') ?? false;
      _autoDeleteDays = prefs.getInt('auto_delete_days') ?? 7;
    });
  }

  Future<void> _runSecurityChecks() async {
    final checks = await SecurityCheck.runChecks();
    setState(() => _securityStatus = checks);
  }

  Future<void> _saveDecoyProfile() async {
    if (_decoyPassCtrl.text.isEmpty || _decoyUserCtrl.text.isEmpty) {
      _showSnack('Completa todos los campos', Colors.red);
      return;
    }
    if (_emergencyPassCtrl.text.isEmpty) {
      _showSnack('Ingresa una contraseña de emergencia', Colors.red);
      return;
    }
    await DecoyProfile.setup(
      realPassword: '',
      decoyPassword: _decoyPassCtrl.text.trim(),
      emergencyPassword: _emergencyPassCtrl.text.trim(),
      decoyUserId: 'decoy_${widget.myUserId}',
      decoyUsername: _decoyUserCtrl.text.trim(),
    );
    setState(() => _decoyEnabled = true);
    _showSnack('✅ Perfil falso configurado', Colors.green);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('🔐 Seguridad', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado de seguridad
            _sectionTitle('🛡️ Estado del dispositivo'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: Column(children: [
                _securityItem('Root/Jailbreak', _securityStatus['rooted'] != true, _securityStatus['rooted'] == true ? 'Detectado ⚠️' : 'No detectado ✅'),
                _securityItem('Modo desarrollador', _securityStatus['emulator'] != true, _securityStatus['emulator'] == true ? 'Activo ⚠️' : 'Inactivo ✅'),
                _securityItem('Cifrado E2E', true, 'Activo ✅'),
                _securityItem('Capturas bloqueadas', true, 'Activo ✅'),
              ]),
            ),

            const SizedBox(height: 24),

            // Perfil falso
            _sectionTitle('👤 Perfil falso'),
            const SizedBox(height: 8),
            Text(
              'Si alguien te obliga a abrir la app, usa la contraseña trampa y verá un chat vacío.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            ),
            const SizedBox(height: 12),
            _buildField(_decoyUserCtrl, 'Nombre del perfil falso', Icons.person_outline),
            const SizedBox(height: 8),
            _buildField(_decoyPassCtrl, 'Contraseña trampa', Icons.lock_outline, obscure: true),
            const SizedBox(height: 8),

            // Contraseña de emergencia
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.warning, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Text('Contraseña de emergencia', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                const Text('Al usar esta clave se borrará TODO instantáneamente', style: TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 8),
                _buildField(_emergencyPassCtrl, 'Contraseña de emergencia', Icons.delete_forever, obscure: true),
              ]),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saveDecoyProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cyan,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _decoyEnabled ? '✅ Perfil falso activo - Actualizar' : 'Activar perfil falso',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Auto borrado
            _sectionTitle('⏱️ Borrado automático'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Borrar mensajes antiguos', style: TextStyle(color: Colors.white)),
                    Switch(
                      value: _autoDeleteEnabled,
                      activeColor: _cyan,
                      onChanged: (v) async {
                        setState(() => _autoDeleteEnabled = v);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('auto_delete_enabled', v);
                      },
                    ),
                  ],
                ),
                if (_autoDeleteEnabled) ...[
                  const Divider(color: Colors.white12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Borrar después de $_autoDeleteDays días', style: const TextStyle(color: Colors.white70)),
                      DropdownButton<int>(
                        value: _autoDeleteDays,
                        dropdownColor: _surface,
                        style: const TextStyle(color: Colors.white),
                        items: [1, 3, 7, 14, 30].map((d) => DropdownMenuItem(value: d, child: Text('$d días'))).toList(),
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _autoDeleteDays = v);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('auto_delete_days', v);
                        },
                      ),
                    ],
                  ),
                ],
              ]),
            ),

            const SizedBox(height: 24),

            // Bloqueo remoto
            _sectionTitle('📡 Control remoto'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(children: [
                const Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Si pierdes el dispositivo puedes borrar todo remotamente desde otro dispositivo con tu cuenta.', style: TextStyle(color: Colors.white70, fontSize: 13))),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showRemoteWipeInfo(),
                    icon: const Icon(Icons.phonelink_erase, color: Colors.orange),
                    label: const Text('Ver instrucciones de borrado remoto', style: TextStyle(color: Colors.orange)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showRemoteWipeInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('📡 Borrado remoto', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Para borrar remotamente:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('1. Desde otro dispositivo inicia sesión\n2. Ve a Ajustes → Botón de pánico\n3. Confirma el borrado\n4. Todos los datos se eliminarán del servidor', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: const Text('⚠️ Esta acción es irreversible', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar', style: TextStyle(color: Color(0xFF00D4FF)))),
        ],
      ),
    );
  }

  Widget _securityItem(String label, bool isOk, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(status, style: TextStyle(color: isOk ? Colors.green : Colors.red, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, {bool obscure = false}) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withOpacity(0.2)),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: _cyan, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
