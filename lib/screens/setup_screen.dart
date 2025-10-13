import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

// Import per i Dipendenti
import '../providers/dipendenti_provider.dart';
import '../models/dipendente.dart';

// Import per i Turni
import '../providers/turni_provider.dart';
import '../models/tipo_turno.dart';
import '../config/app_config.dart'; 


// Import per PIATTI + MENU
import '../providers/piatti_provider.dart';
import '../providers/menu_templates_provider.dart';
import '../models/piatto.dart';
import '../models/menu_template.dart';


import 'dart:convert';
import 'package:http/http.dart' as http;

import '../widgets/vibration_settings_card.dart';

class SetupScreen extends StatefulWidget {

  @override
  _SetupScreenState createState() => _SetupScreenState();  
}



class AutorizzazioneApp {
  final String nome;
  int stato; // 0=disabled, 1=checked, 2=unchecked

  AutorizzazioneApp({required this.nome, required this.stato});

  factory AutorizzazioneApp.fromJson(Map<String, dynamic> json) {
    return AutorizzazioneApp(
      nome: json['nome'],
      stato: json['stato'],
    );
  }

  Map<String, dynamic> toJson() => {'nome': nome, 'stato': stato};
}



class _SetupScreenState extends State<SetupScreen> {
  List<AutorizzazioneApp> _autorizzazioniApp = [];
  bool _isLoadingAutorizzazioni = false;
  String? _erroreAutorizzazioni;

  // Generi/tipologie coerenti con i fogli Google
  static const List<String> _generi = ['antipasto','primo','secondo','contorno','piatto_unico'];
  static const List<String> _tipologie = ['carne','pesce','misto','neutro'];

