import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

// 🚨 MODIFICHE: Nuovi import del provider e dei modelli
import '../../providers/segretario_provider.dart';
import '../../models/promemoria_item.dart'; // Contiene PromemoriaItem
import '../../models/configurazione_segretario.dart'; 

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import '../../providers/settings_provider.dart';
import '../../services/haptics_service.dart';
import 'package:intl/intl.dart';
import '../../models/promemoria_item.dart';
import 'package:flutter/foundation.dart';




// Puoi eseguire questo codice da un pulsante temporaneo nella tua MainScreen
// o in SegretarioPage per il debug.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fic_frontend/models/cliente.dart'; // Assicurati di usare il percorso corretto
import 'package:fic_frontend/models/servizio_selezionato.dart';
import 'package:fic_frontend/models/fornitore_servizio.dart';


class SegretarioPage extends StatefulWidget {
  // 🚨 MODIFICHE: Rimosse le vecchie dipendenze da API e finestraOre (ora nel Provider)
  const SegretarioPage({
    super.key,
  });

  @override
  State<SegretarioPage> createState() => _SegretarioPageState();
}

class _SegretarioPageState extends State<SegretarioPage> {
  // 🚨 RIMOSSE: api, prevSvc (obsoleti)

  // Dati mostrati
  // 🚨 MODIFICHE: _data è ora gestito direttamente dal Provider
  // PromemoriaResponse? _data; 
  
  // Stato di caricamento
  // 🚨 MODIFICHE: Usiamo lo stato del Provider, teniamo solo l'iniziale per il blocco centrale
  bool _initialLoading = true;
  // bool _silentLoading = false;   <-- Rimosso: usiamo provider.isLoading
  // bool _isFetching = false;      <-- Rimosso: usiamo provider.isLoading
  DateTime _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _soloInScadenza = true;

  // spinner “non bloccante” 2s per azione WA/Email
  final Set<String> _waLoading = {};   // key = it.id
  final Set<String> _mailLoading = {}; // key = it.id

  // Optimistic UI per "Fatto"
  final Set<String> _optimisticDone = {}; // id marcate done subito in UI
  final Set<String> _pendingDone = {};    // id in salvataggio

  // --- HOLD-TO-CONFIRM configurabile ---
  final Map<String, Timer> _confirmTimers = {};
  final Set<String> _holdingIds = {};

  // --- Propagazione aggregato (retry/backoff) ---
  // 🚨 RIMOSSE: Tutta la logica di retry/backoff obsoleta
  









  
  @override
  void initState() {
    super.initState();
    // 🚨 RIMOSSE: Inizializzazione API/Services
    _loadInitial();
  }

  @override
  void dispose() {
    // stop timer in corso
    for (final t in _confirmTimers.values) {
      t.cancel();
    }
    _confirmTimers.clear();

    // stop eventuale feedback aptico in loop
    HapticsService().stopHoldingFeedback();

    // 🚨 RIMOZIONE: stop retry propagazione
    // _propRetryTimer?.cancel();
    // _propRetryTimer = null;

    super.dispose();
  }

  // ---- caricamenti ----
  
  // 🚨 NUOVO: La logica fetch è ora nel provider, qui solo l'inizializzazione
  Future<void> _loadInitial() async {
    final provider = context.read<SegretarioProvider>();

    // Carica prima i parametri di configurazione
    await provider.loadConfig();

    setState(() {
      _initialLoading = true;
    });

    try {
      await provider.fetchPromemoria();
      if (!mounted) return;
      setState(() {
        _lastFetchAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: ${provider.error}')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
      });
    }
  }

  // refresh "soft" (ora chiamato semplicemente fetch)
  Future<void> _refreshInBackground() async {
    final provider = context.read<SegretarioProvider>();
    if (provider.isLoading) return;

    await provider.fetchPromemoria();
    if (!mounted) return;
    setState(() {
      _lastFetchAt = DateTime.now();
    });
  }

  // refresh "hard" (chiamato fetch, non ha più bisogno di logica di cache/retry)
  Future<void> _refresh() async {
    final provider = context.read<SegretarioProvider>();
    await provider.fetchPromemoria();
    if (!mounted) return;
    setState(() {
      _lastFetchAt = DateTime.now();
    });
  }

