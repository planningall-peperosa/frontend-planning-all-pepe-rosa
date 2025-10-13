// lib/services/preventivi_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode; // <-- LOG
import '../config/app_config.dart';

void _logSvc(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[SERVICE] $msg');
  }
}

class PreventiviService {
  final String baseUrl;
  final http.Client _client;

  PreventiviService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.currentBaseUrl,
        _client = client ?? http.Client();

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(
        queryParameters: q?.map((k, v) => MapEntry(k, '$v')),
      );

  // --- Sync versione cache (globale) -----------------------------------------
  Future<int?> getVersioneCache() async {
    final sw = Stopwatch()..start();
    final res = await _client.get(_u('/api/sync/versione'));
    sw.stop();
    _logSvc('GET /api/sync/versione -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final swDec = Stopwatch()..start();
      final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      swDec.stop();
      _logSvc('decode versione ${swDec.elapsedMilliseconds}ms');
      return map['versione'] as int?;
    }
    throw Exception('Errore versione cache: ${res.statusCode}');
  }

  /// NEW: wrapper compatibile col provider che si aspetta una mappa (per anno).
  /// Se il backend espone solo una versione globale, la mappo in {"all": <versione>}.
  // --- Sync versioni cache (per-anno) -----------------------------------------
  Future<Map<String, int>> getVersioniCache() async {
    final sw = Stopwatch()..start();
    final res = await _client.get(_u('/api/sync/versioni'));
    sw.stop();
    _logSvc('GET /api/sync/versioni -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decSw = Stopwatch()..start();
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      decSw.stop();
      _logSvc('decode versioni ${decSw.elapsedMilliseconds}ms (type=${decoded.runtimeType})');

      if (decoded is Map) {
        final out = <String, int>{};
        decoded.forEach((k, v) {
          int val;
          try {
            val = v is int ? v : int.parse(v.toString());
          } catch (_) {
            val = 0;
          }
          out[k.toString()] = val;
        });
        return out;
      }
      // formato inatteso
      return {};
    }
    throw Exception('Errore versioni cache: ${res.statusCode}');
  }



  // --- Indici (lista preventivi) --------------------------------------------
  Future<List<Map<String, dynamic>>> getTuttiGliIndici() async {
    final sw = Stopwatch()..start();
    final res = await _client.get(_u('/api/preventivi/indici/tutti'));
    sw.stop();
    _logSvc('GET /api/preventivi/indici/tutti -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final swDec = Stopwatch()..start();
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      swDec.stop();
      _logSvc('decode indici ${swDec.elapsedMilliseconds}ms (type=${decoded.runtimeType})');

      List<dynamic> list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['items'] is List) {
        list = decoded['items'] as List;
      } else {
        throw Exception('Formato indici inatteso: ${decoded.runtimeType}');
      }

      _logSvc('indici items=${list.length}');
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    throw Exception('Errore caricamento indici: ${res.statusCode}');
  }

  // --- Dettaglio preventivo --------------------------------------------------
  Future<Map<String, dynamic>> getPreventivo(String preventivoId) async {
    final sw = Stopwatch()..start();
    final res = await _client.get(_u('/api/preventivi/$preventivoId'));
    sw.stop();
    _logSvc('GET /api/preventivi/$preventivoId -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final swDec = Stopwatch()..start();
      final m = Map<String, dynamic>.from(
        json.decode(utf8.decode(res.bodyBytes)) as Map,
      );
      swDec.stop();
      _logSvc('decode preventivo ${swDec.elapsedMilliseconds}ms');
      return m;
    }
    throw Exception('Errore get preventivo: ${res.statusCode}');
  }

