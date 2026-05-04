import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/user.dart';

class AuthRepository {
  final String _baseUrl = 'http://162.243.174.252:9090';

  Future<User> register(String username, String password, String publicKey) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'public_key': publicKey,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return User(id: data['user_id'], username: data['username'], accessToken: '');
    } else {
      throw Exception(jsonDecode(response.body)['error']);
    }
  }

  Future<User> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return User(id: data['user_id'], username: data['username'], accessToken: data['access_token']);
    } else {
      throw Exception(jsonDecode(response.body)['error']);
    }
  }
}
