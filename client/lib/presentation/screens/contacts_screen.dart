import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'qr_screen.dart';
import 'chat_screen.dart';
import 'phone_contacts_screen.dart';

class ContactsScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const ContactsScreen({super.key, required this.myUserId, required this.username});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const String _serverUrl = 'http://162.243.174.252:9090';
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _renameContact(Map<String, dynamic> contact) async {
    final ctrl = TextEditingController(text: contact['name']);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1321),
        title: const Text('Cambiar nombre', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nuevo nombre',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0A0E1A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D4FF)),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final contactId = contact['id'].toString();
    await prefs.setString('display_name_' + contactId, newName);
    setState(() => contact['name'] = newName);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Nombre cambiado a $newName'), backgroundColor: Colors.green),
    );
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final savedContacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
    final archived = prefs.getStringList('archived_${widget.myUserId}') ?? [];
    
    List<Map<String, dynamic>> contacts = [];
    for (final id in savedContacts.where((id) => !archived.contains(id))) {
      final name = prefs.getString('display_name_$id') ?? 'Usuario';
      final avatarUrl = prefs.getString('avatar_url_$id');
      contacts.add({'id': id, 'name': name, 'avatar_url': avatarUrl});
    }

    // Actualizar desde servidor
    for (final contact in contacts) {
      try {
        final resp = await http.get(Uri.parse('$_serverUrl/profile?user_id=${contact['id']}'));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data['display_name'] != null && data['display_name'] != '') {
            contact['server_name'] = data['display_name'];
          }
          if (data['avatar_url'] != null && data['avatar_url'] != '') {
            contact['avatar_url'] = data['avatar_url'];
          }
          if (data['info'] != null) contact['info'] = data['info'];
        }
      } catch (_) {}
    }

    setState(() { _contacts = contacts; _loading = false; });
  }

  Future<void> _inviteContact(String phone) async {
    final message = '¡Hola! Te invito a usar Ghost Chat, una app de mensajería segura y anónima. Descárgala aquí: http://162.243.174.252:9090/GhostChat.apk';
    final url = 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: message));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Mensaje copiado al portapapeles'), backgroundColor: Colors.green),
      );
    }
  }

  void _showInviteOptions() {
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const Padding(padding: EdgeInsets.all(16), child: Text('Invitar a Ghost Chat', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Número de teléfono (ej: 521234567890)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0A0E1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.phone, color: Color(0xFF00D4FF)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _inviteContact(phoneCtrl.text.trim());
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('Invitar por WhatsApp'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        const msg = '¡Hola! Te invito a usar Ghost Chat: http://162.243.174.252:9090/GhostChat.apk';
                        Clipboard.setData(const ClipboardData(text: msg));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Link copiado'), backgroundColor: Colors.green),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar link'),
                      style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _contacts.where((c) {
      final name = c['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1321),
        title: const Text('Contactos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00D4FF)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => QrScreen(myUserId: widget.myUserId, displayName: widget.username, avatarIndex: 0),
            )).then((_) => _loadContacts()),
          ),
          IconButton(
            icon: const Icon(Icons.contacts, color: Color(0xFF00D4FF)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PhoneContactsScreen(myUserId: widget.myUserId, username: widget.username),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.person_add, color: Color(0xFF00D4FF)),
            onPressed: _showInviteOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar contacto...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: _surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
              ),
            ),
          ),
          // Lista
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline, color: Colors.white24, size: 80),
                            const SizedBox(height: 16),
                            const Text('No tienes contactos', style: TextStyle(color: Colors.white38, fontSize: 16)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _showInviteOptions,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Invitar amigos'),
                              style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length + 1,
                        itemBuilder: (_, i) {
                          if (i == filtered.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: OutlinedButton.icon(
                                onPressed: _showInviteOptions,
                                icon: const Icon(Icons.person_add, color: Color(0xFF00D4FF)),
                                label: const Text('Invitar amigos a Ghost Chat', style: TextStyle(color: Color(0xFF00D4FF))),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF00D4FF))),
                              ),
                            );
                          }
                          final c = filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF2A3550),
                              backgroundImage: c['avatar_url'] != null ? CachedNetworkImageProvider(c['avatar_url']) : null,
                              child: c['avatar_url'] == null
                                  ? Text(c['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            title: Text(c['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: c['info'] != null
                                ? Text(c['info'], style: const TextStyle(color: Colors.white38, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.chat, color: Color(0xFF00D4FF)),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(myUserId: widget.myUserId, username: c['name'], remoteUserId: c['id']),
                              )),
                            ),
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(myUserId: widget.myUserId, username: c['name'], remoteUserId: c['id']),
                            )),
                            onLongPress: () => _renameContact(c),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
