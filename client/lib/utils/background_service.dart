import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initBackgroundService() async {
  // Crear canal de notificación primero
  final plugin = FlutterLocalNotificationsPlugin();
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    'ghost_chat_bg',
    'Ghost Chat Background',
    description: 'Servicio en segundo plano',
    importance: Importance.low,
  ));

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'ghost_chat_bg',
      initialNotificationTitle: 'Ghost Chat',
      initialNotificationContent: 'Activo',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  IOWebSocketChannel? channel;
  Timer? heartbeat;
  Timer? reconnectTimer;
  bool running = true;

  service.on('stopService').listen((_) {
    running = false;
    heartbeat?.cancel();
    reconnectTimer?.cancel();
    channel?.sink.close();
    service.stopSelf();
  });

  Future<void> connect() async {
    if (!running) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) {
        reconnectTimer = Timer(const Duration(seconds: 10), connect);
        return;
      }

      channel?.sink.close();
      channel = IOWebSocketChannel.connect(
        'wss://api.soluciones-publicitarias-latam.com/ws?user_id=\$userId',
        pingInterval: const Duration(seconds: 20),
      );

      channel!.stream.listen(
        (data) async {
          if (!running) return;
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'call') {
              final fromUser = msg['from']?.toString() ?? '';
              final isVideo = msg['isVideo'] == true;
              await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
                id: const Uuid().v4(),
                nameCaller: 'Usuario \$fromUser',
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
          } catch (_) {}
        },
        onDone: () {
          heartbeat?.cancel();
          if (running) reconnectTimer = Timer(const Duration(seconds: 5), connect);
        },
        onError: (_) {
          heartbeat?.cancel();
          if (running) reconnectTimer = Timer(const Duration(seconds: 5), connect);
        },
      );

      heartbeat?.cancel();
      heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try { channel?.sink.add(jsonEncode({'type': 'ping', 'to': 'server'})); } catch (_) {}
      });

    } catch (_) {
      if (running) reconnectTimer = Timer(const Duration(seconds: 5), connect);
    }
  }

  await connect();
}
