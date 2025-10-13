import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class SegretarioApi {
  SegretarioApi({required this.baseUrl});

  final String baseUrl; // es. http://127.0.0.1:8000

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<PromemoriaResponse> getPromemoria({
    int finestraOre = 168, // 7 giorni
    bool debug = false,
    bool refresh = false,
  }) async {
    final params = <String, String>{
      'finestra_ore': finestraOre.toString(),
      if (debug) 'debug': 'true',
      if (refresh) 'refresh': 'true',
      // cache-buster per evitare proxy/cache intermedie quando forziamo il refresh
      if (refresh) '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri = _u('/api/segretario/promemoria', params);
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return PromemoriaResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('Errore getPromemoria: ${res.statusCode} ${res.body}');
  }

  Future<void> postAzioneDone({
    required String preventivoId,
    required String actionId,
    String? note,
  }) async {
    final uri = _u('/api/segretario/azione/done');
    final payload = jsonEncode({
      'preventivo_id': preventivoId,
      'id': actionId,
      if (note != null) 'note': note,
    });
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: payload,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Errore postAzioneDone: ${res.statusCode} ${res.body}');
    }
  }
}
