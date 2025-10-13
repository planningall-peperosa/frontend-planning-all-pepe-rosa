// lib/services/clienti_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ClientiService {
  String get _baseUrl => AppConfig.currentBaseUrl;

  dynamic _processResponse(http.Response response) {
    // Gestisce lo status code 204 (No Content) per le eliminazioni
    if (response.statusCode == 204) return {}; 

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Errore dal server (${response.statusCode}): ${response.body}');
    }
  }

  Future<List<dynamic>> cercaContatti(String query) async {
    final uri = Uri.parse('$_baseUrl/api/contatti/cerca?query=${Uri.encodeComponent(query)}');
    final response = await http.get(uri);
    return _processResponse(response) as List<dynamic>;
  }

  Future<int> getConteggioReale(String idCliente) async {
    final uri = Uri.parse('$_baseUrl/api/contatti/$idCliente/conteggio_reale');
    final response = await http.get(uri);
    final data = _processResponse(response) as Map<String, dynamic>;
    return data['conteggio'] ?? 0;
  }
  
  Future<Map<String, dynamic>> creaNuovoContatto(Map<String, dynamic> data) async {
    print("[ClientiService] Invio nuovo contatto al backend...");
    final uri = Uri.parse('$_baseUrl/api/contatti');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(data),
    );
    return _processResponse(response);
  }

  // --- NUOVI METODI PER MODIFICA ED ELIMINAZIONE ---

  /// Aggiorna un contatto esistente.
  Future<Map<String, dynamic>> aggiornaContatto(String idContatto, Map<String, dynamic> data) async {
    print("[ClientiService] Aggiorno contatto con ID: $idContatto...");
    final uri = Uri.parse('$_baseUrl/api/contatti/$idContatto');
    final response = await http.put(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(data),
    );
    return _processResponse(response);
  }

  /// Elimina un contatto esistente.
  Future<void> eliminaContatto(String idContatto, String tipo) async {
    print("[ClientiService] Elimino contatto con ID: $idContatto...");
    final uri = Uri.parse('$_baseUrl/api/contatti/$idContatto?tipo=${Uri.encodeComponent(tipo)}');
    final response = await http.delete(uri);
    _processResponse(response); // Usato per controllare che la risposta sia valida (es. 204)
  }
  
  // --- FINE NUOVI METODI ---

  Future<List<String>> getRuoliServizi() async {
    print("[ClientiService] Richiesta lista ruoli servizi...");
    final uri = Uri.parse('$_baseUrl/api/setup/ruoli-servizi');
    final response = await http.get(uri);
    final data = _processResponse(response) as List<dynamic>;
    return List<String>.from(data);
  }
}