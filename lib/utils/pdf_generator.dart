// lib/utils/pdf_generator.dart

import 'dart:typed_data';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../models/preventivo_pdf_models.dart';
import 'download_utils.dart';

// Funzione di utilità per caricare il font (DEVE essere asincrona)
Future<Map<String, pw.Font>> _loadRobotoFonts() async {
  // Dovrai assicurarti di avere questi file nel percorso: assets/fonts/Roboto/
  const regularPath = "assets/fonts/Roboto/Roboto-Regular.ttf";
  const boldPath = "assets/fonts/Roboto/Roboto-Bold.ttf";

  pw.Font regular;
  pw.Font bold;

  try {
    // 1. Carica Regular (base)
    final regularData = await rootBundle.load(regularPath);
    regular = pw.Font.ttf(regularData);

    // 2. Carica Bold
    final boldData = await rootBundle.load(boldPath);
    bold = pw.Font.ttf(boldData);
    
    return {
      'regular': regular,
      'bold': bold,
    };
    
  } catch (e) {
    if (kDebugMode) {
      print("ATTENZIONE: Impossibile caricare i font Roboto ($regularPath o $boldPath). Usando fallback di sistema. $e");
    }
    // Fallback in caso di errore
    return {
      'regular': pw.Font.helvetica(),
      'bold': pw.Font.helveticaBold(),
    };
  }
}

Future<Map<String, String>> getDatiAzienda() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('configurazione')
        .doc('dati_azienda')
        .get();

    final data = doc.data() ?? {};

    return {
      // 🟢 MODIFICA: NOME AZIENDA TUTTO MAIUSCOLO
      "NOME_AZIENDA_1": (data['nome_azienda_1'] as String?)?.toUpperCase() ?? 'NOME NON CONFIGURATO',
      "NOME_AZIENDA_2": (data['nome_azienda_2'] as String?) ?? '',
      "INDIRIZZO_AZIENDA": (data['indirizzo_azienda'] as String?) ?? '',
      "EMAIL_AZIENDA": (data['email_azienda'] as String?) ?? '',
      "TELEFONO_AZIENDA": (data['telefono_azienda'] as String?) ?? '',
      "DETTAGLI_FISCALI": (data['dettagli_fiscali'] as String?) ?? '',
      "IBAN": (data['iban'] as String?) ?? '',
      "LOGO_URL": (data['logo_url'] as String?) ?? '',
    };
  } catch (e) {
    if (kDebugMode) print('ERRORE CARICAMENTO DATI AZIENDA DA FIRESTORE: $e');
    return {
      "NOME_AZIENDA_1": "ERRORE CARICAMENTO DATI",
      "LOGO_URL": "",
    };
  }
}


// =========================================================================
/* WIDGET BUILDER DI SUPPORTO E FUNZIONI AGGIUNTIVE */
// =========================================================================

// 🟢 NUOVA FUNZIONE DI FORMATTAZIONE ORARIO
String _formatTime(int? hour, int? minute) {
  if (hour == null || minute == null) return 'N/D';
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

// 🟢 NUOVA FUNZIONE: Pulisce il testo da caratteri problematici (apostrofi ricurvi, legature).
String _cleanTextForPdf(String text) {
  if (text.isEmpty) return text;
  String cleaned = text.replaceAll('’', '\'');
  cleaned = cleaned.replaceAll('ﬀ', 'ff');
  return cleaned;
}

// 🟢 NUOVA FUNZIONE CHIAVE: Converte la parte intera di un numero in lettere (Italiano, MAIUSCOLO)
String _convertiNumeroInLettere(int number) {
  if (number < 0 || number > 999999) {
    return 'IMPORTO NON VALIDO';
  }
  if (number == 0) return 'ZERO';

  const unit = ['', 'UNO', 'DUE', 'TRE', 'QUATTRO', 'CINQUE', 'SEI', 'SETTE', 'OTTO', 'NOVE'];
  const ten = ['', 'DIECI', 'VENTI', 'TRENTA', 'QUARANTA', 'CINQUANTA', 'SESSANTA', 'SETTANTA', 'OTTANTA', 'NOVANTA'];
  const complexTen = ['DIECI', 'UNDICI', 'DODICI', 'TREDICI', 'QUATTORDICI', 'QUINDICI', 'SEDICI', 'DICIASSETTE', 'DICIOTTO', 'DICIANNOVE'];

  String convertUnder100(int n) {
    if (n < 10) return unit[n];
    if (n < 20) return complexTen[n - 10];
    final t = ten[n ~/ 10];
    final u = unit[n % 10];
    if (n % 10 == 1 || n % 10 == 8) {
      if (t.isNotEmpty && (t.endsWith('A') || t.endsWith('I') || t.endsWith('E'))) {
        return t.substring(0, t.length - 1) + u;
      }
    }
    return t + u;
  }
  
  String convertUnder1000(int n) {
    if (n == 0) return '';
    final h = n ~/ 100;
    final r = n % 100;
    String result = '';
    if (h > 0) {
      if (h == 1) {
        result = 'CENTO';
      } else {
        result = unit[h] + 'CENTO';
      }
    }
    String rest = convertUnder100(r);
    if (result == 'CENTO' && (r % 10 == 1 || r % 10 == 8)) {
      if (r < 20 && (r == 11 || r == 18)) {
      } else {
        if (r % 10 == 1 || r % 10 == 8) {
          if (result.endsWith('O') && (rest.startsWith('U') || rest.startsWith('O'))) {
            result = result.substring(0, result.length - 1);
          }
        }
      }
    }
    String combined = (result + rest).replaceAll('CENTOUNO', 'CENTUNO');
    return combined.toUpperCase().trim();
  }
  
  String result = '';
  int migliaia = number ~/ 1000;
  int resto = number % 1000;
  if (migliaia > 0) {
    String migliaiaInLettere = convertUnder1000(migliaia);
    if (migliaia == 1) {
      result += 'MILLE';
    } else {
      if (migliaiaInLettere.endsWith('UNO') || migliaiaInLettere.endsWith('OTTO')) {
        migliaiaInLettere = migliaiaInLettere.substring(0, migliaiaInLettere.length - 1);
      }
      result += migliaiaInLettere + 'MILA';
    }
  }
  result += convertUnder1000(resto);
  if (result.endsWith('UNO') || result.endsWith('OTTO')) {
    result = result.substring(0, result.length - 1) + unit[number % 10];
  }
  return result.toUpperCase().trim();
}

// FUNZIONI HELPER PER WIDGETS

pw.Widget _buildDetailRow(String label, String? value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) {
  final displayValue = (value == null || value.isEmpty) ? 'N/D' : value;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3), // spazio ridotto
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: label, style: labelStyle),
          pw.TextSpan(text: ' $displayValue', style: valueStyle),
        ],
      ),
    ),
  );
}

pw.Widget _buildPremessa(pw.Widget child) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: child,
  );
}

pw.Widget _buildArticolo(String title, String content, pw.TextStyle style, pw.Font boldFont) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: boldFont)),
      pw.SizedBox(height: 4),
      pw.Text(content, style: style),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget _buildSubArticolo(String number, String content, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(left: 0, bottom: 4),
    child: pw.RichText(
      text: pw.TextSpan(
        style: style,
        children: [
          pw.TextSpan(text: '$number '),
          pw.TextSpan(text: content),
        ],
      ),
    ),
  );
}

