// lib/utils/pdf_generator.dart

import 'dart:typed_data';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import '../models/preventivo_pdf_models.dart';
import 'download_utils.dart';

// Funzione di utilità per caricare il font (DEVE essere asincrona)
Future<pw.Font> _loadRobotoFont() async {
  try {
    const fontPath = "assets/fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf";
    final fontData = await rootBundle.load(fontPath);
    return pw.Font.ttf(fontData);
  } catch (e) {
    if (kDebugMode) {
      print("ATTENZIONE: Impossibile caricare il font Roboto. Usando fallback di sistema. $e");
    }
    return pw.Font.helvetica();
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
      "NOME_AZIENDA_1": (data['nome_azienda_1'] as String?) ?? 'NOME NON CONFIGURATO',
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

// 🔑 FUNZIONE CHIAVE: Recupera lo stato aggiornato (e pulito) direttamente da Firestore
Future<String> _recuperaStatoAggiornato(String preventivoId, String? firmaUrlPassata) async {
  if (preventivoId.isEmpty) return 'bozza';
  try {
    final doc = await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).get();
    final data = doc.data() ?? {};
    final statusLettuRaw = data['status'] as String? ?? data['stato'] as String? ?? '';
    final statoLettu = statusLettuRaw.trim().toLowerCase();
    final firmaPresenteInDb = (data['firma_url'] as String?)?.isNotEmpty ?? false;

    if (statoLettu == 'confermato' || firmaPresenteInDb || (firmaUrlPassata?.isNotEmpty ?? false)) {
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

// 🔑 MODIFICA FIRMA: Accetta lo stato finale già risolto
Future<Uint8List> generaPdfDaDatiDart(PreventivoCompletoPdf preventivoObj, String statoFinaleRisolto) async {
  final ttf = await _loadRobotoFont();
  final baseFont = pw.Font.helvetica();

  final datiAzienda = await getDatiAzienda();

  final preventivoObjConStatoFresco = PreventivoCompletoPdf.fromMap({
    ...preventivoObj.toMap(),
    'stato': statoFinaleRisolto,
  });

  if (kDebugMode) {
    final nomeCliente = preventivoObjConStatoFresco.cliente.ragioneSociale;
    final dateFormatterPrint = DateFormat('dd/MM/yyyy');
    final dataEvento = dateFormatterPrint.format(preventivoObjConStatoFresco.dataEvento);
    print('====================================================');
    print('[PDF STATUS DEBUG] STATO INIETTATO E UTILIZZATO: "${statoFinaleRisolto.toUpperCase()}"');
    print('====================================================');
  }

  final fallbackList = [ttf];

  final baseStyle = pw.TextStyle(
    fontSize: 12,
    color: PdfColor.fromInt(0xFF222222),
    font: baseFont,
    fontFallback: fallbackList,
  );

  final mutedStyle = pw.TextStyle(color: PdfColors.grey600, fontSize: 11, font: baseFont, fontFallback: [ttf]);
  final smallStyle = pw.TextStyle(fontSize: 11, color: PdfColors.grey600, font: baseFont, fontFallback: [ttf]);
  final labelStyle = pw.TextStyle(color: PdfColors.grey600, fontSize: 12, font: baseFont, fontFallback: [ttf]);
  final valStyle = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    fontSize: 12,
    color: PdfColor.fromInt(0xFF222222),
    font: baseFont,
    fontFallback: [ttf],
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

  final totOspiti = preventivoObjConStatoFresco.numeroOspiti;
  final numBambini = preventivoObjConStatoFresco.numeroBambini;
  final numAdulti = (totOspiti - numBambini).clamp(0, totOspiti);

  final costoMenuAdulti = (preventivoObjConStatoFresco.prezzoMenuPersona * numAdulti);
  final costoMenuBambini = (preventivoObjConStatoFresco.prezzoMenuBambino * numBambini);
  final costoServizi = preventivoObjConStatoFresco.serviziExtra.fold(0.0, (sum, s) => sum + s.prezzo);

  // ★ Pacchetto Aperitivo di Benvenuto + Buffet di Dolci (opzionale)
  double costoWelcomeDolci = 0.0;
  try {
    final dyn = preventivoObjConStatoFresco as dynamic;
    final maybeCosto = dyn.costoPacchettoWelcomeDolci;
    if (maybeCosto is num && maybeCosto.toDouble() > 0) {
      costoWelcomeDolci = maybeCosto.toDouble();
    }
  } catch (_) {
    // Nessun campo presente → resta 0 e non si stampa la riga
  }

  final subtotale = costoMenuAdulti + costoMenuBambini + costoServizi + costoWelcomeDolci;
  final sconto = preventivoObjConStatoFresco.sconto;
  final totaleFinale = (subtotale - sconto).clamp(0.0, double.infinity);

  // ⚠️ SOLO double nella mappa per rispettare la firma di _buildCostiTable
  final Map<String, double> costi = {
    "costo_welcome_dolci": costoWelcomeDolci,
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

  Uint8List firmaBytes = Uint8List(0);

  if (preventivoObjConStatoFresco.firmaUrl != null && preventivoObjConStatoFresco.firmaUrl!.isNotEmpty) {
    if (kDebugMode) print('[Firma PDF] Tentativo di download firma da: ${preventivoObjConStatoFresco.firmaUrl!}');
    firmaBytes = await scaricaFirmaDaStorage(preventivoObjConStatoFresco.firmaUrl!);
  }

  Uint8List logoBytes = Uint8List(0);
  if (datiAzienda["LOGO_URL"]!.isNotEmpty) {
    if (kDebugMode) print('[Logo PDF] Tentativo di download logo.');
    logoBytes = await scaricaFirmaDaStorage(datiAzienda["LOGO_URL"]!);
  }

  // =========================================================================
  // PAGINA 1
  // =========================================================================

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
                  padding: const pw.EdgeInsets.only(bottom: 12),
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
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
                    ),
                    if (datiAzienda['NOME_AZIENDA_2'] != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(datiAzienda['NOME_AZIENDA_2']!, style: smallStyle),
                      ),
                    if (datiAzienda['INDIRIZZO_AZIENDA'] != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(datiAzienda['INDIRIZZO_AZIENDA']!, style: smallStyle),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
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
                    pw.SizedBox(height: 4),
                    pw.Text(
                      (statoFinaleRisolto == 'confermato') ? 'CONFERMATO' : 'BOZZA',
                      style: smallStyle.copyWith(
                        color: (statoFinaleRisolto == 'confermato') ? PdfColors.green700 : PdfColors.red700,
                      ),
                    ),
                    if (preventivoObjConStatoFresco.id.isNotEmpty)
                      pw.Text('ID: ${preventivoObjConStatoFresco.id}', style: smallStyle.copyWith(color: PdfColors.grey600)),
                    pw.Text(datiAzienda['LUOGO_DATA']!, style: smallStyle.copyWith(color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Divider(height: 12, borderStyle: pw.BorderStyle.dashed),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Cliente', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 8),
                        _buildDetailRow('Ragione sociale:', preventivoObjConStatoFresco.cliente.ragioneSociale, labelStyle, valStyle),
                        _buildDetailRow('Referente:', preventivoObjConStatoFresco.cliente.referente, labelStyle, valStyle),
                        _buildDetailRow('Telefono:', preventivoObjConStatoFresco.cliente.telefono01, labelStyle, valStyle),
                        _buildDetailRow('Email:', preventivoObjConStatoFresco.cliente.mail, labelStyle, valStyle),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Evento', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 8),
                        _buildDetailRow('Nome evento:', preventivoObjConStatoFresco.nomeEvento, labelStyle, valStyle),
                        _buildDetailRow('Data:', dateFormatter.format(preventivoObjConStatoFresco.dataEvento), labelStyle, valStyle),
                        _buildDetailRow('Tipo pasto:', tipoPastoLabel, labelStyle, valStyle),
                        pw.Text(invitatiLabel, style: valStyle),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.Divider(height: 12, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey400),
            pw.Spacer(),
            if (preventivoObjConStatoFresco.menu != null)
              pw.Container(
                width: 120 * PdfPageFormat.mm,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('Proposta di menù', style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(height: 12),
                    ..._buildMenuSection(preventivoObjConStatoFresco.menu!, baseStyle, smallStyle),
                    if (preventivoObjConStatoFresco.noteMenuBambini != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 12),
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(text: 'Menù bambini:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13.2)),
                              pw.TextSpan(text: '\n${preventivoObjConStatoFresco.noteMenuBambini}', style: baseStyle),
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
  // PAGINA 2/3: Servizi Extra
  // =========================================================================
  if (preventivoObjConStatoFresco.serviziExtra.isNotEmpty) {
    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Servizi extra', style: pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 12),
              _buildServiziTable(preventivoObjConStatoFresco.serviziExtra, baseStyle, smallStyle),
            ],
          );
        },
      ),
    );
  }

  // =========================================================================
  // ULTIMA PAGINA: Riepilogo Costi & Firma
  // =========================================================================
  pdf.addPage(
    pw.Page(
      pageFormat: format,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Riepilogo costi', style: pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 12),
            _buildCostiTable(preventivoObjConStatoFresco, costi, baseStyle, valStyle, smallStyle),
            if (preventivoObjConStatoFresco.noteSconto != null &&
                preventivoObjConStatoFresco.noteSconto!.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text('Note sconto: ${preventivoObjConStatoFresco.noteSconto}', style: smallStyle),
              ),
            if (datiAzienda['IBAN'] != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text('Coordinate bancarie: IBAN ${datiAzienda['IBAN']}', style: smallStyle),
              ),
            pw.SizedBox(height: 18),
            if (firmaBytes.isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Firma/e', style: pw.TextStyle(fontSize: 14)),
                  pw.SizedBox(height: 6),
                  pw.Image(pw.MemoryImage(firmaBytes), fit: pw.BoxFit.contain, height: 70),
                ],
              ),
          ],
        );
      },
    ),
  );

  final pdfBytes = pdf.save();

  if (kDebugMode) {
    final nomeCliente = preventivoObjConStatoFresco.cliente.ragioneSociale;
    final dateFormatterPrint = DateFormat('dd/MM/yyyy');
    final dataEvento = dateFormatterPrint.format(preventivoObjConStatoFresco.dataEvento);
    print('====================================================');
    print('[PDF CONFERMA FINALE]');
    print('Stato Finale: ${statoFinaleRisolto.toUpperCase()}');
    print('Cliente: $nomeCliente');
    print('Data Evento: $dataEvento');
    print('====================================================');
  }

  return pdfBytes;
}

// -------------------------------------------------------------------------
// WIDGET BUILDER DI SUPPORTO
// -------------------------------------------------------------------------

pw.Widget _buildDetailRow(String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) {
  if (value.isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: label, style: labelStyle),
          pw.TextSpan(text: ' $value', style: valueStyle),
        ],
      ),
    ),
  );
}

