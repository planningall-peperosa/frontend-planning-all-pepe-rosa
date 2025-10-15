// lib/screens/dati_cliente_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert'; // <-- NEW: per snapshot JSON canonico

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- AGGIUNTO per MethodChannel
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:file_selector/file_selector.dart' as fs;
// NEW: condivisione
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

enum _SignatureLayout { vertical, horizontal }

// =========================
//  PARAMETRI DI LAYOUT FIRME (TOP-LEVEL)
// =========================
class SignatureParams {
  final double padding;         // margine esterno del canvas PNG
  final double leftInset;       // spostamento a destra del blocco firma Cliente
  final double rightInset;      // margine dal bordo destro per blocco Pepe Rosa
  final double minGap;          // distanza minima orizzontale tra le due firme
  final double headerDownshift; // quanto scendere dopo "Nettuno data" prima delle etichette
  final double headerFs;        // font size "Nettuno data"
  final double captionFs;       // font size "Firma Cliente" / "Firma Pepe Rosa"
  final double maxSignH;        // altezza massima delle PNG firma (evita upscaling)
  final double captionsGap;     // gap sotto le etichette prima delle firme
  final double headerExtraTop;  // extra-padding sotto "Nettuno data"

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

/// Modifica questi valori per regolare in modo stabile il layout delle firme.
SignatureParams defaultSignatureParams() => const SignatureParams(
  padding: 24.0,
  leftInset: 10.0,     // aumenta per spostare più a destra la firma cliente
  rightInset: 90.0,    // aumenta per spostare più a destra la firma Pepe Rosa
  minGap: 800.0,       // aumenta per allargare la distanza tra le due firme
  headerDownshift: 56.0, // rende etichette + firme più in basso rispetto a "Nettuno data"
  headerFs: 40.0,      // grandezza "Nettuno data"
  captionFs: 32.0,     // grandezza "Firma Cliente"/"Firma Pepe Rosa"
  maxSignH: 300.0,     // scala massima in altezza per le PNG delle firme
  captionsGap: 8.0,    // spazio tra etichette e immagini firma
  headerExtraTop: 12.0,// piccolo margine sotto l'header
);

// --- LOG helper ---
void _logUi(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
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

  final _nomeClienteController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _nomeEventoController = TextEditingController();

  final _accontoController = TextEditingController();

  // NEW: focus ed autovalidazione
  final _nomeClienteFocusNode = FocusNode();
  bool _autoValidate = false;

  Timer? _debounce;
  bool _isNuovoCliente = false;

  bool _isProcessing = false; // disabilita azioni durante un task
  String? _busyAction; // 'create' | 'save' | 'pdf' | 'firma'

  // Snapshot payload canonico all'apertura (FALLBACK se il provider non espone dirty flag)
  String? _openedPayloadJson;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
      _popolaCampiDalBuilder(prov);

      // >>> MOD: listener che salva NULL quando il campo è vuoto
      _accontoController.addListener(() {
        final raw = _accontoController.text.trim().replaceAll(',', '.');
        if (raw.isEmpty) {
          _setAccontoNullable(prov, null);
        } else {
          final val = double.tryParse(raw);
          if (val != null) {
            _setAccontoNullable(prov, val);
          }
        }
      });
      // <<< MOD

      setState(() {
        _isNuovoCliente = prov.cliente == null || (prov.cliente!.idCliente.isEmpty);
      });

      // Fallback snapshot iniziale (se non useremo il dirty flag)
      _openedPayloadJson = _payloadJsonFor(prov);

      // >>> NEW: segnala che siamo nello screen di editing (sospende refresh/version-check di fondo)
      context.read<PreventiviProvider>().setEditingOpen(true);
      // <<< NEW

      _logUi(
          'init done (cliente=${prov.cliente?.ragioneSociale ?? "-"}, preventivoId=${prov.preventivoId ?? "-"})');
    });
  }

  // --- MOD: helper per impostare acconto come nullable se disponibile ---
  void _setAccontoNullable(PreventivoBuilderProvider prov, double? valore) {
    try {
      final dyn = prov as dynamic;
      // se esiste un setter nullable, usalo
      dyn.setAccontoNullable(valore);
      return;
    } catch (_) {
      // fallback: se non esiste, usa setAcconto(double) se hai un valore
      if (valore != null) {
        try {
          final dyn = prov as dynamic;
          dyn.setAcconto(valore);
          return;
        } catch (_) {}
      } else {
        // nessun metodo nullable disponibile
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compila i campi obbligatori: Nome Cliente')),
      );
    }
    return isValid;
  }


