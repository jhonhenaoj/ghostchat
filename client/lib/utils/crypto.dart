import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart';

class GhostCrypto {
  static List<int> _keyBytes = List<int>.filled(32, 0);
  static bool _hasKey = false;

  static void setSharedSecret(String hexSecret) {
    final bytes = <int>[];
    for (int i = 0; i < 64; i += 2) {
      bytes.add(int.parse(hexSecret.substring(i, i + 2), radix: 16));
    }
    _keyBytes = bytes.take(32).toList();
    _hasKey = true;
  }

  static String encrypt(String plainText) {
    if (!_hasKey || plainText.isEmpty) return plainText;
    try {
      final key = enc.Key(Uint8List.fromList(_keyBytes));
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      // Combinar IV + ciphertext en base64
      final combined = iv.bytes + encrypted.bytes;
      return base64.encode(combined);
    } catch (_) {
      return plainText;
    }
  }

  static String decrypt(String cipherText) {
    if (!_hasKey || cipherText.isEmpty) return cipherText;
    try {
      final combined = base64.decode(cipherText);
      if (combined.length < 16) return cipherText;
      final iv = enc.IV(Uint8List.fromList(combined.sublist(0, 16)));
      final cipherBytes = combined.sublist(16);
      final key = enc.Key(Uint8List.fromList(_keyBytes));
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

  static String signMessage(String message, String privateKeyHex) {
    try {
      final key = utf8.encode(privateKeyHex.substring(0, 32));
      final bytes = utf8.encode(message);
      final hmac = List<int>.generate(32, (i) => bytes[i % bytes.length] ^ key[i % key.length]);
      return base64.encode(hmac);
    } catch (_) {
      return '';
    }
  }

  static bool verifySignature(String message, String signature, String privateKeyHex) {
    return signMessage(message, privateKeyHex) == signature;
  }
}
