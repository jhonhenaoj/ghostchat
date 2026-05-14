import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';

class SocketManager {
  static final SocketManager _instance = SocketManager._internal();
  factory SocketManager() => _instance;
  SocketManager._internal();

  IOWebSocketChannel? _channel;
  String? _userId;
  String? get currentUserId => _userId;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool isConnected = false;

  // Listeners registrados
  final List<Function(Map<String, dynamic>)> _listeners = [];
  String? pendingOffer;
  String? pendingOfferFrom;

  void addListener(Function(Map<String, dynamic>) listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(Function(Map<String, dynamic>) listener) {
    _listeners.remove(listener);
  }

  void connect(String userId) {
    // Si ya está conectado con el mismo usuario, no reconectar
    if (_channel != null && _userId == userId && !_isConnecting) {
      debugPrint("⚡ Socket ya conectado para usuario $userId");
      return;
    }
    _userId = userId;
    if (_isConnecting) return;
    _connect();
  }

  void _connect() {
    if (_isConnecting || _userId == null) return;
    _isConnecting = true;
    _channel?.sink.close();

    try {
      _channel = IOWebSocketChannel.connect(
        'ws://162.243.174.252:9090/ws?user_id=$_userId',
        pingInterval: const Duration(seconds: 10),
      );
      isConnected = true;
    _channel!.stream.listen(
        (data) {
          try {
            // Parsear una sola vez
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            // Guardar offer pendiente globalmente
            if (msg['type'] == 'offer') {
              pendingOffer = msg['sdp']?.toString();
              pendingOfferFrom = msg['from']?.toString();
            }
            for (final listener in List.from(_listeners)) {
              listener(msg);
            }
          } catch (_) {}
        },
        onDone: () {
        isConnected = false;
          _isConnecting = false;
          debugPrint("🔴 Socket desconectado, reconectando...");
          _scheduleReconnect();
        },
        onError: (e) {
          _isConnecting = false;
          debugPrint("❌ Socket error: $e");
          _scheduleReconnect();
        },
      );
      _isConnecting = false;
      _startHeartbeat();
      _flushPendingMessages();
      debugPrint("✅ Socket conectado para usuario $_userId");
    } catch (e) {
      _isConnecting = false;
      debugPrint("❌ Error conectando socket: $e");
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping', 'to': 'server'});
    });
  }

  final List<Map<String, dynamic>> _pendingMessages = [];

  void send(Map<String, dynamic> msg) {
    try {
      if (_channel == null) {
        debugPrint('⚠️ Socket no conectado, guardando mensaje en cola...');
        _pendingMessages.add(msg);
        if (_userId != null) connect(_userId!);
        return;
      }
      _channel?.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('❌ Error enviando mensaje: $e');
      _pendingMessages.add(msg);
    }
  }

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    final pending = List.from(_pendingMessages);
    _pendingMessages.clear();
    for (final msg in pending) {
      _channel?.sink.add(jsonEncode(msg));
    }
    debugPrint('📤 Enviados ${pending.length} mensajes pendientes');
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _userId = null;
    _listeners.clear();
  }
}
