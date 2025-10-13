// lib/services/piatti_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class PiattiService {
  final String _baseUrl = AppConfig.currentBaseUrl;

  Future<List<dynamic>> getPiatti() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/menu/data'));
    if (res.statusCode != 200) {
      throw Exception('Errore getPiatti: ${res.statusCode} -> ${res.body}');
    }
    final decoded = json.decode(res.body);
    // il backend risponde { categorie: [...], piatti: [...] }
    final list = decoded['piatti'] ?? [];
    return List<Map<String, dynamic>>.from(list);
  }

  Future<Map<String, dynamic>> addPiatto(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/menu/piatti'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: json.encode(data),
    );
    final body = res.body.isNotEmpty ? json.decode(res.body) : {};
    return {'statusCode': res.statusCode, 'body': body};
  }

  Future<Map<String, dynamic>> updatePiatto(String idUnico, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/menu/piatti/$idUnico'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: json.encode(data),
    );
    final body = res.body.isNotEmpty ? json.decode(res.body) : {};
    return {'statusCode': res.statusCode, 'body': body};
  }

  Future<Map<String, dynamic>> deletePiatto(String idUnico) async {
    final res = await http.delete(Uri.parse('$_baseUrl/api/menu/piatti/$idUnico'));
    final body = res.body.isNotEmpty ? json.decode(res.body) : {};
    return {'statusCode': res.statusCode, 'body': body};
  }
}
