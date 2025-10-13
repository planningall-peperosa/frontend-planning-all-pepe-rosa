// lib/screens/crea_contatto_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart'; // Assicurati che il path sia corretto
import '../providers/clienti_provider.dart';

class CreaContattoScreen extends StatefulWidget {
  final String tipoContatto;
  const CreaContattoScreen({super.key, required this.tipoContatto});

  @override
  State<CreaContattoScreen> createState() => _CreaContattoScreenState();
}

class _CreaContattoScreenState extends State<CreaContattoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ragioneSocialeController = TextEditingController();
  final _referenteController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  
  String? _ruoloSelezionato;

  @override
  void initState() {
    super.initState();
    if (widget.tipoContatto == 'fornitore') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Provider.of<ClientiProvider>(context, listen: false).caricaRuoliServizi();
      });
    }
  }

  @override
  void dispose() {
    _ragioneSocialeController.dispose();
    _referenteController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _salvaContatto() async {
    if (!_formKey.currentState!.validate()) return;
    
    final provider = Provider.of<ClientiProvider>(context, listen: false);
    
    final data = {
      "tipo": widget.tipoContatto,
      "ragione_sociale": _ragioneSocialeController.text,
      "referente": _referenteController.text,
      "telefono_01": _telefonoController.text,
      "mail": _emailController.text,
      "ruolo": _ruoloSelezionato,
    };
    
    final nuovoContatto = await provider.creaNuovoContatto(data);

    if (mounted) {
      if (nuovoContatto != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.tipoContatto.capitalize()} salvato con successo!'), backgroundColor: Colors.green)
        );
        Navigator.of(context).pop(nuovoContatto);
      } else {
        // --- MODIFICA CHIAVE ---
        // Usiamo il getter corretto 'error' invece di 'operationError'
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Errore nel salvataggio.'), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _mostraDialogSelezioneRuolo() async {
    final provider = Provider.of<ClientiProvider>(context, listen: false);
    
    await showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Seleziona Ruolo'),
          children: provider.ruoliServizi.map((ruolo) {
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Nuovo ${widget.tipoContatto.capitalize()}'),
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
              ],
              const SizedBox(height: 32),
              Consumer<ClientiProvider>(
                builder: (context, provider, child) {
                  // --- MODIFICA CHIAVE ---
                  // Usiamo il getter corretto 'isLoading' invece di 'isOperating'
                  return ElevatedButton(
                    onPressed: provider.isLoading ? null : _salvaContatto,
                    child: provider.isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white)) 
                        : const Text('Salva Contatto'),
                  );
                },
              )
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