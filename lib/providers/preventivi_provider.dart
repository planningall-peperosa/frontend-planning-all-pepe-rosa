// lib/providers/preventivi_provider.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preventivo_summary.dart';
import '../models/preventivo_completo.dart';
import '../services/preventivi_service.dart';

/// Converte una lista JSON (List<dynamic>/Map) in List<PreventivoSummary>
List<PreventivoSummary> _parseSummaries(List<dynamic> raw) {
  return raw
      .whereType<Map<String, dynamic>>()
      .map((m) => PreventivoSummary.fromJson(m))
      .toList();
}

/// (helper opzionale – non più usato dentro la classe; lasciato per completezza)
List<PreventivoSummary> _dedupByIdTop(List<PreventivoSummary> items) {
  final byId = <String, PreventivoSummary>{};
  for (final p in items) {
    byId[p.preventivoId] = p; // se duplicato, tieni l'ultimo
  }
  return byId.values.toList();
}

// --- LOG helper ---
void _logCache(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[CACHE] $msg');
  }
}

class PreventiviProvider extends ChangeNotifier {
  final PreventiviService _service = PreventiviService();

  // Stato per la cache completa
  List<PreventivoSummary> _cacheIndiciCompleta = [];
  bool _isLoadingCache = false; // loader "iniziale/bloccante"
  String? _errorCache;

  // --- PASSAGGIO A VERSIONI PER-ANNO ---
  // Esempio: { "2025": 137, "2026": 42 }
  Map<String, int> _versioniCacheLocali = {};

  // Stato per operazioni di scrittura
  bool _isSaving = false;
  String? _errorSaving;
  String? _successMessage;

  // Stato per la ricerca
  bool _isSearching = false;
  String? _errorSearching;
  List<PreventivoSummary> _risultatiRicerca = [];

  // --- NUOVO: refresh in background (barra sotto AppBar) ---
  bool _isRefreshing = false;

  // --- NUOVO: controllo traffico sync/versione ---
  bool _isEditingOpen = false; // se true, mettiamo in pausa i refresh soft
  DateTime? _lastVersionCheckAt; // ultimo GET /sync/versione completato
  DateTime? _lastLocalSaveAt; // ultimo salvataggio locale che ha aggiornato la cache
  final Duration _versionCheckCooldown = const Duration(seconds: 5); // throttle
  final Duration _postSaveGrace = const Duration(seconds: 3); // grace dopo un nostro save

  // Getters
  bool get isSaving => _isSaving;
  String? get errorSaving => _errorSaving;
  String? get successMessage => _successMessage;
  bool get isSearching => _isSearching;
  String? get errorSearching => _errorSearching;
  List<PreventivoSummary> get risultatiRicerca => _risultatiRicerca;
  int get risultatiCount => _risultatiRicerca.length;
  bool get isLoadingCache => _isLoadingCache;
  String? get errorCache => _errorCache;
  bool get isCacheCaricata => _cacheIndiciCompleta.isNotEmpty;

  // Esposto alla UI per mostrare la barra sottile di refresh
  bool get isRefreshing => _isRefreshing;

  // --- NUOVO: API per segnare che lo screen di editing è aperto/chiuso ---
  bool get isEditingOpen => _isEditingOpen;
  void setEditingOpen(bool value) {
    if (_isEditingOpen == value) return;
    _isEditingOpen = value;
    notifyListeners();
  }

  // --- METODI HELPER PER GESTIRE LA CACHE SU DISCO ---
  Future<File> get _cacheFile async {
    final t = Stopwatch()..start();
    final directory = await getApplicationDocumentsDirectory();
    t.stop();
    _logCache('getApplicationDocumentsDirectory ${t.elapsedMilliseconds}ms');
    return File('${directory.path}/preventivi_cache.json');
  }

  static const _prefsKeyVersioni = 'preventivi_cache_versioni';

