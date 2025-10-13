import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/menu_template.dart';
import '../services/menu_templates_service.dart';

class MenuTemplatesProvider with ChangeNotifier {
  final MenuTemplatesService _service = MenuTemplatesService();

  List<MenuTemplate> _templates = [];
  bool _loading = false;
  String? _error;

  List<MenuTemplate> get templates => List.unmodifiable(_templates);
  bool get isLoading => _loading;
  String? get error => _error;

  // ----------------- HELPERS -----------------

  // Porta le chiavi al formato atteso dal backend (router FastAPI)
  Map<String, dynamic> _fixPayload(Map<String, dynamic> src) {
    final out = Map<String, dynamic>.from(src);

    // normalizza nome menu
    if (out.containsKey('nome_menu') && !out.containsKey('MENU')) {
      out['MENU'] = out['nome_menu'];
    }

    // preferisci composizione_default_json
    if (out.containsKey('composizione_default') &&
        !out.containsKey('composizione_default_json')) {
      out['composizione_default_json'] = out['composizione_default'];
    }

    // niente chiavi legacy
    out.remove('nome_menu');
    out.remove('composizione_default');

    // assicurati che la composizione sia Map (non String)
    final comp = out['composizione_default_json'];
    if (comp is String) {
      try {
        out['composizione_default_json'] = jsonDecode(comp);
      } catch (_) {
        out['composizione_default_json'] = {};
      }
    }
    return out;
  }

  Map<String, List<String>> _normalizeComposizione(dynamic comp) {
    if (comp is String) {
      try { comp = jsonDecode(comp); } catch (_) { comp = {}; }
    }
    final Map<String, List<String>> res = {};
    if (comp is Map) {
      comp.forEach((k, v) {
        if (v is List) {
          res[k.toString()] = v.map((e) => e.toString()).toList();
        }
      });
    }
    return res;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString()
      .replaceAll('€', '')
      .replaceAll('EUR', '')
      .replaceAll(',', '.')
      .trim();
    return double.tryParse(s) ?? 0.0;
  }

  // ----------------- CRUD -----------------

  Future<void> fetch() async {
    _loading = true; _error = null; notifyListeners();
    try {
      final data = await _service.getMenuTemplates(); // <-- NOME NUOVO
      _templates = data
          .map<MenuTemplate>(
            (j) => MenuTemplate.fromJson(Map<String, dynamic>.from(j)),
          )
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<bool> add(Map<String, dynamic> payload) async {
    _loading = true; _error = null; notifyListeners();
    try {
      final res = await _service.addMenuTemplate(_fixPayload(payload)); // <-- NOME NUOVO
      if (res['statusCode'] == 201) {
        await fetch();
        return true;
      }
      _error = res['body']?['detail']?.toString() ?? 'Errore ${res['statusCode']}';
      return false;
    } catch (e) {
      _error = e.toString(); return false;
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<bool> update(String idMenu, Map<String, dynamic> payload) async {
    _error = null; notifyListeners();
    try {
      final fixed = _fixPayload(payload);
      final res = await _service.updateMenuTemplate(idMenu, fixed); // <-- NOME NUOVO
      if (res['statusCode'] == 200) {
        final i = _templates.indexWhere((t) => t.idMenu == idMenu);
        if (i != -1) {
          _templates[i] = _templates[i].copyWith(
            nomeMenu: (fixed['MENU'] ?? _templates[i].nomeMenu).toString(),
            prezzo: _toDouble(fixed['prezzo'] ?? _templates[i].prezzo),
            tipologia: (fixed['tipologia'] ?? _templates[i].tipologia).toString(),
            composizioneDefault: _normalizeComposizione(
              fixed['composizione_default_json'] ?? _templates[i].composizioneDefault,
            ),
          );
          notifyListeners();
        }
        return true;
      }
      _error = res['body']?['detail']?.toString() ?? 'Errore ${res['statusCode']}';
      return false;
    } catch (e) {
      _error = e.toString(); notifyListeners(); return false;
    }
  }

  Future<bool> remove(String idMenu) async {
    _error = null; notifyListeners();
    try {
      final res = await _service.deleteMenuTemplate(idMenu); // <-- NOME NUOVO
      if (res['statusCode'] == 200) {
        _templates.removeWhere((t) => t.idMenu == idMenu);
        notifyListeners();
        return true;
      }
      _error = res['body']?['detail']?.toString() ?? 'Errore ${res['statusCode']}';
      return false;
    } catch (e) {
      _error = e.toString(); notifyListeners(); return false;
    }
  }
}