  Widget _buildPiattiSection() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.restaurant_menu, color: theme.colorScheme.onPrimary),
        iconColor: theme.colorScheme.onPrimary,
        collapsedIconColor: theme.colorScheme.onPrimary,
        title: Text(
          'Gestione Piatti',
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
        ),
        // ⬇️ NUOVO: ogni volta che espandi, ricarica dal foglio
        onExpansionChanged: (expanded) {
          if (expanded) {
            context.read<PiattiProvider>().fetch();
          }
        },
        children: [
          Container(
            color: theme.colorScheme.background,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nuovo Piatto'),
                      onPressed: () => _openPiattoDialog(),
                    ),
                  ),
                ),
                Consumer<PiattiProvider>(
                  builder: (ctx, prov, _) {
                    if (prov.isLoading && prov.piatti.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (prov.error != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text('Errore: ${prov.error}'),
                        ),
                      );
                    }
                    if (prov.piatti.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text('Nessun piatto presente.'),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: prov.piatti.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = prov.piatti[i];
                        return Dismissible(
                          key: ValueKey(p.idUnico),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            final confermato = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Eliminare questo piatto?'),
                                content: Text(p.nome),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Annulla'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Elimina'),
                                  ),
                                ],
                              ),
                            );

                            if (confermato != true) return false;

                            final ok = await context.read<PiattiProvider>().remove(p.idUnico);
                            if (!ok) {
                              final err = context.read<PiattiProvider>().error ?? 'Errore eliminazione piatto';
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                            }
                            return ok;
                          },
                          child: ListTile(
                            title: Text(p.nome),
                            subtitle: Text('${p.genere} • ${p.tipologia}'),
                            onTap: () => _openPiattoDialog(edit: p),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPiattoDialog({Piatto? edit}) async {
    final prov = context.read<PiattiProvider>();
    final formKey = GlobalKey<FormState>();
    String genere = edit?.genere ?? _generi.first;
    String tipologia = edit?.tipologia ?? _tipologie.first;
    final nomeCtrl  = TextEditingController(text: edit?.nome ?? '');
    final descrCtrl = TextEditingController(text: edit?.descrizione ?? '');
    final allergCtrl= TextEditingController(text: edit?.allergeni ?? '');
    final fotoCtrl  = TextEditingController(text: edit?.linkFoto ?? '');

    // <<< flags dichiarati fuori dal builder
    bool saving = false;
    bool deleting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          Future<void> _doSave() async {
            if (!formKey.currentState!.validate()) return;
            setStateDialog(() => saving = true);

            final payload = {
              'genere': genere,
              'piatto': nomeCtrl.text.trim(),            // chiave attesa dal backend
              'descrizione': descrCtrl.text.trim(),
              'allergeni': allergCtrl.text.trim(),
              'link_foto_piatto': fotoCtrl.text.trim(),  // chiave attesa dal backend
              'tipologia': tipologia,
            };

            final ok = edit == null
                ? await prov.add(payload)                // add() già fa fetch() on success
                : await prov.update(edit.idUnico, payload);

            // Cintura di sicurezza: dopo update, riallinea dal foglio
            if (ok && edit != null) {
              await prov.fetch();
            }

            if (!ctx.mounted) return;
            setStateDialog(() => saving = false);

            if (ok) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(edit == null ? 'Piatto creato' : 'Piatto aggiornato')),
              );
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(prov.error ?? 'Operazione non riuscita')));
            }
          }

          Future<void> _doDelete() async {
            if (edit == null) return;
            final conferma = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Eliminare il piatto?'),
                content: const Text('Questa operazione non può essere annullata.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Annulla')),
                  ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Elimina')),
                ],
              ),
            );
            if (conferma != true) return;

            setStateDialog(() => deleting = true);
            final ok = await prov.remove(edit.idUnico);
            if (!ctx.mounted) return;
            setStateDialog(() => deleting = false);

            if (ok) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Piatto eliminato')));
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(prov.error ?? 'Eliminazione fallita')));
            }
          }

          return AbsorbPointer(
            absorbing: saving || deleting,
            child: AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(edit == null ? 'Nuovo piatto' : 'Modifica piatto')),
                  if (edit != null)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: deleting
                          ? const SizedBox(
                              key: ValueKey('spin_del'),
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              key: const ValueKey('btn_del'),
                              tooltip: 'Elimina',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _doDelete,
                            ),
                    ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16,12,16,4),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                      value: genere,
                      items: _generi.map((g)=>DropdownMenuItem(value:g, child: Text(g))).toList(),
                      onChanged: (v)=> genere = v!,
                      decoration: const InputDecoration(labelText: 'Genere'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(labelText: 'Nome piatto'),
                      validator: (v)=> (v==null || v.trim().isEmpty) ? 'Richiesto' : null,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: tipologia,
                      items: _tipologie.map((t)=>DropdownMenuItem(value:t, child: Text(t))).toList(),
                      onChanged: (v)=> tipologia = v!,
                      decoration: const InputDecoration(labelText: 'Tipologia'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(controller: descrCtrl, decoration: const InputDecoration(labelText: 'Descrizione'), maxLines: 3),
                    const SizedBox(height: 8),
                    TextFormField(controller: allergCtrl, decoration: const InputDecoration(labelText: 'Allergeni')),
                    const SizedBox(height: 8),
                    TextFormField(controller: fotoCtrl, decoration: const InputDecoration(labelText: 'Link foto')),
                  ]),
                ),
              ),
              actions: [
                TextButton(onPressed: saving || deleting ? null : ()=>Navigator.pop(ctx), child: const Text('Annulla')),
                ElevatedButton(
                  onPressed: saving || deleting ? null : _doSave,
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(edit == null ? 'Crea' : 'Salva'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuTemplatesSection() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.menu_book, color: theme.colorScheme.onPrimary),
        iconColor: theme.colorScheme.onPrimary,
        collapsedIconColor: theme.colorScheme.onPrimary,
        title: Text(
          'Gestione Menu',
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
        ),
        // ⬇️ NUOVO: quando espandi, ricarica sia menu che piatti (per il picker)
        onExpansionChanged: (expanded) {
          if (expanded) {
            final menuProv = context.read<MenuTemplatesProvider>();
            final piattiProv = context.read<PiattiProvider>();
            menuProv.fetch();
            piattiProv.fetch();
          }
        },
        children: [
          Container(
            color: theme.colorScheme.background,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nuovo Menu'),
                      onPressed: () => _openMenuDialog(),
                    ),
                  ),
                ),
                Consumer2<MenuTemplatesProvider, PiattiProvider>(
                  builder: (ctx, menuProv, piattiProv, _) {
                    if ((menuProv.isLoading && menuProv.templates.isEmpty) || piattiProv.isLoading) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (menuProv.error != null) {
                      return Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text('Errore: ${menuProv.error}'),
                      );
                    }
                    if (menuProv.templates.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text('Nessun menu presente.'),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: menuProv.templates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = menuProv.templates[i];
                        return Dismissible(
                          key: ValueKey(m.idMenu),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            final confermato = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Eliminare questo menu?'),
                                content: Text(m.nomeMenu),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
                                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
                                ],
                              ),
                            );

                            if (confermato != true) return false;

                            final ok = await context.read<MenuTemplatesProvider>().remove(m.idMenu);
                            if (!ok) {
                              final err = context.read<MenuTemplatesProvider>().error ?? 'Errore eliminazione menu';
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                            }
                            return ok;
                          },
                          child: ListTile(
                            title: Text('${m.nomeMenu} • €${m.prezzo.toStringAsFixed(2)}'),
                            subtitle: Text(m.tipologia),
                            onTap: () => _openMenuDialog(edit: m),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMenuDialog({MenuTemplate? edit}) async {
    final menuProv = context.read<MenuTemplatesProvider>();
    final piattiProv = context.read<PiattiProvider>();

    final formKey = GlobalKey<FormState>();
    final nomeCtrl   = TextEditingController(text: edit?.nomeMenu ?? '');
    final prezzoCtrl = TextEditingController(
        text: edit != null ? edit.prezzo.toStringAsFixed(2).replaceAll('.', ',') : '');
    String tipologia = edit?.tipologia ?? _tipologie.first;

    // composizione: genere -> lista id_unico
    final Map<String, List<String>> composizione = {
      for (final g in _generi) g: List<String>.from(edit?.composizioneDefault[g] ?? []),
    };

    // <<< flags fuori dal builder
    bool saving = false;
    bool deleting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          Future<void> _doSave() async {
            if (!formKey.currentState!.validate()) return;
            setStateDialog(() => saving = true);

            final prezzo = double.tryParse(prezzoCtrl.text.replaceAll(',', '.')) ?? 0.0;

            final payload = {
              'MENU': nomeCtrl.text.trim(),
              'prezzo': prezzo,
              'tipologia': tipologia,
              'composizione_default_json': {
                for (final g in _generi)
                  if ((composizione[g] ?? const []).isNotEmpty) g: composizione[g],
              },
            };

            final ok = edit == null
                ? await menuProv.add(payload)
                : await menuProv.update(edit.idMenu, payload);

            if (!ctx.mounted) return;
            setStateDialog(() => saving = false);

            if (ok) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(edit == null ? 'Menu creato' : 'Menu aggiornato')),
              );
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(menuProv.error ?? 'Operazione non riuscita')));
            }
          }

          Future<void> _doDelete() async {
            if (edit == null) return;
            final conferma = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Eliminare il menu?'),
                content: const Text('Questa operazione non può essere annullata.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Annulla')),
                  ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Elimina')),
                ],
              ),
            );
            if (conferma != true) return;

            setStateDialog(() => deleting = true);
            final ok = await menuProv.remove(edit.idMenu);
            if (!ctx.mounted) return;
            setStateDialog(() => deleting = false);

            if (ok) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Menu eliminato')));
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(menuProv.error ?? 'Eliminazione fallita')));
            }
          }

          return AbsorbPointer(
            absorbing: saving || deleting,
            child: AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(edit == null ? 'Nuovo menu' : 'Modifica menu')),
                  if (edit != null)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: deleting
                          ? const SizedBox(
                              key: ValueKey('spin_del'),
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              key: const ValueKey('btn_del'),
                              tooltip: 'Elimina',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _doDelete,
                            ),
                    ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16,12,16,8),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(labelText: 'Nome menu'),
                      validator: (v)=> (v==null || v.trim().isEmpty) ? 'Richiesto' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: prezzoCtrl,
                      decoration: const InputDecoration(labelText: 'Prezzo (€/persona)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final d = double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
                        return d > 0 ? null : 'Prezzo non valido';
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: tipologia,
                      items: _tipologie.map((t)=>DropdownMenuItem(value:t, child: Text(t))).toList(),
                      onChanged: (v)=> tipologia = v!,
                      decoration: const InputDecoration(labelText: 'Tipologia'),
                    ),
                    const SizedBox(height: 12),

                    // blocchi per ogni genere
                    ..._generi.map((g) {
                      final selectedIds = composizione[g]!;
                      final selectedPiatti = piattiProv.piatti.where((p) => selectedIds.contains(p.idUnico)).toList();
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(g.toUpperCase(), style: Theme.of(ctx).textTheme.titleMedium)),
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Seleziona'),
                            onPressed: () async {
                              final picked = await _pickPiatti(genere: g, preselected: selectedIds);
                              if (picked != null) {
                                setStateDialog(() {
                                  composizione[g]!..clear()..addAll(picked);
                                });
                              }
                            },
                          ),
                        ]),
                        if (selectedPiatti.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('Nessun $g selezionato',
                                style: TextStyle(color: Theme.of(ctx).hintColor, fontStyle: FontStyle.italic)),
                          )
                        else
                          Wrap(
                            spacing: 6, runSpacing: -6,
                            children: selectedPiatti.map((p) => Chip(
                              label: Text(p.nome),
                              onDeleted: () => setStateDialog(() => composizione[g]!.remove(p.idUnico)),
                            )).toList(),
                          ),
                        const Divider(),
                      ]);
                    }),
                  ]),
                ),
              ),
              actions: [
                TextButton(onPressed: saving || deleting ? null : ()=>Navigator.pop(ctx), child: const Text('Annulla')),
                ElevatedButton(
                  onPressed: saving || deleting ? null : _doSave,
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(edit == null ? 'Crea' : 'Salva'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }





  Future<List<String>?> _pickPiatti({
    required String genere,
    required List<String> preselected,
  }) async {
    final piatti = context.read<PiattiProvider>().piatti.where((p) => p.genere == genere).toList();
    final sel = preselected.toSet();

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.85,
          builder: (ctx, controller) => Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 48, height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade500, borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Seleziona $genere', style: Theme.of(ctx).textTheme.titleLarge),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: piatti.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = piatti[i];
                    final selected = sel.contains(p.idUnico);
                    return ListTile(
                      title: Text(p.nome),
                      subtitle: Text(p.tipologia),
                      trailing: Checkbox(value: selected, onChanged: (_) {
                        selected ? sel.remove(p.idUnico) : sel.add(p.idUnico);
                        (ctx as Element).markNeedsBuild();
                      }),
                      onTap: () {
                        selected ? sel.remove(p.idUnico) : sel.add(p.idUnico);
                        (ctx as Element).markNeedsBuild();
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Expanded(child: OutlinedButton(onPressed: ()=>Navigator.pop(ctx, null), child: const Text('Annulla'))),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(onPressed: ()=>Navigator.pop(ctx, sel.toList()), child: Text('Aggiungi (${sel.length})'))),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }




  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }




  // Funzione unica per aggiornare tutti i dati
  Future<void> _refreshData() async {
    await Future.wait([
      Provider.of<DipendentiProvider>(context, listen: false).fetchDipendenti(),
      Provider.of<TurniProvider>(context, listen: false).fetchTipiTurno(),
      // NEW
      Provider.of<PiattiProvider>(context, listen: false).fetch(),
      Provider.of<MenuTemplatesProvider>(context, listen: false).fetch(),
    ]);
    await _fetchAutorizzazioniApp();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Setup'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              _buildDipendentiSection(),
              const SizedBox(height: 16),
              _buildTurniSection(),

              _buildPiattiSection(),
              const SizedBox(height: 16),
              _buildMenuTemplatesSection(),
              const SizedBox(height: 16),

              const VibrationSettingsCard(),
              const SizedBox(height: 16),

              const SizedBox(height: 16),
              _buildAutorizzazioniAppSection(), 
            ],
          ),
        ),
      ),
    );
  }


