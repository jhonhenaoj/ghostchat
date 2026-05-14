import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

// Un callback para cuando llega un nuevo mensaje
typedef OnMessageReceived = void Function(Map<String, dynamic>);

class WebSocketService {
  WebSocketChannel? _channel;
  final OnMessageReceived onMessageReceived;

  WebSocketService({required this.onMessageReceived});

  // Conectar al servidor WebSocket
  void connect(String userId, String accessToken) {
    // La URL de conexión incluye el user_id y el token como query params
    final Uri wsUrl = Uri.parse('ws://162.243.174.252:9090/ws?user_id=$userId&token=$accessToken');
    
    print("WebSocketService: Intentando conectar a $wsUrl");

    _channel = WebSocketChannel.connect(wsUrl);

    // Escuchar los mensajes del servidor
    _channel!.stream.listen(
      (message) {
        final decodedMessage = jsonDecode(message) as Map<String, dynamic>;
        print('WebSocket [RECEIVED]: $decodedMessage');
        onMessageReceived(decodedMessage);
      },
      onError: (error) {
        print('WebSocket [ERROR]: $error');
      },
      onDone: () {
        print('WebSocket [DONE]: Conexión cerrada. ¿Hubo un error? Código: ${_channel?.closeCode}, Razón: ${_channel?.closeReason}');
        _channel = null;
      },
      cancelOnError: true, // Importante: cancelar la suscripción si hay un error
    );
  }

  // Enviar un mensaje al servidor
  void sendMessage(String recipientId, String payload) {
    if (_channel != null) {
      final message = {
        'recipient_id': recipientId,
        'payload': payload,
        // El backend podría añadir el sender_id y timestamp
      };
      print('WebSocket [SENDING]: $message');
      _channel!.sink.add(jsonEncode(message));
    } else {
      print('Error: Intentando enviar mensaje sin conexión WebSocket.');
    }
  }

  // Desconectar del servidor
  void disconnect() {
    if (_channel != null) {
      print('WebSocketService: Cerrando conexión activa.');
      _channel!.sink.close();
      _channel = null;
    }
  }
}
