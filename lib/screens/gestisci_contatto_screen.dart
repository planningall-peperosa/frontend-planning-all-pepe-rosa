// lib/screens/gestisci_contatto_screen.dart (Rinomina il file se necessario, altrimenti
// lo chiamiamo CreaContattoScreen, ma il codice riflette il supporto alla modifica)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // Import per usare il Provider nell'Update
import '../models/cliente.dart';
import '../providers/clienti_provider.dart'; // Import per la logica di aggiornamento

class GestisciContattoScreen extends StatefulWidget {
  final String tipoContatto;
  final Cliente? contattoDaModificare; // Campo opzionale per la MODIFICA

  const GestisciContattoScreen({
    super.key,
    required this.tipoContatto,
    this.contattoDaModificare, // Aggiungi il parametro
  });

  @override
  State<GestisciContattoScreen> createState() => _GestisciContattoScreenState();
}

class _GestisciContattoScreenState extends State<GestisciContattoScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controller
  final _ragioneSocialeController = TextEditingController();
  final _referenteController = TextEditingController();
  final _telefono1Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _telefono2Controller = TextEditingController();
  final _prezzoController = TextEditingController();

  String? _ruoloSelezionato;
  bool _isLoading = false;

  bool get _isModifica => widget.contattoDaModificare != null;

  @override
  void initState() {
    super.initState();
    // 1. POPOLAMENTO CAMPI in caso di MODIFICA
    if (_isModifica) {
      final c = widget.contattoDaModificare!;
      _ragioneSocialeController.text = c.ragioneSociale ?? '';
      _referenteController.text = c.referente ?? '';
      _telefono1Controller.text = c.telefono01 ?? '';
      _emailController.text = c.mail ?? '';
      _telefono2Controller.text = c.telefono02 ?? '';
      _ruoloSelezionato = c.ruolo;
      _prezzoController.text = (c.prezzo ?? 0.0).toString(); // Converti double in stringa
    }
  }

  @override
  void dispose() {
    _ragioneSocialeController.dispose();
    _referenteController.dispose();
    _telefono1Controller.dispose();
    _emailController.dispose();
    _telefono2Controller.dispose();
    _prezzoController.dispose();
    super.dispose();
  }



  Future<void> _salvaContatto() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;
    
    setState(() => _isLoading = true);
    final provider = Provider.of<ClientiProvider>(context, listen: false);

    bool dbSuccess = false; 
    Map<String, dynamic> dataToSave = {}; 
    String? finalErrorMessage; 

    try {
      final String ragioneSociale = _ragioneSocialeController.text.trim();
      final String telefono01 = _telefono1Controller.text.trim();
      final double? prezzoVal = double.tryParse(_prezzoController.text.trim());
      
      // 🚨 LOGICA DI CONTROLLO DUPLICATI 🚨
      if (!_isModifica) {
        final List<Cliente> duplicati = await provider.checkDuplicateContact(
            ragioneSociale: ragioneSociale,
            telefono01: telefono01,
            // currentContactId non è necessario in modalità creazione
        );

        if (duplicati.isNotEmpty) {
          final bool continua = await _mostraAvvisoDuplicato(duplicati);
          if (!continua) {
            // L'utente ha interrotto il salvataggio per aggiornare i dati
            return;
          }
        }
      }

      // 1. Costruisci l'oggetto Cliente (temporaneo)
      final Cliente contatto = Cliente(
        idCliente: _isModifica ? widget.contattoDaModificare!.idCliente : '', 
        tipo: widget.tipoContatto,
        ragioneSociale: ragioneSociale,
        referente: _referenteController.text.trim(),
        telefono01: telefono01,
        telefono02: _telefono2Controller.text.trim().isNotEmpty ? _telefono2Controller.text.trim() : null,
        mail: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        ruolo: _ruoloSelezionato,
        prezzo: (widget.tipoContatto == 'fornitore' && prezzoVal != null) ? prezzoVal : null,
      );

      dataToSave = contatto.toJson(); 

      if (_isModifica) {
        // --- LOGICA AGGIORNAMENTO (Update) ---
        final aggiornato = await provider.aggiornaContatto(
          contatto.idCliente, 
          contatto.tipo, 
          dataToSave,
        );
        if (aggiornato == null) {
            throw Exception(provider.error ?? "Aggiornamento fallito dal Provider.");
        }
      } else {
        // --- LOGICA CREAZIONE (Add) ---
        final String collectionName = widget.tipoContatto == 'cliente' ? 'clienti' : 'fornitori';
        await FirebaseFirestore.instance.collection(collectionName).add(dataToSave);
      }
      
      dbSuccess = true; 

    } catch (e) {
      print('ERRORE DB: Impossibile ${ _isModifica ? 'aggiornare' : 'salvare'} il contatto: $e');
      finalErrorMessage = 'Errore nel database: Riprova.';
      
    } finally {
      if (mounted) {
        setState(() => _isLoading = false); 
      }
    }

    // 4. LOGICA DI RISULTATO (Eseguita solo se il widget è ancora montato)
    if (mounted) {
      if (dbSuccess) {
        final action = _isModifica ? 'aggiornato' : 'salvato';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.tipoContatto.capitalize()} $action con successo!'), backgroundColor: Colors.green)
        );

      } else if (finalErrorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(finalErrorMessage), backgroundColor: Colors.red)
        );
      }
    }
  } 
  

  Future<bool> _mostraAvvisoDuplicato(List<Cliente> duplicati) async {
    final Map<String, int> conteggi = {};
    for (final c in duplicati) {
        final key = c.tipo == 'cliente' ? 'Cliente' : 'Fornitore';
        conteggi[key] = (conteggi[key] ?? 0) + 1;
    }

    final String message = conteggi.entries.map((e) => "${e.value} ${e.key}").join(' e ');
    final String dettaglio = duplicati.map((c) {
        final tipo = c.tipo == 'cliente' ? 'Cliente' : 'Fornitore';
        final nome = c.ragioneSociale ?? 'N/A';
        return '$tipo: $nome (Tel: ${c.telefono01 ?? 'N/A'})';
    }).join('\n');
    
    return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
            title: const Text('ATTENZIONE: Contatto Esistente!'),
            content: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text('Sono stati trovati $message con nome o telefono simile.', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        const Text('Dettagli trovati:', style: TextStyle(fontStyle: FontStyle.italic)),
                        Text(dettaglio),
                        const SizedBox(height: 15),
                        const Text('Vuoi salvare comunque o interrompere per aggiornare il contatto?',
                            style: TextStyle(color: Colors.red)),
                    ],
                ),
            ),
            actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Annulla', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Salva comunque'),
                ),
            ],
        ),
    ) ?? false;
  }





  
  // Questa funzione resta identica, ma dovrebbe usare i ruoli dal Provider in futuro
  Future<void> _mostraDialogSelezioneRuolo() async {
    // Per ora usiamo i ruoli hardcoded, in futuro potremmo usare provider.ruoliServizi
    final ruoliServizi = Provider.of<ClientiProvider>(context, listen: false).ruoliServizi;
    
    await showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Seleziona Ruolo'),
          children: ruoliServizi.map((ruolo) {
            return SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _ruoloSelezionato = ruolo;
                });
                Navigator.of(context).pop();
              },
              child: Text(ruolo),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String action = _isModifica ? 'Modifica' : 'Nuovo';
    final String title = '$action ${widget.tipoContatto.capitalize()}';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _ragioneSocialeController,
                decoration: const InputDecoration(labelText: 'Ragione Sociale / Nome e Cognome *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Campo obbligatorio' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenteController,
                decoration: const InputDecoration(labelText: 'Referente (Opzionale)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefono1Controller,
                decoration: const InputDecoration(labelText: 'Telefono Principale *'),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty) ? 'Campo obbligatorio' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefono2Controller,
                decoration: const InputDecoration(labelText: 'Telefono Secondario (Opzionale)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email (Opzionale)'),
                keyboardType: TextInputType.emailAddress,
              ),
              
              // CAMPI SPECIFICI PER FORNITORE
              if (widget.tipoContatto == 'fornitore') ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _mostraDialogSelezioneRuolo,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ruolo / Servizio Offerto',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _ruoloSelezionato ?? 'Nessun ruolo selezionato',
                      style: TextStyle(
                        fontSize: 16,
                        color: _ruoloSelezionato == null ? Colors.grey.shade600 : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // CAMPO PREZZO
                TextFormField(
                  controller: _prezzoController,
                  decoration: const InputDecoration(labelText: 'Prezzo Base (€) (Opzionale)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.]?\d*')),
                  ],
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Pulsante di Salvataggio aggiornato
              ElevatedButton(
                onPressed: _isLoading ? null : _salvaContatto,
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                    : Text(_isModifica ? 'Aggiorna Contatto' : 'Salva Contatto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension StringExtension on String {
    String capitalize() {
      if (isEmpty) return this;
      return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
    }
}