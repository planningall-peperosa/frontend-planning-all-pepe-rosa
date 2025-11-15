// lib/screens/dati_cliente_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import 'dart:ui' as ui;
import 'dart:math' as math;

import '../models/cliente.dart';
import '../services/preventivi_service.dart';
import '../providers/clienti_provider.dart';
import '../providers/preventivo_builder_provider.dart';
import '../providers/preventivi_provider.dart';
import 'cerca_cliente_screen.dart'; // Corretto il percorso
import '../widgets/wizard_stepper.dart';
import '../widgets/firma_dialog.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'archivio_preventivi_screen.dart'; // Corretto il percorso

import '../services/storage_service.dart';

import '../utils/pdf_generator.dart';
import '../models/preventivo_pdf_models.dart';

import '../utils/consistency_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/rendering.dart';


enum _SignatureLayout { vertical, horizontal }

class SignatureParams {
  final double padding;
  final double leftInset;
  final double rightInset;
  final double minGap;
  final double headerDownshift;
  final double headerFs;
  final double captionFs;
  final double maxSignH;
  final double captionsGap;
  final double headerExtraTop;

  const SignatureParams({
    required this.padding,
    required this.leftInset,
    required this.rightInset,
    required this.minGap,
    required this.headerDownshift,
    required this.headerFs,
    required this.captionFs,
    required this.maxSignH,
    required this.captionsGap,
    required this.headerExtraTop,
  });
}

SignatureParams defaultSignatureParams() => const SignatureParams(
  padding: 24.0,
  leftInset: 10.0,
  rightInset: 90.0,
  minGap: 800.0,
  headerDownshift: 56.0,
  headerFs: 40.0,
  captionFs: 32.0,
  maxSignH: 300.0,
  captionsGap: 8.0,
  headerExtraTop: 12.0,
);

void _logUi(String msg) {
  if (kDebugMode) {
    print('[DatiCliente] $msg');
  }
}

class DatiClienteScreen extends StatefulWidget {
  const DatiClienteScreen({super.key});

  @override
  State<DatiClienteScreen> createState() => _DatiClienteScreenState();
}

class _DatiClienteScreenState extends State<DatiClienteScreen> {
  final _formKey = GlobalKey<FormState>();

  final StorageService _storageService = StorageService();

  final _nomeClienteController = TextEditingController();
  final _noteIntegrativeController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _nomeEventoController = TextEditingController();
  final _accontoController = TextEditingController();
  final _codiceFiscaleController = TextEditingController();

  final _nomeClienteFocusNode = FocusNode();
  bool _autoValidate = false;

  Timer? _debounce;
  bool _isNuovoCliente = false;

  bool _isProcessing = false;
  String? _busyAction; // 'create' | 'save' | 'pdf' | 'firma'

  bool _pdfBusy = false;

  // 🔐 Safe refs
  ScaffoldMessengerState? _messenger;
  PreventiviProvider? _preventiviProv;

  String? _openedPayloadJson;

  // =========================
  // 🔒 Costanti Privacy/Consenso
  // =========================
  static const String _kPrivacyPolicyVersion = 'v1.0';
  static const String _kPrivacyPolicyUrl = 'https://tuodominio.it/privacy'; // sostituisci con l’URL reale

  static const String _kConsensoBreve =
      'I dati personali e la firma saranno conservati in forma sicura e '
      'utilizzati esclusivamente per la gestione del preventivo e dei rapporti '
      'contrattuali con l’attività Pepe Rosa.';

  // Sostituisci questo placeholder con la tua informativa completa.
  static const String _kInformativaCompleta = '''
Titolare del trattamento: PEPE ROSA Via dello Scopone 45 NETTUNO (RM) CAP 00048
Finalità: gestione del preventivo e del rapporto contrattuale.
Base giuridica: consenso e/o esecuzione di misure precontrattuali/contrattuali.
Dati trattati: identificativi, contatti, firma, contenuti del preventivo.
Conservazione: per la durata necessaria alla gestione contrattuale e adempimenti di legge.
Destinatari: eventuali fornitori/partner strettamente funzionali all’erogazione del servizio.
Diritti: accesso, rettifica, cancellazione, limitazione, portabilità, opposizione.
Reclamo: Garante per la protezione dei dati personali.
Contatti del Titolare/DPO: Tel: +39 342 7678084 peperosanettuno@gmail.com
''';
//Informativa completa: $_kPrivacyPolicyUrl


