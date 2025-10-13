// lib/features/segretario/segretario_page.dart
import 'package:flutter/material.dart';
import 'segretario_api.dart';
import 'models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import '../../services/preventivi_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart'; // HapticFeedback fallback
import 'package:provider/provider.dart';

// 👇 adegua i percorsi se diversi nella tua app
import '../../providers/settings_provider.dart';
import '../../services/haptics_service.dart';
import 'package:intl/intl.dart';


class SegretarioPage extends StatefulWidget {
  const SegretarioPage({
    super.key,
    required this.apiBaseUrl,
    this.finestraOre = 168, // 7 giorni
  });

  final String apiBaseUrl;
  final int finestraOre;

  @override
  State<SegretarioPage> createState() => _SegretarioPageState();
}

class _SegretarioPageState extends State<SegretarioPage> {
  late final SegretarioApi api;
  late final PreventiviService prevSvc;

  // Dati mostrati
  PromemoriaResponse? _data;

  // Stato di caricamento
  bool _initialLoading = true;   // primo load (spinner centrale)
  bool _silentLoading = false;   // refresh “silenzioso” con UI visibile
  bool _isFetching = false;      // guard re-entrancy
  DateTime _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _soloInScadenza = true;

  // spinner “non bloccante” 2s per azione WA/Email
  final Set<String> _waLoading = {};   // key = it.id
  final Set<String> _mailLoading = {}; // key = it.id

  // Optimistic UI per "Fatto"
  final Set<String> _optimisticDone = {}; // id marcate done subito in UI
  final Set<String> _pendingDone = {};    // id in salvataggio

  // --- HOLD-TO-CONFIRM configurabile ---
  final Map<String, Timer> _confirmTimers = {}; // 1 timer per item in hold
  final Set<String> _holdingIds = {};          // id item attualmente in hold

