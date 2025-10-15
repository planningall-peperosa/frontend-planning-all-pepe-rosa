// lib/providers/preventivo_builder_provider.dart
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

// --- MODIFICA: IMPORT PER FIREBASE ---
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cliente.dart';
import '../models/piatto.dart';
import '../models/servizio_selezionato.dart';
import '../models/menu_template.dart';
import '../models/preventivo_completo.dart';
import '../models/fornitore_servizio.dart';
import '../services/preventivi_service.dart';
import '../models/preventivo_summary.dart';

// --- LOG helper ---
void _logBuilder(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[BUILDER] $msg');
  }
}

class PreventivoBuilderProvider with ChangeNotifier {
  final PreventiviService _preventiviService = PreventiviService();

  Map<String, List<Piatto>> _menu = {};
  Cliente? _cliente;
  String? _nomeEvento;
  DateTime? _dataEvento;
  int? _numeroOspiti;

  // --- MODIFICA: RINOMINATO PER CHIAREZZA ---
  int _numeroBambini = 0;
  double _prezzoMenuBambino = 0.0;
  String? _menuBambini; // Ex _noteMenuBambini

  final Map<String, ServizioSelezionato> _serviziExtra = {};

  String? _preventivoId;
  String? _status;
  bool _confermaPending = false;
  DateTime? _dataCreazione;
  String? _nomeMenuTemplate;

  // --- MODIFICA: RINOMINATO PER CHIAREZZA ---
  double _prezzoMenuAdulto = 0.0; // Ex _prezzoMenuPersona
  bool _scontoAbilitato = false;
  double _sconto = 0.0;
  String? _noteSconto;
  double? _acconto;

  String? _tipoPasto;

  bool _isSaving = false;
  String? _erroreSalvataggio;

  bool _dirty = false;
  bool _hydrating = false;
  String? _baselineJson;

  // =======================================================================
  // --- NUOVI METODI DI TRADUZIONE PER FIRESTORE (AGGIORNATI) ---
  // =======================================================================


  void caricaDaFirestoreMap(Map<String, dynamic> data, {required String id}) {
    _hydrating = true;
    
    reset(); 
    _hydrating = true; 

    // --- MODIFICA CHIAVE: Memorizziamo subito l'ID del preventivo ---
    _preventivoId = id;

    // Il resto della funzione rimane identico...
    _nomeEvento = data['nome_evento'];
    _numeroOspiti = data['numero_ospiti'];
    _status = data['status'];
    _nomeMenuTemplate = data['nome_menu_template'];
    _sconto = (data['sconto'] as num?)?.toDouble() ?? 0.0;
    _scontoAbilitato = _sconto > 0;
    _noteSconto = data['note_sconto'];
    _acconto = (data['acconto'] as num?)?.toDouble();
    _tipoPasto = data['tipo_pasto'];

    _prezzoMenuAdulto = (data['prezzo_menu_adulto'] as num?)?.toDouble() ?? 0.0;
    _numeroBambini = data['numero_bambini'] ?? 0;
    _prezzoMenuBambino = (data['prezzo_menu_bambino'] as num?)?.toDouble() ?? 0.0;
    _menuBambini = data['menu_bambini'];

    _dataEvento = (data['data_evento'] as Timestamp?)?.toDate();
    _dataCreazione = (data['data_creazione'] as Timestamp?)?.toDate();
    
    if (data['cliente'] != null && data['cliente'] is Map) {
      _cliente = Cliente.fromJson(data['cliente']);
    }

    if (data['menu'] is Map) {
      final menuDaDb = data['menu'] as Map<String, dynamic>;
      _menu.clear();
      menuDaDb.forEach((genere, piattiList) {
        if (piattiList is List) {
          _menu[genere] = piattiList.map((piattoData) => Piatto.fromJson(piattoData)).toList();
        }
      });
    }

    if (data['servizi'] is List) {
      final serviziDaDb = data['servizi'] as List;
      _serviziExtra.clear();
      for (var servizioData in serviziDaDb) {
        if (servizioData is Map<String, dynamic>) {
          final servizio = ServizioSelezionato.fromJson(servizioData);
          _serviziExtra[servizio.ruolo] = servizio;
        }
      }
    }
    
    _hydrating = false;
    notifyListeners();
  }


