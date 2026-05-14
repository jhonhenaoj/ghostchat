import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class InviteScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const InviteScreen({super.key, required this.myUserId, required this.username});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  String? _inviteLink;
  String? _inviteCode;
  bool _loading = false;
  final _codeController = TextEditingController();

  static const String _serverUrl = 'http://162.243.174.252:9090';
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  Future<void> _generateInvite() async {
    setState(() => _loading = true);
    try {
      final resp = await http.post(
        Uri.parse('$_serverUrl/invite/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.myUserId}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _inviteCode = data['code'];
          _inviteLink = data['link'];
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _joinInvite() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final resp = await http.get(Uri.parse('$_serverUrl/invite/join?code=$code'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final otherId = data['user_id'] as String;
        final otherName = data['display_name'] ?? data['username'] ?? 'Usuario';
        final avatarUrl = data['avatar_url'] ?? '';

        if (otherId == widget.myUserId) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No puedes agregarte a ti mismo'), backgroundColor: Colors.red),
          );
          return;
        }

        // Pedir nombre personalizado
        final nameController = TextEditingController(text: otherName);
        final customName = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _surface,
            title: const Text('Agregar contacto', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (avatarUrl.isNotEmpty)
                  CircleAvatar(radius: 40, backgroundImage: CachedNetworkImageProvider(avatarUrl)),
                const SizedBox(height: 16),
                const Text('¿Con qué nombre guardar este contacto?', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nombre del contacto',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0A0E1A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, nameController.text.trim().isEmpty ? otherName : nameController.text.trim()),
                style: ElevatedButton.styleFrom(backgroundColor: _cyan),
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (customName == null) return;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('display_name_$otherId', customName);
        if (avatarUrl.isNotEmpty) await prefs.setString('avatar_url_$otherId', avatarUrl);
        // Remover de lista negra si fue eliminado antes
        final deletedList = prefs.getStringList('deleted_contacts_${widget.myUserId}') ?? [];
        deletedList.remove(otherId);
        await prefs.setStringList('deleted_contacts_${widget.myUserId}', deletedList);
        final contacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
        if (!contacts.contains(otherId)) {
          contacts.add(otherId);
          await prefs.setStringList('contacts_${widget.myUserId}', contacts);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ $customName agregado'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Código inválido o expirado'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
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
        title: const Text('Invitar contacto', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Generar invitación
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🔗 Generar link de invitación', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Genera un código único que expira en 24 horas', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 16),
                        if (_inviteCode != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFF0A0E1A), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              children: [
                                Text(_inviteCode!, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8)),
                                const SizedBox(height: 8),
                                Text(_inviteLink ?? '', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _inviteCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('✅ Código copiado'), backgroundColor: Colors.green),
                                    );
                                  },
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copiar código'),
                                  style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ] else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _generateInvite,
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Generar invitación'),
                              style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Unirse con código
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🔑 Ingresar código de invitación', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Ingresa el código que te compartió tu contacto', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _codeController,
                          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 4),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 8,
                          decoration: InputDecoration(
                            hintText: '00000000',
                            hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 4),
                            filled: true,
                            fillColor: const Color(0xFF0A0E1A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _joinInvite,
                            icon: const Icon(Icons.person_add, size: 18),
                            label: const Text('Agregar contacto'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF88), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
