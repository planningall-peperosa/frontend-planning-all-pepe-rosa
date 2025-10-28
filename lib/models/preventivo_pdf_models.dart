// lib/models/preventivo_pdf_models.dart

import 'dart:convert';

class ClientePdf {
  final String ragioneSociale;
  final String referente;
  final String telefono01;
  final String mail;
  
  ClientePdf.fromMap(Map<String, dynamic> map) :
    ragioneSociale = map['ragione_sociale'] ?? '',
    referente = map['referente'] ?? '',
    telefono01 = map['telefono_01'] ?? '',
    mail = map['mail'] ?? '';
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
    fornitore = map['fornitore'] ?? {};
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
  
  MenuPdf.fromMap(Map<String, dynamic> map) :
    antipasto = (map['antipasto'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    primo = (map['primo'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    secondo = (map['secondo'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [],
    contorno = (map['contorno'] as List?)?.map((i) => PiattoPdf.fromMap(i)).toList() ?? [];
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
  final double? acconto;
  final List<ServizioExtraPdf> serviziExtra;
  final MenuPdf? menu;
  final String? firmaUrl;
  
  PreventivoCompletoPdf.fromMap(Map<String, dynamic> map) :
    id = map['preventivo_id'] ?? '',
    nomeEvento = map['nome_evento'] ?? '',
    // Pulizia e conversione in minuscolo immediata dello stato
    stato = ((map['stato'] as String? ?? map['status'] as String? ?? 'BOZZA').trim().toLowerCase()),
    firmaAcquisita = map['firma_acquisita'],
    confermato = map['confermato'],
    cliente = ClientePdf.fromMap(map['cliente'] ?? {}),
    dataEvento = map['data_evento'] is String ? DateTime.parse(map['data_evento']) : (map['data_evento'] as DateTime),
    tipoPasto = map['tipo_pasto'] ?? '',
    numeroOspiti = (map['numero_ospiti'] as num?)?.toInt() ?? 0,
    numeroBambini = (map['numero_bambini'] as num?)?.toInt() ?? 0,
    prezzoMenuPersona = (map['prezzo_menu_persona'] as num?)?.toDouble() ?? 0.0,
    prezzoMenuBambino = (map['prezzo_menu_bambino'] as num?)?.toDouble() ?? 0.0,
    noteMenuBambini = map['note_menu_bambini'],
    sconto = (map['sconto'] as num?)?.toDouble() ?? 0.0,
    noteSconto = map['note_sconto'],
    acconto = (map['acconto'] as num?)?.toDouble(),
    serviziExtra = (map['servizi_extra'] as List?)?.map((s) => ServizioExtraPdf.fromMap(s)).toList() ?? [],
    menu = map['menu'] != null ? MenuPdf.fromMap(map['menu']) : null,
    firmaUrl = map['firma_url'];

  // 🔑 AGGIUNTO: Metodo toMap per clonare l'oggetto e supportare l'aggiornamento dello stato
  Map<String, dynamic> toMap() {
    return {
      'preventivo_id': id,
      'nome_evento': nomeEvento,
      'stato': stato,
      'firma_acquisita': firmaAcquisita,
      'confermato': confermato,
      'cliente': {
        'ragione_sociale': cliente.ragioneSociale,
        'referente': cliente.referente,
        'telefono_01': cliente.telefono01,
        'mail': cliente.mail,
      },
      'data_evento': dataEvento,
      'tipo_pasto': tipoPasto,
      'numero_ospiti': numeroOspiti,
      'numero_bambini': numeroBambini,
      'prezzo_menu_persona': prezzoMenuPersona,
      'prezzo_menu_bambino': prezzoMenuBambino,
      'note_menu_bambini': noteMenuBambini,
      'sconto': sconto,
      'note_sconto': noteSconto,
      'acconto': acconto,
      'servizi_extra': serviziExtra.map((s) => {
          'ruolo': s.ruolo,
          'note': s.note,
          'prezzo': s.prezzo,
          'fornitore': s.fornitore,
      }).toList(),
      'menu': menu != null ? {
          'antipasto': menu!.antipasto.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'primo': menu!.primo.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'secondo': menu!.secondo.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
          'contorno': menu!.contorno.map((p) => {'nome': p.nome, 'custom': p.custom}).toList(),
      } : null,
      'firma_url': firmaUrl,
    };
  }
}