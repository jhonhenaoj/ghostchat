import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const ProfileSetupScreen({super.key, required this.myUserId, required this.username});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  int _selectedAvatar = 0;

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _blue = Color(0xFF0066FF);

  // Avatares de soldados/militares usando emojis y iconos
  final List<Map<String, dynamic>> _avatars = [
    {'emoji': '🪖', 'name': 'Soldado', 'color': const Color(0xFF4CAF50)},
    {'emoji': '🎖️', 'name': 'Medalla', 'color': const Color(0xFFFFD700)},
    {'emoji': '⚔️', 'name': 'Guerrero', 'color': const Color(0xFF9E9E9E)},
    {'emoji': '🛡️', 'name': 'Defensor', 'color': const Color(0xFF2196F3)},
    {'emoji': '🦅', 'name': 'Águila', 'color': const Color(0xFF795548)},
    {'emoji': '🔱', 'name': 'Comandante', 'color': const Color(0xFFFF9800)},
    {'emoji': '💂', 'name': 'Guardia', 'color': const Color(0xFFE91E63)},
    {'emoji': '🚀', 'name': 'Élite', 'color': const Color(0xFF9C27B0)},
    {'emoji': '🎯', 'name': 'Francotirador', 'color': const Color(0xFFF44336)},
    {'emoji': '🌟', 'name': 'General', 'color': const Color(0xFFFFEB3B)},
    {'emoji': '🦁', 'name': 'León', 'color': const Color(0xFFFF5722)},
    {'emoji': '🐺', 'name': 'Lobo', 'color': const Color(0xFF607D8B)},
    {'emoji': '🦊', 'name': 'Zorro', 'color': const Color(0xFFFF7043)},
    {'emoji': '🦈', 'name': 'Tiburón', 'color': const Color(0xFF0288D1)},
    {'emoji': '🔰', 'name': 'Recluta', 'color': const Color(0xFF43A047)},
    {'emoji': '💀', 'name': 'Fantasma', 'color': const Color(0xFF37474F)},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('display_name_${widget.myUserId}') ?? widget.username;
      _selectedAvatar = prefs.getInt('avatar_index_${widget.myUserId}') ?? 0;
    });
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un nombre'), backgroundColor: Colors.red),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_name_${widget.myUserId}', name);
    await prefs.setInt('avatar_index_${widget.myUserId}', _selectedAvatar);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Perfil guardado'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _saveAndContinue() async {
    await _saveProfile();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(myUserId: widget.myUserId, username: _nameController.text.trim())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _avatars[_selectedAvatar];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Configura tu perfil', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Avatar seleccionado grande
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected['color'].withOpacity(0.2),
                border: Border.all(color: selected['color'], width: 3),
                boxShadow: [BoxShadow(color: selected['color'].withOpacity(0.4), blurRadius: 20, spreadRadius: 5)],
              ),
              child: Center(child: Text(selected['emoji'], style: const TextStyle(fontSize: 60))),
            ),

            const SizedBox(height: 8),
            Text(selected['name'], style: TextStyle(color: selected['color'], fontSize: 16, fontWeight: FontWeight.bold)),

            const SizedBox(height: 32),

            // Nombre de usuario
            Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cyan.withOpacity(0.3)),
              ),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                maxLength: 20,
                decoration: InputDecoration(
                  hintText: 'Tu nombre en el chat',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: const Icon(Icons.person, color: Color(0xFF00D4FF)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  counterStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Grid de avatares
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Elige tu avatar:', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _avatars.length,
              itemBuilder: (_, i) {
                final avatar = _avatars[i];
                final isSelected = i == _selectedAvatar;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatar = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatar['color'].withOpacity(isSelected ? 0.3 : 0.1),
                      border: Border.all(
                        color: isSelected ? avatar['color'] : Colors.white.withOpacity(0.1),
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected ? [BoxShadow(color: avatar['color'].withOpacity(0.5), blurRadius: 12)] : null,
                    ),
                    child: Center(child: Text(avatar['emoji'], style: TextStyle(fontSize: isSelected ? 30 : 26))),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Botón guardar
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                  boxShadow: [BoxShadow(color: _cyan.withOpacity(0.4), blurRadius: 15)],
                ),
                child: ElevatedButton(
                  onPressed: _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Guardar y continuar', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Widget reutilizable para mostrar avatar en cualquier pantalla
class GhostAvatar extends StatelessWidget {
  final int avatarIndex;
  final double size;
  final bool showGlow;

  const GhostAvatar({super.key, required this.avatarIndex, this.size = 40, this.showGlow = true});

  static const List<Map<String, dynamic>> avatars = [
    {'emoji': '🪖', 'color': Color(0xFF4CAF50)},
    {'emoji': '🎖️', 'color': Color(0xFFFFD700)},
    {'emoji': '⚔️', 'color': Color(0xFF9E9E9E)},
    {'emoji': '🛡️', 'color': Color(0xFF2196F3)},
    {'emoji': '🦅', 'color': Color(0xFF795548)},
    {'emoji': '🔱', 'color': Color(0xFFFF9800)},
    {'emoji': '💂', 'color': Color(0xFFE91E63)},
    {'emoji': '🚀', 'color': Color(0xFF9C27B0)},
    {'emoji': '🎯', 'color': Color(0xFFF44336)},
    {'emoji': '🌟', 'color': Color(0xFFFFEB3B)},
    {'emoji': '🦁', 'color': Color(0xFFFF5722)},
    {'emoji': '🐺', 'color': Color(0xFF607D8B)},
    {'emoji': '🦊', 'color': Color(0xFFFF7043)},
    {'emoji': '🦈', 'color': Color(0xFF0288D1)},
    {'emoji': '🔰', 'color': Color(0xFF43A047)},
    {'emoji': '💀', 'color': Color(0xFF37474F)},
  ];

  @override
  Widget build(BuildContext context) {
    final idx = avatarIndex.clamp(0, avatars.length - 1);
    final avatar = avatars[idx];
    final color = avatar['color'] as Color;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.2),
        border: Border.all(color: color, width: 2),
        boxShadow: showGlow ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)] : null,
      ),
      child: Center(child: Text(avatar['emoji'], style: TextStyle(fontSize: size * 0.5))),
    );
  }
}
