// lib/screens/cerca_cliente_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../providers/clienti_provider.dart';
import 'crea_contatto_screen.dart';
import 'dettaglio_contatto_screen.dart';

class CercaClienteScreen extends StatefulWidget {
  final bool isSelectionMode;
  const CercaClienteScreen({super.key, this.isSelectionMode = false});

  @override
  State<CercaClienteScreen> createState() => _CercaClienteScreenState();
}

class _CercaClienteScreenState extends State<CercaClienteScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ClientiProvider>(context, listen: false).clearSearch();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<ClientiProvider>(context, listen: false).cercaContatti(query);
    });
  }

  void _apriCreaContatto(String tipo) async {
    final nuovoContatto = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(builder: (context) => CreaContattoScreen(tipoContatto: tipo)),
    );
    if (nuovoContatto != null && mounted) {
      if (widget.isSelectionMode) {
        Navigator.of(context).pop(nuovoContatto);
      } else {
        _searchController.clear();
        Provider.of<ClientiProvider>(context, listen: false).clearSearch();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientiProvider = Provider.of<ClientiProvider>(context);

    return Scaffold(
      appBar: AppBar(
        // --- MODIFICA 1 ---
        title: const Text('Contatti'),
        actions: [
          // --- MODIFICA 2 ---
          // Il PopupMenuButton ora ha come "figlio" un pulsante con testo e icona
          PopupMenuButton<String>(
            onSelected: _apriCreaContatto,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'cliente',
                child: Text('Nuovo Cliente'),
              ),
              const PopupMenuItem<String>(
                value: 'fornitore',
                child: Text('Nuovo Fornitore'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: const [
                  Icon(Icons.add),
                  SizedBox(width: 4),
                  Text('Aggiungi Contatto'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Cerca per nome, cognome, telefono...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: clientiProvider.isLoading
                    ? const SizedBox(height: 10, width: 10, child: CircularProgressIndicator())
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _buildResultList(clientiProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList(ClientiProvider clientiProvider) {
    if (clientiProvider.isLoading && clientiProvider.contattiTrovati.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (clientiProvider.error != null && clientiProvider.contattiTrovati.isEmpty) {
      return Center(child: Text(clientiProvider.error!));
    }

    if (clientiProvider.contattiTrovati.isEmpty) {
      return const Center(child: Text('Nessun contatto trovato.'));
    }

    return ListView.builder(
      itemCount: clientiProvider.contattiTrovati.length,
      itemBuilder: (context, index) {
        final contatto = clientiProvider.contattiTrovati[index];
        return ListTile(
          leading: Icon(contatto.tipo == 'cliente' ? Icons.person : Icons.store),
          title: Text(contatto.ragioneSociale ?? 'Senza nome'),
          subtitle: Text(contatto.telefono01 ?? 'Nessun telefono'),
          trailing: Chip(
            label: Text('${clientiProvider.conteggiReali[contatto.idCliente] ?? contatto.conteggioPreventivi} prev.'),
          ),
          onTap: () {
            if (widget.isSelectionMode) {
              Navigator.of(context).pop(contatto);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DettaglioContattoScreen(contatto: contatto),
                ),
              );
            }
          },
        );
      },
    );
  }
}