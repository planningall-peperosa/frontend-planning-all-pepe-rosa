// lib/models/preventivo_summary.dart
import 'package:flutter/foundation.dart';

/// Piccolo DTO cliente per i riepiloghi (evita dipendenze forti)
class ClienteLite {
  final String idCliente;
  final String? ragioneSociale;
  final String? telefono01;
  final String? mail;

  ClienteLite({
    required this.idCliente,
    this.ragioneSociale,
    this.telefono01,
    this.mail,
  });

  factory ClienteLite.fromJson(Map<String, dynamic> json) {
    return ClienteLite(
      idCliente: (json['id_cliente'] ?? '') as String,
      ragioneSociale: (json['ragione_sociale'] as String?)?.trim(),
      telefono01: (json['telefono_01'] as String?)?.trim(),
      mail: (json['mail'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_cliente': idCliente,
        'ragione_sociale': ragioneSociale,
        'telefono_01': telefono01,
        'mail': mail,
      };
}

class PreventivoSummary {
  final String preventivoId;
  final String status;

  final DateTime dataEvento;
  final DateTime dataCreazione;
  final DateTime? dataModifica;

  final ClienteLite cliente;

  // Campi base
  final double prezzoMenuPersona;
  final String? nomeMenuTemplate;
  final double sconto;
  final String? noteSconto;
  final double? acconto;
  final String? tipoPasto; // 'pranzo' | 'cena' | null

  // Bambini
  final int numeroBambini;
  final double prezzoMenuBambino;

  // Totali pre-calcolati (se disponibili lato backend)
  final double? costoMenuAdulti;
  final double? costoMenuBambini;
  final double? costoServizi;
  final double? subtotale;
  final double? totaleFinale;

  // Per distinguere copie
  final String? nomeEvento;

  PreventivoSummary({
    required this.preventivoId,
    required this.status,
    required this.dataEvento,
    required this.dataCreazione,
    this.dataModifica,
    required this.cliente,
    this.prezzoMenuPersona = 0.0,
    this.nomeMenuTemplate,
    this.sconto = 0.0,
    this.noteSconto,
    this.acconto,
    this.tipoPasto,
    this.numeroBambini = 0,
    this.prezzoMenuBambino = 0.0,
    this.costoMenuAdulti,
    this.costoMenuBambini,
    this.costoServizi,
    this.subtotale,
    this.totaleFinale,
    this.nomeEvento,
  });

  static DateTime _parseDate(String? v, {bool dateOnly = false}) {
    if (v == null || v.isEmpty) return DateTime(1970, 1, 1);
    try {
      // Se è 'YYYY-MM-DD' forziamo alle 00:00
      if (dateOnly && v.length >= 10) {
        return DateTime.parse(v.substring(0, 10));
      }
      return DateTime.parse(v);
    } catch (_) {
      // fallback robusto
      return DateTime(1970, 1, 1);
    }
  }

  factory PreventivoSummary.fromJson(Map<String, dynamic> json) {
    final clienteMap = (json['cliente'] as Map?)?.cast<String, dynamic>() ?? {};
    return PreventivoSummary(
      preventivoId: json['preventivo_id'] as String,
      status: (json['status'] as String?)?.trim() ?? 'Bozza',
      dataEvento: _parseDate(json['data_evento'] as String?, dateOnly: true),
      dataCreazione: _parseDate(json['data_creazione'] as String?),
      dataModifica: (json['data_modifica'] != null)
          ? _parseDate(json['data_modifica'] as String?)
          : null,
      cliente: ClienteLite.fromJson(clienteMap),

      prezzoMenuPersona: (json['prezzo_menu_persona'] as num?)?.toDouble() ?? 0.0,
      nomeMenuTemplate: json['nome_menu_template'] as String?,
      sconto: (json['sconto'] as num?)?.toDouble() ?? 0.0,
      noteSconto: json['note_sconto'] as String?,
      acconto: (json['acconto'] as num?)?.toDouble(),
      tipoPasto: json['tipo_pasto'] as String?,

      numeroBambini: (json['numero_bambini'] as num?)?.toInt() ?? 0,
      prezzoMenuBambino: (json['prezzo_menu_bambino'] as num?)?.toDouble() ?? 0.0,

      costoMenuAdulti: (json['costo_menu_adulti'] as num?)?.toDouble(),
      costoMenuBambini: (json['costo_menu_bambini'] as num?)?.toDouble(),
      costoServizi: (json['costo_servizi'] as num?)?.toDouble(),
      subtotale: (json['subtotale'] as num?)?.toDouble(),
      totaleFinale: (json['totale_finale'] as num?)?.toDouble(),

      nomeEvento: (json['nome_evento'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'preventivo_id': preventivoId,
      'status': status,
      'data_evento': dataEvento.toIso8601String().substring(0, 10),
      'data_creazione': dataCreazione.toIso8601String(),
      if (dataModifica != null) 'data_modifica': dataModifica!.toIso8601String(),
      'cliente': cliente.toJson(),
      'prezzo_menu_persona': prezzoMenuPersona,
      'nome_menu_template': nomeMenuTemplate,
      'sconto': sconto,
      'note_sconto': noteSconto,
      'acconto': acconto,
      'tipo_pasto': tipoPasto,
      'numero_bambini': numeroBambini,
      'prezzo_menu_bambino': prezzoMenuBambino,
      'costo_menu_adulti': costoMenuAdulti,
      'costo_menu_bambini': costoMenuBambini,
      'costo_servizi': costoServizi,
      'subtotale': subtotale,
      'totale_finale': totaleFinale,
      'nome_evento': nomeEvento,
    };
  }
}
