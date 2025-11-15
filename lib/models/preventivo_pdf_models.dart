// lib/models/preventivo_pdf_models.dart (Intero)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Necessario per Timestamp

// ====== LOGGING MINIMALE PER DEBUG ======
final _prettyPdfModels = const JsonEncoder.withIndent('  ');
void dlogPdfModels(String tag, Object? data) {
  if (!kDebugMode) return;
  if (data is Map || data is List) {
    // ignore: avoid_print
    print('[PDFMODELS][$tag] ${_prettyPdfModels.convert(data)}');
  } else {
    // ignore: avoid_print
    print('[PDFMODELS][$tag] $data');
  }
}

// Hash leggero solo per confronto (non crittografico)
String jhashPdfModels(Object? data) {
  try {
    final s = jsonEncode(data);
    return s.hashCode.toUnsigned(20).toRadixString(16);
  } catch (_) {
    return '0';
  }
}
// =======================================

class ClientePdf {
  final String ragioneSociale;
  final String referente;
  final String telefono01;
  final String mail;
  final String? codiceFiscale; 

  ClientePdf.fromMap(Map<String, dynamic> map) :
    ragioneSociale = map['ragione_sociale'] ?? '',
    referente = map['referente'] ?? '',
    telefono01 = map['telefono_01'] ?? '',
    mail = map['mail'] ?? '',
    codiceFiscale = map['codice_fiscale'] ?? ''; 
  
  Map<String, dynamic> toMap() {
    return {
      'ragione_sociale': ragioneSociale,
      'referente': referente,
      'telefono_01': telefono01,
      'mail': mail,
      'codice_fiscale': codiceFiscale, 
    };
  }
}

class ServizioExtraPdf {
  final String ruolo;
  final String note;
  final double prezzo;
  final Map<String, dynamic> fornitore;
  
  ServizioExtraPdf.fromMap(Map<String, dynamic> map) :
    ruolo = map['ruolo'] ?? '',
    note = map['note'] ?? '',
    prezzo = (map['prezzo'] as num?)?.toDouble() ?? 0.0,
    fornitore = map['fornitore'] ?? {} {
    // 🔍 Log ingresso singola riga extra (sample)
    dlogPdfModels('DTO:extra.fromMap', {
      'ruolo': ruolo,
      'prezzo': prezzo,
      'has_fornitore': fornitore.isNotEmpty,
    });
  }

  // ✅ Serializzazione necessaria per il calcolo
  Map<String, dynamic> toMap() {
    return {
      'ruolo': ruolo,
      'note': note,
      'prezzo': prezzo,
      'fornitore': fornitore,
    };
  }
}

class PiattoPdf {
  final String nome;
  final bool custom;
  
  PiattoPdf.fromMap(Map<String, dynamic> map) :
    nome = map['nome'] ?? '',
    custom = map['custom'] ?? false;
}

class MenuPdf {
  final List<PiattoPdf> antipasto;
  final List<PiattoPdf> primo;
  final List<PiattoPdf> secondo;
  final List<PiattoPdf> contorno;
  final List<PiattoPdf> portataGenerica;
  
