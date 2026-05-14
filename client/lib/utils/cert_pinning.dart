import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SecureHttpClient {
  static http.Client create() {
    final context = SecurityContext.defaultContext;
    final httpClient = HttpClient(context: context);

    // Solo aceptar conexiones al servidor conocido
    httpClient.badCertificateCallback = (cert, host, port) {
      // Solo permitir hosts conocidos
      const allowedHosts = [
        'api.soluciones-publicitarias-latam.com',
        '162.243.174.252',
      ];
      return allowedHosts.contains(host);
    };

    return IOClient(httpClient);
  }
}
