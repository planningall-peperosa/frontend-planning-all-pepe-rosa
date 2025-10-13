// lib/services/ore_lavorate_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fic_frontend/config/app_config.dart';

class OreLavorateService {
  String get _baseUrl => AppConfig.currentBaseUrl;

  /// Recupera la lista completa dei dipendenti dal backend.
  /// Utile per popolare i menu a tendina.
  Future<List<Map<String, dynamic>>> getDipendenti() async {
    final url = Uri.parse('$_baseUrl/dipendenti');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> dipendentiList = data['dipendenti'];
        return dipendentiList.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Errore nel caricare la lista dei dipendenti (${response.statusCode})');
      }
    } catch (e) {
      print('[OreLavorateService] Errore in getDipendenti: $e');
      rethrow;
    }
  }

  /// Chiama l'endpoint del backend per calcolare le ore di un dipendente.
  Future<Map<String, dynamic>> calcolaOre({
    required String pin,
    required String nomeDipendente,
    required String dataInizio, // Formato "YYYY-MM-DD"
    required String dataFine,   // Formato "YYYY-MM-DD"
  }) async {
    final url = Uri.parse('$_baseUrl/api/ore-lavorate/calcola');
    print('[OreLavorateService] Chiamata POST a $url per $nomeDipendente');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pin': pin,
          'nome_dipendente': nomeDipendente,
          'data_inizio': dataInizio,
          'data_fine': dataFine,
        }),
      ).timeout(const Duration(seconds: 45)); // Timeout aumentato per calcoli lunghi

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseData['success'] == true) {
          return responseData;
        } else {
          throw Exception(responseData['message'] ?? 'Errore restituito dal server durante il calcolo.');
        }
      } else {
        String errorMessage = 'Errore dal server (${response.statusCode})';
        errorMessage = '$errorMessage: ${responseData['detail'] ?? response.body}';
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('[OreLavorateService] Errore in calcolaOre: $e');
      // Rilancia l'eccezione per gestirla nella UI
      throw Exception('Impossibile calcolare le ore: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }
}
