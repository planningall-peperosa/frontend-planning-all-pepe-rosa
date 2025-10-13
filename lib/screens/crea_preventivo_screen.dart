// lib/screens/crea_preventivo_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/preventivo_builder_provider.dart';
import '../models/piatto.dart';
import '../providers/menu_provider.dart';
import '../models/menu_template.dart';
import 'servizi_extra_screen.dart';
import '../widgets/wizard_stepper.dart';
import '../providers/piatti_provider.dart';
import '../widgets/tipo_pasto_field.dart';

// AGGIUNTE
import 'dart:typed_data';
import '../providers/preventivi_provider.dart';
import '../widgets/firma_dialog.dart';

class CreaPreventivoScreen extends StatefulWidget {
  const CreaPreventivoScreen({super.key});

  @override
  State<CreaPreventivoScreen> createState() => _CreaPreventivoScreenState();
}

class _CreaPreventivoScreenState extends State<CreaPreventivoScreen> {
  MenuTemplate? _selectedTemplate;
  Map<String, List<Piatto>> _menuInCostruzione = {};
  late TextEditingController _prezzoManualeController;

  @override
  void initState() {
    super.initState();
    _prezzoManualeController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final menuProvider = Provider.of<MenuProvider>(context, listen: false);
      final preventivoBuilder = Provider.of<PreventivoBuilderProvider>(context, listen: false);

      if (menuProvider.tuttiIMenuTemplates.isEmpty) {
        await menuProvider.caricaDatiMenu();
      }

      setState(() {
        _menuInCostruzione = Map.from(preventivoBuilder.menu);

        if (preventivoBuilder.nomeMenuTemplate != null) {
          try {
            _selectedTemplate = menuProvider.tuttiIMenuTemplates
                .firstWhere((t) => t.nomeMenu == preventivoBuilder.nomeMenuTemplate);
          } catch (_) {
            _selectedTemplate = null;
          }
        }

        if (preventivoBuilder.prezzoMenuPersona > 0) {
          _prezzoManualeController.text =
              preventivoBuilder.prezzoMenuPersona.toStringAsFixed(2).replaceAll('.', ',');
        }
      });
    });
  }

  @override
  void dispose() {
    _prezzoManualeController.dispose();
    super.dispose();
  }

  void _commitMenuToProvider() {
    context.read<PreventivoBuilderProvider>().setMenu(_menuInCostruzione);
  }

  void _aggiornaMenuDaTemplate(MenuTemplate? template, MenuProvider provider) {
    setState(() {
      _menuInCostruzione.clear();
      if (template == null) return;

      template.composizioneDefault.forEach((genere, List<String> piattoIds) {
        if (piattoIds.isNotEmpty) {
          _menuInCostruzione[genere] = [];
          for (var id in piattoIds) {
            try {
              final piatto = provider.tuttiIpiatti.firstWhere((p) => p.idUnico == id);
              _menuInCostruzione[genere]?.add(piatto);
            } catch (_) {
              // ignoro gli ID non trovati
            }
          }
        }
      });
    });
    _commitMenuToProvider(); // << commit immediato
  }

  void _rimuoviPiatto(String genere, Piatto piattoDaRimuovere) {
    setState(() {
      _menuInCostruzione[genere]?.removeWhere((p) => p.idUnico == piattoDaRimuovere.idUnico);
      if (_menuInCostruzione[genere]?.isEmpty ?? false) {
        _menuInCostruzione.remove(genere);
      }
    });
    _commitMenuToProvider(); // << commit immediato
  }

  void _aggiungiPiatti(String genere, List<Piatto> piattiDaAggiungere) {
    setState(() {
      if (!_menuInCostruzione.containsKey(genere)) {
        _menuInCostruzione[genere] = [];
      }
      _menuInCostruzione[genere]?.addAll(piattiDaAggiungere);
    });
    _commitMenuToProvider(); // << commit immediato
  }

  // (non utilizzata, lascio per eventuale uso futuro)
  void _applyTemplateToBuilder(MenuTemplate template) {
    final preventivoBuilder = context.read<PreventivoBuilderProvider>();
    final piattiProv = context.read<PiattiProvider>();

    final Map<String, List<Piatto>> nuovoMenu = {};
    template.composizioneDefault.forEach((genere, ids) {
      final List<Piatto> lista = [];
      for (final id in ids) {
        final found = piattiProv.piatti.cast<Piatto?>()
            .firstWhere((p) => p != null && p!.idUnico == id, orElse: () => null);
        if (found != null) lista.add(found);
      }
      if (lista.isNotEmpty) nuovoMenu[genere] = lista;
    });

    preventivoBuilder.setPrezzoDaTemplate(template);
    preventivoBuilder.setMenu(nuovoMenu);
  }

  Future<void> _mostraDialogSelezionePiatto(String genere, MenuProvider provider) async {
    final piattiDisponibili = provider.tuttiIpiatti.where((p) => p.genere == genere).toList();

    final List<Piatto> piattiMultiSelezionati = [];
    bool isMultiSelectMode = false;
    final TextEditingController customCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final theme = Theme.of(context);

            void addCustom() {
              final name = customCtrl.text.trim();
              if (name.isEmpty) return;
              final customPiatto = Piatto(
                idUnico: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                genere: genere,
                nome: name,
                tipologia: 'custom',
              );
              _aggiungiPiatti(genere, [customPiatto]); // commit inside
              Navigator.of(context).pop();
            }

            final hasCustom = customCtrl.text.trim().isNotEmpty;

            return AlertDialog(
              title: Text('Seleziona ${genere.toLowerCase()}'),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 300,
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: customCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome piatto (fuori menu)',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (customCtrl.text.trim().isNotEmpty) {
                          setStateDialog(() {
                            isMultiSelectMode = false;
                            piattiMultiSelezionati.clear();
                          });
                        }
                      },
                      onSubmitted: (_) => addCustom(),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: hasCustom,
                        child: ListView.builder(
                          itemCount: piattiDisponibili.length,
                          itemBuilder: (context, index) {
                            final piatto = piattiDisponibili[index];
                            final isSelected = piattiMultiSelezionati.contains(piatto);
                            final isAlreadyInMenu = _menuInCostruzione[genere]
                                    ?.any((p) => p.idUnico == piatto.idUnico) ??
                                false;

                            return GestureDetector(
                              onLongPress: (hasCustom || isAlreadyInMenu)
                                  ? null
                                  : () => setStateDialog(() {
                                        isMultiSelectMode = true;
                                        if (isSelected) {
                                          piattiMultiSelezionati.remove(piatto);
                                        } else {
                                          piattiMultiSelezionati.add(piatto);
                                        }
                                      }),
                              onTap: (hasCustom || isAlreadyInMenu)
                                  ? null
                                  : () {
                                      if (isMultiSelectMode) {
                                        setStateDialog(() {
                                          if (isSelected) {
                                            piattiMultiSelezionati.remove(piatto);
                                          } else {
                                            piattiMultiSelezionati.add(piatto);
                                          }
                                        });
                                      } else {
                                        _aggiungiPiatti(genere, [piatto]); // commit inside
                                        Navigator.of(context).pop();
                                      }
                                    },
                              child: ListTile(
                                enabled: !isAlreadyInMenu && !hasCustom,
                                title: Text(piatto.nome),
                                subtitle: isAlreadyInMenu ? const Text("Già aggiunto") : null,
                                tileColor: (isMultiSelectMode && isSelected)
                                    ? theme.colorScheme.secondary.withOpacity(0.25)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Annulla'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: hasCustom
                                ? addCustom
                                : (isMultiSelectMode && piattiMultiSelezionati.isNotEmpty)
                                    ? () {
                                        _aggiungiPiatti(genere, piattiMultiSelezionati); // commit inside
                                        Navigator.of(context).pop();
                                      }
                                    : null,
                            child: Text(
                              hasCustom
                                  ? 'Aggiungi (fuori menu)'
                                  : (isMultiSelectMode
                                      ? 'Aggiungi (${piattiMultiSelezionati.length})'
                                      : 'Aggiungi'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mostraDialogAggiungiPortata(MenuProvider provider) async {
    final categorieMancanti =
        provider.tutteLeCategorie.where((cat) => !_menuInCostruzione.containsKey(cat)).toList();
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
                          _commitMenuToProvider(); // << commit
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
                                _commitMenuToProvider(); // << commit
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

  // --- Selettore PRANZO/CENA integrato (niente widget esterno) ---
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
            const TipoPastoField(required: true), // se vuoi renderlo obbligatorio,),
          ],
        );
      },
    );
  }

  // -------- FIRMA & CONFERMA ----------
  Future<void> _firmaEConferma() async {
    // Recupero preventivoId passato via arguments (se presente)
    final String? preventivoId =
        ModalRoute.of(context)?.settings.arguments is String
            ? ModalRoute.of(context)!.settings.arguments as String
            : null;

    if (preventivoId == null || preventivoId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devi prima salvare/creare il preventivo per ottenere un ID.')),
      );
      return;
    }

    // Dialog firma
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

    // Upload firma + conferma
    final prov = context.read<PreventiviProvider>();
    final ok = await prov.caricaFirmaEConferma(preventivoId, pngBytes);

    if (!mounted) return;
    final msg = prov.errorSaving ?? prov.successMessage ?? (ok ? 'Preventivo confermato.' : 'Errore durante la conferma.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea Preventivo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Provider.of<PreventivoBuilderProvider>(context, listen: false).reset();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          // NUOVA AZIONE: Esci senza salvare e torna alla Home
          IconButton(
            tooltip: 'Esci senza salvare (Home)',
            icon: const Icon(Icons.home_outlined),
            onPressed: () async {
              final conferma = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Uscire senza salvare?'),
                  content: const Text('Le modifiche non salvate andranno perse.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Annulla'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Esci'),
                    ),
                  ],
                ),
              );
              if (conferma == true && mounted) {
                // Reset del builder e ritorno alla Home
                Provider.of<PreventivoBuilderProvider>(context, listen: false).reset();
                Navigator.of(context).popUntil((route) => route.isFirst);

                // In alternativa, se usi route nominata per la Home:
                // Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
              }
            },
          ),
        ],
      ),
      body: Consumer<MenuProvider>(
        builder: (context, menuProvider, child) {
          if (menuProvider.isLoading && menuProvider.tuttiIMenuTemplates.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (menuProvider.errore != null) {
            return Center(child: Text('Errore: ${menuProvider.errore}'));
          }
          return _buildBody(menuProvider);
        },
      ),
    );
  }

  Widget _buildBody(MenuProvider menuProvider) {
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
                _buildTemplateSelector(menuProvider),

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
                      preventivoBuilder.setPrezzoManuale(prezzo);
                    },
                  ),
                ],

                // --- Selettore Pranzo/Cena (obbligatorio) ---
                const SizedBox(height: 12),
                _buildTipoPastoSelector(),
                const SizedBox(height: 12),

                const SizedBox(height: 24),
                const Divider(),
                _buildMenuComposition(menuProvider),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text("Aggiungi Portata"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () => _mostraDialogAggiungiPortata(menuProvider),
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

              // Validazione Tipo Pasto
              if (builder.tipoPasto == null || builder.tipoPasto!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seleziona Pranzo o Cena per proseguire.')),
                );
                return;
              }

              // Commit finale del menu in Provider prima di navigare
              _commitMenuToProvider();

              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ServiziExtraScreen()),
              );
            },
            child: Row(
              children: const [
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

  Widget _buildTemplateSelector(MenuProvider menuProvider) {
    return DropdownButtonFormField<MenuTemplate?>(
      value: _selectedTemplate,
      items: [
        const DropdownMenuItem<MenuTemplate?>(value: null, child: Text('Crea Menu da Zero')),
        ...menuProvider.tuttiIMenuTemplates.map((template) {
          return DropdownMenuItem<MenuTemplate>(
            value: template,
            child: Text('${template.nomeMenu} (€${template.prezzo.toStringAsFixed(2)})'),
          );
        }).toList(),
      ],
      onChanged: (MenuTemplate? newValue) {
        final builder = Provider.of<PreventivoBuilderProvider>(context, listen: false);
        setState(() {
          _selectedTemplate = newValue;
          _aggiornaMenuDaTemplate(newValue, menuProvider); // include commit
        });

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

  Widget _buildMenuComposition(MenuProvider menuProvider) {
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
                onPressed: () => _mostraSheetSelezionePiatto(genere, menuProvider),
              ),
            ),
            const Divider(height: 24),
          ],
        );
      }).toList(),
    );
  }

  // --------- UX tastiera: AnimatedPadding + DraggableScrollableSheet ---------
  Future<void> _mostraSheetSelezionePiatto(String genere, MenuProvider provider) async {
    final piattiDisponibili = provider.tuttiIpiatti.where((p) => p.genere == genere).toList();

    final List<Piatto> selezionati = [];
    bool multi = false;
    final TextEditingController customCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: RoundedRectangleBorder(
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
            _aggiungiPiatti(genere, [custom]); // commit inside
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
                                        _aggiungiPiatti(genere, [piatto]); // commit inside
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
                                            _aggiungiPiatti(genere, selezionati); // commit inside
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