// lib/screens/setup_screen.dart -> SOSTITUISCI QUESTA FUNZIONE

  Widget _buildAutorizzazioniAppSection() {
    final theme = Theme.of(context);
    
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.security, color: theme.colorScheme.onPrimary),
        iconColor: theme.colorScheme.onPrimary,
        collapsedIconColor: theme.colorScheme.onPrimary,
        title: RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 16, color: theme.colorScheme.onPrimary),
            children: <TextSpan>[
              TextSpan(
                text: 'Autorizzazioni App ', 
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: '  - voci menu nascoste',
                style: TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
              ),
            ],
          ),
        ),
        // MODIFICA: Il contenuto ora non ha più uno sfondo bianco separato.
        children: [
          if (_isLoadingAutorizzazioni)
            Center(child: Padding(
              padding: const EdgeInsets.all(12),
              child: CircularProgressIndicator(color: theme.colorScheme.onPrimary),
            )),
          if (_erroreAutorizzazioni != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_erroreAutorizzazioni!, style: TextStyle(color: theme.colorScheme.onError)),
            ),
          if (!_isLoadingAutorizzazioni && _erroreAutorizzazioni == null)
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _autorizzazioniApp.length,
              itemBuilder: (ctx, index) {
                final item = _autorizzazioniApp[index];
                final isDisabled = item.stato == 0;
                final isChecked = item.stato == 1;
                return ListTile(
                  leading: Checkbox(
                    value: isChecked,
                    activeColor: theme.colorScheme.onPrimary,
                    checkColor: theme.colorScheme.primary,
                     side: MaterialStateBorderSide.resolveWith(
                        (states) => BorderSide(width: 2.0, color: theme.colorScheme.onPrimary),
                      ),
                    onChanged: isDisabled
                        ? null
                        : (v) async {
                            final nuovoStato = isChecked ? 2 : 1;
                            setState(() {
                              _autorizzazioniApp[index].stato = nuovoStato;
                            });
                            await _aggiornaAutorizzazioneApp(item.nome, nuovoStato);
                          },
                  ),
                  title: Text(
                    item.nome,
                    style: isDisabled
                        ? TextStyle(
                            color: theme.colorScheme.onPrimary.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                          )
                        : TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                  enabled: !isDisabled,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDipendentiSection() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.people, color: theme.colorScheme.onPrimary),
        iconColor: theme.colorScheme.onPrimary,
        collapsedIconColor: theme.colorScheme.onPrimary,
        title: Text('Gestione Dipendenti', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
        children: [
          Container(
            color: theme.colorScheme.background,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.add),
                      label: Text('Aggiungi'),
                      onPressed: () => _mostraDialogAggiungiDipendente(),
                    ),
                  ),
                ),
                Consumer<DipendentiProvider>(
                  builder: (ctx, provider, _) {
                    if (provider.isLoading && provider.dipendenti.isEmpty) {
                      return Center(child: CircularProgressIndicator());
                    }
                    if (provider.error != null) {
                      return Center(child: Text('Errore: ${provider.error}'));
                    }
                    if (provider.dipendenti.isEmpty) {
                      return Center(child: Text('Nessun dipendente trovato.'));
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: provider.dipendenti.length,
                      itemBuilder: (ctx, index) {
                        return DipendenteItem(
                          key: ValueKey(provider.dipendenti[index].idUnico),
                          dipendente: provider.dipendenti[index],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _mostraDialogAggiungiDipendente() {
    final _formKey = GlobalKey<FormState>();
    final Map<String, String> _newData = {};
    final theme = Theme.of(context);
    final textStyle = TextStyle(color: theme.colorScheme.onSurface);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aggiungi Dipendente'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(decoration: InputDecoration(labelText: 'Nome Dipendente'), style: textStyle, validator: (v) => v!.isEmpty ? 'Campo obbligatorio' : null, onSaved: (v) => _newData['nome_dipendente'] = v!,),
                TextFormField(decoration: InputDecoration(labelText: 'Ruolo'), style: textStyle, validator: (v) => v!.isEmpty ? 'Campo obbligatorio' : null, onSaved: (v) => _newData['ruolo'] = v!,),
                TextFormField(decoration: InputDecoration(labelText: 'PIN'), style: textStyle, keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'Campo obbligatorio' : null, onSaved: (v) => _newData['pin'] = v!,),
                TextFormField(decoration: InputDecoration(labelText: 'Email'), style: textStyle, keyboardType: TextInputType.emailAddress, onSaved: (v) => _newData['email'] = v ?? '',),
                TextFormField(decoration: InputDecoration(labelText: 'Telefono'), style: textStyle, keyboardType: TextInputType.phone, onSaved: (v) => _newData['telefono'] = v ?? '',),
                TextFormField(decoration: InputDecoration(labelText: 'Colore (es. #FF0000)'), style: textStyle, onSaved: (v) => _newData['colore'] = v ?? '',),
                for (int i = 1; i <= 10; i++)
                  TextFormField(decoration: InputDecoration(labelText: 'Campo Extra ${i.toString().padLeft(2, '0')}'), style: textStyle, onSaved: (v) => _newData['campo_extra_${i.toString().padLeft(2, '0')}'] = v ?? '',),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Annulla')),
          ElevatedButton(
            child: Text('Salva'),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                Provider.of<DipendentiProvider>(context, listen: false).addDipendente(_newData);
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  
  void _confermaEliminazioneDipendente(String id) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(color: theme.colorScheme.onPrimary);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.primary,
        title: Text('Sei sicuro?', style: textStyle),
        content: Text('Questa azione eliminerà il dipendente in modo permanente.', style: textStyle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Annulla', style: textStyle),
          ),
          TextButton(
            child: Text('Elimina', style: textStyle.copyWith(fontWeight: FontWeight.bold)),
            onPressed: () {
              Provider.of<DipendentiProvider>(context, listen: false).deleteDipendente(id);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }


  Widget _buildTurniSection() {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.access_time_filled, color: theme.colorScheme.onPrimary),
        iconColor: theme.colorScheme.onPrimary,
        collapsedIconColor: theme.colorScheme.onPrimary,
        title: Text('Gestione Turno', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
        children: [
          Container(
            color: theme.colorScheme.background,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.add),
                      label: Text('Aggiungi Turno'),
                      onPressed: () => _mostraDialogAggiungiTurno(),
                    ),
                  ),
                ),
                Consumer<TurniProvider>(
                  builder: (ctx, provider, _) {
                    if (provider.isLoading && provider.tipiTurno.isEmpty) {
                      return Center(child: CircularProgressIndicator());
                    }
                    if (provider.error != null) {
                      return Center(child: Text('Errore: ${provider.error}'));
                    }
                    if (provider.tipiTurno.isEmpty) {
                      return Center(child: Text('Nessun tipo di turno trovato.'));
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: provider.tipiTurno.length,
                      itemBuilder: (ctx, index) {
                        return TurnoItem(
                          key: ValueKey(provider.tipiTurno[index].idTurno),
                          tipoTurno: provider.tipiTurno[index],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostraDialogAggiungiTurno() {
    final _formKey = GlobalKey<FormState>();
    final Map<String, String> _newData = {};
    final theme = Theme.of(context);
    final textStyle = TextStyle(color: theme.colorScheme.onSurface);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aggiungi Tipo Turno'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(decoration: InputDecoration(labelText: 'Nome Turno'), style: textStyle, validator: (v) => v!.isEmpty ? 'Obbligatorio' : null, onSaved: (v) => _newData['nome_turno'] = v!,),
                SizedBox(height: 16),
                TimePickerFormField(labelText: 'Orario Inizio', onSaved: (v) => _newData['orario_inizio'] = v!,),
                SizedBox(height: 16),
                TimePickerFormField(labelText: 'Orario Fine', onSaved: (v) => _newData['orario_fine'] = v!,),
            ]),
          )
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Annulla')),
          ElevatedButton(
            child: Text('Salva'),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                Provider.of<TurniProvider>(context, listen: false).addTipoTurno(_newData);
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  void _confermaEliminazioneTurno(String id) {
    final theme = Theme.of(context);
    final textStyleOnPrimary = TextStyle(color: theme.colorScheme.onPrimary);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: theme.colorScheme.primary,
      title: Text('Confermi?', style: textStyleOnPrimary),
      content: Text('Questa azione eliminerà il tipo di turno.',style: textStyleOnPrimary),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Annulla', style: textStyleOnPrimary)),
        TextButton(
          child: Text('Elimina', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
          onPressed: () {
            Provider.of<TurniProvider>(context, listen: false).deleteTipoTurno(id);
            Navigator.of(ctx).pop();
          },
        ),
      ],
    ));
  }




  Future<void> _aggiornaAutorizzazioneApp(String nomeFunzione, int nuovoStato) async {
    final theme = Theme.of(context);
    final url = Uri.parse('${AppConfig.currentBaseUrl}/autorizzazioni-app');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'nome': nomeFunzione, 'nuovo_stato': nuovoStato}),
      );
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore aggiornamento permesso (${response.statusCode})'),
          backgroundColor: theme.colorScheme.error,
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore di rete: $e'),
        backgroundColor: theme.colorScheme.error,
      ));
    }
  }

  Future<void> _fetchAutorizzazioniApp() async {
    setState(() {
      _isLoadingAutorizzazioni = true;
      _erroreAutorizzazioni = null;
    });
    try {
      final url = Uri.parse('${AppConfig.currentBaseUrl}/autorizzazioni-app');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> lista = json.decode(response.body);
        setState(() {
          _autorizzazioniApp = lista.map((e) => AutorizzazioneApp.fromJson(e)).toList();
          _isLoadingAutorizzazioni = false;
        });
      } else {
        setState(() {
          _erroreAutorizzazioni = 'Errore di caricamento dati (${response.statusCode})';
          _isLoadingAutorizzazioni = false;
        });
      }
    } catch (e) {
      setState(() {
        _erroreAutorizzazioni = 'Errore: $e';
        _isLoadingAutorizzazioni = false;
      });
    }
  }

}

class DipendenteItem extends StatefulWidget {
  final Dipendente dipendente;
  DipendenteItem({Key? key, required this.dipendente}) : super(key: key);
  @override
  _DipendenteItemState createState() => _DipendenteItemState();
}

class _DipendenteItemState extends State<DipendenteItem> {
  bool _isEditing = false;
  bool _isExpanded = false;
  late TextEditingController _nomeController;
  late TextEditingController _ruoloController;
  late TextEditingController _pinController;
  late TextEditingController _emailController;
  late TextEditingController _telController;
  late TextEditingController _coloreController;
  late List<TextEditingController> _extraControllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final dip = widget.dipendente;
    _nomeController = TextEditingController(text: dip.nomeDipendente);
    _ruoloController = TextEditingController(text: dip.ruolo);
    _pinController = TextEditingController(text: dip.pin);
    _emailController = TextEditingController(text: dip.email);
    _telController = TextEditingController(text: dip.telefono);
    _coloreController = TextEditingController(text: dip.colore);
    
    _extraControllers = List.generate(10, (i) {
      switch (i) {
        case 0: return TextEditingController(text: dip.campoExtra01);
        case 1: return TextEditingController(text: dip.campoExtra02);
        case 2: return TextEditingController(text: dip.campoExtra03);
        case 3: return TextEditingController(text: dip.campoExtra04);
        case 4: return TextEditingController(text: dip.campoExtra05);
        case 5: return TextEditingController(text: dip.campoExtra06);
        case 6: return TextEditingController(text: dip.campoExtra07);
        case 7: return TextEditingController(text: dip.campoExtra08);
        case 8: return TextEditingController(text: dip.campoExtra09);
        case 9: return TextEditingController(text: dip.campoExtra10);
        default: return TextEditingController();
      }
    });
  }
  
  @override
  void didUpdateWidget(DipendenteItem oldWidget) {
      super.didUpdateWidget(oldWidget);
      if (widget.dipendente != oldWidget.dipendente) {
          _initControllers();
      }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _ruoloController.dispose();
    _pinController.dispose();
    _emailController.dispose();
    _telController.dispose();
    _coloreController.dispose();
    _extraControllers.forEach((c) => c.dispose());
    super.dispose();
  }
  
  void _onSave() {
      final theme = Theme.of(context);
      final Map<String, dynamic> data = {
        'nome_dipendente': _nomeController.text,
        'ruolo': _ruoloController.text,
        'pin': _pinController.text,
        'email': _emailController.text,
        'telefono': _telController.text,
        'colore': _coloreController.text,
      };

      for (int i = 0; i < _extraControllers.length; i++) {
        data['campo_extra_${(i + 1).toString().padLeft(2, '0')}'] = _extraControllers[i].text;
      }

      Provider.of<DipendentiProvider>(context, listen: false)
        .updateDipendente(widget.dipendente.idUnico, data)
        .then((success) {
          if (success && mounted) {
              setState(() { _isEditing = false; _isExpanded = false; });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dipendente aggiornato!'), duration: Duration(seconds: 2),));
          } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante l\'aggiornamento.'), backgroundColor: theme.colorScheme.error,));
          }
      });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: _isEditing ? theme.cardColor : theme.colorScheme.primary,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(4.0)
      ),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          if (!_isEditing) {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: _isEditing
              ? _buildEditingView()
              : (_isExpanded ? _buildExpandedView() : _buildReadOnlyView()),
        ),
      ),
    );
  }

  Widget _buildReadOnlyView() {
    final theme = Theme.of(context);
    final dip = widget.dipendente;
    return ListTile(
      title: Text(dip.nomeDipendente, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
      subtitle: Text('Ruolo: ${dip.ruolo}\nPIN: ${dip.pin}\nTel: ${dip.telefono}', style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.8))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit, color: theme.colorScheme.onPrimary),
            onPressed: () => setState(() => _isEditing = true),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: theme.colorScheme.error),
            onPressed: () => (context.findAncestorStateOfType<_SetupScreenState>())?.
                _confermaEliminazioneDipendente(widget.dipendente.idUnico),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedView() {
    final theme = Theme.of(context);
    final dip = widget.dipendente;
    final textStyle = TextStyle(fontSize: 14, color: theme.colorScheme.onPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(dip.nomeDipendente, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onPrimary)),
          subtitle: Text('Ruolo: ${dip.ruolo}', style: textStyle),
          trailing: IconButton(
            icon: Icon(Icons.arrow_drop_up, size: 30, color: theme.colorScheme.onPrimary),
            onPressed: () {
              setState(() {
                _isExpanded = false;
              });
            },
          ),
        ),
        Divider(color: theme.colorScheme.onPrimary.withOpacity(0.2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID Unico: ${dip.idUnico}', style: textStyle),
              Text('PIN: ${dip.pin}', style: textStyle),
              Text('Email: ${dip.email}', style: textStyle),
              Text('Telefono: ${dip.telefono}', style: textStyle),
              Text('Colore: ${dip.colore}', style: textStyle),
              if (dip.campoExtra01.isNotEmpty) Text('Campo Extra 01: ${dip.campoExtra01}', style: textStyle),
              if (dip.campoExtra02.isNotEmpty) Text('Campo Extra 02: ${dip.campoExtra02}', style: textStyle),
              if (dip.campoExtra03.isNotEmpty) Text('Campo Extra 03: ${dip.campoExtra03}', style: textStyle),
              if (dip.campoExtra04.isNotEmpty) Text('Campo Extra 04: ${dip.campoExtra04}', style: textStyle),
              if (dip.campoExtra05.isNotEmpty) Text('Campo Extra 05: ${dip.campoExtra05}', style: textStyle),
              if (dip.campoExtra06.isNotEmpty) Text('Campo Extra 06: ${dip.campoExtra06}', style: textStyle),
              if (dip.campoExtra07.isNotEmpty) Text('Campo Extra 07: ${dip.campoExtra07}', style: textStyle),
              if (dip.campoExtra08.isNotEmpty) Text('Campo Extra 08: ${dip.campoExtra08}', style: textStyle),
              if (dip.campoExtra09.isNotEmpty) Text('Campo Extra 09: ${dip.campoExtra09}', style: textStyle),
              if (dip.campoExtra10.isNotEmpty) Text('Campo Extra 10: ${dip.campoExtra10}', style: textStyle),
            ],
          ),
        ),
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(Icons.edit, color: theme.colorScheme.onPrimary),
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: Icon(Icons.delete, color: theme.colorScheme.error),
              onPressed: () => (context.findAncestorStateOfType<_SetupScreenState>())?.
                  _confermaEliminazioneDipendente(widget.dipendente.idUnico),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditingView() {
    final theme = Theme.of(context);
    final textStyle = TextStyle(color: theme.colorScheme.onSurface);
    return Column(
      children: [
        TextFormField(controller: _nomeController, decoration: InputDecoration(labelText: 'Nome'),style: textStyle,),
        TextFormField(controller: _ruoloController, decoration: InputDecoration(labelText: 'Ruolo'),style: textStyle,),
        TextFormField(controller: _pinController, decoration: InputDecoration(labelText: 'PIN'), keyboardType: TextInputType.number,style: textStyle,),
        TextFormField(controller: _emailController, decoration: InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress,style: textStyle,),
        TextFormField(controller: _telController, decoration: InputDecoration(labelText: 'Telefono'), keyboardType: TextInputType.phone,style: textStyle,),
        TextFormField(controller: _coloreController, decoration: InputDecoration(labelText: 'Colore'),style: textStyle,),
        
        ExpansionTile(
          title: Text('Campi Extra', style: TextStyle(fontSize: 14)),
          tilePadding: EdgeInsets.zero,
          children: [
            for (int i = 0; i < 10; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: TextFormField(
                  controller: _extraControllers[i],
                  decoration: InputDecoration(
                    labelText: 'Campo Extra ${(i + 1).toString().padLeft(2, '0')}',
                    isDense: true,
                  ),
                  style: textStyle,
                ),
              ),
          ],
        ),

        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              child: Text('Annulla'),
              onPressed: () {
                _initControllers(); 
                setState(() { _isEditing = false; _isExpanded = true; });
              },
            ),
            ElevatedButton(
              child: Text('Salva'),
              onPressed: _onSave,
            ),
          ],
        )
      ],
    );
  }
}