  Map<String, dynamic> toFirestoreMap() {
    return {
      'cliente_id': _cliente?.idCliente,
      'cliente': _cliente?.toJson(),
      'nome_cliente': _cliente?.ragioneSociale,

      'nome_evento': _nomeEvento,
      'data_evento': _dataEvento != null ? Timestamp.fromDate(_dataEvento!) : null,
      'numero_ospiti': _numeroOspiti,
      'tipo_pasto': _tipoPasto,

      // --- MODIFICA: SCRITTURA CAMPI RINOMINATI ---
      'menu': _menuPerBackend(),
      'prezzo_menu_adulto': _prezzoMenuAdulto, // Ex prezzo_menu_persona
      'nome_menu_template': _nomeMenuTemplate,
      'numero_bambini': _numeroBambini,
      'prezzo_menu_bambino': _prezzoMenuBambino,
      'menu_bambini': _menuBambini, // Ex note_menu_bambini

      'servizi': _serviziExtra.values.map((s) => s.toJson()).toList(),

      'sconto': _sconto,
      'note_sconto': _noteSconto,
      'acconto': _acconto,

      'status': _status ?? 'Bozza',
      'data_creazione': _dataCreazione ?? Timestamp.now(),
      'data_modifica': Timestamp.now(),
      'deleted_at': null,
    };
  }


  // =======================================================================
  // --- IL TUO CODICE ORIGINALE (CON VARIABILI RINOMINATE) ---
  // =======================================================================

  bool get hasLocalChanges {
    final sw = Stopwatch()..start();
    final snap = _safeSnapshotJson();
    sw.stop();
    _logBuilder('hasLocalChanges snapshot ${sw.elapsedMilliseconds}ms');

    if (snap == null) return _dirty;
    if (_preventivoId == null) return true;
    if (_baselineJson == null) return true;
    return snap != _baselineJson;
  }

  void markDirty() {
    if (_hydrating) return;
    _dirty = true;
  }

  void clearLocalChanges() {
    _dirty = false;
    final snapSw = Stopwatch()..start();
    final snap = _safeSnapshotJson();
    snapSw.stop();
    _logBuilder('clearLocalChanges snapshot ${snapSw.elapsedMilliseconds}ms');
    if (snap != null) {
      _baselineJson = snap;
    }
    notifyListeners();
  }

  Map<String, List<Piatto>> get menu => _menu;
  Cliente? get cliente => _cliente;
  String? get nomeEvento => _nomeEvento;
  DateTime? get dataEvento => _dataEvento;
  int? get numeroOspiti => _numeroOspiti;

  // --- MODIFICA: GETTER RINOMINATI ---
  int get numeroBambini => _numeroBambini;
  double get prezzoMenuBambino => _prezzoMenuBambino;
  String? get menuBambini => _menuBambini; // Ex noteMenuBambini

  Map<String, ServizioSelezionato> get serviziExtra => _serviziExtra;
  String? get preventivoId => _preventivoId;
  String? get status => _status;
  bool get confermaPending => _confermaPending;

  bool get isSaving => _isSaving;
  String? get erroreSalvataggio => _erroreSalvataggio;

  String? get nomeMenuTemplate => _nomeMenuTemplate;
  // --- MODIFICA: GETTER RINOMINATO ---
  double get prezzoMenuAdulto => _prezzoMenuAdulto; // Ex prezzoMenuPersona

  bool get scontoAbilitato => _scontoAbilitato;
  double get sconto => _sconto;
  String? get noteSconto => _noteSconto;

  double? get acconto => _acconto;
  String? get tipoPasto => _tipoPasto;

  int get _numeroAdulti {
    final ospiti = _numeroOspiti ?? 0;
    final b = _numeroBambini;
    final bb = b < 0 ? 0 : (b > ospiti ? ospiti : b);
    return ospiti - bb;
  }

