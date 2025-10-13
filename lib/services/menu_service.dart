// lib/services/menu_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class MenuService {
  // Prende l'URL base (es. http://127.0.0.1:8000) dal nostro file di configurazione
  String get _baseUrl => AppConfig.currentBaseUrl;

  /// Gestisce la risposta del server, decodificandola o lanciando un errore.
  dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      // Usiamo utf8.decode per gestire correttamente i caratteri speciali come 'à', 'è', 'ì'
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Errore dal server (${response.statusCode}): ${response.body}');
    }
  }

  /// Chiama l'endpoint /api/menu/data per ottenere la lista completa dei piatti e delle categorie.
  Future<Map<String, dynamic>> getMenuData() async {
    print("[MenuService] Chiamata per ottenere tutti i piatti e le categorie...");
    final uri = Uri.parse('$_baseUrl/api/menu/data');
    final response = await http.get(uri);
    return _processResponse(response) as Map<String, dynamic>;
  }

  /// Chiama l'endpoint /api/menu/templates per ottenere i template dei menu.
  Future<List<dynamic>> getMenuTemplates() async {
    print("[MenuService] Chiamata per ottenere i template dei menu...");
    final uri = Uri.parse('$_baseUrl/api/menu/templates');
    final response = await http.get(uri);
    return _processResponse(response) as List<dynamic>;
  }
}