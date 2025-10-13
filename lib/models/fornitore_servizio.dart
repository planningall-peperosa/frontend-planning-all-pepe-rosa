// lib/models/fornitore_servizio.dart
class FornitoreServizio {
  final String idContatto;
  final String ragioneSociale;
  final double? prezzo;

  FornitoreServizio({
    required this.idContatto,
    required this.ragioneSociale,
    this.prezzo,
  });

  factory FornitoreServizio.fromJson(Map<String, dynamic> json) {
    final p = json['prezzo'];
    double? parsedPrezzo;
    if (p is num) parsedPrezzo = p.toDouble();
    else if (p is String && p.trim().isNotEmpty) {
      parsedPrezzo = double.tryParse(p.replaceAll(',', '.'));
    }
    return FornitoreServizio(
      idContatto: json['id_contatto'] ?? json['idContatto'] ?? '',
      ragioneSociale: json['ragione_sociale'] ?? json['ragioneSociale'] ?? '',
      prezzo: parsedPrezzo,
    );
  }

  Map<String, dynamic> toJson() => {
    'id_contatto': idContatto,
    'ragione_sociale': ragioneSociale,
    'prezzo': prezzo,
  };

  FornitoreServizio copyWith({
    String? idContatto,
    String? ragioneSociale,
    double? prezzo,
  }) => FornitoreServizio(
    idContatto: idContatto ?? this.idContatto,
    ragioneSociale: ragioneSociale ?? this.ragioneSociale,
    prezzo: prezzo ?? this.prezzo,
  );
}