Future<bool> _salvaSuFirebase({bool popOnSuccess = false}) async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compila i campi obbligatori prima di salvare.'), backgroundColor: Colors.red),
      );
      return false;
    }
    
    setState(() {
       _isProcessing = true;
       _busyAction = 'save';
    });
    
    _aggiornaBuilderDaiController();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
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
      
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Preventivo salvato con successo!'), backgroundColor: Colors.green),
      );

      if (popOnSuccess && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      success = true;

    } catch (e) {
      scaffoldMessenger.showSnackBar(
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
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: BorderSide.none,
              ),
              onPressed: _isProcessing
                  ? null
                  : () {
                      _aggiornaBuilderDaiController();
                      Navigator.of(context).pop();
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.arrow_back_ios_new),
                  SizedBox(width: 8),
                  Text('Servizi extra'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              icon: (_busyAction == 'save') ? _spinner() : const Icon(Icons.save),
              label: const Text('Salva'),
              onPressed: _isProcessing ? null : () => _salvaSuFirebase(popOnSuccess: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              icon: (_busyAction == 'pdf') ? _spinner() : const Icon(Icons.picture_as_pdf),
              label: const Text('Genera PDF'),
              onPressed: _isProcessing ? null : _salvaEGeneraPdf,
            ),
          ),
        ],
      ),
    );
  }



  // La vecchia funzione _salva ora è obsoleta. Puoi cancellarla o lasciarla vuota.
  Future<void> _salva() async {
    _logUi('CHIAMATA A FUNZIONE DEPRECATA _salva(). Usare _salvaSuFirebase().');
  }



  // =================================================
  // --- FUNZIONE PDF AGGIORNATA ---
  // =================================================
  Future<void> _salvaEGeneraPdf() async {
    if (!_validateFormOrNotify()) return;

    final total = Stopwatch()..start();
    _logUi('PDF start');
    setState(() {
      _isProcessing = true;
      _busyAction = 'pdf';
    });
    
    _aggiornaBuilderDaiController();

    final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    // Manteniamo il vecchio service solo per la generazione del PDF
    final service = PreventiviService();

    try {
      // --- MODIFICA APPLICATA QUI ---
      // Passo 1: Salva sempre prima su Firebase se ci sono modifiche, usando la nostra nuova funzione.
      if (_hasLocalChangesDyn(prov)) {
        // Chiamiamo la nuova funzione di salvataggio e attendiamo il risultato.
        // popOnSuccess è false perché non vogliamo chiudere la schermata.
        final salvataggioOk = await _salvaSuFirebase(popOnSuccess: false);
        
        // Se il salvataggio su Firebase fallisce, interrompiamo l'intera operazione.
        if (!salvataggioOk) {
          throw Exception('Salvataggio su Firebase fallito prima della generazione del PDF.');
        }
      }
      
      // A questo punto, siamo sicuri che i dati sono salvati e aggiornati su Firebase.

      // Passo 2: Crea il payload nel vecchio formato, ancora richiesto dal servizio PDF.
      // Questa parte è un "ponte" temporaneo verso il vecchio backend.
      final payloadCompleto = prov.creaPayloadSalvataggio();
      if (payloadCompleto == null) throw Exception('Dati incompleti per la generazione del PDF');

      final body = {
        'preventivo_id': prov.preventivoId, // L'ID è ora disponibile anche per i nuovi preventivi dopo il primo salvataggio.
        'payload': payloadCompleto['payload'],
      };

      // Passo 3: Chiama il vecchio servizio Python per generare il PDF.
      final swPdf = Stopwatch()..start();
      final bytes = await service.salvaEGeneraPdf(body);
      swPdf.stop();
      _logUi('service.salvaEGeneraPdf ${swPdf.elapsedMilliseconds}ms (bytes=${bytes.length})');

      // Passo 4: Gestisci il file PDF generato (questa logica rimane invariata).
      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        await _savePdfDesktop(bytes, prov);
      } else if (!kIsWeb && Platform.isAndroid) {
        await _presentAndroidPdfActions(bytes, prov);
      } else if (!kIsWeb && Platform.isIOS) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: _suggestedName(prov), mimeType: 'application/pdf')],
          text: 'Preventivo',
        );
      } else {
        final tmp = await getTemporaryDirectory();
        final file = File('${tmp.path}/${_suggestedName(prov)}');
        await file.writeAsBytes(bytes, flush: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF creato: ${file.path}')),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generato con successo')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
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

  // ====================== DESKTOP SAVE (file_selector) =======================
  Future<void> _savePdfDesktop(Uint8List pdfBytes, PreventivoBuilderProvider prov) async {
    final suggestedName = _suggestedName(prov);

    final home = Platform.environment['HOME'] ?? '';
    final defaultDir =
        home.isNotEmpty ? '$home/Documents/planning_all-pepe_rosa-PDF' : Directory.systemTemp.path;
    try {
      await Directory(defaultDir).create(recursive: true);
    } catch (_) {}

    final saveLoc = await fs.getSaveLocation(
      suggestedName: suggestedName,
      initialDirectory: defaultDir,
    );
    if (saveLoc == null) return;

    final file = File(saveLoc.path);
    await file.writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF salvato in: ${file.path}')),
    );
  }

  // =================== ANDROID ACTIONS (Share / Save via SAF) ===============
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

                    if (!mounted) return;
                    if (ok == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PDF salvato.')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Operazione annullata.')),
                      );
                    }
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Errore salvataggio: $e')),
                    );
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

  String _suggestedName(PreventivoBuilderProvider prov) {
    final nomeCliente = prov.cliente?.ragioneSociale ?? 'cliente';
    final nomeClienteSafe = nomeCliente.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_');
    final dataSafe = (prov.dataEvento ?? DateTime.now());
    return 'preventivo_${nomeClienteSafe}_${DateFormat('yyyy-MM-dd').format(dataSafe)}.pdf';
  }

  // ====================== (AGGIUNTO) CREA NUOVO CLIENTE ======================
  Future<void> _creaNuovoCliente() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;        // blocca tap multipli
      _busyAction = 'create';      // mostra spinner sul bottone
    });

    final clientiProvider = Provider.of<ClientiProvider>(context, listen: false);

    try {
      final sw = Stopwatch()..start();
      final nuovoCliente = await clientiProvider.creaNuovoContatto({
        'tipo': 'cliente',
        'ragione_sociale': _nomeClienteController.text,
        'telefono_01': _telefonoController.text,
        'mail': _emailController.text,
        'ruolo': null,
      });
      sw.stop();
      _logUi('creaNuovoContatto ${sw.elapsedMilliseconds}ms (ok=${nuovoCliente != null})');

      if (nuovoCliente != null && mounted) {
        final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
        prov.setCliente(nuovoCliente);
        _popolaCampiDalBuilder(prov);
        setState(() => _isNuovoCliente = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nuovo cliente creato con successo!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: ${clientiProvider.error}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
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

  Future<void> _duplicaPreventivo() async {
    if (_isProcessing) return;
    if (!_validateFormOrNotify()) return;

    setState(() {
      _isProcessing = true;
      _busyAction = null;
    });
    _aggiornaBuilderDaiController();

    final prov = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    final preventiviProvider = Provider.of<PreventiviProvider>(context, listen: false);

    try {
      final sw = Stopwatch()..start();
      final summary = await prov.duplicaPreventivo(preventiviProvider: preventiviProvider);
      sw.stop();
      _logUi('duplicaPreventivo ${sw.elapsedMilliseconds}ms (ok=${summary != null})');

      if (!mounted) return;
      if (summary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duplicazione fallita')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preventivo duplicato')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore duplicazione: $e')),
      );
      _logUi('duplica error: $e');
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

    context.read<PreventiviProvider>().setEditingOpen(false);

    super.dispose();
  }

  void _onTelefonoChanged(String telefono) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
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
        if (mounted) setState(() => _isNuovoCliente = false);
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

  // ===== FIRMA (doppia firma: Cliente + Pepe Rosa) =====
  Widget _buildConfermaCard(PreventivoBuilderProvider builder) {
    final hasId = (builder.preventivoId ?? '').isNotEmpty;
    if (!hasId) return const SizedBox.shrink();

    final bool isConfermato = _isConfermatoDyn(builder);

    Widget _spinner() => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );

    Future<void> _acquisisciFirmaEConferma() async {
      if (_isProcessing) return;

      // 1) Firma CLIENTE
      final Uint8List? pngCliente = await showDialog<Uint8List?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const FirmaDialog(title: 'Firma del cliente'),
      );
      if (pngCliente == null || pngCliente.isEmpty) return;

      // 2) Firma RISTORATORE
      final Uint8List? pngRisto = await showDialog<Uint8List?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const FirmaDialog(title: 'Firma Pepe Rosa'),
      );
      if (pngRisto == null || pngRisto.isEmpty) return;

      setState(() {
        _isProcessing = true;
        _busyAction = 'firma';
      });

      try {
        // salva eventuali modifiche pendenti prima della conferma
        if (_hasLocalChangesDyn(builder)) {
          final preventiviProvider =
              Provider.of<PreventiviProvider>(context, listen: false);
          final summary =
              await builder.salvaPreventivo(preventiviProvider: preventiviProvider);
          if (summary == null) throw Exception('Salvataggio fallito prima della conferma');
          _clearLocalChangesDyn(builder);
        }

        // Header unico "Nettuno gg/mm/aaaa"
        final headerText = 'Nettuno ${DateFormat('dd/MM/yyyy').format(DateTime.now())}';

        // 3) Componi PNG (etichette sopra, cliente a sinistra / Pepe Rosa a destra, distanziate)
        final composed = await _composeDualSignaturePng(
          firmaCliente: pngCliente,
          firmaRistoratore: pngRisto,
          headerText: headerText,
          didascaliaSinistra: 'Firma Cliente',
          didascaliaDestra: 'Firma Pepe Rosa',
        );

        // 4) Upload + (ri)conferma: sovrascrive la firma anche se già confermato
        final preventivoId = builder.preventivoId!;
        final ok = await context
            .read<PreventiviProvider>()
            .caricaFirmaEConferma(preventivoId, composed);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? (isConfermato
                    ? 'Firme riacquisite e aggiornate.'
                    : 'Firme acquisite e preventivo confermato.')
                : 'Errore durante acquisizione firme.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: (_busyAction == 'firma') ? _spinner() : const Icon(Icons.edit),
              label: Text(
                  isConfermato ? 'Riacquisisci firme (sostituisci)' : 'Acquisisci firma & Conferma'),
              onPressed: _isProcessing ? null : _acquisisciFirmaEConferma,
            ),
          ],
        ),
      ),
    );
  }

  /// Composizione del PNG con doppia firma:
  /// - Etichette sopra le rispettive firme, allineate a sinistra
  /// - Cliente a sinistra, Pepe Rosa a destra
  /// - Distanza, font e posizioni governate da [SignatureParams]
  Future<Uint8List> _composeDualSignaturePng({
    required Uint8List firmaCliente,
    required Uint8List firmaRistoratore,
    required String headerText,
    required String didascaliaSinistra,
    required String didascaliaDestra,
    SignatureParams? style, // opzionale: override a runtime
  }) async {
    // Parametri “vivi” (vengono ricreati ad ogni chiamata)
    final p = style ?? defaultSignatureParams();

    // Decode immagini
    final ui.Image imgC = await _decodeUiImage(firmaCliente);
    final ui.Image imgR = await _decodeUiImage(firmaRistoratore);

    // Scale uniformi senza upscaling
    final double sC = math.min(p.maxSignH / imgC.height, 1.0);
    final double sR = math.min(p.maxSignH / imgR.height, 1.0);
    final double wC = imgC.width * sC, hC = imgC.height * sC;
    final double wR = imgR.width * sR, hR = imgR.height * sR;
    final double rowH = math.max(hC, hR);

    // Header "Nettuno data"
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

    // Didascalie sopra le firme (allineate a sinistra della rispettiva firma)
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

    // Larghezza minima per garantire gap e inset desiderati
    final double contentMinW = p.leftInset + wC + p.minGap + wR + p.rightInset;
    final double width = p.padding + contentMinW + p.padding;

    // Altezze
    final double headerH = headerTp.height + p.headerExtraTop;
    final double captionsH = math.max(capLeft.height, capRight.height) + p.captionsGap;
    final double height =
        p.padding + headerH + p.headerDownshift + captionsH + rowH + p.padding;

    // Canvas
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

    // Header in alto a sinistra
    double y = p.padding;
    headerTp.paint(canvas, ui.Offset(p.padding, y));
    y += headerH + p.headerDownshift;

    // Posizioni X: cliente a sinistra, Pepe Rosa a destra
    final double xLeft = p.padding + p.leftInset;
    final double xRight = width - p.padding - p.rightInset - wR;

    // Etichette sopra e allineate a sinistra con la firma
    capLeft.paint(canvas, ui.Offset(xLeft, y));
    capRight.paint(canvas, ui.Offset(xRight, y));
    y += captionsH;

    // Allineamento verticale firme
    final double yC = y + (rowH - hC) / 2.0;
    final double yR = y + (rowH - hR) / 2.0;

    // Disegna firme
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

  // ----- (opzionali) helper legacy: non usati dalla composizione attuale, lasciati per compatibilità -----
  double _sectionHeightEstimate(
    ui.Image img,
    TextStyle hdrStyle,
    TextStyle lblStyle,
    double totalW,
    double pad,
    double textGapSmall,
    double textGapLarge,
  ) {
    // Stima altezza sezione: header + gap + label + gap + firma (senza upscaling)
    final headerH = _measureTextHeight('X', hdrStyle, totalW - pad * 2);
    final labelH = _measureTextHeight('X', lblStyle, totalW - pad * 2);
    return headerH + textGapSmall + labelH + textGapLarge + img.height.toDouble();
  }

  Future<double> _drawSignatureSection({
    required ui.Canvas canvas,
    required double totalW,
    required double startY,
    required String header,
    required String label,
    required ui.Image image,
    required double pad,
    required double textGapSmall,
    required double textGapLarge,
    ui.Rect? area, // opzionale: area limitata (per layout orizzontale)
  }) async {
    final double left = area?.left ?? 0;
    final double right = area != null ? area.right : totalW;
    final double usableW = (right - left) - pad * 2;

    // Header (es. "Nettuno 07/10/2025")
    final headerH = _paintText(
      canvas,
      text: header,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black),
      maxWidth: usableW,
      dx: left + pad,
      dy: startY,
    );

    // Label ("Firma Cliente"/"Pepe Rosa")
    final labelY = startY + headerH + textGapSmall;
    final labelH = _paintText(
      canvas,
      text: label,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black),
      maxWidth: usableW,
      dx: left + pad,
      dy: labelY,
    );

    // Firma: centrata, no upscaling
    final double y = labelY + labelH + textGapLarge;
    final double scale = math.min(usableW / image.width, 1.0);
    final double targetW = image.width * scale;
    final double targetH = image.height * scale;
    final double x = left + ((right - left) - targetW) / 2;

    final ui.Rect src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final ui.Rect dst = ui.Rect.fromLTWH(x, y, targetW, targetH);
    canvas.drawImageRect(image, src, dst, ui.Paint());

    return (y + targetH) - startY;
  }

  // ----- Text helpers -----
  double _paintText(ui.Canvas canvas,
      {required String text,
      required TextStyle style,
      required double maxWidth,
      required double dx,
      required double dy}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, ui.Offset(dx, dy));
    return tp.height;
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

      return Scaffold(
        appBar: AppBar(
          title: const Text('Completa Preventivo'),
          // --- MODIFICHE APPLICATE QUI ---
          actions: [
            IconButton(
              tooltip: 'Torna ai Preventivi',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () {
                // Chiude tutte le schermate del wizard e torna alla home,
                // poi apre l'archivio preventivi.
                Navigator.of(context).popUntil((route) => route.isFirst);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArchivioPreventiviScreen()));
              },
            ),
            IconButton(
              tooltip: 'Torna alla Home',
              icon: const Icon(Icons.home_outlined),
              onPressed: () {
                // Chiude tutte le schermate del wizard e torna alla home.
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
                      // Dati Cliente
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Dati Cliente', style: Theme.of(context).textTheme.titleLarge),
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
                                onPressed:
                                    (_isNuovoCliente && !_isProcessing) ? () => _creaNuovoCliente() : null,
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
                              Text('Acconto', style: Theme.of(context).textTheme.titleLarge),
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

                      // Card unica per acquisire firma & confermare
                      _buildConfermaCard(prov),
                      const SizedBox(height: 24),

                      // Riepilogo costi
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Riepilogo costi', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
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
  

