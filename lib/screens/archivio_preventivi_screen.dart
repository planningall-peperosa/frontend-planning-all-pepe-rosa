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

// --- MODIFICA: NUOVO MODELLO DATI ---
// Questo piccolo "modello" rappresenta un preventivo letto da Firestore.
// Sostituisce il vecchio `PreventivoSummary` per questa schermata.
class Preventivo {
  final String id;
  final String nomeCliente;
  final String nomeEvento;
  final DateTime dataEvento;
  final String status;
  // Potremmo aggiungere altri campi qui se servono per la lista

  Preventivo({
    required this.id,
    required this.nomeCliente,
    required this.nomeEvento,
    required this.dataEvento,
    required this.status,
  });

  // Factory constructor per creare un'istanza da un DocumentSnapshot di Firestore
  factory Preventivo.fromFirestore(DocumentSnapshot doc) {
    // Converte i dati del documento Firestore in un oggetto che possiamo usare facilmente
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Preventivo(
      id: doc.id,
      // NOTA: Per mostrare il nome del cliente nella lista, è necessario
      // che questo campo sia presente direttamente nel documento del preventivo.
      // È una pratica comune chiamata "denormalizzazione" per migliorare le performance.
      nomeCliente: data['nome_cliente'] ?? 'Cliente Sconosciuto',
      nomeEvento: data['nome_evento'] ?? 'Senza Nome',
      dataEvento: (data['data_evento'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'Sconosciuto',
    );
  }
}


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
    // La query di base parte dalla collezione 'preventivi'
    Query query = FirebaseFirestore.instance.collection('preventivi');

    // Applica i filtri per data direttamente sulla query al database
    if (_dataDa != null) {
      query = query.where('data_evento', isGreaterThanOrEqualTo: Timestamp.fromDate(_dataDa!));
    }
    if (_dataA != null) {
      // Per includere l'intero giorno finale, impostiamo l'ora alla fine della giornata
      final endOfDay = DateTime(_dataA!.year, _dataA!.month, _dataA!.day, 23, 59, 59);
      query = query.where('data_evento', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }
    
    // Ordiniamo sempre i risultati per coerenza.
    // NOTA: Firestore richiede un indice per query complesse (es. filtro su un campo e ordine su un altro).
    // Se ricevi un errore in console con un link, cliccalo per creare l'indice automaticamente.
    query = query.orderBy('data_evento').orderBy('data_creazione', descending: true);
    
    // Aggiorniamo lo stato con il nuovo stream, la UI si aggiornerà di conseguenza
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
          _dataA = oggi.add(const Duration(days: 7));
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
                  // La ricerca testuale viene rieseguita a ogni cambio
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
          
          // --- NUOVO: STREAMBUILDER PER LA LISTA DEI PREVENTIVI ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _preventiviStream,
              builder: (context, snapshot) {
                // Stato 1: In attesa di dati
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Stato 2: Errore nel caricamento
                if (snapshot.hasError) {
                  return Center(child: Text('Errore: ${snapshot.error}'));
                }
                // Stato 3: Nessun dato trovato
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('Nessun preventivo trovato'),
                    ),
                  );
                }

                // Se abbiamo i dati, li convertiamo nei nostri oggetti Preventivo
                List<Preventivo> tuttiPreventivi = snapshot.data!.docs
                    .map((doc) => Preventivo.fromFirestore(doc))
                    .toList();
                
                // --- NUOVO: FILTRO TESTUALE SUI DATI CARICATI ---
                // Firestore non supporta la ricerca "contains", quindi la facciamo qui
                // dopo aver ricevuto i dati filtrati per data.
                final testoRicerca = _textController.text.toLowerCase();
                final preventiviFiltrati = testoRicerca.isEmpty
                    ? tuttiPreventivi
                    : tuttiPreventivi.where((p) {
                        final nomeCliente = p.nomeCliente.toLowerCase();
                        final nomeEvento = p.nomeEvento.toLowerCase();
                        return nomeCliente.contains(testoRicerca) || nomeEvento.contains(testoRicerca);
                      }).toList();

                if (preventiviFiltrati.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('Nessun preventivo corrisponde alla ricerca testuale'),
                    ),
                  );
                }
                
                // Costruiamo la lista con i dati filtrati
                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: preventiviFiltrati.length,
                  itemBuilder: (context, index) {
                    final preventivo = preventiviFiltrati[index];
                    final isBozza = preventivo.status.toLowerCase() == 'bozza';

                    return Dismissible(
                      key: Key(preventivo.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerRight,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Elimina', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            SizedBox(width: 8),
                            Icon(Icons.delete, color: Colors.white),
                          ],
                        ),
                      ),
                      confirmDismiss: (direction) async {
                         return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Conferma eliminazione'),
                                content: const Text('Sei sicuro di voler eliminare il preventivo?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Annulla'),
                                  ),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => Navigator.of(context).pop(true),
                                    label: const Text('Elimina'),
                                  ),
                                ],
                              ),
                            ) ?? false;
                      },
                      // --- MODIFICA: ELIMINAZIONE DIRETTA SU FIRESTORE ---
                      onDismissed: (direction) async {
                        try {
                          await FirebaseFirestore.instance
                              .collection('preventivi')
                              .doc(preventivo.id)
                              .delete();
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Preventivo eliminato con successo'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Errore durante l\'eliminazione: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
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
                              Text('ID: ${preventivo.id}', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(label: Text(preventivo.status)),
                              const SizedBox(width: 6),
                              // TODO: La logica di duplicazione va riscritta per Firestore
                              IconButton(
                                tooltip: 'Duplica Preventivo',
                                icon: const Icon(Icons.copy_all),
                                onPressed: () async {
                                  // Chiedi conferma all'utente
                                  final conferma = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Duplicare il preventivo?'),
                                      content: Text('Verrà creata una nuova bozza basata su "${preventivo.nomeEvento}".'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
                                        ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Duplica')),
                                      ],
                                    ),
                                  );

                                  if (conferma != true) return;

                                  // Usa la nostra nuova funzione per preparare il provider con la copia
                                  Provider.of<PreventivoBuilderProvider>(context, listen: false)
                                      .preparaPerDuplicazione(preventivo);

                                  // Naviga alla prima schermata del wizard per permettere all'utente di modificare la copia
                                  Navigator.of(context).pushNamed('/crea-preventivo');
                                },
                              ),
                            ],
                          ),
                          onTap: () => _apriDettaglioPreventivo(preventivo),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}