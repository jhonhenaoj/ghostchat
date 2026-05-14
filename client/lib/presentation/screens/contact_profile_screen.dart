import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_screen.dart';

class ContactProfileScreen extends StatefulWidget {
  final String contactId;
  final String contactName;
  final String myUserId;
  const ContactProfileScreen({super.key, required this.contactId, required this.contactName, required this.myUserId});

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  String _name = '';
  String _info = '';
  String? _avatarUrl;
  bool _loading = true;

  static const String _serverUrl = 'http://162.243.174.252:9090';
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _name = widget.contactName;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final resp = await http.get(Uri.parse('$_serverUrl/profile?user_id=${widget.contactId}'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _name = data['display_name'] ?? widget.contactName;
          _info = data['info'] ?? '';
          final url = data['avatar_url']?.toString() ?? '';
          _avatarUrl = url.isNotEmpty ? url : null;
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _openChat() {
    Navigator.pop(context);
  }

  void _startCall() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        myUserId: widget.myUserId,
        username: _name,
        remoteUserId: widget.contactId,
        autoAnswerCall: false,
      ),
    ));
    Future.delayed(const Duration(milliseconds: 500), () {});
  }

  void _startVideoCall() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        myUserId: widget.myUserId,
        username: _name,
        remoteUserId: widget.contactId,
        autoAnswerCall: false,
        autoAnswerIsVideo: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  backgroundColor: const Color(0xFF0D1321),
                  foregroundColor: Colors.white,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _avatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: _avatarUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF1A2035)),
                            errorWidget: (_, __, ___) => _buildInitialAvatar(),
                          )
                        : _buildInitialAvatar(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        color: _surface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            if (_info.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(_info, style: const TextStyle(color: Colors.white54, fontSize: 14)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        color: _surface,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _actionButton(Icons.message, 'Mensaje', _openChat),
                            _actionButton(Icons.call, 'Llamar', _startCall),
                            _actionButton(Icons.videocam, 'Video', _startVideoCall),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_info.isNotEmpty)
                        Container(
                          color: _surface,
                          child: ListTile(
                            leading: const Icon(Icons.info_outline, color: Color(0xFF00D4FF)),
                            title: const Text('Info', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            subtitle: Text(_info, style: const TextStyle(color: Colors.white, fontSize: 15)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInitialAvatar() {
    return Container(
      color: const Color(0xFF1A2035),
      child: Center(
        child: Text(
          _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
          style: const TextStyle(color: Colors.white, fontSize: 100, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 55, height: 55,
            decoration: BoxDecoration(color: _cyan.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: _cyan, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
