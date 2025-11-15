// lib/providers/preventivo_builder_provider.dart

import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/piatto.dart';
import '../models/servizio_selezionato.dart';
import '../models/menu_template.dart';
import '../models/preventivo_completo.dart';
import '../models/fornitore_servizio.dart';
import '../services/preventivi_service.dart';
import '../models/preventivo_summary.dart';
import '../models/pacchetto_evento.dart';

// --- LOG helper ---
void _logBuilder(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[BUILDER] $msg');
  }
}

// ====== LOGGING STRUTTURATO (aggiuntivo) ======
final _prettyBuilder = const JsonEncoder.withIndent('  ');
void dlogBuilder(String tag, Object? data) {
  if (!kDebugMode) return;
  if (data is Map || data is List) {
    // ignore: avoid_print
    print('[BUILDER][$tag] ${_prettyBuilder.convert(data)}');
  } else {
    // ignore: avoid_print
    print('[BUILDER][$tag] $data');
  }
}

// Hash leggero (solo per confronto in log)
String jhashBuilder(Object? data) {
  try {
    final s = jsonEncode(data);
    return s.hashCode.toUnsigned(20).toRadixString(16);
  } catch (_) {
    return '0';
  }
}
// =============================================

class PreventivoBuilderProvider with ChangeNotifier {
  final PreventiviService _preventiviService = PreventiviService();

  Map<String, List<Piatto>> _menu = {};
  Cliente? _cliente;
  String? _nomeEvento;
  DateTime? _dataEvento;
  int? _numeroOspiti;

  // --- NOTE INTEGRATIVE (debug + persistenza) ---
  String _noteIntegrative = '';

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
  
  // ===================== 🟢 NUOVI CAMPI ORARI 🟢 =====================
  TimeOfDay? _orarioInizio;
  TimeOfDay? _orarioFine;
  // ===================================================================

  bool _isSaving = false;
  String? _erroreSalvataggio;

  bool _dirty = false;
  bool _hydrating = false;
  String? _baselineJson;

  // ===================== CAMPI ESISTENTI (MENU A PORTATE) =====================
  bool _aperitivoBenvenuto = false;
  bool _buffetDolci = false;
  String? _buffetDolciNote;
  
  // 🔑 CAMPI FIRMA AGGIUNTI NEL PROVIDER
  String? _firmaUrl; 
  String? _firmaUrlCliente2; 
  
  // ===================== 🟢 NUOVI CAMPI (PACCHETTO FISSO) 🟢 =====================
  bool _isPacchettoFisso = false;
  String? _nomePacchettoFisso;
  String? _descrizionePacchettoFisso;
  String? _descrizionePacchettoFisso2; // 🚨 AGGIUNTO
  String? _descrizionePacchettoFisso3; // 🚨 AGGIUNTO
  double _prezzoPacchettoFisso = 0.0;
  String? _propostaGastronomicaPacchetto; // 🌟 NUOVO CAMPO
  // ==============================================================================

  // =======================================================================
  // --- NUOVI METODI DI TRADUZIONE PER FIRESTORE (AGGIORNATI) ---
  // =======================================================================

