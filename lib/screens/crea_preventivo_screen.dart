// lib/screens/crea_preventivo_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 

import '../providers/piatti_provider.dart';
import '../providers/menu_templates_provider.dart';

import '../providers/preventivo_builder_provider.dart';
import '../models/piatto.dart';
import '../models/menu_template.dart';
import '../models/pacchetto_evento.dart'; // 🟢 NUOVO IMPORT
import 'servizi_extra_screen.dart';
import '../widgets/wizard_stepper.dart';
import '../widgets/tipo_pasto_field.dart';
import 'dart:typed_data';
import '../widgets/firma_dialog.dart';

import 'archivio_preventivi_screen.dart';

class CreaPreventivoScreen extends StatefulWidget {
  final String? preventivoId;

  const CreaPreventivoScreen({super.key, this.preventivoId});

  @override
  State<CreaPreventivoScreen> createState() => _CreaPreventivoScreenState();
}

class _CreaPreventivoScreenState extends State<CreaPreventivoScreen> {
  MenuTemplate? _selectedTemplate;
  PacchettoEvento? _selectedPacchetto; // 🟢 NUOVO STATO
  Map<String, List<Piatto>> _menuInCostruzione = {};
  late TextEditingController _prezzoManualeController;

  // 🔹 NOTE buffet di dolci
  late TextEditingController _buffetDolciNoteController;

  // 🔹 Stato locale per rendere i toggle reattivi anche se il Provider non notifica
  bool _aperitivoBenvenutoLocal = false;
  bool _buffetDolciLocal = false;
  
  List<PacchettoEvento> _pacchettiEventi = []; // 🟢 NUOVO STATO

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _prezzoManualeController = TextEditingController();
    _buffetDolciNoteController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final piattiProvider = Provider.of<PiattiProvider>(context, listen: false);
      final templatesProvider =
          Provider.of<MenuTemplatesProvider>(context, listen: false);
      final preventivoBuilder =
          Provider.of<PreventivoBuilderProvider>(context, listen: false);

      // Inizializza note + stato locale dai valori del Provider
      _buffetDolciNoteController.text =
          (preventivoBuilder.buffetDolciNote ?? '');
      _aperitivoBenvenutoLocal = preventivoBuilder.aperitivoBenvenuto;
      _buffetDolciLocal = preventivoBuilder.buffetDolci;

      // Carica i dati di catalogo E I PACCHETTI
      await Future.wait([
        piattiProvider.fetch(),
        templatesProvider.fetch(),
        _caricaPacchettiEventi(), // 🟢 CARICA NUOVI PACCHETTI
      ]);

      final templates = templatesProvider.templates;

