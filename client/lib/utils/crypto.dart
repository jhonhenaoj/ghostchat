import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;

class GhostCrypto {
  // Clave por usuario en vez de global
  static final Map<String, List<int>> _keys = {};

  static void setSharedSecret(String hexSecret, {String userId = 'default'}) {
    try {
      if (hexSecret.length < 64) return;
      final bytes = <int>[];
      for (int i = 0; i < 64; i += 2) {
        bytes.add(int.parse(hexSecret.substring(i, i + 2), radix: 16));
      }
      _keys[userId] = bytes.take(32).toList();
    } catch (_) {}
  }

  static bool hasKey({String userId = 'default'}) => _keys.containsKey(userId);

  static String encrypt(String plainText, {String userId = 'default'}) {
    final keyBytes = _keys[userId];
    if (keyBytes == null || plainText.isEmpty) return plainText;
    try {
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      final combined = iv.bytes + encrypted.bytes;
      return base64.encode(combined);
    } catch (_) {
      return plainText;
    }
  }

  static String decrypt(String cipherText, {String userId = 'default'}) {
    final keyBytes = _keys[userId];
    if (keyBytes == null || cipherText.isEmpty) return cipherText;
    try {
      final combined = base64.decode(cipherText);
      if (combined.length < 16) return cipherText;
      final iv = enc.IV(Uint8List.fromList(combined.sublist(0, 16)));
      final cipherBytes = combined.sublist(16);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt(enc.Encrypted(Uint8List.fromList(cipherBytes)), iv: iv);
    } catch (_) {
      return cipherText;
    }
  }

  static String generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64.encode(bytes);
  }
}
