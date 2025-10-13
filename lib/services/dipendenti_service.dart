// lib/services/dipendenti_service.dart
// VERSIONE CHE RESTITUISCE ANCHE IL BODY DELLA RISPOSTA

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart'; 

class DipendentiService {
  final String _baseUrl = AppConfig.currentBaseUrl;

  Future<List<dynamic>> getDipendenti() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/dipendenti'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      print('Errore caricamento dipendenti: ${response.body}');
      throw Exception('Errore nel caricare i dipendenti: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> addDipendente(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/dipendenti'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: json.encode(data),
    );
    final responseBody = response.body.isNotEmpty ? json.decode(response.body) : {};
    return {'statusCode': response.statusCode, 'body': responseBody};
  }

  // --- MODIFICA CHIAVE QUI ---
  Future<Map<String, dynamic>> updateDipendente(String id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/dipendenti/$id'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: json.encode(data),
    );
    final responseBody = response.body.isNotEmpty ? json.decode(response.body) : {};
    return {'statusCode': response.statusCode, 'body': responseBody};
  }
  // --- FINE MODIFICA ---

  Future<Map<String, dynamic>> deleteDipendente(String id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/dipendenti/$id'),
    );
    final responseBody = response.body.isNotEmpty ? json.decode(response.body) : {};
    return {'statusCode': response.statusCode, 'body': responseBody};
  }
}