// lib/providers/clienti_provider.dart
import 'package:flutter/foundation.dart';
import '../models/cliente.dart';
import '../services/clienti_service.dart';

class ClientiProvider extends ChangeNotifier {
  final ClientiService _clientiService = ClientiService();

  bool _isLoading = false;
  String? _error;
  List<Cliente> _contattiTrovati = [];
  
  Map<String, int> _conteggiReali = {};
  String? _verifyingCountForClientId;
  List<String> _ruoliServizi = [];
  bool _isLoadingRuoli = false;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Cliente> get contattiTrovati => _contattiTrovati;
  Map<String, int> get conteggiReali => _conteggiReali;
  String? get verifyingCountForClientId => _verifyingCountForClientId;
  List<String> get ruoliServizi => _ruoliServizi;
  bool get isLoadingRuoli => _isLoadingRuoli;

  Future<void> cercaContatti(String query) async {
    if (query.length < 3) {
      _contattiTrovati = [];
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final jsonDataList = await _clientiService.cercaContatti(query);
      _contattiTrovati = jsonDataList.map((json) => Cliente.fromJson(json)).toList();
      if (_contattiTrovati.isEmpty) _error = "Nessun contatto trovato.";
    } catch (e) {
      _error = e.toString();
      _contattiTrovati = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Cliente?> cercaClientePerTelefono(String telefono) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final jsonDataList = await _clientiService.cercaContatti(telefono);
      final clienti = jsonDataList.map((json) => Cliente.fromJson(json)).toList();
      final clienteEsatto = clienti.firstWhere(
        (c) => c.telefono01 == telefono && c.tipo == 'cliente',
        orElse: () => Cliente.empty(),
      );
      return clienteEsatto.idCliente.isEmpty ? null : clienteEsatto;
    } catch (e) {
      _error = 'Errore imprevisto nella ricerca: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Cliente?> creaNuovoContatto(Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final nuovoContattoJson = await _clientiService.creaNuovoContatto(data);
      clearSearch();
      return Cliente.fromJson(nuovoContattoJson);
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NUOVO METODO PER AGGIORNARE ---
  Future<Cliente?> aggiornaContatto(String idContatto, Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final contattoAggiornatoJson = await _clientiService.aggiornaContatto(idContatto, data);
      // Aggiorna la lista locale se il contatto è presente
      final index = _contattiTrovati.indexWhere((c) => c.idCliente == idContatto);
      if (index != -1) {
        _contattiTrovati[index] = Cliente.fromJson(contattoAggiornatoJson);
      }
      return Cliente.fromJson(contattoAggiornatoJson);
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NUOVO METODO PER ELIMINARE ---
  Future<bool> eliminaContatto(String idContatto, String tipo) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _clientiService.eliminaContatto(idContatto, tipo);
      // Rimuovi il contatto dalla lista in memoria
      _contattiTrovati.removeWhere((c) => c.idCliente == idContatto);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Metodi di utilità
  void clearSearch() {
    _contattiTrovati = [];
    _error = null;
    _conteggiReali = {};
    _verifyingCountForClientId = null;
    notifyListeners();
  }

  void clearState() {
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> caricaRuoliServizi() async {
      if (_ruoliServizi.isNotEmpty) return;
      _isLoadingRuoli = true;
      notifyListeners();
      try {
        _ruoliServizi = await _clientiService.getRuoliServizi();
      } catch (e) {
        print("ERRORE caricamento ruoli: $e");
      } finally {
        _isLoadingRuoli = false;
        notifyListeners();
      }
    }
}