  // --- Propagazione aggregato (retry/backoff) ---
  bool _propagationPending = false;
  int _resyncAttempts = 0;
  Timer? _propRetryTimer;
  final List<Duration> _resyncBackoff = const [
    Duration(seconds: 3),
    Duration(seconds: 7),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  @override
  void initState() {
    super.initState();
    api = SegretarioApi(baseUrl: widget.apiBaseUrl);
    prevSvc = PreventiviService(baseUrl: widget.apiBaseUrl);
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

    // stop retry propagazione
    _propRetryTimer?.cancel();
    _propRetryTimer = null;

    super.dispose();
  }

  // ---- caricamenti ----

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _isFetching = true; // evita doppio refresh concorrente
    });
    try {
      final res = await api.getPromemoria(finestraOre: widget.finestraOre);
      if (!mounted) return;
      setState(() {
        _data = res;
        _lastFetchAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _isFetching = false;
      });
    }
  }

  // refresh "soft" (cache ok, nessun &refresh=true)
  Future<void> _refreshInBackground() async {
    if (_isFetching) return;
    _isFetching = true;

    setState(() {
      _silentLoading = true;
    });

    final started = DateTime.now();
    const minSpinner = Duration(milliseconds: 600); // durata minima visibile

    try {
      final res = await api.getPromemoria(finestraOre: widget.finestraOre);
      if (!mounted) return;
      setState(() {
        _data = res;
        _lastFetchAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Soft refresh error: $e');
    } finally {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < minSpinner) {
        await Future.delayed(minSpinner - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _silentLoading = false;
        _isFetching = false;
      });
    }
  }

  // refresh "hard": forza rebuild lato backend (&refresh=true)
  Future<bool> _refreshHard({bool withSpinner = true}) async {
    if (_isFetching) return false;
    _isFetching = true;

    if (withSpinner) {
      setState(() {
        _silentLoading = true;
      });
    }

    final started = DateTime.now();
    const minSpinner = Duration(milliseconds: 600);
    var success = false;

    try {
      final res = await api.getPromemoria(
        finestraOre: widget.finestraOre,
        refresh: true, // forza rebuild aggregato
      );
      if (!mounted) return false;
      setState(() {
        _data = res;
        _lastFetchAt = DateTime.now();
      });
      success = true;
    } catch (e) {
      if (!mounted) return false;
      debugPrint('Hard refresh error: $e');
      success = false;
    } finally {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < minSpinner) {
        await Future.delayed(minSpinner - elapsed);
      }
      if (!mounted) return success;
      if (withSpinner) {
        setState(() {
          _silentLoading = false;
        });
      }
      _isFetching = false;
    }

    return success;
  }

  // Programma un retry con backoff
  void _schedulePropagationRetry() {
    if (!_propagationPending) return;
    final attempt = _resyncAttempts;
    if (attempt >= _resyncBackoff.length) {
      // Esauriti i tentativi automatici
      return;
    }
    final wait = _resyncBackoff[attempt];
    _resyncAttempts += 1;

    _propRetryTimer?.cancel();
    _propRetryTimer = Timer(wait, () async {
      if (!mounted) return;
      final ok = await _refreshHard(withSpinner: false);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _propagationPending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aggiornamento propagato su Drive.')),
        );
      } else {
        _schedulePropagationRetry();
      }
    });
  }

  // dopo il POST: hard refresh; se fallisce → banner + retry/backoff
  Future<void> _postWriteResync() async {
    final ok = await _refreshHard(withSpinner: true);
    if (!mounted) return;

    if (ok) {
      return;
    }

    setState(() {
      _propagationPending = true;
      _resyncAttempts = 0;
    });
    _schedulePropagationRetry();
  }

  // refresh esplicito (pull-to-refresh)
  Future<void> _refresh() async {
    await _refreshHard(withSpinner: true);
  }

  // heuristica: quando la pagina torna in vista, aggiorna “morbido”
  void _maybeSoftRefreshOnFocus() {
    if (_initialLoading || _isFetching) return;
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

  void _marcaFattoOptimistic(PromemoriaItem it) {
    if (_optimisticDone.contains(it.id) ||
        it.stato == 'done' ||
        _pendingDone.contains(it.id)) {
      return;
    }
    // 1) ottimistico in UI
    setState(() {
      _optimisticDone.add(it.id);
      _pendingDone.add(it.id);
    });

    // 2) salva in background (non bloccante)
    api.postAzioneDone(preventivoId: it.preventivoId, actionId: it.id).then((_) async {
      if (!mounted) return;
      setState(() {
        _pendingDone.remove(it.id);
      });
      // 3) sync con backend
      await _postWriteResync();
    }).catchError((e) {
      if (!mounted) return;
      // rollback ottimistico su errore
      setState(() {
        _pendingDone.remove(it.id);
        _optimisticDone.remove(it.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nel salvataggio: $e')),
      );
    });
  }

  // ===== WhatsApp / Email =====



  Future<String> _buildMsgAsync(PromemoriaItem it) async {
    // Dalla descrizione “Servizio • Fornitore” estraggo ruolo e nome fornitore
    final parts = it.descrizione.split(' • ');
    final ruolo = parts.isNotEmpty ? parts.first.trim() : '';
    final fornitoreNome = parts.length > 1 ? parts[1].trim() : '';

    // Carico il preventivo (mappa) dal servizio esistente
    Map<String, dynamic>? p;
    try {
      p = await prevSvc.getPreventivo(it.preventivoId);
    } catch (_) {
      p = null;
    }

    // Estrazioni robuste con fallback dal PromemoriaItem
    final cliente = _extCliente(p) ??
        _fallbackClienteDaTitolo(it.titolo) ??
        'Cliente';

    final evento = _extEventoNome(p) ??
        _fallbackEventoDaTitolo(it.titolo) ??
        'Evento';

    final dtEvento = _extEventoData(p) ?? _fallbackDataDaPromemoria(it);
    final dataStr = (dtEvento != null)
        ? DateFormat('dd/MM/yyyy').format(dtEvento)
        : '—';

    final noteForn = _extNotePerFornitore(p, ruolo, fornitoreNome) ?? '';

    final righe = <String>[
      if (fornitoreNome.isNotEmpty) 'Ciao $fornitoreNome,' else 'Ciao,',
      'ti scriviamo da Pepe Rosa.',
      '',
      'Dettagli:',
      '• Cliente: $cliente',
      '• Evento: $evento',
      '• Data evento: $dataStr',
      if (ruolo.isNotEmpty) '• Servizio: ${_cap(ruolo)}',
      if (noteForn.trim().isNotEmpty) '• Note per te: $noteForn',
    ];

    return righe.join('\n');
  }

  // ------------------------- HELPERS -------------------------

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _extCliente(Map<String, dynamic>? p) {
    if (p == null) return null;

    // Struttura comune: blocco "cliente"
    final cli = p['cliente'];
    if (cli is Map) {
      final nome = (cli['nome'] ?? cli['nome_cliente'] ?? '').toString();
      final cognome = (cli['cognome'] ?? '').toString();
      final ragSoc =
          (cli['ragione_sociale'] ?? cli['ragioneSociale'] ?? '').toString();

      final full = [nome, cognome].where((e) => e.trim().isNotEmpty).join(' ').trim();
      if (full.isNotEmpty) return full;
      if (ragSoc.trim().isNotEmpty) return ragSoc.trim();
    }

    // Chiavi flat di ripiego
    for (final k in ['nome_cliente', 'cliente_nome', 'cliente']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    return null;
  }

  String? _extEventoNome(Map<String, dynamic>? p) {
    if (p == null) return null;

    for (final k in ['nome_evento', 'evento', 'titolo_evento']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    final ev = p['evento'];
    if (ev is Map) {
      final v = (ev['nome'] ?? ev['titolo'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  DateTime? _extEventoData(Map<String, dynamic>? p) {
    if (p == null) return null;

    for (final k in ['data_evento', 'data', 'dataISO']) {
      final raw = p[k];
      if (raw is String) {
        final dt = DateTime.tryParse(raw);
        if (dt != null) return dt;
      }
    }

    final ev = p['evento'];
    if (ev is Map) {
      for (final k in ['data', 'data_evento']) {
        final raw = ev[k];
        if (raw is String) {
          final dt = DateTime.tryParse(raw);
          if (dt != null) return dt;
        }
      }
    }
    return null;
  }

  String? _fallbackClienteDaTitolo(String titolo) {
    // pattern tipico: "Cliente — Evento  •  DATA"
    final pieces = titolo.split('—');
    if (pieces.isNotEmpty) {
      final left = pieces.first.trim();
      if (left.isNotEmpty) return left;
    }
    return null;
  }

  String? _fallbackEventoDaTitolo(String titolo) {
    final pieces = titolo.split('—');
    if (pieces.length >= 2) {
      final mid = pieces[1].split('•').first.trim();
      if (mid.isNotEmpty) return mid;
    }
    return null;
  }

  DateTime? _fallbackDataDaPromemoria(PromemoriaItem it) {
    DateTime? dtQuando;
    try {
      dtQuando = DateTime.tryParse(it.quando);
    } catch (_) {}
    int offsetOre = 0;
    try {
      offsetOre = (it.offsetOre is int) ? it.offsetOre as int : 0;
    } catch (_) {}
    return (dtQuando != null) ? dtQuando.add(Duration(hours: offsetOre)) : null;
  }

  String? _extNotePerFornitore(
    Map<String, dynamic>? p,
    String ruolo,
    String fornitoreNome,
  ) {
    if (p == null) return null;

    // struttura comune: servizi_extra[ruolo] -> { note, fornitore{ragione_sociale|nome} }
    final servizi = p['servizi_extra'] ?? p['servizi'] ?? p['extra'];
    if (servizi is Map) {
      Map? entry;

      // match tollerante sulla chiave ruolo
      for (final key in servizi.keys) {
        if (_norm('$key') == _norm(ruolo)) {
          final e = servizi[key];
          if (e is Map) { entry = e; break; }
        }
      }
      entry ??= (servizi[ruolo] is Map) ? servizi[ruolo] as Map : null;

      if (entry != null) {
        String? fornName;
        final forn = entry['fornitore'];
        if (forn is Map) {
          fornName = (forn['ragione_sociale'] ??
                      forn['ragioneSociale'] ??
                      forn['nome'] ??
                      '').toString();
        } else {
          fornName = (entry['fornitore_nome'] ?? entry['fornitoreName'] ?? '').toString();
        }

        if (fornitoreNome.isEmpty ||
            fornName.isEmpty ||
            _norm(fornName) == _norm(fornitoreNome)) {
          final note = (entry['note'] ?? entry['note_fornitore'] ?? '').toString().trim();
          if (note.isNotEmpty) return note;
        }
      }
    }

    return null;
  }


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
    if (_pendingDone.contains(id)) return;           // già in salvataggio
    if (_confirmTimers.containsKey(id)) return;      // già in hold

    final s = context.read<SettingsProvider>();      // durata + intensità da Setup
    final ms = s.holdConfirmMs;
    final strength = s.vibrationStrength;

    setState(() => _holdingIds.add(id));

    // feedback continuo durante l’hold
    HapticsService().startHoldingFeedback(strength);

    // timer di conferma
    _confirmTimers[id] = Timer(Duration(milliseconds: ms), () async {
      await HapticsService().stopHoldingFeedback();
      await HapticsService().success();

      if (mounted) setState(() => _holdingIds.remove(id));
      _confirmTimers.remove(id);

      _marcaFattoOptimistic(it);
    });
  }

  Future<void> _cancelHoldConfirm(String id) async {
    _confirmTimers.remove(id)?.cancel();           // annulla hold in corso
    await HapticsService().stopHoldingFeedback();  // ferma feedback continuo
    await HapticsService().cancelTap();            // piccolo tap “annullato”
    if (mounted) setState(() => _holdingIds.remove(id));
  }

  // Manteniamo la firma per eventuali chiamate legacy (non usata direttamente)
  void _endHoldConfirm(String id, {required bool confirmed}) {
    _confirmTimers.remove(id)?.cancel();
    HapticsService().stopHoldingFeedback();
    if (mounted) setState(() => _holdingIds.remove(id));
    // Il tap di successo/cancel è gestito rispettivamente nel timer e in _cancelHoldConfirm.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Segretario'),
        actions: [
          IconButton(
            onPressed: () => _refreshHard(withSpinner: true),
            icon: _silentLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: _initialLoading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, i) {
                      final it = _filteredItems[i];

                      // Stato effettivo con overlay ottimistico
                      final bool optimisticIsDone =
                          _optimisticDone.contains(it.id);
                      final String statoEff =
                          optimisticIsDone ? 'done' : it.stato;

                      // Riga 1
                      final primaRiga = it.descrizione;

                      // Riga 2
                      final secondaRiga = it.titolo;

                      // Stile/etichetta del pulsante
                      final _BtnStatus btnStatus =
                          _statusForButton(it, statoEff: statoEff);

                      final waBusy = _waLoading.contains(it.id);
                      final mailBusy = _mailLoading.contains(it.id);
                      final doneBusy = _pendingDone.contains(it.id);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // RIGA 1
                              Text(
                                (primaRiga.isEmpty) ? '—' : primaRiga,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),

                              // RIGA 2
                              Text(
                                secondaRiga,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),

                              // RIGA 3: Azioni
                              Row(
                                children: [
                                  if (it.telefono != null &&
                                      it.telefono!.isNotEmpty)
                                    IconButton(
                                      tooltip: 'WhatsApp',
                                      onPressed: waBusy
                                          ? null
                                          : () => _openWhatsAppToSupplier(
                                              it.telefono!, it),
                                      icon: waBusy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : const FaIcon(
                                              FontAwesomeIcons.whatsapp,
                                              color: Color(0xFF25D366),
                                            ),
                                    ),
                                  if (it.email != null &&
                                      it.email!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: IconButton(
                                        tooltip: 'Email',
                                        onPressed: mailBusy
                                            ? null
                                            : () => _sendEmailToSupplier(
                                                it.email!, it),
                                        icon: mailBusy
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(Icons.mail_outline),
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
                                    enabled: !(btnStatus.isDone || doneBusy),
                                    showBusy: doneBusy,
                                    onHoldStart: () {
                                      if (btnStatus.isDone || doneBusy) return;
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

                // Overlay centrale durante il refresh “silenzioso”
                IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    opacity: _silentLoading ? 1.0 : 0.0,
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

                // Barra di caricamento “silenziosa” in alto
                if (_silentLoading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),

                // Banner di propagazione con retry/backoff
                if (_propagationPending)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _PropagationBanner(
                      attempts: _resyncAttempts,
                      maxAttempts: _resyncBackoff.length,
                      onRetryNow: () async {
                        final ok = await _refreshHard(withSpinner: true);
                        if (!mounted) return;
                        if (ok) {
                          setState(() {
                            _propagationPending = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Aggiornamento propagato su Drive.')),
                          );
                        } else {
                          _schedulePropagationRetry();
                        }
                      },
                      onDismiss: () {
                        setState(() {
                          _propagationPending = false;
                        });
                        _propRetryTimer?.cancel();
                        _propRetryTimer = null;
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  // comodo getter per filtrare gli items
  List<PromemoriaItem> get _filteredItems {
    final data = _data;
    if (data == null) return const [];
    final items = data.items.where((e) {
      if (_soloInScadenza) {
        // includi ToDo, Urgente/overdue **e anche Fatto** (così resta visibile in verde)
        return e.stato == 'todo' ||
            e.stato == 'urgente' ||
            e.stato == 'overdue' ||
            e.stato == 'done';
      }
      return true;
    }).toList();
    return items;
  }

  // =============== LOGICA STATO PER IL PULSANTE (ex chip) ===============
  _BtnStatus _statusForButton(PromemoriaItem it, {required String statoEff}) {
    // Se già confermato
    if (statoEff == 'done') {
      return _BtnStatus('Confermato', Colors.green.shade600, Colors.white, true);
    }

    final now = DateTime.now();

    // Ricavo data evento stimata da "quando + offsetOre"
    DateTime? dtQuando;
    try {
      dtQuando = DateTime.tryParse(it.quando);
    } catch (_) {}
    int offsetOre = 0;
    try {
      offsetOre = (it.offsetOre is int) ? it.offsetOre as int : 0;
    } catch (_) {}
    final DateTime? dtEvento =
        (dtQuando != null) ? dtQuando.add(Duration(hours: offsetOre)) : null;

    bool urgente;
    if (dtEvento != null) {
      urgente = dtEvento.difference(now).inHours < 72;
    } else {
      // Fallback: se manca dtEvento, usa lo stato dal backend
      urgente = (statoEff == 'urgente' || statoEff == 'overdue');
    }

    if (urgente) {
      return _BtnStatus('Urgente', Colors.red.shade600, Colors.white, false);
    }
    return _BtnStatus('ToDo', Colors.orange.shade600, null, false);
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

// ===================== WIDGET PULSANTE CON GRIP =====================

class _ConfirmGripButton extends StatelessWidget {
  const _ConfirmGripButton({
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

  final String id;
  final String label;
  final Color bg;
  final Color? fg;
  final bool holding; // non usato per colore (voluto), ma tenuto per futura UX
  final bool enabled;
  final bool showBusy;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

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
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
          ).copyWith(color: leftBg),
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

class _GripStripesPainter extends CustomPainter {
  _GripStripesPainter({
    required this.color,
    this.stripeWidth = 2,
    this.gap = 3,
  });

  final Color color;
  final double stripeWidth;
  final double gap;

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

// ===================== BANNER DI PROPAGAZIONE =====================

class _PropagationBanner extends StatelessWidget {
  const _PropagationBanner({
    required this.attempts,
    required this.maxAttempts,
    required this.onRetryNow,
    required this.onDismiss,
  });

  final int attempts;
  final int maxAttempts;
  final VoidCallback onRetryNow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1), // amber very light
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFECB3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_sync, size: 20, color: Colors.black87),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Aggiornamento in propagazione… '
                '(tentativo ${attempts.clamp(0, maxAttempts)} di $maxAttempts)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: onRetryNow,
              child: const Text('Riprova ora'),
            ),
            IconButton(
              tooltip: 'Nascondi',
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
