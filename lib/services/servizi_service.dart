// lib/services/servizi_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/fornitore_servizio.dart';


class ServiziService {
  String get _baseUrl => AppConfig.currentBaseUrl;

  dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return [];
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Errore dal server (${response.statusCode}): ${response.body}');
    }
  }

  /// Recupera la lista di fornitori per un ruolo specifico.
  Future<List<FornitoreServizio>> getFornitoriPerRuolo(String ruolo) async {
    print("[ServiziService] Richiesta fornitori per ruolo: $ruolo");
    final uri = Uri.parse('$_baseUrl/api/servizi?ruolo=${Uri.encodeComponent(ruolo)}');
    final response = await http.get(uri);
    final data = _processResponse(response) as List<dynamic>;
    return data.map((json) => FornitoreServizio.fromJson(json)).toList();
  }

  // NUOVO METODO
  Future<List<String>> getTuttiIRuoli() async {
    print("[ServiziService] Richiesta di tutti i ruoli dei servizi...");
    final uri = Uri.parse('$_baseUrl/api/servizi/ruoli');
    final response = await http.get(uri);
    final data = _processResponse(response) as List<dynamic>;
    return List<String>.from(data);
  }
}