      if (widget.preventivoId != null) {
        // Modalità Modifica (richiede fetch da Firestore)
        await _caricaDatiPreventivo(widget.preventivoId!);
      } else {
        // Modalità Creazione
        _sincronizzaStatoUI(templates);
        // 🟢 IMPOSTA IL DEFAULT: Menu a Portate
        preventivoBuilder.setPacchettoFissoMode(false);
        setState(() => _isLoading = false);
      }
    });
  }

  // 🟢 NUOVA FUNZIONE: Carica i pacchetti evento dalla collezione
  Future<void> _caricaPacchettiEventi() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pacchetti_eventi')
          .get();
      _pacchettiEventi = snapshot.docs
          .map((doc) => PacchettoEvento.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (mounted) {
        // ignore: avoid_print
        print("Errore caricamento pacchetti evento: $e");
      }
    }
  }

  Future<List<MenuTemplate>> _caricaMenuTemplates() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('menu_templates').get();
      return snapshot.docs
          .map((doc) => MenuTemplate.fromFirestore(doc))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print("Errore caricamento templates: $e");
      throw Exception("Impossibile caricare i menu predefiniti.");
    }
  }

  // SINCRONIZZAZIONE STATO LOCALE
  void _sincronizzaStatoUI(List<MenuTemplate> templates) {
    if (!mounted) return;

    final preventivoBuilder =
        Provider.of<PreventivoBuilderProvider>(context, listen: false);

    // 🚨 DEBUG START 🚨
    print('flutter: [SYNC START] Sincronizzazione UI avviata.');
    print('flutter: [DEBUG SYNC] isPacchettoFisso (Provider): ${preventivoBuilder.isPacchettoFisso}');
    print('flutter: [DEBUG SYNC] nomePacchettoFisso (Provider): ${preventivoBuilder.nomePacchettoFisso}');
    print('flutter: [DEBUG SYNC] Totale Pacchetti DB Caricati: ${_pacchettiEventi.length}');

    // 🟢 Sincronizzazione PACCHETTO FISSO
    final nomePacchetto = preventivoBuilder.nomePacchettoFisso;
    
    if (preventivoBuilder.isPacchettoFisso && nomePacchetto != null) {
      
      // 🔑 FIX/DEBUG: Cerca e imposta il pacchetto locale solo SE il builder lo ha
      try {
          _selectedPacchetto = _pacchettiEventi
              .cast<PacchettoEvento?>()
              .firstWhere((p) => p?.nome == nomePacchetto, orElse: () => null);
          
          if (_selectedPacchetto != null) {
               print('flutter: [DEBUG SYNC] Pacchetto ${nomePacchetto} trovato e impostato localmente.');
          } else {
               print('flutter: [DEBUG SYNC WARNING] Pacchetto "${nomePacchetto}" NON trovato nella lista locale.');
          }

      } catch (e) {
          print('flutter: [DEBUG SYNC ERROR] Errore ricerca pacchetto per nome: $e');
          _selectedPacchetto = null;
      }
      
      // 🔑 FIX: Se è pacchetto fisso, il template DEVE essere null
      _selectedTemplate = null; 

    } else {
      // 🔑 FIX: Se non siamo in modalità pacchetto fisso, puliamo il campo locale del pacchetto.
      _selectedPacchetto = null;

      // Template selezionato (solo se non è Pacchetto Fisso)
      _selectedTemplate = templates
          .cast<MenuTemplate?>()
          .firstWhere((t) => t?.nomeMenu == preventivoBuilder.nomeMenuTemplate,
              orElse: () => null);
    }


    // Log data da Provider
    print(
        "flutter: [DEBUG CARICA] Data evento dal Provider: ${preventivoBuilder.dataEvento != null ? DateFormat('dd/MM/yyyy').format(preventivoBuilder.dataEvento!) : 'NULL'}");

    setState(() {
      // Prezzo manuale (solo se non è Pacchetto Fisso)
      _prezzoManualeController.text = preventivoBuilder.prezzoMenuAdulto > 0 && !preventivoBuilder.isPacchettoFisso
          ? preventivoBuilder.prezzoMenuAdulto
              .toStringAsFixed(2)
              .replaceAll('.', ',')
          : '';

      // Menu (solo se non è Pacchetto Fisso)
      _menuInCostruzione = preventivoBuilder.isPacchettoFisso ? {} : Map.from(preventivoBuilder.menu);

      // Buffet dolci note + toggle (sincronizza locale)
      _buffetDolciNoteController.text =
          (preventivoBuilder.buffetDolciNote ?? '');
      _aperitivoBenvenutoLocal = preventivoBuilder.aperitivoBenvenuto;
      _buffetDolciLocal = preventivoBuilder.buffetDolci;
    });

    print('flutter: [SYNC END] Sincronizzazione UI completata.');
    // 🚨 DEBUG END 🚨
  }

  Future<void> _caricaDatiPreventivo(String id) async {
    final templatesProvider = context.read<MenuTemplatesProvider>();

    try {
      final doc =
          await FirebaseFirestore.instance.collection('preventivi').doc(id).get();

      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        final preventivoBuilder =
            Provider.of<PreventivoBuilderProvider>(context, listen: false);

        // Carica i dati nel provider (modifica)
        preventivoBuilder.caricaDaFirestoreMap(data, id: widget.preventivoId);

        final templates = templatesProvider.templates;

        _sincronizzaStatoUI(templates);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Preventivo non trovato.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore nel caricamento: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _salvaPreventivo() async {
    setState(() => _isSaving = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final builder =
          Provider.of<PreventivoBuilderProvider>(context, listen: false);
      final dataToSave = builder.toFirestoreMap();
      final preventivoId = builder.preventivoId;

      if (preventivoId != null && preventivoId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('preventivi')
            .doc(preventivoId)
            .update(dataToSave);
      } else {
        final newDoc = await FirebaseFirestore.instance
            .collection('preventivi')
            .add(dataToSave);
        builder.setPreventivoId(newDoc.id);
      }

      scaffoldMessenger.showSnackBar(const SnackBar(
          content: Text('Preventivo salvato!'), backgroundColor: Colors.green));
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(
          content: Text('Errore durante il salvataggio: $e'),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _prezzoManualeController.dispose();
    _buffetDolciNoteController.dispose();
    super.dispose();
  }

  void _commitMenuToProvider() {
    context.read<PreventivoBuilderProvider>().setMenu(_menuInCostruzione);
  }

  Future<void> _aggiornaMenuDaTemplate(MenuTemplate? template) async {
    final piattiProvider = context.read<PiattiProvider>();

    setState(() {
      _isLoading = true;
      _menuInCostruzione.clear();
    });

    if (template == null) {
      setState(() => _isLoading = false);
      _commitMenuToProvider();
      return;
    }

    try {
      final List<Piatto> tuttiIPiatti = piattiProvider.piatti;

      // Mappa id -> piatto (per ordine template)
      final Map<String, Piatto> byId = {
        for (final p in tuttiIPiatti) p.idUnico: p,
      };

      final Map<String, List<Piatto>> nuovoMenu = {};
      final composizione = template.composizioneDefault;

      for (var genere in composizione.keys) {
        final List<String> piattoIds =
            List<String>.from(composizione[genere] ?? const <String>[]);
        if (piattoIds.isEmpty) continue;

        final List<Piatto> ordered = <Piatto>[
          for (final id in piattoIds) if (byId[id] != null) byId[id]!,
        ];

        if (ordered.isNotEmpty) {
          nuovoMenu[genere] = ordered;
        }
      }

      setState(() => _menuInCostruzione = nuovoMenu);
      _commitMenuToProvider();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Errore nel caricare i piatti del template: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _rimuoviPiatto(String genere, Piatto piattoDaRimuovere) {
    setState(() {
      _menuInCostruzione[genere]
          ?.removeWhere((p) => p.idUnico == piattoDaRimuovere.idUnico);
      if (_menuInCostruzione[genere]?.isEmpty ?? false) {
        _menuInCostruzione.remove(genere);
      }
    });
    _commitMenuToProvider();
  }

  void _aggiungiPiatti(String genere, List<Piatto> piattiDaAggiungere) {
    setState(() {
      if (!_menuInCostruzione.containsKey(genere)) {
        _menuInCostruzione[genere] = [];
      }
      _menuInCostruzione[genere]?.addAll(piattiDaAggiungere);
    });
    _commitMenuToProvider();
  }

  Future<void> _mostraDialogAggiungiPortata() async {
    final categorieSnapshot =
        await FirebaseFirestore.instance.collection('piatti').get();
    final tutteLeCategorie =
        categorieSnapshot.docs.map((doc) => doc.data()['genere'] as String).toSet();

    final categorieMancanti = tutteLeCategorie
        .where((cat) => !_menuInCostruzione.containsKey(cat))
        .toList();

    if (categorieMancanti.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tutte le categorie di portate sono già presenti.')));
      }
      return;
    }

    List<String> categorieSelezionate = [];
    bool isMultiSelectMode = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Aggiungi Portata'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: categorieMancanti.length,
                  itemBuilder: (context, index) {
                    final cat = categorieMancanti[index];
                    final isSelected = categorieSelezionate.contains(cat);
                    return GestureDetector(
                      onLongPress: () => setStateDialog(() {
                        isMultiSelectMode = true;
                        if (isSelected) {
                          categorieSelezionate.remove(cat);
                        } else {
                          categorieSelezionate.add(cat);
                        }
                      }),
                      onTap: () {
                        if (isMultiSelectMode) {
                          setStateDialog(() {
                            if (isSelected) {
                              categorieSelezionate.remove(cat);
                            } else {
                              categorieSelezionate.add(cat);
                            }
                          });
                        } else {
                          setState(() => _menuInCostruzione[cat] = []);
                          _commitMenuToProvider();
                          Navigator.of(context).pop();
                        }
                      },
                      child: ListTile(
                        title: Text(cat),
                        tileColor: isMultiSelectMode && isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .secondary
                                .withOpacity(0.3)
                            : null,
                      ),
                    );
                  },
                ),
              ),
              actions: isMultiSelectMode
                  ? [
                      TextButton(
                        child: const Text('Annulla'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      ElevatedButton(
                        child:
                            Text('Aggiungi (${categorieSelezionate.length})'),
                        onPressed: categorieSelezionate.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  for (var cat in categorieSelezionate) {
                                    _menuInCostruzione[cat] = [];
                                  }
                                });
                                _commitMenuToProvider();
                                Navigator.of(context).pop();
                              },
                      ),
                    ]
                  : null,
            );
          },
        );
      },
    );
  }

  // 🟢 WIDGET MANCANTE: Navigazione (Footer)
  Widget _buildNavigationControls() {
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 1),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              final builder =
                  Provider.of<PreventivoBuilderProvider>(context, listen: false);

              _commitMenuToProvider();

              if (!builder.isPacchettoFisso && (builder.tipoPasto == null || builder.tipoPasto!.isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Seleziona Pranzo o Cena per proseguire.')));
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ServiziExtraScreen()),
              );
            },
            child: const Row(
              children: [
                Text('Servizi'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🟢 LOGICA ORARI: Seleziona l'orario di default
  void _selectTime(bool isStart) async {
    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    final isPranzo = builder.tipoPasto?.toLowerCase() == 'pranzo';
    
    // 🔑 Orari di default
    TimeOfDay defaultTime;
    if (isStart) {
      // Inizio: Pranzo 12:00 / Cena 19:00
      defaultTime = isPranzo ? const TimeOfDay(hour: 12, minute: 0) : const TimeOfDay(hour: 19, minute: 0);
    } else {
      // Fine: Pranzo 17:00 / Cena 01:00 (rappresentato come 01:00)
      defaultTime = isPranzo ? const TimeOfDay(hour: 17, minute: 0) : const TimeOfDay(hour: 1, minute: 0);
    }

    final initialTime = isStart 
        ? (builder.orarioInizio ?? defaultTime)
        : (builder.orarioFine ?? defaultTime);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (isStart) {
        builder.setOrarioInizio(picked);
      } else {
        builder.setOrarioFine(picked);
      }
      setState(() {});
    }
  }

  // 🟢 WIDGET NUOVO: Selettore Orari
  Widget _buildOrarioSection() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, builder, _) {
        if (builder.isPacchettoFisso) return const SizedBox.shrink();
        
        final isTipoPastoSelected = builder.tipoPasto != null && builder.tipoPasto!.isNotEmpty;
        final startText = builder.orarioInizio?.format(context) ?? 'Seleziona';
        final endText = builder.orarioFine?.format(context) ?? 'Seleziona';
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('Orario Evento', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: isTipoPastoSelected ? () => _selectTime(true) : null,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Inizio',
                        border: const OutlineInputBorder(),
                        enabled: isTipoPastoSelected,
                        hintText: !isTipoPastoSelected ? 'Seleziona Pranzo/Cena' : null,
                      ),
                      child: Text(startText),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: isTipoPastoSelected ? () => _selectTime(false) : null,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fine',
                        border: const OutlineInputBorder(),
                        enabled: isTipoPastoSelected,
                        hintText: !isTipoPastoSelected ? 'Seleziona Pranzo/Cena' : null,
                      ),
                      child: Text(endText),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _buildBody(List<MenuTemplate> menuTemplates) {
    final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context);
    
    const List<String> wizardSteps = ['Menu', 'Servizi', 'Cliente'];
    final bool isPacchettoFisso = preventivoBuilder.isPacchettoFisso;

    return Column(
      children: [
        // 1. WIZARD STEPPER (corretto con i parametri e lo step 0)
        WizardStepper(
          currentStep: 0, // Schermata Menu = Step 1 (Index 0)
          steps: wizardSteps,
          // onStepTapped: permette la navigazione verso Servizi (index 1)
          onStepTapped: (index) {
            if (index == 1) { 
                // Qui dovresti idealmente replicare la validazione di _buildNavigationControls
                // ma per ora navighiamo solo
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ServiziExtraScreen()),
                );
            }
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 2. Selettore Menu/Pacchetto (Sempre in cima)
                _buildTypeSelector(),

                // 3. Selettore Pacchetto Fisso (condizionale)
                _buildPacchettoSelector(),
                
                // --- SEZIONE MENU A PORTATE (Condizionale) ---
                if (!isPacchettoFisso) ...[
                  // 🔴 NUOVO ORDINE 1: SELETTORE TEMPLATE / PREZZO
                  _buildMenuTemplateAndPrezzo(menuTemplates),

                  // 🔴 NUOVO ORDINE 2: TIPO PASTO (Pranzo/Cena)
                  _buildTipoPastoSelector(),

                  // 🟢 INTEGRAZIONE ORARI
                  _buildOrarioSection(),

                  // 🔴 NUOVO ORDINE 3: APERITIVO DI BENVENUTO
                  _buildAperitivoSection(),
                  
                  const SizedBox(height: 24),
                  const Divider(),

                  // Composizione menù
                  _buildMenuComposition(),

                  // Buffet di dolci
                  const SizedBox(height: 16),
                  _buildBuffetDolciSection(),

                  const SizedBox(height: 16),

                  // AGGIUNGI PORTATA
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text("Aggiungi Portata"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: _mostraDialogAggiungiPortata,
                    ),
                  ),
                ],
                // ---------------------------------------------
              ],
            ),
          ),
        ),
        // FOOTER NAVIGAZIONE
        _buildNavigationControls(),
      ],
    );
  }


  // --- I TUOI WIDGET ORIGINALI, INCLUSI _buildTypeSelector E _buildPacchettoSelector ---
  
  // 🟢 WIDGET MODIFICATO: Selettore del tipo di preventivo (Menu/Pacchetto) - Usa ToggleButtons