class TurnoItem extends StatefulWidget {
  final TipoTurno tipoTurno;
  TurnoItem({Key? key, required this.tipoTurno}) : super(key: key);
  @override
  _TurnoItemState createState() => _TurnoItemState();
}

class _TurnoItemState extends State<TurnoItem> {
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  
  String? _nomeTurno;
  String? _orarioInizio;
  String? _orarioFine;
  
  void _onSave() {
    final theme = Theme.of(context);
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final data = {
        'nome_turno': _nomeTurno,
        'orario_inizio': _orarioInizio,
        'orario_fine': _orarioFine,
      };
      Provider.of<TurniProvider>(context, listen: false)
        .updateTipoTurno(widget.tipoTurno.idTurno, data)
        .then((success) {
          if (success && mounted) {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Turno aggiornato!'), duration: Duration(seconds: 2)));
             setState(() => _isEditing = false);
          } else if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante l\'aggiornamento.'), backgroundColor: theme.colorScheme.error));
          }
        });
    }
  }

  @override
  Widget build(BuildContext class_context) {
    final theme = Theme.of(context);
    return Card(
      color: _isEditing ? theme.cardColor : theme.colorScheme.primary,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(4.0)
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: _isEditing ? _buildEditingView() : _buildReadOnlyView(),
      ),
    );
  }

  Widget _buildReadOnlyView() {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(widget.tipoTurno.nomeTurno, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
      subtitle: Text('Orari: ${widget.tipoTurno.orarioInizio} - ${widget.tipoTurno.orarioFine}', style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.8))),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: Icon(Icons.edit, color: theme.colorScheme.onPrimary), onPressed: () => setState(() => _isEditing = true)),
        IconButton(
          icon: Icon(Icons.delete, color: theme.colorScheme.error),
          onPressed: () => (context.findAncestorStateOfType<_SetupScreenState>())
              ?. _confermaEliminazioneTurno(widget.tipoTurno.idTurno),
        ),
      ]),
    );
  }

  Widget _buildEditingView() {
    final theme = Theme.of(context);
    final textStyle = TextStyle(color: theme.colorScheme.onSurface);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        TextFormField(
          initialValue: widget.tipoTurno.nomeTurno,
          decoration: InputDecoration(labelText: 'Nome Turno'),
          style: textStyle,
          validator: (v) => v!.isEmpty ? 'Obbligatorio' : null,
          onSaved: (v) => _nomeTurno = v,
        ),
        SizedBox(height: 16),
        TimePickerFormField(
          labelText: 'Orario Inizio',
          initialValue: widget.tipoTurno.orarioInizio,
          onSaved: (v) => _orarioInizio = v,
        ),
        SizedBox(height: 16),
        TimePickerFormField(
          labelText: 'Orario Fine',
          initialValue: widget.tipoTurno.orarioFine,
          onSaved: (v) => _orarioFine = v,
        ),
        SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(child: Text('Annulla'), onPressed: () {
            setState(() => _isEditing = false);
          }),
          ElevatedButton(child: Text('Salva'), onPressed: _onSave),
        ]),
      ]),
    );
  }
}

