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

  // --- NUOVA VARIABILE DI STATO ---
  // Tiene traccia se i dati sono stati modificati dall'utente
  bool _isModified = false;

  @override
  void initState() {
    super.initState();
    _ragioneSocialeController = TextEditingController(text: widget.contatto.ragioneSociale);
    _referenteController = TextEditingController(text: widget.contatto.referente);
    _telefonoController = TextEditingController(text: widget.contatto.telefono01);
    _emailController = TextEditingController(text: widget.contatto.mail);

    // --- MODIFICA CHIAVE: Aggiungiamo i listener ---
    // Questi "ascoltatori" chiamano la funzione _checkForChanges ogni volta
    // che l'utente scrive qualcosa in uno dei campi.
    _ragioneSocialeController.addListener(_checkForChanges);
    _referenteController.addListener(_checkForChanges);
    _telefonoController.addListener(_checkForChanges);
    _emailController.addListener(_checkForChanges);
  }

  @override
  void dispose() {
    // Rimuoviamo i listener per pulire la memoria
    _ragioneSocialeController.removeListener(_checkForChanges);
    _referenteController.removeListener(_checkForChanges);
    _telefonoController.removeListener(_checkForChanges);
    _emailController.removeListener(_checkForChanges);
    
    _ragioneSocialeController.dispose();
    _referenteController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // --- NUOVA FUNZIONE ---
  // Controlla se il testo attuale nei campi è diverso da quello originale.
  void _checkForChanges() {
    final hasChanged = 
      (_ragioneSocialeController.text != (widget.contatto.ragioneSociale ?? '')) ||
      (_referenteController.text != (widget.contatto.referente ?? '')) ||
      (_telefonoController.text != (widget.contatto.telefono01 ?? '')) ||
      (_emailController.text != (widget.contatto.mail ?? ''));
    
    // Aggiorniamo lo stato (e quindi la UI) solo se necessario, per ottimizzare.
    if (hasChanged != _isModified) {
      setState(() {
        _isModified = hasChanged;
      });
    }
  }

  Future<void> _salvaModifiche() async {
    if (!_formKey.currentState!.validate()) return;
    
    final provider = Provider.of<ClientiProvider>(context, listen: false);
    
    final data = {
      "tipo": widget.contatto.tipo,
      "ragione_sociale": _ragioneSocialeController.text,
      "referente": _referenteController.text,
      "telefono_01": _telefonoController.text,
      "mail": _emailController.text,
      "ruolo": widget.contatto.ruolo,
    };

    final contattoAggiornato = await provider.aggiornaContatto(
    widget.contatto.idCliente, 
    widget.contatto.tipo, // <-- ARGOMENTO MANCANTE AGGIUNTO QUI
    data
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
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email (Opzionale)'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      // --- MODIFICA CHIAVE: Il pulsante è abilitato solo se _isModified è true ---
                      onPressed: _isModified ? _salvaModifiche : null,
                      child: const Text('Salva Modifiche'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  ],
                ),
              ),
            ),
        );
      },
    );
  }
}