import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/preventivo_summary.dart';
import '../providers/preventivi_provider.dart';
import '../providers/preventivo_builder_provider.dart';
import 'crea_preventivo_screen.dart';
import '../services/preventivi_service.dart';
import '../widgets/refresh_button.dart';

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

  // Traccia lo stato di duplicazione per card
  final Set<String> _duplicatingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = Provider.of<PreventiviProvider>(context, listen: false);
      if (!prov.isCacheCaricata) {
        await prov.caricaCacheIniziale();
      } else {
        prov.verificaVersioneCache(); // non blocca la UI
      }
    });
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

  void _eseguiRicerca() {
    Provider.of<PreventiviProvider>(context, listen: false).cercaPreventivi(
      testo: _textController.text,
      dataDa: _dataDa,
      dataA: _dataA,
      stato: null,
    );
  }

  void _pulisciFiltri() {
    setState(() {
      _textController.clear();
      _dataDa = null;
      _dataA = null;
      _filtroRapidoSelezionato = null;
      _etichettaPulsanteMese = 'Mese corrente';
    });
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

  Future<void> _apriDettaglioPreventivo(PreventivoSummary preventivoSummary) async {
    final preventiviProvider =
        Provider.of<PreventiviProvider>(context, listen: false);
    final preventivoBuilder =
        Provider.of<PreventivoBuilderProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final preventivoCompleto = await preventiviProvider
        .caricaDettaglioPreventivo(preventivoSummary.preventivoId);

    if (mounted) Navigator.of(context).pop();

    if (preventivoCompleto != null && mounted) {
      preventivoBuilder.caricaPreventivoEsistente(preventivoCompleto);

      final bool? preventivoSalvato = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const CreaPreventivoScreen()),
      );

      if (preventivoSalvato == true) {
        _eseguiRicerca();
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(preventiviProvider.errorSearching ??
              'Impossibile caricare il dettaglio.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<PreventiviProvider>(
      builder: (context, provider, _) {
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
                  // reset per iniziare un preventivo da zero
                  Provider.of<PreventivoBuilderProvider>(context, listen: false).reset();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreaPreventivoScreen()),
                  );
                },
              ),
              const RefreshButton(), // resta a destra del "+" 
            ],
          ),

          body: _buildBody(theme, provider),
        );
      },
    );
  }

  Widget _buildBody(ThemeData theme, PreventiviProvider provider) {
    if (!provider.isCacheCaricata && provider.isLoadingCache) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Download preventivi in corso...'),
          ],
        ),
      );
    }

    if (!provider.isCacheCaricata && provider.errorCache != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                provider.errorCache!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
                onPressed: () {
                  Provider.of<PreventiviProvider>(context, listen: false)
                      .caricaCacheIniziale();
                },
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 720; // se ti serve in futuro
      final showTopProgress =
          (provider.isLoadingCache && provider.isCacheCaricata) ||
          provider.isRefreshing;

      return SafeArea(
        child: CustomScrollView(
          slivers: [
            if (showTopProgress)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),

            // Barra filtri e ricerca
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        labelText: 'Cerca cliente, evento...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _eseguiRicerca(),
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
                          label: const Text('Prossimi 30 giorni'),
                          selected: _filtroRapidoSelezionato == '30giorni',
                          onSelected: (_) => _selezionaFiltroRapido('30giorni'),
                          selectedColor: theme.colorScheme.secondaryContainer,
                        ),
                        FilterChip(
                          label: Text(_etichettaPulsanteMese),
                          selected: _filtroRapidoSelezionato == 'mese_corrente',
                          onSelected: (_) => _toggleMese(),
                          selectedColor: theme.colorScheme.secondaryContainer,
                        ),
                        // ⚠️ niente Spacer in un Wrap!
                        const SizedBox.shrink(),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: (provider.risultatiCount > 0 &&
                                  !provider.isSearching)
                              ? Text(
                                  '${provider.risultatiCount} preventivi trovati',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        TextButton(
                          onPressed: _pulisciFiltri,
                          child: const Text('Pulisci Filtri'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _eseguiRicerca,
                          child: const Text('Cerca'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (provider.isSearching)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),

            // EMPTY STATE: occupa lo spazio senza scroll dedicato
            if (provider.risultatiRicerca.isEmpty && !provider.isSearching)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text('Nessun preventivo trovato'),
                  ),
                ),
              )
            else
              // LISTA: usa SliverList per evitare ListView dentro uno ScrollView a slivers
              SliverPadding(
                padding: const EdgeInsets.all(8.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final preventivo = provider.risultatiRicerca[index];
                      final isBozza =
                          preventivo.status.toLowerCase() == 'bozza';

                      return Dismissible(
                        key: Key(preventivo.preventivoId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Elimina',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.delete, color: Colors.white),
                            ],
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.endToStart) {
                            return await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title:
                                        const Text('Conferma eliminazione'),
                                    content: const Text(
                                        'Sei sicuro di voler eliminare il preventivo?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Annulla'),
                                      ),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        label: const Text('Elimina'),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;
                          }
                          return false;
                        },
                        onDismissed: (direction) async {
                          final success =
                              await Provider.of<PreventiviProvider>(context,
                                      listen: false)
                                  .eliminaPreventivo(
                                      preventivo.preventivoId);

                          if (success && mounted) {
                            await Provider.of<PreventiviProvider>(context,
                                    listen: false)
                                .hardRefresh(ignoreEditingOpen: true);
                            _eseguiRicerca();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Preventivo eliminato con successo'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (!success && mounted) {
                            final pr =
                                Provider.of<PreventiviProvider>(context,
                                    listen: false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(pr.errorSaving ??
                                    'Errore durante l\'eliminazione'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            _eseguiRicerca();
                          }
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: isBozza
                              ? theme.colorScheme.surface
                              : theme.cardColor,
                          child: ListTile(
                            title: Text(
                              preventivo.cliente.ragioneSociale ??
                                  'Cliente Sconosciuto',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${preventivo.nomeEvento ?? 'Evento'} • '
                                  '${DateFormat('dd/MM/yyyy').format(preventivo.dataEvento)}',
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${preventivo.preventivoId}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(label: Text(preventivo.status)),
                                const SizedBox(width: 6),
                                _duplicatingIds
                                        .contains(preventivo.preventivoId)
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : IconButton(
                                        tooltip: 'Duplica',
                                        icon: const Icon(Icons.copy_all),
                                        onPressed: () =>
                                            _duplicaDaCard(preventivo),
                                      ),
                              ],
                            ),
                            onTap: () =>
                                _apriDettaglioPreventivo(preventivo),
                          ),
                        ),
                      );
                    },
                    childCount: provider.risultatiRicerca.length,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  // --- INCOLLA QUESTO METODO da qualche parte nella classe dello screen ---
  Future<void> _duplicaDaCard(PreventivoSummary item) async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() {
      _duplicatingIds.add(item.preventivoId);
    });

    try {
      final service = PreventiviService();
      final nuovoId = await service.duplicaPreventivoDaId(item.preventivoId);

      if (nuovoId == null) {
        scaffold.showSnackBar(const SnackBar(content: Text('Duplicazione non riuscita')));
        return;
      }

      // 🔄 refresh come il bottone (forzato anche se editor aperto)
      await Provider.of<PreventiviProvider>(context, listen: false)
          .hardRefresh(ignoreEditingOpen: true);

      // 🔍 riapplica i filtri correnti (se presenti)
      _eseguiRicerca();

      scaffold.showSnackBar(const SnackBar(content: Text('Preventivo duplicato')));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Errore duplicazione: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _duplicatingIds.remove(item.preventivoId);
        });
      }
    }
  }

}