  // --- Crea/Aggiorna preventivo ---------------------------------------------
  Future<Map<String, dynamic>> creaNuovoPreventivo(
      Map<String, dynamic> payload) async {
    final encSw = Stopwatch()..start();
    final body = json.encode(payload);
    encSw.stop();
    _logSvc('creaNuovoPreventivo encode ${encSw.elapsedMilliseconds}ms');

    final sw = Stopwatch()..start();
    final res = await _client.post(
      _u('/api/preventivi'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    sw.stop();
    _logSvc('POST /api/preventivi -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    return _decodeJsonOk(res, 'creaNuovoPreventivo');
  }

  Future<Map<String, dynamic>> aggiornaPreventivo(
      String preventivoId, Map<String, dynamic> payload) async {
    final encSw = Stopwatch()..start();
    final body = json.encode(payload);
    encSw.stop();
    _logSvc('aggiornaPreventivo encode ${encSw.elapsedMilliseconds}ms (id=$preventivoId)');

    final sw = Stopwatch()..start();
    final res = await _client.put(
      _u('/api/preventivi/$preventivoId'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    sw.stop();
    _logSvc('PUT /api/preventivi/$preventivoId -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    return _decodeJsonOk(res, 'aggiornaPreventivo');
  }

  // --- Conferma / Elimina ----------------------------------------------------
  Future<Map<String, dynamic>> confermaPreventivo(String preventivoId) async {
    final sw = Stopwatch()..start();
    final res = await _client.post(_u('/api/preventivi/$preventivoId/conferma'));
    sw.stop();
    _logSvc('POST /api/preventivi/$preventivoId/conferma -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    return _decodeJsonOk(res, 'confermaPreventivo');
  }

  Future<bool> eliminaPreventivo(String preventivoId) async {
    final sw = Stopwatch()..start();
    final res = await _client.delete(_u('/api/preventivi/$preventivoId'));
    sw.stop();
    _logSvc('DELETE /api/preventivi/$preventivoId -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms');
    if (res.statusCode == 204) return true;
    if (res.statusCode >= 200 && res.statusCode < 300) return true;
    return false;
  }

  // --- Salva & genera PDF ----------------------------------------------------
  Future<Uint8List> salvaEGeneraPdf(Map<String, dynamic> body) async {
    final encSw = Stopwatch()..start();
    final bodyStr = json.encode(body);
    encSw.stop();
    _logSvc('salvaEGeneraPdf encode ${encSw.elapsedMilliseconds}ms');

    final sw = Stopwatch()..start();
    final res = await _client.post(
      _u('/api/preventivi/salva-e-genera-pdf'),
      headers: {'Content-Type': 'application/json'},
      body: bodyStr,
    );
    sw.stop();
    _logSvc('POST /api/preventivi/salva-e-genera-pdf -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception('Errore PDF: ${res.statusCode}');
  }

  // --- Duplicazione ----------------------------------------------------------
  Future<String?> duplicaPreventivoDaId(
    String preventivoId, {
    String? nomeEventoOverride,
    bool appendCopiaIfMissing = true,
  }) async {
    final t = Stopwatch()..start();
    _logSvc('DUPL start (id=$preventivoId)');

    final t1 = Stopwatch()..start();
    final original = await getPreventivo(preventivoId);
    t1.stop();
    _logSvc('DUPL getPreventivo ${t1.elapsedMilliseconds}ms');

    final payload = <String, dynamic>{...original};
    payload.remove('preventivo_id');
    payload.remove('status');
    payload.remove('data_creazione');
    payload.remove('data_modifica');
    payload.remove('data_conferma');
    payload.remove('firma_acquisita');

    final currentName = (original['nome_evento'] as String?)?.trim() ?? '';
    if (nomeEventoOverride != null && nomeEventoOverride.trim().isNotEmpty) {
      payload['nome_evento'] = nomeEventoOverride.trim();
    } else if (appendCopiaIfMissing) {
      payload['nome_evento'] =
          currentName.isEmpty ? '(copia)' : '$currentName (copia)';
    }

    final t2 = Stopwatch()..start();
    final resp = await creaNuovoPreventivo(payload);
    t2.stop();
    _logSvc('DUPL creaNuovoPreventivo ${t2.elapsedMilliseconds}ms');

    final success = resp['success'] == true;
    final nuovoId = resp['preventivo_id'] as String?;
    t.stop();
    _logSvc('DUPL done total=${t.elapsedMilliseconds}ms success=$success nuovoId=$nuovoId');
    if (success && nuovoId != null && nuovoId.isNotEmpty) {
      return nuovoId;
    }
    return null;
  }

  // --------------------------------------------------------------------------
  Map<String, dynamic> _decodeJsonOk(http.Response res, String ctx) {
    final body = utf8.decode(res.bodyBytes);
    final decSw = Stopwatch()..start();
    final decoded = body.isNotEmpty ? json.decode(body) : {};
    decSw.stop();
    _logSvc('$ctx decode ${decSw.elapsedMilliseconds}ms (status=${res.statusCode}, bytes=${res.bodyBytes.length})');
    if (res.statusCode >= 200 && res.statusCode < 300 && decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    _logSvc('$ctx ERROR status=${res.statusCode} body=$body');
    throw Exception('Errore $ctx: ${res.statusCode} ${res.body}');
  }

  // =============================
  //   FIRMA – METODO CORRETTO
  // =============================
  Future<bool> uploadFirmaPng(String preventivoId, Uint8List pngBytes) async {
    final b64 = base64Encode(pngBytes);
    final body = jsonEncode({
      'data_url': 'data:image/png;base64,$b64',
    });

    final sw = Stopwatch()..start();
    final res = await _client.post(
      _u('/api/preventivi/$preventivoId/firma'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    sw.stop();
    _logSvc('POST /api/preventivi/$preventivoId/firma -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['ok'] == true) return true;
        return true;
      } catch (_) {
        return true;
      }
    }
    throw Exception('Errore upload firma: ${res.statusCode} ${res.body}');
  }

  // =============================
  //   METODI ESISTENTI (legacy)
  // =============================
  Future<bool> confermaConFirma(String preventivoId, String firmaBase64Png) async {
    final uri = Uri.parse('$baseUrl/api/preventivi/$preventivoId/conferma-con-firma');
    final sw = Stopwatch()..start();
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'firma_base64_png': firmaBase64Png}),
    );
    sw.stop();
    _logSvc('POST /api/preventivi/$preventivoId/conferma-con-firma -> ${resp.statusCode} in ${sw.elapsedMilliseconds}ms');
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        return (m['success'] == true);
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  Future<bool> caricaFirma({required String preventivoId, required Uint8List pngBytes}) async {
    final b64 = base64Encode(pngBytes);
    final url = Uri.parse('$baseUrl/api/preventivi/$preventivoId/firma');

    final sw = Stopwatch()..start();
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'firma_base64_png': b64}),
    );
    sw.stop();
    _logSvc('POST /api/preventivi/$preventivoId/firma [legacy] -> ${resp.statusCode} in ${sw.elapsedMilliseconds}ms');

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final data = jsonDecode(resp.body);
        return (data is Map && (data['success'] == true));
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  Future<void> firmaPreventivo(String preventivoId) async {
    final String _baseUrl = AppConfig.currentBaseUrl;
    final uri = Uri.parse('$_baseUrl/api/preventivi/$preventivoId/conferma');
    final sw = Stopwatch()..start();
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );
    sw.stop();
    _logSvc('POST /api/preventivi/$preventivoId/conferma [legacy] -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms');

    if (res.statusCode != 200) {
      try {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final msg = body['detail'] ??
            body['message'] ??
            'Errore ${res.statusCode} durante la conferma preventivo';
        throw Exception(msg.toString());
      } catch (_) {
        throw Exception('Errore ${res.statusCode} durante la conferma preventivo');
      }
    }
  }
}