List<pw.Widget> _buildMenuSection(MenuPdf menu, pw.TextStyle baseStyle, pw.TextStyle smallStyle) {
  final List<String> ordine = ['antipasto', 'primo', 'secondo', 'contorno'];
  final List<pw.Widget> widgets = [];

  final Map<String, List<PiattoPdf>> menuMap = {
    'antipasto': menu.antipasto,
    'primo': menu.primo,
    'secondo': menu.secondo,
    'contorno': menu.contorno,
  };

  int totalRendered = 0;
  for (final genere in ordine) {
    if (menuMap[genere] != null && menuMap[genere]!.isNotEmpty) {
      totalRendered++;
    }
  }

  int renderedCount = 0;
  for (final genere in ordine) {
    final piatti = menuMap[genere];
    if (piatti != null && piatti.isNotEmpty) {
      renderedCount++;
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(genere.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
      );
      widgets.add(pw.SizedBox(height: 6));

      widgets.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: piatti
              .map((item) => pw.Row(
                    children: [
                      pw.Text('- ${item.nome}', style: baseStyle),
                      if (item.custom) pw.Text(' (fuori menù)', style: smallStyle),
                    ],
                  ))
              .toList(),
        ),
      );

      if (renderedCount < totalRendered) widgets.add(pw.SizedBox(height: 12));
    }
  }

  return widgets;
}

