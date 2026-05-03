import 'dart:async';
import '../../../utils/crypto.dart';
import '../../../utils/socket_manager.dart';
import '../../../utils/key_exchange.dart';
import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'call_screen.dart';
import 'settings_screen.dart';
import 'call_history_screen.dart';
import 'profile_setup_screen.dart';
import 'camera_screen.dart';
import 'package:camera/camera.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class ChatScreen extends StatefulWidget {
  final String myUserId;
  final String username;
  final String? remoteUserId;
  final bool autoAnswerCall;
  final bool autoAnswerIsVideo;
  const ChatScreen({super.key, required this.myUserId, required this.username, this.remoteUserId, this.autoAnswerCall = false, this.autoAnswerIsVideo = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String serverUrl = "https://api.soluciones-publicitarias-latam.com";
  final _httpClient = http.Client();

  String get remoteUserId => widget.remoteUserId ?? (widget.myUserId == "1" ? "2" : "1");
  String get wsUrl => "wss://api.soluciones-publicitarias-latam.com/ws?user_id=${widget.myUserId}";

  IOWebSocketChannel? channel;
  FlutterSoundRecorder? recorder;
  FlutterSoundPlayer? player;

  bool isRecording = false;
  bool isSendingFile = false;
  bool _inCall = false;
  bool _pendingIsVideo = false;
  String? audioPath;
  String? _pendingOffer;
  bool _waitingToAutoAnswer = false;
  String? _pendingCallerId;

  // Funciones de mensaje
  Map<String, dynamic>? _replyingTo;
  bool _showEmoji = false;
  Map<int, String> _reactions = {};
  Timer? _liveLocationTimer;
  Set<int> _selectedMessages = {};
  bool _isSelecting = false;
  bool _isTyping = false;
  bool _remoteIsTyping = false;
  Timer? _typingTimer;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _searchMode = false;
  String _searchQuery = '';
  int? _destroySeconds;
  final TextEditingController _searchController = TextEditingController();
  Set<String> _readTimestamps = {};
  DateTime? _lastReadSent;
  String? _remoteAvatarUrl;
  int _myAvatarIndex = 0;
  int _remoteAvatarIndex = 0;
  String _displayName = '';
  Map<String, dynamic>? _editingMsg;
  List<Map<String, dynamic>> _pinnedMessages = [];
  Set<int> _starredIndexes = {};
  Set<int> _deletedForMe = {};
  Set<String> _deletedTimestamps = {};

  final GlobalKey<CallScreenState> _callKey = GlobalKey<CallScreenState>();
  List<Map<String, dynamic>> messages = [];

  @override
  void initState() {
    super.initState();
    initAudio();
    initSocket();
    Future.delayed(const Duration(milliseconds: 500), () => _loadHistory());
    if (widget.autoAnswerCall) {
      _waitingToAutoAnswer = true;
      _pendingCallerId = widget.remoteUserId;
    }
    _startHeartbeat();
    _initFCM();
    _initKeyExchange();
    _loadRemoteAvatar();
    _markMessagesAsRead();
    _loadDeletedMessages();
  }

  Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    debugPrint("🔔 FCM Token: $token");
    // Enviar token al servidor
    try {
      await http.post(
        Uri.parse("$serverUrl/register-token"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.myUserId, "token": token}),
      );
    } catch (e) {
      debugPrint("❌ Error registrando token: $e");
    }

    // Notificacion cuando app esta abierta
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notification.title ?? "Nueva notificación"),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  Future<void> _loadHistory() async {
    debugPrint("📱 myUserId: " + widget.myUserId + " remoteUserId: " + remoteUserId);
    try {
      final response = await http.get(
        Uri.parse("$serverUrl/history?user_id=${widget.myUserId}&other_id=$remoteUserId"),
      );
      debugPrint("📦 History status: " + response.statusCode.toString());
      debugPrint("📦 History body: " + response.body.substring(0, response.body.length > 100 ? 100 : response.body.length));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> msgs = data["messages"];
        debugPrint("📦 Mensajes cargados: " + msgs.length.toString());
        setState(() {
          messages = msgs.map((m) {
            final msg = Map<String, dynamic>.from(m);
            if (msg["type"] == "text" && msg["message"] != null) {
              msg["message"] = GhostCrypto.decrypt(msg["message"].toString());
            }
            if (msg["reply_to"] != null) {
              msg["reply_to"] = GhostCrypto.decrypt(msg["reply_to"].toString());
            }
            return msg;
          }).toList();
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("❌ Error cargando historial: $e");
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> initAudio() async {
    recorder = FlutterSoundRecorder();
    player = FlutterSoundPlayer();
    await recorder!.openRecorder();
    await player!.openPlayer();
  }

  Future<void> _loadDeletedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final deleted = prefs.getStringList('deleted_${widget.myUserId}_$remoteUserId') ?? [];
    setState(() => _deletedTimestamps = deleted.toSet());
  }

  Future<void> _saveDeletedMessage(String timestamp) async {
    _deletedTimestamps.add(timestamp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('deleted_${widget.myUserId}_$remoteUserId', _deletedTimestamps.toList());
  }

  Future<void> _markMessagesAsRead() async {
    // Evitar spam: solo enviar si pasaron mas de 5 segundos
    final now = DateTime.now();
    if (_lastReadSent != null && now.difference(_lastReadSent!).inSeconds < 5) return;
    _lastReadSent = now;
    try {
      await http.post(
        Uri.parse('$serverUrl/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'from_user': remoteUserId, 'to_user': widget.myUserId}),
      );
    } catch (_) {}
  }

  Future<void> _loadRemoteAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myAvatarIndex = prefs.getInt('avatar_index_\${widget.myUserId}') ?? 0;
      _remoteAvatarIndex = prefs.getInt('avatar_index_$remoteUserId') ?? 0;
      _displayName = prefs.getString('display_name_\${widget.myUserId}') ?? widget.username;
    });
    final url = prefs.getString('avatar_url_$remoteUserId');
    if (url != null) setState(() => _remoteAvatarUrl = url);
    // Intentar cargar desde servidor
    try {
      final resp = await http.get(Uri.parse('$serverUrl/avatar/$remoteUserId'));
      if (resp.statusCode == 200) {
        final avatarUrl = '$serverUrl/avatars/$remoteUserId.jpg';
        await prefs.setString('avatar_url_$remoteUserId', avatarUrl);
        if (mounted) setState(() => _remoteAvatarUrl = avatarUrl);
      }
    } catch (_) {}
  }

  void initSocket() => _connectSocket();

  void _startHeartbeat() {
    // SocketManager maneja heartbeat internamente
  }

  void _reconnectSocket() {
    // SocketManager maneja reconexión internamente
  }

  Future<void> _initKeyExchange() async {
    // Generar o cargar par de claves
    var myPublic = await KeyExchange.loadPublicKey(widget.myUserId);
    if (myPublic == null) {
      final keyPair = KeyExchange.generateKeyPair();
      await KeyExchange.saveKeyPair(widget.myUserId, keyPair);
      myPublic = keyPair['public']!;
    }
    // Enviar clave publica al otro usuario
    Future.delayed(const Duration(seconds: 1), () {
      SocketManager().send({
        'type': 'dh_public_key',
        'to': remoteUserId,
        'public_key': myPublic,
      });
    });
    // Cargar secreto compartido si ya existe
    final sharedSecret = await KeyExchange.loadSharedSecret(remoteUserId);
    if (sharedSecret != null) {
      GhostCrypto.setSharedSecret(sharedSecret);
      debugPrint('🔐 Clave E2E cargada para usuario $remoteUserId');
    }
  }

  void _connectSocket() {
    // Usar socket global
    SocketManager().connect(widget.myUserId);
    SocketManager().addListener(_onSocketMessage);
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg["type"]?.toString() ?? "";
    final from = msg["from"]?.toString() ?? "";
    // Permitir mensajes WebRTC aunque no tengan from correcto
    final isWebRTC = type == "offer" || type == "answer" || type == "ice" || type == "call" || type == "hangup";
    if (!isWebRTC && from != remoteUserId && from != widget.myUserId) return;
    if (type == "read_receipt") {
      setState(() {
        for (var m in messages) {
          if (m["from"] == widget.myUserId) m["read"] = true;
        }
      });
      return;
    }
    if (type == "live_location_update") {
      final liveId = msg["live_id"]?.toString() ?? "";
      setState(() {
        for (var m in messages) {
          if (m["live_id"]?.toString() == liveId) {
            m["message"] = msg["message"]?.toString() ?? "";
            m["url"] = msg["url"]?.toString() ?? "";
            break;
          }
        }
      });
      return;
    }
    if (type == "dh_public_key") {
      final theirPublic = msg["public_key"]?.toString() ?? "";
      KeyExchange.saveTheirPublicKey(from, theirPublic).then((_) async {
        final myPrivate = await KeyExchange.loadPrivateKey(widget.myUserId);
        if (myPrivate != null && theirPublic.isNotEmpty) {
          final sharedSecret = KeyExchange.computeSharedSecret(theirPublic, myPrivate);
          await KeyExchange.saveSharedSecret(from, sharedSecret);
          GhostCrypto.setSharedSecret(sharedSecret);
        }
      });
      return;
    }
    if (type == "typing") {
      setState(() => _remoteIsTyping = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _remoteIsTyping = false);
      });
      return;
    }
    if (type == "stop_typing") {
      setState(() => _remoteIsTyping = false);
      return;
    }
    if (type == "delete_for_all") {
      final ts = msg["target_timestamp"]?.toString() ?? "";
      setState(() {
        messages.removeWhere((m) => m["timestamp"]?.toString() == ts);
      });
      return;
    }
    if (type == "edit") {
      final ts = msg["target_timestamp"]?.toString() ?? "";
      final newText = GhostCrypto.decrypt(msg["new_message"]?.toString() ?? "");
      setState(() {
        for (var m in messages) {
          if (m["timestamp"]?.toString() == ts) {
            m["message"] = newText;
            m["edited"] = true;
            break;
          }
        }
      });
      return;
    }
    if (type == "ping") return;
    if (type == "call") { _pendingIsVideo = msg["isVideo"] == true; _pendingCallerId = msg["from"]?.toString() ?? remoteUserId; if (_waitingToAutoAnswer) { /* esperar offer */ } else { _showIncomingCall(msg); } return; }
    if (type == "hangup") { _handleRemoteHangup(); return; }
    if (type == "offer") { _pendingOffer = msg["sdp"]?.toString(); final callFrom = msg["from"]?.toString(); if (callFrom != null && callFrom.isNotEmpty) _pendingCallerId = callFrom; if (_inCall) { _callKey.currentState?.handleOffer(msg["sdp"]); } else if (_waitingToAutoAnswer) { _waitingToAutoAnswer = false; _pendingIsVideo = widget.autoAnswerIsVideo; _answerCall(_pendingCallerId ?? remoteUserId); } return; }
    if (type == "answer" && _inCall) { _callKey.currentState?.handleAnswer(msg["sdp"]); return; }
    if (type == "ice" && _inCall) { _callKey.currentState?.handleIce(msg); return; }
    // Mensaje normal
    if (msg["type"] == "text" && msg["message"] != null) {
      msg["message"] = GhostCrypto.decrypt(msg["message"].toString());
    }
    if (msg["reply_to"] != null) {
      msg["reply_to"] = GhostCrypto.decrypt(msg["reply_to"].toString());
    }
    setState(() => messages.add(msg));
    _scrollToBottom();
    _markMessagesAsRead();
  }

  void _connectSocketOld() {
    channel?.sink.close();
    channel = IOWebSocketChannel.connect(wsUrl);
    channel!.stream.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg["type"]?.toString() ?? "";

      // Intercambio de claves DH
      if (type == "dh_public_key") {
        final theirPublic = msg["public_key"]?.toString() ?? "";
        final fromUser = msg["from"]?.toString() ?? "";
        KeyExchange.saveTheirPublicKey(fromUser, theirPublic).then((_) async {
          final myPrivate = await KeyExchange.loadPrivateKey(widget.myUserId);
          if (myPrivate != null && theirPublic.isNotEmpty) {
            final sharedSecret = KeyExchange.computeSharedSecret(theirPublic, myPrivate);
            await KeyExchange.saveSharedSecret(fromUser, sharedSecret);
            GhostCrypto.setSharedSecret(sharedSecret);
            debugPrint("🔐 Secreto compartido establecido con usuario $fromUser");
          }
        });
        return;
      }
      // WebRTC manejado por _onSocketMessage
      if (type == "delete_for_all") { _handleRemoteDelete(msg); return; }
      if (type == "edit") { _handleRemoteEdit(msg); return; }

      if (msg["type"] == "text" && msg["message"] != null) {
        msg["message"] = GhostCrypto.decrypt(msg["message"].toString());
      }
      if (msg["reply_to"] != null) {
        msg["reply_to"] = GhostCrypto.decrypt(msg["reply_to"].toString());
      }
      setState(() => messages.add(msg));
      _scrollToBottom();
      // Marcar como leido automaticamente
      _markMessagesAsRead();
    }, onDone: () {
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _connectSocket(); });
    }, onError: (e) {
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _connectSocket(); });
    });
  }

  void _handleRemoteDelete(Map<String, dynamic> msg) {
    final timestamp = msg["target_timestamp"]?.toString();
    setState(() {
      messages.removeWhere((m) => m["timestamp"]?.toString() == timestamp);
    });
  }

  void _handleRemoteEdit(Map<String, dynamic> msg) {
    final timestamp = msg["target_timestamp"]?.toString();
    final newText = GhostCrypto.decrypt(msg["new_message"]?.toString() ?? "");
    setState(() {
      for (var m in messages) {
        if (m["timestamp"]?.toString() == timestamp) {
          m["message"] = newText;
          m["edited"] = true;
          break;
        }
      }
    });
  }

  void sendSignal(Map<String, dynamic> msg) {
    SocketManager().send(msg);
  }

  // ── Menú contextual al mantener presionado ──
  void _showMessageOptions(int index, Map<String, dynamic> msg) {
    final isMe = msg["from"]?.toString() == widget.myUserId;
    final type = msg["type"]?.toString() ?? "";
    final isStarred = _starredIndexes.contains(index);
    final isPinned = _pinnedMessages.any((m) => m["timestamp"] == msg["timestamp"]);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),

            // Reenviar
            _optionTile(Icons.forward, "Reenviar", Colors.teal, () {
              Navigator.pop(context);
              _forwardMessage(msg);
            }),
            // Responder
            _optionTile(Icons.reply, "Responder", Colors.blue, () {
              Navigator.pop(context);
              setState(() => _replyingTo = msg);
            }),

            // Copiar (solo texto)
            if (type == "text")
              _optionTile(Icons.copy, "Copiar", Colors.grey, () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg["message"]?.toString() ?? ""));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copiado")));
              }),

            // Editar (solo mis mensajes de texto)
            if (isMe && type == "text")
              _optionTile(Icons.edit, "Editar", Colors.orange, () {
                Navigator.pop(context);
                setState(() {
                  _editingMsg = msg;
                  _controller.text = msg["message"]?.toString() ?? "";
                });
              }),

            // Destacar
            _optionTile(
              isStarred ? Icons.star : Icons.star_border,
              isStarred ? "Quitar destacado" : "Destacar",
              Colors.amber,
              () {
                Navigator.pop(context);
                setState(() {
                  if (isStarred) _starredIndexes.remove(index);
                  else _starredIndexes.add(index);
                });
              },
            ),

            // Fijar
            _optionTile(
              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              isPinned ? "Desfijar" : "Fijar mensaje",
              Colors.purple,
              () {
                Navigator.pop(context);
                setState(() {
                  if (isPinned) _pinnedMessages.removeWhere((m) => m["timestamp"] == msg["timestamp"]);
                  else _pinnedMessages.add(msg);
                });
              },
            ),

            // Eliminar para mí
            _optionTile(Icons.delete_outline, "Eliminar para mí", Colors.red.shade300, () {
              Navigator.pop(context);
              final ts = msg["timestamp"]?.toString() ?? "";
              setState(() => _deletedForMe.add(index));
              _saveDeletedMessage(ts);
            }),

            // Eliminar para todos (solo mis mensajes)
            if (isMe)
              _optionTile(Icons.delete_forever, "Eliminar para todos", Colors.red, () {
                Navigator.pop(context);
                final timestamp = msg["timestamp"]?.toString();
                sendSignal({'type': 'delete_for_all', 'to': remoteUserId, 'target_timestamp': timestamp});
                setState(() => messages.removeAt(index));
              }),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      onTap: onTap,
    );
  }

  void _startCall() async {
    await Permission.microphone.request();
    sendSignal({'type': 'call', 'to': remoteUserId, 'from': widget.myUserId});
    setState(() => _inCall = true);
    final callStart = DateTime.now();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(key: _callKey, callType: 'caller', remoteUserId: remoteUserId, sendSignal: sendSignal),
    )).then((_) {
      setState(() => _inCall = false);
      CallHistoryScreen.saveCall(
        myUserId: widget.myUserId,
        remoteUserId: remoteUserId,
        remoteName: widget.username,
        isVideo: false,
        isIncoming: false,
        answered: true,
        duration: DateTime.now().difference(callStart),
      );
    });
  }

  void _startVideoCall() async {
    await Permission.microphone.request();
    await Permission.camera.request();
    sendSignal({'type': 'call', 'to': remoteUserId, 'from': widget.myUserId, 'isVideo': true});
    setState(() => _inCall = true);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(key: _callKey, callType: 'caller', remoteUserId: remoteUserId, sendSignal: sendSignal, isVideo: true),
    )).then((_) => setState(() => _inCall = false));
  }

  void _showIncomingCall(Map<String, dynamic> msg) {
    final from = msg["from"]?.toString() ?? "?";
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(msg["isVideo"] == true ? "📹 Videollamada entrante" : "📞 Llamada entrante"),
        content: Text("Usuario $from te está llamando"),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); sendSignal({'type': 'hangup', 'to': from}); },
            child: const Text("Rechazar", style: TextStyle(color: Colors.red))),
          ElevatedButton(onPressed: () { Navigator.pop(context); _answerCall(from); },
            child: const Text("Contestar")),
        ],
      ),
    );
  }

  void _answerCall(String from) async {
    await Permission.microphone.request();
    if (_pendingIsVideo) await Permission.camera.request();
    setState(() => _inCall = true);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(key: _callKey, callType: 'receiver', pendingOffer: _pendingOffer,
          remoteUserId: from, isVideo: _pendingIsVideo, sendSignal: sendSignal),
    )).then((_) => setState(() => _inCall = false));
  }

  void _handleRemoteHangup() {
    if (_inCall) {
      Navigator.of(context).pop();
      setState(() => _inCall = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La llamada terminó")));
    }
  }

  void sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Editar mensaje existente
    if (_editingMsg != null) {
      final timestamp = _editingMsg!["timestamp"]?.toString();
      sendSignal({'type': 'edit', 'to': remoteUserId, 'target_timestamp': timestamp, 'new_message': text});
      setState(() {
        for (var m in messages) {
          if (m["timestamp"]?.toString() == timestamp) {
            m["message"] = text;
            m["edited"] = true;
            break;
          }
        }
        _editingMsg = null;
      });
      _controller.clear();
      return;
    }

    final encrypted = GhostCrypto.encrypt(text);
    final msgData = {
      "to": remoteUserId,
      "type": "text",
      "message": encrypted,
      if (_replyingTo != null) "reply_to": GhostCrypto.encrypt(_replyingTo!["message"]?.toString() ?? ""),
      if (_replyingTo != null) "reply_from": _replyingTo!["from"]?.toString() ?? "",
    };
    SocketManager().send(msgData);
    setState(() {
      final newIndex = messages.length;
      final newMsg = {
        ...msgData,
        "from": widget.myUserId,
        "message": text,
        "timestamp": DateTime.now().millisecondsSinceEpoch.toString(),
      };
      messages.add(newMsg);
      if (_destroySeconds != null) _scheduleDestroy(newIndex, _destroySeconds!);
      _replyingTo = null;
    });
    _controller.clear();
    _scrollToBottom();
  }

  Future<void> _openCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (result == null) return;
    final XFile file = result['file'];
    final bool isVideo = result['isVideo'];

    if (isVideo) {
      // Enviar video como archivo
      setState(() => isSendingFile = true);
      try {
        final request = http.MultipartRequest("POST", Uri.parse("$serverUrl/upload-file"));
        request.files.add(await http.MultipartFile.fromPath("file", file.path, filename: "video.mp4"));
        final response = await _httpClient.send(request).timeout(const Duration(seconds: 120));
        final resp = await response.stream.bytesToString();
        if (response.statusCode == 200) {
          final data = jsonDecode(resp);
          final fileSize = await File(file.path).length();
          SocketManager().send({"to": remoteUserId, "type": "file", "url": data["url"], "filename": "video.mp4", "size": fileSize});
        }
      } catch (e) {
        debugPrint("❌ Error enviando video: \$e");
      } finally {
        setState(() => isSendingFile = false);
      }
    } else {
      // Enviar foto como imagen
      final request = http.MultipartRequest("POST", Uri.parse("$serverUrl/upload"));
      request.files.add(await http.MultipartFile.fromPath("file", file.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final resp = await response.stream.bytesToString();
        final url = jsonDecode(resp)["url"] as String;
        SocketManager().send({"to": remoteUserId, "type": "image", "url": url});
        setState(() => messages.add({"type": "image", "url": url, "from": widget.myUserId}));
        _scrollToBottom();
      }
    }
  }

  Future<void> sendImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => isSendingFile = true);
    try {
      final request = http.MultipartRequest("POST", Uri.parse("$serverUrl/upload"));
      request.files.add(await http.MultipartFile.fromPath("file", file.path));
      final client = http.Client();
      final response = await client.send(request);
      if (response.statusCode == 200) {
        final resp = await response.stream.bytesToString();
        final url = jsonDecode(resp)["url"] as String;
        SocketManager().send({"to": remoteUserId, "type": "image", "url": url});
        setState(() => messages.add({"type": "image", "url": url, "from": widget.myUserId, "timestamp": DateTime.now().millisecondsSinceEpoch.toString()}));
        _scrollToBottom();
      }
      client.close();
    } catch(e) {
      debugPrint("Error enviando imagen: " + e.toString());
    } finally {
      setState(() => isSendingFile = false);
    }
  }

  Future<void> sendFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;
    setState(() => isSendingFile = true);
    try {
      final request = http.MultipartRequest("POST", Uri.parse("$serverUrl/upload-file"));
      request.files.add(await http.MultipartFile.fromPath("file", picked.path!, filename: picked.name));
      final response = await _httpClient.send(request).timeout(const Duration(seconds: 60));
      final resp = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final data = jsonDecode(resp);
        SocketManager().send({"to": remoteUserId, "type": "file", "url": data["url"], "filename": picked.name, "size": picked.size});
      }
    } catch (e) {
      debugPrint("❌ Error enviando archivo: $e");
    } finally {
      setState(() => isSendingFile = false);
    }
  }

  Future<void> startRecording() async {
    await Permission.microphone.request();
    final dir = await getTemporaryDirectory();
    audioPath = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';
    await recorder!.startRecorder(toFile: audioPath, codec: Codec.pcm16WAV);
    setState(() => isRecording = true);
  }

  Future<void> stopRecording() async {
    await recorder!.stopRecorder();
    setState(() => isRecording = false);
    if (audioPath == null) return;
    final request = http.MultipartRequest("POST", Uri.parse("$serverUrl/upload-audio"));
    request.files.add(await http.MultipartFile.fromPath("audio", audioPath!));
    final response = await request.send();
    if (response.statusCode == 200) {
      final resp = await response.stream.bytesToString();
      final url = jsonDecode(resp)["url"] as String;
      SocketManager().send({"to": remoteUserId, "type": "audio", "url": url});
      setState(() => messages.add({"type": "audio", "url": url, "from": widget.myUserId}));
      _scrollToBottom();
    }
  }

  Future<void> playAudio(String url) async {
    try {
      if (player!.isPlaying) await player!.stopPlayer();
      await player!.startPlayer(fromURI: url, codec: Codec.pcm16WAV, whenFinished: () {});
    } catch (e) {
      debugPrint("❌ Error al reproducir: $e");
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return "";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  Widget buildMessage(int index, Map<String, dynamic> msg) {
    if (_deletedForMe.contains(index)) return const SizedBox.shrink();
    final msgTimestamp = msg["timestamp"]?.toString() ?? "";
    if (_deletedTimestamps.contains(msgTimestamp)) return const SizedBox.shrink();
    final type = msg["type"]?.toString() ?? "";
    final isMe = msg["from"]?.toString() == widget.myUserId;
    final isStarred = _starredIndexes.contains(index);
    final isPinned = _pinnedMessages.any((m) => m["timestamp"] == msg["timestamp"]);
    final replyTo = msg["reply_to"]?.toString();
    final edited = msg["edited"] == true;
    final isSelected = _selectedMessages.contains(index);
    final reaction = _reactions[index];

    Widget content;

    if (type == "image") {
      final imgUrl = msg["url"]?.toString() ?? "";
      content = GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: Center(child: PhotoView(imageProvider: NetworkImage(imgUrl))),
          ),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(imgUrl, width: 220, height: 180, fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null ? child :
              Container(width: 220, height: 180, color: const Color(0xFF1A2235),
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF), strokeWidth: 2))),
          ),
        ),
      );
    } else if (type == "location" || type == "live_location") {
      final locUrl = msg["url"]?.toString() ?? "";
      final isLive = type == "live_location";
      content = GestureDetector(
        onTap: () async {
          final coords = locUrl.replaceAll("https://maps.google.com/?q=", "").split(",");
          if (coords.length < 2) return;
          final lat = double.tryParse(coords[0]) ?? 0;
          final lng = double.tryParse(coords[1]) ?? 0;
          final availableMaps = await MapLauncher.installedMaps;
          if (!mounted) return;
          if (availableMaps.isEmpty) {
            await launchUrl(Uri.parse(locUrl), mode: LaunchMode.externalApplication);
            return;
          }
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              const ListTile(title: Text("Abrir con...", style: TextStyle(fontWeight: FontWeight.bold))),
              ...availableMaps.map((map) => ListTile(
                leading: Image.asset(map.icon, width: 32, height: 32, package: "map_launcher"),
                title: Text(map.mapName),
                onTap: () { Navigator.pop(context); map.showMarker(coords: Coords(lat, lng), title: "Ubicacion compartida"); },
              )),
              const SizedBox(height: 8),
            ])),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isLive ? Colors.green.shade900 : Colors.blue.shade900,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isLive ? Colors.green : Colors.blue),
          ),
          child: Row(children: [
            Icon(Icons.location_on, color: isLive ? Colors.green : Colors.blue, size: 32),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isLive ? "Ubicacion en vivo" : "Ubicacion exacta", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text(msg["message"]?.toString() ?? "", style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text("Toca para abrir en Maps", style: TextStyle(fontSize: 11, color: isLive ? Colors.green : Colors.blue)),
            ])),
          ]),
        ),
      );
    } else if (type == "audio") {
      final url = msg["url"]?.toString() ?? "";
      content = _AudioBubble(url: url, isMe: isMe, player: player!);
    } else if (type == "file") {
      final filename = msg["filename"]?.toString() ?? "Archivo";
      final size = msg["size"] is int ? msg["size"] as int : null;
      final fileUrl = msg["url"]?.toString() ?? "";
      final isVideo = filename.endsWith(".mp4") || filename.endsWith(".mov") || filename.endsWith(".avi");
      if (isVideo) {
        content = GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoPlayerScreen(url: fileUrl))),
          child: Stack(alignment: Alignment.center, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Container(width: 200, height: 150, color: Colors.black87)),
            const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
            Positioned(bottom: 8, left: 8, child: Text(_formatSize(size), style: const TextStyle(color: Colors.white70, fontSize: 11))),
            const Positioned(top: 8, right: 8, child: Icon(Icons.videocam, color: Colors.white70, size: 18)),
          ]),
        );
      } else {
        content = Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.shade900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade700)),
          child: Row(children: [
            const Icon(Icons.insert_drive_file, color: Colors.orange, size: 32),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              if (size != null) Text(_formatSize(size), style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ])),
          ]),
        );
      }
    } else {
      content = Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyTo != null)
            Container(
              padding: const EdgeInsets.all(6),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Text("-> " + replyTo, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          Text(msg["message"]?.toString() ?? "", style: const TextStyle(color: Colors.white), softWrap: true, overflow: TextOverflow.visible),
          if (edited)
            Text("editado", style: TextStyle(fontSize: 10, color: isMe ? Colors.white60 : Colors.grey)),
          if (type == "text")
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Text(
                    _formatTimestamp(msg["timestamp"]?.toString() ?? ""),
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.done_all, size: 11,
                      color: msg["read"] == true ? const Color(0xFF00D4FF) : Colors.white38),
                  ],
                ],
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      onLongPress: () {
        if (_isSelecting) {
          setState(() {
            if (isSelected) _selectedMessages.remove(index);
            else _selectedMessages.add(index);
          });
        } else {
          setState(() {
            _isSelecting = true;
            _selectedMessages.add(index);
          });
        }
      },
      onTap: () {
        if (_isSelecting) {
          setState(() {
            if (isSelected) _selectedMessages.remove(index);
            else _selectedMessages.add(index);
            if (_selectedMessages.isEmpty) _isSelecting = false;
          });
        }
      },
      onDoubleTap: () => _isSelecting ? null : _showReactions(index),
      child: Container(
        color: isSelected ? const Color(0xFF00D4FF).withOpacity(0.15) : Colors.transparent,
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
            padding: type == "text" ? const EdgeInsets.all(12) : const EdgeInsets.all(4),
            decoration: type == "text" ? BoxDecoration(
              gradient: isMe ? const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF0044CC)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: isMe ? null : const Color(0xFF1A2235),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
              ),
              boxShadow: isMe ? [BoxShadow(color: const Color(0xFF0066FF).withOpacity(0.3), blurRadius: 8)] : null,
            ) : null,
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    content,
                    if (isStarred) const Positioned(top: 0, right: 0, child: Icon(Icons.star, size: 14, color: Colors.amber)),
                    if (isPinned) const Positioned(top: 0, left: 0, child: Icon(Icons.push_pin, size: 14, color: Colors.purple)),
                  ],
                ),
                if (reaction != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)]),
                    child: Text(reaction, style: const TextStyle(fontSize: 16)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelecting
          ? AppBar(
              backgroundColor: const Color(0xFF1A2235),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() { _isSelecting = false; _selectedMessages.clear(); }),
              ),
              title: Text('\${_selectedMessages.length} seleccionado(s)', style: const TextStyle(color: Colors.white)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: "Eliminar seleccionados",
                  onPressed: _deleteSelectedMessages,
                ),
                IconButton(
                  icon: const Icon(Icons.select_all, color: Color(0xFF00D4FF)),
                  tooltip: "Seleccionar todos",
                  onPressed: () => setState(() => _selectedMessages = Set.from(List.generate(messages.length, (i) => i))),
                ),
              ],
            )
          : AppBar(
              backgroundColor: const Color(0xFF0D1321),
              elevation: 0,
              title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GhostAvatar(avatarIndex: _remoteAvatarIndex, size: 40),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.username, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text("● Online", style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF))),
            ]),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: _inCall ? null : _startCall,
            tooltip: "Llamar",
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: _inCall ? null : _startVideoCall,
            tooltip: "Videollamar",
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF0D1321),
            onSelected: (value) {
              switch (value) {
                case 'call':
                  if (!_inCall) _startCall();
                  break;
                case 'search':
                  setState(() { _searchMode = !_searchMode; _searchQuery = ''; _searchController.clear(); });
                  break;
                case 'timer':
                  _showDestroyOptions();
                  break;
                case 'pinned':
                  _showPinnedMessages();
                  break;
                case 'starred':
                  _showStarredMessages();
                  break;
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(myUserId: widget.myUserId, username: widget.username)));
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'call', child: Row(children: [Icon(Icons.call, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Llamada de voz', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'search', child: Row(children: [Icon(Icons.search, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Buscar', style: TextStyle(color: Colors.white))])),
              PopupMenuItem(value: 'timer', child: Row(children: [Icon(Icons.timer, color: _destroySeconds != null ? Colors.red : const Color(0xFF00D4FF), size: 20), const SizedBox(width: 12), Text(_destroySeconds != null ? 'Autodestruir (activo)' : 'Autodestruir', style: const TextStyle(color: Colors.white))])),
              if (_pinnedMessages.isNotEmpty)
                const PopupMenuItem(value: 'pinned', child: Row(children: [Icon(Icons.push_pin, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Mensajes fijados', style: TextStyle(color: Colors.white))])),
              if (_starredIndexes.isNotEmpty)
                const PopupMenuItem(value: 'starred', child: Row(children: [Icon(Icons.star, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Destacados', style: TextStyle(color: Colors.white))])),
              const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings, color: Color(0xFF00D4FF), size: 20), SizedBox(width: 12), Text('Ajustes', style: TextStyle(color: Colors.white))])),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E1A), Color(0xFF0D1321), Color(0xFF0A0E1A)],
          ),
        ),
        child: Column(
          children: [
            if (_searchMode)
              Container(
                color: const Color(0xFF0D1321),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF1A2235), borderRadius: BorderRadius.circular(20)),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: "Buscar mensajes...",
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF00D4FF), size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() { _searchMode = false; _searchQuery = ''; _searchController.clear(); })),
                ]),
              ),
            if (_pinnedMessages.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.purple.shade900,
                child: Row(
                  children: [
                    const Icon(Icons.push_pin, size: 16, color: Colors.purple),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      _pinnedMessages.last["message"]?.toString() ?? "Mensaje fijado",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    )),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: messages.length,
                itemBuilder: (_, i) => buildMessage(i, messages[i]),
              ),
            ),
            if (_remoteIsTyping)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(left: 16, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFF1A2235), borderRadius: BorderRadius.circular(18)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _TypingDot(delay: 0),
                    _TypingDot(delay: 200),
                    _TypingDot(delay: 400),
                  ]),
                ),
              ),
            if (isSendingFile) const LinearProgressIndicator(color: Color(0xFF00D4FF)),
            if (_showEmoji) SizedBox(
              height: 250,
              child: EmojiPicker(onEmojiSelected: (_, emoji) => setState(() {
                _controller.text += emoji.emoji;
                _showEmoji = false;
              })),
            ),
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: const Color(0xFF0D1321),
                child: Row(
                  children: [
                    const Icon(Icons.reply, size: 16, color: Color(0xFF00D4FF)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      _replyingTo!["message"]?.toString() ?? "Mensaje",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    )),
                    IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.white54), onPressed: () => setState(() => _replyingTo = null)),
                  ],
                ),
              ),
            if (_editingMsg != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: const Color(0xFF0D1321),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    const Expanded(child: Text("Editando mensaje", style: TextStyle(fontSize: 13, color: Colors.orange))),
                    IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.white54), onPressed: () => setState(() { _editingMsg = null; _controller.clear(); })),
                  ],
                ),
              ),
            // ── Barra de entrada estilo WhatsApp ──
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0D1321),
                border: Border(top: BorderSide(color: Color(0xFF1A2235))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // Botón + menú izquierda
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A2235),
                      border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.add, color: Color(0xFF00D4FF), size: 22),
                      onPressed: () => _showAttachMenu(),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Campo de texto expandido
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2235),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 4,
                              minLines: 1,
                              decoration: InputDecoration(
                                hintText: "Message...",
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              onSubmitted: (_) => sendMessage(),
                            ),
                          ),
                          // Emoji dentro del campo
                          IconButton(
                            icon: Icon(Icons.emoji_emotions, color: Colors.white.withOpacity(0.4), size: 20),
                            onPressed: () => setState(() => _showEmoji = !_showEmoji),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          // Camara dentro del campo
                          IconButton(
                            icon: Icon(Icons.camera_alt, color: Colors.white.withOpacity(0.4), size: 20),
                            onPressed: _openCamera,
                            padding: const EdgeInsets.only(right: 4),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botón enviar o micrófono derecha
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFF0066FF), Color(0xFF00D4FF)]),
                      boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4), blurRadius: 8)],
                    ),
                    child: IconButton(
                      icon: Icon(
                        isRecording ? Icons.stop : (_controller.text.isEmpty ? Icons.mic : Icons.send),
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {
                        if (isRecording) {
                          stopRecording();
                        } else if (_controller.text.isEmpty) {
                          startRecording();
                        } else {
                          sendMessage();
                        }
                      },
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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

  void _deleteSelectedMessages() async {
    final isMe = _selectedMessages.every((i) => messages[i]["from"]?.toString() == widget.myUserId);

    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1321),
        title: const Text('Eliminar mensajes', style: TextStyle(color: Colors.white)),
        content: Text('¿Eliminar \${_selectedMessages.length} mensaje(s)?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, 'me'),
            child: const Text('Eliminar para mí', style: TextStyle(color: Colors.orange)),
          ),
          if (isMe)
            TextButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('Eliminar para todos', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );

    if (choice == null) return;

    final sorted = _selectedMessages.toList()..sort((a, b) => b.compareTo(a));

    if (choice == 'all') {
      for (final i in sorted) {
        final timestamp = messages[i]["timestamp"]?.toString();
        sendSignal({'type': 'delete_for_all', 'to': remoteUserId, 'target_timestamp': timestamp});
      }
      setState(() {
        for (final i in sorted) messages.removeAt(i);
      });
    } else {
      setState(() {
        for (final i in sorted) {
          _deletedForMe.add(i);
          final ts = messages[i]["timestamp"]?.toString() ?? "";
          _saveDeletedMessage(ts);
        }
      });
    }

    setState(() { _isSelecting = false; _selectedMessages.clear(); });
  }

  // ── Typing indicator ──
  void _sendTyping() {
    SocketManager().send({'type': 'typing', 'to': remoteUserId});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      SocketManager().send({'type': 'stop_typing', 'to': remoteUserId});
    });
  }

  // ── Autodestruccion ──
  void _scheduleDestroy(int index, int seconds) {
    Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _deletedForMe.add(index));
    });
  }

  void _showDestroyOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1321),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const ListTile(title: Text("💣 Mensajes que se autodestruyen", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            _optionTile(Icons.timer, "Desactivado", Colors.grey, () { Navigator.pop(context); setState(() => _destroySeconds = null); }),
            _optionTile(Icons.timer, "5 segundos", Colors.red, () { Navigator.pop(context); setState(() => _destroySeconds = 5); }),
            _optionTile(Icons.timer, "10 segundos", Colors.orange, () { Navigator.pop(context); setState(() => _destroySeconds = 10); }),
            _optionTile(Icons.timer, "30 segundos", Colors.amber, () { Navigator.pop(context); setState(() => _destroySeconds = 30); }),
            _optionTile(Icons.timer, "1 minuto", Colors.green, () { Navigator.pop(context); setState(() => _destroySeconds = 60); }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Reenviar mensaje ──
  void _forwardMessage(Map<String, dynamic> msg) {
    final type = msg["type"]?.toString() ?? "";
    if (type == "text") {
      final text = msg["message"]?.toString() ?? "";
      final encrypted = GhostCrypto.encrypt("↪ $text");
      final msgData = {"to": remoteUserId, "type": "text", "message": encrypted};
      SocketManager().send(msgData);
      setState(() => messages.add({...msgData, "from": widget.myUserId, "message": "↪ $text", "timestamp": DateTime.now().millisecondsSinceEpoch.toString()}));
      _scrollToBottom();
    } else if (type == "image" || type == "audio" || type == "file") {
      SocketManager().send({...msg, "to": remoteUserId, "from": widget.myUserId});
      setState(() => messages.add({...msg, "from": widget.myUserId, "timestamp": DateTime.now().millisecondsSinceEpoch.toString()}));
      _scrollToBottom();
    }
  }

  String _formatTimestamp(String ts) {
    try {
      final ms = int.tryParse(ts);
      if (ms != null && ms > 1000000000000) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return h + ':' + m;
      }
      if (ts.length >= 5) return ts.substring(0, 5);
      return ts;
    } catch (_) { return ''; }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1321),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachItem(Icons.image, "Galería", const Color(0xFF9C27B0), () { Navigator.pop(context); sendImage(); }),
                  _attachItem(Icons.insert_drive_file, "Documento", const Color(0xFF2196F3), () { Navigator.pop(context); sendFile(); }),
                  _attachItem(Icons.location_on, "Ubicación", const Color(0xFF4CAF50), () { Navigator.pop(context); _showLiveLocationOptions(); }),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachItem(Icons.mic, isRecording ? "Detener" : "Audio", const Color(0xFFFF5722), () { Navigator.pop(context); isRecording ? stopRecording() : startRecording(); }),
                  _attachItem(Icons.videocam, "Video call", const Color(0xFF00BCD4), () { Navigator.pop(context); _startVideoCall(); }),
                  _attachItem(Icons.call, "Llamada", const Color(0xFF8BC34A), () { Navigator.pop(context); _startCall(); }),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  void _showPinnedMessages() {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: [
          const ListTile(title: Text("📌 Mensajes fijados", style: TextStyle(fontWeight: FontWeight.bold))),
          ..._pinnedMessages.map((m) => ListTile(
            title: Text(m["message"]?.toString() ?? "Mensaje"),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () { setState(() => _pinnedMessages.remove(m)); Navigator.pop(context); },
            ),
          )),
        ],
      ),
    );
  }

  void _showStarredMessages() {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: [
          const ListTile(title: Text("⭐ Mensajes destacados", style: TextStyle(fontWeight: FontWeight.bold))),
          ..._starredIndexes.map((i) {
            if (i >= messages.length) return const SizedBox.shrink();
            final m = messages[i];
            return ListTile(
              title: Text(m["message"]?.toString() ?? "Mensaje"),
              trailing: IconButton(
                icon: const Icon(Icons.star, color: Colors.amber),
                onPressed: () { setState(() => _starredIndexes.remove(i)); Navigator.pop(context); },
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _sendLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    final pos = await Geolocator.getCurrentPosition();
    final url = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
    final msg = {"to": remoteUserId, "type": "location", "message": "📍 Ubicación: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}", "url": url};
    SocketManager().send(msg);
    setState(() => messages.add({...msg, "from": widget.myUserId, "timestamp": DateTime.now().millisecondsSinceEpoch.toString()}));
    _scrollToBottom();
  }

  Future<void> _sendLiveLocation(int hours) async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    _liveLocationTimer?.cancel();
    final endTime = DateTime.now().add(Duration(hours: hours));
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (DateTime.now().isAfter(endTime)) { timer.cancel(); return; }
      final pos = await Geolocator.getCurrentPosition();
      final url = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
      SocketManager().send({"to": remoteUserId, "type": "live_location", "message": "📡 Ubicación en vivo (${hours}h): ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}", "url": url});
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("📡 Compartiendo ubicación en vivo por ${hours}h")));
  }

  void _showLiveLocationOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const ListTile(title: Text("📡 Compartir ubicación", style: TextStyle(fontWeight: FontWeight.bold))),
            _optionTile(Icons.location_on, "📍 Ubicación exacta", Colors.blue, () { Navigator.pop(context); _sendLocation(); }),
            _optionTile(Icons.location_on, "📡 En vivo 1 hora", Colors.green, () { Navigator.pop(context); _sendLiveLocation(1); }),
            _optionTile(Icons.location_on, "📡 En vivo 6 horas", Colors.orange, () { Navigator.pop(context); _sendLiveLocation(6); }),
            _optionTile(Icons.location_on, "📡 En vivo 12 horas", Colors.red, () { Navigator.pop(context); _sendLiveLocation(12); }),
            if (_liveLocationTimer != null)
              _optionTile(Icons.stop, "⛔ Detener ubicación en vivo", Colors.red, () { Navigator.pop(context); _liveLocationTimer?.cancel(); _liveLocationTimer = null; if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⛔ Ubicación en vivo detenida"))); }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _addReaction(int index, String emoji) {
    setState(() => _reactions[index] = emoji);
    Navigator.pop(context);
  }

  void _showReactions(int index) {
    final emojis = ["❤️", "😂", "😮", "😢", "👍", "🔥", "🎉", "👀"];
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis.map((e) => GestureDetector(
            onTap: () => _addReaction(index, e),
            child: Text(e, style: const TextStyle(fontSize: 32)),
          )).toList(),
        ),
      ),
    );
  }
  void dispose() {
    _liveLocationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _typingTimer?.cancel();
    SocketManager().removeListener(_onSocketMessage);
    _httpClient.close();
    _scrollController.dispose();
    recorder?.closeRecorder();
    player?.closePlayer();
    super.dispose();
  }
}

