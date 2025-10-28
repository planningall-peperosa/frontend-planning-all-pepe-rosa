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
import 'cerca_cliente_screen.dart';
import '../widgets/wizard_stepper.dart';
import '../widgets/firma_dialog.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'archivio_preventivi_screen.dart';

import '../services/storage_service.dart';

import '../utils/pdf_generator.dart';
import '../models/preventivo_pdf_models.dart';

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
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _nomeEventoController = TextEditingController();
  final _accontoController = TextEditingController();

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

  // --- snackbar helper sicuro
  void _showSnack(SnackBar bar) {
    final m = _messenger;
    if (!mounted || m == null || !m.mounted) return;
    m.showSnackBar(bar);
  }

  @override
  void initState() {
    super.initState();
    // NB: non usare Provider.of qui per scrivere; farlo dopo in didChangeDependencies/post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
      _popolaCampiDalBuilder(prov);

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
    final c = prov.cliente;
    _nomeClienteController.text = c?.ragioneSociale ?? '';
    _telefonoController.text = c?.telefono01 ?? '';
    _emailController.text = c?.mail ?? '';
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

    final curr = prov.cliente ?? Cliente(idCliente: '', tipo: 'cliente');
    final clienteAggiornato = Cliente(
      idCliente: curr.idCliente,
      tipo: 'cliente',
      ragioneSociale: _nomeClienteController.text,
      telefono01: _telefonoController.text,
      mail: _emailController.text,
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
        const SnackBar(content: Text('Compila i campi obbligatori prima di salvare.'), backgroundColor: Colors.red),
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
      final dataToSave = builder.toFirestoreMap();
      final preventivoId = builder.preventivoId;

      if (preventivoId != null && preventivoId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).update(dataToSave);
      } else {
        final newDoc = await FirebaseFirestore.instance.collection('preventivi').add(dataToSave);
        builder.setPreventivoId(newDoc.id);
      }

      _clearLocalChangesDyn(builder);

      _showSnack(
        const SnackBar(content: Text('Preventivo salvato con successo!'), backgroundColor: Colors.green),
      );

      if (popOnSuccess && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      success = true;
    } catch (e) {
      _showSnack(
        SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red),
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
      final ok = await _salvaSuFirebase(popOnSuccess: false);
      if (!ok) {
        _showSnack(
          const SnackBar(content: Text('Errore nel salvataggio del preventivo')),
        );
        return;
      }

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

  Widget _buildNavigationControls() {
    Widget _spinner() => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );

    return Container(
      padding: const EdgeInsets.all(16.0),
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
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Colors.black26, width: 1.2),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
              ),
              onPressed: _isProcessing
                  ? null
                  : () {
                      _aggiornaBuilderDaiController();
                      Navigator.of(context).pop();
                    },
              child: Row(
                children: const [
                  Icon(Icons.arrow_back_ios_new, size: 18),
                  SizedBox(width: 8),
                  Text('       Servizi'),
                  Spacer(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 10,
            child: ElevatedButton.icon(
              icon: (_busyAction == 'save') ? _spinner() : const Icon(Icons.save),
              label: const Text('Salva'),
              onPressed: _isProcessing ? null : () => _salvaSuFirebase(popOnSuccess: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 10,
            child: ElevatedButton.icon(
              icon: (_busyAction == 'pdf' || _pdfBusy) ? _spinner() : const Icon(Icons.picture_as_pdf),
              label: const Text('Genera PDF'),
              onPressed: _pdfBusy ? null : _onTapGeneraPdf,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _salva() async {
    _logUi('CHIAMATA A FUNZIONE DEPRECATA _salva(). Usare _salvaSuFirebase().');
  }

  Future<void> _salvaEGeneraPdf() async {
    if (!_validateFormOrNotify()) return;

    final total = Stopwatch()..start();
    _logUi('PDF start');
    setState(() {
      _isProcessing = true;
      _busyAction = 'pdf';
    });

    _aggiornaBuilderDaiController();

    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    final service = PreventiviService();

    try {
      if (_hasLocalChangesDyn(builder)) {
        final salvataggioOk = await _salvaSuFirebase(popOnSuccess: false);
        if (!salvataggioOk) {
          throw Exception('Salvataggio su Firebase fallito prima della generazione del PDF.');
        }
      }

      final payloadCompleto = builder.creaPayloadSalvataggio();
      if (payloadCompleto == null) throw Exception('Dati incompleti per la generazione del PDF');
      final preventivoId = builder.preventivoId ?? '';

      // Provo a recuperare firma_url dal documento, se esiste
      String? firmaUrlDb;
      if (preventivoId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('preventivi')
            .doc(preventivoId)
            .get();
        final data = snap.data() ?? {};
        final maybe = data['firma_url'] as String?;
        if (maybe != null && maybe.isNotEmpty) {
          firmaUrlDb = maybe;
        }
      }

      // Costruisco il modello PDF includendo l'ID (e la firma se trovata)
      final preventivoObj = PreventivoCompletoPdf.fromMap({
        ...payloadCompleto['payload'] as Map<String, dynamic>,
        'preventivo_id': preventivoId,
        if (firmaUrlDb != null) 'firma_url': firmaUrlDb,
      });

      // Stato “preferito” dalla UI, ma il generatore lo risolverà comunque via DB
      final statoPreferito = builder.status ?? 'Bozza';

      final bytes = await generaPdfDaDatiDart(preventivoObj, statoPreferito);

      _logUi('Generazione PDF Dart completata (bytes=${bytes.length})');

      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        await _savePdfDesktop(bytes, builder);
      } else if (!kIsWeb && Platform.isAndroid) {
        await _presentAndroidPdfActions(bytes, builder);
      } else if (!kIsWeb && Platform.isIOS) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: _suggestedName(builder), mimeType: 'application/pdf')],
          text: 'Preventivo',
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
        final dataToSave = Cliente(
          idCliente: '',
          tipo: 'cliente',
          ragioneSociale: _nomeClienteController.text.trim(),
          telefono01: _telefonoController.text.trim(),
          mail: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        ).toJson();

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
    _telefonoController.dispose();
    _emailController.dispose();
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

    final tmp = _accontoController.text.trim();
    final parsed = double.tryParse(tmp.replaceAll(',', '.'));
    _setAccontoNullable(prov, tmp.isEmpty ? null : parsed);

    final risultato = await Navigator.push<Cliente?>(
      context,
      MaterialPageRoute(
        builder: (context) => const CercaClienteScreen(isSelectionMode: true),
      ),
    );

    if (risultato != null && mounted) {
      prov.setCliente(risultato);
      _popolaCampiDalBuilder(prov);
      setState(() => _isNuovoCliente = false);
    }
  }

  Widget _buildConfermaCard(PreventivoBuilderProvider builder) {
    final hasId = (builder.preventivoId ?? '').isNotEmpty;
    if (!hasId) return const SizedBox.shrink();

    final bool isConfermato = builder.status?.toLowerCase() == 'confermato';

    Widget _spinner() => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );

    Future<void> _acquisisciFirmaEConferma() async {
      if (_isProcessing) return;

      _aggiornaBuilderDaiController();

      if (builder.cliente == null) {
        _showSnack(const SnackBar(content: Text('Seleziona un cliente prima di confermare.')));
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
        final Uint8List? pngCliente = await showDialog<Uint8List?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const FirmaDialog(title: 'Firma del cliente'),
        );
        if (pngCliente == null || pngCliente.isEmpty) {
          if (mounted) setState(() { _isProcessing = false; _busyAction = null; });
          return;
        }

        final Uint8List? pngRisto = await showDialog<Uint8List?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const FirmaDialog(title: 'Firma Pepe Rosa'),
        );
        if (pngRisto == null || pngRisto.isEmpty) {
          if (mounted) setState(() { _isProcessing = false; _busyAction = null; });
          return;
        }

        final headerText = 'Nettuno ${DateFormat('dd/MM/yyyy').format(DateTime.now())}';
        final composed = await _composeDualSignaturePng(
          firmaCliente: pngCliente,
          firmaRistoratore: pngRisto,
          headerText: headerText,
          didascaliaSinistra: 'Firma Cliente',
          didascaliaDestra: 'Firma Pepe Rosa',
          style: const SignatureParams(
            padding: 24.0,
            leftInset: 10.0,
            rightInset: 90.0,
            minGap: 800.0,
            headerDownshift: 56.0,
            headerFs: 48.0,   // <-- più grande
            captionFs: 48.0,  // <-- più grande
            maxSignH: 300.0,
            captionsGap: 8.0,
            headerExtraTop: 12.0,
          ),
        );


        final preventivoId = builder.preventivoId!;

        final firmaUrl = await _storageService.uploadSignature(
          preventivoId,
          composed,
          'firma_composta.png',
        );

        await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).update({
          'status': 'Confermato',
          'data_conferma': Timestamp.now(),
          'firma_url': firmaUrl,
        });

        builder.setStato('Confermato');

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
              label: Text(isConfermato ? 'Preventivo CONFERMATO (Disabilitato)' : 'Acquisisci firma & Conferma'),
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
      leading: const Icon(Icons.search),
      title: const Text('Cerca un cliente esistente'),
      subtitle: const Text('Sovrascriverà i campi sottostanti'),
      onTap: _isProcessing ? null : _selezionaClienteDaLista,
    );
  }

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
                MaterialPageRoute(builder: (_) => const ArchivioPreventiviScreen()),
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

                            // 🔴 NUOVO: riga opzionale PRIMA di “Menù Adulti”
                            if ((prov.costoPacchettoWelcomeDolci ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${prov.labelPacchettoWelcomeDolci}: € ${(prov.costoPacchettoWelcomeDolci).toStringAsFixed(2)}',
                                ),
                              ),

                            Text('Menu Adulti: € ${prov.costoMenuAdulti.toStringAsFixed(2)}'),
                            Text('Menu Bambini: € ${prov.costoMenuBambini.toStringAsFixed(2)}'),
                            Text('Servizi Extra: € ${prov.costoServizi.toStringAsFixed(2)}'),
                            const SizedBox(height: 4),
                            Divider(color: Colors.grey.shade600),
                            const SizedBox(height: 4),
                            Text('Subtotale: € ${prov.subtotale.toStringAsFixed(2)}'),
                            Text('Sconto: -€ ${prov.sconto.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            Text(
                              'Totale Finale: € ${prov.totaleFinale.toStringAsFixed(2)}',
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
          _buildNavigationControls(),
        ],
      ),
    );
  }
}
