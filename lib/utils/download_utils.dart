// lib/utils/download_utils.dart

import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Scarica i byte dell'immagine della firma da un URL.
/// Ritorna una Uint8List vuota se il download fallisce o l'URL non è HTTP/S.
Future<Uint8List> scaricaFirmaDaStorage(String url) async {
  if (url.isEmpty) {
    return Uint8List(0);
  }
  
  // 🔑 CORREZIONE: CONTROLLO DELLO SCHEMA NON SUPPORTATO
  if (!url.toLowerCase().startsWith('http')) {
      if (kDebugMode) print('[Firma Download] ERRORE: L\'URL non usa lo schema HTTP/S. URL: $url');
      return Uint8List(0);
  }
  
  try {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      if (kDebugMode) print('[Firma Download] Download completato: ${response.bodyBytes.length} bytes.');
      return response.bodyBytes;
    } else {
      if (kDebugMode) print('[Firma Download] Errore HTTP ${response.statusCode}');
      return Uint8List(0);
    }
  } catch (e) {
    if (kDebugMode) print('[Firma Download] Errore di rete/parsing: $e');
    return Uint8List(0);
  }
}