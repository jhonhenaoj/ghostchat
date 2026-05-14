import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initBackgroundService() async {
  print('🚀 Iniciando servicio en segundo plano...');
  final plugin = FlutterLocalNotificationsPlugin();
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  
  // Canal de background con importancia alta
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    'ghost_chat_bg',
    'Ghost Chat',
    description: 'Mantiene conexión activa',
    importance: Importance.low,
    playSound: false,
  ));

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'ghost_chat_bg',
      initialNotificationTitle: 'Ghost Chat',
      initialNotificationContent: 'Conectado',
      foregroundServiceNotificationId: 888,
      autoStartOnBoot: true,
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print('🔧 Servicio en segundo plano INICIADO');
  print('🔧 Servicio en segundo plano iniciado');
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  IOWebSocketChannel? channel;
  Timer? heartbeat;
  Timer? reconnectTimer;
  bool running = true;
  bool isConnected = false;

  service.on('stopService').listen((_) {
    running = false;
    heartbeat?.cancel();
    reconnectTimer?.cancel();
    channel?.sink.close();
    service.stopSelf();
  });

  Future<String> getCallerName(String userId) async {
    try {
      final resp = await http.get(
        Uri.parse('http://162.243.174.252:9090/profile?user_id=$userId'),
      ).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final name = data['display_name']?.toString() ?? '';
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'Usuario $userId';
  }

  Future<void> connect() async {
    return; // Usar solo SocketManager
    if (!running) return;
    isConnected = false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) {
        reconnectTimer = Timer(const Duration(seconds: 10), connect);
        return;
      }

      channel?.sink.close();
      channel = IOWebSocketChannel.connect(
        'ws://162.243.174.252:9090/ws?user_id=$userId',
        pingInterval: const Duration(seconds: 20),
      );

      isConnected = true;
      print('🔌 Conectado al WebSocket');

      channel!.stream.listen(
        (data) async {
          if (!running) return;
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final type = msg['type']?.toString() ?? '';
            print('📩 MENSAJE RECIBIDO: $type');
            if (type == 'call') print('📞 ¡LLAMADA DETECTADA! Datos: $msg');
            
            if (type == 'call') {
              final fromUser = msg['from']?.toString() ?? '';
              final isVideo = msg['isVideo'] == true;
              // Guardar datos de llamada para acceso rápido
              final prefs2 = await SharedPreferences.getInstance();
              await prefs2.setString('bg_call_from', fromUser);
              await prefs2.setBool('bg_call_video', isVideo);
              await prefs2.setString('flutter.pending_call_from', fromUser);
              await prefs2.setBool('flutter.pending_call_video', isVideo);
              await prefs2.setInt('bg_call_time', DateTime.now().millisecondsSinceEpoch);
              // Obtener nombre real del servidor
              final callerName = await getCallerName(fromUser);
              
              await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
                id: const Uuid().v4(),
                nameCaller: callerName,
                appName: 'Ghost Chat',
                type: isVideo ? 1 : 0,
                duration: 30000,
                textAccept: 'Contestar',
                textDecline: 'Rechazar',
                extra: {
                  'from_user': fromUser,
                  'is_video': isVideo ? 'true' : 'false',
                },
                android: const AndroidParams(
                  isCustomNotification: true,
                  isShowLogo: false,
                  ringtonePath: 'system_ringtone_default',
                  backgroundColor: '#0A0E1A',
                  backgroundUrl: null,
                  actionColor: '#00D4FF',
                  textColor: '#FFFFFF',
                  incomingCallNotificationChannelName: 'Llamadas',
                  missedCallNotificationChannelName: 'Llamadas perdidas',
                ),
              ));
            }
          } catch (e) {
            print('❌ ERROR procesando llamada: $e');
          }
        },
        onDone: () {
          isConnected = false;
          heartbeat?.cancel();
          if (running) reconnectTimer = Timer(const Duration(seconds: 30), connect);
        },
        onError: (_) {
          isConnected = false;
          heartbeat?.cancel();
          if (running) reconnectTimer = Timer(const Duration(seconds: 30), connect);
        },
      );

      heartbeat?.cancel();
      heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          channel?.sink.add(jsonEncode({'type': 'ping', 'to': 'server'}));
        } catch (_) {
          if (running) {
            reconnectTimer?.cancel();
            reconnectTimer = Timer(const Duration(seconds: 3), connect);
          }
        }
      });

    } catch (_) {
      isConnected = false;
      if (running) reconnectTimer = Timer(const Duration(seconds: 30), connect);
    }
  }

  await connect();
}
