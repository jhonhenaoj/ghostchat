import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeyExchange {
  // Rotar claves cada 24 horas
  static Future<bool> shouldRotateKeys(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastRotation = prefs.getInt('key_rotation_$userId') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastRotation > 24 * 60 * 60 * 1000; // 24 horas
  }

  static Future<void> markKeyRotation(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('key_rotation_$userId', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<String, String>> rotateKeys(String userId) async {
    final keyPair = generateKeyPair();
    await saveKeyPair(userId, keyPair);
    await markKeyRotation(userId);
    return keyPair;
  }
  static const int _dhPrimeBits = 2048;

  // Primo seguro de 2048 bits (RFC 3526 Group 14)
  static final BigInt _p = BigInt.parse(
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'
    '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'
    'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'
    'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
    'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D'
    'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'
    '83655D23DCA3AD961C62F356208552BB9ED529077096966D'
    '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'
    'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9'
    'DE2BCBF6955817183995497CEA956AE515D2261898FA0510'
    '15728E5A8AACAA68FFFFFFFFFFFFFFFF',
    radix: 16,
  );
  static final BigInt _g = BigInt.from(2);

  // Generar par de claves DH
  static Map<String, String> generateKeyPair() {
    final random = Random.secure();
    // Clave privada aleatoria de 256 bits
    final privateKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final privateKey = BigInt.parse(
      privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    // Clave pública = g^privateKey mod p
    final publicKey = _g.modPow(privateKey, _p);
    return {
      'private': privateKey.toRadixString(16),
      'public': publicKey.toRadixString(16),
    };
  }

  // Calcular secreto compartido
  static String computeSharedSecret(String theirPublicHex, String myPrivateHex) {
    final theirPublic = BigInt.parse(theirPublicHex, radix: 16);
    final myPrivate = BigInt.parse(myPrivateHex, radix: 16);
    final sharedSecret = theirPublic.modPow(myPrivate, _p);
    // Tomar primeros 32 bytes como clave AES-256
    final hex = sharedSecret.toRadixString(16).padLeft(64, '0');
    return hex.substring(0, 64);
  }

  // Guardar claves en disco
  static Future<void> saveKeyPair(String userId, Map<String, String> keyPair) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dh_private_$userId', keyPair['private']!);
    await prefs.setString('dh_public_$userId', keyPair['public']!);
  }

  // Cargar clave privada
  static Future<String?> loadPrivateKey(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dh_private_$userId');
  }

  // Cargar clave publica
  static Future<String?> loadPublicKey(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dh_public_$userId');
  }

  // Guardar clave publica del otro usuario
  static Future<void> saveTheirPublicKey(String theirUserId, String publicKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dh_their_public_$theirUserId', publicKey);
  }

  // Cargar clave publica del otro usuario
  static Future<String?> loadTheirPublicKey(String theirUserId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dh_their_public_$theirUserId');
  }

  // Guardar secreto compartido
  static Future<void> saveSharedSecret(String withUserId, String secret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dh_shared_$withUserId', secret);
  }

  // Cargar secreto compartido
  static Future<String?> loadSharedSecret(String withUserId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('dh_shared_$withUserId');
  }
}
