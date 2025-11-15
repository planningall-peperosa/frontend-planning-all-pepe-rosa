// lib/screens/archivio_preventivi_screen.dart

// NUOVI IMPORT RICHIESTI PER FIREBASE
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
// VECCHI IMPORT NON PIÙ UTILIZZATI (ma lasciati per compatibilità con altre parti dell'app)
import '../models/preventivo_summary.dart';
import '../providers/preventivi_provider.dart';
// NUOVO IMPORT
import '../providers/preventivo_builder_provider.dart';
import 'crea_preventivo_screen.dart';
// VECCHI IMPORT NON PIÙ UTILIZZATI
import '../services/preventivi_service.dart';
import '../widgets/refresh_button.dart';

// --- MODIFICA CHIAVE: IMPORT DEL MODELLO ESTERNO ---
// Ora importiamo la classe Preventivo dal suo file dedicato.
import '../models/preventivo.dart'; 


class ArchivioPreventiviScreen extends StatefulWidget {
  const ArchivioPreventiviScreen({super.key});

  @override
  State<ArchivioPreventiviScreen> createState() =>
      _ArchivioPreventiviScreenState();
}

class _ArchivioPreventiviScreenState extends State<ArchivioPreventiviScreen> {
  final _textController = TextEditingController();
  DateTime? _dataDa;
  DateTime? _dataA;
  String? _filtroRapidoSelezionato;
  String _etichettaPulsanteMese = 'Mese corrente';
  
  // --- NUOVO: GESTIONE DELLO STREAM PER I DATI IN TEMPO REALE ---
  // Questa variabile conterrà il "flusso" di dati da Firestore.
  // Verrà aggiornata ogni volta che cambiamo i filtri.
  Stream<QuerySnapshot>? _preventiviStream;

  @override
  void initState() {
    super.initState();
    // Al primo avvio, carichiamo tutti i preventivi ordinati per data di creazione.
    // Non c'è più bisogno di `addPostFrameCallback` o di caricare una cache.
    _pulisciFiltri();
  }

  String get _etichettaIntervalloDate {
    if (_dataDa != null && _dataA != null) {
      if (_dataDa!.isAtSameMomentAs(_dataA!)) {
        return DateFormat('dd/MM/yy').format(_dataDa!);
      }
      return '${DateFormat('dd/MM/yy').format(_dataDa!)} - ${DateFormat('dd/MM/yy').format(_dataA!)}';
    }
    return 'Seleziona date';
  }

  // --- MODIFICA: NUOVA LOGICA DI RICERCA ---
  // Questo metodo non chiama più un Provider, ma costruisce una query per Firestore
  // e aggiorna lo stream a cui la UI è in ascolto.
  void _eseguiRicerca() {
    // Base: collezione
    Query query = FirebaseFirestore.instance.collection('preventivi');

    // Se NON ci sono filtri data attivi, di default mostra solo da OGGI in poi
    DateTime? qDa = _dataDa;
    DateTime? qA  = _dataA;
    if (qDa == null && qA == null && _filtroRapidoSelezionato == null) {
      final now = DateTime.now();
      qDa = DateTime(now.year, now.month, now.day); // oggi 00:00
    }

    // Applica i filtri data (inclusivi) se presenti
    if (qDa != null) {
      query = query.where('data_evento',
          isGreaterThanOrEqualTo: Timestamp.fromDate(qDa));
    }
    if (qA != null) {
      final endOfDay =
          DateTime(qA.year, qA.month, qA.day, 23, 59, 59, 999); // fine giorno
      query = query.where('data_evento',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    // Ordinamento coerente
    query = query.orderBy('data_evento').orderBy('data_creazione', descending: true);

    setState(() {
      _preventiviStream = query.snapshots();
    });
  }

  void _pulisciFiltri() {
    setState(() {
      _textController.clear();
      _dataDa = null;
      _dataA = null;
      _filtroRapidoSelezionato = null;
      _etichettaPulsanteMese = 'Mese corrente';
    });
    // Dopo aver pulito i filtri, eseguiamo una ricerca "vuota" che mostrerà tutti i preventivi
    _eseguiRicerca();
  }

  Future<void> _selezionaIntervalloDate() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) {
      setState(() {
        _dataDa = picked.start;
        _dataA = picked.end;
        _filtroRapidoSelezionato = 'custom_date';
        _etichettaPulsanteMese = 'Mese corrente';
      });
      _eseguiRicerca();
    }
  }

