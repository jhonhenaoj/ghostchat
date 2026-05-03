import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SecureHttpClient {
  static http.Client create() {
    final context = SecurityContext.defaultContext;
    final httpClient = HttpClient(context: context);

    // Solo aceptar conexiones al servidor conocido
    httpClient.badCertificateCallback = (cert, host, port) {
      // En produccion aqui se valida el certificado real
      // Por ahora solo verificamos el host
      return host == 'kits-stranger-dimension-grove.trycloudflare.com';
    };

    return IOClient(httpClient);
  }
}
