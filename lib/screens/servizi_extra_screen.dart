// lib/screens/servizi_extra_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/servizio_selezionato.dart';
import '../providers/preventivo_builder_provider.dart';
import '../models/fornitore_servizio.dart';
import 'dati_cliente_screen.dart';
import '../widgets/wizard_stepper.dart';

// 🚨 AGGIUNTO: Import ClientiProvider
import '../providers/clienti_provider.dart' ; 

import 'archivio_preventivi_screen.dart';

class ServiziExtraScreen extends StatefulWidget {
  const ServiziExtraScreen({super.key});

  @override
  State<ServiziExtraScreen> createState() => _ServiziExtraScreenState();
}

class _ServiziExtraScreenState extends State<ServiziExtraScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nomeEventoController = TextEditingController();
  final _ospitiController = TextEditingController();
  final _scontoController = TextEditingController();

  bool _haTentatoDiAndareAvanti = false;

  bool _isProcessing = false;
  String? _busyAction;
  
  // 🚨 FUTURO: userà il provider corretto
  late Future<List<String>> _ruoliFuture;

  @override
  void initState() {
    super.initState();
    _ruoliFuture = _caricaTuttiIRuoliDaFirestore();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context, listen: false);

      _nomeEventoController.text = preventivoBuilder.nomeEvento ?? '';
      
      // 🚨 CORREZIONE BUG OSPITI: Assicurati che l'int sia caricato correttamente
      final osp = preventivoBuilder.numeroOspiti ?? 0;
      _ospitiController.text = (osp > 0) ? osp.toString() : '';

      _scontoController.text = preventivoBuilder.sconto > 0
          ? preventivoBuilder.sconto.toStringAsFixed(2)
          : '';

      _nomeEventoController.addListener(() {
        preventivoBuilder.setNomeEvento(_nomeEventoController.text);
      });

      _ospitiController.addListener(() {
        final n = int.tryParse(_ospitiController.text) ?? 0;
        preventivoBuilder.setNumeroOspiti(n);
      });
    });
  }
  
  // 🚨 RIFATTORIZZATO: Usa ClientiProvider per i ruoli
  Future<List<String>> _caricaTuttiIRuoliDaFirestore() async {
    final provider = context.read<ClientiProvider>();
    try {
      await provider.fetchAllContacts(force: true);
      
      final ruoli = provider.tuttiContatti
          .where((c) => c.tipo == 'fornitore' && c.ruolo != null)
          .map((c) => c.ruolo!)
          .toSet() 
          .toList();
      ruoli.sort();
      return ruoli;
    } catch (e) {
      // ignore: avoid_print
      print("Errore caricamento ruoli fornitori: $e");
      return [];
    }
  }

  @override
  void dispose() {
    _nomeEventoController.dispose();
    _ospitiController.dispose();
    _scontoController.dispose();
    super.dispose();
  }



  void _procediAiDatiCliente() {
    setState(() {
      _haTentatoDiAndareAvanti = true;
    });
    final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    
    // 🟢 NUOVO FLAG
    final bool isPacchettoFisso = preventivoBuilder.isPacchettoFisso;

    final formOk = _formKey.currentState!.validate();
    
    // 🔑 NUOVA LOGICA DI VALIDAZIONE
    // Nome evento (sempre richiesto) e Data Evento (sempre richiesta)
    final nomeOk = preventivoBuilder.nomeEvento != null && preventivoBuilder.nomeEvento!.isNotEmpty;
    final dataOk = preventivoBuilder.dataEvento != null;
    
    // Numero Ospiti è obbligatorio SOLO se NON è Pacchetto Fisso
    final ospitiOk = isPacchettoFisso || ((preventivoBuilder.numeroOspiti ?? 0) > 0);

    // Tipo Pasto è obbligatorio SOLO se NON è Pacchetto Fisso
    final tipoPastoOk = isPacchettoFisso || (preventivoBuilder.tipoPasto != null && preventivoBuilder.tipoPasto!.isNotEmpty);

    // Il controllo finale del Form e della data è combinato
    final tuttoOk = formOk && nomeOk && dataOk && ospitiOk && tipoPastoOk;
    
    // --- FINE NUOVA LOGICA ---

    if (tuttoOk) {
      final scontoVal = double.tryParse(_scontoController.text.replaceAll(',', '.')) ?? 0.0;
      preventivoBuilder.setSconto(scontoVal);

      Navigator.push(context, MaterialPageRoute(builder: (context) => const DatiClienteScreen()));
    } else {
      // 🟢 MESSAGGIO DI ERRORE PIÙ INFORMATIVO
      String errorMessage = 'Controlla i campi obbligatori: Nome, Data';
      if (!isPacchettoFisso) {
         errorMessage += ', Ospiti e Pranzo/Cena';
      }
      if (!nomeOk) errorMessage = 'Inserisci il Nome Evento';
      if (!dataOk) errorMessage = 'Seleziona la Data Evento';
      if (!ospitiOk && !isPacchettoFisso) errorMessage = 'Inserisci il Numero Ospiti';
      if (!tipoPastoOk && !isPacchettoFisso) errorMessage = 'Seleziona Pranzo o Cena';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _selezionaDataEvento() async {
    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);

    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last  = DateTime(2100, 12, 31);

    DateTime initial;
    final curr = builder.dataEvento;
    if (curr == null) {
      initial = first;
    } else if (curr.isBefore(first)) {
      initial = first;
    } else if (curr.isAfter(last)) {
      initial = last;
    } else {
      initial = curr;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      locale: const Locale('it', 'IT'),
    );

    if (picked != null) {
      builder.setDataEvento(picked);
      if (mounted) setState(() {});
    }
  }

  Future<void> _gestisciSelezioneFornitore(String ruolo) async {
    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    final fornitoreScelto = await _mostraDialogSelezioneFornitore(ruolo);
    if (fornitoreScelto != null) {
      builder.setServizioFornitore(ruolo, fornitoreScelto);
    }
  }

  Future<FornitoreServizio?> _mostraDialogSelezioneFornitore(String ruolo) async {
    // 🚨 ASSUMI che il ClienteProvider sia corretto e sia stato fetchato.
    final provider = context.read<ClientiProvider>();
    
    // Filtra la lista completa dei contatti (già in memoria)
    final List<FornitoreServizio> fornitori = provider.tuttiContatti
        .where((c) => c.tipo == 'fornitore' && c.ruolo == ruolo)
        .map((c) => FornitoreServizio( 
            idContatto: c.idCliente,
            ragioneSociale: c.ragioneSociale ?? 'N/A',
            prezzo: c.prezzo,
            // 🚨 CORREZIONE: Mappiamo i campi di contatto dal modello Cliente
            telefono01: c.telefono01, 
            mail: c.mail,
            ruolo: c.ruolo, // Assumiamo che anche il ruolo sia utile
        ))
        .toList();

    return showDialog<FornitoreServizio>(
      context: context,
      builder: (context) {
        
        return SimpleDialog(
          title: Text('Seleziona ${ruolo.replaceAll("_", " ")}'),
          children: fornitori.isEmpty
              ? [const SimpleDialogOption(child: Text("Nessun fornitore disponibile per questo ruolo."))]
              : fornitori
                  .map(
                    (fornitore) => SimpleDialogOption(
                      onPressed: () {
                        // 🚨 DEBUG: Stampa l'oggetto prima di inviarlo al builder
                        debugPrint('[DEBUG SOURCE] Fornitore selezionato: ${fornitore.toJson()}'); 
                        Navigator.pop(context, fornitore);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(fornitore.ragioneSociale),
                          if (fornitore.prezzo != null && fornitore.prezzo! > 0)
                            Text('€${fornitore.prezzo!.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        );
      },
    );
  }

  Future<void> _salvaSuFirebase() async {
    // Aggiorna il provider con gli ultimi dati inseriti nei campi di testo di questa schermata
    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    builder.setNomeEvento(_nomeEventoController.text);
    final ospiti = int.tryParse(_ospitiController.text) ?? 0;
    builder.setNumeroOspiti(ospiti);
    final sconto = double.tryParse(_scontoController.text.replaceAll(',', '.')) ?? 0.0;
    builder.setSconto(sconto);

    setState(() {
       _isProcessing = true;
       _busyAction = 'save';
    });
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      final dataToSave = builder.toFirestoreMap();
      final preventivoId = builder.preventivoId;

      if (preventivoId != null && preventivoId.isNotEmpty) {
        // AGGIORNA
        await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).update(dataToSave);
      } else {
        // CREA
        final newDoc = await FirebaseFirestore.instance.collection('preventivi').add(dataToSave);
        builder.setPreventivoId(newDoc.id);
      }
      
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Preventivo salvato!'), backgroundColor: Colors.green),
      );

    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _busyAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, preventivoBuilder, child) {
        // --- LOGICA BADGE ---
        final String status = preventivoBuilder.status ?? 'Bozza';
        final bool isConfermato = status.toLowerCase() == 'confermato';
        final String statusText = status.toUpperCase();

        final Widget statusChip = (preventivoBuilder.preventivoId ?? '').isNotEmpty
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
                    backgroundColor: isConfermato
                        ? Colors.green.shade600
                        : Colors.red.shade600,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  ),
                ),
              )
            : const SizedBox.shrink();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dati Evento e Servizi'),
            actions: [
              // --- MODIFICA: BADGE STATUS (Primo elemento a destra) ---
              statusChip,
              // --------------------------------------------------------

              // --- NUOVI PULSANTI ---
              if (!_isProcessing)
                IconButton(
                  tooltip: 'Salva Stato Attuale',
                  icon: const Icon(Icons.save),
                  onPressed: _salvaSuFirebase,
                )
              else
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                ),

              IconButton(
                tooltip: 'Torna ai Preventivi',
                icon: const Icon(Icons.inventory_2_outlined),
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArchivioPreventiviScreen()));
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
          // --- MODIFICA CORRETTIVA: Aggiunto 'body' e 'Column' ---
          body: Column(
            children: [
              WizardStepper(
                currentStep: 1,
                steps: const ['Menu', 'Servizi', 'Cliente'],
                onStepTapped: (index) {
                  if (index < 1) Navigator.of(context).pop();
                },
              ),
              const Divider(height: 1),
              Expanded(
                // 🚨 CORREZIONE CRITICA: Il Form avvolge l'area di input, non l'intera schermata.
                child: Form(
                  key: _formKey,
                  child: FutureBuilder<List<String>>(
                    future: _ruoliFuture,
                    builder: (context, snapshot) {
                       if (snapshot.connectionState == ConnectionState.waiting) {
                         return const Center(child: CircularProgressIndicator());
                       }
                       if (snapshot.hasError) {
                         return Center(child: Text("Errore nel caricamento dei ruoli: ${snapshot.error}"));
                       }

                       final ruoliDisponibili = snapshot.data ?? [];

                       return ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          _buildDatiEventoSection(preventivoBuilder),
                          const SizedBox(height: 32),
                          _buildServiziExtraSection(ruoliDisponibili, preventivoBuilder),
                          const SizedBox(height: 32),
                          _buildRiepilogoCosti(preventivoBuilder),
                        ],
                      );
                    },
                  ),
                ),
              ),
              // Barra di navigazione fissa in fondo
              _buildNavigationControls(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationControls() {
    // 🚨 CORREZIONE: Avvolgiamo in Material per dare una Z-depth corretta (risolve il problema del tap in alto)
    return Material(
      elevation: 8, // Diamo una elevazione maggiore del BoxShadow precedente
      child: Container(
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 🔹 Pulsante "Menu" ora con bordo coerente agli altri
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back_ios),
              label: const Text(
                "Menu   ",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 0,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                side: const BorderSide(color: Colors.black26, width: 1.2), // ✅ BORDO AGGIUNTO
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8), // coerente con gli altri pulsanti
                ),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: _procediAiDatiCliente,
              child: const Row(
                children: [
                  Text('Cliente'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildDatiEventoSection(PreventivoBuilderProvider builder) {
    final numeroOspiti = builder.numeroOspiti ?? 0;
    final numeroBambini = builder.numeroBambini;
    final adulti = (numeroOspiti - numeroBambini).clamp(0, numeroOspiti);

    // 🟢 NUOVO FLAG
    final bool isPacchettoFisso = builder.isPacchettoFisso;
    // ----------------------

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Dati Evento", style: Theme.of(context).textTheme.titleLarge),
        const Divider(height: 24),
        TextFormField(
          controller: _nomeEventoController,
          decoration: const InputDecoration(labelText: 'Nome Evento (es. Diciottesimo-Matrimonio-Comunione ecc.)'),
          validator: (v) => (v == null || v.isEmpty) ? 'Campo obbligatorio' : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _ospitiController,
                // 🔑 MODIFICA CHIAVE: Disabilita se Pacchetto Fisso
                enabled: !isPacchettoFisso, 
                decoration: InputDecoration(
                  labelText: 'Numero Ospiti (totale)',
                  hintText: isPacchettoFisso ? 'Numero fisso non richiesto' : null,
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  // 🔑 Validazione richiesta SOLO se NON è Pacchetto Fisso
                  if (isPacchettoFisso) return null; 
                  
                  if (v == null || v.isEmpty) return 'Obbligatorio';
                  if (int.tryParse(v) == null) return 'Numero non valido';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: InkWell(
                onTap: _selezionaDataEvento,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data Evento',
                    border: const OutlineInputBorder(),
                    errorText:
                        _haTentatoDiAndareAvanti && builder.dataEvento == null ? ' ' : null,
                    errorStyle: const TextStyle(height: 0),
                    errorBorder: _haTentatoDiAndareAvanti && builder.dataEvento == null
                        ? OutlineInputBorder(
                            borderSide:
                                BorderSide(color: Theme.of(context).colorScheme.error))
                        : null,
                  ),
                  child: Text(
                    builder.dataEvento == null
                        ? 'Seleziona'
                        : DateFormat('dd/MM/yyyy').format(builder.dataEvento!),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
        
        // 🟢 SEZIONE MENU BAMBINI (già condizionale)
        if (!isPacchettoFisso) ...[
          const SizedBox(height: 16),
          Text("Menu Bambini", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: builder.numeroBambini > 0 ? builder.numeroBambini.toString() : '',
                  decoration: const InputDecoration(labelText: 'Numero bambini'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = int.tryParse(v) ?? 0;
                    builder.setNumeroBambini(n);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  initialValue: builder.prezzoMenuBambino > 0
                      ? builder.prezzoMenuBambino.toStringAsFixed(2).replaceAll('.', ',')
                      : '',
                  decoration:
                      const InputDecoration(labelText: 'Prezzo menu bambino', prefixText: '€ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final prezzo = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    builder.setPrezzoMenuBambino(prezzo);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: builder.menuBambini,
            decoration: const InputDecoration(
              labelText: 'Piatti menu bambini',
              hintText: 'Es. Pasta al pomodoro, cotoletta e patatine…',
            ),
            maxLines: 2,
            onChanged: builder.setMenuBambini,
          ),
        ],
        // -------------------------------------------------------------

        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text("Adulti calcolati: $adulti",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ),
      ],
    );
  }


  Widget _buildServiziExtraSection(
      List<String> allRuoli, PreventivoBuilderProvider builder) {
    
    final explicitOrder = <String>[
      'pasticceria',
      'allestimento',
      'servizio fotografico',
      'spettacolo pirotecnico',
      'servizio generico',
    ];

    final ruoliFornitore = <String>[
      ...explicitOrder.where((r) => allRuoli.contains(r)),
      ...allRuoli.where((r) => !explicitOrder.contains(r)),
    ];

    // ⚠️ MODIFICA: rimosso "buffet di dolci" (ora gestito in crea_preventivo_screen)
    final serviziConNota = ['open bar', 'beverage'];
    final serviziSemplici = ['cream tart', 'confettata'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Servizi Extra", style: Theme.of(context).textTheme.titleLarge),
        const Divider(height: 24),

        ...ruoliFornitore.map((ruolo) => _buildServizioFornitoreRow(ruolo, builder)),

        ...serviziConNota.map((nomeServizio) => _buildServizioNotaRow(nomeServizio, builder)),

        ...serviziSemplici.map((nomeServizio) => _buildServizioSempliceRow(nomeServizio, builder)),
      ],
    );
  }

  Widget _buildServizioFornitoreRow(
      String ruolo, PreventivoBuilderProvider builder) {
    final nomeServizio = ruolo.replaceAll("_", " ").capitalize();
    final servizio = builder.serviziExtra[ruolo];
    final isSelected = servizio != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          children: [
            SwitchListTile(
              title: Text(nomeServizio),
              value: isSelected,
              onChanged: (value) {
                builder.toggleServizio(ruolo, value);
                if (value) _gestisciSelezioneFornitore(ruolo);
              },
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: InkWell(
                            onTap: () => _gestisciSelezioneFornitore(ruolo),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                labelText: 'Fornitore',
                              ),
                              child: Text(
                                servizio!.fornitore?.ragioneSociale ??
                                    'Seleziona fornitore',
                                style: TextStyle(
                                  color: servizio.fornitore == null
                                      ? Colors.grey.shade600
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            key: ValueKey('${ruolo}_${servizio.fornitore?.idContatto}'),
                            initialValue: (servizio.prezzo ?? 0) > 0
                                ? (servizio.prezzo ?? 0)
                                    .toStringAsFixed(2)
                                    .replaceAll('.', ',')
                                : '',
                            decoration: const InputDecoration(
                                labelText: 'Prezzo', prefixText: '€ '),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (value) {
                              final prezzo =
                                  double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                              builder.aggiornaPrezzoServizio(ruolo, prezzo);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                      TextFormField(
                        initialValue: servizio!.note,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          hintText: 'Aggiungi indicazioni per il fornitore…',
                        ),
                        onChanged: (value) => builder.setServizioNota(ruolo, value),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildServizioNotaRow(
      String nomeServizio, PreventivoBuilderProvider builder) {
    final isSelected = builder.serviziExtra.containsKey(nomeServizio);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          children: [
            SwitchListTile(
              title: Text(nomeServizio.capitalize()),
              value: isSelected,
              onChanged: (value) => builder.toggleServizio(nomeServizio, value),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: builder.serviziExtra[nomeServizio]?.note,
                        decoration:
                            const InputDecoration(labelText: 'Note', hintText: 'Aggiungi dettagli...'),
                        onChanged: (value) => builder.setServizioNota(nomeServizio, value),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: ValueKey('${nomeServizio}_prezzo'),
                        initialValue: (((builder.serviziExtra[nomeServizio]?.prezzo) ?? 0) > 0)
                            ? ((builder.serviziExtra[nomeServizio]?.prezzo ?? 0)
                                .toStringAsFixed(2)
                                .replaceAll('.', ','))
                            : '',
                        decoration:
                            const InputDecoration(labelText: 'Prezzo', prefixText: '€ '),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (value) {
                          final prezzo =
                              double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                          builder.aggiornaPrezzoServizio(nomeServizio, prezzo);
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildServizioSempliceRow(
      String nomeServizio, PreventivoBuilderProvider builder) {

    // 🔑 MODIFICA CHIAVE: Lista dei servizi che richiedono input aggiuntivo
    final serviziComplessi = ['confettata', 'cream tart'];
    final bool isComplex = serviziComplessi.contains(nomeServizio.toLowerCase()); 

    final isSelected = builder.serviziExtra.containsKey(nomeServizio);
    final servizio = builder.serviziExtra[nomeServizio];
    
    if (!isComplex) {
      // Gestione standard (solo toggle) per tutti gli altri servizi
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: SwitchListTile(
          title: Text(nomeServizio.capitalize()),
          value: isSelected,
          onChanged: (value) => builder.toggleServizio(nomeServizio, value),
        ),
      );
    }

    // LOGICA COMPLESSA PER CONFETTATA E CREAM TART
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          children: [
            SwitchListTile(
              title: Text(nomeServizio.capitalize()),
              value: isSelected,
              onChanged: (value) => builder.toggleServizio(nomeServizio, value),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Casella di testo per le Note
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            // 🔑 AGGIUNTA CHIAVE STATICA
                            key: ValueKey('${nomeServizio}_note_field'), 
                            initialValue: servizio?.note,
                            decoration:
                                InputDecoration(labelText: 'Note ${nomeServizio.capitalize()}', hintText: 'Dettagli, colori, gusti...'),
                            onChanged: (value) => builder.setServizioNota(nomeServizio, value),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Casella di testo per il Prezzo
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            // ❌ RIMOZIONE DELLA CHIAVE DINAMICA: L'initialValue gestirà il ricaricamento del valore,
                            // ma il widget non sarà distrutto a ogni keystroke.
                            initialValue: ((servizio?.prezzo) ?? 0) > 0
                                ? ((servizio?.prezzo ?? 0)
                                    .toStringAsFixed(2)
                                    .replaceAll('.', ','))
                                : '',
                            decoration:
                                const InputDecoration(labelText: 'Prezzo', prefixText: '€ '),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (value) {
                              final prezzo =
                                  double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                              builder.aggiornaPrezzoServizio(nomeServizio, prezzo);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildRiepilogoCosti(PreventivoBuilderProvider b) {
    final textStyle = Theme.of(context).textTheme.bodyLarge;
    final totalStyle =
        textStyle?.copyWith(fontWeight: FontWeight.bold, fontSize: 18);

    final bool isPacchettoFisso = b.isPacchettoFisso; // 🟢 FLAG PACCHETTO

    final ospiti = b.numeroOspiti ?? 0;
    final bambini = b.numeroBambini;
    final adulti = (ospiti - bambini).clamp(0, ospiti);

    // ✅ NOTA: Prendo il prezzo pacchetto direttamente dal provider (o sarà 0.0)
    final double prezzoPacchetto = b.prezzoPacchettoSelezionato; 
    
    // ✅ NOTA: Questi campi sono usati solo se NON è pacchetto fisso
    final double costoPacchettoWelcome = b.costoPacchettoWelcomeDolci;
    final String? labelPacchettoWelcome = b.labelPacchettoWelcomeDolci;

    final double subtotale = b.subtotale;          
    final double totale = b.totaleFinale;         

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Riepilogo Costi", style: Theme.of(context).textTheme.titleLarge),
        const Divider(height: 24),

        // 🟢 LOGICA CONDIZIONALE COSTI MENU
        if (isPacchettoFisso)
          // ➡️ CASO PACCHETTO FISSO
          ListTile(
            title: Text("Prezzo Pacchetto", style: totalStyle),
            trailing: Text("€ ${prezzoPacchetto.toStringAsFixed(2)}", style: totalStyle),
            contentPadding: EdgeInsets.zero,
          )
        else ...[
          // ⬅️ CASO MENU A PORTATE
          if (labelPacchettoWelcome != null && costoPacchettoWelcome > 0)
            ListTile(
              title: Text(labelPacchettoWelcome, style: textStyle),
              trailing: Text("€ ${costoPacchettoWelcome.toStringAsFixed(2)}", style: textStyle),
              contentPadding: EdgeInsets.zero,
            ),
          
          ListTile(
            title: Text("Menu Adulti ($adulti × € ${b.prezzoMenuAdulto.toStringAsFixed(2)})", style: textStyle),
            trailing: Text("€ ${b.costoMenuAdulti.toStringAsFixed(2)}", style: textStyle),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            title: Text(
                "Menu Bambini ($bambini × € ${b.prezzoMenuBambino.toStringAsFixed(2)})",
                style: textStyle),
            trailing:
                Text("€ ${b.costoMenuBambini.toStringAsFixed(2)}", style: textStyle),
            contentPadding: EdgeInsets.zero,
          ),
        ],
        // ----------------------------------

        // Costo Servizi Extra (Sempre presente)
        ListTile(
          title: Text("Costo Servizi Extra", style: textStyle),
          trailing: Text("€ ${b.costoServizi.toStringAsFixed(2)}", style: textStyle),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),
        ListTile(
          title: Text("Subtotale", style: totalStyle),
          trailing: Text("€ ${subtotale.toStringAsFixed(2)}", style: totalStyle),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          title: const Text("Applica Sconto"),
          value: b.scontoAbilitato,
          onChanged: (value) => b.toggleSconto(value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (b.scontoAbilitato)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _scontoController,
                    decoration: const InputDecoration(
                      labelText: 'Importo Sconto',
                      prefixText: '€ ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      final scontoVal =
                          double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                      b.setSconto(scontoVal);
                    },
                  ),
                ),
              ],
            ),
          ),
        ListTile(
          title: Text("TOTALE FINALE",
              style: totalStyle?.copyWith(
                  color: Colors.black)),
          trailing: Text("€ ${totale.toStringAsFixed(2)}",
              style: totalStyle?.copyWith(
                  color: Colors.black)),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
