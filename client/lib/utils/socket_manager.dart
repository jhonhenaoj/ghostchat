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
        'wss://api.soluciones-publicitarias-latam.com/ws?user_id=$_userId',
        pingInterval: const Duration(seconds: 10),
      );
      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            for (final listener in List.from(_listeners)) {
              listener(msg);
            }
          } catch (_) {}
          // Guardar offer pendiente globalmente
          try {
            final msg2 = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg2['type'] == 'offer') {
              pendingOffer = msg2['sdp']?.toString();
              pendingOfferFrom = msg2['from']?.toString();
            }
          } catch (_) {}
        },
        onDone: () {
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

  void send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
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
