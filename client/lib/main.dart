import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/call_screen.dart';
import 'utils/socket_manager.dart';
import 'utils/background_service.dart';
import 'package:flutter_background/flutter_background.dart';

Map<String, dynamic>? pendingCallData;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  if (data['type'] == 'call' || data['call_type'] != null) {
    await _showCallkitIncoming(data);
  }
}

Future<void> _showCallkitIncoming(Map<String, dynamic> data) async {
  final callID = data['call_id'] ?? const Uuid().v4();
  final callerName = data['caller_name'] ?? 'Usuario';
  final isVideo = data['is_video'] == 'true';
  final params = CallKitParams(
    id: callID,
    nameCaller: callerName,
    appName: 'Ghost Chat',
    type: isVideo ? 1 : 0,
    duration: 30000,
    textAccept: 'Contestar',
    textDecline: 'Rechazar',
    extra: {
      'from_user': data['from_user'] ?? '',
      'is_video': data['is_video'] ?? 'false',
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
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

  FlutterCallkitIncoming.onEvent.listen((event) async {
    if (event == null) return;
    switch (event.event) {
      case Event.actionCallAccept:
        final data = event.body as Map<dynamic, dynamic>? ?? {};
        final fromId = data['extra']?['from_user']?.toString() ?? '';
        final isVideo = data['extra']?['is_video']?.toString() == 'true';
        pendingCallData = {'from_user': fromId, 'is_video': isVideo};
        // Intentar navegar si la app ya está corriendo
        if (navigatorKey.currentContext != null && fromId.isNotEmpty) {
          await Permission.microphone.request();
          if (isVideo) await Permission.camera.request();
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => CallScreen(
              callType: 'receiver',
              remoteUserId: fromId,
              isVideo: isVideo,
              pendingOffer: SocketManager().pendingOffer,
              sendSignal: (msg) => SocketManager().send(msg),
            ),
          ));
          pendingCallData = null;
        }
        break;
      case Event.actionCallDecline:
        final declineData = event.body as Map<dynamic, dynamic>? ?? {};
        final declineFromId = declineData['extra']?['from_user']?.toString() ?? '';
        await FlutterCallkitIncoming.endCall(declineData['id']?.toString() ?? '');
        if (declineFromId.isNotEmpty) {
          SocketManager().send({'type': 'hangup', 'to': declineFromId});
        }
        break;
      default:
        break;
    }
  });

  // Pedir todos los permisos al iniciar
  await Permission.microphone.request();
  await Permission.camera.request();
  await Permission.location.request();
  await Permission.storage.request();
  await Permission.notification.request();

  // Iniciar servicio de background
  const androidConfig = FlutterBackgroundAndroidConfig(
    notificationTitle: 'Ghost Chat',
    notificationText: 'Ejecutándose en segundo plano',
    notificationImportance: AndroidNotificationImportance.normal,
    enableWifiLock: true,
  );
  await FlutterBackground.initialize(androidConfig: androidConfig);
  await FlutterBackground.enableBackgroundExecution();

  await initBackgroundService(); // temporalmente desactivado
  runApp(const GhostChatApp());
}

class GhostChatApp extends StatelessWidget {
  const GhostChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Chat',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00D4FF),
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF0066FF),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
