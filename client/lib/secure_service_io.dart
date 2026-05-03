import 'dart:convert';
import 'dart:io';

class SecureService {
  WebSocket? socket;

  // 🔥 Callback para recibir mensajes
  Function(dynamic)? onMessageReceived;

  Future<void> initialize() async {
    print("🔐 SecureService IO inicializado");
  }

  Future<void> connectWebSocket(String userId, String token) async {
  final url = "ws://192.168.1.105:9090/ws?user_id=$userId&token=$token";
    print("🔌 Conectando a $url");

    socket = await WebSocket.connect(url);

    print("🌐 WS conectado como $userId");

    socket!.listen((data) {
      print("📩 Mensaje: $data");

      // 🔥 enviar al UI
      if (onMessageReceived != null) {
        onMessageReceived!(data);
      }
    });
  }

  void sendWSMessage(String toUser, String message) {
    final data = jsonEncode({
      "to": toUser,
      "message": message,
    });

    socket?.add(data);
    print("📤 Enviado: $data");
  }
}