  // --- MODIFICA: CALCOLO CON CAMPO RINOMINATO ---
  double get costoMenuAdulti => _prezzoMenuAdulto * _numeroAdulti;
  double get costoMenuBambini => _prezzoMenuBambino * _numeroBambini;
  double get costoMenu => costoMenuAdulti + costoMenuBambini;

  double get costoServizi =>
      _serviziExtra.values.fold<double>(0.0, (sum, s) => sum + (s.prezzo ?? 0.0));

  double get subtotale => costoMenu + costoServizi;
  double get totaleFinale => subtotale - _sconto;

  bool _menuEquals(Map<String, List<Piatto>> a, Map<String, List<Piatto>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      final la = a[k] ?? const [];
      final lb = b[k] ?? const [];
      if (la.length != lb.length) return false;
      for (var i = 0; i < la.length; i++) {
        final pa = la[i];
        final pb = lb[i];
        if (pa.idUnico != pb.idUnico ||
            pa.nome != pb.nome ||
            pa.tipologia != pb.tipologia ||
            pa.genere != pb.genere) {
          return false;
        }
      }
    }
    return true;
  }

  bool _serviziEquals(Map<String, ServizioSelezionato> a,
      Map<String, ServizioSelezionato> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      final sa = a[k]!;
      final sb = b[k]!;
      if (sa.ruolo != sb.ruolo) return false;
      if ((sa.prezzo ?? 0) != (sb.prezzo ?? 0)) return false;
      if ((sa.note ?? '') != (sb.note ?? '')) return false;
      final fa = sa.fornitore;
      final fb = sb.fornitore;
      if ((fa?.ragioneSociale ?? '') != (fb?.ragioneSociale ?? '')) return false;
    }
    return true;
  }

  dynamic _canonicalize(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((e) => e.toString()).toList()..sort();
      final out = <String, dynamic>{};
      for (final k in keys) {
        out[k] = _canonicalize(v[k]);
      }
      return out;
    } else if (v is List) {
      return v.map(_canonicalize).toList();
    } else if (v is num) {
      final d = v.toDouble();
      return (d == d.roundToDouble()) ? d.toInt() : d;
    } else {
      return v;
    }
  }

  String? _safeSnapshotJson() {
    final wrap = creaPayloadSalvataggio();
    if (wrap == null) return null;
    final payload = wrap['payload'];
    final canon = _canonicalize(payload);
    return jsonEncode(canon);
  }

  void setMenu(Map<String, List<Piatto>> nuovoMenu) {
    if (_menuEquals(_menu, nuovoMenu)) return;
    _menu = nuovoMenu;
    markDirty();
    notifyListeners();
  }

  void setConfermaPending(bool v) {
    if (v == _confermaPending) return;
    _confermaPending = v;
    markDirty();
    notifyListeners();
  }

  void setConfermatoLocal(bool value) {
    if (value == _confermaPending) return;
    _confermaPending = value;
    markDirty();
    notifyListeners();
  }

  void setCliente(Cliente nuovoCliente) {
    if (_cliente != null &&
        _cliente!.idCliente == nuovoCliente.idCliente &&
        _cliente!.ragioneSociale == nuovoCliente.ragioneSociale &&
        (_cliente!.telefono01 ?? '') == (nuovoCliente.telefono01 ?? '') &&
        (_cliente!.mail ?? '') == (nuovoCliente.mail ?? '')) {
      return;
    }
    _cliente = nuovoCliente;
    markDirty();
    notifyListeners();
  }

  void setNomeEvento(String nome) {
    final nv = nome;
    if (_nomeEvento == nv) return;
    _nomeEvento = nv;
    markDirty();
    notifyListeners();
  }

  void setDataEvento(DateTime data) {
    final normalized = DateTime(data.year, data.month, data.day);
    if (_dataEvento == normalized) return;
    _dataEvento = normalized;
    markDirty();
    notifyListeners();
  }

  void setNumeroOspiti(int ospiti) {
    if (_numeroOspiti == ospiti) return;
    _numeroOspiti = ospiti;
    markDirty();
    notifyListeners();
  }

  void setNumeroBambini(int v) {
    final nv = v < 0 ? 0 : v;
    if (_numeroBambini == nv) return;
    _numeroBambini = nv;
    markDirty();
    notifyListeners();
  }

  void setPrezzoMenuBambino(double v) {
    final double nv = v < 0 ? 0.0 : v;
    if (_prezzoMenuBambino == nv) return;
    _prezzoMenuBambino = nv;
    markDirty();
    notifyListeners();
  }

  // --- MODIFICA: SETTER RINOMINATO ---
  void setMenuBambini(String? v) { // Ex setNoteMenuBambini
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_menuBambini == nv) return;
    _menuBambini = nv;
    markDirty();
    notifyListeners();
  }


  void setPreventivoId(String newId) {
    if (_preventivoId == newId) return;
    _preventivoId = newId;
    // Non serve un notifyListeners() perché questo aggiorna solo lo stato interno
    // per azioni successive come il salvataggio o la generazione del PDF.
  }

  void setPrezzoDaTemplate(MenuTemplate template) {
    if (_prezzoMenuAdulto == template.prezzo &&
        _nomeMenuTemplate == template.nomeMenu) {
      return;
    }
    _prezzoMenuAdulto = template.prezzo;
    _nomeMenuTemplate = template.nomeMenu;
    markDirty();
    notifyListeners();
  }

  // --- MODIFICA: RINOMINATO PER CHIAREZZA ---
  void setPrezzoMenuAdulto(double prezzo) { // Ex setPrezzoManuale
    if (_prezzoMenuAdulto == prezzo && _nomeMenuTemplate == null) return;
    _prezzoMenuAdulto = prezzo;
    _nomeMenuTemplate = null;
    markDirty();
    notifyListeners();
  }

  void resetPrezzoMenu() {
    if (_prezzoMenuAdulto == 0.0 && _nomeMenuTemplate == null) return;
    _prezzoMenuAdulto = 0.0;
    _nomeMenuTemplate = null;
    markDirty();
    notifyListeners();
  }

  void toggleServizio(String ruolo, bool isSelected, {double prezzoDefault = 0.0}) {
    final before = Map<String, ServizioSelezionato>.from(_serviziExtra);
    if (isSelected) {
      if (!_serviziExtra.containsKey(ruolo)) {
        _serviziExtra[ruolo] = ServizioSelezionato(
          ruolo: ruolo,
          prezzo: prezzoDefault,
        );
      }
    } else {
      _serviziExtra.remove(ruolo);
    }
    if (_serviziEquals(before, _serviziExtra)) return;
    markDirty();
    notifyListeners();
  }

  void aggiornaPrezzoServizio(String ruolo, double nuovoPrezzo) {
    final s = _serviziExtra[ruolo];
    if (s == null) return;
    if ((s.prezzo ?? 0.0) == nuovoPrezzo) return;
    s.prezzo = nuovoPrezzo;
    markDirty();
    notifyListeners();
  }

  void setServizioNota(String ruolo, String nota) {
    final s = _serviziExtra[ruolo];
    if (s == null) return;
    final nn = nota.trim();
    if ((s.note ?? '') == nn) return;
    s.note = nn;
    markDirty();
    notifyListeners();
  }

  void setServizioFornitore(String ruolo, FornitoreServizio fornitore) {
    final s = _serviziExtra[ruolo];
    if (s == null) return;
    final sameForn =
        (s.fornitore?.ragioneSociale ?? '') == (fornitore.ragioneSociale ?? '');
    final newPrezzo = fornitore.prezzo ?? s.prezzo ?? 0.0;
    final samePrezzo = (s.prezzo ?? 0.0) == newPrezzo;
    if (sameForn && samePrezzo) return;
    s.fornitore = fornitore;
    s.prezzo = newPrezzo;
    markDirty();
    notifyListeners();
  }

  void toggleSconto(bool abilitato) {
    if (_scontoAbilitato == abilitato) return;
    _scontoAbilitato = abilitato;
    if (!abilitato) {
      _sconto = 0.0;
      _noteSconto = null;
    }
    markDirty();
    notifyListeners();
  }

  void setSconto(double valore, {String? note}) {
    final nn = note;
    if (_sconto == valore && _noteSconto == nn) return;
    _sconto = valore;
    _noteSconto = nn;
    markDirty();
    notifyListeners();
  }

  void setAcconto(double valore) {
    if ((_acconto ?? 0.0) == valore) return;
    _acconto = valore;
    markDirty();
    notifyListeners();
  }

  void setTipoPasto(String? v) {
    if (_tipoPasto == v) return;
    _tipoPasto = v;
    markDirty();
    notifyListeners();
  }

  void aggiungiPiattiDaCatalogo({
    required String genere,
    required List<Piatto> piatti,
  }) {
    _menu.putIfAbsent(genere, () => <Piatto>[]);
    final before = Map<String, List<Piatto>>.from(_menu);
    _menu[genere] = List<Piatto>.from(_menu[genere]!)..addAll(piatti);
    if (_menuEquals(before, _menu)) return;
    markDirty();
    notifyListeners();
  }

  void aggiungiPiattoCustom({
    required String genere,
    required String nome,
  }) {
    _menu.putIfAbsent(genere, () => <Piatto>[]);
    final before = Map<String, List<Piatto>>.from(_menu);
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final updated = List<Piatto>.from(_menu[genere]!);
    updated.add(
      Piatto(
        idUnico: id,
        nome: nome.trim(),
        tipologia: 'fuori_menu',
        genere: genere,
      ),
    );
    _menu[genere] = updated;
    if (_menuEquals(before, _menu)) return;
    markDirty();
    notifyListeners();
  }

  void caricaPreventivoEsistente(PreventivoCompleto p) {
    final total = Stopwatch()..start();
    _hydrating = true;

    _menu = p.menu;
    _cliente = p.cliente;
    _nomeEvento = p.nomeEvento;
    _dataEvento = p.dataEvento;
    _numeroOspiti = p.numeroOspiti;

    _serviziExtra
      ..clear()
      ..addEntries(p.serviziExtra.map((s) => MapEntry(s.ruolo, s)));

    _preventivoId = p.preventivoId;
    _status = p.status;
    _confermaPending = false;
    _dataCreazione = p.dataCreazione;
    _prezzoMenuAdulto = p.prezzoMenuPersona; // Mantenuto per compatibilità con questo vecchio metodo
    _nomeMenuTemplate = p.nomeMenuTemplate;
    _sconto = p.sconto;
    _noteSconto = p.noteSconto;
    _scontoAbilitato = p.sconto > 0;
    _acconto = p.acconto;
    _tipoPasto = p.tipoPasto;

    _numeroBambini = p.numeroBambini ?? 0;
    _prezzoMenuBambino = p.prezzoMenuBambino ?? 0.0;
    _menuBambini = p.noteMenuBambini; // Mantenuto per compatibilità

    _dirty = false;
    _hydrating = false;

    final snapSw = Stopwatch()..start();
    _baselineJson = _safeSnapshotJson();
    snapSw.stop();
    _logBuilder('caricaPreventivoEsistente snapshot ${snapSw.elapsedMilliseconds}ms');

    notifyListeners();
    total.stop();
    _logBuilder('caricaPreventivoEsistente TOTAL ${total.elapsedMilliseconds}ms (id=${_preventivoId ?? "-"})');
  }

  void prepareForDuplicate() {
    _preventivoId = null;
    _status = null;
    _confermaPending = false;
    markDirty();
    notifyListeners();
  }

  Map<String, List<Map<String, dynamic>>> _menuPerBackend() {
    final out = <String, List<Map<String, dynamic>>>{};
    final sortedKeys = _menu.keys.toList()..sort();
    for (final genere in sortedKeys) {
      final piatti = _menu[genere] ?? const <Piatto>[];
      final items = <Map<String, dynamic>>[];
      for (final p in piatti) {
        items.add({
          'id_unico': p.idUnico.isNotEmpty ? p.idUnico : null,
          'nome': p.nome,
          'custom': p.tipologia == 'fuori_menu' || p.idUnico.startsWith('custom_'),
        });
      }
      if (items.isNotEmpty) out[genere] = items;
    }
    return out;
  }

  Map<String, dynamic>? creaPayloadSalvataggio() {
    final t = Stopwatch()..start();
    if (_cliente == null || _dataEvento == null || _nomeEvento == null || _numeroOspiti == null) {
      _erroreSalvataggio = "Dati essenziali mancanti (cliente, data, nome evento, ospiti).";
      notifyListeners();
      t.stop();
      _logBuilder('creaPayloadSalvataggio FAIL ${t.elapsedMilliseconds}ms (campi mancanti)');
      return null;
    }

    final payload = <String, dynamic>{
      'cliente': _cliente!.toJson(),
      'menu': _menuPerBackend(),
      'data_evento': _dataEvento!.toIso8601String().substring(0, 10),
      'nome_evento': _nomeEvento!,
      'numero_ospiti': _numeroOspiti!,
      'numero_bambini': _numeroBambini,
      'prezzo_menu_bambino': _prezzoMenuBambino,
      'note_menu_bambini': _menuBambini, // Vecchio nome per compatibilità payload
      'servizi_extra': _serviziExtra.values.map((s) => s.toJson()).toList(),
      'prezzo_menu_persona': _prezzoMenuAdulto, // Vecchio nome per compatibilità payload
      'nome_menu_template': _nomeMenuTemplate,
      'sconto': _sconto,
      'note_sconto': _noteSconto,
      'acconto': _acconto,
      'tipo_pasto': _tipoPasto,
    };

    t.stop();
    _logBuilder('creaPayloadSalvataggio OK ${t.elapsedMilliseconds}ms');
    return {
      "preventivo_id": _preventivoId,
      "payload": payload,
    };
  }

  Future<void> _applicaConfermaSeRichiesta(String idSalvato) async {
    if (confermaPending && ((_status ?? '').toUpperCase() != 'CONFERMATO')) {
      final t = Stopwatch()..start();
      await _preventiviService.confermaPreventivo(idSalvato);
      t.stop();
      _logBuilder('_applicaConfermaSeRichiesta ${t.elapsedMilliseconds}ms');
      _status = 'CONFERMATO';
      _confermaPending = false;
    }
  }

  Future<PreventivoSummary?> salvaPreventivo({
    required dynamic preventiviProvider,
  }) async {
    final total = Stopwatch()..start();
    _isSaving = true;
    _erroreSalvataggio = null;
    notifyListeners();

    try {
      final tHas = Stopwatch()..start();
      final changed = hasLocalChanges;
      tHas.stop();
      _logBuilder('hasLocalChanges=${changed} in ${tHas.elapsedMilliseconds}ms');

      if (!changed) {
        final tSnap = Stopwatch()..start();
        final payload = creaPayloadSalvataggio();
        tSnap.stop();
        _logBuilder('payload (no HTTP) ${tSnap.elapsedMilliseconds}ms');

        return PreventivoSummary.fromJson({
          ...(payload?['payload'] ?? <String, dynamic>{}),
          'preventivo_id': _preventivoId,
          'status': _status ?? 'Bozza',
          'data_creazione': (_dataCreazione ?? DateTime.now()).toIso8601String(),
        });
      }

      final tBuild = Stopwatch()..start();
      final payloadCompleto = creaPayloadSalvataggio();
      tBuild.stop();
      _logBuilder('creaPayloadSalvataggio ${tBuild.elapsedMilliseconds}ms');
      if (payloadCompleto == null) {
        _isSaving = false;
        notifyListeners();
        _logBuilder('salvaPreventivo ABORT (payload null)');
        return null;
      }

      final payload = payloadCompleto['payload'] as Map<String, dynamic>;

      Map<String, dynamic> response;
      String idPreventivoSalvato;

      if (_preventivoId == null) {
        final tHttp = Stopwatch()..start();
        response = await _preventiviService.creaNuovoPreventivo(payload);
        tHttp.stop();
        _logBuilder('HTTP creaNuovoPreventivo ${tHttp.elapsedMilliseconds}ms');
        idPreventivoSalvato = response['preventivo_id'] as String;
        _preventivoId = idPreventivoSalvato;
      } else {
        final tHttp = Stopwatch()..start();
        response = await _preventiviService.aggiornaPreventivo(_preventivoId!, payload);
        tHttp.stop();
        _logBuilder('HTTP aggiornaPreventivo ${tHttp.elapsedMilliseconds}ms');
        idPreventivoSalvato = _preventivoId!;
      }

      final tConf = Stopwatch()..start();
      await _applicaConfermaSeRichiesta(idPreventivoSalvato);
      tConf.stop();
      _logBuilder('applicaConferma ${tConf.elapsedMilliseconds}ms');

      final tSumm = Stopwatch()..start();
      final summaryAggiornato = PreventivoSummary.fromJson({
        ...payload,
        'preventivo_id': idPreventivoSalvato,
        'status': _status ?? 'Bozza',
        'data_creazione': (_dataCreazione ?? DateTime.now()).toIso8601String(),
      });
      tSumm.stop();
      _logBuilder('build PreventivoSummary ${tSumm.elapsedMilliseconds}ms');

      try {
        final tCache = Stopwatch()..start();
        preventiviProvider.aggiungiOAggiornaPreventivoInCache(summaryAggiornato);
        tCache.stop();
        _logBuilder('aggiungiOAggiornaPreventivoInCache ${tCache.elapsedMilliseconds}ms');
      } catch (e) {
        _logBuilder('cache update error: $e');
      }

      _dirty = false;
      final tBase = Stopwatch()..start();
      _baselineJson = _safeSnapshotJson();
      tBase.stop();
      _logBuilder('update baseline ${tBase.elapsedMilliseconds}ms');

      total.stop();
      _logBuilder('salvaPreventivo TOTAL ${total.elapsedMilliseconds}ms');
      return summaryAggiornato;
    } catch (e) {
      _erroreSalvataggio = e.toString();
      _logBuilder('salvaPreventivo ERROR: $e');
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void reset() {
    final total = Stopwatch()..start();
    _hydrating = true;

    _confermaPending = false;
    _menu = {};
    _cliente = null;
    _nomeEvento = null;
    _dataEvento = null;
    _numeroOspiti = null;

    _numeroBambini = 0;
    _prezzoMenuBambino = 0.0;
    _menuBambini = null;

    _serviziExtra.clear();
    _preventivoId = null;
    _status = null;
    _dataCreazione = null;
    _erroreSalvataggio = null;
    _prezzoMenuAdulto = 0.0;
    _scontoAbilitato = false;
    _sconto = 0.0;
    _noteSconto = null;
    _nomeMenuTemplate = null;
    _acconto = null;
    _tipoPasto = null;

    _dirty = false;
    _baselineJson = null;
    _hydrating = false;

    if (kDebugMode) {
      // ignore: avoid_print
      print("PreventivoBuilderProvider resettato.");
    }
    notifyListeners();
    total.stop();
    _logBuilder('reset TOTAL ${total.elapsedMilliseconds}ms');
  }

  Future<PreventivoSummary?> duplicaPreventivo({
    required dynamic preventiviProvider, // dynamic: niente dipendenza circolare
  }) async {
    final suffix = '(Copia ${DateFormat('dd/MM HH:mm').format(DateTime.now())})';
    final base = nomeEvento ?? '';
    setNomeEvento(base.isEmpty ? 'Copia $suffix' : '$base $suffix');

    _preventivoId = null;
    _status = null;
    _confermaPending = false;

    notifyListeners();

    final summary = await salvaPreventivo(preventiviProvider: preventiviProvider);

    try {
      await preventiviProvider.hardRefresh(ignoreEditingOpen: true);
    } catch (_) {}

    _dirty = false;
    _baselineJson = _safeSnapshotJson();
    notifyListeners();
    return summary;
  }
}