// ====== SEZIONE MENU A PORTATE ======
List<pw.Widget> _buildMenuSection(
  MenuPdf menu,
  pw.TextStyle baseStyle,
  pw.TextStyle smallStyle,
  pw.TextStyle portataTitleStyle
) {
  final List<String> ordine = ['antipasto', 'primo', 'secondo', 'contorno', 'portata_generica'];
  final List<pw.Widget> widgets = [];

  final Map<String, List<PiattoPdf>> menuMapFromPdf = {
    'antipasto': menu.antipasto,
    'primo': menu.primo,
    'secondo': menu.secondo,
    'contorno': menu.contorno,
    'portata_generica': menu.portataGenerica,
  };
  
  final List<String> categorieConPiatti = [];
  for (final genere in ordine) {
    if (menuMapFromPdf[genere] != null && menuMapFromPdf[genere]!.isNotEmpty) {
      categorieConPiatti.add(genere);
    }
  }
  
  int renderedCount = 0;
  for (final genere in categorieConPiatti) {
    final piatti = menuMapFromPdf[genere];
    if (piatti != null && piatti.isNotEmpty) {
      renderedCount++;
      final isGeneric = (genere == 'portata_generica');
      final String titleText = genere.toUpperCase();
      final pw.TextStyle titleStyle = portataTitleStyle;
      
      if (!isGeneric) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(titleText, style: titleStyle),
          ),
        );
      }
      if (!isGeneric) {
        widgets.add(pw.SizedBox(height: 5));
      }
      
      widgets.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: piatti.map((item) {
            final String prefix = isGeneric ? '' : '- ';
            final String suffix = isGeneric ? '' : (item.custom ? ' (fuori menù)' : '');
            final String nomePulito = _cleanTextForPdf(item.nome);
            final nomeCompleto = prefix + nomePulito + suffix;
            return pw.Text(nomeCompleto, style: baseStyle, maxLines: 10);
          }).toList(),
        ),
      );

      if (renderedCount < categorieConPiatti.length) widgets.add(pw.SizedBox(height: 8));
    }
  }

  return widgets;
}

// ====== SEZIONE PACCHETTO FISSO (PAG. 1) ======



// SOSTITUIRE _buildPacchettoFissoContent con questo codice pulito
pw.Widget _buildPacchettoFissoContent(
  PreventivoCompletoPdf p,
  pw.TextStyle baseStyle,
  pw.TextStyle smallStyle,
  pw.Font boldFont,
) {
  final titleStyle = pw.TextStyle(
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
    decoration: pw.TextDecoration.underline,
    font: boldFont,
  );
  final paragraphStyle = baseStyle.copyWith(fontSize: 9);

  // prezzo senza simbolo €
  final nf = NumberFormat('#,##0.00', 'it_IT');

  final titolo  = (p.nomePacchettoFisso ?? '').trim().isEmpty
      ? (p.nomeMenuTemplate ?? 'Pacchetto Fisso')
      : p.nomePacchettoFisso!.trim();

  // I dati dovrebbero arrivare separati qui
  final descr1  = (p.descrizionePacchettoFisso  ?? '').trim();
  final descr2  = (p.descrizionePacchettoFisso2 ?? '').trim();
  final descr3  = (p.descrizionePacchettoFisso3 ?? '').trim();
  final proposta= (p.propostaGastronomicaPacchetto ?? '').trim();

  // ⬇️ Box grigio con solo prezzo + "e u r o" 
  final prezzoBox = pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Prezzo pacchetto: ${nf.format(p.prezzoPacchettoFisso)}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: boldFont),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'e u r o',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 10, letterSpacing: 2, color: PdfColors.grey700, font: baseStyle.font),
        ),
      ],
    ),
  );

  return pw.Container(
    width: 160 * PdfPageFormat.mm,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // 1. Titolo
        pw.Text('Proposta: $titolo', style: titleStyle),
        pw.SizedBox(height: 8),

        // 2. Descrizione 1
        if (descr1.isNotEmpty) pw.Text(descr1, style: paragraphStyle),
        if (descr1.isNotEmpty) pw.SizedBox(height: 6),

        // 3. Descrizione 2
        if (descr2.isNotEmpty) pw.Text(descr2, style: paragraphStyle),
        if (descr2.isNotEmpty) pw.SizedBox(height: 6),

        // 4. Proposta Gastronomica
        if (proposta.isNotEmpty)
          pw.Text(proposta, style: paragraphStyle, textAlign: pw.TextAlign.justify),
        if (proposta.isNotEmpty) pw.SizedBox(height: 8),

        // 5. Box Grigio (Prezzo)
        prezzoBox,
        
        // 6. 🚨 LAYOUT CORRETTO: Descrizione 3 SOTTO il box grigio
        if (descr3.isNotEmpty) pw.SizedBox(height: 8),
        if (descr3.isNotEmpty) 
          pw.Text(
            descr3, 
            style: smallStyle.copyWith(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.black),
            textAlign: pw.TextAlign.left
          ),
      ],
    ),
  );
}

pw.Widget _buildServiziTable(List<ServizioExtraPdf> servizi, pw.TextStyle baseStyle, pw.TextStyle smallStyle, pw.Font boldFont) {
  const tableHeaders = ['Servizio', 'Fornitore', 'Prezzo'];

  final List<List<pw.Widget>> data = servizi.map((s) {
    final fornitoreNome = s.fornitore['ragione_sociale'] ?? '';
    return [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.ruolo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: boldFont)),
          if (s.note.isNotEmpty) pw.Text(s.note, style: smallStyle),
        ],
      ),
      pw.Text(fornitoreNome, style: baseStyle),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Euro ${s.prezzo.toStringAsFixed(2)}', style: baseStyle),
      ),
    ];
  }).toList();

  return pw.Table(
    defaultColumnWidth: const pw.IntrinsicColumnWidth(),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: tableHeaders
            .map((header) => pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(header, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black, font: boldFont)),
                ))
            .toList(),
      ),
      ...data.map(
        (widgets) => pw.TableRow(
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
          children: widgets.map((w) => pw.Container(padding: const pw.EdgeInsets.all(8), child: w)).toList(),
        ),
      ),
    ],
    border: pw.TableBorder.all(color: PdfColors.grey300),
  );
}

