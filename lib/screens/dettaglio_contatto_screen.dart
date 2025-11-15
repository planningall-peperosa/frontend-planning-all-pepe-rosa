// lib/screens/dettaglio_contatto_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../providers/clienti_provider.dart';

class DettaglioContattoScreen extends StatefulWidget {
  final Cliente contatto;

  const DettaglioContattoScreen({super.key, required this.contatto});

  @override
  State<DettaglioContattoScreen> createState() => _DettaglioContattoScreenState();
}

class _DettaglioContattoScreenState extends State<DettaglioContattoScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ragioneSocialeController;
  late TextEditingController _referenteController;
  late TextEditingController _telefonoController;
  late TextEditingController _emailController;

  // 🔹 AGGIUNTE: campi editabili richiesti
  late TextEditingController _telefonoSecondarioController; // telefono_02
  late TextEditingController _prezzoController;             // prezzo (fornitore)
  String? _ruoloSelezionato;                                // ruolo (fornitore)

  // Tiene traccia se i dati sono stati modificati dall'utente
  bool _isModified = false;

  bool get _isFornitore => widget.contatto.tipo == 'fornitore';

  @override
  void initState() {
    super.initState();
    _ragioneSocialeController = TextEditingController(text: widget.contatto.ragioneSociale);
    _referenteController = TextEditingController(text: widget.contatto.referente);
    _telefonoController = TextEditingController(text: widget.contatto.telefono01);
    _emailController = TextEditingController(text: widget.contatto.mail);

    // 🔹 INIT aggiunte
    _telefonoSecondarioController = TextEditingController(text: widget.contatto.telefono02 ?? '');
    _ruoloSelezionato = widget.contatto.ruolo;
    _prezzoController = TextEditingController(
      text: widget.contatto.prezzo != null ? widget.contatto.prezzo!.toString() : '',
    );

    // Listener per il check modifiche
    _ragioneSocialeController.addListener(_checkForChanges);
    _referenteController.addListener(_checkForChanges);
    _telefonoController.addListener(_checkForChanges);
    _emailController.addListener(_checkForChanges);

    // 🔹 Listener anche per i nuovi campi
    _telefonoSecondarioController.addListener(_checkForChanges);
    _prezzoController.addListener(_checkForChanges);
  }

  @override
  void dispose() {
    // Rimuoviamo i listener per pulire la memoria
    _ragioneSocialeController.removeListener(_checkForChanges);
    _referenteController.removeListener(_checkForChanges);
    _telefonoController.removeListener(_checkForChanges);
    _emailController.removeListener(_checkForChanges);
    _telefonoSecondarioController.removeListener(_checkForChanges);
    _prezzoController.removeListener(_checkForChanges);

    _ragioneSocialeController.dispose();
    _referenteController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _telefonoSecondarioController.dispose();
    _prezzoController.dispose();
    super.dispose();
  }

  // Controlla se il testo attuale nei campi è diverso da quello originale.
  void _checkForChanges() {
    final hasChangedBase =
        (_ragioneSocialeController.text != (widget.contatto.ragioneSociale ?? '')) ||
        (_referenteController.text != (widget.contatto.referente ?? '')) ||
        (_telefonoController.text != (widget.contatto.telefono01 ?? '')) ||
        (_emailController.text != (widget.contatto.mail ?? ''));

    final hasChangedTelefono2 =
        (_telefonoSecondarioController.text != (widget.contatto.telefono02 ?? ''));

    bool hasChangedFornitore = false;
    if (_isFornitore) {
      final prezzoOriginale = widget.contatto.prezzo != null ? widget.contatto.prezzo!.toString() : '';
      final ruoloOriginale = widget.contatto.ruolo;
      hasChangedFornitore =
          (_prezzoController.text != prezzoOriginale) ||
          (_ruoloSelezionato != ruoloOriginale);
    }

    final hasChanged = hasChangedBase || hasChangedTelefono2 || hasChangedFornitore;

    if (hasChanged != _isModified) {
      setState(() {
        _isModified = hasChanged;
      });
    }
  }

  Future<void> _salvaModifiche() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<ClientiProvider>(context, listen: false);

    // Costruzione payload aggiornamento
    final Map<String, dynamic> data = {
      "tipo": widget.contatto.tipo,
      "ragione_sociale": _ragioneSocialeController.text,
      "referente": _referenteController.text,
      "telefono_01": _telefonoController.text,
      "mail": _emailController.text,
      // 🔹 Nuovo campo sempre presente (anche per Cliente)
      "telefono_02": _telefonoSecondarioController.text.isNotEmpty ? _telefonoSecondarioController.text : null,
    };

    // 🔹 Campi specifici Fornitore
    if (_isFornitore) {
      final prezzoVal = double.tryParse(_prezzoController.text.trim());
      data["ruolo"] = _ruoloSelezionato;                 // può essere null se non impostato
      data["prezzo"] = prezzoVal != null ? prezzoVal : null; // salva null se campo vuoto/invalid
    }

    final contattoAggiornato = await provider.aggiornaContatto(
      widget.contatto.idCliente,
      widget.contatto.tipo,
      data,
    );

    if (mounted) {
      if (contattoAggiornato != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contatto aggiornato!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: ${provider.error}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _eliminaContatto() async {
    final confermato = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Eliminazione'),
        content: Text('Sei sicuro di voler eliminare ${widget.contatto.ragioneSociale}? L\'azione è irreversibile.'),
        actions: [
          TextButton(
            child: const Text('Annulla'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confermato ?? false) {
      final provider = Provider.of<ClientiProvider>(context, listen: false);
      final successo = await provider.eliminaContatto(widget.contatto.idCliente, widget.contatto.tipo);

      if (mounted) {
        if (successo) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contatto eliminato.'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore: ${provider.error}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientiProvider>(
      builder: (context, provider, child) {
        final ruoli = provider.ruoliServizi; // lista ruoli dal provider

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.contatto.ragioneSociale ?? 'Dettaglio Contatto'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: provider.isLoading ? null : _eliminaContatto,
                tooltip: 'Elimina Contatto',
              ),
            ],
          ),
          body: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _ragioneSocialeController,
                          decoration: const InputDecoration(labelText: 'Ragione Sociale / Nome e Cognome'),
                          validator: (v) => (v == null || v.isEmpty) ? 'Campo obbligatorio' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _referenteController,
                          decoration: const InputDecoration(labelText: 'Referente (Opzionale)'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _telefonoController,
                          decoration: const InputDecoration(labelText: 'Telefono Principale'),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),

                        // 🔹 Nuovo: Telefono Secondario (sempre visibile)
                        TextFormField(
                          controller: _telefonoSecondarioController,
                          decoration: const InputDecoration(labelText: 'Telefono Secondario (Opzionale)'),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email (Opzionale)'),
                          keyboardType: TextInputType.emailAddress,
                        ),

                        // 🔹 Se FORNITORE, mostriamo Ruolo e Prezzo base
                        if (_isFornitore) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _ruoloSelezionato,
                            decoration: const InputDecoration(
                              labelText: 'Ruolo / Servizio Offerto',
                              border: OutlineInputBorder(),
                            ),
                            items: ruoli
                                .map((r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _ruoloSelezionato = val;
                                _checkForChanges();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _prezzoController,
                            decoration: const InputDecoration(labelText: 'Prezzo Base (€)'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],

                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _isModified ? _salvaModifiche : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Salva Modifiche'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
