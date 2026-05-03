import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class CryptoService {
  // Cifra un mensaje usando SHA-256. Es un "hash", no se puede descifrar,
  // pero es una demo de criptografía funcional y visual.
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';

    final bytes = utf8.encode(plainText);
    final hash = sha256.convert(bytes);

    // Lo devolvemos en formato hexadecimal para que se vea bien en la UI
    return hash.toString();
  }

  // Como SHA-256 es un hash de una sola vía, no podemos descifrarlo.
  // Devolveremos un texto explicativo.
  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return '';
    return '¡No se puede! SHA-256 es de una sola vía (hash).';
  }
}