// Modifica in lib/screens/crea_preventivo_screen.dart (nel metodo _buildTypeSelector)

Widget _buildTypeSelector() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, builder, _) {
        final bool isPacchetto = builder.isPacchettoFisso;
        final List<bool> isSelected = [!isPacchetto, isPacchetto];

        // 🔑 NOTA: 'selectionColor' dovrebbe essere definito nel contesto padre come Colors.pink o Theme.of(context).colorScheme.secondary.
        // Assumo che sia Colors.pink o una variabile di tema rosa.
        final Color selectionColor = Theme.of(context).colorScheme.secondary; 
        
        // 🔑 Colore del testo non selezionato (Nero)
        final Color unselectedTextColor = Colors.black;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: ToggleButtons(
            isSelected: isSelected,
            onPressed: (index) {
              final bool newIsPacchetto = index == 1;
              if (newIsPacchetto != isPacchetto) {
                
                // 1. Aggiorna il Provider (causa un rebuild)
                builder.setPacchettoFissoMode(newIsPacchetto);

                // 2. Aggiorna lo stato locale immediatamente per evitare inconsistenze
                if (newIsPacchetto) {
                  // Passa a Pacchetto Fisso
                  builder.setMenu({});
                  builder.resetPrezzoMenu();
                  builder.setTipoPasto(null);
                  
                  // 🔑 FIX: Aggiunto setState per pulire lo stato locale del menu a portate
                  setState(() { 
                    _menuInCostruzione = {};
                    _selectedTemplate = null;
                  });

                } else {
                  // Passa a Menu a Portate
                  builder.resetPacchettoFisso();
                  
                  // 🔑 FIX: Aggiunto setState per pulire lo stato locale del pacchetto
                  setState(() {
                    _selectedPacchetto = null;
                  });
                }
              }
            },
            borderRadius: BorderRadius.circular(8),
            
            // 🔑 MODIFICA CHIAVE 1: Sfondo Rosa e Bordo Rosa
            selectedBorderColor: selectionColor, 
            fillColor: const Color.fromARGB(255, 255, 203, 238),
            
            // 🔑 MODIFICA CHIAVE 2: Il testo selezionato è NERO
            selectedColor: Colors.black, 
            
            // 🔑 MODIFICA CHIAVE 3: Colore del testo NON selezionato è NERO
            color: unselectedTextColor, 
            
            constraints: BoxConstraints.expand(
                width: (MediaQuery.of(context).size.width - 32) / 2 - 8,
                height: 48),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Menù a portate', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    // 🔑 Corregge il testo: se selezionato è NERO, altrimenti NERO.
                    color: isSelected[0] ? Colors.black : unselectedTextColor,
                  )),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Pacchetto Fisso', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    // 🔑 Corregge il testo: se selezionato è NERO, altrimenti NERO.
                    color: isSelected[1] ? Colors.black : unselectedTextColor,
                  )),
              ),
            ],
          ),
        );
      },
    );
  }
  // 🟢 NUOVO WIDGET: Selettore del pacchetto evento

  Widget _buildPacchettoSelector() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, builder, _) {
        if (!builder.isPacchettoFisso) {
            // 🔑 FIX: Se non siamo in modalità Pacchetto Fisso, non mostrare nulla.
            return const SizedBox.shrink(); 
        }

        // Riferimento al pacchetto selezionato (per accedere alle descrizioni separate)
        final PacchettoEvento? pacchetto = _selectedPacchetto;

        // Copia ordinata (nome)
        final List<PacchettoEvento> sorted = List<PacchettoEvento>.from(_pacchettiEventi)
            ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
        
        // 🟢 DEFINIZIONE STILI GERARCHICI
        final TextStyle priceStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
          fontWeight: FontWeight.bold, 
          fontSize: 22, // Stile del prezzo/nome evento
        );
        final TextStyle desc12Style = Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: 17, // Leggermente più piccolo del prezzo, ma grande (17px)
          color: Colors.grey.shade700,
        );
        final TextStyle desc3Style = Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 15, // Più piccolo (15px)
          color: Colors.grey,
        );
        final TextStyle proposalStyle = desc12Style; // Stile della proposta gastronomica (uguale a desc12Style)
        // -------------------------------------------------------------

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔑 FIX: Titolo "Seleziona Pacchetto Fisso" è ora all'interno del DropdownButtonFormField.
            // Lo usiamo qui solo come contenitore generale se il pacchetto è null
            if (pacchetto == null)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                    children: [
                        Text('Tipo evento:', 
                             style: Theme.of(context).textTheme.titleMedium!.copyWith(color: Color.fromRGBO(0, 0, 0, 1))
                        )
                    ]
                )
              )
            else
              const SizedBox.shrink(),

            DropdownButtonFormField<PacchettoEvento?>(
              value: pacchetto, 
              items: [
                const DropdownMenuItem<PacchettoEvento?>(
                  value: null,
                  child: Text('Seleziona Pacchetto Fisso'),
                ),
                ...sorted.map((p) {
                  return DropdownMenuItem<PacchettoEvento>(
                    value: p,
                    child: Text(
                        '${p.nome} (€${p.prezzoFisso.toStringAsFixed(2)})'),
                  );
                }).toList(),
              ],
              onChanged: (PacchettoEvento? newValue) {
                setState(() => _selectedPacchetto = newValue); 
                builder.setPacchettoFisso(newValue);
              },
              decoration: const InputDecoration(
                labelText: 'Pacchetto',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
            ),
            
            // 🌟 VISUALIZZAZIONE DEI DETTAGLI DEL PACCHETTO SELEZIONATO
            if (pacchetto != null) ...[
                const SizedBox(height: 24),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                // 1. NOME EVENTO (Stile = Prezzo)
                                Text(
                                    pacchetto.nome,
                                    style: priceStyle,
                                ),
                                const Divider(height: 16),

                                // 2. DESCRIZIONE 1 (Condizioni)
                                Text(
                                    pacchetto.descrizione_1,
                                    style: desc12Style,
                                ),
                                const SizedBox(height: 8),

                                // 3. DESCRIZIONE 2 (Promozione)
                                Text(
                                    pacchetto.descrizione_2,
                                    style: desc12Style,
                                ),
                                const SizedBox(height: 16),
                                
                                // 4. PROPOSTA GASTRONOMICA
                                Text(
                                    pacchetto.propostaGastronomica,
                                    style: proposalStyle,
                                ),
                                const Divider(height: 16),
                                
                                // 5. PREZZO FISSO (Stile = Prezzo)
                                Text(
                                    'Prezzo Fisso: € ${pacchetto.prezzoFisso.toStringAsFixed(2)}',
                                    style: priceStyle,
                                ),
                                const SizedBox(height: 16),

                                // 6. DESCRIZIONE 3 (Numero persone)
                                Text(
                                    pacchetto.descrizione_3,
                                    style: desc3Style,
                                ),
                            ],
                        ),
                    ),
                ),
                const Divider(height: 32, thickness: 1),
            ],
            // -----------------------------------------------------------------
          ],
        );
      },
    );
  }