class _VideoPlayerScreen extends StatefulWidget {
  final String url;
  const _VideoPlayerScreen({required this.url});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButton: _initialized
          ? FloatingActionButton(
              onPressed: () => setState(() =>
                  _controller.value.isPlaying ? _controller.pause() : _controller.play()),
              child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}

class _AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  final FlutterSoundPlayer player;
  const _AudioBubble({required this.url, required this.isMe, required this.player});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  bool _isPlaying = false;
  Duration _total = Duration.zero;
  Duration _current = Duration.zero;
  double _progress = 0;
  final PlayerController _waveController = PlayerController();
  bool _waveReady = false;

  @override
  void initState() {
    super.initState();
    _prepareWave();
  }

  Future<void> _prepareWave() async {
    try {
      await _waveController.preparePlayer(
        path: widget.url,
        shouldExtractWaveform: true,
        noOfSamples: 40,
        volume: 1.0,
      );
      if (mounted) setState(() => _waveReady = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await widget.player.stopPlayer();
      await _waveController.pausePlayer();
      setState(() { _isPlaying = false; _progress = 0; _current = Duration.zero; });
      return;
    }
    setState(() => _isPlaying = true);
    // Reproducir con flutter_sound para el progreso
    await widget.player.startPlayer(
      fromURI: widget.url,
      codec: Codec.pcm16WAV,
      whenFinished: () {
        if (mounted) setState(() { _isPlaying = false; _progress = 0; _current = Duration.zero; });
        _waveController.stopPlayer();
      },
    );
    // Sincronizar waveform
    if (_waveReady) _waveController.startPlayer();

    widget.player.setSubscriptionDuration(const Duration(milliseconds: 100));
    widget.player.onProgress?.listen((e) {
      if (!mounted) return;
      setState(() {
        _current = e.position;
        _total = e.duration;
        _progress = _total.inMilliseconds > 0 ? _current.inMilliseconds / _total.inMilliseconds : 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : const Color(0xFF00D4FF);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMe ? Colors.white24 : const Color(0xFF00D4FF).withOpacity(0.2),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: color, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Forma de onda
                if (_waveReady)
                  AudioFileWaveforms(
                    playerController: _waveController,
                    size: const Size(double.infinity, 32),
                    waveformType: WaveformType.fitWidth,
                    playerWaveStyle: PlayerWaveStyle(
                      fixedWaveColor: color.withOpacity(0.3),
                      liveWaveColor: color,
                      spacing: 4,
                      waveThickness: 2,
                      showSeekLine: false,
                    ),
                  )
                else
                  // Fallback barra de progreso
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: color.withOpacity(0.2),
                      color: color,
                      minHeight: 3,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(_current), style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
                    Row(children: [
                      Icon(Icons.mic, size: 10, color: color.withOpacity(0.5)),
                      const SizedBox(width: 2),
                      Text(
                        _isPlaying ? _fmt(_total) : (_total > Duration.zero ? _fmt(_total) : "Audio"),
                        style: TextStyle(fontSize: 10, color: color.withOpacity(0.7)),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7, height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF00D4FF).withOpacity(0.4 + 0.6 * _ctrl.value),
        ),
      ),
    );
  }
}
