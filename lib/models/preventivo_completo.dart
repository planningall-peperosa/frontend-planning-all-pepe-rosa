// lib/models/preventivo_completo.dart
import 'cliente.dart';
import 'piatto.dart';
import 'servizio_selezionato.dart';

class PreventivoCompleto {
  final Map<String, List<Piatto>> menu;
  final Cliente cliente;

  final String nomeEvento;
  final DateTime dataEvento;
  final int numeroOspiti;

  // NEW: bambini
  final int? numeroBambini;           // opzionale per retrocompatibilità
  final double? prezzoMenuBambino;    // opzionale
  final String? noteMenuBambini;      // opzionale

  final List<ServizioSelezionato> serviziExtra;

  final double prezzoMenuPersona;
  final String? nomeMenuTemplate;

  final double sconto;
  final String? noteSconto;

  final double? acconto;
  final String? tipoPasto;

  final String? status;
  final String? preventivoId;
  final DateTime? dataCreazione;

  PreventivoCompleto({
    required this.menu,
    required this.cliente,
    required this.nomeEvento,
    required this.dataEvento,
    required this.numeroOspiti,
    this.numeroBambini,
    this.prezzoMenuBambino,
    this.noteMenuBambini,
    required this.serviziExtra,
    required this.prezzoMenuPersona,
    this.nomeMenuTemplate,
    required this.sconto,
    this.noteSconto,
    this.acconto,
    this.tipoPasto,
    this.status,
    this.preventivoId,
    this.dataCreazione,
  });

  factory PreventivoCompleto.fromJson(Map<String, dynamic> json) {
    // menu
    final Map<String, List<Piatto>> menu = {};
    final menuIn = (json['menu'] as Map?) ?? {};
    menuIn.forEach((genere, lista) {
      final l = (lista as List?) ?? const [];
      menu[genere as String] = l.map((e) {
        return Piatto(
          idUnico: (e['id_unico'] as String?) ?? '',
          nome: (e['nome'] as String?) ?? '',
          tipologia: (e['custom'] == true) ? 'fuori_menu' : 'catalogo',
          genere: genere as String,
        );
      }).toList();
    });

    return PreventivoCompleto(
      menu: menu,
      cliente: Cliente.fromJson((json['cliente'] as Map).cast<String, dynamic>()),
      nomeEvento: (json['nome_evento'] as String?) ?? '',
      dataEvento: DateTime.parse((json['data_evento'] as String?) ?? DateTime.now().toIso8601String()),
      numeroOspiti: (json['numero_ospiti'] as num?)?.toInt() ?? 0,

      // NEW bambini
      numeroBambini: (json['numero_bambini'] as num?)?.toInt(),
      prezzoMenuBambino: (json['prezzo_menu_bambino'] as num?)?.toDouble(),
      noteMenuBambini: json['note_menu_bambini'] as String?,

      serviziExtra: ((json['servizi_extra'] as List?) ?? const [])
          .map((e) => ServizioSelezionato.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),

      prezzoMenuPersona: (json['prezzo_menu_persona'] as num?)?.toDouble() ?? 0.0,
      nomeMenuTemplate: json['nome_menu_template'] as String?,
      sconto: (json['sconto'] as num?)?.toDouble() ?? 0.0,
      noteSconto: json['note_sconto'] as String?,
      acconto: (json['acconto'] as num?)?.toDouble(),
      tipoPasto: json['tipo_pasto'] as String?,

      status: json['status'] as String?,
      preventivoId: json['preventivo_id'] as String?,
      dataCreazione: _parseDateTime(json['data_creazione']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'menu': menu.map((k, v) => MapEntry(k, v.map((p) => {
        'id_unico': p.idUnico,
        'nome': p.nome,
        'custom': p.tipologia == 'fuori_menu' || p.idUnico.startsWith('custom_'),
      }).toList())),
      'cliente': cliente.toJson(),
      'nome_evento': nomeEvento,
      'data_evento': dataEvento.toIso8601String().substring(0, 10),
      'numero_ospiti': numeroOspiti,
      // NEW bambini
      'numero_bambini': numeroBambini,
      'prezzo_menu_bambino': prezzoMenuBambino,
      'note_menu_bambini': noteMenuBambini,
      'servizi_extra': serviziExtra.map((s) => s.toJson()).toList(),
      'prezzo_menu_persona': prezzoMenuPersona,
      'nome_menu_template': nomeMenuTemplate,
      'sconto': sconto,
      'note_sconto': noteSconto,
      'acconto': acconto,
      'tipo_pasto': tipoPasto,
      'status': status,
      'preventivo_id': preventivoId,
      'data_creazione': dataCreazione?.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
}