pw.Widget _buildCostiTable(
  PreventivoCompletoPdf p,
  Map<String, double> costi,
  pw.TextStyle baseStyle,
  pw.TextStyle valStyle,
  pw.TextStyle smallStyle,
  pw.Font boldFont,
) {
  final rows = <List<pw.Widget>>[];

  if (p.isPacchettoFisso == true) {
    // Riga unica del pacchetto fisso
    rows.add(
      _costiRow(
        'Pacchetto Fisso',
        '(Costo base)',
        costi['costo_pacchetto_fisso']!,
        baseStyle,
        valStyle,
        smallStyle,
        boldFont,
      ),
    );
  } else {
    // Menù a portate (dettaglio adulti/bambini + eventuale pacchetto welcome/dolci)
    final nAdulti = (p.numeroOspiti - p.numeroBambini).clamp(0, p.numeroOspiti);
    final nBimbi = p.numeroBambini;
    final prezzoAdulto = p.prezzoMenuPersona;
    final prezzoBimbo = p.prezzoMenuBambino;
    final double costoPacchetto = p.pacchettoCosto;
    final String labelPacchetto = p.pacchettoLabel;
    final bool mostraPacchetto = costoPacchetto > 0 && labelPacchetto.isNotEmpty;

    if (mostraPacchetto) {
      final double unitPrice = (costoPacchetto / p.numeroOspiti).clamp(0.0, double.infinity);
      final String details = '(${p.numeroOspiti} x Euro ${unitPrice.toStringAsFixed(2)})';
      rows.add(
        _costiRow(
          labelPacchetto,
          details,
          costoPacchetto,
          baseStyle,
          valStyle,
          smallStyle,
          boldFont,
        ),
      );
    }

    rows.addAll([
      _costiRow(
        'Menù Adulti',
        '(${nAdulti} x Euro ${prezzoAdulto.toStringAsFixed(2)})',
        costi['costo_menu_adulti']!,
        baseStyle,
        valStyle,
        smallStyle,
        boldFont,
      ),
      _costiRow(
        'Menù Bambini',
        '(${nBimbi} x Euro ${prezzoBimbo.toStringAsFixed(2)})',
        costi['costo_menu_bambini']!,
        baseStyle,
        valStyle,
        smallStyle,
        boldFont,
      ),
    ]);
  }

  rows.addAll([
    _costiRow('Servizi Extra', '', costi['costo_servizi']!, baseStyle, valStyle, smallStyle, boldFont),
    _costiRow('Subtotale', '', costi['subtotale']!, baseStyle, valStyle, smallStyle, boldFont, isBold: true),
    _costiRow('Sconto', '', -costi['sconto']!, baseStyle, valStyle, smallStyle, boldFont, isDiscount: true),
    _costiRow('Totale', '', costi['totale_finale']!, baseStyle, valStyle, smallStyle, boldFont, isTotal: true),
  ]);

  if (costi['acconto'] != null && (costi['acconto'] ?? 0) > 0) {
    rows.addAll([
      _costiRow('Acconto', '', -costi['acconto']!, baseStyle, valStyle, smallStyle, boldFont, isDiscount: true),
      _costiRow('Saldo', '', costi['saldo']!, baseStyle, valStyle, smallStyle, boldFont, isTotal: true),
    ]);
  }

  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FlexColumnWidth(1.5),
    },
    border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
    children: rows.map((r) => pw.TableRow(children: r)).toList(),
  );
}

List<pw.Widget> _costiRow(
  String label,
  String details,
  double amount,
  pw.TextStyle baseStyle,
  pw.TextStyle valStyle,
  pw.TextStyle smallStyle,
  pw.Font boldFont, {
  bool isBold = false,
  bool isTotal = false,
  bool isDiscount = false,
}) {
  final labelStyle =
      isTotal ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.black, font: boldFont) : baseStyle;
  final priceStyle = isTotal
      ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.black, font: boldFont)
      : (isDiscount ? pw.TextStyle(color: PdfColors.red, font: baseStyle.font) : valStyle);

  final priceString = amount < 0 ? '- Euro ${(-amount).toStringAsFixed(2)}' : 'Euro ${amount.toStringAsFixed(2)}';

  return [
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: labelStyle),
          if (details.isNotEmpty) pw.Text(details, style: smallStyle),
        ],
      ),
    ),
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(priceString, style: priceStyle)),
    ),
  ];
}


// 🔑 FUNZIONE CHIAVE: Recupera lo stato aggiornato (e pulito) direttamente da Firestore
Future<String> _recuperaStatoAggiornato(String preventivoId, String? firmaUrlPassata) async {
  if (preventivoId.isEmpty) return 'bozza';
  try {
    final doc = await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).get();
    final data = doc.data() ?? {};
    final statusLettuRaw = data['status'] as String? ?? data['stato'] as String? ?? '';
    final statoLettu = statusLettuRaw.trim().toLowerCase();
    
    final firmaPresenteInDb = (data['firma_url'] as String?)?.isNotEmpty ?? false;
    final firma2PresenteInDb = (data['firma_url_cliente_2'] as String?)?.isNotEmpty ?? false;
    
    if (statoLettu == 'confermato' || firmaPresenteInDb || firma2PresenteInDb || (firmaUrlPassata?.isNotEmpty ?? false)) {
      if (kDebugMode) print('[DEBUG STATO DB] STATO RISOLTO: CONFERMATO (Status DB o Firma OK).');
      return 'confermato';
    }
    if (kDebugMode) print('[DEBUG STATO DB] STATO RISOLTO: BOZZA (Nessuna conferma esplicita).');
    return statoLettu.isNotEmpty ? statoLettu : 'bozza';
  } catch (e) {
    if (kDebugMode) print('[DEBUG STATO DB] Errore lettura stato: $e');
    return 'bozza';
  }
}


