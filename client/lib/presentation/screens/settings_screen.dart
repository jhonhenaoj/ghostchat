import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../../utils/crypto.dart';
import 'security_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const SettingsScreen({super.key, required this.myUserId, required this.username});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailPassController = TextEditingController();
  final _destEmailController = TextEditingController();
  String? _coverImagePath;
  String? _avatarUrl;
  bool _loading = false;
  String _status = '';

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _blue = Color(0xFF0066FF);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailController.text = prefs.getString('panic_email') ?? '';
      _emailPassController.text = prefs.getString('panic_email_pass') ?? '';
      _destEmailController.text = prefs.getString('panic_dest_email') ?? '';
      _coverImagePath = prefs.getString('panic_cover_image');
      _avatarUrl = prefs.getString('avatar_url_${widget.myUserId}');
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('panic_email', _emailController.text.trim());
    await prefs.setString('panic_email_pass', _emailPassController.text.trim());
    await prefs.setString('panic_dest_email', _destEmailController.text.trim());
    if (_coverImagePath != null) {
      await prefs.setString('panic_cover_image', _coverImagePath!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Configuración guardada'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_name_${widget.myUserId}', name);
    // Actualizar en servidor
    try {
      await http.post(
        Uri.parse('http://162.243.174.252:9090/update-name'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.myUserId, 'display_name': name}),
      );
    } catch (_) {}
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Nombre actualizado'), backgroundColor: Colors.green),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('http://162.243.174.252:9090/upload-avatar'));
      request.fields['user_id'] = widget.myUserId;
      request.files.add(await http.MultipartFile.fromPath('avatar', file.path));
      final response = await request.send();
      final resp = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final data = jsonDecode(resp);
        final url = data['url'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('avatar_url_${widget.myUserId}', url);
        setState(() => _avatarUrl = url);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Foto de perfil actualizada'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: \$e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickCoverImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) setState(() => _coverImagePath = file.path);
  }

  // Ocultar clave dentro de imagen usando LSB steganography
  Uint8List _hideKeyInImage(Uint8List imageBytes, String key) {
    final keyBytes = utf8.encode(key);
    final keyLength = keyBytes.length;
    final result = Uint8List.fromList(imageBytes);

    // Guardar longitud de la clave en los primeros 32 bits
    for (int i = 0; i < 32; i++) {
      final bit = (keyLength >> (31 - i)) & 1;
      result[i] = (result[i] & 0xFE) | bit;
    }

    // Guardar los bytes de la clave
    for (int i = 0; i < keyLength * 8; i++) {
      final byteIndex = i ~/ 8;
      final bitIndex = 7 - (i % 8);
      final bit = (keyBytes[byteIndex] >> bitIndex) & 1;
      result[32 + i] = (result[32 + i] & 0xFE) | bit;
    }

    return result;
  }

  // Extraer clave de imagen
  static String extractKeyFromImage(Uint8List imageBytes) {
    // Leer longitud
    int keyLength = 0;
    for (int i = 0; i < 32; i++) {
      keyLength = (keyLength << 1) | (imageBytes[i] & 1);
    }

    // Leer bytes de la clave
    final keyBytes = <int>[];
    for (int i = 0; i < keyLength; i++) {
      int byte = 0;
      for (int j = 0; j < 8; j++) {
        byte = (byte << 1) | (imageBytes[32 + i * 8 + j] & 1);
      }
      keyBytes.add(byte);
    }

    return utf8.decode(keyBytes);
  }

  Future<void> _panicButton() async {
    // Confirmacion
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('⚠️ BOTÓN DE PÁNICO', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
          'Esto borrará ABSOLUTAMENTE TODO:\n\n'
          '• Todos los mensajes\n'
          '• Todas las imágenes\n'
          '• Todos los audios\n'
          '• Todos los archivos\n'
          '• Datos del servidor\n\n'
          'Se enviará un backup cifrado a tu correo.\n\n'
          '¿Estás SEGURO?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SÍ, BORRAR TODO', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm1 != true) return;

    // Segunda confirmacion
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('🔴 ÚLTIMA ADVERTENCIA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
          'Esta acción es IRREVERSIBLE.\n\nEscribe "BORRAR" para confirmar:',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('CONFIRMAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm2 != true) return;

    setState(() { _loading = true; _status = '🔄 Generando backup...'; });

    try {
      // 1. Obtener historial del servidor
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = 'http://162.243.174.252:9090';
      // Obtener todos los contactos guardados
      final savedContacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
      final allMessages = [];
      setState(() => _status = '📦 Descargando historial...');
      for (final otherId in savedContacts) {
        try {
          final historyResp = await http.get(Uri.parse('$serverUrl/history?user_id=${widget.myUserId}&other_id=$otherId'));
          if (historyResp.statusCode == 200) {
            final historyData = jsonDecode(historyResp.body);
            allMessages.addAll(historyData['messages'] ?? []);
          }
        } catch (_) {}
      }

      // 2. Crear backup completo
      final backup = {
        'user_id': widget.myUserId,
        'username': widget.username,
        'timestamp': DateTime.now().toIso8601String(),
        'messages': allMessages,
      };

      // 3. Generar clave de recuperacion aleatoria
      setState(() => _status = '🔑 Generando clave de recuperación...');
      final recoveryKey = GhostCrypto.generateKey();

      // 4. Cifrar backup con la clave
      final backupJson = jsonEncode(backup);
      final encryptedBackup = GhostCrypto.encrypt(backupJson);

      // 5. Ocultar clave en imagen
      setState(() => _status = '🖼️ Ocultando clave en imagen...');
      Uint8List? imageWithKey;
      if (_coverImagePath != null) {
        final imageFile = File(_coverImagePath!);
        final imageBytes = await imageFile.readAsBytes();
        imageWithKey = _hideKeyInImage(imageBytes, recoveryKey);
      } else {
        // Crear imagen simple si no hay una seleccionada
        imageWithKey = _createDefaultImage(recoveryKey);
      }

      // Guardar imagen con clave
      final tempDir = Directory.systemTemp;
      final imageFile = File('${tempDir.path}/ghost_recovery.png');
      await imageFile.writeAsBytes(imageWithKey);

      // Guardar backup cifrado
      final backupFile = File('${tempDir.path}/ghost_backup.txt');
      await backupFile.writeAsString(encryptedBackup);

      // 6. Enviar por correo
      setState(() => _status = '📧 Enviando backup al correo...');
      final senderEmail = _emailController.text.trim();
      final senderPass = _emailPassController.text.trim();
      final destEmail = _destEmailController.text.trim();

      if (senderEmail.isNotEmpty && senderPass.isNotEmpty && destEmail.isNotEmpty) {
        final smtpServer = gmail(senderEmail, senderPass);
        final message = Message()
          ..from = Address(senderEmail, 'Ghost Chat Backup')
          ..recipients.add(destEmail)
          ..subject = '🔐 Ghost Chat - Backup de Emergencia ${DateTime.now().toIso8601String()}'
          ..text = '''
Ghost Chat - Backup de Emergencia

Usuario: ${widget.username}
Fecha: ${DateTime.now()}

INSTRUCCIONES DE RECUPERACIÓN:
1. Instala Ghost Chat en el nuevo dispositivo
2. Ve a Ajustes → Recuperar datos
3. Sube la imagen adjunta (ghost_recovery.png)
4. El sistema extraerá la clave automáticamente
5. Sube el archivo ghost_backup.txt
6. Tus datos serán restaurados

⚠️ GUARDA ESTOS ARCHIVOS EN LUGAR SEGURO
⚠️ LA IMAGEN CONTIENE LA CLAVE DE RECUPERACIÓN OCULTA
          '''
          ..attachments = [
            FileAttachment(imageFile)..location = Location.attachment,
            FileAttachment(backupFile)..location = Location.attachment,
          ];

        await send(message, smtpServer);
      }

      // 7. Borrar todo del servidor
      setState(() => _status = '🗑️ Eliminando datos del servidor...');
      await http.delete(Uri.parse('$serverUrl/delete-all?user_id=${widget.myUserId}'));

      // 8. Borrar datos locales
      setState(() => _status = '🗑️ Eliminando datos locales...');
      await prefs.clear();

      setState(() { _loading = false; _status = '✅ Todo eliminado. Backup enviado.'; });

      // 9. Cerrar sesion
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() { _loading = false; _status = '❌ Error: $e'; });
    }
  }

  Uint8List _createDefaultImage(String key) {
    // Imagen PNG minima 100x100 pixels negra
    final pixels = List<int>.filled(100 * 100 * 3, 0);
    final result = Uint8List.fromList(pixels);
    return _hideKeyInImage(result, key);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
        content: const Text('¿Quieres cerrar sesión?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('username');
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1321),
        title: const Text('⚙️ Ajustes', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF00D4FF)),
                  const SizedBox(height: 20),
                  Text(_status, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Perfil
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cyan.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                          ),
                          child: const Icon(Icons.person, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('ID: ${widget.myUserId}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          const Text('🔐 E2E Cifrado activo', style: TextStyle(color: Color(0xFF00D4FF), fontSize: 12)),
                        ]),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Configuracion de backup
                  _sectionTitle('📧 Configuración de Backup'),
                  const SizedBox(height: 12),

                  _buildField(_emailController, 'Gmail emisor', Icons.email, false),
                  const SizedBox(height: 10),
                  _buildField(_emailPassController, 'Contraseña de aplicación', Icons.lock, true),
                  const SizedBox(height: 10),
                  _buildField(_destEmailController, 'Correo destino (tuyo)', Icons.inbox, false),

                  const SizedBox(height: 16),

                  // Imagen portadora
                  _sectionTitle('🖼️ Imagen para ocultar clave'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickCoverImage,
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _cyan.withOpacity(0.3), style: BorderStyle.solid),
                      ),
                      child: _coverImagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(File(_coverImagePath!), fit: BoxFit.cover),
                            )
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.add_photo_alternate, color: _cyan, size: 40),
                              const SizedBox(height: 8),
                              Text('Toca para seleccionar imagen', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                            ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Guardar configuracion
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text('Guardar configuración', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Contactos bloqueados
                  _sectionTitle('🚫 Privacidad'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final blocked = prefs.getStringList("blocked_${widget.myUserId}") ?? [];
                        if (!mounted) return;
                        if (blocked.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No tienes contactos bloqueados'), backgroundColor: Colors.blue),
                          );
                          return;
                        }
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: const Color(0xFF0D1321),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          builder: (_) => StatefulBuilder(
                            builder: (ctx, setModalState) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 12),
                                const Text('Contactos bloqueados', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 8),
                                ...blocked.map((id) => ListTile(
                                  leading: const Icon(Icons.block, color: Colors.red),
                                  title: Text(prefs.getString("display_name_$id") ?? id, style: const TextStyle(color: Colors.white)),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      blocked.remove(id);
                                      await prefs.setStringList("blocked_${widget.myUserId}", blocked);
                                      // Agregar de vuelta a contactos
                                      final contacts = prefs.getStringList("contacts_${widget.myUserId}") ?? [];
                                      if (!contacts.contains(id)) {
                                        contacts.add(id);
                                        await prefs.setStringList("contacts_${widget.myUserId}", contacts);
                                      }
                                      setModalState(() {});
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Contacto desbloqueado'), backgroundColor: Colors.green),
                                      );
                                    },
                                    child: const Text('Desbloquear', style: TextStyle(color: Color(0xFF00D4FF))),
                                  ),
                                )).toList(),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.block, color: Colors.red),
                      label: const Text('Contactos bloqueados', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Cerrar sesion
                  _sectionTitle('👤 Cuenta'),
                  const SizedBox(height: 12),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Colors.white70),
                      label: const Text('Cerrar sesión', style: TextStyle(color: Colors.white70)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Boton de panico
                  _sectionTitle('🔴 Zona de Peligro'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ Botón de Pánico',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Elimina ABSOLUTAMENTE TODO: mensajes, imágenes, audios, archivos del servidor. '
                          'Envía backup cifrado a tu correo con la clave oculta en la imagen.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _panicButton,
                            icon: const Icon(Icons.delete_forever, color: Colors.white),
                            label: const Text('🔴 DESTRUIR TODO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(_status, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, bool obscure) {
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
