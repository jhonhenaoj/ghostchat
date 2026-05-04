import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'package:http/http.dart' as http;
import 'profile_setup_screen.dart';

class QrScreen extends StatefulWidget {
  final String myUserId;
  final String displayName;
  final int avatarIndex;
  const QrScreen({super.key, required this.myUserId, required this.displayName, required this.avatarIndex});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _scanned = false;
  static const String _serverUrl = 'http://162.243.174.252:9090';

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // QR contiene info del usuario cifrada
  String get _qrData => jsonEncode({
    'user_id': widget.myUserId,
    'display_name': widget.displayName,
    'avatar_index': widget.avatarIndex,
    'app': 'ghost_chat',
  });

  Future<void> _onQrDetected(String rawValue) async {
    if (_scanned) return;
    try {
      final data = jsonDecode(rawValue) as Map<String, dynamic>;
      if (data['app'] != 'ghost_chat') {
        _showError('QR no válido');
        return;
      }
      setState(() => _scanned = true);
      final otherId = data['user_id'] as String;
      final otherName = data['display_name'] as String? ?? 'Usuario';
      final otherAvatar = data['avatar_index'] as int? ?? 0;

      if (otherId == widget.myUserId) {
        _showError('No puedes agregarte a ti mismo');
        setState(() => _scanned = false);
        return;
      }

      // Guardar contacto localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('display_name_$otherId', otherName);
      await prefs.setInt('avatar_index_$otherId', otherAvatar);

      // Agregar a lista de contactos
      final contacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
      if (!contacts.contains(otherId)) {
        contacts.add(otherId);
        await prefs.setStringList('contacts_${widget.myUserId}', contacts);
      }

      if (mounted) {
        // Mostrar confirmacion y abrir chat
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: _surface,
            title: const Text('✅ Contacto agregado', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GhostAvatar(avatarIndex: otherAvatar, size: 64),
                const SizedBox(height: 12),
                Text(otherName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Contacto agregado exitosamente', style: TextStyle(color: Colors.white54)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      myUserId: widget.myUserId,
                      username: otherName,
                      remoteUserId: otherId,
                    ),
                  ));
                },
                style: ElevatedButton.styleFrom(backgroundColor: _cyan),
                child: const Text('Abrir chat', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showError('QR inválido');
      setState(() => _scanned = false);
    }
  }

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Agregar contacto', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _cyan,
          labelColor: _cyan,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'Mi QR'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Escanear'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Mi QR
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Muestra este QR a tus contactos', style: TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: _cyan.withOpacity(0.3), blurRadius: 20)],
                    ),
                    child: QrImageView(
                      data: _qrData,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GhostAvatar(avatarIndex: widget.avatarIndex, size: 60),
                  const SizedBox(height: 8),
                  Text(widget.displayName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('ID: ${widget.myUserId}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _cyan.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.security, color: Color(0xFF00D4FF), size: 16),
                        SizedBox(width: 8),
                        Text('QR cifrado y seguro', style: TextStyle(color: Color(0xFF00D4FF), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tab 2: Escanear QR
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    MobileScanner(
                      onDetect: (capture) {
                        final barcode = capture.barcodes.firstOrNull;
                        if (barcode?.rawValue != null) {
                          _onQrDetected(barcode!.rawValue!);
                        }
                      },
                    ),
                    // Marco de escaneo
                    Center(
                      child: Container(
                        width: 250, height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: _cyan, width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          children: [
                            // Esquinas
                            Positioned(top: 0, left: 0, child: _corner()),
                            Positioned(top: 0, right: 0, child: Transform.rotate(angle: 1.5708, child: _corner())),
                            Positioned(bottom: 0, left: 0, child: Transform.rotate(angle: -1.5708, child: _corner())),
                            Positioned(bottom: 0, right: 0, child: Transform.rotate(angle: 3.14159, child: _corner())),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                color: _surface,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner, color: Color(0xFF00D4FF)),
                    SizedBox(width: 8),
                    Text('Apunta la cámara al QR de tu contacto', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _corner() => Container(
    width: 24, height: 24,
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: _cyan, width: 4), left: BorderSide(color: _cyan, width: 4)),
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(4)),
    ),
  );
}
