// lib/utils/consistency_check.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../providers/preventivo_builder_provider.dart';
import '../models/servizio_selezionato.dart';

class ConsistencyIssue {
  final String path;        // es. "prezzo_menu_persona"
  final String expected;    // cosa ci aspettiamo
  final String actual;      // cosa troviamo
  final String severity;    // "warning" | "error"

  ConsistencyIssue({
    required this.path,
    required this.expected,
    required this.actual,
    this.severity = 'warning',
  });
}

class ConsistencyReport {
  final List<ConsistencyIssue> issues;
  const ConsistencyReport(this.issues);

  bool get hasIssues => issues.isNotEmpty;
}

/// Helpers ------------------------------------------------------------------

bool _numEq(num a, num b, {num eps = 0.005}) => (a - b).abs() <= eps;

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

int? _i(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String _fmtMoney(num? v) =>
    (v == null) ? '-' : '€ ${v.toStringAsFixed(2)}';

String _fmt(dynamic v) => v?.toString() ?? '-';

/// Alcuni progetti hanno nomi diversi per “prezzo per persona” nel builder.
/// Qui proviamo più getter via `dynamic` e torniamo la prima occorrenza valida.
double? _getProvPrezzoMenuPersona(PreventivoBuilderProvider prov) {
  final dyn = prov as dynamic;
  try {
    final v = dyn.prezzoMenuPersona;
    if (v is num) return v.toDouble();
  } catch (_) {}
  try {
    final v = dyn.prezzoMenuAdulti; // a volte esiste questo
    if (v is num) return v.toDouble();
  } catch (_) {}
  try {
    final v = dyn.prezzoPersona; // nome generico
    if (v is num) return v.toDouble();
  } catch (_) {}
  try {
    final v = dyn.prezzoPerPersona; // altro alias
    if (v is num) return v.toDouble();
  } catch (_) {}
  // Non trovato: restituiamo null -> saltiamo il check relativo
  return null;
}

/// Accesso robusto alla lista servizi dal provider
List<ServizioSelezionato>? _getServiziProv(PreventivoBuilderProvider prov) {
  try {
    final dyn = prov as dynamic;
    final v = dyn.serviziSelezionati;
    if (v is List<ServizioSelezionato>) return v;
  } catch (_) {}
  return null;
}

/// Funzione principale di controllo -----------------------------------------
Future<ConsistencyReport> checkPreventivoConsistency(
  PreventivoBuilderProvider prov,
  Map<String, dynamic> db,
) async {
  final issues = <ConsistencyIssue>[];
  final df = DateFormat('yyyy-MM-dd');

  // ---- Stato / Status ------------------------------------------------------
  final provStatus = (prov.status ?? '').toString().trim().toLowerCase();
  final dbStatus = ((db['status'] ?? db['stato']) ?? '').toString().trim().toLowerCase();
  if (provStatus.isNotEmpty && dbStatus.isNotEmpty && provStatus != dbStatus) {
    issues.add(ConsistencyIssue(
      path: 'status',
      expected: provStatus,
      actual: dbStatus,
      severity: 'warning',
    ));
  }

  // ---- Data evento ---------------------------------------------------------
  try {
    final provDate = prov.dataEvento;
    final dbDateStr = (db['data_evento'] ?? '').toString();
    if (provDate != null && dbDateStr.isNotEmpty) {
      final provStr = df.format(provDate);
      final dbStr = dbDateStr.length >= 10 ? dbDateStr.substring(0, 10) : dbDateStr;
      if (provStr != dbStr) {
        issues.add(ConsistencyIssue(
          path: 'data_evento',
          expected: provStr,
          actual: dbStr,
          severity: 'warning',
        ));
      }
    }
  } catch (_) {}

  // ---- Numero ospiti -------------------------------------------------------
  final provOspiti = prov.numeroOspiti;
  final dbOspiti = _i(db['numero_ospiti']);
  if (provOspiti != null && dbOspiti != null && provOspiti != dbOspiti) {
    issues.add(ConsistencyIssue(
      path: 'numero_ospiti',
      expected: provOspiti.toString(),
      actual: dbOspiti.toString(),
      severity: 'warning',
    ));
  }

  // ---- Prezzo menu per persona (solo se riusciamo a leggerlo dal provider) -
  final prezzoProv = _getProvPrezzoMenuPersona(prov);
  final prezzoDb = _d(db['prezzo_menu_persona']);
  if (prezzoProv != null && prezzoDb != null && !_numEq(prezzoProv, prezzoDb)) {
    issues.add(ConsistencyIssue(
      path: 'prezzo_menu_persona',
      expected: _fmtMoney(prezzoProv),
      actual: _fmtMoney(prezzoDb),
      severity: 'warning',
    ));
  }

  // ---- Sconto --------------------------------------------------------------
  final provSconto = prov.sconto;
  final dbSconto = _d(db['sconto']) ?? 0.0;
  if (!_numEq(provSconto, dbSconto)) {
    issues.add(ConsistencyIssue(
      path: 'sconto',
      expected: _fmtMoney(provSconto),
      actual: _fmtMoney(dbSconto),
      severity: 'warning',
    ));
  }

  // ---- Acconto -------------------------------------------------------------
  final provAcconto = prov.acconto ?? 0.0;
  final dbAcconto = _d(db['acconto']) ?? 0.0;
  if (!_numEq(provAcconto, dbAcconto)) {
    issues.add(ConsistencyIssue(
      path: 'acconto',
      expected: _fmtMoney(provAcconto),
      actual: _fmtMoney(dbAcconto),
      severity: 'warning',
    ));
  }

  // ---- Modalità “pacchetto fisso” vs “menu a portate” ----------------------
  final provIsPacchetto = prov.isPacchettoFisso;
  final dbHasPacchettoFields = db.containsKey('prezzo_pacchetto') ||
      db.containsKey('descrizione_pacchetto_fisso') ||
      db.containsKey('descrizione_pacchetto_fisso_2') ||
      db.containsKey('descrizione_pacchetto_fisso_3');

  if (provIsPacchetto != dbHasPacchettoFields) {
    issues.add(ConsistencyIssue(
      path: 'modalita_preventivo',
      expected: provIsPacchetto ? 'pacchetto_fisso' : 'menu_a_portate',
      actual: dbHasPacchettoFields ? 'pacchetto_fisso' : 'menu_a_portate',
      severity: 'warning',
    ));
  }

  // ---- Servizi extra: confronto basico su numero e ruoli -------------------
  final serviziProv = _getServiziProv(prov);
  final serviziDbRaw = (db['servizi_extra'] is List) ? (db['servizi_extra'] as List) : const [];
  final serviziDb = serviziDbRaw.whereType<Map>().toList();

  if ((serviziProv?.length ?? 0) != serviziDb.length) {
    issues.add(ConsistencyIssue(
      path: 'servizi_extra.count',
      expected: (serviziProv?.length ?? 0).toString(),
      actual: serviziDb.length.toString(),
      severity: 'warning',
    ));
  } else {
    for (int i = 0; i < serviziDb.length; i++) {
      final ruoloProv = (serviziProv?[i]?.ruolo ?? '').toString(); // <- fix null-safety
      final ruoloDb = (serviziDb[i]['ruolo'] ?? '').toString();
      if (ruoloProv != ruoloDb) {
        issues.add(ConsistencyIssue(
          path: 'servizi_extra[$i].ruolo',
          expected: ruoloProv,
          actual: ruoloDb,
          severity: 'warning',
        ));
      }
    }
  }

  return ConsistencyReport(issues);
}

/// Dialog per mostrare il report --------------------------------------------
Future<void> showConsistencyReportDialog(
  BuildContext context,
  ConsistencyReport report,
) async {
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Check di coerenza'),
        content: SizedBox(
          width: 480,
          child: report.hasIssues
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sono emerse alcune differenze tra stato locale e Firestore:',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...report.issues.map((i) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            i.severity == 'error'
                                ? Icons.error_outline
                                : Icons.warning_amber_outlined,
                          ),
                          title: Text(i.path),
                          subtitle: Text('Atteso: ${i.expected}\nTrovato: ${i.actual}'),
                        )),
                  ],
                )
              : const Text('Tutto coerente!'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