  // 🚨 RIMOZIONE: Logica di retry/propagation obsoleta
  /*
  Future<bool> _refreshHard({bool withSpinner = true}) async { ... }
  void _schedulePropagationRetry() { ... }
  Future<void> _postWriteResync() async { ... }
  */


  // heuristica: quando la pagina torna in vista, aggiorna “morbido”
  void _maybeSoftRefreshOnFocus() {
    final provider = context.read<SegretarioProvider>();
    if (_initialLoading || provider.isLoading) return;
    final now = DateTime.now();
    if (now.difference(_lastFetchAt) > const Duration(seconds: 1)) {
      _refreshInBackground();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeSoftRefreshOnFocus();
    });
  }
  
  // 🚨 RIFATTORIZZATA: Logica di marcatura "Fatto" (usa Firestore update)
  void _marcaFattoOptimistic(PromemoriaItem it) {
    if (_optimisticDone.contains(it.id) ||
        it.isContattato || // 🚨 MODIFICA: Usiamo il campo isContattato
        _pendingDone.contains(it.id)) {
      return;
    }
    
    // 1) ottimistico in UI
    setState(() {
      _optimisticDone.add(it.id);
      _pendingDone.add(it.id);
    });

    // 2) salva in background (non bloccante)
    context.read<SegretarioProvider>().marcaAzioneDone(
        preventivoId: it.preventivoId,
        servizioRuolo: it.ruolo, // Usiamo il ruolo per l'identificazione nel provider
    ).then((success) async {
      if (!mounted) return;
      setState(() {
        _pendingDone.remove(it.id);
      });
      
      if (!success) {
        // rollback ottimistico su errore
        setState(() {
          _optimisticDone.remove(it.id);
        });
        final error = context.read<SegretarioProvider>().error ?? 'Errore nel salvataggio stato.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      // 🚨 RIMOZIONE: non serve _postWriteResync, il provider ha già richiamato fetchPromemoria
    }).catchError((e) {
      if (!mounted) return;
      // rollback ottimistico su errore generale
      setState(() {
        _pendingDone.remove(it.id);
        _optimisticDone.remove(it.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore generale salvataggio: $e')),
      );
    });
  }

  // ===== WhatsApp / Email: Nessuna modifica alla logica di formattazione del messaggio, ma RIMOZIONE della dipendenza da PreventiviService



  Future<String> _buildMsgAsync(PromemoriaItem it) async {
    // Dalla descrizione “Servizio • Fornitore” estraggo ruolo e nome fornitore
    final parts = it.descrizione.split(' • ');
    final ruolo = parts.isNotEmpty ? parts.first.trim() : '';
    final fornitoreNome = parts.length > 1 ? parts[1].trim() : '';

    // Dati denormalizzati dal PromemoriaItem
    final pieces = it.titolo.split('—');
    final cliente = pieces.isNotEmpty ? pieces.first.trim() : 'Cliente';
    final evento = pieces.length > 1 ? pieces[1].trim() : 'Evento';

    final dataStr = it.dataEvento.isNotEmpty
        ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(it.dataEvento) ?? DateTime.now())
        : '—';
    
    // Recupera tipo pasto e nota
    final String tipoPastoRaw = it.tipoPasto?.capitalize() ?? 'Pasto';
    final String noteServizio = it.noteServizio?.trim() ?? '';
    
    final String tipoPastoStr = tipoPastoRaw.toUpperCase(); 

    final righe = <String>[
      'PROMEMORIA da Pepe Rosa', 
      
      '', // A capo
      
      'Dettagli:',
      '• Cliente: $cliente',
      '• Evento: $evento',
      '• Servizio: ${ruolo.toUpperCase()}', 
      '• Tipo evento: $tipoPastoStr',
      '• Data evento: $dataStr',
      // 🚨 CORREZIONE FINALE: Usa la proprietà IT.NUMERO OSPITI letta correttamente dal DB
      '• Numero ospiti: ${it.numeroOspiti}', 
      
      if (noteServizio.isNotEmpty) '• Nota per te: $noteServizio', 
    ];

    return righe.join('\n');
  }
  
  // ------------------------- HELPERS (MANTENUTI o SEMPLIFICATI) -------------------------

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // Rimosse tutte le funzioni _ext e _fallback complesse che dipendevano dalla mappa preventivo.
  // 🚨 Rimosse: _norm, _extCliente, _extEventoNome, _extEventoData, _fallbackClienteDaTitolo, _fallbackEventoDaTitolo, _fallbackDataDaPromemoria, _extNotePerFornitore

  String _normalizePhoneForWhatsApp(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9\+]'), '');
    if (cleaned.startsWith('+')) return cleaned;
    return '+39$cleaned';
  }

  void _startSpinner(Set<String> set, String key, {int seconds = 2}) {
    setState(() => set.add(key));
    Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      setState(() => set.remove(key));
    });
  }

  Future<void> _openWhatsAppToSupplier(String numero, PromemoriaItem it) async {
    // 🚨 DEBUG LOG: Stampa il valore ricevuto
    debugPrint('[DEBUG WA] Ricevuto numero: "$numero" per ID: ${it.id}'); 

    if (numero.trim().isEmpty) return;
    _startSpinner(_waLoading, it.id);

    final phoneIntl = _normalizePhoneForWhatsApp(numero);
    final phoneNoPlus = phoneIntl.replaceAll('+', '');
    final text = Uri.encodeComponent(await _buildMsgAsync(it));

    final uriApp = Uri.parse('whatsapp://send?phone=$phoneNoPlus&text=$text');
    final uriWeb = Uri.parse('https://wa.me/$phoneNoPlus?text=$text');

    bool launched = false;
    if (await canLaunchUrl(uriApp)) {
      launched = await launchUrl(uriApp, mode: LaunchMode.externalApplication);
    }
    if (!launched && await canLaunchUrl(uriWeb)) {
      launched = await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
    }
    if (!launched && mounted) {
      final sms = Uri.parse('sms:$phoneNoPlus?body=$text');
      if (await canLaunchUrl(sms)) {
        launched = await launchUrl(sms, mode: LaunchMode.externalApplication);
      }
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire WhatsApp')),
      );
    }
  }


  Future<void> _sendEmailToSupplier(String email, PromemoriaItem it) async {
    // 🚨 DEBUG LOG: Stampa il valore ricevuto
    debugPrint('[DEBUG EMAIL] Ricevuta email: "$email" per ID: ${it.id}'); 

    if (email.trim().isEmpty) return;
    _startSpinner(_mailLoading, it.id);

    final subject = 'Promemoria servizio — Pepe Rosa';
    final body = await _buildMsgAsync(it);
    final uri = Uri(
      scheme: 'mailto',
      path: email.trim(),
      queryParameters: {'subject': subject, 'body': body},
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il client email')),
      );
    }
  }



  // --- HOLD-TO-CONFIRM (usa SettingsProvider + HapticsService) ---

  void _beginHoldConfirm(String id, PromemoriaItem it) {
    // 🚨 MODIFICA: Controlla il campo isContattato
    if (_pendingDone.contains(id) || it.isContattato || _confirmTimers.containsKey(id)) {
      return;
    }

    final s = context.read<SettingsProvider>();
    final ms = s.holdConfirmMs;
    final strength = s.vibrationStrength;

    setState(() => _holdingIds.add(id));

    HapticsService().startHoldingFeedback(strength);

    _confirmTimers[id] = Timer(Duration(milliseconds: ms), () async {
      await HapticsService().stopHoldingFeedback();
      await HapticsService().success();

      if (mounted) setState(() => _holdingIds.remove(id));
      _confirmTimers.remove(id);

      _marcaFattoOptimistic(it);
    });
  }

  Future<void> _cancelHoldConfirm(String id) async {
    _confirmTimers.remove(id)?.cancel();
    await HapticsService().stopHoldingFeedback();
    await HapticsService().cancelTap();
    if (mounted) setState(() => _holdingIds.remove(id));
  }

  void _endHoldConfirm(String id, {required bool confirmed}) {
    _confirmTimers.remove(id)?.cancel();
    HapticsService().stopHoldingFeedback();
    if (mounted) setState(() => _holdingIds.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 MODIFICA: Ascolta il SegretarioProvider
    return Consumer<SegretarioProvider>(
        builder: (context, provider, child) {
          final _filteredItems = _getFilteredItems(provider.items);

          // Determina lo stato di caricamento corretto
          final bool isFetching = provider.isLoading;
          final bool silentLoading = isFetching && !_initialLoading;


          return Scaffold(
            appBar: AppBar(
              title: const Text('Segretario'),
              actions: [
                IconButton(
                  onPressed: isFetching ? null : provider.fetchPromemoria,
                  icon: silentLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: 'Aggiorna',
                ),
              ],
            ),
            body: _initialLoading && provider.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: provider.fetchPromemoria,
                        child: ListView.builder(
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, i) {
                            final it = _filteredItems[i];

                            // Stato effettivo con overlay ottimistico
                            final bool optimisticIsDone =
                                _optimisticDone.contains(it.id);
                            final bool isDone = optimisticIsDone || it.isContattato;
                            final String statoEff = isDone ? 'done' : it.statoCalcolato;

                            // Riga 1 (Servizio)
                            final primaRiga = it.descrizione;
                            
                            // 🚨 CORREZIONE DATA: Estrai e formatta la data per la riga 2
                            final String dataEventoFormatted = it.dataEvento.isNotEmpty
                                ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(it.dataEvento) ?? DateTime.now())
                                : 'Data Sconosciuta';

                            // 🚨 NUOVA RIGA 2: Include Data Evento + Cliente/Evento
                            final String secondaRigaCompleta = '$dataEventoFormatted • ${it.titolo}';


                            final _BtnStatus btnStatus =
                                _statusForButton(it, statoEff: statoEff);

                            final waBusy = _waLoading.contains(it.id);
                            final mailBusy = _mailLoading.contains(it.id);
                            final doneBusy = _pendingDone.contains(it.id);

                            final bool buttonEnabled = !(isDone || doneBusy);

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // RIGA 1 (Servizio)
                                    Text(
                                      (primaRiga.isEmpty) ? '—' : primaRiga,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),

                                    // 🚨 RIGA 2 (Cliente + Data)
                                    Text(
                                      secondaRigaCompleta,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 8),

                                    // RIGA 3: Azioni
                                    Row(
                                      children: [
                                        // 🚨 DEBUG: Stampa i dati di contatto ricevuti
                                        if (kDebugMode) // 🚨 kDebugMode deve essere importato da flutter/foundation.dart
                                            TextButton(
                                                onPressed: () => debugPrint(
                                                    '[UI SEG] id=${it.id} tel="${it.telefono}" mail="${it.email}"'),
                                                child: const Text('DEBUG', style: TextStyle(fontSize: 10)),
                                            ),

                                        // ===== Pulsante WhatsApp (Visibilità/Click Forzata) =====
                                        IgnorePointer(
                                          // Non cliccabile se dati sono nulli o vuoti
                                          ignoring: it.telefono == null || it.telefono!.isEmpty,
                                          child: IconButton(
                                            tooltip: 'WhatsApp',
                                            onPressed: (it.telefono == null || waBusy)
                                                ? null
                                                : () => _openWhatsAppToSupplier(it.telefono!, it),
                                            icon: FaIcon(
                                                FontAwesomeIcons.whatsapp,
                                                // 🚨 COLORE: Verde se ci sono dati, Grigio se mancano
                                                color: (it.telefono != null && it.telefono!.isNotEmpty)
                                                    ? const Color(0xFF25D366)
                                                    : Colors.grey.shade400,
                                            ),
                                          ),
                                        ),

                                        // ===== Pulsante Email (Visibilità/Click Forzata) =====
                                        IgnorePointer(
                                          // Non cliccabile se dati sono nulli o vuoti
                                          ignoring: it.email == null || it.email!.isEmpty,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: IconButton(
                                              tooltip: 'Email',
                                              onPressed: (it.email == null || mailBusy)
                                                  ? null
                                                  : () => _sendEmailToSupplier(it.email!, it),
                                              icon: Icon(Icons.mail_outline,
                                                  // 🚨 COLORE: Default se ci sono dati, Grigio se mancano
                                                  color: (it.email != null && it.email!.isNotEmpty)
                                                      ? Theme.of(context).iconTheme.color
                                                      : Colors.grey.shade400,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Spacer(),

                                        // ===== Pulsante stato con grip =====
                                        _ConfirmGripButton(
                                          id: it.id,
                                          label: btnStatus.label,
                                          bg: btnStatus.bg,
                                          fg: btnStatus.fg,
                                          holding: _holdingIds.contains(it.id),
                                          enabled: buttonEnabled,
                                          showBusy: doneBusy,
                                          onHoldStart: () {
                                            if (!buttonEnabled) return;
                                            _beginHoldConfirm(it.id, it);
                                          },
                                          onHoldEnd: () => _cancelHoldConfirm(it.id),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Overlay di caricamento centrale e barra di progresso
                      if (silentLoading) ...[
                        IgnorePointer(
                          ignoring: true,
                          child: AnimatedOpacity(
                            opacity: silentLoading ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 180),
                            child: Container(
                              color: Colors.white.withOpacity(0.6),
                              child: Center(
                                child: CircularProgressIndicator(
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.topCenter,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ],
                    ],
                  ),
          );
        }
    );
  }



  // Comodo getter per filtrare gli items (ora usa provider.items)
  List<PromemoriaItem> _getFilteredItems(List<PromemoriaItem> providerItems) {
    if (providerItems.isEmpty) return const [];
    
    final items = providerItems.where((e) {
      if (_soloInScadenza) {
        // Includi ToDo, Urgente e anche Fatto/Confermato
        return e.statoCalcolato == 'todo' ||
            e.statoCalcolato == 'urgente' ||
            e.statoCalcolato == 'overdue' ||
            e.isContattato; // 🚨 Usa il nuovo campo isContattato per l'inclusione
      }
      return true;
    }).toList();
    
    return items;
  }



  _BtnStatus _statusForButton(PromemoriaItem it, {required String statoEff}) {
    // Se già confermato
    if (statoEff == 'done' || it.isContattato) {
      return const _BtnStatus('Confermato', Color(0xFF4CAF50), Colors.white, true); // Green
    }
    
    // Usa lo stato calcolato dal provider
    if (statoEff == 'urgente' || statoEff == 'overdue') {
      return const _BtnStatus('Urgente', Color(0xFFF44336), Colors.white, false); // Red
    }
    return const _BtnStatus('ToDo', Color(0xFFFF9800), Colors.black, false); // Orange
  }
}



// ===================== MODELLO PER STATO PULSANTE =====================
class _BtnStatus {
  final String label;
  final Color bg;
  final Color? fg;
  final bool isDone;
  const _BtnStatus(this.label, this.bg, this.fg, this.isDone);
}

// ===================== WIDGET PULSANTE CON GRIP (RISOLVE GLI ERRORI DI SINTASSI) =====================

class _ConfirmGripButton extends StatelessWidget {
  final String id;
  final String label;
  final Color bg;
  final Color? fg;
  final bool holding;
  final bool enabled;
  final bool showBusy;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  
  // 🚨 CORREZIONE: Sintassi corretta del costruttore principale
  const _ConfirmGripButton({
    super.key,
    required this.id,
    required this.label,
    required this.bg,
    required this.fg,
    required this.holding,
    required this.enabled,
    required this.showBusy,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  Widget build(BuildContext context) {
    final leftBg = bg;
    final leftFg = fg ?? Colors.black;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Segmento sinistro (testo + icona) colorato per stato
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
            color: leftBg,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              showBusy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(leftFg),
                      ),
                    )
                  : Icon(Icons.check, size: 18, color: leftFg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: leftFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Segmento destro: cerchio con strisce orizzontali (grip) – area di long press
        GestureDetector(
          onLongPressStart: (_) => enabled ? onHoldStart() : null,
          onLongPressEnd: (_) => enabled ? onHoldEnd() : null,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
            child: CustomPaint(
              painter: _GripStripesPainter(
                color: Colors.grey,
                stripeWidth: 3,
                gap: 1,
              ),
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black12),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

// ===================== CUSTOM PAINTER =====================

class _GripStripesPainter extends CustomPainter {
  final Color color;
  final double stripeWidth;
  final double gap;

  // 🚨 CORREZIONE: Sintassi corretta del costruttore principale
  _GripStripesPainter({
    required this.color,
    this.stripeWidth = 2,
    this.gap = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Clip a cerchio
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(clipPath);

    // Strisce orizzontali
    double y = gap;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += gap + stripeWidth;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GripStripesPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.gap != gap;
  }
}

extension StringExtension on String {
    String capitalize() {
      if (isEmpty) return this;
      return "${this[0].toUpperCase()}${substring(1)}";
    }
}