class TimePickerFormField extends FormField<String> {
  TimePickerFormField({
    Key? key,
    String labelText = 'Orario',
    String? initialValue,
    FormFieldSetter<String>? onSaved,
  }) : super(
          key: key,
          onSaved: onSaved,
          initialValue: initialValue ?? '00:00',
          validator: (value) {
            if (value == null || !RegExp(r'^[0-2][0-9]:[0-5][0-9]$').hasMatch(value)) {
              return 'Orario non valido';
            }
            return null;
          },
          builder: (FormFieldState<String> state) {
            return _TimePickerField(
              state: state,
              labelText: labelText,
            );
          },
        );
}

class _TimePickerField extends StatefulWidget {
  final FormFieldState<String> state;
  final String labelText;
  const _TimePickerField({required this.state, required this.labelText});
  @override
  _TimePickerFieldState createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<_TimePickerField> {
  late TextEditingController _hourController;
  late TextEditingController _minuteController;

  @override
  void initState() {
    super.initState();
    _hourController = TextEditingController();
    _minuteController = TextEditingController();
    _parseInitialValue();
  }
  
  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TimePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.value != oldWidget.state.value) {
      _parseInitialValue();
    }
  }

  void _parseInitialValue() {
    try {
      final parts = widget.state.value!.split(':');
      _hourController.text = parts[0];
      _minuteController.text = parts[1];
    } catch (e) {
      _hourController.text = '00';
      _minuteController.text = '00';
    }
  }

  void _updateState() {
    final hours = _hourController.text.padLeft(2, '0');
    final minutes = _minuteController.text.padLeft(2, '0');
    final newValue = '$hours:$minutes';
    widget.state.didChange(newValue);
  }

  void _incrementHour() {
    int h = int.tryParse(_hourController.text) ?? 0;
    h = (h + 1) % 24;
    _hourController.text = h.toString().padLeft(2, '0');
    _updateState();
  }

  void _decrementHour() {
    int h = int.tryParse(_hourController.text) ?? 0;
    h = (h - 1 + 24) % 24;
    _hourController.text = h.toString().padLeft(2, '0');
    _updateState();
  }
  
  void _incrementMinute() {
    setState(() {
      int m = int.tryParse(_minuteController.text) ?? 0;
      int unit = m % 10;
      
      if (unit > 0 && unit < 5) {
        m = (m ~/ 10) * 10 + 5;
      } else if (unit > 5 && unit <= 9) {
        m = ((m ~/ 10) + 1) * 10;
      } else {
        m += 5;
      }

      if (m >= 60) m = 0;
      
      _minuteController.text = m.toString().padLeft(2, '0');
      _updateState();
    });
  }

  void _decrementMinute() {
    setState(() {
      int m = int.tryParse(_minuteController.text) ?? 0;
      int unit = m % 10;

      if (unit > 0 && unit < 5) {
        m = (m ~/ 10) * 10;
      } else if (unit > 5 && unit <= 9) {
        m = (m ~/ 10) * 10 + 5;
      } else {
        m -= 5;
      }

      if (m < 0) m = 55;

      _minuteController.text = m.toString().padLeft(2, '0');
      _updateState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.state.errorText,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTimeColumn(
            controller: _hourController,
            onIncrement: _incrementHour,
            onDecrement: _decrementHour,
            maxValue: 23,
          ),
          Text(':', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          _buildTimeColumn(
            controller: _minuteController,
            onIncrement: _incrementMinute,
            onDecrement: _decrementMinute,
            maxValue: 59,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn({
      required TextEditingController controller,
      required VoidCallback onIncrement,
      required VoidCallback onDecrement,
      required int maxValue
    }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_drop_up, size: 30),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
          onPressed: onIncrement,
        ),
        SizedBox(
          width: 70,
          child: TextFormField(
            controller: controller,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            decoration: InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero, counterText: ''),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
              _TimeRangeTextInputFormatter(max: maxValue),
            ],
            onChanged: (value) => _updateState(),
          ),
        ),
        IconButton(
          icon: Icon(Icons.arrow_drop_down, size: 30),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
          onPressed: onDecrement,
        ),
      ],
    );
  }
}

class _TimeRangeTextInputFormatter extends TextInputFormatter {
  final int max;
  _TimeRangeTextInputFormatter({required this.max});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final num = int.tryParse(newValue.text);
    if (num == null) return oldValue;
    if (num > max) return oldValue;
    return newValue;
  }
}