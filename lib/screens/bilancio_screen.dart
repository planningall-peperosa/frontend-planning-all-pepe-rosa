// lib/screens/bilancio_screen.dart 

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/bilancio_models.dart';
import '../providers/bilancio_provider.dart';
import '../repositories/bilancio_repository.dart';

// 🔑 IMPORT NECESSARIO PER LA NAVIGAZIONE
import 'crea_preventivo_screen.dart';

// Colori di base
const Color kIncomeColor = Color(0xFF00C853); // Green A700
const Color kExpenseColor = Color(0xFFD50000); // Red A700
const Color kBalanceColor = Color(0xFF0091EA); // Blue A700


class BilancioScreen extends ConsumerWidget { 
  const BilancioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) { 
    final bilancioState = ref.watch(bilancioProvider);
    final repo = ref.watch(bilancioRepositoryProvider);
    
    final netBalance = bilancioState.entrate - bilancioState.totaleSpese;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Modulo Bilancio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showAddExpenseDialog(context, ref, repo),
            tooltip: 'Aggiungi Spesa',
          ),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            onPressed: () => _showManageCategoriesDialog(context, ref, repo),
            tooltip: 'Gestisci Categorie',
          ),
        ],
      ),
      body: Column(
        children: [
          // Sezione Selettore Periodo
          _buildPeriodSelector(context, ref, bilancioState),
          
          // Sezione Riepilogo Generale
          _buildSummaryCards(context, bilancioState, netBalance, repo),

          // 🔑 MODIFICA CHIAVE: Rimosso l'Expanded con l'elenco delle spese
          const Spacer(),
          const Center(child: Text('Dati visualizzati nel periodo selezionato.')),
          const Spacer(),
        ],
      ),
    );
  }

  // --- WIDGETS INTERNI (omissis) ---

  Widget _buildPeriodSelector(BuildContext context, WidgetRef ref, BilancioState state) { 
    final dateFormat = DateFormat('dd/MM/yyyy');
    
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildDateButton(
            context,
            'Dal:',
            state.startDate,
            (date) => ref.read(bilancioProvider.notifier).updatePeriod(date, state.endDate),
          ),
          _buildDateButton(
            context,
            'Al:',
            state.endDate,
            (date) => ref.read(bilancioProvider.notifier).updatePeriod(state.startDate, date),
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton(BuildContext context, String label, DateTime date, ValueChanged<DateTime> onChanged) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        // 🔑 MODIFICA CHIAVE: Container per lo sfondo bianco e il bordo
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.grey.shade400),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
              ),
            ],
          ),
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero, // Rimuove padding minimo
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              final selectedDate = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (selectedDate != null) {
                onChanged(selectedDate);
              }
            },
            child: Text(
              dateFormat.format(date),
              style: const TextStyle(
                fontSize: 16,
                // 🔑 Mantieni il colore del testo scuro
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildSummaryCards(BuildContext context, BilancioState state, double netBalance, BilancioRepository repo) {
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');

    return Card(
      margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🔑 1. RIGA ENTRATE (Naviga al dettaglio preventivi)
            GestureDetector(
              onTap: state.entrate > 0 ? () => _showEntrateDetailsDialog(context, state) : null,
              child: _buildSummaryRow('Entrate Totali', state.entrate, kIncomeColor, currencyFormat),
            ),
            const Divider(),
            
            // 🔑 2. RIGA SPESE (Naviga al dettaglio spese)
            GestureDetector(
              onTap: state.totaleSpese > 0 ? () => _showSpeseDetailsDialog(context, state, repo) : null,
              child: _buildSummaryRow('Spese Totali', state.totaleSpese, kExpenseColor, currencyFormat),
            ),
            
            const Divider(thickness: 2),
            _buildSummaryRow('Bilancio Netto', netBalance, netBalance >= 0 ? kIncomeColor : kExpenseColor, currencyFormat, isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, Color color, NumberFormat formatter, {bool isBold = false}) {
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 16 : 14,
          )),
          Text(formatter.format(value), style: TextStyle(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: isBold ? 16 : 14,
          )),
        ],
      ),
    );
  }

  // --- MODIFICATO: Dettagli Spese con icona cestino, senza chiudere il dialog ---
  void _showSpeseDetailsDialog(BuildContext context, BilancioState state, BilancioRepository repo) {
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    final dateFormat = DateFormat('dd/MM/yyyy');

    // Copia locale per aggiornare la lista senza chiudere il dialog
    final List<SpesaRegistrata> speseList = List<SpesaRegistrata>.from(state.spese);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Dettaglio Spese Registrate'),
              content: SizedBox(
                width: double.maxFinite,
                child: speseList.isEmpty
                    ? const Center(child: Text('Nessuna spesa nel periodo selezionato.'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: speseList.length,
                        itemBuilder: (context, index) {
                          final spesa = speseList[index];
                          
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.arrow_downward, color: kExpenseColor),
                              title: Text(spesa.descrizione),
                              subtitle: Text('Categoria: ${spesa.categoria} - ${dateFormat.format(spesa.data.toDate())}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currencyFormat.format(spesa.importo),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: kExpenseColor),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Elimina',
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () async {
                                      final conferma = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Conferma Eliminazione'),
                                          content: Text('Eliminare la spesa "${spesa.descrizione}" da ${currencyFormat.format(spesa.importo)}?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(false),
                                              child: const Text('Annulla'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              onPressed: () => Navigator.of(ctx).pop(true),
                                              child: const Text('Elimina', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (conferma == true) {
                                        await repo.deleteSpesa(spesa.id);
                                        // Aggiorna la lista locale e resta nel dialog
                                        setState(() {
                                          speseList.removeAt(index);
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Spesa eliminata.')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Chiudi'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  // --- DIALOGO Dettagli Entrate ---
  void _showEntrateDetailsDialog(BuildContext context, BilancioState state) {
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    final dateFormat = DateFormat('dd/MM/yyyy');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dettaglio Entrate (Preventivi)'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: state.preventiviDetails.length,
              itemBuilder: (context, index) {
                final detail = state.preventiviDetails[index];
                final totale = detail['totale_conteggiato'] as double;
                final preventivoId = detail['id'] as String;
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(detail['nome_evento'] as String),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cliente: ${detail['cliente_nome']}'),
                        Text('Data Evento: ${dateFormat.format(detail['data_evento'] as DateTime)}'),
                        // La riga dello sconto è stata rimossa
                      ],
                    ),
                    trailing: Text(
                      currencyFormat.format(totale),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: kIncomeColor),
                    ),
                    onTap: () {
                       Navigator.of(context).pop(); // Chiude il modale
                       Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => CreaPreventivoScreen(preventivoId: preventivoId), 
                          ),
                       );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }


  void _showAddExpenseDialog(BuildContext context, WidgetRef ref, BilancioRepository repo) { 
    final notifier = ref.read(bilancioProvider.notifier);
    
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<SpesaCategoria>>(
          future: notifier.fetchCategoriesForDialog(), 
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Errore'),
                content: Text('Impossibile caricare le categorie: ${snapshot.error}'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Chiudi')),
                ],
              );
            }

            final categories = snapshot.data ?? [];
            final categoriesNames = categories.map((c) => c.nome).toList();
            
            DateTime date = DateTime.now();
            String? selectedCategoryName = categories.isNotEmpty ? categories.first.nome : null;
            final amountController = TextEditingController();
            final descriptionController = TextEditingController();
            final newCategoryController = TextEditingController(); 
            final formKey = GlobalKey<FormState>();
            
            bool isNewCategoryMode = categories.isEmpty;

            return StatefulBuilder(
              builder: (context, setState) {
                const String addNewOption = '__ADD_NEW_CATEGORY__';

                List<DropdownMenuItem<String>> dropdownItems = categoriesNames.map((name) => DropdownMenuItem(
                  value: name,
                  child: Text(name),
                )).toList();
                
                dropdownItems.add(const DropdownMenuItem(
                  value: addNewOption,
                  child: Text('➕ Aggiungi Nuova Categoria', style: TextStyle(fontStyle: FontStyle.italic)),
                ));

                return AlertDialog(
                  insetPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 24.0), // ✅ più spazio utile
                  title: const Text('Nuova Spesa'),
                  content: ConstrainedBox( // ✅ limita la larghezza massima del dialog
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Importo (€)'),
                              validator: (val) => val == null || double.tryParse(val) == null ? 'Inserisci un importo valido.' : null,
                            ),
                            TextFormField(
                              controller: descriptionController,
                              decoration: const InputDecoration(labelText: 'Descrizione'),
                              validator: (val) => val == null || val.isEmpty ? 'Campo obbligatorio.' : null,
                            ),

                            if (!isNewCategoryMode)
                              DropdownButtonFormField<String>(
                                value: selectedCategoryName,
                                isExpanded: true, // ✅ evita overflow del campo a discesa
                                decoration: const InputDecoration(labelText: 'Categoria Esistente'),
                                items: dropdownItems,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == addNewOption) {
                                      isNewCategoryMode = true;
                                      selectedCategoryName = null;
                                    } else {
                                      selectedCategoryName = value;
                                    }
                                  });
                                },
                                validator: (val) => (val == null && !isNewCategoryMode) ? 'Seleziona una categoria.' : null,
                              ),

                            if (isNewCategoryMode)
                              Padding(
                                padding: EdgeInsets.only(top: isNewCategoryMode ? 16.0 : 0.0),
                                child: TextFormField(
                                  controller: newCategoryController,
                                  decoration: InputDecoration(
                                    labelText: 'Nome Nuova Categoria',
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: categories.isNotEmpty ? () {
                                        setState(() {
                                          isNewCategoryMode = false;
                                          selectedCategoryName = categories.first.nome;
                                          newCategoryController.clear();
                                        });
                                      } : null,
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Inserisci un nome.' : null,
                                ),
                              ),

                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                              title: const Text('Data Spesa'),
                              subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () async {
                                final newDate = await showDatePicker(
                                  context: context,
                                  initialDate: date,
                                  firstDate: DateTime(2020),
                                  // ⬇️ consentite spese future
                                  lastDate: DateTime(2100),
                                );
                                if (newDate != null) setState(() => date = newDate);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),

                    ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          String finalCategoryName = selectedCategoryName ?? '';

                          if (isNewCategoryMode) {
                            finalCategoryName = newCategoryController.text.trim();
                            await repo.addCategoria(finalCategoryName);
                          }

                          if (finalCategoryName.isNotEmpty) {
                            await repo.addSpesa(
                              data: date,
                              importo: double.parse(amountController.text.replaceAll(',', '.')),
                              descrizione: descriptionController.text,
                              categoria: finalCategoryName,
                            );
                            notifier.refreshBilancioData();
                            Navigator.of(context).pop();
                          }
                        }
                      },
                      child: Text(isNewCategoryMode ? 'Crea e Salva' : 'Salva Spesa'),
                    ),
                  ],
                );

              },
            );
          },
        );
      },
    );
  }

  // --- DIALOGO Gestisci Categorie (FIX SPINNER) ---
  void _showManageCategoriesDialog(BuildContext context, WidgetRef ref, BilancioRepository repo) { 
    final notifier = ref.read(bilancioProvider.notifier);
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<SpesaCategoria>>(
          future: notifier.fetchCategoriesForDialog(), // Nuova funzione Future
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final categories = snapshot.data ?? [];
            
            return AlertDialog(
              title: const Text('Gestisci Categorie Spesa'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Lista Categorie
                  SizedBox(
                    height: 200,
                    width: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return ListTile(
                          title: Text(category.nome),
                          // 🔑 IMPLEMENTAZIONE CHIAVE: Pulsanti Modifica/Elimina
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _showEditCategoryDialog(context, ref, repo, category);
                                },
                                tooltip: 'Modifica',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.red),
                                onPressed: () {
                                  // Naviga al dialogo di conferma cancellazione
                                  Navigator.of(context).pop();
                                  _showDeleteCategoryConfirmDialog(context, ref, repo, category);
                                },
                                tooltip: 'Elimina',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  // Aggiungi nuova Categoria
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: const InputDecoration(labelText: 'Nuova categoria'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: kIncomeColor),
                          onPressed: () async {
                            if (controller.text.isNotEmpty) {
                              await repo.addCategoria(controller.text);
                              controller.clear();
                              // 🔑 Ricarica il dialogo forzando un aggiornamento
                              Navigator.of(context).pop();
                              // Riapre il dialogo subito dopo aver salvato
                              _showManageCategoriesDialog(context, ref, repo);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Chiudi')),
              ],
            );
          },
        );
      },
    );
  }

  // 🔑 NUOVO DIALOGO: Modifica Categoria
  void _showEditCategoryDialog(BuildContext context, WidgetRef ref, BilancioRepository repo, SpesaCategoria category) {
    final controller = TextEditingController(text: category.nome);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Modifica Categoria'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: 'Nuovo nome per "${category.nome}"'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showManageCategoriesDialog(context, ref, repo); // Ritorna al dialogo principale
              },
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nuovoNome = controller.text.trim();
                if (nuovoNome.isNotEmpty && nuovoNome != category.nome) {
                  await repo.updateCategoria(category.id, nuovoNome);
                  Navigator.of(context).pop();
                  _showManageCategoriesDialog(context, ref, repo); // Ritorna al dialogo aggiornato
                } else {
                  Navigator.of(context).pop();
                  _showManageCategoriesDialog(context, ref, repo);
                }
              },
              child: const Text('Salva Modifica'),
            ),
          ],
        );
      },
    );
  }

  // 🔑 NUOVO DIALOGO: Conferma Cancellazione
  void _showDeleteCategoryConfirmDialog(BuildContext context, WidgetRef ref, BilancioRepository repo, SpesaCategoria category) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Conferma Eliminazione'),
          content: Text('Sei sicuro di voler eliminare la categoria "${category.nome}"? Tutte le spese associate POTREBBERO diventare non categorizzate.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showManageCategoriesDialog(context, ref, repo); // Ritorna al dialogo principale
              },
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await repo.deleteCategoria(category.id);
                Navigator.of(context).pop();
                _showManageCategoriesDialog(context, ref, repo); // Ritorna al dialogo aggiornato
              },
              child: const Text('Elimina', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