// lib/screens/crea_preventivo_screen.dart (funzione _buildTipoPastoSelector)

  Widget _buildTipoPastoSelector() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, builder, _) {
        // 🟢 Mostra SOLO se è modalità Menu a portate
        if (builder.isPacchettoFisso) return const SizedBox.shrink();

        // 🔑 Logica di Pre-valorizzazione Orari
        final String? currentTipoPasto = builder.tipoPasto;
        
        // Applica l'orario di default se il tipo pasto è selezionato
        // MA SOLO se gli orari non sono ancora stati impostati dall'utente.
        if (currentTipoPasto != null && 
            currentTipoPasto.isNotEmpty && 
            builder.orarioInizio == null && 
            builder.orarioFine == null) {
              
              final isPranzo = currentTipoPasto.toLowerCase() == 'pranzo';
              final TimeOfDay defaultStart = isPranzo ? const TimeOfDay(hour: 12, minute: 0) : const TimeOfDay(hour: 19, minute: 0);
              final TimeOfDay defaultEnd = isPranzo ? const TimeOfDay(hour: 17, minute: 0) : const TimeOfDay(hour: 1, minute: 0);
              
              // ⚠️ Nota: Usiamo addPostFrameCallback per evitare di chiamare setState/notifyListeners
              // direttamente durante la fase di build del Consumer.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                 builder.setOrarioInizio(defaultStart);
                 builder.setOrarioFine(defaultEnd);
              });
        }
        // ------------------------------------
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            // Rimosso il parametro 'onChanged' che causava l'errore
            const TipoPastoField(required: true), 
            
            // Divider richiesto
            const Divider(
              height: 24, 
              thickness: 1, 
            ),
          ],
        );
      },
    );
  }
  
  
   // 🔹 SOLO Aperitivo (rimane nella sezione “Extra veloci (menu)”)
  Widget _buildAperitivoSection() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, b, _) {
        // 🟢 Mostra SOLO se è modalità Menu a portate
        if (b.isPacchettoFisso) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                title: Text(
                  'Aperitivo di benvenuto',
                  // Applica lo stile condizionale
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _aperitivoBenvenutoLocal ? null : Colors.grey,
                      ),
                ),
                value: _aperitivoBenvenutoLocal,
                onChanged: (v) {
                  setState(() => _aperitivoBenvenutoLocal = v);
                  b.setAperitivoBenvenuto(v);
                },
              ),
            ),
          ],
        );
      },
    );
  }


  // 🔹 SOLO Buffet di dolci (SPOSTATO in fondo dopo la composizione del menu)
  Widget _buildBuffetDolciSection() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, b, _) {
        // 🟢 Mostra SOLO se è modalità Menu a portate
        if (b.isPacchettoFisso) return const SizedBox.shrink();

        final bool dolci = _buffetDolciLocal;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ho rimosso il Text e la SizedBox superiore, come concordato in precedenza
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      'Buffet di dolci', 
                      // Stile condizionale applicato qui
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: dolci ? null : Colors.grey,
                          ),
                    ),
                    value: dolci,
                    onChanged: (v) {
                      setState(() => _buffetDolciLocal = v);
                      b.setBuffetDolci(v);
                      if (!v) {
                        _buffetDolciNoteController.text = '';
                        b.setBuffetDolciNote(null);
                      }
                    },
                  ),
                  if (dolci)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: TextFormField(
                        controller: _buffetDolciNoteController,
                        decoration: const InputDecoration(
                          labelText: 'Note Buffet di dolci',
                          hintText: 'Dettagli, preferenze, richieste…',
                        ),
                        maxLines: 2,
                        onChanged: (v) => b.setBuffetDolciNote(v),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Selettore del Template (solo per menù a portate)
  Widget _buildMenuTemplateAndPrezzo(List<MenuTemplate> templates) {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, builder, _) {
        // 🟢 Mostra SOLO se è modalità Menu a portate
        if (builder.isPacchettoFisso) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('Selezione Template e Prezzo',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTemplateSelector(templates),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _prezzoManualeController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo Adulto (€)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final cleaned = v.replaceAll(',', '.');
                      final prezzo = double.tryParse(cleaned) ?? 0.0;
                      builder.setPrezzoMenuAdulto(prezzo);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  // Composizione del Menu (solo per menù a portate)
  Widget _buildMenuComposition() {
    // 🟢 Logica condizionale aggiunta
    final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
    if (builder.isPacchettoFisso) return const SizedBox.shrink();

    const ordineCorrettoPortate = [
      'antipasto',
      'primo',
      'secondo',
      'contorno',
      'portata_generica'
    ];
    final chiaviOrdinate = _menuInCostruzione.keys.toList()
      ..sort((a, b) {
        final keyA = a.trim();
        final keyB = b.trim();
        final indexA = ordineCorrettoPortate.contains(keyA)
            ? ordineCorrettoPortate.indexOf(keyA)
            : 999;
        final indexB = ordineCorrettoPortate.contains(keyB)
            ? ordineCorrettoPortate.indexOf(keyB)
            : 999;
        return indexA.compareTo(indexB);
      });

    if (chiaviOrdinate.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32.0),
          child: Text(
            "Seleziona un template o aggiungi una portata per iniziare.",
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: chiaviOrdinate.map((genere) {
        final piatti = _menuInCostruzione[genere] ?? <Piatto>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              genere.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            if (piatti.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                child: Text(
                  "Nessun piatto aggiunto.",
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600),
                ),
              )
            else
              ReorderableListView(
                key: ValueKey('reorder_$genere'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final moved =
                        _menuInCostruzione[genere]!.removeAt(oldIndex);
                    _menuInCostruzione[genere]!.insert(newIndex, moved);
                  });
                  _commitMenuToProvider();
                },
                children: [
                  for (final entry in piatti.asMap().entries)
                    ReorderableDelayedDragStartListener(
                      key: ValueKey('${genere}_${entry.value.idUnico}'),
                      index: entry.key,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          title: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.value.nome,
                                  style: const TextStyle(height: 1.2),
                                  // 🔑 CORREZIONE DEL PROBLEMA: Ripristina maxLines 2
                                  maxLines: 2, 
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 32),
                              _seasonIconFor(entry.value.stagione),
                            ],
                          ),
                          subtitle: Text(
                            entry.value.tipologia,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Rimuovi',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () =>
                                    _rimuoviPiatto(genere, entry.value),
                                splashRadius: 18,
                              ),
                              const SizedBox(width: 16),
                              ReorderableDragStartListener(
                                index: entry.key,
                                child: const Icon(Icons.drag_handle),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text("Aggiungi ${genere.toLowerCase()}"),
                onPressed: () => _mostraSheetSelezionePiatto(genere),
              ),
            ),
            const Divider(height: 24),
          ],
        );
      }).toList(),
    );
  }


  Widget _buildTemplateSelector(List<MenuTemplate> templates) {
    // Copia ordinata per prezzo crescente (stabile)
    final List<MenuTemplate> sorted = List<MenuTemplate>.from(templates)
      ..sort((a, b) {
        final c = a.prezzo.compareTo(b.prezzo);
        return c != 0 ? c : a.nomeMenu.toLowerCase().compareTo(b.nomeMenu.toLowerCase());
      });

    // Usa idMenu per l’istanza corretta, presa dalla lista ordinata
    MenuTemplate? currentTemplateInList;
    if (_selectedTemplate != null) {
      try {
        currentTemplateInList = sorted.firstWhere(
          (t) => t.idMenu == _selectedTemplate!.idMenu,
        );
      } catch (_) {
        currentTemplateInList = null;
      }
    }

    final MenuTemplate? dropdownValue = currentTemplateInList;

    return DropdownButtonFormField<MenuTemplate?>(
      value: dropdownValue,
      items: [
        const DropdownMenuItem<MenuTemplate?>(
          value: null,
          child: Text('Crea menu personalizzato'),
        ),
        ...sorted.map((template) {
          return DropdownMenuItem<MenuTemplate>(
            value: template,
            child: Text('${template.nomeMenu} (€${template.prezzo.toStringAsFixed(2)})'),
          );
        }).toList(),
      ],
      onChanged: (MenuTemplate? newValue) {
        final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
        setState(() => _selectedTemplate = newValue);

        _aggiornaMenuDaTemplate(newValue);

        if (newValue != null) {
          builder.setPrezzoDaTemplate(newValue);
          _prezzoManualeController.text = newValue.prezzo.toStringAsFixed(2).replaceAll('.', ',');
        } else {
          builder.resetPrezzoMenu();
          _prezzoManualeController.clear();
        }
      },
      decoration: const InputDecoration(
        labelText: 'Punto di Partenza',
        border: OutlineInputBorder(),
      ),
      isExpanded: true,
    );
  }

  int _tipologiaRank(String? tipologia) {
    switch ((tipologia ?? '').toLowerCase().trim()) {
      case 'carne':
        return 0;
      case 'pesce':
        return 1;
      case 'misti':
        return 2;
      case 'neutri':
        return 3;
      default:
        return 100;
    }
  }

  Widget _seasonIconFor(String? stagione) {
    switch ((stagione ?? '').toLowerCase()) {
      case 'inverno':
        return const Icon(Icons.ac_unit, size: 18, color: Colors.lightBlue);
      case 'estate':
        return const Icon(Icons.wb_sunny, size: 18, color: Colors.amber);
      case 'evergreen':
        return const Icon(Icons.eco, size: 18, color: Colors.green);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _mostraSheetSelezionePiatto(String genere) async {
    final piattiDisponibiliSnapshot = await FirebaseFirestore.instance
        .collection('piatti')
        .where('genere', isEqualTo: genere)
        .get();

    final List<Piatto> piattiDisponibili = piattiDisponibiliSnapshot.docs
        .map((doc) => Piatto.fromFirestore(doc))
        .toList();

    int _rankTipologia(String? t) {
      final s = (t ?? '').trim().toLowerCase();
      if (s == 'carne') return 0;
      if (s == 'pesce') return 1;
      if (s == 'neutro') return 2;
      if (s == 'misto') return 3;
      return 999;
    }

    piattiDisponibili.sort((a, b) {
      final ra = _rankTipologia(a.tipologia);
      final rb = _rankTipologia(b.tipologia);
      if (ra != rb) return ra.compareTo(rb);
      return (a.nome.toLowerCase()).compareTo(b.nome.toLowerCase());
    });

    final List<Piatto> selezionati = [];
    bool multi = false;
    final TextEditingController customCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateSheet) {
          void addCustom() {
            final name = customCtrl.text.trim();
            if (name.isEmpty) return;
            final custom = Piatto(
              idUnico: 'custom_${DateTime.now().millisecondsSinceEpoch}',
              genere: genere,
              nome: name,
              tipologia: 'custom',
            );
            _aggiungiPiatti(genere, [custom]);
            Navigator.of(ctx).pop();
          }

          final hasCustom = customCtrl.text.trim().isNotEmpty;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.88,
              minChildSize: 0.50,
              maxChildSize: 0.96,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade500,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Seleziona ${genere.toLowerCase()}',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: hasCustom,
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: piattiDisponibili.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final piatto = piattiDisponibili[index];
                            final isSel = selezionati.contains(piatto);
                            final giaNelMenu = _menuInCostruzione[genere]
                                    ?.any((p) => p.idUnico == piatto.idUnico) ??
                                false;

                            return GestureDetector(
                              onLongPress: (hasCustom || giaNelMenu)
                                  ? null
                                  : () {
                                      setStateSheet(() {
                                        multi = true;
                                        if (isSel) {
                                          selezionati.remove(piatto);
                                        } else {
                                          selezionati.add(piatto);
                                        }
                                      });
                                    },
                              onTap: (hasCustom || giaNelMenu)
                                  ? null
                                  : () {
                                      if (multi) {
                                        setStateSheet(() {
                                          if (isSel) {
                                            selezionati.remove(piatto);
                                          } else {
                                            selezionati.add(piatto);
                                          }
                                        });
                                      } else {
                                        _aggiungiPiatti(genere, [piatto]);
                                        Navigator.of(ctx).pop();
                                      }
                                    },
                              child: ListTile(
                                enabled: !giaNelMenu && !hasCustom,
                                title: Row(
                                  children: [
                                    Expanded(child: Text(piatto.nome)),
                                    const SizedBox(width: 8),
                                    _seasonIconFor(piatto.stagione),
                                  ],
                                ),
                                subtitle:
                                    giaNelMenu ? const Text('Già aggiunto') : null,
                                selected: multi && isSel,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: customCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome piatto (fuori menu)',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (customCtrl.text.trim().isNotEmpty) {
                            setStateSheet(() {
                              multi = false;
                              selezionati.clear();
                            });
                          } else {
                            setStateSheet(() {});
                          }
                        },
                        onSubmitted: (_) => addCustom(),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Annulla'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: hasCustom
                                    ? addCustom
                                    : (multi && selezionati.isNotEmpty)
                                        ? () {
                                            _aggiungiPiatti(
                                                genere, selezionati);
                                            Navigator.of(ctx).pop();
                                          }
                                        : null,
                                child: Text(
                                  hasCustom
                                      ? 'Aggiungi (fuori menu)'
                                      : (multi
                                          ? 'Aggiungi (${selezionati.length})'
                                          : 'Aggiungi'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        });
      },
    );
  }


