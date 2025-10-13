// lib/models/servizio_selezionato.dart
import 'fornitore_servizio.dart';

class ServizioSelezionato {
  final String ruolo; // es: "allestimento"
  FornitoreServizio? fornitore;
  String? note;
  double? prezzo;

  ServizioSelezionato({
    required this.ruolo,
    this.fornitore,
    this.note,
    this.prezzo,
  });

  factory ServizioSelezionato.fromJson(Map<String, dynamic> json) {
    final p = json['prezzo'];
    double? parsedPrezzo;
    if (p is num) parsedPrezzo = p.toDouble();
    else if (p is String && p.trim().isNotEmpty) {
      parsedPrezzo = double.tryParse(p.replaceAll(',', '.'));
    }
    return ServizioSelezionato(
      ruolo: json['ruolo'] ?? '',
      fornitore: (json['fornitore'] is Map<String, dynamic>)
          ? FornitoreServizio.fromJson(json['fornitore'] as Map<String, dynamic>)
          : null,
      note: json['note'],
      prezzo: parsedPrezzo,
    );
  }

  Map<String, dynamic> toJson() => {
    'ruolo': ruolo,
    'fornitore': fornitore?.toJson(),
    'note': note,
    'prezzo': prezzo,
  };
}