  // --- snackbar helper sicuro
  void _showSnack(SnackBar bar) {
    if (!mounted) return; // blocca chiamate dopo dispose
    try {
      ScaffoldMessenger.of(context).showSnackBar(bar);
    } catch (e) {
      debugPrint('[UI][ERROR] showSnackBar after dispose: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // NB: non usare Provider.of qui per scrivere; farlo dopo in didChangeDependencies/post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);

      // 1) Popola i campi dalla sorgente (Provider)
      _popolaCampiDalBuilder(prov);

      // 2) Mantieni il provider allineato ai cambi del campo Note (listener singolo)
      _noteIntegrativeController.addListener(() {
        prov.setNoteIntegrative(_noteIntegrativeController.text);
      });

      // 3) Listener per acconto
      _accontoController.addListener(() {
        final raw = _accontoController.text.trim().replaceAll(',', '.');
        if (raw.isEmpty) {
          _setAccontoNullable(prov, null);
        } else {
          final val = double.tryParse(raw);
          if (val != null) _setAccontoNullable(prov, val);
        }
      });

      setState(() {
        _isNuovoCliente = prov.cliente == null || (prov.cliente!.idCliente.isEmpty);
      });

      _openedPayloadJson = _payloadJsonFor(prov);

      // sposta setEditingOpen(true) su post-frame ma usa provider cached
      _preventiviProv?.setEditingOpen(true);

      _logUi('init done (cliente=${prov.cliente?.ragioneSociale ?? "-"}, preventivoId=${prov.preventivoId ?? "-"})');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    // cache del provider per usarlo in dispose senza lookup dal context
    _preventiviProv ??= context.read<PreventiviProvider>();
  }

  void _setAccontoNullable(PreventivoBuilderProvider prov, double? valore) {
    try {
      final dyn = prov as dynamic;
      dyn.setAccontoNullable(valore);
      return;
    } catch (_) {
      if (valore != null) {
        try {
          final dyn = prov as dynamic;
          dyn.setAcconto(valore);
          return;
        } catch (_) {}
      }
    }
  }

  void _popolaCampiDalBuilder(PreventivoBuilderProvider prov) {
    _noteIntegrativeController.text = prov.noteIntegrative;
    final c = prov.cliente;
    _nomeClienteController.text = c?.ragioneSociale ?? '';
    _telefonoController.text = c?.telefono01 ?? '';
    _emailController.text = c?.mail ?? '';
    _codiceFiscaleController.text = c?.codiceFiscale ?? '';
    _nomeEventoController.text = prov.nomeEvento ?? '';

    if (prov.acconto == null) {
      _accontoController.text = '';
    } else {
      _accontoController.text =
          (prov.acconto!).toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  void _aggiornaBuilderDaiController() {
    final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);

    // Note integrative (già allineate dal listener, ma la lasciamo per sicurezza on-demand)
    prov.setNoteIntegrative(_noteIntegrativeController.text);

    final curr = prov.cliente ?? Cliente(idCliente: '', tipo: 'cliente');
    final clienteAggiornato = Cliente(
      idCliente: curr.idCliente,
      tipo: 'cliente',
      ragioneSociale: _nomeClienteController.text,
      telefono01: _telefonoController.text,
      mail: _emailController.text,
      codiceFiscale: _codiceFiscaleController.text.trim().isNotEmpty
          ? _codiceFiscaleController.text.trim()
          : null,
      // Manteniamo gli altri campi del cliente esistente/corrente (ruolo, prezzo, etc.)
      ruolo: curr.ruolo,
      prezzo: curr.prezzo,
      colore: curr.colore,
    );
    prov.setCliente(clienteAggiornato);

    prov.setNomeEvento(_nomeEventoController.text);

    final raw = _accontoController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) {
      _setAccontoNullable(prov, null);
    } else {
      _setAccontoNullable(prov, double.tryParse(raw));
    }
  }

  dynamic _canonicalize(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((e) => e.toString()).toList()..sort();
      final out = <String, dynamic>{};
      for (final k in keys) {
        out[k] = _canonicalize(v[k]);
      }
      return out;
    } else if (v is List) {
      return v.map(_canonicalize).toList();
    } else if (v is num) {
      final d = v.toDouble();
      return (d == d.roundToDouble()) ? d.toInt() : d;
    } else {
      return v;
    }
  }

  String _payloadJsonFor(PreventivoBuilderProvider prov) {
    final wrap = prov.creaPayloadSalvataggio();
    final payload = (wrap == null) ? const {} : (wrap['payload'] ?? const {});
    return jsonEncode(_canonicalize(payload));
  }

  bool _hasLocalChangesFallback(PreventivoBuilderProvider prov) {
    final curr = _payloadJsonFor(prov);
    if (_openedPayloadJson == null) {
      _openedPayloadJson = curr;
      return false;
    }
    return curr != _openedPayloadJson;
  }

  bool _hasLocalChangesDyn(PreventivoBuilderProvider prov) {
    try {
      final dyn = prov as dynamic;
      final v1 = dyn.hasLocalChanges;
      if (v1 is bool) return v1;
      final v2 = dyn.isDirty;
      if (v2 is bool) return v2;
      final v3 = dyn.dirty;
      if (v3 is bool) return v3;
    } catch (_) {}
    return _hasLocalChangesFallback(prov);
  }

  void _clearLocalChangesDyn(PreventivoBuilderProvider prov) {
    bool cleared = false;
    try {
      final dyn = prov as dynamic;
      final fn = dyn.clearLocalChanges;
      if (fn is Function) {
        fn.call();
        cleared = true;
      }
    } catch (_) {}
    if (!cleared) {
      _openedPayloadJson = _payloadJsonFor(prov);
    }
  }

  bool _isConfermatoDyn(PreventivoBuilderProvider prov) {
    try {
      final dyn = prov as dynamic;
      final c = dyn.confermato;
      if (c is bool) return c;
      final stato = dyn.stato;
      if (stato != null && stato.toString().toLowerCase() == 'confermato') return true;
    } catch (_) {}
    return false;
  }

  bool _validateFormOrNotify() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _autoValidate = true);
      _nomeClienteFocusNode.requestFocus();
      _showSnack(
        const SnackBar(content: Text('Compila i campi obbligatori: Nome Cliente')),
      );
    }
    return isValid;
  }

  Future<bool> _salvaSuFirebase({bool popOnSuccess = false}) async {
    if (!_formKey.currentState!.validate()) {
      _showSnack(
        const SnackBar(
          content: Text('Compila i campi obbligatori prima di salvare.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    setState(() {
      _isProcessing = true;
      _busyAction = 'save';
    });

    _aggiornaBuilderDaiController();
    bool success = false;

    try {
      final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);

      // 1) Payload completo dal builder
      final dataToSave = builder.toFirestoreMap();
      final preventivoId = builder.preventivoId;

      // 2) Per gli UPDATE inviamo solo i campi non-null (evita cancellazioni involontarie)
      final Map<String, dynamic> dataToUpdate = {};
      dataToSave.forEach((key, value) {
        if (value != null) dataToUpdate[key] = value;
      });

      if (preventivoId != null && preventivoId.isNotEmpty) {
        // --- UPDATE ---
        await FirebaseFirestore.instance
            .collection('preventivi')
            .doc(preventivoId)
            .update(dataToUpdate);

        // (Facoltativo) assicura che il campo preventivo_id esista nel doc
        try {
          await FirebaseFirestore.instance
              .collection('preventivi')
              .doc(preventivoId)
              .set({'preventivo_id': preventivoId}, SetOptions(merge: true));
        } catch (_) {}

      } else {
        // --- CREATE ---
        final docRef = await FirebaseFirestore.instance
            .collection('preventivi')
            .add(dataToSave);

        // Salva l'ID nel builder
        try {
          final dyn = builder as dynamic;
          if (dyn.setPreventivoId is Function) {
            dyn.setPreventivoId(docRef.id);
          } else {
            dyn.preventivoId = docRef.id;
          }
        } catch (_) {}

        // (utile) scrivi anche l'id dentro al documento
        try {
          await docRef.update({'preventivo_id': docRef.id});
        } catch (_) {}
      }

      _clearLocalChangesDyn(builder);

      _showSnack(
        const SnackBar(
          content: Text('Preventivo salvato con successo!'),
          backgroundColor: Colors.green,
        ),
      );

      if (popOnSuccess && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      success = true;
    } catch (e) {
      _showSnack(
        SnackBar(
          content: Text('Errore durante il salvataggio: $e'),
          backgroundColor: Colors.red,
        ),
      );
      success = false;
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _busyAction = null;
        });
      }
    }
    return success;
  }

  Future<void> _onTapGeneraPdf() async {
    if (_pdfBusy) return;
    setState(() {
      _pdfBusy = true;
      _busyAction = 'pdf';
    });

    try {
      await _salvaEGeneraPdf();
    } catch (e, st) {
      debugPrint('[UI][ERROR] generaPdf: $e\n$st');
      _showSnack(
        const SnackBar(content: Text('Errore durante la generazione del PDF')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _pdfBusy = false;
        if (_busyAction == 'pdf') _busyAction = null;
      });
    }
  }

  Future<void> _runConsistencyCheck() async {
    try {
      final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
      prov.setNoteIntegrative(_noteIntegrativeController.text);
      final id = prov.preventivoId;

      if (id == null || id.isEmpty) {
        _showSnack(const SnackBar(
          content: Text('Salva prima il preventivo per eseguire il check.'),
          backgroundColor: Colors.red,
        ));
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('preventivi')
          .doc(id)
          .get();

      final Map<String, dynamic> dbData = snap.data() ?? {};

      final report = await checkPreventivoConsistency(prov, dbData);
      await showConsistencyReportDialog(context, report);
    } catch (e) {
      _showSnack(SnackBar(
        content: Text('Errore nel check di coerenza: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _salva() async {
    _logUi('CHIAMATA A FUNZIONE DEPRECATA _salva(). Usare _salvaSuFirebase().');
  }

  // lib/screens/dati_cliente_screen.dart (SOLO LA FUNZIONE _salvaEGeneraPdf MODIFICATA)
  Future<void> _salvaEGeneraPdf() async {
    if (!_validateFormOrNotify()) return;


    // Anchor per il popover iPad richiesto da share_plus
    ui.Rect _shareOrigin(BuildContext ctx) {
      final overlay = Overlay.of(ctx);
      final ro = overlay?.context.findRenderObject();
      if (ro is RenderBox) {
        final size = ro.size;
        final center = ro.localToGlobal(size.center(Offset.zero));
        return ui.Rect.fromCenter(center: center, width: 240, height: 240);
      }
      // Fallback: rettangolo non nullo al centro schermo
      final mq = MediaQuery.maybeOf(ctx);
      final s = mq?.size ?? const Size(600, 800);
      final center = Offset(s.width / 2, s.height / 2);
      return ui.Rect.fromCenter(center: center, width: 240, height: 240);
}




    final total = Stopwatch()..start();
    _logUi('PDF start');
    setState(() {
      _isProcessing = true;
      _busyAction = 'pdf';
    });

    _aggiornaBuilderDaiController(); // Aggiorna lo stato interno del Provider

    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);

    try {
      // 1. SALVATAGGIO GARANTITO DEI CAMBIAMENTI
      final salvataggioOk = await _salvaSuFirebase(popOnSuccess: false);
      if (!salvataggioOk) {
        throw Exception('Salvataggio su Firebase fallito prima della generazione del PDF.');
      }
      
      // 2. RILETTURA TOTALE DAL DB (Fonte Unica dei Dati per il PDF) 
      final snap = await FirebaseFirestore.instance
            .collection('preventivi')
            .doc(builder.preventivoId!)
            .get();
      final dbData = snap.data() ?? {}; // Dati freschi e completi dal DB

      dbData['preventivo_id'] ??= snap.id;

      // 3. COSTRUZIONE DEL MODEL PDF ESCLUSIVAMENTE DAL DB
      final preventivoObj = PreventivoCompletoPdf.fromMap(dbData);
      
      // 🚨 BLOCCO CRITICO DI DEBUG: STAMPA IL PAYLOAD COMPLETO
      if (kDebugMode) {
          final Map<String, dynamic> payloadMap = {
              'Descr1': preventivoObj.descrizionePacchettoFisso,
              'Descr2': preventivoObj.descrizionePacchettoFisso2,
              'Descr3': preventivoObj.descrizionePacchettoFisso3,
              'ServiziExtraCount': preventivoObj.serviziExtra.length,
              'Acconto': preventivoObj.acconto,
              'DataEvento': preventivoObj.dataEvento.toIso8601String(),
          };
          final encoder = JsonEncoder.withIndent('  ');
          final readableJson = encoder.convert(payloadMap);
          print('====================================================');
          print('>>> PAYLOAD FINALE PER PDF GENERATOR START <<<');
          print(readableJson);
          print('>>> PAYLOAD FINALE PER PDF GENERATOR END <<<');
          print('====================================================');
      }
      // --------------------------------------------------------

      // 3.b RISOLUZIONE STATO DAL DB (Patch 3)
      String _resolvePdfStateFromDb(Map<String, dynamic> data) {
        final raw = (data['status'] ?? data['stato'] ?? '').toString().trim().toLowerCase();
        final hasFirma1 = (data['firma_url'] ?? '').toString().isNotEmpty;
        final hasFirma2 = (data['firma_url_cliente_2'] ?? '').toString().isNotEmpty;
        if (raw == 'confermato' || hasFirma1 || hasFirma2) return 'confermato';
        return (raw.isNotEmpty) ? raw : 'bozza';
      }

      final statoPreferito = _resolvePdfStateFromDb(dbData);

      _logUi('4. Inizio generazione PDF con stato risolto: $statoPreferito');
      final bytes = await generaPdfDaDatiDart(preventivoObj, statoPreferito);

      _logUi('Generazione PDF Dart completata (bytes=${bytes.length})');

      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        await _savePdfDesktop(bytes, builder);
      } else if (!kIsWeb && Platform.isAndroid) {
        await _presentAndroidPdfActions(bytes, builder);
      } else if (!kIsWeb && Platform.isIOS) {
        final origin = _shareOrigin(context); // << anchor richiesto su iPad
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: _suggestedName(builder), mimeType: 'application/pdf')],
          text: 'Preventivo',
          sharePositionOrigin: origin,
        );
      } else {
        final tmp = await getTemporaryDirectory();
        final file = File('${tmp.path}/${_suggestedName(builder)}');
        await file.writeAsBytes(bytes, flush: true);
        _showSnack(SnackBar(content: Text('PDF creato: ${file.path}')));
      }

      _showSnack(const SnackBar(content: Text('PDF generato con successo')));

    } catch (e) {
      _showSnack(SnackBar(content: Text('Errore generazione PDF: $e')));
      _logUi('PDF error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _busyAction = null;
        });
      }
      total.stop();
      _logUi('PDF end total=${total.elapsedMilliseconds}ms');
    }
  }
  
  Future<void> _savePdfDesktop(Uint8List pdfBytes, PreventivoBuilderProvider prov) async {
    final suggestedName = _suggestedName(prov);








    _logUi('[SAVE DESKTOP] Tentativo di salvare PDF tramite file_selector...');

    final home = Platform.environment['HOME'] ?? '';
    final defaultDir =
        home.isNotEmpty ? '$home/Documents/Preventivi_PepeRosa' : Directory.systemTemp.path;

    try {
      if (!Directory(defaultDir).existsSync()) {
        Directory(defaultDir).createSync(recursive: true);
      }
    } catch (_) {
      _logUi('[SAVE DESKTOP] Errore nella creazione della directory di default: $_');
    }

    if (!mounted) {
      _logUi('[SAVE DESKTOP] Errore: Contesto smontato prima di chiamare getSaveLocation.');
      return;
    }

    final saveLoc = await Future.delayed(Duration.zero, () async {
      return await fs.getSaveLocation(
        suggestedName: suggestedName,
        initialDirectory: defaultDir,
      );
    });

    _logUi('[SAVE DESKTOP] getSaveLocation completata. Risultato: ${saveLoc?.path ?? "ANNULLATO"}');

    if (saveLoc == null) {
      _showSnack(const SnackBar(content: Text('Salvataggio annullato dall\'utente.')));
      return;
    }

    final file = File(saveLoc.path);
    try {
      await file.writeAsBytes(pdfBytes, flush: true);
      _showSnack(SnackBar(content: Text('PDF salvato con successo in: ${file.path}')));
    } catch (e) {
      _logUi('[SAVE DESKTOP] Errore scrittura file: $e');
      _showSnack(SnackBar(content: Text('Errore durante la scrittura del file: $e')));
    }
  }

  Future<void> _presentAndroidPdfActions(
    Uint8List pdfBytes,
    PreventivoBuilderProvider prov,
  ) async {
    final name = _suggestedName(prov);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Condividi (WhatsApp, Email, Drive…)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await Share.shareXFiles(
                    [XFile.fromData(pdfBytes, name: name, mimeType: 'application/pdf')],
                    text: 'Preventivo',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Salva in…'),
                subtitle: const Text('Scegli cartella e nome file'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    final tmp = await getTemporaryDirectory();
                    final tempPath = '${tmp.path}/$name';
                    final f = File(tempPath);
                    await f.writeAsBytes(pdfBytes, flush: true);

                    const channel = MethodChannel('it.peperosa/savefile');
                    final ok = await channel.invokeMethod<bool>('createDocument', {
                      'suggestedName': name,
                      'mimeType': 'application/pdf',
                      'tempPath': tempPath,
                    });

                    if (ok == true) {
                      _showSnack(const SnackBar(content: Text('PDF salvato.')));
                    } else {
                      _showSnack(const SnackBar(content: Text('Operazione annullata.')));
                    }
                  } catch (e) {
                    _showSnack(SnackBar(content: Text('Errore salvataggio: $e')));
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  TextPainter _tp(String text, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.ltr,
    );
  }

  // 🔧 FIX RegExp
  String _suggestedName(PreventivoBuilderProvider prov) {
    final safeClient =
        (prov.cliente?.ragioneSociale ?? 'cliente').replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_');
    final date = DateFormat('yyyy-MM-dd').format(prov.dataEvento ?? DateTime.now());
    return 'preventivo_${safeClient}_$date.pdf';
  }

  Future<void> _creaNuovoCliente() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
      _busyAction = 'create';
    });

    try {
      final sw = Stopwatch()..start();
      Cliente? nuovoCliente;
      try {
        final uid = FirebaseAuth.instance.currentUser!.uid; // 🔹 aggiunta per prendere l’utente loggato
        final dataToSave = Cliente(
          idCliente: '',
          tipo: 'cliente',
          ragioneSociale: _nomeClienteController.text.trim(),
          telefono01: _telefonoController.text.trim(),
          mail: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
          codiceFiscale: _codiceFiscaleController.text.trim().isNotEmpty ? _codiceFiscaleController.text.trim() : null,
        ).toJson();

        // 🔹 aggiunta campo obbligatorio per le regole
        dataToSave['createdBy'] = uid;

        // 🔍 DEBUG: mostra path e dati
        print('[DEBUG_CREA_CLIENTE] path=clienti data=${jsonEncode(dataToSave)}');

        final docRef = await FirebaseFirestore.instance.collection('clienti').add(dataToSave);
        final docSnapshot = await docRef.get();
        nuovoCliente = Cliente.fromFirestore(docSnapshot);
      } catch (e) {
        print('Errore creazione cliente al volo: $e');
      }
      sw.stop();
      _logUi('creaNuovoContatto ${sw.elapsedMilliseconds}ms (ok=${nuovoCliente != null})');

      if (nuovoCliente != null && mounted) {
        final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
        prov.setNoteIntegrative(_noteIntegrativeController.text);
        prov.setCliente(nuovoCliente);
        _popolaCampiDalBuilder(prov);
        setState(() => _isNuovoCliente = false);

        _showSnack(const SnackBar(
          content: Text('Nuovo cliente creato con successo!'),
          backgroundColor: Colors.green,
        ));
      } else if (mounted) {
        _showSnack(const SnackBar(content: Text('Errore durante la creazione del nuovo cliente.')));
      }
    } catch (e) {
      _showSnack(SnackBar(content: Text('Errore: $e')));
      _logUi('create cliente error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _busyAction = null;
        });
      }
    }
  }

  void _navigateBack(bool result) {
    if (!mounted) return;
    int popCount = 0;
    Navigator.of(context).popUntil((route) {
      popCount++;
      if (popCount >= 3) {
        Navigator.of(context).pop(result);
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nomeClienteController.dispose();
    _noteIntegrativeController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _codiceFiscaleController.dispose(); // 🟢 AGGIUNGE DISPOSE
    _nomeEventoController.dispose();
    _accontoController.dispose();
    _nomeClienteFocusNode.dispose();

    // ❌ NIENTE lookup dal context in dispose
    _preventiviProv?.setEditingOpen(false);

    super.dispose();
  }

  void _onTelefonoChanged(String telefono) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (telefono.length >= 6) {
        final clientiProvider = Provider.of<ClientiProvider>(context, listen: false);
        clientiProvider.cercaClientePerTelefono(telefono).then((cliente) {
          if (!mounted) return;
          setState(() {
            if (cliente != null) {
              final prov =
                  Provider.of<PreventivoBuilderProvider>(context, listen: false)
                    ..setCliente(cliente);
              _popolaCampiDalBuilder(prov);
              _isNuovoCliente = false;
            } else {
              _isNuovoCliente = true;
            }
          });
        });
      } else {
        setState(() => _isNuovoCliente = false);
      }
    });
  }

  Future<void> _selezionaClienteDaLista() async {
    final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    prov.setNoteIntegrative(_noteIntegrativeController.text);

    final tmp = _accontoController.text.trim();
    final parsed = double.tryParse(tmp.replaceAll(',', '.'));
    _setAccontoNullable(prov, tmp.isEmpty ? null : parsed);

    final risultato = await Navigator.push<Cliente?>(
      context,
      MaterialPageRoute(
        builder: (context) => CercaClienteScreen(isSelectionMode: true),
      ),
    );

    if (risultato != null && mounted) {
      prov.setCliente(risultato);
      _popolaCampiDalBuilder(prov);
      setState(() => _isNuovoCliente = false);
    }
  }

  // =========================
  // 🔒 Dialoghi Privacy/Consenso
  // =========================
  Future<void> _showPrivacyDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Informativa sulla Privacy'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Text(_kInformativaCompleta),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _askPrivacyConsent(String preventivoId) async {
    bool hasOpenedPrivacy = false;
    bool accepted = false;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Consenso e Privacy'),
              content: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kConsensoBreve),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('Visualizza l’Informativa sulla Privacy'),
                      onPressed: () async {
                        await _showPrivacyDialog();
                        setState(() => hasOpenedPrivacy = true);
                      },
                    ),
                    const Divider(),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: accepted,
                      onChanged: (v) => setState(() => accepted = v ?? false),
                      title: const Text('Ho letto e accetto quanto sopra'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (!hasOpenedPrivacy)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Per continuare devi prima visualizzare l’Informativa.',
                          style: TextStyle(fontSize: 12, color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: (accepted && hasOpenedPrivacy)
                      ? () async {
                          try {
                            await FirebaseFirestore.instance
                                .collection('preventivi')
                                .doc(preventivoId)
                                .set({
                              'privacy_consent': true,
                              'privacy_consent_at': Timestamp.now(),
                              'privacy_policy_version': _kPrivacyPolicyVersion,
                              'privacy_policy_url': _kPrivacyPolicyUrl,
                            }, SetOptions(merge: true));
                          } catch (_) {}
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        }
                      : null,
                  child: const Text('Accetto e procedi alla firma'),
                ),
              ],
            );
          },
        );
      },
    ) ?? false;
  }

  Widget _buildConfermaCard(PreventivoBuilderProvider builder) {
    final hasId = (builder.preventivoId ?? '').isNotEmpty;
    if (!hasId) return const SizedBox.shrink();

    final String status = builder.status ?? 'bozza';
    final bool isConfermato = status.toLowerCase() == 'confermato';

    Widget _spinner() => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );

    Future<void> _acquisisciFirmaEConferma() async {
      if (_isProcessing) return;

      _aggiornaBuilderDaiController(); // Salva Codice Fiscale e altri dati

      if (builder.cliente == null || (builder.cliente!.codiceFiscale ?? '').isEmpty) {
        _showSnack(const SnackBar(content: Text('Inserisci il Codice Fiscale prima di confermare la firma.'), backgroundColor: Colors.red));
        return;
      }
      
      if ((builder.preventivoId ?? '').isEmpty) {
        final salvataggioOk = await _salvaSuFirebase(popOnSuccess: false);
        if (!salvataggioOk) {
          _showSnack(const SnackBar(content: Text('Salvataggio iniziale fallito. Impossibile procedere con la firma.')));
          return;
        }
      }

      setState(() {
        _isProcessing = true;
        _busyAction = 'firma';
      });

      try {
        _logUi('5. Inizio Acquisizione Firme...');

        // 🔒 PRIMA: popup Consenso + visualizzazione Informativa obbligatoria
        final preventivoId = builder.preventivoId!;
        final consentOk = await _askPrivacyConsent(preventivoId);
        if (!consentOk) {
          _logUi('Consenso non fornito. Interrompo la procedura di firma.');
          if (mounted) setState(() { _isProcessing = false; _busyAction = null; });
          return;
        }
        
        // 1. ACQUISIZIONE PRIMA FIRMA CLIENTE
        final Uint8List? pngCliente1 = await showDialog<Uint8List?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const FirmaDialog(title: 'Firma Cliente (Contratto)'),
        );
        if (pngCliente1 == null || pngCliente1.isEmpty) {
          _logUi('Acquisizione Firma Cliente 1 ANNULLATA.');
          if (mounted) setState(() { _isProcessing = false; _busyAction = null; });
          return;
        }

        // 2. ACQUISIZIONE SECONDA FIRMA CLIENTE (NUOVA RICHIESTA)
        final Uint8List? pngCliente2 = await showDialog<Uint8List?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const FirmaDialog(title: 'Firma Cliente (Condizioni)'),
        );
        if (pngCliente2 == null || pngCliente2.isEmpty) {
          _logUi('Acquisizione Firma Cliente 2 ANNULLATA.');
          if (mounted) setState(() { _isProcessing = false; _busyAction = null; });
          return;
        }
        
        // 3. ACQUISIZIONE FIRMA RISTORATORE (PEPE ROSA)
        final Uint8List? pngRisto = await showDialog<Uint8List?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const FirmaDialog(title: 'Firma Pepe Rosa'),
        );
        if (pngRisto == null || pngRisto.isEmpty) {
          _logUi('Acquisizione Firma Ristoratore ANNULLATA.');
          if (mounted) setState(() { _isProcessing = false; _busyAction = null; });
          return;
        }
        _logUi('6. Tutte le firme sono state acquisite (bytes > 0). Inizio composizione e upload.');

        // 4. COMPOSIZIONE PRIMA FIRMA (Come prima)
        final headerText = 'Nettuno ${DateFormat('dd/MM/yyyy').format(DateTime.now())}';
        final composed1 = await _composeDualSignaturePng(
          firmaCliente: pngCliente1,
          firmaRistoratore: pngRisto,
          headerText: headerText,
          didascaliaSinistra: 'Firma Cliente',
          didascaliaDestra: 'Gabriele Castellano',
          style: const SignatureParams(
            padding: 24.0,
            leftInset: 10.0,
            rightInset: 90.0,
            minGap: 800.0,
            headerDownshift: 56.0,
            headerFs: 48.0, 
            captionFs: 48.0,
            maxSignH: 300.0,
            captionsGap: 8.0,
            headerExtraTop: 12.0,
          ),
        );
        
        // 5. UPLOAD DELLE FIRME SEPARATAMENTE
        _logUi('7. Inizio upload Firma 1 (Composta)...');
        final firmaUrl1 = await _storageService.uploadSignature(
          preventivoId,
          composed1,
          'firma_composta_1.png',
        );
        _logUi('7a. URL Firma 1 Composta (Storage): ${firmaUrl1 ?? 'NULL'}');

        _logUi('8. Inizio upload Firma 2 (Singola Cliente)...');
        final firmaUrl2 = await _storageService.uploadSignature(
          preventivoId,
          pngCliente2,
          'firma_cliente_2.png',
        );
        _logUi('8a. URL Firma 2 Cliente (Storage): ${firmaUrl2 ?? 'NULL'}');

        // 6. AGGIORNAMENTO FIRESTORE E PROVIDER
        _logUi('9. Aggiornamento Firestore con i nuovi URL.');
        await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).update({
          'status': 'Confermato',
          'data_conferma': Timestamp.now(),
          'firma_url': firmaUrl1, // Prima firma (composta)
          'firma_url_cliente_2': firmaUrl2, // 🟢 SECONDA FIRMA CLIENTE
        });

        builder.setFirmaUrl(firmaUrl1); // Aggiorna provider
        builder.setFirmaUrlCliente2(firmaUrl2); // Aggiorna provider
        builder.setStato('Confermato'); // Aggiorna provider
        
        _logUi('10. Provider aggiornato. Firma1: ${builder.firmaUrl?.length ?? 0}, Firma2: ${builder.firmaUrlCliente2?.length ?? 0}');

        _showSnack(const SnackBar(
          content: Text('Preventivo confermato e firmato con successo!'),
          backgroundColor: Colors.green,
        ));
      } catch (e) {
        _showSnack(SnackBar(
          content: Text('Errore durante la conferma: $e'),
          backgroundColor: Colors.red,
        ));
        _logUi('doppia-firma+conferma error: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _busyAction = null;
          });
        }
      }
    }

    final bool isProcessing = _isProcessing;
    final bool isEnabled = !isConfermato && !isProcessing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: (isProcessing && _busyAction == 'firma') ? _spinner() : const Icon(Icons.edit),
              label: Text(isConfermato ? 'Preventivo CONFERMATO (Disabilitato)' : 'Acquisisci firme & Conferma'),
              onPressed: isEnabled ? _acquisisciFirmaEConferma : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConfermato
                    ? Colors.grey.shade400
                    : Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: isConfermato
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSecondaryContainer,
                disabledBackgroundColor: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _composeDualSignaturePng({
    required Uint8List firmaCliente,
    required Uint8List firmaRistoratore,
    required String headerText,
    required String didascaliaSinistra,
    required String didascaliaDestra,
    SignatureParams? style,
  }) async {
    final p = style ?? defaultSignatureParams();

    final ui.Image imgC = await _decodeUiImage(firmaCliente);
    final ui.Image imgR = await _decodeUiImage(firmaRistoratore);

    final double sC = math.min(p.maxSignH / imgC.height, 1.0);
    final double sR = math.min(p.maxSignH / imgR.height, 1.0);
    final double wC = imgC.width * sC, hC = imgC.height * sC;
    final double wR = imgR.width * sR, hR = imgR.height * sR;
    final double rowH = math.max(hC, hR);

    final headerTp = TextPainter(
      text: TextSpan(
        text: headerText,
        style: TextStyle(
          fontSize: p.headerFs,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);

    final capLeft = TextPainter(
      text: TextSpan(
        text: didascaliaSinistra,
        style: TextStyle(
          fontSize: p.captionFs,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: wC);

    final capRight = TextPainter(
      text: TextSpan(
        text: didascaliaDestra,
        style: TextStyle(
          fontSize: p.captionFs,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: wR);

    final double contentMinW = p.leftInset + wC + p.minGap + wR + p.rightInset;
    final double width = p.padding + contentMinW + p.padding;

    final double headerH = headerTp.height + p.headerExtraTop;
    final double captionsH = math.max(capLeft.height, capRight.height) + p.captionsGap;
    final double height =
        p.padding + headerH + p.headerDownshift + captionsH + rowH + p.padding;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

    double y = p.padding;
    headerTp.paint(canvas, ui.Offset(p.padding, y));
    y += headerH + p.headerDownshift;

    final double xLeft = p.padding + p.leftInset;
    final double xRight = width - p.padding - p.rightInset - wR;

    capLeft.paint(canvas, ui.Offset(xLeft, y));
    capRight.paint(canvas, ui.Offset(xRight, y));
    y += captionsH;

    final double yC = y + (rowH - hC) / 2.0;
    final double yR = y + (rowH - hR) / 2.0;

    canvas.drawImageRect(
      imgC,
      ui.Rect.fromLTWH(0, 0, imgC.width.toDouble(), imgC.height.toDouble()),
      ui.Rect.fromLTWH(xLeft, yC, wC, hC),
      ui.Paint(),
    );
    canvas.drawImageRect(
      imgR,
      ui.Rect.fromLTWH(0, 0, imgR.width.toDouble(), imgR.height.toDouble()),
      ui.Rect.fromLTWH(xRight, yR, wR, hR),
      ui.Paint(),
    );

    final picture = recorder.endRecording();
    final out = await picture.toImage(width.ceil(), height.ceil());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  double _measureTextHeight(String text, TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    return tp.height;
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Widget _buildCardCercaCliente() {
    return ListTile(
      tileColor: Theme.of(context).colorScheme.secondary.withOpacity(0.85),
      leading: const Icon(Icons.search),
      title: const Text('Cerca un cliente esistente'),
      subtitle: const Text('Sovrascriverà i campi sottostanti'),
      onTap: _isProcessing ? null : _selezionaClienteDaLista,
    );
  }

  // 🔑 DEFINIZIONE DEL METODO SPOSTATA QUI PER RISOLVERE L'ERRORE DI UNDEFINED
  Widget _buildNavigationControls() {
    Widget _spinner() => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );

    return Container(
      padding: const EdgeInsets.all(12.0), // ridotto da 16
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 9,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14), // ridotto
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Colors.black26, width: 1.2),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                minimumSize: const Size(0, 44), // assicura altezza senza forzare larghezza
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _isProcessing
                  ? null
                  : () {
                      _aggiornaBuilderDaiController();
                      Navigator.of(context).pop();
                    },
              child: Row(
                mainAxisSize: MainAxisSize.min, // non occupa spazio extra
                children: const [
                  Icon(Icons.arrow_back_ios_new, size: 18),
                  SizedBox(width: 8),
                  Text('Servizi'),
                  // RIMOSSO Spacer() che causava allargamento forzato
                ],
              ),
            ),
          ),
          const SizedBox(width: 8), // ridotto da 12
          Expanded(
            flex: 10,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12), // ridotto
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: (_busyAction == 'save') ? _spinner() : const Icon(Icons.save),
              label: const Text('Salva'),
              onPressed: _isProcessing ? null : () => _salvaSuFirebase(popOnSuccess: false),
            ),
          ),
          const SizedBox(width: 8), // ridotto da 12
          Expanded(
            flex: 10,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12), // ridotto
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: (_busyAction == 'pdf' || _pdfBusy) ? _spinner() : const Icon(Icons.picture_as_pdf),
              label: const Text('genera PDF'),
              onPressed: _pdfBusy ? null : _onTapGeneraPdf,
            ),
          ),
        ],
      ),
    );
  }

  // 🔑 FINE DEFINIZIONE _buildNavigationControls

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<PreventivoBuilderProvider>(context, listen: true);

    final String status = prov.status ?? 'Bozza';
    final bool isConfermato = status.toLowerCase() == 'confermato';
    final String statusText = status.toUpperCase();

    final Widget statusChip = (prov.preventivoId ?? '').isNotEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Chip(
                label: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                backgroundColor:
                    isConfermato ? Colors.green.shade600 : Colors.red.shade600,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              ),
            ),
          )
        : const SizedBox.shrink();

    // 🟢 Dati per il riepilogo
    final bool isPacchettoFisso = prov.isPacchettoFisso;
    final double prezzoPacchetto = prov.prezzoPacchettoSelezionato;
    final double costoServizi = prov.costoServizi;
    final double subtotale = prov.subtotale;
    final double sconto = prov.sconto;
    final double totaleFinale = prov.totaleFinale;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa Preventivo'),
        actions: [
          statusChip,
          IconButton(
            tooltip: 'Torna ai Preventivi',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ArchivioPreventiviScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Torna alla Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          /* IconButton(
            tooltip: 'Check coerenza Provider ↔︎ DB',
            icon: const Icon(Icons.rule_folder_outlined),
            onPressed: () async {
              final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
              prov.setNoteIntegrative(_noteIntegrativeController.text);
              final id = prov.preventivoId ?? '';
              if (id.isEmpty) {
                _showSnack(const SnackBar(content: Text('Salva prima il preventivo per ottenere un ID.')));
                return;
              }
              try {
                await _runConsistencyCheck();
              } catch (e) {
                _showSnack(SnackBar(content: Text('Errore nel check: $e')));
              }
            },
          ), */
        ],
      ),
      body: Column(
        children: [
          WizardStepper(
            currentStep: 2,
            steps: const ['Menu', 'Servizi', 'Cliente'],
            onStepTapped: (index) {
              _aggiornaBuilderDaiController();
              if (index == 1) {
                Navigator.of(context).pop();
              } else if (index == 0) {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              }
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                autovalidateMode:
                    _autoValidate ? AutovalidateMode.always : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Note integrative (in cima) ---
                    Text('Note integrative', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteIntegrativeController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Inserisci eventuali note...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _aggiornaBuilderDaiController(),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Dati Cliente',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 16),
                            _buildCardCercaCliente(),
                            const SizedBox(height: 16),
                            TextFormField(
                              focusNode: _nomeClienteFocusNode,
                              controller: _nomeClienteController,
                              decoration: const InputDecoration(
                                labelText: 'Nome Cliente / Ragione Sociale',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Campo obbligatorio';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _telefonoController,
                              decoration: const InputDecoration(
                                labelText: 'Telefono Principale',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.phone,
                              onChanged: _onTelefonoChanged,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email (Opzionale)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            TextFormField(
                              controller: _codiceFiscaleController,
                              decoration: const InputDecoration(
                                labelText: 'Codice Fiscale',
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 16,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: (_busyAction == 'create')
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.person_add_alt_1),
                              label: const Text('Crea e Seleziona Nuovo Cliente'),
                              onPressed: (_isNuovoCliente && !_isProcessing)
                                  ? () => _creaNuovoCliente()
                                  : null,
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green.shade600,
                                disabledBackgroundColor: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Acconto',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _accontoController,
                              decoration: const InputDecoration(
                                labelText: 'Acconto',
                                prefixText: '€ ',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildConfermaCard(prov),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Riepilogo costi',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),

                            // 🔴 INIZIO LOGICA CONDIZIONALE PACCHETTO/MENU 🔴
                            if (isPacchettoFisso)
                              // CASO PACCHETTO FISSO
                              Text(
                                'Prezzo Pacchetto: € ${prezzoPacchetto.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.bodyLarge,
                              )
                            else ...[
                              // CASO MENU A PORTATE
                              if ((prov.costoPacchettoWelcomeDolci) > 0)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${prov.labelPacchettoWelcomeDolci}: € ${(prov.costoPacchettoWelcomeDolci).toStringAsFixed(2)}',
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                              
                              Text('Menu Adulti: € ${prov.costoMenuAdulti.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.bodyLarge),
                              
                              Text('Menu Bambini: € ${prov.costoMenuBambini.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.bodyLarge),
                            ],
                            // 🔴 FINE LOGICA CONDIZIONALE 🔴

                            Text('Servizi Extra: € ${costoServizi.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.bodyLarge),
                            const SizedBox(height: 4),
                            Divider(color: Colors.grey.shade600),
                            const SizedBox(height: 4),
                            Text('Subtotale: € ${subtotale.toStringAsFixed(2)}'),
                            Text('Sconto: -€ ${sconto.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            Text(
                              'Totale Finale: € ${totaleFinale.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildNavigationControls(), // 🔑 CHIAMATA CORRETTA
        ],
      ),
    );
  }
}
