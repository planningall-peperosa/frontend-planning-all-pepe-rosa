// lib/services/sync_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../config/app_config.dart';

void _logSync(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[SYNC] $msg');
  }
}

class SyncService {
  final String _baseUrl;
  final http.Client _client;

  SyncService({String? baseUrl, http.Client? client})
      : _baseUrl = (baseUrl ?? AppConfig.currentBaseUrl)
            .replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$_baseUrl$path').replace(
        queryParameters: q?.map((k, v) => MapEntry(k, '$v')),
      );

  void dispose() {
    try {
      _client.close();
    } catch (_) {}
  }

  /// Versione cache *globale* (intero singolo).
  Future<int?> getVersione() async {
    final sw = Stopwatch()..start();
    final res = await _client.get(_u('/api/sync/versione'));
    sw.stop();
    _logSync('GET /api/sync/versione -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final dec = Stopwatch()..start();
      final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      dec.stop();
      _logSync('decode versione ${dec.elapsedMilliseconds}ms');
      return map['versione'] as int?;
    }
    throw Exception('Errore versione cache: ${res.statusCode}');
  }

  /// Alias per retrocompatibilità col provider esistente.
  Future<int?> getVersioneCorrente() => getVersione();

  /// Versioni cache *per anno* (mappa string->int).
  Future<Map<String, int>> getVersioni() async {
    final sw = Stopwatch()..start();
    final res = await _client.get(_u('/api/sync/versioni'));
    sw.stop();
    _logSync('GET /api/sync/versioni -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms, bytes=${res.bodyBytes.length}');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final dec = Stopwatch()..start();
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      dec.stop();
      _logSync('decode versioni ${dec.elapsedMilliseconds}ms (type=${decoded.runtimeType})');

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
      return {};
    }
    throw Exception('Errore versioni cache: ${res.statusCode}');
  }
}
