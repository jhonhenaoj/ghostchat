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
import 'create_group_screen.dart';
import 'qr_screen.dart';
import 'call_history_screen.dart';
import '../../../utils/socket_manager.dart';
import 'profile_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  const HomeScreen({super.key, required this.myUserId, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _blue = Color(0xFF0066FF);
  static const String _serverUrl = 'https://api.soluciones-publicitarias-latam.com';

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

  // Todos los usuarios disponibles
  final List<Map<String, dynamic>> _allUsers = [
    {'id': '1', 'name': 'Usuario 1'},
    {'id': '2', 'name': 'Usuario 2'},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadContacts();
    _connectSocket();
    _listenCallkit();
    _registerFCMToken();
    // Verificar si hay llamada pendiente al abrir desde cero
    if (pendingCallData != null) {
      final fromId = pendingCallData!['from_user']?.toString() ?? '';
      final isVideo = pendingCallData!['is_video'] == true;
      pendingCallData = null;
      if (fromId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          int attempts = 0;
          Future.doWhile(() async {
            await Future.delayed(const Duration(milliseconds: 500));
            attempts++;
            if (!mounted) return false;
            if (SocketManager().pendingOffer != null || attempts >= 8) {
              _openChatForCall(fromId, 'Usuario $fromId', isVideo);
              return false;
            }
            return true;
          });
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
      debugPrint('❌ Error registrando FCM token: \$e');
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

    if (type == 'text' || type == 'image' || type == 'audio' || type == 'file' || type == 'location' || type == 'live_location') {
      setState(() {
        _lastMessages[from] = msg;
        _unreadCounts[from] = (_unreadCounts[from] ?? 0) + 1;
        final exists = _contacts.any((c) => c['id'] == from);
        if (!exists) {
          _contacts.add({'id': from, 'display_name': 'Usuario \$from', 'avatar_index': 0});
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
    _heartbeatTimer?.cancel();
    SocketManager().removeListener(_onSocketMessage);
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _displayName = prefs.getString('display_name_${widget.myUserId}') ?? widget.username;
      _myAvatarIndex = prefs.getInt('avatar_index_${widget.myUserId}') ?? 0;
    });
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    // Cargar contactos guardados por QR
    List<Map<String, dynamic>> contacts = [];
    final prefs2 = await SharedPreferences.getInstance();
    final savedContacts = prefs2.getStringList('contacts_\${widget.myUserId}') ?? [];

    for (final id in savedContacts) {
      final displayName = prefs2.getString('display_name_$id') ?? 'Usuario';
      final avatarIndex = prefs2.getInt('avatar_index_$id') ?? 0;
      contacts.add({'id': id, 'display_name': displayName, 'avatar_index': avatarIndex});
    }

    // Si no hay contactos QR, intentar cargar del servidor
    if (contacts.isEmpty) {
      try {
        final resp = await http.get(Uri.parse("${_serverUrl}/users?my_id=${widget.myUserId}"));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          contacts = List<Map<String, dynamic>>.from(data['users']);
        }
      } catch (_) {}
    }

    // Cargar grupos
    try {
      final resp = await http.get(Uri.parse("${_serverUrl}/group/list?user_id=${widget.myUserId}"));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _groups = List<Map<String, dynamic>>.from(data['groups']));
      }
    } catch (_) {}

    // Cargar ultimo mensaje de cada contacto
    for (final contact in contacts) {
      final otherId = contact['id'] as String;
      try {
        final resp = await http.get(Uri.parse(
            "${_serverUrl}/history?user_id=${widget.myUserId}&other_id=${otherId}"));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final msgs = data['messages'] as List;
          if (msgs.isNotEmpty) {
            final last = Map<String, dynamic>.from(msgs.last);
            int unread = 0;
            for (final m in msgs) {
              if (m['from'] != widget.myUserId && m['read_at'] == null) unread++;
            }
            _lastMessages[otherId] = last;
            _unreadCounts[otherId] = unread;
          }
        }
      } catch (_) {}
    }

    // Ordenar por ultimo mensaje mas reciente primero
    contacts.sort((a, b) {
      final aId = a['id'] as String;
      final bId = b['id'] as String;
      final aTs = int.tryParse(_lastMessages[aId]?['timestamp']?.toString() ?? '0') ?? 0;
      final bTs = int.tryParse(_lastMessages[bId]?['timestamp']?.toString() ?? '0') ?? 0;
      return bTs.compareTo(aTs);
    });

    // Solo mostrar contactos que tienen mensajes o son contactos QR
    debugPrint("👥 Contactos cargados: \${contacts.length}");
    debugPrint("📨 Últimos mensajes: \${_lastMessages.keys.toList()}");
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  void _connectSocket() {
    SocketManager().connect(widget.myUserId);
    SocketManager().addListener(_onSocketMessage);
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      // Si es milliseconds
      final ms = int.tryParse(timestamp.toString());
      if (ms != null && ms > 1000000000000) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        final now = DateTime.now();
        if (dt.day == now.day) {
          return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }
        return '${dt.day}/${dt.month}';
      }
      // Si es formato HH:mm:ss
      return timestamp.toString().substring(0, 5);
    } catch (_) {
      return '';
    }
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
      default: return '';
    }
  }

  Future<void> _openChat(Map<String, dynamic> contact) async {
    final otherId = contact['id'] as String;
    setState(() => _unreadCounts[otherId] = 0);

    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        myUserId: widget.myUserId,
        username: contact['display_name'] ?? contact['name'] ?? 'Usuario',
        remoteUserId: otherId,
      ),
    ));
    // Recargar contactos y mensajes al volver
    setState(() {});
    _loadContacts();
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
              child: GhostAvatar(avatarIndex: _myAvatarIndex, size: 38),
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
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SettingsScreen(myUserId: widget.myUserId, username: widget.username),
                  ));
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Actualizar', style: TextStyle(color: Colors.white))])),
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
                      final avatarIndex = contact['avatar_index'] as int? ?? 0;
                      final name = contact['display_name'] ?? contact['name'] ?? 'Usuario';
                      final preview = _previewMessage(lastMsg);
                      final time = _formatTime(lastMsg?['timestamp']);
                      final isFromMe = lastMsg?['from'] == widget.myUserId;

                      return InkWell(
                        onTap: () => _openChat(contact),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
                          ),
                          child: Row(
                            children: [
                              // Avatar con indicador online
                              Stack(
                                children: [
                                  GhostAvatar(avatarIndex: avatarIndex, size: 52),
                                  Positioned(
                                    bottom: 2, right: 2,
                                    child: Container(
                                      width: 12, height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.green,
                                        border: Border.all(color: _bg, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),

                              // Nombre y preview
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(name, style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                                        )),
                                        Text(time, style: TextStyle(
                                          color: unread > 0 ? _cyan : Colors.white38,
                                          fontSize: 11,
                                        )),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (isFromMe) const Icon(Icons.done_all, size: 14, color: Color(0xFF00D4FF)),
                                        if (isFromMe) const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            preview,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: unread > 0 ? Colors.white70 : Colors.white38,
                                              fontSize: 13,
                                              fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        if (unread > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _cyan,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text('$unread', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (i) {
          if (i == 0) setState(() => _selectedTab = 0);
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => CallHistoryScreen(myUserId: widget.myUserId)));
          if (i == 2) {
            SharedPreferences.getInstance().then((prefs) {
              final displayName = prefs.getString('display_name_\${widget.myUserId}') ?? widget.username;
              final avatarIndex = prefs.getInt('avatar_index_\${widget.myUserId}') ?? 0;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => QrScreen(myUserId: widget.myUserId, displayName: displayName, avatarIndex: avatarIndex),
              )).then((result) { if (result == true) _loadContacts(); });
            });
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
