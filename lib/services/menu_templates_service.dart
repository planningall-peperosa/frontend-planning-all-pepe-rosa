import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class MenuTemplatesService {
  final String _baseUrl = AppConfig.currentBaseUrl;

  // GET /api/menu/templates
  Future<List<dynamic>> getMenuTemplates() async {
    final r = await http.get(Uri.parse('$_baseUrl/api/menu/templates'));
    if (r.statusCode != 200) {
      throw Exception('Errore caricamento menu: ${r.statusCode} ${r.body}');
    }
    final list = jsonDecode(r.body) as List;

    // Normalizza 'composizione_default' / '..._json' in una Map
    return list.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final comp = m['composizione_default'] ?? m['composizione_default_json'];

      if (comp is String) {
        try {
          m['composizione_default'] = Map<String, dynamic>.from(jsonDecode(comp));
        } catch (_) {
          m['composizione_default'] = <String, dynamic>{};
        }
      } else if (comp is Map) {
        m['composizione_default'] = Map<String, dynamic>.from(comp);
      } else {
        m['composizione_default'] = <String, dynamic>{};
      }
      return m;
    }).toList();
  }

  // POST /api/menu/templates
  Future<Map<String, dynamic>> addMenuTemplate(Map<String, dynamic> data) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/menu/templates'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(data), // inviamo un OGGETTO, non una stringa
    );
    final body = r.body.isNotEmpty ? jsonDecode(r.body) : {};
    return {'statusCode': r.statusCode, 'body': body};
  }

  // PUT /api/menu/templates/{id}
  Future<Map<String, dynamic>> updateMenuTemplate(String id, Map<String, dynamic> data) async {
    final r = await http.put(
      Uri.parse('$_baseUrl/api/menu/templates/$id'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(data),
    );
    final body = r.body.isNotEmpty ? jsonDecode(r.body) : {};
    return {'statusCode': r.statusCode, 'body': body};
  }

  // DELETE /api/menu/templates/{id}
  Future<Map<String, dynamic>> deleteMenuTemplate(String id) async {
    final r = await http.delete(Uri.parse('$_baseUrl/api/menu/templates/$id'));
    final body = r.body.isNotEmpty ? jsonDecode(r.body) : {};
    return {'statusCode': r.statusCode, 'body': body};
  }
}