pw.Widget _buildServiziTable(List<ServizioExtraPdf> servizi, pw.TextStyle baseStyle, pw.TextStyle smallStyle) {
  const tableHeaders = ['Servizio', 'Fornitore', 'Prezzo'];

  final List<List<pw.Widget>> data = servizi.map((s) {
    final fornitoreNome = s.fornitore['ragione_sociale'] ?? '';
    return [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.ruolo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
                  child: pw.Text(header, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
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
) {
  final nAdulti = (p.numeroOspiti - p.numeroBambini).clamp(0, p.numeroOspiti);
  final nBimbi = p.numeroBambini;
  final prezzoAdulto = p.prezzoMenuPersona;
  final prezzoBimbo = p.prezzoMenuBambino;

  final double costoWelcome = costi['costo_welcome_dolci'] ?? 0.0;

  String _labelWelcomeComputed(double amount, int invitati) {
    if (amount <= 0 || invitati <= 0) return '';
    return 'Pacchetto aperitivo di benvenuto + buffet di dolci';
  }

  String _welcomeDetails(double amount, int invitati) {
    if (amount <= 0 || invitati <= 0) return '';
    final unit = (amount / invitati).toStringAsFixed(2);
    return '(${invitati} x Euro $unit)';
  }

  final rows = <List<pw.Widget>>[];

  if (costoWelcome > 0) {
    rows.add(
      _costiRow(
        _labelWelcomeComputed(costoWelcome, p.numeroOspiti),
        _welcomeDetails(costoWelcome, p.numeroOspiti),
        costoWelcome,
        baseStyle,
        valStyle,
        smallStyle,
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
    ),
    _costiRow(
      'Menù Bambini',
      '(${nBimbi} x Euro ${prezzoBimbo.toStringAsFixed(2)})',
      costi['costo_menu_bambini']!,
      baseStyle,
      valStyle,
      smallStyle,
    ),
    _costiRow('Servizi Extra', '', costi['costo_servizi']!, baseStyle, valStyle, smallStyle),
    _costiRow('Subtotale', '', costi['subtotale']!, baseStyle, valStyle, smallStyle, isBold: true),
    _costiRow('Sconto', '', -costi['sconto']!, baseStyle, valStyle, smallStyle, isDiscount: true),
    _costiRow('Totale', '', costi['totale_finale']!, baseStyle, valStyle, smallStyle, isTotal: true),
  ]);

  if (p.acconto != null) {
    rows.addAll([
      _costiRow('Acconto', '', -costi['acconto']!, baseStyle, valStyle, smallStyle, isDiscount: true),
      _costiRow('Saldo', '', costi['saldo']!, baseStyle, valStyle, smallStyle, isTotal: true),
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
  pw.TextStyle smallStyle, {
  bool isBold = false,
  bool isTotal = false,
  bool isDiscount = false,
}) {
  final labelStyle =
      isTotal ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.black) : baseStyle;
  final priceStyle = isTotal
      ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.black)
      : (isDiscount ? pw.TextStyle(color: PdfColors.red) : valStyle);

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