  MenuPdf.fromMap(Map<String, dynamic> map) :
    antipasto = (map['antipasto'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    primo = (map['primo'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    secondo = (map['secondo'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    contorno = (map['contorno'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    portataGenerica = (map['portata_generica'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [];
}


class PreventivoCompletoPdf {
  final String id;
  final String nomeEvento;
  final String stato; 
  final bool? firmaAcquisita;
  final bool? confermato;
  final ClientePdf cliente;
  final DateTime dataEvento;
  final String tipoPasto;
  final int numeroOspiti;
  final int numeroBambini;
  final double prezzoMenuPersona;
  final double prezzoMenuBambino;
  final String? noteMenuBambini;
  final double sconto;
  final String? noteSconto;
  final String? noteIntegrative;
  final double? acconto;
  final List<ServizioExtraPdf> serviziExtra; 
  final MenuPdf? menu;
  final String? firmaUrl;
  
  final String? nomeMenuTemplate; 
  final int? orarioInizioH;
  final int? orarioInizioM;
  final int? orarioFineH;
  final int? orarioFineM;
  final String? firmaUrlCliente2; 

  final bool aperitivoBenvenuto; 
  final bool buffetDolci; 
  final String? buffetDolciNote; 
  final String pacchettoLabel; 
  final double pacchettoCosto; 

  // 🔑 CAMPI PACCHETTO FISSO
  final bool isPacchettoFisso; 
  final String? nomePacchettoFisso;
  final String? descrizionePacchettoFisso;      
  final String? descrizionePacchettoFisso2;     
  final String? descrizionePacchettoFisso3;     
  final String? propostaGastronomicaPacchetto;
  final double prezzoPacchettoFisso; 
  // 🔴 FINE CAMPI PACCHETTO FISSO


  PreventivoCompletoPdf.fromMap(Map<String, dynamic> map) :
    id = map['preventivo_id'] ?? '',
    nomeEvento = map['nome_evento'] ?? '',
    stato = ((map['stato'] as String? ?? map['status'] as String? ?? 'BOZZA').trim().toLowerCase()),
    firmaAcquisita = map['firma_acquisita'],
    confermato = map['confermato'],
    cliente = ClientePdf.fromMap(map['cliente'] ?? {}),
    dataEvento = map['data_evento'] is String
        ? DateTime.parse(map['data_evento'])
        : (map['data_evento'] is Timestamp
            ? (map['data_evento'] as Timestamp).toDate()
            : (map['data_evento'] as DateTime? ?? DateTime.now())),
    tipoPasto = map['tipo_pasto'] ?? '',
    numeroOspiti = (map['numero_ospiti'] as num?)?.toInt() ?? 0,
    numeroBambini = (map['numero_bambini'] as num?)?.toInt() ?? 0,
    prezzoMenuPersona = (map['prezzo_menu_persona'] as num? ?? map['prezzo_menu_adulto'] as num? ?? 0).toDouble(),
    prezzoMenuBambino = (map['prezzo_menu_bambino'] as num?)?.toDouble() ?? 0.0,
    noteMenuBambini = map['note_menu_bambini'] ?? map['menu_bambini'],
    sconto = (map['sconto'] as num?)?.toDouble() ?? 0.0,
    noteSconto = map['note_sconto'],
    noteIntegrative = map['note_integrative'],
    acconto = (map['acconto'] as num?)?.toDouble(),

    // servizi_extra con fallback da "servizi"
    serviziExtra = ((map['servizi_extra'] ?? map['servizi']) as List?)
        ?.map((s) => ServizioExtraPdf.fromMap(s as Map<String, dynamic>))
        .toList() ?? [],

    menu = map['menu'] != null ? MenuPdf.fromMap(map['menu']) : null,
    firmaUrl = map['firma_url'],
    nomeMenuTemplate = map['nome_menu_template'],

    // descrizioni: prima chiavi corte, poi fallback split dalla vecchia "descrizione_pacchetto_fisso"
    descrizionePacchettoFisso = (map['descrizione_1'] as String?) ?? (() {
      final full = map['descrizione_pacchetto_fisso'] as String?;
      if (full == null) return null;
      final parts = full.split('\n').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
      return parts.isNotEmpty ? parts[0] : null;
    })(),
    descrizionePacchettoFisso2 = (map['descrizione_2'] as String?) ?? (() {
      final full = map['descrizione_pacchetto_fisso'] as String?;
      if (full == null) return null;
      final parts = full.split('\n').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
      return parts.length > 1 ? parts[1] : null;
    })(),
    descrizionePacchettoFisso3 = (map['descrizione_3'] as String?) ?? (() {
      final full = map['descrizione_pacchetto_fisso'] as String?;
      if (full == null) return null;
      final parts = full.split('\n').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
      return parts.length > 2 ? parts[2] : null;
    })(),

    isPacchettoFisso = map['is_pacchetto_fisso'] ?? false,
    nomePacchettoFisso = map['nome_pacchetto_fisso'],
    propostaGastronomicaPacchetto = map['proposta_gastronomica_pacchetto'],
    prezzoPacchettoFisso = (map['prezzo_pacchetto_fisso'] as num?)?.toDouble() ?? 0.0,

    orarioInizioH = map['orario_inizio_h'] as int?,
    orarioInizioM = map['orario_inizio_m'] as int?,
    orarioFineH = map['orario_fine_h'] as int?,
    orarioFineM = map['orario_fine_m'] as int?,
    firmaUrlCliente2 = map['firma_url_cliente_2'],

    aperitivoBenvenuto = map['aperitivo_benvenuto'] ?? false,
    buffetDolci = map['buffet_dolci'] ?? false,
    buffetDolciNote = map['buffet_dolci_note'],

    // pacchetto label/costo: usa DB se presente, altrimenti calcola dal flag welcome/dolci
    pacchettoLabel = (map['pacchetto_label'] as String?) ??
        (() {
          final ab = map['aperitivo_benvenuto'] == true;
          final bd = map['buffet_dolci'] == true;
          if (ab && bd) return 'pacchetto aperitivo di benvenuto+buffet di dolci';
          if (ab && !bd) return 'aperitivo di benvenuto';
          if (!ab && bd) return 'buffet di dolci';
          return '';
        })(),
    pacchettoCosto = (map['pacchetto_costo'] as num?)
        ?.toDouble() ??
        (() {
          final n = (map['numero_ospiti'] as num?)?.toInt() ?? 0;
          final ab = map['aperitivo_benvenuto'] == true;
          final bd = map['buffet_dolci'] == true;
          if (ab && bd) return n * 10.0;
          if (ab && !bd) return n * 8.0;
          if (!ab && bd) return n * 5.0;
          return 0.0;
        })();

    
  
  Map<String, dynamic> toMap() {
    final out = {
      'preventivo_id': id,
      'nome_evento': nomeEvento,
      'stato': stato,
      'firma_acquisita': firmaAcquisita,
      'confermato': confermato,
      'cliente': cliente.toMap(), 
      'data_evento': dataEvento,
      'tipo_pasto': tipoPasto,
      'numero_ospiti': numeroOspiti,
      'numero_bambini': numeroBambini,
      'prezzo_menu_persona': prezzoMenuPersona,
      'prezzo_menu_bambino': prezzoMenuBambino,
      'note_menu_bambini': noteMenuBambini,
      'sconto': sconto,
      'note_sconto': noteSconto,
      'note_integrative': noteIntegrative,
      'acconto': acconto,
      // ✅ Serializzazione corretta della lista di servizi usando ServizioExtraPdf.toMap()
      'servizi_extra': serviziExtra.map((s) => s.toMap()).toList(), 
      'menu': menu != null ? {
          'antipasto': menu!.antipasto.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'primo': menu!.primo.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'secondo': menu!.secondo.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'contorno': menu!.contorno.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'portata_generica': menu!.portataGenerica.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
      } : null,
      'firma_url': firmaUrl,
      
      'nome_menu_template': nomeMenuTemplate,
      
      // 🟢 INCLUSIONE DEI CAMPI PACCHETTO FISSO
      'is_pacchetto_fisso': isPacchettoFisso,
      'nome_pacchetto_fisso': nomePacchettoFisso,
      'descrizione_1': descrizionePacchettoFisso, 
      'descrizione_2': descrizionePacchettoFisso2, 
      'descrizione_3': descrizionePacchettoFisso3, 
      'proposta_gastronomica_pacchetto': propostaGastronomicaPacchetto,
      'prezzo_pacchetto_fisso': prezzoPacchettoFisso,
      
      // 🔴 FINE INCLUSIONE
      'orario_inizio_h': orarioInizioH,
      'orario_inizio_m': orarioInizioM,
      'orario_fine_h': orarioFineH,
      'orario_fine_m': orarioFineM,
      'firma_url_cliente_2': firmaUrlCliente2,
      
      'aperitivo_benvenuto': aperitivoBenvenuto,
      'buffet_dolci': buffetDolci,
      'buffet_dolci_note': buffetDolciNote,
      'pacchetto_label': pacchettoLabel,
      'pacchetto_costo': pacchettoCosto,
    };

    dlogPdfModels('DTO:toMap', {
      'hash': jhashPdfModels(out),
      'descr.has': [
        out['descrizione_1'] != null,
        out['descrizione_2'] != null,
        out['descrizione_3'] != null,
      ],
      'extra.len': (out['servizi_extra'] as List).length,
    });

    return out;
  }
}
