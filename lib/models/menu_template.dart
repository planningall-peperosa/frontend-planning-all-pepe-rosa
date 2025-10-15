// lib/models/menu_template.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    // --- MODIFICA CORRETTIVA: Leggiamo dal nuovo nome campo 'composizione' ---
    final compAny = json['composizione'] ?? json['composizione_default'] ?? json['composizione_default_json'] ?? {};

    return MenuTemplate(
      idMenu: json['id_menu']?.toString() ?? '',
      nomeMenu: nome,
      tipologia: json['tipologia']?.toString() ?? '',
      // --- MODIFICA CORRETTIVA: Leggiamo dal nuovo nome campo 'prezzo_predefinito' ---
      prezzo: parsePrezzo(json['prezzo_predefinito'] ?? json['prezzo']),
      composizioneDefault: parseComp(compAny),
    );
  }

  // --- NUOVA AGGIUNTA: TRADUTTORE DA FIRESTORE ---
  factory MenuTemplate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // L'id del documento diventa il nostro idMenu per coerenza
    data['id_menu'] = doc.id; 
    return MenuTemplate.fromJson(data);
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
        'prezzo_predefinito': prezzo, // Scriviamo con il nuovo nome
        'composizione': composizioneDefault, // Scriviamo con il nuovo nome
      };
}