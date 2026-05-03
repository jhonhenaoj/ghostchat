import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/auth_repository.dart';
import '../../domain/user.dart';
import '../../services/websocket_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repository = AuthRepository();
  
  // El servicio WebSocket, ahora es una variable normal, no final
  late WebSocketService wsService;

  User? _user;
  User? get user => _user;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Callback para que otras clases (como ChatScreen) puedan recibir mensajes
  void Function(Map<String, dynamic>)? onMessageReceived;

  // Constructor: ahora inicializamos el servicio aquí, evitando el error
  AuthProvider() {
    wsService = WebSocketService(onMessageReceived: _defaultMessageHandler);
    _loadUserFromStorage();
  }

  // Manejador por defecto si no se establece un callback externo
  void _defaultMessageHandler(Map<String, dynamic> message) {
    print('AuthProvider recibió mensaje (manejador por defecto): $message');
  }

  // --- LÓGICA DE REGISTRO ---
  Future<void> register(String username, String password, String publicKey) async {
    _setLoading(true);
    try {
      _user = await _repository.register(username, password, publicKey);
      await _saveUserToStorage(_user!); // Guardamos sesión
      _clearError();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  // --- LÓGICA DE LOGIN ---
  Future<void> login(String username, String password) async {
    _setLoading(true);
    try {
      _user = await _repository.login(username, password);
      await _saveUserToStorage(_user!); // Guardamos sesión
      
      // <-- CONECTAR WEBSOCKET DESPUÉS DEL LOGIN (usando el servicio público) -->
      wsService.connect(_user!.id, _user!.accessToken);
      
      _clearError();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  // --- LÓGICA DE LOGOUT ---
  Future<void> logout() async {
    wsService.disconnect(); // <-- DESCONECTAR WEBSOCKET (usando el servicio público)
    _user = null;
    await _clearUserFromStorage();
    notifyListeners();
  }

  // --- MÉTODOS AUXILIARES PARA MANEJO DE ESTADO Y ALMACENAMIENTO ---
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _saveUserToStorage(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', user.id);
    await prefs.setString('username', user.username);
    await prefs.setString('access_token', user.accessToken);
  }

  Future<void> _loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final username = prefs.getString('username');
    final token = prefs.getString('access_token');

    if (userId != null && username != null && token != null) {
      _user = User(id: userId, username: username, accessToken: token);
      // <-- RECONECTAR WEBSOCKET AL CARGAR SESIÓN (usando el servicio público) -->
      wsService.connect(_user!.id, _user!.accessToken);
      notifyListeners(); // Notificamos que ya hay un usuario cargado
    }
  }

  Future<void> _clearUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('username');
    await prefs.remove('access_token');
  }
}
