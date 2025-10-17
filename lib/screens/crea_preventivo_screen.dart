// lib/screens/crea_preventivo_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Aggiunto per formattare il log della data

import '../providers/preventivo_builder_provider.dart';
import '../models/piatto.dart';
import '../models/menu_template.dart';
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
  Map<String, List<Piatto>> _menuInCostruzione = {};
  late TextEditingController _prezzoManualeController;

  bool _isLoading = true;
  bool _isSaving = false;

  late Future<List<MenuTemplate>> _menuTemplatesFuture;

  @override
  void initState() {
    super.initState();
    _prezzoManualeController = TextEditingController();
    _menuTemplatesFuture = _caricaMenuTemplates(); 

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.preventivoId != null) {
        // Modalità Modifica (richiede fetch da Firestore)
        await _caricaDatiPreventivo(widget.preventivoId!);
      } else {
        // Modalità Creazione (da zero o Duplicazione)
        
        // Carica i templates
        final templates = await _menuTemplatesFuture;

        // Sincronizziamo lo stato locale della UI con il Provider 
        // (che ora contiene i dati del duplicato, se presenti)
        _sincronizzaStatoUI(templates);
        
        setState(() => _isLoading = false);
      }
    });
  }

  Future<List<MenuTemplate>> _caricaMenuTemplates() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('menu_templates').get();
      return snapshot.docs.map((doc) => MenuTemplate.fromFirestore(doc)).toList();
    } catch (e) {
      // ignore: avoid_print
      print("Errore caricamento templates: $e");
      throw Exception("Impossibile caricare i menu predefiniti.");
    }
  }

  // NUOVA FUNZIONE DI SINCRONIZZAZIONE DELLO STATO LOCALE
  void _sincronizzaStatoUI(List<MenuTemplate> templates) {
      if (!mounted) return;

      final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
      
      // LOG RICHIESTO DALL'UTENTE: stampiamo la data che il Provider possiede
      print("flutter: [DEBUG CARICA] Data evento dal Provider: ${preventivoBuilder.dataEvento != null ? DateFormat('dd/MM/yyyy').format(preventivoBuilder.dataEvento!) : 'NULL'}");

      setState(() {
        // Sincronizza il prezzo manuale
        _prezzoManualeController.text = preventivoBuilder.prezzoMenuAdulto > 0
            ? preventivoBuilder.prezzoMenuAdulto.toStringAsFixed(2).replaceAll('.', ',')
            : '';

        // Sincronizza il template selezionato
        _selectedTemplate = templates.cast<MenuTemplate?>().firstWhere(
            (t) => t?.nomeMenu == preventivoBuilder.nomeMenuTemplate,
            orElse: () => null);

        // Sincronizza il menu (usiamo Map.from() per creare una nuova istanza)
        _menuInCostruzione = Map.from(preventivoBuilder.menu);
      });
  }

  // FUNZIONE AGGIORNATA PER IL CARICAMENTO DA FIREBASE
  Future<void> _caricaDatiPreventivo(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('preventivi').doc(id).get();

      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
        
        // Carica i dati nel provider (in modalità modifica)
        preventivoBuilder.caricaDaFirestoreMap(data, id: widget.preventivoId); 

        // Avviamo il caricamento dei templates
        final templates = await _menuTemplatesFuture; 
        
        // Chiama la funzione di sincronizzazione dello stato locale
        _sincronizzaStatoUI(templates);

      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preventivo non trovato.')));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore nel caricamento: $e')));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _salvaPreventivo() async {
    setState(() => _isSaving = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
      final dataToSave = builder.toFirestoreMap();
      final preventivoId = builder.preventivoId; // Usiamo l'ID memorizzato nel provider

      if (preventivoId != null && preventivoId.isNotEmpty) {
        // Modalità AGGIORNAMENTO
        await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).update(dataToSave);
      } else {
        // Modalità CREAZIONE
        final newDoc = await FirebaseFirestore.instance.collection('preventivi').add(dataToSave);
        builder.setPreventivoId(newDoc.id); // Memorizza il nuovo ID per i salvataggi futuri
      }

      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Preventivo salvato!'), backgroundColor: Colors.green));

    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }


  @override
  void dispose() {
    _prezzoManualeController.dispose();
    super.dispose();
  }

  void _commitMenuToProvider() {
    context.read<PreventivoBuilderProvider>().setMenu(_menuInCostruzione);
  }

  Future<void> _aggiornaMenuDaTemplate(MenuTemplate? template) async {
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
      final Map<String, List<Piatto>> nuovoMenu = {};
      final composizione = template.composizioneDefault;

      for (var genere in composizione.keys) {
        final piattoIds = composizione[genere]!;
        if (piattoIds.isEmpty) continue;
        
        final piattiSnapshot = await FirebaseFirestore.instance
            .collection('piatti')
            .where('id_unico', whereIn: piattoIds)
            .get();
        
        final piattiRecuperati = piattiSnapshot.docs.map((doc) => Piatto.fromFirestore(doc)).toList();
        nuovoMenu[genere] = piattiRecuperati;
      }

      setState(() => _menuInCostruzione = nuovoMenu);
      _commitMenuToProvider();

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore nel caricare i piatti del template: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _rimuoviPiatto(String genere, Piatto piattoDaRimuovere) {
    setState(() {
      _menuInCostruzione[genere]?.removeWhere((p) => p.idUnico == piattoDaRimuovere.idUnico);
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
    final categorieSnapshot = await FirebaseFirestore.instance.collection('piatti').get();
    final tutteLeCategorie = categorieSnapshot.docs.map((doc) => doc.data()['genere'] as String).toSet();
    
    final categorieMancanti = tutteLeCategorie.where((cat) => !_menuInCostruzione.containsKey(cat)).toList();

    if (categorieMancanti.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tutte le categorie di portate sono già presenti.')),
        );
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
                            ? Theme.of(context).colorScheme.secondary.withOpacity(0.3)
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
                        child: Text('Aggiungi (${categorieSelezionate.length})'),
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

  Widget _buildTipoPastoSelector() {
    return Consumer<PreventivoBuilderProvider>(
      builder: (context, builder, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tipo pasto (obbligatorio)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const TipoPastoField(required: true),
          ],
        );
      },
    );
  }

  Future<void> _firmaEConferma() async {
    final String? preventivoId = widget.preventivoId;

    if (preventivoId == null || preventivoId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devi prima salvare/creare il preventivo per ottenere un ID.')),
      );
      return;
    }

    final Uint8List? pngBytes = await showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FirmaDialog(),
    );

    if (pngBytes == null || pngBytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firma annullata o vuota.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('preventivi').doc(preventivoId).update({
        'status': 'Confermato',
        'data_conferma': Timestamp.now(),
        // 'firma_url': urlDaStorage,
      });
       if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preventivo confermato!')));
    } catch(e) {
       if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.preventivoId == null ? 'Crea Preventivo' : 'Modifica Preventivo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (widget.preventivoId == null) {
              Provider.of<PreventivoBuilderProvider>(context, listen: false).reset();
            }
            Navigator.of(context).pop();
          },
        ),
        actions: [
          // Pulsante SALVA
          if (!_isSaving)
            IconButton(
              tooltip: 'Salva stato attuale',
              icon: const Icon(Icons.save),
              onPressed: _salvaPreventivo, // Usa la funzione di salvataggio corretta per questa schermata
            )
          else 
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2,)),
            ),

          // Pulsante PREVENTIVI
          IconButton(
            tooltip: 'Torna ai Preventivi',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArchivioPreventiviScreen()));
            },
          ),

          // Pulsante HOME
          IconButton(
            tooltip: 'Torna alla Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],      
      ),
      body: FutureBuilder<List<MenuTemplate>>(
        future: _menuTemplatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Errore fatale: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text("Nessun menu predefinito trovato."));
          }
          final templates = snapshot.data!;
          return _buildBody(templates);
        },
      ),
    );
  }

  Widget _buildBody(List<MenuTemplate> menuTemplates) {
    final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context);
    final bool mostraPrezzoManuale = _selectedTemplate == null;

    return Column(
      children: [
        WizardStepper(
          currentStep: 0,
          steps: const ['Menu', 'Servizi', 'Cliente'],
          onStepTapped: (index) {},
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTemplateSelector(menuTemplates),

                if (mostraPrezzoManuale) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _prezzoManualeController,
                    decoration: const InputDecoration(
                      labelText: 'Prezzo Menu (a persona)',
                      prefixText: '€ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      final prezzo = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                      preventivoBuilder.setPrezzoMenuAdulto(prezzo);
                    },
                  ),
                ],

                const SizedBox(height: 12),
                _buildTipoPastoSelector(),
                const SizedBox(height: 12),

                const SizedBox(height: 24),
                const Divider(),
                _buildMenuComposition(),
                const SizedBox(height: 16),
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
            ),
          ),
        ),
        _buildNavigationControls(),
      ],
    );
  }

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
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);

              // 1. Commit Menu alla fine
              _commitMenuToProvider();

              // 2. Validazione
              if (builder.tipoPasto == null || builder.tipoPasto!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seleziona Pranzo o Cena per proseguire.')),
                );
                return;
              }
              
              // 3. Navigazione
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

  Widget _buildTemplateSelector(List<MenuTemplate> templates) {
    return DropdownButtonFormField<MenuTemplate?>(
      value: _selectedTemplate,
      items: [
        const DropdownMenuItem<MenuTemplate?>(value: null, child: Text('Crea Menu da Zero')),
        ...templates.map((template) {
          return DropdownMenuItem<MenuTemplate>(
            value: template,
            // --- MODIFICA CORRETTIVA ---
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
          // --- MODIFICA CORRETTIVA ---
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

  Widget _buildMenuComposition() {
    const ordineCorrettoPortate = ['antipasto', 'primo', 'secondo', 'contorno', 'piatto_unico'];
    final chiaviOrdinate = _menuInCostruzione.keys.toList()
      ..sort((a, b) {
        final keyA = a.trim();
        final keyB = b.trim();
        final indexA = ordineCorrettoPortate.contains(keyA) ? ordineCorrettoPortate.indexOf(keyA) : 999;
        final indexB = ordineCorrettoPortate.contains(keyB) ? ordineCorrettoPortate.indexOf(keyB) : 999;
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
        final piatti = _menuInCostruzione[genere]!;
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
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                ),
              ),
            ...piatti.map((piatto) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(piatto.nome),
                  subtitle: Text(
                    piatto.tipologia,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () => _rimuoviPiatto(genere, piatto),
                  ),
                ),
              );
            }).toList(),
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

  Future<void> _mostraSheetSelezionePiatto(String genere) async {
    final piattiDisponibiliSnapshot = await FirebaseFirestore.instance.collection('piatti').where('genere', isEqualTo: genere).get();
    final piattiDisponibili = piattiDisponibiliSnapshot.docs.map((doc) => Piatto.fromFirestore(doc)).toList();

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
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                                title: Text(piatto.nome),
                                subtitle: giaNelMenu ? const Text('Già aggiunto') : null,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                                            _aggiungiPiatti(genere, selezionati);
                                            Navigator.of(ctx).pop();
                                          }
                                        : null,
                                child: Text(
                                  hasCustom
                                      ? 'Aggiungi (fuori menu)'
                                      : (multi ? 'Aggiungi (${selezionati.length})' : 'Aggiungi'),
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
}