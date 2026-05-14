import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const ProfileScreen({super.key, required this.myUserId, required this.username});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _infoController = TextEditingController();
  String? _avatarUrl;
  bool _loading = false;
  bool _editingName = false;
  bool _editingInfo = false;

  static const String _serverUrl = 'http://162.243.174.252:9090';
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('display_name_${widget.myUserId}') ?? widget.username;
      _infoController.text = prefs.getString('info_${widget.myUserId}') ?? 'Hola, estoy usando Ghost Chat';
      _avatarUrl = prefs.getString('avatar_url_${widget.myUserId}');
    });
    // Cargar desde servidor
    try {
      final resp = await http.get(Uri.parse('$_serverUrl/profile?user_id=${widget.myUserId}'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final prefs = await SharedPreferences.getInstance();
        // Solo actualizar nombre si el servidor tiene uno válido Y el local está vacío
        final localName = prefs.getString('display_name_${widget.myUserId}') ?? '';
        if (data['display_name'] != null && data['display_name'] != '' && localName.isEmpty) {
          _nameController.text = data['display_name'];
          await prefs.setString('display_name_${widget.myUserId}', data['display_name']);
        }
        if (data['info'] != null) {
          _infoController.text = data['info'];
          await prefs.setString('info_${widget.myUserId}', data['info']);
        }
        if (data['avatar_url'] != null) {
          setState(() => _avatarUrl = data['avatar_url']);
          await prefs.setString('avatar_url_${widget.myUserId}', data['avatar_url']);
        }
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await http.post(
        Uri.parse('$_serverUrl/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.myUserId, 'display_name': name}),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('display_name_${widget.myUserId}', name);
      setState(() => _editingName = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Nombre actualizado'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveInfo() async {
    final info = _infoController.text.trim();
    setState(() => _loading = true);
    try {
      await http.post(
        Uri.parse('$_serverUrl/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.myUserId, 'info': info}),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('info_${widget.myUserId}', info);
      setState(() => _editingInfo = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Info actualizada'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_serverUrl/upload-avatar'));
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
          const SnackBar(content: Text('✅ Foto actualizada'), backgroundColor: Colors.green),
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

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Foto de perfil', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Color(0xFF00D4FF)),
            title: const Text('Cámara', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Color(0xFF00D4FF)),
            title: const Text('Galería', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.gallery); },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1321),
        title: const Text('Perfil', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header con avatar
                  Container(
                    width: double.infinity,
                    color: const Color(0xFF0D1321),
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _showAvatarOptions,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 60,
                                backgroundColor: const Color(0xFF1A2035),
                                backgroundImage: _avatarUrl != null ? CachedNetworkImageProvider(_avatarUrl!) : null,
                                child: _avatarUrl == null
                                    ? const Icon(Icons.person, color: Colors.white70, size: 60)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0, right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: Color(0xFF00D4FF), shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Nombre
                  Container(
                    color: _surface,
                    child: ListTile(
                      leading: const Icon(Icons.person_outline, color: Color(0xFF00D4FF)),
                      title: const Text('Nombre', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      subtitle: _editingName
                          ? TextField(
                              controller: _nameController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              decoration: const InputDecoration(border: InputBorder.none),
                              onSubmitted: (_) => _saveName(),
                            )
                          : Text(_nameController.text, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      trailing: _editingName
                          ? IconButton(icon: const Icon(Icons.check, color: Color(0xFF00D4FF)), onPressed: _saveName)
                          : IconButton(icon: const Icon(Icons.edit, color: Colors.white54), onPressed: () => setState(() => _editingName = true)),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Info
                  Container(
                    color: _surface,
                    child: ListTile(
                      leading: const Icon(Icons.info_outline, color: Color(0xFF00D4FF)),
                      title: const Text('Info', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      subtitle: _editingInfo
                          ? TextField(
                              controller: _infoController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              maxLines: 3,
                              decoration: const InputDecoration(border: InputBorder.none),
                              onSubmitted: (_) => _saveInfo(),
                            )
                          : Text(_infoController.text, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      trailing: _editingInfo
                          ? IconButton(icon: const Icon(Icons.check, color: Color(0xFF00D4FF)), onPressed: _saveInfo)
                          : IconButton(icon: const Icon(Icons.edit, color: Colors.white54), onPressed: () => setState(() => _editingInfo = true)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