  Future<void> _salvaCacheSuDisco(
    List<PreventivoSummary> data,
    Map<String, int> versioniPerAnno,
  ) async {
    final total = Stopwatch()..start();
    final file = await _cacheFile;

    final tMap = Stopwatch()..start();
    final jsonList = data.map((p) => p.toJson()).toList();
    tMap.stop();
    _logCache('_salvaCacheSuDisco build list ${tMap.elapsedMilliseconds}ms (items=${jsonList.length})');

    final tWrite = Stopwatch()..start();
    await file.writeAsString(jsonEncode(jsonList));
    tWrite.stop();
    _logCache('_salvaCacheSuDisco write file ${tWrite.elapsedMilliseconds}ms (path=${file.path})');

    final tPrefs = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyVersioni, jsonEncode(versioniPerAnno));
    tPrefs.stop();
    _logCache('_salvaCacheSuDisco write prefs ${tPrefs.elapsedMilliseconds}ms (versioni=${versioniPerAnno.length})');

    _versioniCacheLocali = Map<String, int>.from(versioniPerAnno);
    total.stop();
    _logCache('_salvaCacheSuDisco TOTAL ${total.elapsedMilliseconds}ms');
  }

  Future<List<PreventivoSummary>> _leggiCacheDaDisco() async {
    final total = Stopwatch()..start();
    try {
      final file = await _cacheFile;
      if (await file.exists()) {
        final tRead = Stopwatch()..start();
        final content = await file.readAsString();
        tRead.stop();
        _logCache('_leggiCacheDaDisco read ${tRead.elapsedMilliseconds}ms (bytes=${content.length})');

        final tDec = Stopwatch()..start();
        final List<dynamic> jsonList = jsonDecode(content);
        tDec.stop();
        _logCache('_leggiCacheDaDisco decode ${tDec.elapsedMilliseconds}ms (items=${jsonList.length})');

        final tMap = Stopwatch()..start();
        final out = jsonList.map((json) => PreventivoSummary.fromJson(json)).toList();
        tMap.stop();
        _logCache('_leggiCacheDaDisco map ${tMap.elapsedMilliseconds}ms');
        total.stop();
        _logCache('_leggiCacheDaDisco TOTAL ${total.elapsedMilliseconds}ms');
        return out;
      } else {
        _logCache('_leggiCacheDaDisco file non presente');
      }
    } catch (e) {
      // ignore: avoid_print
      print("Errore lettura cache da disco: $e");
    }
    total.stop();
    _logCache('_leggiCacheDaDisco TOTAL ${total.elapsedMilliseconds}ms (empty)');
    return [];
  }

  Future<Map<String, int>> _leggiVersioniDaPrefs() async {
    final total = Stopwatch()..start();
    try {
      final tInst = Stopwatch()..start();
      final prefs = await SharedPreferences.getInstance();
      tInst.stop();
      _logCache('_leggiVersioniDaPrefs getInstance ${tInst.elapsedMilliseconds}ms');

      final s = prefs.getString(_prefsKeyVersioni);
      if (s != null && s.isNotEmpty) {
        final tDec = Stopwatch()..start();
        final decoded = jsonDecode(s);
        tDec.stop();
        _logCache('_leggiVersioniDaPrefs decode ${tDec.elapsedMilliseconds}ms');

        if (decoded is Map) {
          final m = <String, int>{};
          decoded.forEach((k, v) {
            int val;
            try {
              val = v is int ? v : int.parse(v.toString());
            } catch (_) {
              val = 0;
            }
            m[k.toString()] = val;
          });
          total.stop();
          _logCache('_leggiVersioniDaPrefs TOTAL ${total.elapsedMilliseconds}ms (keys=${m.length})');
          return m;
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print("Errore lettura versioni da prefs: $e");
    }
    total.stop();
    _logCache('_leggiVersioniDaPrefs TOTAL ${total.elapsedMilliseconds}ms (empty)');
    return {};
  }

  bool _versionMapsEqual(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  // --- DEDUP locale per sicurezza (stesso preventivo_id in due mesi) ---
  List<PreventivoSummary> _dedupById(List<PreventivoSummary> items) {
    final t = Stopwatch()..start();
    final map = <String, PreventivoSummary>{};
    for (final p in items) {
      final prev = map[p.preventivoId];
      if (prev == null) {
        map[p.preventivoId] = p;
      } else {
        if (p.dataEvento.isAfter(prev.dataEvento) ||
            p.dataEvento.isAtSameMomentAs(prev.dataEvento)) {
          map[p.preventivoId] = p;
        }
      }
    }
    final out = map.values.toList();
    out.sort((a, b) => a.dataEvento.compareTo(b.dataEvento));
    t.stop();
    _logCache('_dedupById ${t.elapsedMilliseconds}ms (in=${items.length}, out=${out.length})');
    return out;
  }

  // --- COMPAT: versione cache (se il service non espone getVersioniCache) ---
  Future<Map<String, int>> _getVersioniCacheCompat() async {
    return await _service.getVersioniCache();
  }


  // --- REFRESH INTELLIGENTE IN BACKGROUND (non blocca la UI) ---
  Future<void> verificaVersioneCache() async {
    final total = Stopwatch()..start();

    if (_isEditingOpen) {
      _logCache('verificaVersioneCache skipped (editing open)');
      return;
    }

    final now = DateTime.now();
    if (_lastVersionCheckAt != null &&
        now.difference(_lastVersionCheckAt!) < _versionCheckCooldown) {
      _logCache('verificaVersioneCache throttled (${now.difference(_lastVersionCheckAt!).inMilliseconds}ms since last)');
      return;
    }

    if (_lastLocalSaveAt != null &&
        now.difference(_lastLocalSaveAt!) < _postSaveGrace) {
      _logCache('verificaVersioneCache grace after local save (${now.difference(_lastLocalSaveAt!).inMilliseconds}ms)');
      return;
    }

    if (_isLoadingCache || _isRefreshing) {
      _logCache('verificaVersioneCache skipped (_isLoadingCache=$_isLoadingCache, _isRefreshing=$_isRefreshing)');
      return;
    }

    _isRefreshing = true;
    notifyListeners();

    try {
      final tRemote = Stopwatch()..start();
      final versioniRemote = await _getVersioniCacheCompat();
      tRemote.stop();
      _logCache('getVersioniCacheCompat ${tRemote.elapsedMilliseconds}ms');

      _lastVersionCheckAt = DateTime.now();

      final vr = versioniRemote;
      final vc = _versioniCacheLocali;

      if (!_versionMapsEqual(vr, vc)) {
        _logCache("Versioni diverse (server=$vr, locale=$vc). Aggiorno in background...");
        final tIdx = Stopwatch()..start();
        final remotiRaw = await _service.getTuttiGliIndici(); // List<Map>
        tIdx.stop();
        _logCache('getTuttiGliIndici ${tIdx.elapsedMilliseconds}ms (items=${remotiRaw.length})');

        final tParse = Stopwatch()..start();
        final remoti = _parseSummaries(remotiRaw);
        final dedup = _dedupById(remoti);
        _cacheIndiciCompleta = dedup;
        tParse.stop();
        _logCache('parse+dedup ${tParse.elapsedMilliseconds}ms');

        final tSave = Stopwatch()..start();
        await _salvaCacheSuDisco(_cacheIndiciCompleta, vr);
        tSave.stop();
        _logCache('save cache ${tSave.elapsedMilliseconds}ms');

        _risultatiRicerca = List.from(_cacheIndiciCompleta);
      } else {
        _logCache("Versioni locali già allineate ($vc).");
      }
    } catch (e) {
      print("Errore durante la verifica della versione cache: $e");
    } finally {
      _isRefreshing = false;
      notifyListeners();
      total.stop();
      _logCache('verificaVersioneCache TOTAL ${total.elapsedMilliseconds}ms');
    }
  }

  // --- CARICAMENTO INIZIALE (può mostrare loader centrale) ---
  Future<void> caricaCacheIniziale() async {
    if (_isLoadingCache) return;

    final total = Stopwatch()..start();
    _isLoadingCache = true;
    _errorCache = null;
    if (_cacheIndiciCompleta.isEmpty) {
      notifyListeners();
    }

    try {
      final tLoc = Stopwatch()..start();
      _versioniCacheLocali = await _leggiVersioniDaPrefs();
      tLoc.stop();
      _logCache('versioni locali lette in ${tLoc.elapsedMilliseconds}ms ($_versioniCacheLocali)');

      final tVer = Stopwatch()..start();
      final versioniRemote = await _getVersioniCacheCompat();
      tVer.stop();
      _logCache('getVersioniCacheCompat ${tVer.elapsedMilliseconds}ms (remote=$versioniRemote)');

      final vr = versioniRemote;

      if (_versionMapsEqual(vr, _versioniCacheLocali) &&
          _versioniCacheLocali.isNotEmpty) {
        final tDisk = Stopwatch()..start();
        final datiDaDisco = await _leggiCacheDaDisco();
        tDisk.stop();
        _logCache('read cache disk ${tDisk.elapsedMilliseconds}ms (items=${datiDaDisco.length})');

        if (datiDaDisco.isNotEmpty) {
          final tDedup = Stopwatch()..start();
          _cacheIndiciCompleta = _dedupById(datiDaDisco);
          tDedup.stop();
          _logCache('dedup local ${tDedup.elapsedMilliseconds}ms');
        } else {
          final tIdx = Stopwatch()..start();
          final remotiRaw = await _service.getTuttiGliIndici();
          tIdx.stop();
          _logCache('getTuttiGliIndici ${tIdx.elapsedMilliseconds}ms (items=${remotiRaw.length})');

          final tParse = Stopwatch()..start();
          final remoti = _parseSummaries(remotiRaw);
          _cacheIndiciCompleta = _dedupById(remoti);
          tParse.stop();
          _logCache('parse+dedup ${tParse.elapsedMilliseconds}ms');

          final tSave = Stopwatch()..start();
          await _salvaCacheSuDisco(_cacheIndiciCompleta, vr);
          tSave.stop();
          _logCache('save cache ${tSave.elapsedMilliseconds}ms');
        }
      } else {
        final tIdx = Stopwatch()..start();
        final remotiRaw = await _service.getTuttiGliIndici();
        tIdx.stop();
        _logCache('getTuttiGliIndici ${tIdx.elapsedMilliseconds}ms (items=${remotiRaw.length})');

        final tParse = Stopwatch()..start();
        final remoti = _parseSummaries(remotiRaw);
        _cacheIndiciCompleta = _dedupById(remoti);
        tParse.stop();
        _logCache('parse+dedup ${tParse.elapsedMilliseconds}ms');

        final tSave = Stopwatch()..start();
        await _salvaCacheSuDisco(_cacheIndiciCompleta, vr);
        tSave.stop();
        _logCache('save cache ${tSave.elapsedMilliseconds}ms');
      }

      _risultatiRicerca = List.from(_cacheIndiciCompleta);
    } catch (e) {
      _errorCache = e.toString();
      _cacheIndiciCompleta = [];
      _risultatiRicerca = [];
    } finally {
      _isLoadingCache = false;
      notifyListeners();
      total.stop();
      _logCache('caricaCacheIniziale TOTAL ${total.elapsedMilliseconds}ms (items=${_cacheIndiciCompleta.length})');
    }
  }

  void aggiungiOAggiornaPreventivoInCache(PreventivoSummary summary) async {
    final total = Stopwatch()..start();
    final tIdx = Stopwatch()..start();
    final index = _cacheIndiciCompleta.indexWhere(
      (p) => p.preventivoId == summary.preventivoId,
    );
    if (index != -1) {
      _cacheIndiciCompleta[index] = summary;
    } else {
      _cacheIndiciCompleta.add(summary);
    }
    tIdx.stop();
    _logCache('cache update index ${tIdx.elapsedMilliseconds}ms');

    final tSort = Stopwatch()..start();
    _cacheIndiciCompleta.sort((a, b) => a.dataEvento.compareTo(b.dataEvento));
    tSort.stop();
    _logCache('cache sort ${tSort.elapsedMilliseconds}ms (items=${_cacheIndiciCompleta.length})');

    final tSave = Stopwatch()..start();
    await _salvaCacheSuDisco(_cacheIndiciCompleta, _versioniCacheLocali);
    tSave.stop();
    _logCache('cache save ${tSave.elapsedMilliseconds}ms');

    _risultatiRicerca = List.from(_cacheIndiciCompleta);
    _lastLocalSaveAt = DateTime.now();

    notifyListeners();
    total.stop();
    _logCache('aggiungiOAggiornaPreventivoInCache TOTAL ${total.elapsedMilliseconds}ms');
  }

  Future<void> cercaPreventivi({
    String? testo,
    DateTime? dataDa,
    DateTime? dataA,
    String? stato,
  }) async {
    final total = Stopwatch()..start();
    _isSearching = true;
    _errorSearching = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 50));

    try {
      List<PreventivoSummary> risultatiFiltrati = List.from(_cacheIndiciCompleta);

      if (testo != null && testo.trim().isNotEmpty) {
        final testoLower = testo.toLowerCase();
        final df = DateFormat('dd/MM/yyyy');

        bool _match(PreventivoSummary p) {
          final ragioneSociale =
              (p.cliente.ragioneSociale ?? '').toLowerCase();
          final nomeEvento = (p.nomeEvento ?? '').toLowerCase();
          final dataStr = df.format(p.dataEvento).toLowerCase();

          return ragioneSociale.contains(testoLower) ||
              nomeEvento.contains(testoLower) ||
              dataStr.contains(testoLower);
        }

        final tFilter = Stopwatch()..start();
        risultatiFiltrati = risultatiFiltrati.where(_match).toList();
        tFilter.stop();
        _logCache('search text filter ${tFilter.elapsedMilliseconds}ms');
      }

      if (stato != null && stato.isNotEmpty) {
        final tState = Stopwatch()..start();
        risultatiFiltrati = risultatiFiltrati
            .where((p) => p.status.toLowerCase() == stato.toLowerCase())
            .toList();
        tState.stop();
        _logCache('search stato filter ${tState.elapsedMilliseconds}ms');
      }

      if (dataDa != null) {
        final tFrom = Stopwatch()..start();
        risultatiFiltrati = risultatiFiltrati
            .where((p) => !p.dataEvento.isBefore(dataDa))
            .toList();
        tFrom.stop();
        _logCache('search dataDa filter ${tFrom.elapsedMilliseconds}ms');
      }

      if (dataA != null) {
        final tTo = Stopwatch()..start();
        final dataFine = dataA.add(const Duration(days: 1));
        risultatiFiltrati = risultatiFiltrati
            .where((p) => p.dataEvento.isBefore(dataFine))
            .toList();
        tTo.stop();
        _logCache('search dataA filter ${tTo.elapsedMilliseconds}ms');
      }

      final tSort = Stopwatch()..start();
      risultatiFiltrati.sort((a, b) => a.dataEvento.compareTo(b.dataEvento));
      tSort.stop();
      _logCache('search sort ${tSort.elapsedMilliseconds}ms (out=${risultatiFiltrati.length})');

      _risultatiRicerca = risultatiFiltrati;
    } catch (e) {
      _errorSearching = "Errore durante il filtraggio locale: ${e.toString()}";
      _risultatiRicerca = [];
    } finally {
      _isSearching = false;
      notifyListeners();
      total.stop();
      _logCache('cercaPreventivi TOTAL ${total.elapsedMilliseconds}ms');
    }
  }

  Future<void> caricaPreventiviPerCliente(String idCliente) async {
    final total = Stopwatch()..start();
    _isSearching = true;
    _errorSearching = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final t = Stopwatch()..start();
      final list = _cacheIndiciCompleta
          .where((p) => p.cliente.idCliente == idCliente)
          .toList()
        ..sort((a, b) => a.dataEvento.compareTo(b.dataEvento));
      t.stop();
      _logCache('caricaPreventiviPerCliente filter+sort ${t.elapsedMilliseconds}ms (out=${list.length})');
      _risultatiRicerca = list;
    } catch (e) {
      _errorSearching = e.toString();
      _risultatiRicerca = [];
    } finally {
      _isSearching = false;
      notifyListeners();
      total.stop();
      _logCache('caricaPreventiviPerCliente TOTAL ${total.elapsedMilliseconds}ms');
    }
  }

  Future<PreventivoCompleto?> caricaDettaglioPreventivo(
    String preventivoId,
  ) async {
    final total = Stopwatch()..start();
    _isSearching = true;
    _errorSearching = null;
    notifyListeners();
    try {
      final json = await _service.getPreventivo(preventivoId);
      return PreventivoCompleto.fromJson(json);
    } catch (e) {
      _errorSearching = e.toString();
      return null;
    } finally {
      _isSearching = false;
      notifyListeners();
      total.stop();
      _logCache('caricaDettaglioPreventivo TOTAL ${total.elapsedMilliseconds}ms (id=$preventivoId)');
    }
  }

  Future<bool> eliminaPreventivo(String preventivoId) async {
    final total = Stopwatch()..start();
    final indexInCache = _cacheIndiciCompleta.indexWhere(
      (p) => p.preventivoId == preventivoId,
    );
    if (indexInCache == -1) return false;
    final preventivoDaEliminare = _cacheIndiciCompleta[indexInCache];

    final indexInRisultati = _risultatiRicerca.indexWhere(
      (p) => p.preventivoId == preventivoId,
    );

    _cacheIndiciCompleta.removeAt(indexInCache);
    if (indexInRisultati != -1) {
      _risultatiRicerca.removeAt(indexInRisultati);
    }
    final tSave = Stopwatch()..start();
    await _salvaCacheSuDisco(_cacheIndiciCompleta, _versioniCacheLocali);
    tSave.stop();
    _logCache('eliminaPreventivo pre-remote save ${tSave.elapsedMilliseconds}ms');
    notifyListeners();

    try {
      final tRemote = Stopwatch()..start();
      await _service.eliminaPreventivo(preventivoId);
      tRemote.stop();
      _logCache('eliminaPreventivo remote ${tRemote.elapsedMilliseconds}ms');
      total.stop();
      _logCache('eliminaPreventivo TOTAL ${total.elapsedMilliseconds}ms (success)');
      return true;
    } catch (e) {
      _errorSaving = e.toString();
      _cacheIndiciCompleta.insert(indexInCache, preventivoDaEliminare);
      if (indexInRisultati != -1) {
        _risultatiRicerca.insert(indexInRisultati, preventivoDaEliminare);
      }
      final tSave2 = Stopwatch()..start();
      await _salvaCacheSuDisco(_cacheIndiciCompleta, _versioniCacheLocali);
      tSave2.stop();
      _logCache('eliminaPreventivo rollback save ${tSave2.elapsedMilliseconds}ms');
      notifyListeners();
      total.stop();
      _logCache('eliminaPreventivo TOTAL ${total.elapsedMilliseconds}ms (rollback)');
      return false;
    }
  }

  void pulisciRisultatiRicerca() {
    _risultatiRicerca = [];
    _errorSearching = null;
    notifyListeners();
  }

    // Forza un refresh completo ignorando la versione locale
  // Forza un refresh completo ignorando la versione locale
  Future<void> hardRefresh({bool ignoreEditingOpen = false}) async {
    if (_isEditingOpen && !ignoreEditingOpen) {
      _logCache('hardRefresh skipped (editing open)');
      return;
    }

    final total = Stopwatch()..start();
    if (_isLoadingCache) return;
    _isLoadingCache = true;
    _errorCache = null;
    notifyListeners();

    try {
      final tVer = Stopwatch()..start();
      final versioniRemote = await _getVersioniCacheCompat();
      tVer.stop();
      _logCache('hardRefresh getVersioniCacheCompat ${tVer.elapsedMilliseconds}ms');

      final tIdx = Stopwatch()..start();
      final remotiRaw = await _service.getTuttiGliIndici(); // List<Map>
      tIdx.stop();
      _logCache('hardRefresh getTuttiGliIndici ${tIdx.elapsedMilliseconds}ms (items=${remotiRaw.length})');

      final tParse = Stopwatch()..start();
      final remoti = _parseSummaries(remotiRaw); // -> List<PreventivoSummary>
      _cacheIndiciCompleta = _dedupById(remoti);
      tParse.stop();
      _logCache('hardRefresh parse+dedup ${tParse.elapsedMilliseconds}ms');

      final tSave = Stopwatch()..start();
      await _salvaCacheSuDisco(_cacheIndiciCompleta, versioniRemote);
      tSave.stop();
      _logCache('hardRefresh save cache ${tSave.elapsedMilliseconds}ms');

      _risultatiRicerca = List.from(_cacheIndiciCompleta);
    } catch (e) {
      _errorCache = e.toString();
    } finally {
      _isLoadingCache = false;
      notifyListeners();
      total.stop();
      _logCache('hardRefresh TOTAL ${total.elapsedMilliseconds}ms');
    }
  }


  /// Panic reload: azzera versioni locali e ricarica tutto da zero (server-of-truth)
  Future<void> forceResync() async {
    final total = Stopwatch()..start();
    try {
      final tInst = Stopwatch()..start();
      final prefs = await SharedPreferences.getInstance();
      tInst.stop();
      _logCache('forceResync prefs.getInstance ${tInst.elapsedMilliseconds}ms');
      await prefs.remove(_prefsKeyVersioni);
      _versioniCacheLocali = {};
      try {
        final file = await _cacheFile;
        if (await file.exists()) {
          final tDel = Stopwatch()..start();
          await file.delete();
          tDel.stop();
          _logCache('forceResync delete file ${tDel.elapsedMilliseconds}ms');
        }
      } catch (_) {}
    } catch (_) {}
    await hardRefresh();
    total.stop();
    _logCache('forceResync TOTAL ${total.elapsedMilliseconds}ms');
  }

  // =========================================================
  //                 METODI FIRMA / CONFERMA
  // =========================================================

  Future<bool> uploadFirmaPng(String preventivoId, Uint8List pngBytes) async {
    final total = Stopwatch()..start();
    _errorSaving = null;
    _successMessage = null;
    _isSaving = true;
    notifyListeners();
    try {
      final ok = await _service.uploadFirmaPng(preventivoId, pngBytes);
      if (!ok) throw Exception('Upload firma non riuscito');
      _successMessage = 'Firma caricata';
      return true;
    } catch (e) {
      _errorSaving = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
      total.stop();
      _logCache('uploadFirmaPng TOTAL ${total.elapsedMilliseconds}ms (id=$preventivoId)');
    }
  }

  Future<bool> confermaPreventivo(String preventivoId) async {
    final total = Stopwatch()..start();
    _errorSaving = null;
    _successMessage = null;
    _isSaving = true;
    notifyListeners();
    try {
      await _service.confermaPreventivo(preventivoId);
      _successMessage = 'Preventivo confermato';
      await _setStatusLocal(preventivoId, 'CONFERMATO');
      await verificaVersioneCache();
      return true;
    } catch (e) {
      _errorSaving = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
      total.stop();
      _logCache('confermaPreventivo TOTAL ${total.elapsedMilliseconds}ms (id=$preventivoId)');
    }
  }

  Future<bool> caricaFirmaEConferma(
    String preventivoId,
    Uint8List pngBytes,
  ) async {
    final total = Stopwatch()..start();
    _errorSaving = null;
    _successMessage = null;
    _isSaving = true;
    notifyListeners();
    try {
      final okUpload = await _service.uploadFirmaPng(preventivoId, pngBytes);
      if (!okUpload) {
        throw Exception('Upload firma non riuscito');
      }
      await _service.confermaPreventivo(preventivoId);
      _successMessage = 'Firma caricata e preventivo confermato';
      await _setStatusLocal(preventivoId, 'CONFERMATO');
      await verificaVersioneCache();
      return true;
    } catch (e) {
      _errorSaving = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
      total.stop();
      _logCache('caricaFirmaEConferma TOTAL ${total.elapsedMilliseconds}ms (id=$preventivoId)');
    }
  }

  Future<void> _setStatusLocal(String preventivoId, String newStatus) async {
    final total = Stopwatch()..start();
    bool touched = false;

    for (var i = 0; i < _cacheIndiciCompleta.length; i++) {
      if (_cacheIndiciCompleta[i].preventivoId == preventivoId) {
        final json = _cacheIndiciCompleta[i].toJson();
        json['status'] = newStatus;
        _cacheIndiciCompleta[i] = PreventivoSummary.fromJson(json);
        touched = true;
        break;
      }
    }
    for (var i = 0; i < _risultatiRicerca.length; i++) {
      if (_risultatiRicerca[i].preventivoId == preventivoId) {
        final json = _risultatiRicerca[i].toJson();
        json['status'] = newStatus;
        _risultatiRicerca[i] = PreventivoSummary.fromJson(json);
        touched = true;
        break;
      }
    }

    if (touched) {
      final tSave = Stopwatch()..start();
      await _salvaCacheSuDisco(_cacheIndiciCompleta, _versioniCacheLocali);
      tSave.stop();
      _lastLocalSaveAt = DateTime.now();
      notifyListeners();
      _logCache('_setStatusLocal save ${tSave.elapsedMilliseconds}ms');
    }
    total.stop();
    _logCache('_setStatusLocal TOTAL ${total.elapsedMilliseconds}ms (touched=$touched)');
  }
}
