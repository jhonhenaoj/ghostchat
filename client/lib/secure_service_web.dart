import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

class SecureService {
  WebSocket? socket;

  // 🔥 Callback para recibir mensajes
  Function(dynamic)? onMessageReceived;

  Future<void> initialize() async {
    print("🔐 SecureService WEB inicializado");
  }

  Future<void> connectWebSocket(String userId, String token) async {
    final url = "ws://192.168.1.105:9090/ws//ws?user_id=$userId&token=$token";

    print("🔌 Conectando a $url");

    socket = WebSocket(url);

    socket!.onOpen.listen((event) {
      print("🌐 WS conectado como $userId");
    });

    socket!.onMessage.listen((event) {
      print("📩 Mensaje: ${event.data}");

      // 🔥 enviar al UI
      if (onMessageReceived != null) {
        onMessageReceived!(event.data);
      }
    });

    socket!.onClose.listen((event) {
      print("❌ WS cerrado");
    });
  }

  void sendWSMessage(String toUser, String message) {
    final data = jsonEncode({
      "to": toUser,
      "message": message,
    });

    socket?.send(data);
    print("📤 Enviado: $data");
  }
}