  void caricaDaFirestoreMap(Map<String, dynamic> data, {String? id}) {
    print('[DEBUG][caricaDaFirestoreMap] IN: keys=' + data.keys.toString());
    print('[DEBUG][caricaDaFirestoreMap] IN: note_integrative=' + (data['note_integrative']?.toString() ?? 'null'));
    _hydrating = true;
    print('--- TRACCIA: INIZIO caricaDaFirestoreMap ---'); 

    // 🔍 Log IN ingresso
    dlogBuilder('PROV:carica.in', {
      'id': id,
      'hash': jhashBuilder(data),
      'fields': data.keys.toList(),
      'descr1': data['descrizione_1'],
      'descr2': data['descrizione_2'],
      'descr3': data['descrizione_3'],
      'extra.len': (data['servizi_extra'] as List?)?.length ?? 0,
    });

    reset();
    _hydrating = true;

    // Solo se l'ID viene fornito, lo impostiamo.
    _preventivoId = id;

    _nomeEvento = data['nome_evento'];
    _numeroOspiti = (data['numero_ospiti'] as num?)?.toInt();
    // 🔑 CORREZIONE 1: Standardizza lo stato a minuscolo durante il caricamento
    _status = (data['status'] as String? ?? 'Bozza').trim().toLowerCase();
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
    
    // 🟢 LETTURA ORARI
    final int? hI = data['orario_inizio_h'] as int?;
    final int? mI = data['orario_inizio_m'] as int?;
    _orarioInizio = (hI != null && mI != null) ? TimeOfDay(hour: hI, minute: mI) : null;

    final int? hF = data['orario_fine_h'] as int?;
    final int? mF = data['orario_fine_m'] as int?;
    _orarioFine = (hF != null && mF != null) ? TimeOfDay(hour: hF, minute: mF) : null;
    // ==================

    // 🔑 CORREZIONE CHIAVE: Leggi gli URL delle firme
    _firmaUrl = data['firma_url'] as String?;
    _firmaUrlCliente2 = data['firma_url_cliente_2'] as String?; // <-- URL Seconda Firma
    
    // ===================== LETTURA CAMPI ESISTENTI (MENU A PORTATE) =====================
    _aperitivoBenvenuto = (data['aperitivo_benvenuto'] as bool?) ?? false;
    _buffetDolci = (data['buffet_dolci'] as bool?) ?? false;
    _buffetDolciNote = data['buffet_dolci_note'];
    
    // ===================== 🟢 LETTURA NUOVI CAMPI (PACCHETTO FISSO) 🟢 =====================
    _isPacchettoFisso = (data['is_pacchetto_fisso'] as bool?) ?? false;
    _nomePacchettoFisso = data['nome_pacchetto_fisso'];
    
    // 1. TENTA LA LETTURA DAI NUOVI CAMPI SEPARATI (descrizione_1, 2, 3)
    _descrizionePacchettoFisso = data['descrizione_1']; 
    _descrizionePacchettoFisso2 = data['descrizione_2']; 
    _descrizionePacchettoFisso3 = data['descrizione_3'];
    
    _prezzoPacchettoFisso = (data['prezzo_pacchetto_fisso'] as num?)?.toDouble() ?? 0.0;
    _propostaGastronomicaPacchetto = data['proposta_gastronomica_pacchetto']; // 🌟 NUOVO CAMPO
    
    // 2. 🚨 FALLBACK DI COMPATIBILITÀ (Per i preventivi vecchi o mal salvati)
    if (_isPacchettoFisso && 
        (_descrizionePacchettoFisso == null || _descrizionePacchettoFisso!.isEmpty) && 
        data['descrizione_pacchetto_fisso'] != null) {
      
      final fullDescr = (data['descrizione_pacchetto_fisso'] as String).trim();
      final descLines = fullDescr.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      _descrizionePacchettoFisso = descLines.length > 0 ? descLines[0] : null; 
      _descrizionePacchettoFisso2 = descLines.length > 1 ? descLines[1] : null; 
      _descrizionePacchettoFisso3 = descLines.length > 2 ? descLines[2] : null;
    } 
    // =======================================================================================

    if (data['cliente'] != null && data['cliente'] is Map) {
      _cliente = Cliente.fromJson(data['cliente']);
    }

    // --- Ricostruzione dei Piatti da Dati Parziali ---
    if (data['menu'] is Map) {
      final menuDaDb = data['menu'] as Map<String, dynamic>;
      _menu.clear();
      menuDaDb.forEach((genere, piattiList) {
        if (piattiList is List) {
          _menu[genere] = piattiList.map((piattoData) {
            final Map<String, dynamic> json =
                piattoData is Map ? piattoData as Map<String, dynamic> : {};

            return Piatto(
              idUnico: json['id_unico'] ??
                  'custom_${DateTime.now().millisecondsSinceEpoch}',
              genere: genere,
              nome: json['nome'] ?? json['piatto'] ?? 'Piatto Sconosciuto',
              tipologia: (json['custom'] == true ||
                      json['tipologia'] == 'fuori_menu')
                  ? 'fuori_menu'
                  : (json['tipologia'] ?? 'standard'),
              descrizione: json['descrizione'],
              stagione: json['stagione'],
              linkFoto: json['link_foto'],
            );
          }).toList();
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

    // 🟢 NOTE INTEGRATIVE — LETTURA ROBUSTA
    _noteIntegrative = ((data['note_integrative'] ?? data['noteIntegrative']) as String?)
            ?.trim() ?? '';
    print('[DEBUG][caricaDaFirestoreMap] SET _noteIntegrative=' + _noteIntegrative);

    // 🔍 Log OUT sintesi
    dlogBuilder('PROV:carica.out', {
      'id': _preventivoId,
      'descrizione_1': _descrizionePacchettoFisso,
      'descrizione_2': _descrizionePacchettoFisso2,
      'descrizione_3': _descrizionePacchettoFisso3,
      'servizi.len': _serviziExtra.length,
      'is_pacchetto_fisso': _isPacchettoFisso,
      'prezzo_pacchetto_fisso': _prezzoPacchettoFisso,
      'data_evento': _dataEvento?.toIso8601String(),
      'note_integrative': _noteIntegrative,
    });

    _hydrating = false;
    print('[DEBUG][caricaDaFirestoreMap] OUT: _noteIntegrative=' + _noteIntegrative);
    notifyListeners();
    print('--- TRACCIA: FINE caricaDaFirestoreMap ---');
  }

  // --- FUNZIONE PER DUPLICAZIONE (VERSIONE CORRETTA) ---

  /// Carica un preventivo esistente e lo prepara per essere salvato come nuova copia.
  Future<void> preparaPerDuplicazione(String preventivoIdOriginale) async {
    final doc = await FirebaseFirestore.instance
        .collection('preventivi')
        .doc(preventivoIdOriginale)
        .get();

    if (!doc.exists) {
      throw Exception(
          "Impossibile trovare il preventivo originale per la duplicazione.");
    }

    final data = doc.data() as Map<String, dynamic>;

    _hydrating = true; // Inizio caricamento

    // 1. Carica tutti i dati del vecchio preventivo
    caricaDaFirestoreMap(data, id: null); // Carica i dati ma non l'ID

    // 2. Modifiche per DUPLICAZIONE: azzera stato, ID e aggiungi "Copia" al nome
    _preventivoId = null; // ESSENZIALE: Forziamo la creazione di un nuovo documento
    _status = 'Bozza';
    _dataCreazione = Timestamp.now().toDate();

    // Aggiungiamo un suffisso al nome dell'evento
    final baseNome = data['nome_evento'] ?? 'Nuovo Evento';
    _nomeEvento =
        '$baseNome (COPIA ${DateFormat('dd/MM').format(DateTime.now())})';

    // Azzeriamo i campi relativi alla conferma/firma
    _confermaPending = false;
    _firmaUrl = null; // 🔑 AZZERAMENTO FIRME
    _firmaUrlCliente2 = null; // 🔑 AZZERAMENTO FIRME
    
    // Rimuoviamo eventuali acconti
    _acconto = null;

    _dirty = true;
    _hydrating = false;

    notifyListeners();
  }

  Map<String, dynamic> toFirestoreMap() {
    // calcolo pacchetto welcome/dolci (solo per menu a portate)
    final bool isPacchetto = _isPacchettoFisso == true;
    final double pacchettoCosto = isPacchetto ? 0.0 : costoPacchettoWelcomeDolci;
    final String pacchettoLabel = isPacchetto ? '' : labelPacchettoWelcomeDolci;

    print('[DEBUG][toFirestoreMap] _noteIntegrative=' + _noteIntegrative);
    return {
      // Cliente completo
      'cliente_id': _cliente?.idCliente,
      'cliente': _cliente?.toJson(),
      'nome_cliente': _cliente?.ragioneSociale,

      'nome_evento': _nomeEvento,
      'data_evento': _dataEvento != null ? Timestamp.fromDate(_dataEvento!) : null,
      'numero_ospiti': _numeroOspiti,
      'tipo_pasto': _tipoPasto,

      // Orari
      'orario_inizio_h': _orarioInizio?.hour,
      'orario_inizio_m': _orarioInizio?.minute,
      'orario_fine_h': _orarioFine?.hour,
      'orario_fine_m': _orarioFine?.minute,

      // Menu a portate (se non pacchetto fisso)
      'menu': isPacchetto ? null : _menuPerBackend(),
      'prezzo_menu_adulto': _prezzoMenuAdulto,
      'nome_menu_template': _nomeMenuTemplate,
      'numero_bambini': _numeroBambini,
      'prezzo_menu_bambino': _prezzoMenuBambino,
      'menu_bambini': _menuBambini,

      // Servizi extra — scrivo sia "servizi" (legacy) che "servizi_extra" (nuovo)
      'servizi': _serviziExtra.values.map((s) => s.toJson()).toList(),
      'servizi_extra': _serviziExtra.values.map((s) => s.toJson()).toList(),

      'sconto': _sconto,
      'note_sconto': _noteSconto,
      'note_integrative': _noteIntegrative, // 🟢 SALVO SEMPRE
      'acconto': _acconto,

      'status': (_status ?? 'Bozza').trim(),
      'data_creazione': _dataCreazione ?? Timestamp.now(),
      'data_modifica': Timestamp.now(),
      'deleted_at': null,

      // Firme
      'firma_url': _firmaUrl,
      'firma_url_cliente_2': _firmaUrlCliente2,

      // Flag/sezioni menu a portate
      'aperitivo_benvenuto': _aperitivoBenvenuto,
      'buffet_dolci': _buffetDolci,
      'buffet_dolci_note': _buffetDolciNote,

      // Pacchetto fisso (nuove chiavi corte + compatibilità con le vecchie)
      'is_pacchetto_fisso': _isPacchettoFisso,
      'nome_pacchetto_fisso': _nomePacchettoFisso,
      // ✅ chiavi “corte” usate dal PDF
      'descrizione_1': _descrizionePacchettoFisso,
      'descrizione_2': _descrizionePacchettoFisso2,
      'descrizione_3': _descrizionePacchettoFisso3,
      'proposta_gastronomica_pacchetto': _propostaGastronomicaPacchetto,
      'prezzo_pacchetto_fisso': _prezzoPacchettoFisso,
      // 🔁 compat: scrivo anche le “lunghe”
      'descrizione_pacchetto_fisso': _descrizionePacchettoFisso,
      'descrizione_pacchetto_fisso_2': _descrizionePacchettoFisso2,
      'descrizione_pacchetto_fisso_3': _descrizionePacchettoFisso3,

      // Pacchetto welcome+dolci calcolato (usato dal PDF lato DB)
      'pacchetto_label': pacchettoLabel,
      'pacchetto_costo': pacchettoCosto,
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
  
  // 🟢 NUOVI GETTER ORARI
  TimeOfDay? get orarioInizio => _orarioInizio;
  TimeOfDay? get orarioFine => _orarioFine;
  // ============================================

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
  
  // 🔑 GETTER FIRME AGGIUNTO
  String? get firmaUrl => _firmaUrl;
  String? get firmaUrlCliente2 => _firmaUrlCliente2; 
  
  // ===================== 🟢 NUOVI GETTER (PACCHETTO FISSO) 🟢 =====================
  bool get isPacchettoFisso => _isPacchettoFisso;
  String? get nomePacchettoFisso => _nomePacchettoFisso;
  String? get descrizionePacchettoFisso => _descrizionePacchettoFisso;
  String? get descrizionePacchettoFisso2 => _descrizionePacchettoFisso2; // 🚨 AGGIUNTO
  String? get descrizionePacchettoFisso3 => _descrizionePacchettoFisso3; // 🚨 AGGIUNTO
  double get prezzoPacchettoFisso => _prezzoPacchettoFisso;
  String? get propostaGastronomicaPacchetto => _propostaGastronomicaPacchetto; // 🌟 NUOVO GETTER
  
  // 🟢 GETTER PER IL RIEPILOGO SERVIZI/CLIENTE (evita l'errore di duplicazione)
  double get prezzoPacchettoSelezionato => _prezzoPacchettoFisso; 
  // ==============================================================================

  bool get scontoAbilitato => _scontoAbilitato;
  double get sconto => _sconto;
  String? get noteSconto => _noteSconto;

  double? get acconto => _acconto;
  String? get tipoPasto => _tipoPasto;

  // ===================== GETTER AGGIUNTI (MENU A PORTATE) =====================
  bool get aperitivoBenvenuto => _aperitivoBenvenuto;
  bool get buffetDolci => _buffetDolci;
  String? get buffetDolciNote => _buffetDolciNote;
  String get noteIntegrative => _noteIntegrative;
  // ========================================================================

  int get _numeroAdulti {
    final ospiti = _numeroOspiti ?? 0;
    final b = _numeroBambini;
    final bb = b < 0 ? 0 : (b > ospiti ? ospiti : b);
    return ospiti - bb;
  }


  double get costoMenuAdulti => _prezzoMenuAdulto * _numeroAdulti;
  double get costoMenuBambini => _prezzoMenuBambino * _numeroBambini;
  double get costoMenu => costoMenuAdulti + costoMenuBambini;

  double get costoServizi =>
      _serviziExtra.values.fold<double>(0.0, (sum, s) => sum + (s.prezzo ?? 0.0));

  double get costoPacchettoWelcomeDolci {
    final n = _numeroOspiti ?? 0;
    if (_aperitivoBenvenuto && _buffetDolci) return n * 10.0; // pacchetto
    if (_aperitivoBenvenuto && !_buffetDolci) return n * 8.0; // solo aperitivo
    if (!_aperitivoBenvenuto && _buffetDolci) return n * 5.0; // solo dolci
    return 0.0;
  }

  String get labelPacchettoWelcomeDolci {
    if (_aperitivoBenvenuto && _buffetDolci) {
      return 'pacchetto aperitivo di benvenuto+buffet di dolci';
    }
    if (_aperitivoBenvenuto && !_buffetDolci) {
      return 'aperitivo di benvenuto';
    }
    if (!_aperitivoBenvenuto && _buffetDolci) {
      return 'buffet di dolci';
    }
    return '';
  }


  // 🔴 MODIFICA CHIAVE: Implementazione della logica condizionale nel subtotale
  @override
  double get subtotale {
    final double costoBase;
    
    if (_isPacchettoFisso) {
      // 🟢 CASO 1: Pacchetto a Prezzo Fisso (ignora i costi Menu/Welcome/Bambini)
      costoBase = _prezzoPacchettoFisso;
    } else {
      // 🟢 CASO 2: Menu a Portate (MANTIENE LA LOGICA ESISTENTE)
      costoBase = costoMenu + costoPacchettoWelcomeDolci;
    }

    // I servizi extra sono sempre aggiunti
    return costoBase + costoServizi;
  }

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
    final sw = Stopwatch()..start();
    final wrap = creaPayloadSalvataggio();
    sw.stop();
    _logBuilder('hasLocalChanges snapshot ${sw.elapsedMilliseconds}ms');

    if (wrap == null) return _baselineJson;
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
  
  // 🔑 Modifica: Aggiorna cliente
  void setCliente(Cliente nuovoCliente) {
    final bool isSame = (_cliente != null &&
        _cliente!.idCliente == nuovoCliente.idCliente &&
        _cliente!.ragioneSociale == nuovoCliente.ragioneSociale &&
        (_cliente!.telefono01 ?? '') == (nuovoCliente.telefono01 ?? '') &&
        (_cliente!.mail ?? '') == (nuovoCliente.mail ?? '') &&
        (_cliente!.codiceFiscale ?? '') == (nuovoCliente.codiceFiscale ?? ''));
        
    if (isSame) return;
    
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
  void setMenuBambini(String? v) {
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_menuBambini == nv) return;
    _menuBambini = nv;
    markDirty();
    notifyListeners();
  }

  void setPreventivoId(String newId) {
    if (_preventivoId == newId) return;
    _preventivoId = newId;
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

  // --- MODIFICA: SETTER RINOMINATO ---
  void setPrezzoMenuAdulto(double prezzo) {
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
  
  // 🔑 SETTER URL FIRMA 1
  void setFirmaUrl(String? url) {
    final cleanedUrl = (url ?? '').trim().isEmpty ? null : url!.trim();
    if (_firmaUrl == cleanedUrl) return;
    _firmaUrl = cleanedUrl;
    markDirty();
    notifyListeners();
  }

  // 🔑 SETTER URL FIRMA 2
  void setFirmaUrlCliente2(String? url) {
    final cleanedUrl = (url ?? '').trim().isEmpty ? null : url!.trim();
    if (_firmaUrlCliente2 == cleanedUrl) return;
    _firmaUrlCliente2 = cleanedUrl;
    markDirty();
    notifyListeners();
  }

  void toggleServizio(String ruolo, bool isSelected,
      {double prezzoDefault = 0.0}) {
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

  void setStato(String nuovoStato) {
    final cleanedStato = nuovoStato.trim().toLowerCase();
    if (_status == cleanedStato) return;
    _status = cleanedStato;
    markDirty();
    notifyListeners();
  }

  void setTipoPasto(String? v) {
    if (_tipoPasto == v) return;
    _tipoPasto = v;
    markDirty();
    notifyListeners();
  }
  
  // 🟢 SETTER ORARI
  void setOrarioInizio(TimeOfDay? time) {
    if (_orarioInizio == time) return;
    _orarioInizio = time;
    markDirty();
    notifyListeners();
  }

  void setOrarioFine(TimeOfDay? time) {
    if (_orarioFine == time) return;
    _orarioFine = time;
    markDirty();
    notifyListeners();
  }
  // =================

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
    print('[DEBUG][caricaPreventivoEsistente] IN: p.noteIntegrative=' + (p.noteIntegrative?.toString() ?? 'null'));
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
    _prezzoMenuAdulto =
        p.prezzoMenuPersona; // compatibilità
    _nomeMenuTemplate = p.nomeMenuTemplate;
    _sconto = p.sconto;
    _noteSconto = p.noteSconto;
    _scontoAbilitato = p.sconto > 0;
    _acconto = p.acconto;
    _tipoPasto = p.tipoPasto;

    _numeroBambini = p.numeroBambini ?? 0;
    _prezzoMenuBambino = p.prezzoMenuBambino ?? 0.0;
    _menuBambini = p.noteMenuBambini;

    // 🟢 CARICO NOTE INTEGRATIVE DAL MODEL
    _noteIntegrative = p.noteIntegrative ?? '';
    print('[DEBUG][caricaPreventivoEsistente] SET _noteIntegrative=' + _noteIntegrative);

    _dirty = false;
    _hydrating = false;

    final snapSw = Stopwatch()..start();
    _baselineJson = _safeSnapshotJson();
    snapSw.stop();
    _logBuilder(
        'caricaPreventivoEsistente snapshot ${snapSw.elapsedMilliseconds}ms');

    print('[DEBUG][caricaPreventivoEsistente] OUT: _noteIntegrative=' + _noteIntegrative);
    notifyListeners();
    total.stop();
    _logBuilder(
        'caricaPreventivoEsistente TOTAL ${total.elapsedMilliseconds}ms (id=${_preventivoId ?? "-"})');
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
          'custom': p.tipologia == 'fuori_menu' ||
              p.idUnico.startsWith('custom_'),
        });
      }
      if (items.isNotEmpty) out[genere] = items;
    }
    return out;
  }

  Map<String, dynamic>? creaPayloadSalvataggio() {
    final t = Stopwatch()..start();

    // 🟢 NUOVA LOGICA DI VALIDAZIONE
    bool isMissingEssentialData = 
        _cliente == null ||
        _dataEvento == null ||
        _nomeEvento == null;
    
    if (!_isPacchettoFisso && _numeroOspiti == null) {
      isMissingEssentialData = true;
    }
    
    if (isMissingEssentialData) {
      _erroreSalvataggio =
          "Dati essenziali mancanti (cliente, data, nome evento, ospiti/tipo pasto).";
      notifyListeners();
      t.stop();
      _logBuilder(
          'creaPayloadSalvataggio FAIL ${t.elapsedMilliseconds}ms (campi mancanti)');
      return null;
    }

    final payload = <String, dynamic>{
      'cliente': _cliente!.toJson(),
      'menu': _isPacchettoFisso ? null : _menuPerBackend(),
      'data_evento': _dataEvento!.toIso8601String().substring(0, 10),
      'nome_evento': _nomeEvento!,
      'numero_ospiti': _numeroOspiti ?? 0,
      'numero_bambini': _numeroBambini ?? 0,
      'orario_inizio_h': _orarioInizio?.hour,
      'orario_inizio_m': _orarioInizio?.minute,
      'orario_fine_h': _orarioFine?.hour,
      'orario_fine_m': _orarioFine?.minute,
      'prezzo_menu_bambino': _prezzoMenuBambino,
      'note_menu_bambini': _menuBambini, 
      'prezzo_menu_persona': _prezzoMenuAdulto, 
      'nome_menu_template': _nomeMenuTemplate,
      'aperitivo_benvenuto': _aperitivoBenvenuto,
      'buffet_dolci': _buffetDolci,
      'buffet_dolci_note': _buffetDolciNote,
      'servizi_extra': _serviziExtra.values.map((s) => s.toJson()).toList(),
      'sconto': _sconto,
      'note_sconto': _noteSconto,
      'note_integrative': _noteIntegrative, // 🟢 SCRIVO NEL PAYLOAD
      'acconto': _acconto,
      'tipo_pasto': _tipoPasto,
      'status': (_status ?? 'Bozza').trim(),
      'firma_url': _firmaUrl,
      'firma_url_cliente_2': _firmaUrlCliente2, 
      
      // ===================== 🟢 SCRITTURA NUOVI CAMPI (PACCHETTO FISSO) 🟢 =====================
      'is_pacchetto_fisso': _isPacchettoFisso,
      'nome_pacchetto_fisso': _nomePacchettoFisso,
      
      // 🚨 CHIAVI CORTE DB (quelle usate dal PDF)
      'descrizione_1': _descrizionePacchettoFisso, 
      'descrizione_2': _descrizionePacchettoFisso2, 
      'descrizione_3': _descrizionePacchettoFisso3, 
      
      'proposta_gastronomica_pacchetto': _propostaGastronomicaPacchetto, 
      'prezzo_pacchetto_fisso': _prezzoPacchettoFisso,
      
      // Chiavi legacy (si mantengono valorizzate uguali, nessuna logica cambiata)
      'descrizione_pacchetto_fisso': _descrizionePacchettoFisso,
      'descrizione_pacchetto_fisso_2': _descrizionePacchettoFisso2,
      'descrizione_pacchetto_fisso_3': _descrizionePacchettoFisso3,
    };

    print('[DEBUG][creaPayloadSalvataggio] payload.note_integrative=' + (payload['note_integrative']?.toString() ?? 'null'));

    // 🔍 Log payload (prima del return)
    dlogBuilder('PROV:save.snapshot', {
      'hash': jhashBuilder(payload),
      'descr1': payload['descrizione_1'],
      'descr2': payload['descrizione_2'],
      'descr3': payload['descrizione_3'],
      'extra.len': (payload['servizi_extra'] as List).length,
      'is_pacchetto_fisso': payload['is_pacchetto_fisso'],
    });

    t.stop();
    _logBuilder('creaPayloadSalvataggio OK ${t.elapsedMilliseconds}ms');
    return {
      "preventivo_id": _preventivoId,
      "payload": payload,
    };
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
          'data_creazione':
              (_dataCreazione ?? DateTime.now()).toIso8601String(),
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

      // 🔍 Log PRE-salvataggio DB
      dlogBuilder('SAVE:payload', {
        'id': _preventivoId,
        'hash': jhashBuilder(payload),
        'fields': payload.keys.toList(),
        'descr1': payload['descrizione_1'],
        'descr2': payload['descrizione_2'],
        'descr3': payload['descrizione_3'],
        'extra.len': (payload['servizi_extra'] as List).length,
        'note_integrative': payload['note_integrative'],
      });

      String idPreventivoSalvato;

      // LOGICA DI SALVATAGGIO SU FIRESTORE
      if (_preventivoId == null) {
        // CREAZIONE
        final newDoc =
            await FirebaseFirestore.instance.collection('preventivi').add(payload);
        idPreventivoSalvato = newDoc.id;
        _preventivoId = idPreventivoSalvato;
      } else {
        // AGGIORNAMENTO
        await FirebaseFirestore.instance
            .collection('preventivi')
            .doc(_preventivoId!)
            .update(payload);
        idPreventivoSalvato = _preventivoId!;
      }

      _logBuilder('Firestore Save/Update completato per ID: $idPreventivoSalvato');
      print('[DEBUG][salvaPreventivo] _noteIntegrative=' + _noteIntegrative);

      final tSumm = Stopwatch()..start();
      final summaryAggiornato = PreventivoSummary.fromJson({
        ...payload,
        'preventivo_id': idPreventivoSalvato,
        'status': _status ?? 'Bozza',
        'data_creazione':
            (_dataCreazione ?? DateTime.now()).toIso8601String(),
      });
      tSumm.stop();
      _logBuilder('build PreventivoSummary ${tSumm.elapsedMilliseconds}ms');

      try {
        final tCache = Stopwatch()..start();
        // preventiviProvider.aggiungiOAggiornaPreventivoInCache(summaryAggiornato);
        tCache.stop();
        _logBuilder('aggiungiOAggiornaPreventivoInCache SKIPPED: Cache update logic not verified.');
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
    
    // 🔑 RESET FIRME
    _firmaUrl = null;
    _firmaUrlCliente2 = null;

    // 🟢 RESET ORARI
    _orarioInizio = null;
    _orarioFine = null;
    // =================

    // ===================== RESET CAMPI ESISTENTI (MENU A PORTATE) =====================
    _aperitivoBenvenuto = false;
    _buffetDolci = false;
    _buffetDolciNote = null;
    
    // ===================== 🟢 RESET NUOVI CAMPI (PACCHETTO FISSO) 🟢 =====================
    _isPacchettoFisso = false;
    _nomePacchettoFisso = null;
    _descrizionePacchettoFisso = null;
    _descrizionePacchettoFisso2 = null; 
    _descrizionePacchettoFisso3 = null; 
    _prezzoPacchettoFisso = 0.0;
    _propostaGastronomicaPacchetto = null; 
    // =======================================================================================

    // 🟢 RESET NOTE INTEGRATIVE
    _noteIntegrative = '';

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

  // ===================== NUOVI SETTER PUBBLICI (MENU A PORTATE) =====================
  void setAperitivoBenvenuto(bool v) {
    if (_aperitivoBenvenuto == v) return;
    _aperitivoBenvenuto = v;
    markDirty();
    notifyListeners();
  }

  void setBuffetDolci(bool v) {
    if (_buffetDolci == v) return;
    _buffetDolci = v;
    markDirty();
    notifyListeners();
  }

  void setBuffetDolciNote(String? v) {
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_buffetDolciNote == nv) return;
    _buffetDolciNote = nv;
    markDirty();
    notifyListeners();
  }
  
  // ===================== 🟢 NUOVI SETTER (PACCHETTO FISSO) 🟢 =====================
  
  void setDescrizionePacchettoFisso(String? v) {
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_descrizionePacchettoFisso == nv) return;
    _descrizionePacchettoFisso = nv;
    markDirty();
    notifyListeners();
  }
  
  void setDescrizionePacchettoFisso2(String? v) {
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_descrizionePacchettoFisso2 == nv) return;
    _descrizionePacchettoFisso2 = nv;
    markDirty();
    notifyListeners();
  }
  
  void setDescrizionePacchettoFisso3(String? v) {
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_descrizionePacchettoFisso3 == nv) return;
    _descrizionePacchettoFisso3 = nv;
    markDirty();
    notifyListeners();
  }
  
  void setPropostaGastronomicaPacchetto(String? v) {
    final nv = (v ?? '').trim().isEmpty ? null : v!.trim();
    if (_propostaGastronomicaPacchetto == nv) return;
    _propostaGastronomicaPacchetto = nv;
    markDirty();
    notifyListeners();
  }
  
  void setPacchettoFissoMode(bool v) {
    if (_isPacchettoFisso == v) return;
    _isPacchettoFisso = v;
    
    if (v) {
      _menu = {};
      _prezzoMenuAdulto = 0.0;
      _nomeMenuTemplate = null;
      _aperitivoBenvenuto = false;
      _buffetDolci = false;
      _buffetDolciNote = null;
      _menuBambini = null;
      _prezzoMenuBambino = 0.0;
      _numeroBambini = 0;
    } else {
      _nomePacchettoFisso = null;
      _descrizionePacchettoFisso = null;
      _descrizionePacchettoFisso2 = null; 
      _descrizionePacchettoFisso3 = null; 
      _prezzoPacchettoFisso = 0.0;
      _propostaGastronomicaPacchetto = null;
    }
    
    markDirty();
    notifyListeners();
  }
  
  void setPacchettoFisso(PacchettoEvento? pacchetto) {  
    if (pacchetto == null) {
      _isPacchettoFisso = false;
      _nomePacchettoFisso = null;
      _descrizionePacchettoFisso = null;
      _descrizionePacchettoFisso2 = null; 
      _descrizionePacchettoFisso3 = null; 
      _prezzoPacchettoFisso = 0.0;
      _propostaGastronomicaPacchetto = null;
    } else {
      _isPacchettoFisso = true;
      _nomePacchettoFisso = pacchetto.nome;
      _prezzoPacchettoFisso = pacchetto.prezzoFisso;
      _propostaGastronomicaPacchetto = pacchetto.propostaGastronomica;
      
      final fullDesc = pacchetto.descrizione ?? '';
      final descLines = fullDesc.split('\n')
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList();

      _descrizionePacchettoFisso = descLines.length > 0 ? descLines[0] : null; 
      _descrizionePacchettoFisso2 = descLines.length > 1 ? descLines[1] : null; 
      _descrizionePacchettoFisso3 = descLines.length > 2 ? descLines[2] : null; 
      
      if (_isPacchettoFisso) {
          _menu = {};
          _prezzoMenuAdulto = 0.0;
          _nomeMenuTemplate = null;
          _aperitivoBenvenuto = false;
          _buffetDolci = false;
          _buffetDolciNote = null;
          _menuBambini = null;
          _prezzoMenuBambino = 0.0;
          _numeroBambini = 0;
      }
    }
    
    markDirty();
    notifyListeners();
  } 

  void resetPacchettoFisso() {
    _isPacchettoFisso = false;
    _nomePacchettoFisso = null;
    _descrizionePacchettoFisso = null;
    _descrizionePacchettoFisso2 = null; 
    _descrizionePacchettoFisso3 = null; 
    _prezzoPacchettoFisso = 0.0;
    _propostaGastronomicaPacchetto = null; 
    markDirty();
    notifyListeners();
  }
  // =======================================================================================

  void setNoteIntegrative(String? v) {
    final nv = (v == null || v.trim().isEmpty) ? '' : v.trim();
    if (_noteIntegrative == nv) return;
    _noteIntegrative = nv;
    _dirty = true;
    notifyListeners();
  }
}
