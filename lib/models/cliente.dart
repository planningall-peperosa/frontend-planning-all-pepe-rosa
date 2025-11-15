// lib/models/cliente.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Cliente {
  final String idCliente;
  final String tipo;
  final String? ruolo;
  final String? ragioneSociale;
  final String? referente;
  final String? telefono01;
  final String? telefono02;
  final String? telefono03;
  final String? indirizzo;
  final String? mail;
  final String? note;
  final int conteggioPreventivi;
  final double? prezzo;
  final String? colore; // *** NUOVO CAMPO: Colore per Dipendenti ***
  final String? codiceFiscale; // 🟢 NUOVO CAMPO: Codice Fiscale

  Cliente({
    required this.idCliente,
    required this.tipo,
    this.ruolo,
    this.ragioneSociale,
    this.referente,
    this.telefono01,
    this.telefono02,
    this.telefono03,
    this.indirizzo,
    this.mail,
    this.note,
    this.conteggioPreventivi = 0,
    this.prezzo,
    this.colore, // *** NUOVO CAMPO AGGIUNTO ***
    this.codiceFiscale, // 🟢 NUOVO CAMPO NEL COSTRUTTORE
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    int conteggio = 0;
    if (json['conteggio_preventivi'] is int) {
      conteggio = json['conteggio_preventivi'];
    } else if (json['conteggio_preventivi'] is String) {
      conteggio = int.tryParse(json['conteggio_preventivi']) ?? 0;
    }

    double? prezzoVal;
    if (json['prezzo'] is num) {
      prezzoVal = (json['prezzo'] as num).toDouble();
    } else if (json['prezzo'] is String) {
      prezzoVal = double.tryParse(json['prezzo']);
    }

    return Cliente(
      idCliente: json['id_contatto'] ?? json['id_cliente'] ?? json['id_unico'] ?? '', // Aggiunto id_unico per compatibilità dipendenti
      tipo: json['tipo'] ?? 'sconosciuto',
      // Mappiamo i campi dipendente su quelli esistenti o nuovi
      ruolo: json['ruolo']?.toString(), // Usato per ruolo Dipendente e Fornitore
      ragioneSociale: json['ragione_sociale']?.toString() ?? json['nome_dipendente']?.toString(), // Mappa nome_dipendente su ragioneSociale
      referente: json['referente']?.toString(),
      telefono01: json['telefono_01']?.toString() ?? json['telefono']?.toString(), // Mappa telefono dipendente su telefono01
      telefono02: json['telefono_02']?.toString(),
      telefono03: json['telefono_03']?.toString(),
      indirizzo: json['indirizzo']?.toString(),
      mail: json['mail']?.toString() ?? json['email']?.toString(), // Mappa email dipendente su mail
      note: json['note']?.toString(),
      conteggioPreventivi: conteggio,
      prezzo: prezzoVal,
      colore: json['colore']?.toString(), // *** ASSEGNAZIONE NUOVO CAMPO ***
      codiceFiscale: json['codice_fiscale']?.toString(), // 🟢 NUOVO CAMPO NEL FROMJSON
    );
  }

  // --- NUOVA AGGIUNTA: TRADUTTORE DA FIRESTORE ---
  factory Cliente.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id_cliente'] = doc.id;
    return Cliente.fromJson(data);
  }

  factory Cliente.empty() {
    return Cliente(
      idCliente: '',
      tipo: '',
      ruolo: null,
      ragioneSociale: '',
      referente: '',
      telefono01: '',
      telefono02: null,
      telefono03: null,
      indirizzo: null,
      mail: '',
      note: null,
      conteggioPreventivi: 0,
      prezzo: null,
      colore: null, // *** NUOVO CAMPO ***
      codiceFiscale: null, // 🟢 NUOVO CAMPO
    );
  }

  // --- METODO AGGIUNTO E AGGIORNATO PER FIRESTORE ---
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'tipo': tipo,
      'ragione_sociale': ragioneSociale,
      'referente': referente,
      'telefono_01': telefono01,
      'indirizzo': indirizzo,
      'mail': mail,
      'note': note,
      'conteggio_preventivi': conteggioPreventivi,
      'codice_fiscale': codiceFiscale, // 🟢 NUOVO CAMPO NEL TOJSON
      // Questi campi vengono inclusi solo se non sono nulli per ottimizzare Firestore
      if (idCliente.isNotEmpty) 'id_cliente': idCliente,
      if (telefono02 != null) 'telefono_02': telefono02,
      if (telefono03 != null) 'telefono_03': telefono03,
      // Campi specifici del Fornitore
      if (tipo == 'fornitore') ...{
        if (ruolo != null && ruolo!.isNotEmpty) 'ruolo': ruolo,
        if (prezzo != null) 'prezzo': prezzo,
      },
      // Campi specifici del Dipendente
      if (tipo == 'dipendente') ...{
        // Se è dipendente, il campo 'ruolo' è già coperto
        if (colore != null) 'colore': colore, // *** NUOVO CAMPO AGGIUNTO ***
        // NB: I campi extra 01-10 e PIN sono stati omessi come da discussione precedente
      }
    };
    return json;
  }
}