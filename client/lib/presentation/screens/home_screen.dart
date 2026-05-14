import 'package:cached_network_image/cached_network_image.dart';
import 'package:animations/animations.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../main.dart' show pendingCallData;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import '../../../utils/socket_manager.dart';
import 'chat_screen.dart';
import 'call_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'profile_setup_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'invite_screen.dart';
import 'create_group_screen.dart';
import 'qr_screen.dart';
import 'contacts_screen.dart';
import 'call_history_screen.dart';
import '../../../utils/socket_manager.dart';
import 'profile_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  final bool isDecoy;
  const HomeScreen({super.key, required this.myUserId, required this.username, this.isDecoy = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _blue = Color(0xFF0066FF);
  static const String _serverUrl = 'http://162.243.174.252:9090';

  IOWebSocketChannel? _channel;
  List<Map<String, dynamic>> _contacts = [];
  Map<String, Map<String, dynamic>> _lastMessages = {};
  Map<String, int> _unreadCounts = {};
  Map<String, bool> _onlineStatus = {};
  bool _loading = true;
  List<Map<String, dynamic>> _groups = [];
  Timer? _heartbeatTimer;
  int _selectedTab = 0;
  String _displayName = '';
  int _myAvatarIndex = 0;
  String? _myAvatarUrl;

  // Todos los usuarios disponibles
  final List<Map<String, dynamic>> _allUsers = [
    {'id': '1', 'name': 'Usuario 1'},
    {'id': '2', 'name': 'Usuario 2'},
  ];

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    // Limpiar URLs de avatar cacheadas para forzar recarga fresca
    SharedPreferences.getInstance().then((p) {
      p.getKeys().where((k) => k.startsWith('avatar_url_')).forEach((k) => p.remove(k));
    });
    debugPrint('🎭 isDecoy: \${widget.isDecoy} myUserId: ${widget.myUserId}');
    if (widget.isDecoy) {
      // Modo señuelo - solo cargar datos falsos
      _displayName = 'Usuario';
      _loadContacts();
      return;
    }
    // Marcar app como activa para pausar background service
    SharedPreferences.getInstance().then((p) => p.setBool('app_active', true));
    _loadProfile();
    _loadContacts();
    _connectSocket();
    _listenCallkit();
    _registerFCMToken();
    // Verificar si hay llamada pendiente al abrir desde cero
    if (pendingCallData != null) {
      final fromId = pendingCallData!["from_user"]?.toString() ?? "";
      final isVideo = pendingCallData!["is_video"] == true;
      pendingCallData = null;
      if (fromId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Conectar socket inmediatamente
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          SocketManager().send({"type": "receiver_reconnected", "to": fromId});
          // Abrir CallScreen inmediatamente sin esperar offer
          if (!mounted) return;
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => CallScreen(
              callType: "receiver",
              remoteUserId: fromId,
              isVideo: isVideo,
              pendingOffer: SocketManager().pendingOffer,
              sendSignal: (msg) => SocketManager().send(msg),
            ),
          ));
        });
      }
    }
  }

  Future<void> _registerFCMToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('$_serverUrl/register-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': widget.myUserId, 'token': token}),
      );
    } catch (e) {
      debugPrint('❌ Error registrando FCM token: $e');
    }
  }

  void _listenCallkit() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null || !mounted) return;
      if (event.event == Event.actionCallAccept) {
        final data = event.body as Map<dynamic, dynamic>? ?? {};
        final fromId = data['extra']?['from_user']?.toString() ?? data['id']?.toString() ?? '';
        final isVideo = data['extra']?['is_video']?.toString() == 'true';
        final callerName = data['nameCaller']?.toString() ?? 'Usuario';
        if (fromId.isNotEmpty && mounted) {
          _openChatForCall(fromId, callerName, isVideo);
        }
      } else if (event.event == Event.actionCallDecline) {
        final data = event.body as Map<dynamic, dynamic>? ?? {};
        final callId = data['id']?.toString() ?? '';
        final fromId = data['extra']?['from_user']?.toString() ?? '';
        await FlutterCallkitIncoming.endCall(callId);
        // Notificar al caller que fue rechazado
        if (fromId.isNotEmpty) {
          SocketManager().send({'type': 'hangup', 'to': fromId});
        }
      }
    });
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type']?.toString() ?? '';
    final from = msg['from']?.toString() ?? '';

    if (type == 'call') {
      _showIncomingCall(msg);
      return;
    }


    if (type == 'user_online') {
      final userId = msg['user_id']?.toString() ?? '';
      setState(() => _onlineStatus[userId] = true);
      return;
    }
    if (type == 'user_offline') {
      final userId = msg['user_id']?.toString() ?? '';
      setState(() => _onlineStatus[userId] = false);
      return;
    }
    if (type == 'text' || type == 'image' || type == 'audio' || type == 'file' || type == 'location' || type == 'live_location') {
      setState(() {
        _lastMessages[from] = msg;
        _unreadCounts[from] = (_unreadCounts[from] ?? 0) + 1;
        // Actualizar badge del ícono
        final totalUnread = _unreadCounts.values.fold(0, (a, b) => a + b);
        AppBadgePlus.updateBadge(totalUnread);
        final exists = _contacts.any((c) => c['id'] == from);
        if (!exists) {
          _contacts.add({'id': from, 'display_name': 'Usuario $from', 'avatar_index': 0});
        }
      });
    }
  }

  void _showIncomingCall(Map<String, dynamic> msg) {
    final from = msg['from']?.toString() ?? '';
    final isVideo = msg['isVideo'] == true;
    final callerName = _contacts.firstWhere(
      (c) => c['id'] == from,
      orElse: () => {'display_name': 'Usuario $from'},
    )['display_name'] as String? ?? 'Usuario';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1321),
        title: Row(children: [
          Icon(isVideo ? Icons.videocam : Icons.call, color: const Color(0xFF00D4FF)),
          const SizedBox(width: 8),
          Text(isVideo ? 'Videollamada' : 'Llamada', style: const TextStyle(color: Colors.white)),
        ]),
        content: Text('$callerName te está llamando...', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SocketManager().send({'type': 'hangup', 'to': from});
            },
            child: const Text('Rechazar', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openChatForCall(from, callerName, isVideo);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Contestar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openChatForCall(String fromId, String fromName, bool isVideo) async {
    await Permission.microphone.request();
    if (isVideo) await Permission.camera.request();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(
        callType: 'receiver',
        remoteUserId: fromId,
        isVideo: isVideo,
        pendingOffer: null,
        sendSignal: (msg) => SocketManager().send(msg),
      ),
    ));
  }

  @override
  void dispose() {
    // Marcar app como inactiva para reactivar background service
    SharedPreferences.getInstance().then((p) => p.setBool('app_active', false));
    _heartbeatTimer?.cancel();
    SocketManager().removeListener(_onSocketMessage);
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _displayName = prefs.getString('display_name_${widget.myUserId}') ?? widget.username;
      _myAvatarIndex = prefs.getInt('avatar_index_${widget.myUserId}') ?? 0;
      _myAvatarUrl = prefs.getString('avatar_url_${widget.myUserId}');
    });
    // Cargar desde servidor
    try {
      final resp = await http.get(Uri.parse('http://162.243.174.252:9090/profile?user_id=${widget.myUserId}'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['avatar_url'] != null && data['avatar_url'] != '') {
          await prefs.setString('avatar_url_${widget.myUserId}', data['avatar_url']);
          setState(() => _myAvatarUrl = data['avatar_url']);
        }
        if (data['display_name'] != null && data['display_name'] != '') {
          setState(() => _displayName = data['display_name']);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    if (widget.isDecoy) {
      final now = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _contacts = [
          {"id": "fake1", "display_name": "Mamá", "avatar_index": 0, "avatar_url": "https://i.pravatar.cc/150?img=47"},
          {"id": "fake2", "display_name": "Papá", "avatar_index": 0, "avatar_url": "https://i.pravatar.cc/150?img=52"},
          {"id": "fake3", "display_name": "Carlos", "avatar_index": 0, "avatar_url": "https://i.pravatar.cc/150?img=33"},
          {"id": "fake4", "display_name": "Ana Trabajo", "avatar_index": 0, "avatar_url": "https://i.pravatar.cc/150?img=20"},
          {"id": "fake5", "display_name": "Luis", "avatar_index": 0, "avatar_url": "https://i.pravatar.cc/150?img=11"},
        ];
        _lastMessages = {
          "fake1": {"type": "text", "message": "Cuándo llegas a cenar?", "from": "fake1", "timestamp": "${now - 1800000}"},
          "fake2": {"type": "text", "message": "Ok cuídate hijo", "from": "fake2", "timestamp": "${now - 7200000}"},
          "fake3": {"type": "text", "message": "Jugamos futbol el sábado?", "from": "fake3", "timestamp": "${now - 86400000}"},
          "fake4": {"type": "text", "message": "Reunión a las 9am mañana", "from": "fake4", "timestamp": "${now - 172800000}"},
          "fake5": {"type": "text", "message": "Ya llegué gracias", "from": "fake5", "timestamp": "${now - 259200000}"},
        };
        _unreadCounts = {"fake1": 2, "fake3": 1};
        _loading = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedContacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
    final archivedList = prefs.getStringList('archived_${widget.myUserId}') ?? [];

    // PASO 0: Guardar último mensaje en caché local
    // (esto se hace en _updateInBackground)

    // PASO 1: Mostrar contactos desde caché inmediatamente
    List<Map<String, dynamic>> contacts = [];
    for (final id in savedContacts.where((id) => !archivedList.contains(id))) {
      final displayName = prefs.getString('display_name_$id') ?? 'Usuario';
      final avatarIndex = prefs.getInt('avatar_index_$id') ?? 0;
      final avatarUrl = prefs.getString('avatar_url_\$id') ?? 'http://162.243.174.252:9090/avatars/\$id.jpg';
      contacts.add({'id': id, 'display_name': displayName, 'avatar_index': avatarIndex, 'avatar_url': avatarUrl});
    }
    setState(() { _contacts = contacts; _loading = false; });

    // PASO 2: Actualizar en background sin bloquear UI
    _updateInBackground(contacts, prefs);
  }

  Future<void> _updateInBackground(List<Map<String, dynamic>> contacts, SharedPreferences prefs) async {
    try {
      // Cargar últimos mensajes en paralelo
      await Future.wait(contacts.map((contact) async {
        final otherId = contact['id'] as String;
        try {
          final resp = await http.get(Uri.parse(
            "${_serverUrl}/history?user_id=${widget.myUserId}&other_id=${otherId}"
          )).timeout(const Duration(seconds: 5));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final msgs = data['messages'] as List;
            if (msgs.isNotEmpty) {
              final last = Map<String, dynamic>.from(msgs.last);
              int unread = 0;
              for (final m in msgs) {
                if (m['from'] != widget.myUserId && m['read_at'] == null) unread++;
              }
              if (mounted) setState(() {
                _lastMessages[otherId] = last;
                _unreadCounts[otherId] = unread;
              });
            }
          }
        } catch (_) {}
      }));

      // Sincronizar contactos con servidor
      final resp = await http.get(Uri.parse('${_serverUrl}/contacts/load?user_id=${widget.myUserId}'))
        .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final contactsStr = data['contacts']?.toString() ?? '';
        if (contactsStr.isNotEmpty) {
          final serverEntries = contactsStr.split(',').where((s) => s.isNotEmpty).toList();
          final deletedContacts = prefs.getStringList('deleted_contacts_${widget.myUserId}') ?? [];
          for (final entry in serverEntries) {
            final parts = entry.split(':');
            final id = parts[0];
            if (deletedContacts.contains(id)) continue;
            final serverName = parts.length > 1 ? Uri.decodeComponent(parts[1]) : 'Usuario';
            String displayName = serverName;
            await prefs.setString('display_name_$id', displayName);
            final exists = contacts.any((c) => c['id'] == id);
            if (!exists) {
              String? avatarUrl = prefs.getString('avatar_url_$id');
              try {
                final profileResp = await http.get(Uri.parse('\${_serverUrl}/profile?user_id=\$id')).timeout(const Duration(seconds: 3));
                if (profileResp.statusCode == 200) {
                  final profileData = jsonDecode(profileResp.body);
                  if (profileData['avatar_url'] != null && profileData['avatar_url'].toString().isNotEmpty) {
                    avatarUrl = profileData['avatar_url'].toString().split('?')[0];
                    await prefs.setString('avatar_url_$id', avatarUrl!);
                  }
                  if (profileData['display_name'] != null && profileData['display_name'].toString().isNotEmpty) {
                    displayName = profileData['display_name'].toString();
                    await prefs.setString('display_name_$id', displayName);
                  }
                }
              } catch (_) {}
              contacts.add({'id': id, 'display_name': displayName, 'avatar_index': 0, 'avatar_url': avatarUrl});
            } else {
              // Actualizar nombre y avatar en contacto existente
              for (final c in contacts) {
                if (c['id'] == id) { c['display_name'] = displayName; break; }
              }
            }
          }
        }
      }
      // Cargar grupos
      final groupResp = await http.get(Uri.parse("${_serverUrl}/group/list?user_id=${widget.myUserId}"))
        .timeout(const Duration(seconds: 5));
      if (groupResp.statusCode == 200) {
        final data = jsonDecode(groupResp.body);
        if (mounted) setState(() => _groups = List<Map<String, dynamic>>.from(data['groups']));
      }

      // Ordenar por último mensaje
      contacts.sort((a, b) {
        final aTs = int.tryParse(_lastMessages[a['id']]?['timestamp']?.toString() ?? '0') ?? 0;
        final bTs = int.tryParse(_lastMessages[b['id']]?['timestamp']?.toString() ?? '0') ?? 0;
        return bTs.compareTo(aTs);
      });
      // Guardar contactos en cache local
      final allIds = contacts.map((c) => c['id'].toString()).toList();
      await prefs.setStringList('contacts_${widget.myUserId}', allIds);
      for (final c in contacts) {
        final id = c['id'].toString();
        await prefs.setString('display_name_$id', c['display_name']?.toString() ?? '');
        if (c['avatar_url'] != null) await prefs.setString('avatar_url_$id', c['avatar_url'].toString());
      }
      if (mounted) setState(() {
        // Fusionar con contactos existentes en lugar de reemplazar
        for (final c in contacts) {
          final exists = _contacts.any((e) => e['id'] == c['id']);
          if (!exists) _contacts.add(c);
        }
        // Ordenar
        _contacts.sort((a, b) {
          final aTs = int.tryParse(_lastMessages[a['id']]?['timestamp']?.toString() ?? '0') ?? 0;
          final bTs = int.tryParse(_lastMessages[b['id']]?['timestamp']?.toString() ?? '0') ?? 0;
          return bTs.compareTo(aTs);
        });
      });
    } catch (_) {}
  }


  void _connectSocket() {
    SocketManager().connect(widget.myUserId);
    SocketManager().addListener(_onSocketMessage);
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return "";
    try {
      final ms = int.tryParse(timestamp.toString());
      if (ms != null && ms > 1000000000000) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (diff.inMinutes < 1) return "ahora";
        if (diff.inMinutes < 60) return "hace ${diff.inMinutes}m";
        if (dt.day == now.day) return "${dt.hour.toString().padLeft(2,"0")}:${dt.minute.toString().padLeft(2,"0")}";
        if (diff.inDays == 1) return "ayer";
        if (diff.inDays < 7) return "hace ${diff.inDays}d";
        return "${dt.day}/${dt.month}";
      }
      return timestamp.toString().substring(0, 5);
    } catch (_) { return ""; }
  }

  String _previewMessage(Map<String, dynamic>? msg) {
    if (msg == null) return 'Toca para chatear';
    final type = msg['type']?.toString() ?? '';
    switch (type) {
      case 'text': return msg['message']?.toString() ?? '';
      case 'image': return '📷 Imagen';
      case 'audio': return '🎤 Audio';
      case 'file': return '📎 ${msg['filename'] ?? 'Archivo'}';
      case 'location': return '📍 Ubicación';
      case 'live_location': return '📡 Ubicación en vivo';
      case 'call_status':
        final status = msg['status']?.toString() ?? 'missed';
        final isVideo = msg['isVideo'] == true;
        if (status == 'missed') return isVideo ? '📹 Videollamada perdida' : '📞 Llamada perdida';
        if (status == 'rejected') return isVideo ? '📹 Videollamada rechazada' : '📞 Llamada rechazada';
        return isVideo ? '📹 Videollamada' : '📞 Llamada';
      default: return '';
  }
  }
  Future<void> _showArchivedChats() async {
    final prefs = await SharedPreferences.getInstance();
    final archived = prefs.getStringList('archived_${widget.myUserId}') ?? [];
    if (archived.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay chats archivados')),
      );
      return;
    }
    final contacts = archived.map((id) {
      final name = prefs.getString('display_name_$id') ?? id;
      final avatar = prefs.getString('avatar_url_$id');
      return {'id': id, 'name': name, 'avatar': avatar};
    }).toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1321),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const Padding(padding: EdgeInsets.all(16), child: Text('Chats archivados', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: contacts.length,
                  itemBuilder: (_, i) {
                    final c = contacts[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2A3550),
                        backgroundImage: c['avatar'] != null ? CachedNetworkImageProvider(c['avatar']!) : null,
                        child: c['avatar'] == null ? Text(c['name']![0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
                      ),
                      title: Text(c['name']!, style: const TextStyle(color: Colors.white)),
                      trailing: TextButton(
                        onPressed: () async {
                          final archived2 = prefs.getStringList('archived_${widget.myUserId}') ?? [];
                          archived2.remove(c['id']);
                          await prefs.setStringList('archived_${widget.myUserId}', archived2);
                          final contactsList = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
                          if (!contactsList.contains(c['id'])) {
                            contactsList.add(c['id']!);
                            await prefs.setStringList('contacts_${widget.myUserId}', contactsList);
                          }
                          contacts.removeAt(i);
                          setModalState(() {});
                          _loadContacts();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Chat desarchivado'), backgroundColor: Colors.green),
                          );
                        },
                        child: const Text('Desarchivar', style: TextStyle(color: Color(0xFF00D4FF))),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Future<void> _showChatOptions(Map<String, dynamic> contact, String otherId, String name) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1321),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.archive, color: Color(0xFF00D4FF)),
            title: const Text('Archivar chat', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              final archived = prefs.getStringList('archived_${widget.myUserId}') ?? [];
              if (!archived.contains(otherId)) archived.add(otherId);
              await prefs.setStringList('archived_${widget.myUserId}', archived);
              setState(() => _contacts.removeWhere((c) => c['id'] == otherId));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat archivado'), backgroundColor: Colors.blue),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off, color: Colors.orange),
            title: const Text('Silenciar', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              final muted = prefs.getStringList('muted_${widget.myUserId}') ?? [];
              if (!muted.contains(otherId)) muted.add(otherId);
              await prefs.setStringList('muted_${widget.myUserId}', muted);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$name silenciado'), backgroundColor: Colors.orange),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: Color(0xFF00D4FF)),
            title: const Text('Cambiar nombre', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final ctrl = TextEditingController(text: name);
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
              await prefs.setString('display_name_' + otherId, newName);
              setState(() => contact['display_name'] = newName);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Nombre cambiado a ' + newName), backgroundColor: Colors.green),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text("Bloquear contacto", style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF0D1321),
                  title: const Text("Bloquear contacto", style: TextStyle(color: Colors.white)),
                  content: Text("¿Bloquear a $name? No podrá enviarte mensajes ni llamarte.", style: const TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text("Bloquear"),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final prefs = await SharedPreferences.getInstance();
                final blocked = prefs.getStringList("blocked_${widget.myUserId}") ?? [];
                if (!blocked.contains(otherId)) blocked.add(otherId);
                await prefs.setStringList("blocked_${widget.myUserId}", blocked);
                setState(() => _contacts.removeWhere((c) => c["id"] == otherId));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$name bloqueado"), backgroundColor: Colors.red),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Borrar chat', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF0D1321),
                  title: const Text('Borrar chat', style: TextStyle(color: Colors.white)),
                  content: Text('¿Borrar el chat con $name?', style: const TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Borrar'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final prefs = await SharedPreferences.getInstance();
                final contacts = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
                contacts.remove(otherId);
                await prefs.setStringList('contacts_${widget.myUserId}', contacts);
                final deleted2 = prefs.getStringList('deleted_contacts_${widget.myUserId}') ?? [];
                if (!deleted2.contains(otherId)) deleted2.add(otherId);
                await prefs.setStringList('deleted_contacts_${widget.myUserId}', deleted2);
                // Sincronizar contactos activos con servidor (formato id:nombre)
                final activeContacts2 = prefs.getStringList('contacts_${widget.myUserId}') ?? [];
                try {
                  final entries2 = activeContacts2.map((id) {
                    final name = prefs.getString('display_name_$id') ?? 'Usuario';
                    return '$id:${Uri.encodeComponent(name)}';
                  }).toList();
                  await http.post(Uri.parse('http://162.243.174.252:9090/contacts/save'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'user_id': widget.myUserId, 'contacts': entries2.join(',')}));
                } catch (_) {}
                setState(() {
                  _contacts.removeWhere((c) => c['id'] == otherId);
                  _lastMessages.remove(otherId);
                  _unreadCounts.remove(otherId);
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat borrado'), backgroundColor: Colors.red),
                );
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _openChat(Map<String, dynamic> contact) async {
    final otherId = contact['id'] as String;
    setState(() => _unreadCounts[otherId] = 0);
    // Limpiar badge
    final totalUnread = _unreadCounts.values.fold(0, (a, b) => a + b);
    AppBadgePlus.updateBadge(totalUnread);

    await Navigator.push(context, PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        child: ChatScreen(
          myUserId: widget.myUserId,
          username: contact['display_name'] ?? contact['name'] ?? 'Usuario',
          remoteUserId: otherId,
        ),
      ),
      transitionDuration: const Duration(milliseconds: 300),
    ));
    // Recargar contactos y mensajes al volver
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ProfileSetupScreen(myUserId: widget.myUserId, username: widget.username),
              )).then((_) => _loadProfile()),
              child: CircleAvatar(
                radius: 19,
                backgroundColor: const Color(0xFF2A3550),
                backgroundImage: _myAvatarUrl != null ? CachedNetworkImageProvider(_myAvatarUrl!) : null,
                child: _myAvatarUrl == null ? Text(
                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ) : null,
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ghost Chat', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(_displayName, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 12)),
            ]),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add, color: Color(0xFF00D4FF)),
            tooltip: 'Crear grupo',
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(
                builder: (_) => CreateGroupScreen(myUserId: widget.myUserId),
              ));
              if (result == true) _loadContacts();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF0D1321),
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _loadContacts();
                  break;
                case 'profile':
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ProfileScreen(myUserId: widget.myUserId, username: widget.username),
                  ));
                  break;
                case 'invite':
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => InviteScreen(myUserId: widget.myUserId, username: widget.username),
                  )).then((result) { if (result == true) _loadContacts(); });
                  break;
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SettingsScreen(myUserId: widget.myUserId, username: widget.username),
                  )).then((_) => _loadContacts());
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Actualizar', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Perfil', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'invite', child: Row(children: [Icon(Icons.link, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Invitar contacto', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Ajustes', style: TextStyle(color: Colors.white))])),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
          : Column(
              children: [
                // Barra de busqueda
                Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _cyan.withOpacity(0.2)),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar conversaciones...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF00D4FF), size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                // Lista de contactos
                Expanded(
                  child: ListView(
                    children: [
                      // Grupos
                      if (_groups.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('GRUPOS', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        ),
                        ..._groups.map((group) {
                          final groupId = group['id'] as String;
                          final groupName = group['name'] as String? ?? 'Grupo';
                          final avatarIndex = group['avatar_index'] as int? ?? 0;
                          final groupEmojis = ['👥','🔱','⚔️','🛡️','🦅','🌟','💀','🔰','🎯','🦁'];
                          return InkWell(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(myUserId: widget.myUserId, username: groupName),
                            )),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
                              child: Row(children: [
                                Container(
                                  width: 52, height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF00D4FF).withOpacity(0.2),
                                    border: Border.all(color: const Color(0xFF00D4FF), width: 2),
                                  ),
                                  child: Center(child: Text(groupEmojis[avatarIndex.clamp(0, groupEmojis.length-1)], style: const TextStyle(fontSize: 26))),
                                ),
                                const SizedBox(width: 14),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(groupName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                  const Text('Grupo', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                ])),
                                const Icon(Icons.chevron_right, color: Colors.white24),
                              ]),
                            ),
                          );
                        }),
                        const Divider(color: Colors.white12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('CONTACTOS', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        ),
                      ],
                      // Contactos
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _contacts.length,
                    itemBuilder: (_, i) {
                      final contact = _contacts[i];
                      final otherId = contact['id'] as String;
                      final lastMsg = _lastMessages[otherId];
                      final unread = _unreadCounts[otherId] ?? 0;
                      final name = contact['display_name'] ?? contact['name'] ?? 'Usuario';
                      final preview = _previewMessage(lastMsg);
                      final time = _formatTime(lastMsg?['timestamp']);
                      final isFromMe = lastMsg?['from'] == widget.myUserId;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 150 + (i * 30).clamp(0, 300)),
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(20 * (1 - value), 0),
                            child: child,
                          ),
                        ),
                        child: Dismissible(
                          key: Key(otherId),
                          background: Container(
                            color: Colors.blue.shade800,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.archive, color: Colors.white),
                              Text('Archivar', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ]),
                          ),
                          secondaryBackground: Container(
                            color: Colors.red.shade800,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.delete, color: Colors.white),
                              Text('Borrar', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ]),
                          ),
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.endToStart) {
                              return await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF0D1321),
                                  title: const Text('Borrar chat', style: TextStyle(color: Colors.white)),
                                  content: Text('¿Borrar el chat con $name?', style: const TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Borrar'),
                                    ),
                                  ],
                                ),
                              ) ?? false;
                            } else {
                              final prefs = await SharedPreferences.getInstance();
                              final archived = prefs.getStringList('archived_\${widget.myUserId}') ?? [];
                              if (!archived.contains(otherId)) archived.add(otherId);
                              await prefs.setStringList('archived_\${widget.myUserId}', archived);
                              setState(() => _contacts.removeWhere((c) => c['id'] == otherId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Chat archivado'), backgroundColor: Colors.blue),
                              );
                              return false;
                            }
                          },
                          onDismissed: (direction) async {
                            if (direction == DismissDirection.endToStart) {
                              final prefs = await SharedPreferences.getInstance();
                              final contacts = prefs.getStringList('contacts_\${widget.myUserId}') ?? [];
                              contacts.remove(otherId);
                              await prefs.setStringList('contacts_\${widget.myUserId}', contacts);
                              final deleted = prefs.getStringList('deleted_contacts_\${widget.myUserId}') ?? [];
                              if (!deleted.contains(otherId)) deleted.add(otherId);
                              await prefs.setStringList('deleted_contacts_\${widget.myUserId}', deleted);
                              final activeContacts = prefs.getStringList('contacts_\${widget.myUserId}') ?? [];
                              try {
                                final entries = activeContacts.map((id) {
                                  final n = prefs.getString('display_name_\$id') ?? 'Usuario';
                                  return '\$id:\${Uri.encodeComponent(n)}';
                                }).toList();
                                await http.post(Uri.parse('http://162.243.174.252:9090/contacts/save'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode({'user_id': widget.myUserId, 'contacts': entries.join(',')}));
                              } catch (_) {}
                              setState(() {
                                _contacts.removeWhere((c) => c['id'] == otherId);
                                _lastMessages.remove(otherId);
                                _unreadCounts.remove(otherId);
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Chat borrado'), backgroundColor: Colors.red),
                              );
                            }
                          },
                          child: InkWell(
                            onTap: () => _openChat(contact),
                            onLongPress: () => _showChatOptions(contact, otherId, name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
                              ),
                              child: Row(
                                children: [
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 26,
                                        backgroundColor: const Color(0xFF2A3550),
                                        child: ClipOval(
                                          child: Image.network(
                                            'http://162.243.174.252:9090/avatars/$otherId.jpg',
                                            width: 52, height: 52, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_onlineStatus[otherId] == true)
                                        Positioned(
                                          right: 0, bottom: 0,
                                          child: Container(
                                            width: 12, height: 12,
                                            decoration: BoxDecoration(
                                              color: Colors.greenAccent,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: _bg, width: 2),
                                            ),
                                          ),
                                        ),
                                      if (unread > 0 && _onlineStatus[otherId] != true)
                                        Positioned(
                                          right: 0, top: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: unread > 9 ? Colors.red : _cyan,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: _bg, width: 2),
                                              boxShadow: [BoxShadow(color: _cyan.withOpacity(0.5), blurRadius: 4)],
                                            ),
                                            child: Text(
                                              unread > 99 ? '99+' : unread.toString(),
                                              style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(name,
                                                style: TextStyle(
                                                  color: unread > 0 ? _cyan : Colors.white,
                                                  fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500,
                                                  fontSize: 15,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(time, style: TextStyle(
                                              color: unread > 0 ? _cyan : Colors.white38,
                                              fontSize: 11,
                                            )),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (isFromMe) const Icon(Icons.done_all, size: 14, color: Colors.white38),
                                            if (isFromMe) const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(preview,
                                                style: TextStyle(
                                                  color: unread > 0 ? Colors.white70 : Colors.white38,
                                                  fontSize: 13,
                                                  fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (unread > 0)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: unread > 9 ? Colors.red : _cyan,
                                                  borderRadius: BorderRadius.circular(10),
                                                  boxShadow: [BoxShadow(
                                                    color: (unread > 9 ? Colors.red : _cyan).withOpacity(0.5),
                                                    blurRadius: 4,
                                                  )],
                                                ),
                                                child: Text(
                                                  unread > 99 ? '99+' : unread.toString(),
                                                  style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                      ),

                    ],
                  ),
                ),
              ],
            ),
      // Botón chats archivados
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showArchivedChats(),
        backgroundColor: const Color(0xFF0D1321),
        icon: const Icon(Icons.archive, color: Color(0xFF00D4FF)),
        label: const Text('Archivados', style: TextStyle(color: Color(0xFF00D4FF))),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (i) {
          if (i == 0) setState(() => _selectedTab = 0);
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => CallHistoryScreen(myUserId: widget.myUserId)));
          if (i == 2) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => ContactsScreen(myUserId: widget.myUserId, username: widget.username),
            )).then((_) => _loadContacts());
          }
        },
        backgroundColor: const Color(0xFF0D1321),
        selectedItemColor: const Color(0xFF00D4FF),
        unselectedItemColor: Colors.white38,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Llamadas'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Contactos'),
        ],
      ),
    );
  }
}
