// lib/providers/piatti_provider.dart
import 'package:flutter/material.dart';
import '../models/piatto.dart';
import '../services/piatti_service.dart';

class PiattiProvider with ChangeNotifier {
  final PiattiService _service = PiattiService();

  List<Piatto> _piatti = [];
  bool _loading = false;
  String? _error;

  List<Piatto> get piatti => _piatti;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> fetch() async {
    _loading = true; _error = null; notifyListeners();
    try {
      final data = await _service.getPiatti();
      _piatti = data.map<Piatto>((j) => Piatto.fromJson(j)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<bool> add(Map<String, dynamic> payload) async {
    _loading = true; notifyListeners();
    try {
      final res = await _service.addPiatto(payload);
      if (res['statusCode'] == 201) {
        await fetch();
        return true;
      }
      _error = res['body']?['detail'] ?? 'Errore sconosciuto';
      return false;
    } catch (e) {
      _error = e.toString(); return false;
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<bool> update(String idUnico, Map<String, dynamic> payload) async {
    try {
      final res = await _service.updatePiatto(idUnico, payload);
      if (res['statusCode'] == 200) {
        final i = _piatti.indexWhere((p) => p.idUnico == idUnico);
        if (i != -1) {
          // aggiorno solo i campi cambiati (mappati con nomi foglio)
          _piatti[i] = _piatti[i].copyWith(
            genere:      payload['genere'],
            nome:        payload['nome'],        // << era 'piatto'
            descrizione: payload['descrizione'],
            allergeni:   payload['allergeni'],
            linkFoto:    payload['link_foto'],   // << era 'link_foto_piatto'
            tipologia:   payload['tipologia'],
          );
          notifyListeners();
        }
        return true;
      }
      _error = res['body']?['detail'] ?? 'Errore ${res['statusCode']}';
      return false;
    } catch (e) {
      _error = e.toString(); notifyListeners(); return false;
    }
  }

  Future<bool> remove(String idUnico) async {
    try {
      final res = await _service.deletePiatto(idUnico);
      if (res['statusCode'] == 200) {
        _piatti.removeWhere((p) => p.idUnico == idUnico);
        notifyListeners();
        return true;
      }
      _error = res['body']?['detail'] ?? 'Errore ${res['statusCode']}';
      return false;
    } catch (e) {
      _error = e.toString(); notifyListeners(); return false;
    }
  }
}
