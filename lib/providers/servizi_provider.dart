// lib/providers/servizi_provider.dart
import 'package:flutter/foundation.dart';
import '../services/servizi_service.dart';
import '../models/fornitore_servizio.dart';

class ServiziProvider extends ChangeNotifier {
  final ServiziService _service = ServiziService();

  List<String> _ruoliDisponibili = [];
  Map<String, List<FornitoreServizio>> _fornitoriPerRuolo = {};
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<String> get ruoliDisponibili => _ruoliDisponibili;
  List<FornitoreServizio> fornitoriPerRuolo(String ruolo) => _fornitoriPerRuolo[ruolo] ?? [];

  Future<void> caricaTuttiIRuoli() async {
    if (_ruoliDisponibili.isNotEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _ruoliDisponibili = await _service.getTuttiIRuoli();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<FornitoreServizio>> caricaFornitoriPerRuolo(String ruolo) async {
    if (_fornitoriPerRuolo.containsKey(ruolo)) {
      return _fornitoriPerRuolo[ruolo]!;
    }
    // Non usiamo isLoading qui per non bloccare l'intera UI,
    // il caricamento verrà mostrato nel dialogo.
    try {
      final fornitori = await _service.getFornitoriPerRuolo(ruolo);
      _fornitoriPerRuolo[ruolo] = fornitori;
      notifyListeners();
      return fornitori;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }
}