// lib/services/turni_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class TipiTurnoService {
  final String _baseUrl = AppConfig.currentBaseUrl;

  // Prende la lista di tutti i tipi di turno
  Future<List<Map<String, dynamic>>> getTipiTurno() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/tipi-turno'));
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Errore caricamento tipi turno (${response.statusCode})');
  }

  // Aggiunge un nuovo tipo di turno
  Future<Map<String, dynamic>> addTipoTurno(Map<String, dynamic> data) async {
    final response = await http.post(Uri.parse('$_baseUrl/api/tipi-turno'),
        headers: {'Content-Type': 'application/json'}, body: json.encode(data));
    return {'statusCode': response.statusCode, 'body': json.decode(response.body)};
  }

  // Aggiorna un tipo di turno esistente
  Future<int> updateTipoTurno(String id, Map<String, dynamic> data) async {
    final response = await http.put(Uri.parse('$_baseUrl/api/tipi-turno/$id'),
        headers: {'Content-Type': 'application/json'}, body: json.encode(data));
    return response.statusCode;
  }

  // Cancella un tipo di turno
  Future<int> deleteTipoTurno(String id) async {
    final response = await http.delete(Uri.parse('$_baseUrl/api/tipi-turno/$id'));
    return response.statusCode;
  }
}