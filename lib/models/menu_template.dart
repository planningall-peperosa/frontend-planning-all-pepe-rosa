import 'dart:convert';

class MenuTemplate {
  final String idMenu;
  final String nomeMenu;
  final String tipologia;
  final double prezzo;
  final Map<String, List<String>> composizioneDefault;

  MenuTemplate({
    required this.idMenu,
    required this.nomeMenu,
    required this.tipologia,
    required this.prezzo,
    required this.composizioneDefault,
  });

  factory MenuTemplate.fromJson(Map<String, dynamic> json) {
    // Nome: accetta sia 'nome_menu' che 'MENU'
    final nome = (json['nome_menu'] ?? json['MENU'] ?? '').toString();

    // Prezzo: accetta num o stringa con virgola/euro
    double parsePrezzo(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final s = v.toString().replaceAll('€', '').replaceAll('EUR', '').replaceAll(',', '.').trim();
      return double.tryParse(s) ?? 0.0;
    }

    // Composizione: accetta Map o String JSON
    Map<String, List<String>> parseComp(dynamic raw) {
      dynamic c = raw;
      if (c is String && c.trim().isNotEmpty) {
        try { c = jsonDecode(c); } catch (_) { c = {}; }
      }
      final Map<String, List<String>> out = {};
      if (c is Map) {
        c.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v.map((e) => e.toString()).toList();
          } else if (v is String && v.trim().isNotEmpty) {
            out[k.toString()] = [v];
          }
        });
      }
      return out;
    }

    final compAny = json['composizione_default'] ?? json['composizione_default_json'] ?? {};

    return MenuTemplate(
      idMenu: json['id_menu']?.toString() ?? '',
      nomeMenu: nome,
      tipologia: json['tipologia']?.toString() ?? '',
      prezzo: parsePrezzo(json['prezzo']),
      composizioneDefault: parseComp(compAny),
    );
  }

  MenuTemplate copyWith({
    String? idMenu,
    String? nomeMenu,
    String? tipologia,
    double? prezzo,
    Map<String, List<String>>? composizioneDefault,
  }) {
    return MenuTemplate(
      idMenu: idMenu ?? this.idMenu,
      nomeMenu: nomeMenu ?? this.nomeMenu,
      tipologia: tipologia ?? this.tipologia,
      prezzo: prezzo ?? this.prezzo,
      composizioneDefault: composizioneDefault ?? this.composizioneDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id_menu': idMenu,
        'nome_menu': nomeMenu,
        'tipologia': tipologia,
        'prezzo': prezzo,
        'composizione_default': composizioneDefault,
      };
}
