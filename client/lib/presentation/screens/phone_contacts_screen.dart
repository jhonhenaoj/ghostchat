import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';

class PhoneContactsScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const PhoneContactsScreen({super.key, required this.myUserId, required this.username});

  @override
  State<PhoneContactsScreen> createState() => _PhoneContactsScreenState();
}

class _PhoneContactsScreenState extends State<PhoneContactsScreen> {
  List<Map<String, dynamic>> _ghostContacts = [];
  bool _loading = true;
  String _searchQuery = '';

  static const String _serverUrl = 'http://162.243.174.252:9090';
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _loadGhostUsers();
  }

  Future<void> _loadGhostUsers() async {
    setState(() => _loading = true);
    try {
      final resp = await http.get(Uri.parse('$_serverUrl/users?my_id=${widget.myUserId}'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _ghostContacts = List<Map<String, dynamic>>.from(data['users']));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _addContact(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
    if (!contacts.contains(user['id'].toString())) {
      contacts.add(user['id'].toString());
      await prefs.setStringList('contacts_${widget.myUserId}', contacts);
      await prefs.setString('display_name_${user['id']}', user['display_name'] ?? user['username'] ?? '');
      if (user['avatar_url'] != null && user['avatar_url'] != '') {
        await prefs.setString('avatar_url_${user['id']}', user['avatar_url']);
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ ${user['display_name'] ?? user['username']} agregado'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _ghostContacts.where((u) {
      final name = (u['display_name'] ?? u['username'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1321),
        title: const Text('Usuarios en Ghost Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF)), onPressed: _loadGhostUsers),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar usuario...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: _surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
                : filtered.isEmpty
                    ? const Center(child: Text('No hay usuarios', style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final user = filtered[i];
                          final name = user['display_name'] ?? user['username'] ?? 'Usuario';
                          final avatarUrl = user['avatar_url'];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF2A3550),
                              backgroundImage: avatarUrl != null && avatarUrl != '' ? CachedNetworkImageProvider(avatarUrl) : null,
                              child: avatarUrl == null || avatarUrl == ''
                                  ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                                  : null,
                            ),
                            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text('@${user['username']}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.person_add, color: Color(0xFF00D4FF)), onPressed: () => _addContact(user)),
                                IconButton(
                                  icon: const Icon(Icons.chat, color: Colors.green),
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => ChatScreen(myUserId: widget.myUserId, username: name, remoteUserId: user['id'].toString()),
                                  )),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