  void _selezionaFiltroRapido(String tipo) {
    setState(() {
      _etichettaPulsanteMese = 'Mese corrente';
      if (_filtroRapidoSelezionato == tipo) {
        _filtroRapidoSelezionato = null;
        _dataDa = null;
        _dataA = null;
      } else {
        _filtroRapidoSelezionato = tipo;
        final ora = DateTime.now();
        final oggi = DateTime(ora.year, ora.month, ora.day);

        if (tipo == 'oggi') {
          _dataDa = oggi;
          _dataA = oggi;
        } else if (tipo == '7giorni') {
          _dataDa = oggi;
          _dataA = oggi.add(const Duration(days: 8));
        } else if (tipo == '30giorni') {
          _dataDa = oggi;
          _dataA = oggi.add(const Duration(days: 30));
        }
      }
    });
    _eseguiRicerca();
  }

  void _toggleMese() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    setState(() {
      if (_filtroRapidoSelezionato == 'mese_corrente') {
        _filtroRapidoSelezionato = null;
        _dataDa = null;
        _dataA = null;
        _etichettaPulsanteMese = 'Mese corrente';
      } else {
        _filtroRapidoSelezionato = 'mese_corrente';
        _dataDa = startOfMonth;
        _dataA = endOfMonth;
        _etichettaPulsanteMese = 'Tutto';
      }
    });
    _eseguiRicerca();
  }


  Future<void> _apriDettaglioPreventivo(Preventivo preventivo) async {
    // Passiamo alla schermata di creazione/modifica l'ID del preventivo da caricare.
    final bool? preventivoSalvato = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreaPreventivoScreen(preventivoId: preventivo.id),
      ),
    );

    // Se torniamo indietro e il risultato è 'true', significa che abbiamo salvato
    // qualcosa e la lista potrebbe dover essere aggiornata (anche se con gli stream non è strettamente necessario).
    if (preventivoSalvato == true && mounted) {
      // Non è più necessario forzare un refresh con gli stream, ma lo lasciamo per coerenza
      _eseguiRicerca();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // --- MODIFICA: VIA IL CONSUMER, BENVENUTO SCAFFOLD ---
    // La logica di rebuild è ora gestita dallo StreamBuilder nel body.
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        automaticallyImplyLeading: false,
        title: const Text('Archivio Preventivi'),
        actions: [
          IconButton(
            tooltip: 'Nuovo preventivo',
            icon: const Icon(Icons.add),
            onPressed: () {
              // Questa logica rimane valida
              Provider.of<PreventivoBuilderProvider>(context, listen: false).reset();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreaPreventivoScreen()),
              );
            },
          ),
          // --- MODIFICA: RefreshButton rimosso ---
          // Il RefreshButton era legato al vecchio Provider. Con gli stream,
          // i dati sono sempre aggiornati. Se serve un refresh manuale,
          // si può aggiungere un IconButton che riesegue _eseguiRicerca().
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _pulisciFiltri();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dati ricaricati.'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
      // Il body ora è un metodo separato che contiene lo StreamBuilder
      body: _buildBody(theme),
    );
  }

  // --- MODIFICA SOSTANZIALE: IL BODY È ORA UNO STREAMBUILDER ---
  Widget _buildBody(ThemeData theme) {
    return SafeArea(
      child: Column(
        children: [
          // Barra filtri e ricerca (rimane quasi identica)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Column(
              children: [
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'Cerca cliente, evento...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  alignment: WrapAlignment.start,
                  children: [
                    FilterChip(
                      avatar: const Icon(Icons.date_range_outlined),
                      label: Text(_etichettaIntervalloDate),
                      selected: _filtroRapidoSelezionato == 'custom_date',
                      onSelected: (_) => _selezionaIntervalloDate(),
                      selectedColor: theme.colorScheme.secondaryContainer,
                    ),
                    FilterChip(
                      label: const Text('Oggi'),
                      selected: _filtroRapidoSelezionato == 'oggi',
                      onSelected: (_) => _selezionaFiltroRapido('oggi'),
                      selectedColor: theme.colorScheme.secondaryContainer,
                    ),
                    FilterChip(
                      label: const Text('Prossimi 7 giorni'),
                      selected: _filtroRapidoSelezionato == '7giorni',
                      onSelected: (_) => _selezionaFiltroRapido('7giorni'),
                      selectedColor: theme.colorScheme.secondaryContainer,
                    ),
                    FilterChip(
                      label: Text(_etichettaPulsanteMese),
                      selected: _filtroRapidoSelezionato == 'mese_corrente',
                      onSelected: (_) => _toggleMese(),
                      selectedColor: theme.colorScheme.secondaryContainer,
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _pulisciFiltri,
                      child: const Text('Pulisci Filtri'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- STREAMBUILDER PER LA LISTA DEI PREVENTIVI ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _preventiviStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Errore: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('Nessun preventivo trovato'),
                    ),
                  );
                }

                List<Preventivo> tuttiPreventivi = snapshot.data!.docs
                    .map((doc) => Preventivo.fromFirestore(doc))
                    .toList();

                final testoRicerca = _textController.text.toLowerCase();
                final preventiviFiltrati = testoRicerca.isEmpty
                    ? tuttiPreventivi
                    : tuttiPreventivi.where((p) {
                        final nomeCliente = p.nomeCliente.toLowerCase();
                        final nomeEvento = p.nomeEvento.toLowerCase();
                        return nomeCliente.contains(testoRicerca) ||
                            nomeEvento.contains(testoRicerca);
                      }).toList();

                if (preventiviFiltrati.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('Nessun preventivo corrisponde alla ricerca testuale'),
                    ),
                  );
                }

                // --- ✅ CONTATORE PREVENTIVI ---
                final int totalePreventivi = preventiviFiltrati.length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Preventivi: $totalePreventivi',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: preventiviFiltrati.length,
                        itemBuilder: (context, index) {
                          final preventivo = preventiviFiltrati[index];
                          final isBozza = preventivo.status.toLowerCase() == 'bozza';

                          return _buildPreventivoCard(theme, preventivo, isBozza);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPreventivoCard(ThemeData theme, Preventivo preventivo, bool isBozza) {
    final bool isConfermato = preventivo.status.toLowerCase() == 'confermato';
    final String preventivoId = preventivo.id;

    // 🔑 CORREZIONE: Avvolgiamo la Card in un Dismissible
    return Dismissible(
      key: ValueKey(preventivoId), // Chiave unica per l'elemento
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        color: Colors.red,
        child: const Icon(Icons.delete_forever, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // **🔑 NUOVA LOGICA: Sposto la conferma qui**

          final bool? conferma = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Eliminare il preventivo?'),
              content: const Text(
                'Questa azione è definitiva e non può essere annullata.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Elimina'),
                ),
              ],
            ),
          );

          if (conferma != true) {
            return false; // **L'utente ha ANNULLATO: NON rimuovere la Card.**
          }

          // **Se l'utente ha CONFERMATO, procedi con l'eliminazione del database**
          final bool eliminazioneRiuscita = await _eliminaPreventivo(preventivoId);
          
          return eliminazioneRiuscita; // Restituisce true solo se l'eliminazione DB è OK.
        }
        return false;
      },
      onDismissed: (_) {
        // Questa callback ora serve solo come "pass-through" dopo che confirmDismiss ha restituito true.
        // L'azione di DB e la notifica all'utente sono già state gestite in confirmDismiss.
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: isBozza ? theme.colorScheme.surface : theme.cardColor,
        child: ListTile(
          title: Text(preventivo.nomeCliente),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Text('${preventivo.nomeEvento} • ${DateFormat('dd/MM/yyyy').format(preventivo.dataEvento)}'),
              const SizedBox(height: 2),
              Text('ID: ${preventivo.id}', style: theme.textTheme.bodySmall),
            ],
          ),
          trailing: Transform.translate(
            offset: const Offset(6, 0), // leggero spostamento a destra
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(
                    preventivo.status,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                  backgroundColor: isConfermato
                      ? Colors.green
                      : Colors.redAccent, // ✅ verde per confermato, rosso per bozza
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Duplica Preventivo',
                  icon: const Icon(Icons.copy_all, size: 20),
                  onPressed: () async {
                    // Logica di duplicazione omessa per brevità, assumendo sia corretta
                    final conferma = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Duplicare il preventivo?'),
                        content: Text(
                          'Verrà creata una nuova bozza basata su "${preventivo.nomeCliente} - ${preventivo.nomeEvento}".',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
                          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Duplica')),
                        ],
                      ),
                    );

                    if (conferma != true || !mounted) return;

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      await Provider.of<PreventivoBuilderProvider>(context, listen: false)
                          .preparaPerDuplicazione(preventivo.id);

                      Navigator.of(context, rootNavigator: true).pop();

                      if (mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreaPreventivoScreen()),
                        );
                      }
                    } catch (e) {
                      Navigator.of(context, rootNavigator: true).pop();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Errore durante la duplicazione: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          onTap: () => _apriDettaglioPreventivo(preventivo),
        ),
      ),
    );
  }


  // 🔑 NUOVA SIGNATURE: Ora restituisce un Future<bool> (true = eliminato con successo, false = errore)
  Future<bool> _eliminaPreventivo(String preventivoId) async {
    // La logica del dialogo è stata spostata in _buildPreventivoCard.
    // Questa funzione si occupa SOLO dell'eliminazione e della gestione degli errori/feedback.
    
    try {
      // 🔑 Eliminazione del documento da Firestore
      await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preventivo eliminato con successo.'), backgroundColor: Colors.green),
        );
      }
      
      // Con l'uso di StreamBuilder, la UI si aggiornerà automaticamente dopo l'eliminazione
      return true; // **Successo**
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'eliminazione: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
      return false; // **Errore: NON rimuovere la Card.**
    }
  }
}