// 🔑 FUNZIONE PRINCIPALE: Generazione PDF
Future<Uint8List> generaPdfDaDatiDart(PreventivoCompletoPdf preventivoObj, String statoFinaleRisolto) async {
  final fonts = await _loadRobotoFonts();
  final baseFont = fonts['regular']!;
  final boldFont = fonts['bold']!;
  final fallbackList = <pw.Font>[];

  final datiAzienda = await getDatiAzienda();

  final preventivoObjConStatoFresco = PreventivoCompletoPdf.fromMap({
    ...preventivoObj.toMap(),
    'stato': statoFinaleRisolto,
  });


  final p = preventivoObjConStatoFresco; // Alias per brevità
  if (kDebugMode) {
    print('--- DATI PACCHETTO FISSO RICEVUTI ---');
    print('DB KEY: is_pacchetto_fisso: ${p.isPacchettoFisso}');
    print('DB KEY: nome_pacchetto_fisso: ${p.nomePacchettoFisso}');
    print('DB KEY: descrizione_1: [${p.descrizionePacchettoFisso}]');
    print('DB KEY: descrizione_2: [${p.descrizionePacchettoFisso2}]');
    print('DB KEY: descrizione_3: [${p.descrizionePacchettoFisso3}]');
    print('--- FINE DATI RICEVUTI ---');
  }

  if (kDebugMode) {
    final dateFormatterPrint = DateFormat('dd/MM/yyyy');
    final dataEvento = dateFormatterPrint.format(preventivoObjConStatoFresco.dataEvento);
    print('====================================================');
    print('[PDF STATUS DEBUG] STATO INIETTATO E UTILIZZATO: "${statoFinaleRisolto.toUpperCase()}"');
    print('Cliente: ${preventivoObjConStatoFresco.cliente.ragioneSociale}');
    print('Data Evento: $dataEvento');
    print('isPacchettoFisso: ${preventivoObjConStatoFresco.isPacchettoFisso}');
    print('PrezzoPacchettoFisso: ${preventivoObjConStatoFresco.prezzoPacchettoFisso}');
    print('====================================================');
  }

  // Stili base
  final baseStyle = pw.TextStyle(
    fontSize: 10,
    color: PdfColor.fromInt(0xFF222222),
    font: baseFont,
    fontFallback: fallbackList,
  );

  final mutedStyle = pw.TextStyle(color: PdfColors.grey600, fontSize: 11, font: baseFont, fontFallback: fallbackList);
  final smallStyle = pw.TextStyle(color: PdfColors.grey600, fontSize: 11, font: baseFont, fontFallback: fallbackList);
  final labelStyle = pw.TextStyle(color: PdfColors.grey600, fontSize: 12, font: baseFont, fontFallback: fallbackList);
  final valStyle = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    fontSize: 12,
    color: PdfColor.fromInt(0xFF222222),
    font: boldFont,
    fontFallback: fallbackList,
  );

  final pdf = pw.Document(
    title: 'Preventivo ${preventivoObjConStatoFresco.nomeEvento}',
    pageMode: PdfPageMode.outlines,
  );

  final format = PdfPageFormat.a4.copyWith(
    marginBottom: 22 * PdfPageFormat.mm,
    marginLeft: 16 * PdfPageFormat.mm,
    marginRight: 16 * PdfPageFormat.mm,
    marginTop: 22 * PdfPageFormat.mm,
  );

  final now = DateTime.now();
  final dateFormatter = DateFormat('dd/MM/yyyy', 'it_IT');

  datiAzienda["LUOGO_DATA"] = "Nettuno, ${dateFormatter.format(now)}";
  final String logoDataLuogo = datiAzienda["LUOGO_DATA"]!;

  // Calcoli
  final totOspiti = preventivoObjConStatoFresco.numeroOspiti;
  final numBambini = preventivoObjConStatoFresco.numeroBambini;
  final numAdulti = (totOspiti - numBambini).clamp(0, totOspiti);

  final costoMenuAdulti = (preventivoObjConStatoFresco.prezzoMenuPersona * numAdulti);
  final costoMenuBambini = (preventivoObjConStatoFresco.prezzoMenuBambino * numBambini);

  final List<ServizioExtraPdf> serviziExtraFiltrati = preventivoObjConStatoFresco.serviziExtra;
  final costoServizi = serviziExtraFiltrati.fold(0.0, (sum, s) => sum + s.prezzo);

  // Costo principale in base al tipo
  final bool pacchettoFisso = preventivoObjConStatoFresco.isPacchettoFisso == true;
  final double costoPacchettoFisso = preventivoObjConStatoFresco.prezzoPacchettoFisso; // decisione finale

  // Subtotale e totale
  final double subtotale = pacchettoFisso
      ? (costoPacchettoFisso + costoServizi)
      : (costoMenuAdulti + costoMenuBambini + costoServizi + preventivoObjConStatoFresco.pacchettoCosto);

  final sconto = preventivoObjConStatoFresco.sconto;
  final totaleFinale = (subtotale - sconto).clamp(0.0, double.infinity);

  final Map<String, double> costi = {
    "costo_pacchetto_fisso": costoPacchettoFisso,
    "costo_welcome_dolci": preventivoObjConStatoFresco.pacchettoCosto,
    "costo_menu_adulti": costoMenuAdulti,
    "costo_menu_bambini": costoMenuBambini,
    "costo_servizi": costoServizi,
    "subtotale": subtotale,
    "totale_finale": totaleFinale,
    "sconto": sconto,
    "acconto": preventivoObjConStatoFresco.acconto ?? 0.0,
    "saldo": (totaleFinale - (preventivoObjConStatoFresco.acconto ?? 0.0)).clamp(0.0, double.infinity),
  };

  final tipo = preventivoObjConStatoFresco.tipoPasto.trim().toLowerCase();
  final tipoPastoLabel = tipo == "pranzo" ? "Pranzo" : (tipo == "cena" ? "Cena" : "");
  final invitatiLabel = "Invitati: Adulti $numAdulti - Bambini $numBambini";

  // Firma & Logo
  Uint8List firmaBytes = Uint8List(0);
  Uint8List firma2Bytes = Uint8List(0);

  if (preventivoObjConStatoFresco.firmaUrl != null && preventivoObjConStatoFresco.firmaUrl!.isNotEmpty) {
    if (kDebugMode) print('[Firma PDF] Tentativo di download firma 1 (composta) da: ${preventivoObjConStatoFresco.firmaUrl!}');
    firmaBytes = await scaricaFirmaDaStorage(preventivoObjConStatoFresco.firmaUrl!);
    if (kDebugMode) print('[Firma Download] Download completato: ${firmaBytes.length} bytes.');
  }
  if (preventivoObjConStatoFresco.firmaUrlCliente2 != null && preventivoObjConStatoFresco.firmaUrlCliente2!.isNotEmpty) {
    if (kDebugMode) {
      print('[Firma PDF] Tentativo di download firma 2 (cliente) da: ${preventivoObjConStatoFresco.firmaUrlCliente2!}');
      print('[Firma DEBUG] Lunghezza URL Firma 2: ${preventivoObjConStatoFresco.firmaUrlCliente2!.length}');
    }
    firma2Bytes = await scaricaFirmaDaStorage(preventivoObjConStatoFresco.firmaUrlCliente2!);
    if (kDebugMode) print('[Firma Download] Download completato: ${firma2Bytes.length} bytes.');
    if (kDebugMode) print('[Firma Download] Esito Firma 2: ${firma2Bytes.isNotEmpty ? "Download OK" : "Download Fallito (0 bytes)"}');
  }

  Uint8List logoBytes = Uint8List(0);
  if (datiAzienda["LOGO_URL"]!.isNotEmpty) {
    if (kDebugMode) print('[Logo PDF] Tentativo di download logo.');
    logoBytes = await scaricaFirmaDaStorage(datiAzienda["LOGO_URL"]!);
    if (kDebugMode) print('[Firma Download] Download completato: ${logoBytes.length} bytes.');
  }

  // Header/Footer per pagine 2+ 
  pw.PageTheme _getPageTheme(pw.TextStyle style, Uint8List? logoBytes) {
    return pw.PageTheme(
      pageFormat: format,
      buildBackground: (pw.Context context) {
        return pw.FullPage(
          ignoreMargins: true,
          child: pw.Column(
            children: [
              pw.Container(
                alignment: pw.Alignment.topLeft,
                padding: const pw.EdgeInsets.only(left: 16 * PdfPageFormat.mm, top: 10 * PdfPageFormat.mm), // un filo meno
                child: (logoBytes != null && logoBytes.isNotEmpty)
                    ? pw.Image(pw.MemoryImage(logoBytes), height: 16)
                    : pw.Text(logoDataLuogo, style: style.copyWith(fontSize: 9)),
              ),
              pw.Spacer(),
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.only(bottom: 14), // un filo meno
                child: pw.Text('Pagina ${context.pageNumber} di ${context.pagesCount}', style: style),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // PAGINA 1
  // =========================================================================

  final pw.TextStyle baseStyleFinal = pw.TextStyle(
    fontSize: 9,
    color: PdfColor.fromInt(0xFF222222),
    font: baseFont,
    fontFallback: fallbackList,
  );
  final pw.TextStyle portataTitleStyleFinal = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.black,
    font: boldFont,
  );
  final pw.TextStyle buffetNoteContentStyle = pw.TextStyle(
    fontSize: 8,
    color: PdfColor.fromInt(0xFF222222),
    font: baseFont,
    fontFallback: fallbackList,
  );
  final pw.TextStyle menuTitleStyle = pw.TextStyle(
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
    decoration: pw.TextDecoration.underline,
    font: boldFont,
  );

  final bool hasAperitivo = preventivoObjConStatoFresco.aperitivoBenvenuto;
  final bool hasBuffetDolci = preventivoObjConStatoFresco.buffetDolci;
  final bool hasMenuBambiniNotes = preventivoObjConStatoFresco.noteMenuBambini != null && preventivoObjConStatoFresco.noteMenuBambini!.trim().isNotEmpty;

  final List<pw.Widget> menuWidgets = preventivoObjConStatoFresco.menu != null
      ? _buildMenuSection(preventivoObjConStatoFresco.menu!, baseStyleFinal, smallStyle, portataTitleStyleFinal)
      : <pw.Widget>[];

  final bool isMenuEmpty = menuWidgets.isEmpty;

  pdf.addPage(
    pw.Page(
      pageFormat: format,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoBytes.isNotEmpty)
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8, top: 2), // meno spazio
                  child: pw.Image(pw.MemoryImage(logoBytes), height: 40),
                ),
              ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      datiAzienda['NOME_AZIENDA_1']!,
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5, font: boldFont),
                    ),
                    if (datiAzienda['NOME_AZIENDA_2'] != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2), // meno spazio
                        child: pw.Text(datiAzienda['NOME_AZIENDA_2']!, style: smallStyle),
                      ),
                    if (datiAzienda['INDIRIZZO_AZIENDA'] != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(datiAzienda['INDIRIZZO_AZIENDA']!, style: smallStyle),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            if (datiAzienda['EMAIL_AZIENDA'] != null)
                              pw.TextSpan(text: 'Email: ${datiAzienda['EMAIL_AZIENDA']}', style: smallStyle),
                            if (datiAzienda['EMAIL_AZIENDA'] != null && datiAzienda['TELEFONO_AZIENDA'] != null)
                              pw.TextSpan(text: ' - ', style: smallStyle),
                            if (datiAzienda['TELEFONO_AZIENDA'] != null)
                              pw.TextSpan(text: 'Tel: ${datiAzienda['TELEFONO_AZIENDA']}', style: smallStyle),
                          ],
                        ),
                      ),
                    ),
                    if (datiAzienda['DETTAGLI_FISCALI'] != null)
                      pw.Text(datiAzienda['DETTAGLI_FISCALI']!, style: smallStyle),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PREVENTIVO', style: smallStyle.copyWith(color: PdfColors.grey600)),
                    if (preventivoObjConStatoFresco.id.isNotEmpty)
                      pw.Text('ID: ${preventivoObjConStatoFresco.id}', style: smallStyle.copyWith(color: PdfColors.grey600)),
                    pw.SizedBox(height: 2), // meno spazio
                    pw.Text(
                      (statoFinaleRisolto == 'confermato') ? 'CONFERMATO' : 'BOZZA',
                      style: smallStyle.copyWith(
                        color: (statoFinaleRisolto == 'confermato') ? PdfColors.green700 : PdfColors.red700,
                        font: baseFont,
                      ),
                    ),
                    pw.Text(logoDataLuogo, style: smallStyle.copyWith(color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6), // meno spazio sopra il divider
            pw.Divider(height: 10, borderStyle: pw.BorderStyle.dashed), // divider più compatto
            pw.SizedBox(height: 6), // meno spazio sotto il divider
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8), // padding ridotto
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Cliente', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: boldFont)),
                        pw.SizedBox(height: 6),
                        _buildDetailRow('Ragione sociale:', preventivoObjConStatoFresco.cliente.ragioneSociale, labelStyle, valStyle),
                        _buildDetailRow('Codice Fiscale:', preventivoObjConStatoFresco.cliente.codiceFiscale, labelStyle, valStyle),
                        _buildDetailRow('Telefono:', preventivoObjConStatoFresco.cliente.telefono01, labelStyle, valStyle),
                        _buildDetailRow('Email:', preventivoObjConStatoFresco.cliente.mail, labelStyle, valStyle),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8), // padding ridotto
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Evento', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: boldFont)),
                        pw.SizedBox(height: 6),
                        _buildDetailRow('Nome evento:', preventivoObjConStatoFresco.nomeEvento, labelStyle, valStyle),
                        _buildDetailRow('Data:', '${dateFormatter.format(preventivoObjConStatoFresco.dataEvento)} - $tipoPastoLabel', labelStyle, valStyle),
                        if (!preventivoObjConStatoFresco.isPacchettoFisso)
                          _buildDetailRow(
                            'Orari evento:',
                            '${_formatTime(preventivoObjConStatoFresco.orarioInizioH, preventivoObjConStatoFresco.orarioInizioM)} - ${_formatTime(preventivoObjConStatoFresco.orarioFineH, preventivoObjConStatoFresco.orarioFineM)}',
                            labelStyle,
                            valStyle,
                          ),
                        if (!preventivoObjConStatoFresco.isPacchettoFisso)
                          pw.Text(invitatiLabel, style: valStyle),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6), // meno spazio prima del paragrafo
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, bottom: 10), // spazi ridotti
              child: pw.Text(
                'Gentile Cliente, riportiamo di seguito la Ns migliore offerta nella quale proponiamo una serie di opzioni per i servizi da Lei richiesti, secondo quanto riportato nel listino menù allegato sub ALL. 1. I termini e le condizioni per l\'erogazione dei servizi sono riportati in calce alle opzioni della presente offerta, che dovrà essere da Lei sottoscritta per accettazione.',
                style: baseStyleFinal,
              ),
            ),
            pw.SizedBox(height: 4), // meno spazio prima di "Proposta"

            // Corpo centrale Pagina 1
            if (preventivoObjConStatoFresco.isPacchettoFisso)
              _buildPacchettoFissoContent(preventivoObjConStatoFresco, baseStyleFinal, smallStyle, boldFont)
            else
              pw.Container(
                width: 160 * PdfPageFormat.mm,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Proposta: ${preventivoObjConStatoFresco.nomeMenuTemplate != null && preventivoObjConStatoFresco.nomeMenuTemplate!.isNotEmpty ? preventivoObjConStatoFresco.nomeMenuTemplate! : 'Menu Personalizzato'}',
                      style: menuTitleStyle,
                    ),
                    pw.SizedBox(height: 8),
                    if (hasAperitivo) ...[
                      pw.Text('APERITIVO DI BENVENUTO', style: portataTitleStyleFinal),
                      if (!isMenuEmpty) pw.SizedBox(height: 6),
                    ],
                    ...menuWidgets,
                    if (hasBuffetDolci) ...[
                      pw.SizedBox(height: 8),
                      pw.Text('BUFFET DI DOLCI', style: portataTitleStyleFinal),
                      if (preventivoObjConStatoFresco.buffetDolciNote != null && preventivoObjConStatoFresco.buffetDolciNote!.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text('Note: ${preventivoObjConStatoFresco.buffetDolciNote}', style: buffetNoteContentStyle),
                        ),
                    ],
                    if (hasMenuBambiniNotes)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 8),
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(text: 'MENÙ BAMBINI', style: portataTitleStyleFinal),
                              pw.TextSpan(text: '\n${preventivoObjConStatoFresco.noteMenuBambini}', style: buffetNoteContentStyle),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            pw.Spacer(),
            pw.SizedBox(height: 1),
            pw.NewPage(),
          ],
        );
      },
    ),
  );

  // =========================================================================
  // PAGINA 2: Servizi Inclusi & Servizi Extra
  // =========================================================================
  pdf.addPage(
    pw.Page(
      pageTheme: _getPageTheme(baseStyle, logoBytes),
      build: (pw.Context context) {
        final pw.TextStyle serviziTitleStyle = pw.TextStyle(fontSize: 16, font: boldFont);
        final pw.TextStyle serviziIncludedStyle = buffetNoteContentStyle;
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Servizi inclusi in ciascuna proposta:', style: serviziTitleStyle),
            pw.SizedBox(height: 8),
            pw.Text(
              'mis en place correlata all\'opzione prescelta; location esclusiva; utilizzo area piscina (balneazione condizionata alla presenza di bagnino).',
              style: serviziIncludedStyle,
            ),
            pw.SizedBox(height: 18),
            pw.Text('Servizi extra', style: serviziTitleStyle),
            pw.SizedBox(height: 10),
            if (serviziExtraFiltrati.isNotEmpty) _buildServiziTable(serviziExtraFiltrati, baseStyle, smallStyle, boldFont),
            pw.SizedBox(height: 18),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text('N.B. I prezzi proposti sono da intendersi sempre IVA esclusa.', style: serviziIncludedStyle),
            ),
            pw.Spacer(),
            pw.NewPage(),
          ],
        );
      },
    ),
  );

  // =========================================================================
  // PAGINA 3: Riepilogo Costi
  // =========================================================================
  pdf.addPage(
    pw.Page(
      pageTheme: _getPageTheme(baseStyle, logoBytes),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // --- Note integrative (se presenti) ---
                  if (preventivoObjConStatoFresco.noteIntegrative != null &&
                      preventivoObjConStatoFresco.noteIntegrative!.trim().isNotEmpty) ...[
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Note integrative', style: pw.TextStyle(fontSize: 14, font: boldFont)),
                          pw.SizedBox(height: 6),
                          pw.Text(preventivoObjConStatoFresco.noteIntegrative!, style: baseStyle),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 12),
                  ],

                  // Titolo sezione
                  pw.Text('Riepilogo costi', style: pw.TextStyle(fontSize: 16, font: boldFont)),
                ],
              ),
            ),

            pw.SizedBox(height: 10),

            _buildCostiTable(
              preventivoObjConStatoFresco,
              costi,
              baseStyle,
              valStyle,
              smallStyle,
              boldFont,
            ),

            pw.SizedBox(height: 16),

            if (preventivoObjConStatoFresco.noteSconto != null &&
                preventivoObjConStatoFresco.noteSconto!.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text('Note sconto: ${preventivoObjConStatoFresco.noteSconto}', style: smallStyle),
              ),

            if (datiAzienda['IBAN'] != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text('Coordinate bancarie: IBAN ${datiAzienda['IBAN']}', style: smallStyle),
              ),

            pw.Spacer(),
            pw.NewPage(),
          ],
        );
      },
    ),
  );

  // =========================================================================
  // PAGINA 4 (Contratto 1 + 2)
  // =========================================================================
  pdf.addPage(
    pw.Page(
      pageTheme: _getPageTheme(baseStyleFinal, logoBytes),
      build: (pw.Context context) {
        final prezzoAdultoIntero = preventivoObjConStatoFresco.prezzoMenuPersona.toInt();
        final prezzoBambinoIntero = preventivoObjConStatoFresco.prezzoMenuBambino.toInt();
        final prezzoAdultoLettere = _convertiNumeroInLettere(prezzoAdultoIntero);
        final prezzoBambinoLettere = _convertiNumeroInLettere(prezzoBambinoIntero);
        
        // 🔧 MODIFICA: DURATA -> "come da pacchetto" se pacchetto fisso
        // 🔧 MODIFICA: DURATA -> frase unica "negli orari indicati nel pacchetto" se pacchetto fisso
        final bool isPacchetto = preventivoObjConStatoFresco.isPacchettoFisso == true;

        final List<pw.InlineSpan> durataSpans = isPacchetto
            ? <pw.InlineSpan>[
                pw.TextSpan(text: 'Le Parti convengono che l\'EVENTO si terrà il '),
                pw.TextSpan(
                  text: dateFormatter.format(preventivoObjConStatoFresco.dataEvento),
                  style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont),
                ),
                pw.TextSpan(text: ', negli orari indicati nel pacchetto. Per lo svolgimento dell\'EVENTO, il PREPONENTE concederà al CLIENTE l\'uso esclusivo dei locali del PEPE ROSA negli orari sopra indicati. Qualora l\'evento si protraesse oltre l\'orario concordato, dopo mezz\'ora di tolleranza, il CLIENTE dovrà corrispondere al PREPONENTE la somma di Euro 250, oltre IVA se dovuta, per ogni ulteriore ora di ritardo, fino ad un massimo di 2 ore.'),
              ]
            : <pw.InlineSpan>[
                pw.TextSpan(text: 'Le Parti convengono che l\'EVENTO si terrà il '),
                pw.TextSpan(
                  text: dateFormatter.format(preventivoObjConStatoFresco.dataEvento),
                  style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont),
                ),
                pw.TextSpan(text: ' dalle ore '),
                pw.TextSpan(
                  text: _formatTime(preventivoObjConStatoFresco.orarioInizioH, preventivoObjConStatoFresco.orarioInizioM),
                  style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont),
                ),
                pw.TextSpan(text: ' alle ore '),
                pw.TextSpan(
                  text: _formatTime(preventivoObjConStatoFresco.orarioFineH, preventivoObjConStatoFresco.orarioFineM),
                  style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont),
                ),
                pw.TextSpan(text: '. Per lo svolgimento dell\'EVENTO, il PREPONENTE concederà al CLIENTE l\'uso esclusivo dei locali del PEPE ROSA negli orari sopra indicati. Qualora l\'evento si protraesse oltre l\'orario concordato, dopo mezz\'ora di tolleranza, il CLIENTE dovrà corrispondere al PREPONENTE la somma di Euro 250, oltre IVA se dovuta, per ogni ulteriore ora di ritardo, fino ad un massimo di 2 ore.'),
              ];


        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CONDIZIONI GENERALI', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, font: boldFont)),
              pw.SizedBox(height: 8),

              _buildPremessa(pw.Text('A) Il sig. Gabriele Castellano (d\'ora in avanti, il "PREPONENTE") è un imprenditore individuale operante nel settore della ristorazione, banqueting, organizzazione eventi e home food.', style: baseStyleFinal)),
              _buildPremessa(pw.Text('B) Il PREPONENTE possiede idonea organizzazione e specifiche competenze per le attività oggetto del presente accordo; inoltre, il PREPONENTE è in possesso di tutte le necessarie autorizzazioni commerciali, amministrative ed igienico-sanitarie per lo svolgimento delle suddette attività.', style: baseStyleFinal)),
              _buildPremessa(
                pw.RichText(
                  text: pw.TextSpan(
                    style: baseStyleFinal,
                    children: [
                      pw.TextSpan(text: 'C) Il/La sig./sig.ra '),
                      pw.TextSpan(text: preventivoObjConStatoFresco.cliente.ragioneSociale ?? '__________________________________', style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont)),
                      pw.TextSpan(text: ' C.F. '),
                      pw.TextSpan(text: preventivoObjConStatoFresco.cliente.codiceFiscale ?? '____________________________', style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont)),
                      pw.TextSpan(text: ' - (di seguito, il "CLIENTE") intende avvalersi dei servizi offerti dal PREPONENTE, così come selezionati nella presente offerta, in occasione dell\'evento che si terrà in data '),
                      pw.TextSpan(text: dateFormatter.format(preventivoObjConStatoFresco.dataEvento), style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont)),
                      pw.TextSpan(text: ', presso i locali del PEPE ROSA, siti in 00048 Nettuno (RM), Via dello Scopone, n. 45 (di seguito, l\'"EVENTO").'),
                    ],
                  ),
                ),
              ),
              _buildPremessa(pw.Text('D) Il PREPONENTE ha interesse a fornire i propri servizi al Cliente e a concedergli la disponibilità esclusiva dei locali nella data prescelta.', style: baseStyleFinal)),
              pw.SizedBox(height: 10),
              pw.Text('Tanto premesso, si conviene e stipula quanto segue.', style: baseStyleFinal.copyWith(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),

              _buildArticolo('1. PREMESSE E SCELTA DEI SERVIZI.', 'Le premesse e l\'indicazione dei servizi (opzioni menù e servizi extra) di cui sopra costituiscono parte integrale e sostanziale del presente accordo.', baseStyleFinal, boldFont),
              _buildArticolo('2. OGGETTO DELL\'INCARICO.', 'Con il presente Contratto, il CLIENTE affida al PREPONENTE, che accetta, l\'incarico di fornire i servizi di organizzazione dell\'Evento, preparazione e somministrazione di alimenti e bevande, nonchè gli ulteriori servizi extra richiesti dal Cliente, ai prezzi sopra indicati.', baseStyleFinal, boldFont),

              pw.Text('3. PRESTAZIONE DEI SERVIZI.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: boldFont)),
              _buildSubArticolo('3.1', 'Il PREPONENTE fornirà i servizi affidati dal CLIENTE con organizzazione dei mezzi necessari e con gestione a proprio rischio, secondo gli standards qualitativi del settore.', baseStyleFinal),
              _buildSubArticolo('3.2', 'Il PREPONENTE si occuperà dell\'assunzione del personale necessario al regolare funzionamento del servizio di banqueting.', baseStyleFinal),
              _buildSubArticolo('3.3', 'Il PREPONENTE provvederà all\'approvvigionamento delle derrate alimentari secondo le opzioni scelte dal Cliente. Inoltre, curerà l\'arredo dei locali con tavoli, sedie, tovaglie, posate e quanto necessario per lo svolgimento dell\'EVENTO.', baseStyleFinal),
              _buildSubArticolo('3.4', 'Il CLIENTE si farà carico di adempiere a tutti gli eventuali oneri ed obblighi con la SIAE, qualora nei locali si diffonda musica. Il CLIENTE dichiara pertanto di essere tenuto a garantire e manlevare il PREPONENTE da qualsiasi conseguenza pregiudizievole derivante dal mancato rispetto di tale obbligo.', baseStyleFinal),

              pw.SizedBox(height: 10),

              pw.Text('4. DURATA.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: boldFont)),
              pw.RichText(text: pw.TextSpan(style: baseStyleFinal, children: durataSpans)),

              pw.SizedBox(height: 10),

              pw.Text('5. CORRISPETTIVO.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: boldFont)),
              pw.RichText(
                text: pw.TextSpan(
                  style: baseStyleFinal,
                  children: [
                    pw.TextSpan(text: 'Le Parti convengono che il corrispettivo per i servizi prestati dal PREPONENTE è fissato in Euro '),
                    pw.TextSpan(text: preventivoObjConStatoFresco.prezzoMenuPersona.toStringAsFixed(2), style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont)),
                    pw.TextSpan(text: ' a persona (in lettere: ${_convertiNumeroInLettere(prezzoAdultoIntero)}/00), oltre IVA se dovuta (il "Prezzo Adulto"), nonchè in Euro '),
                    pw.TextSpan(text: preventivoObjConStatoFresco.prezzoMenuBambino.toStringAsFixed(2), style: pw.TextStyle(decoration: pw.TextDecoration.underline, font: baseFont)),
                    pw.TextSpan(text: ' per ogni MENÙ BABY (in lettere: ${_convertiNumeroInLettere(prezzoBambinoIntero)}/00), da corrispondersi nei tempi e con le modalità previste dal successivo art. 6.\n'),
                  ],
                ),
              ),
              
              _buildArticolo(
                '6. MODALITÀ DI PAGAMENTO.',
                '6.1 Al momento della sottoscrizione del presente Contratto, Il CLIENTE verserà un importo pari al 20% del Prezzo a titolo di caparra confirmatoria. \n6.2 Entro e non oltre 30 giorni dalla data fissata per l\'EVENTO, il CLIENTE verserà un ulteriore importo pari al 30% del Prezzo a titolo di acconto. \n6.3 Il saldo del Prezzo verrà corrisposto dal Cliente entro la data fissata per l\'EVENTO.',
                baseStyleFinal,
                boldFont
              ),

              _buildArticolo(
                '7. MINIMALE GARANTITO E SERVIZI EXTRA.',
                '7.1 Le Parti si danno atto che il Prezzo è stato determinato per la prestazione di servizi ad un numero minimo di 40 adulti garantiti. Sulla base del numero minimo garantito, il PREPONENTE ha interesse a concedere l\'uso esclusivo dei locali del PEPE ROSA. \n7.2 Le Parti convengono pertanto che, qualora l\'EVENTO abbia un numero di ospiti inferiore a 40 adulti, il CLIENTE dovrà comunque pagare l\'importo corrispondente al Prezzo adulto moltiplicato per 40, oltre agli eventuali MENÙ BABY. \n7.3 Resta inteso tra le Parti che, per ogni altra richiesta o eccedenza rispetto a quanto qui pattuito, il CLIENTE dovrà corrispondere gli ulteriori importi calcolati sulla base dei prezzi proposti nella lista servizi extra e nel listino corrente (ALL. 1).',
                baseStyleFinal,
                boldFont
              ),

              pw.Spacer(),
              pw.NewPage(),
            ],
          ),
        );
      },
    ),
  );

  // =========================================================================
  // PAGINA 5 (Contratto 3 + 4)
  // =========================================================================
  pdf.addPage(
    pw.Page(
      pageTheme: _getPageTheme(baseStyleFinal, logoBytes),
      build: (pw.Context context) {
        if (kDebugMode) {
          print('Firma 2 Bytes length (Check): ${firma2Bytes.length}');
        }
        
        final pw.TextStyle h1Style = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: boldFont);
        final pw.TextStyle artTitleStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, font: boldFont);
        final pw.TextStyle baseStyleP5 = baseStyleFinal.copyWith(fontSize: 8);
        final pw.TextStyle firmaTitleStyle = pw.TextStyle(fontSize: 13, font: boldFont);
        
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('8. MANCATO PAGAMENTO COMPENSI - INTERESSI DI MORA.', style: artTitleStyle),
              pw.SizedBox(height: 4), 
              pw.Text(
                '8.1 I pagamenti dovranno essere effettuati dal Cliente secondo le modalità e alle scadenze fissate al\nsuperiore art. 6.\n8.2 Le Parti si danno atto che, qualora alla scadenza del termine fissato per ciascun pagamento il\nCLIENTE non abbia versato i rispettivi importi, sulle somme dovute graveranno interessi moratori,\nfatto salvo il maggior danno.\n8.3 Fermo quanto sopra, nell\'ipotesi di mancato pagamento entro qualsiasi delle scadenze fissate\nall\'art. 6, il PREPONENTE avrà facoltà di risolvere il presente Contratto con effetto immediato,\nincamerando definitivamente gli importi già versati dal CLIENTE, fatto salvo il maggior danno.',
                style: baseStyleP5,
              ),
              
              pw.SizedBox(height: 4),
              
              _buildArticolo('9. RESPONSABILITÀ.', '9.1 Il CLIENTE sarà responsabile di qualsiasi danno a persone e/o cose derivante dalla propria condotta o da quella dei suoi ospiti. A tal fine, le Parti convengono che, successivamente allo svolgimento dell\'EVENTO, le stesse procederanno in contraddittorio alla verifica dello stato dei luoghi. \n9.2 In ogni caso, il PREPONENTE non risponderà a nessun titolo per eventuali danni eventualmente subiti dal CLIENTE o da terzi a causa dell\'uso improprio dei locali e delle attrezzature ivi presenti o per il mancato rispetto del regolamento della struttura di cui al successivo art. 10.', baseStyleP5, boldFont),
              
              pw.SizedBox(height: 4),
              
              pw.Text('10. Regolamento della Struttura.', style: artTitleStyle),
              pw.SizedBox(height: 2), 
              _buildSubArticolo('10.1', 'Il CLIENTE si impegna a rispettare il Regolamento della Struttura e tutte le indicazioni fornite dal PREPONENTE per l\'utilizzo della stessa.', baseStyleP5),
              pw.Text('10.2 In particolare, a titolo meramente esemplificativo e non esaustivo, il CLIENTE riconosce e prende atto che nel corso dell\'evento non sarò in alcun caso consentito:', style: baseStyleP5),
              pw.SizedBox(height: 0),
              pw.Text('a. la balneazione della piscina;', style: baseStyleP5),
              pw.Text('b. utilizzare coriandoli di ogni genere;', style: baseStyleP5),
              pw.Text('c. utilizzare lanterne cinesi o simili;', style: baseStyleP5),
              pw.Text('d. mantenere il volume alto della musica dopo le ore 00:00;', style: baseStyleP5),
              pw.Text('e. utilizzare microfoni o amplificazione per voce dopo le ore 00:00;', style: baseStyleP5),
              pw.Text('f. __________________________________________________________;', style: baseStyleP5),
              pw.Text('g. __________________________________________________________;', style: baseStyleP5),
              pw.Text('h. __________________________________________________________.', style: baseStyleP5),
              
              pw.SizedBox(height: 4),

              _buildArticolo('11. TRATTAMENTO DEI DATI.', 'Il CLIENTE dichiara di aver preso visione dell\'informativa ex art. 13 D.lgs 196/2003 e del Regolamento UE n. 2016/679 sulla protezione dei dati personali e presta il proprio consenso al trattamento dei propri dati personali per gli usi consentiti dalla legge ed esclusivamente connessi all\'esecuzione del presente Contratto.', baseStyleP5, boldFont),
              
              pw.SizedBox(height: 4),

              pw.Text('12. FORO COMPETENTE.', style: artTitleStyle),
              pw.Text('Si conviene espressamente che per ogni controversia relativa all\'interpretazione, esecuzione e/o risoluzione del presente Contratto sarà competente in via esclusiva il Foro di Roma.', style: baseStyleP5),
              
              pw.SizedBox(height: 12),
              
              pw.Text('Firma Cliente e Preponente', style: firmaTitleStyle),
              pw.SizedBox(height: 2),
              if (firmaBytes.isNotEmpty)
                pw.Container(
                  height: 100,
                  width: double.infinity,
                  child: pw.Image(pw.MemoryImage(firmaBytes), fit: pw.BoxFit.contain, height: 100),
                )
              else
                pw.Container(
                  height: 100,
                  width: double.infinity,
                  child: pw.Text('__________________________________________________________\n(Firma Cliente e Preponente per Accettazione Offerta)', style: baseStyleP5),
                ),
              
              pw.SizedBox(height: 12),
              
              pw.Text('Ai sensi e per gli effetti degli artt. 33 e 34 Cod. Cons., il CLIENTE dichiara espressamente di aver compreso pienamente il contenuto delle seguenti disposizioni contrattuali, le quali hanno costituito oggetto di trattativa individuale con il PREPONENTE:', style: baseStyleP5),
              pw.SizedBox(height: 2),
              pw.Text('ART. 8. MANCATO PAGAMENTO COMPENSI - INTERESSI DI MORA;', style: artTitleStyle),
              pw.Text('ART. 9. RESPONSABILITÀ;', style: artTitleStyle),
              pw.Text('ART. 12. FORO COMPETENTE.', style: artTitleStyle),

              pw.SizedBox(height: 6),
              
              if (statoFinaleRisolto == 'confermato')
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Accettazione Condizioni Cliente', style: firmaTitleStyle),
                    pw.SizedBox(height: 2),
                    if (firma2Bytes.isNotEmpty)
                      pw.Container(
                        height: 40,
                        width: double.infinity,
                        child: pw.Image(pw.MemoryImage(firma2Bytes), fit: pw.BoxFit.contain, height: 40),
                      )
                    else
                      pw.Text('__________________________________________________________', style: baseStyleP5),
                    pw.SizedBox(height: 12),
                  ],
                ),
              pw.Spacer(),
            ],
          ),
        );
      },
    ),
  );

  final pdfBytes = pdf.save();

  if (kDebugMode) {
    final dateFormatterPrint = DateFormat('dd/MM/yyyy');
    final dataEvento = dateFormatterPrint.format(preventivoObjConStatoFresco.dataEvento);
    print('====================================================');
    print('[PDF CONFERMA FINALE]');
    print('Stato Finale: ${statoFinaleRisolto.toUpperCase()}');
    print('Cliente: ${preventivoObjConStatoFresco.cliente.ragioneSociale}');
    print('Data Evento: $dataEvento');
    print('====================================================');
  }

  return pdfBytes;
}
