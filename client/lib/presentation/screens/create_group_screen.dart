import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_setup_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  final String myUserId;
  const CreateGroupScreen({super.key, required this.myUserId});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  Set<String> _selectedUsers = {};
  int _groupAvatar = 0;
  bool _loading = false;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  final List<String> _groupEmojis = ['👥','🔱','⚔️','🛡️','🦅','🌟','💀','🔰','🎯','🦁'];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final resp = await http.get(Uri.parse('http://162.243.174.252:9090/users?my_id=${widget.myUserId}'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _users = List<Map<String, dynamic>>.from(data['users']));
      }
    } catch (_) {}
  }

  Future<void> _createGroup() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un nombre para el grupo')));
      return;
    }
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona al menos un miembro')));
      return;
    }
    setState(() => _loading = true);
    try {
      final resp = await http.post(
        Uri.parse('http://162.243.174.252:9090/group/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameCtrl.text.trim(),
          'created_by': widget.myUserId,
          'avatar_index': _groupAvatar,
          'members': _selectedUsers.toList(),
        }),
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Grupo creado'), backgroundColor: Colors.green));
          Navigator.pop(context, true);
        }
      }
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Nuevo grupo', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _loading ? null : _createGroup,
            child: const Text('Crear', style: TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icono del grupo
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _cyan.withOpacity(0.2),
                      border: Border.all(color: _cyan, width: 2),
                    ),
                    child: Center(child: Text(_groupEmojis[_groupAvatar], style: const TextStyle(fontSize: 40))),
                  ),
                  const SizedBox(height: 8),
                  // Selector de emoji
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _groupEmojis.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => setState(() => _groupAvatar = i),
                        child: Container(
                          width: 44, height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _groupAvatar ? _cyan.withOpacity(0.3) : Colors.transparent,
                            border: Border.all(color: i == _groupAvatar ? _cyan : Colors.white24),
                          ),
                          child: Center(child: Text(_groupEmojis[i], style: const TextStyle(fontSize: 22))),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nombre del grupo
            Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Nombre del grupo',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: const Icon(Icons.group, color: Color(0xFF00D4FF), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Miembros
            Text('Agregar miembros (${_selectedUsers.length} seleccionados)',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            ..._users.map((user) {
              final id = user['id'] as String;
              final name = user['display_name'] ?? user['username'] ?? 'Usuario';
              final avatarIndex = user['avatar_index'] as int? ?? 0;
              final isSelected = _selectedUsers.contains(id);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) _selectedUsers.remove(id);
                  else _selectedUsers.add(id);
                }),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _cyan.withOpacity(0.15) : _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? _cyan : Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(children: [
                    GhostAvatar(avatarIndex: avatarIndex, size: 44),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 15))),
                    if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF00D4FF)),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