@override
Widget build(BuildContext context) {
    // Usa Consumer2 per stato e dati
    return Consumer2<MenuTemplatesProvider, PiattiProvider>(
      builder: (context, templatesProvider, piattiProvider, child) {
        final bool isDataLoading =
            templatesProvider.isLoading || piattiProvider.isLoading || _isLoading;
        final List<MenuTemplate> templates = templatesProvider.templates;

        final Widget appBarContent = AppBar(
          title: Text(widget.preventivoId == null
              ? 'Crea Preventivo'
              : 'Modifica Preventivo'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              if (widget.preventivoId == null) {
                Provider.of<PreventivoBuilderProvider>(context, listen: false)
                    .reset();
              }
              Navigator.of(context).pop();
            },
          ),
          actions: [
            // Badge STATUS
            Consumer<PreventivoBuilderProvider>(
              builder: (context, prov, child) {
                final status = prov.status ?? 'Bozza';
                final isConfermato = status.toLowerCase() == 'confermato';
                final statusText = status.toUpperCase();

                if ((prov.preventivoId ?? '').isEmpty) {
                  return const SizedBox.shrink();
                }

                return Padding(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 0),
                    ),
                  ),
                );
              },
            ),

            // Salva
            if (!_isSaving)
              IconButton(
                tooltip: 'Salva stato attuale',
                icon: const Icon(Icons.save),
                onPressed: _salvaPreventivo,
              )
            else
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),

            // Preventivi
            IconButton(
              tooltip: 'Torna ai Preventivi',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ArchivioPreventiviScreen()));
              },
            ),

            // Home
            IconButton(
              tooltip: 'Torna alla Home',
              icon: const Icon(Icons.home_outlined),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        );

        return Scaffold(
          appBar: appBarContent as PreferredSizeWidget?,
          body: isDataLoading
              ? const Center(child: CircularProgressIndicator())
              : templates.isEmpty
                  ? const Center(
                      child: Text(
                          "Nessun menu predefinito trovato. Aggiungi un template nella sezione Setup."))
                  // CHIAMATA A _buildBody (che era mancante)
                  : _buildBody(templates),
          // 🟢 Il navigation control (footer) è gestito all'interno di _buildBody.
        );
      },
    );
  }


}