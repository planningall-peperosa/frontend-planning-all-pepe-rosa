// lib/providers/dipendenti_provider.dart
// VERSIONE CON DEBUG AVANZATO PER L'UPDATE

import 'package:flutter/material.dart';
import '../models/dipendente.dart';
import '../services/dipendenti_service.dart';

class DipendentiProvider with ChangeNotifier {
  final DipendentiService _service = DipendentiService();
  
  List<Dipendente> _dipendenti = [];
  bool _isLoading = false;
  String? _error;

  List<Dipendente> get dipendenti => _dipendenti;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchDipendenti() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _service.getDipendenti();
      _dipendenti = data.map((item) => Dipendente.fromJson(item)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addDipendente(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _service.addDipendente(data);
      if (response['statusCode'] == 201) {
        await fetchDipendenti(); 
        return true;
      }
      _error = response['body']?['detail'] ?? 'Errore sconosciuto dal server.';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- MODIFICA CHIAVE QUI ---
  Future<bool> updateDipendente(String id, Map<String, dynamic> data) async {
    try {
      print("[DipendentiProvider] Tentativo di aggiornare dipendente ID: $id");
      final response = await _service.updateDipendente(id, data);
      
      // Stampiamo sempre la risposta per il debug
      print("[DipendentiProvider] Risposta dal server per l'update: StatusCode=${response['statusCode']}, Body=${response['body']}");

      if (response['statusCode'] == 200) {
        final index = _dipendenti.indexWhere((d) => d.idUnico == id);
        if (index != -1) {
            _dipendenti[index].nomeDipendente = data['nome_dipendente'] ?? _dipendenti[index].nomeDipendente;
            _dipendenti[index].ruolo = data['ruolo'] ?? _dipendenti[index].ruolo;
            _dipendenti[index].pin = data['pin'] ?? _dipendenti[index].pin;
            _dipendenti[index].email = data['email'] ?? _dipendenti[index].email;
            _dipendenti[index].telefono = data['telefono'] ?? _dipendenti[index].telefono;
            _dipendenti[index].colore = data['colore'] ?? _dipendenti[index].colore;
            
            _dipendenti[index].campoExtra01 = data['campo_extra_01'] ?? _dipendenti[index].campoExtra01;
            _dipendenti[index].campoExtra02 = data['campo_extra_02'] ?? _dipendenti[index].campoExtra02;
            _dipendenti[index].campoExtra03 = data['campo_extra_03'] ?? _dipendenti[index].campoExtra03;
            _dipendenti[index].campoExtra04 = data['campo_extra_04'] ?? _dipendenti[index].campoExtra04;
            _dipendenti[index].campoExtra05 = data['campo_extra_05'] ?? _dipendenti[index].campoExtra05;
            _dipendenti[index].campoExtra06 = data['campo_extra_06'] ?? _dipendenti[index].campoExtra06;
            _dipendenti[index].campoExtra07 = data['campo_extra_07'] ?? _dipendenti[index].campoExtra07;
            _dipendenti[index].campoExtra08 = data['campo_extra_08'] ?? _dipendenti[index].campoExtra08;
            _dipendenti[index].campoExtra09 = data['campo_extra_09'] ?? _dipendenti[index].campoExtra09;
            _dipendenti[index].campoExtra10 = data['campo_extra_10'] ?? _dipendenti[index].campoExtra10;
            
            notifyListeners();
        }
        return true;
      } else {
        // Se il server risponde con un errore, lo salviamo per poterlo leggere
        _error = "Errore ${response['statusCode']}: ${response['body']?['detail'] ?? 'Nessun dettaglio'}";
        print("[DipendentiProvider] Aggiornamento fallito. Errore: $_error");
        return false;
      }
    } catch (e) {
      _error = e.toString();
      print("[DipendentiProvider] Eccezione catturata durante l'aggiornamento: $_error");
      notifyListeners();
      return false;
    }
  }
  // --- FINE MODIFICA ---

  Future<bool> deleteDipendente(String id) async {
    try {
      final response = await _service.deleteDipendente(id);
      if (response['statusCode'] == 200) {
        _dipendenti.removeWhere((d) => d.idUnico == id);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}