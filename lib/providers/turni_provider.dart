// lib/providers/turni_provider.dart

import 'package:flutter/material.dart';
import '../models/tipo_turno.dart';
import '../services/turni_service.dart';

class TurniProvider with ChangeNotifier {
  final TipiTurnoService _service = TipiTurnoService();
  List<TipoTurno> _tipiTurno = [];
  bool _isLoading = false;
  String? _error;

  List<TipoTurno> get tipiTurno => _tipiTurno;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchTipiTurno() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _service.getTipiTurno();
      _tipiTurno = data.map((item) => TipoTurno.fromJson(item)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addTipoTurno(Map<String, dynamic> data) async {
    final response = await _service.addTipoTurno(data);
    if (response['statusCode'] == 201) {
      await fetchTipiTurno();
      return true;
    }
    return false;
  }

  Future<bool> updateTipoTurno(String id, Map<String, dynamic> data) async {
    final statusCode = await _service.updateTipoTurno(id, data);
    if (statusCode == 200) {
      final index = _tipiTurno.indexWhere((t) => t.idTurno == id);
      if (index != -1) {
        _tipiTurno[index].nomeTurno = data['nome_turno'] ?? _tipiTurno[index].nomeTurno;
        _tipiTurno[index].orarioInizio = data['orario_inizio'] ?? _tipiTurno[index].orarioInizio;
        _tipiTurno[index].orarioFine = data['orario_fine'] ?? _tipiTurno[index].orarioFine;
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  Future<bool> deleteTipoTurno(String id) async {
    final statusCode = await _service.deleteTipoTurno(id);
    if (statusCode == 200) {
      _tipiTurno.removeWhere((t) => t.idTurno == id);
      notifyListeners();
      return true;
    }
    return false;
  }
}