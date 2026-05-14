import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/screens/pin_screen.dart';
import 'presentation/screens/call_screen.dart';
import 'utils/socket_manager.dart';
import 'utils/background_service.dart';

Map<String, dynamic>? pendingCallData;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // El nativo (CallReceiver) ya maneja la pantalla de llamada
  // No mostrar Flutter Callkit para evitar duplicados
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
  
  // Inicializar OneSignal
  OneSignal.initialize('265c6d06-d77f-46df-9032-87c803e03906');
  await OneSignal.Notifications.requestPermission(true);
  
  // Vincular user_id con OneSignal para poder enviar notificaciones
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');
  if (userId != null && userId.isNotEmpty) {
    OneSignal.login(userId);
    OneSignal.User.addTagWithKey('user_id', userId);
  }
  
  // Manejar notificaciones cuando app está en background/muerta
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    final data = event.notification.additionalData;
    if (data != null && data['type'] == 'call') {
      event.preventDefault(); // No mostrar notificación normal para llamadas
    } else {
      event.notification.display();
    }
  });

  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData;
    if (data != null && data['type'] == 'call') {
      final fromUser = data['from_user']?.toString() ?? '';
      final isVideo = data['is_video'] == 'true';
      final callerName = data['caller_name']?.toString() ?? 'Usuario';
      final callId = data['call_id']?.toString() ?? '';
      pendingCallData = {'from_user': fromUser, 'is_video': isVideo};
      // Mostrar pantalla de llamada nativa
      FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
        id: callId.isNotEmpty ? callId : const Uuid().v4(),
        nameCaller: callerName,
        appName: 'Ghost Chat',
        type: isVideo ? 1 : 0,
        duration: 30000,
        textAccept: 'Contestar',
        textDecline: 'Rechazar',
        extra: {'from_user': fromUser, 'is_video': isVideo ? 'true' : 'false'},
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
  });
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Crear canales de notificacion con maxima prioridad
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(const AndroidNotificationChannel(
      'ghost_chat_messages', 'Mensajes',
      description: 'Notificaciones de mensajes',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(const AndroidNotificationChannel(
      'ghost_chat_calls', 'Llamadas',
      description: 'Notificaciones de llamadas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
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
      case Event.actionCallEnded:
        // Cancelar notificacion residual al terminar llamada
        await FlutterCallkitIncoming.endAllCalls();
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
  await Permission.phone.request();
  // Registrar PhoneAccount para llamadas del sistema
  try {
    const platform = MethodChannel("ghost_chat/call");
    await platform.invokeMethod("registerPhoneAccount");
  } catch (_) {}
  // Pedir ignorar optimizacion de bateria - CRITICO para notificaciones
  // Intentar varias veces hasta que el usuario lo acepte
  for (int i = 0; i < 3; i++) {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) break;
    await Permission.ignoreBatteryOptimizations.request();
    await Future.delayed(const Duration(milliseconds: 500));
  }
  // Permiso para mostrar sobre otras apps (necesario para llamadas)
  if (await Permission.systemAlertWindow.isDenied) {
    await Permission.systemAlertWindow.request();
  }
  // Permiso fullscreen para llamadas (Android 14+)
  await FlutterCallkitIncoming.requestNotificationPermission({
    'title': 'Permiso de notificacion',
    'rationaleMessagePermission': 'Se requiere para mostrar llamadas entrantes.',
    'postNotificationMessageRequired': 'Por favor activa las notificaciones en ajustes.',
  });
  if (await FlutterCallkitIncoming.canUseFullScreenIntent() == false) {
    await FlutterCallkitIncoming.requestFullIntentPermission();
  }

  // Iniciar servicio de background

  print('🔔 A punto de iniciar el servicio en segundo plano...');
  await initBackgroundService();
  print('✅ Servicio en segundo plano iniciado desde main.dart');
  // Escuchar eventos de llamada nativa
  try {
    const EventChannel callEventChannel = EventChannel('ghost_chat/call_events');
    callEventChannel.receiveBroadcastStream().listen((event) {
      try {
        final data = Map<String, dynamic>.from(event);
        if (data['type'] == 'accept_call') {
          final fromUser = data['from_user']?.toString() ?? '';
          final isVideo = data['is_video'] == true;
          pendingCallData = {'from_user': fromUser, 'is_video': isVideo};
        }
      } catch (_) {}
    }, onError: (_) {});
  } catch (_) {}
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
      home: SplashScreen(nextScreen: const LoginScreen()),
    );
  }
}
