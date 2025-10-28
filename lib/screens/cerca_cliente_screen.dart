// lib/screens/cerca_cliente_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Importiamo 'rxdart' per unire gli Stream, se non l'hai ancora, dovrai aggiungerlo al pubspec.yaml:
// dependencies:
//   rxdart: ^0.27.0 (o versione compatibile)
import 'package:rxdart/rxdart.dart'; 

import '../models/cliente.dart';
// **IMPORT CORRETTO:** Usiamo GestisciContattoScreen che è il form unificato
import 'gestisci_contatto_screen.dart';
import 'dettaglio_contatto_screen.dart';

class CercaClienteScreen extends StatefulWidget {
  final bool isSelectionMode;
  const CercaClienteScreen({super.key, this.isSelectionMode = false});

  @override
  State<CercaClienteScreen> createState() => _CercaClienteScreenState();
}

class _CercaClienteScreenState extends State<CercaClienteScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      // Forziamo il rebuild ogni volta che la query di ricerca cambia
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // LOGICA CREAZIONE: Ora chiama GestisciContattoScreen
  void _apriCreaContatto(String tipo) async {
    // Nota: Ho lasciato il tipo di ritorno come Cliente? per coerenza
    final nuovoContatto = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        // CHIAMATA CORRETTA al form di gestione unificata
        builder: (context) => GestisciContattoScreen(tipoContatto: tipo), 
      ),
    );
    // Se un contatto è stato creato e tornato (non nullo)
    if (nuovoContatto != null && mounted) {
      if (widget.isSelectionMode) {
        Navigator.of(context).pop(nuovoContatto);
      } else {
        // Puliamo la ricerca per mostrare il nuovo contatto nell'elenco
        _searchController.clear(); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatti'),
        actions: [
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
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _buildResultList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList() {
    // 1. Definiamo gli Stream per le due collezioni
    final Stream<QuerySnapshot> clientiStream = 
        FirebaseFirestore.instance.collection('clienti').snapshots();
    final Stream<QuerySnapshot> fornitoriStream = 
        FirebaseFirestore.instance.collection('fornitori').snapshots();

    // 2. Uniamo i due Stream in un unico Stream di liste di QuerySnapshot
    final combinedStream = Rx.combineLatest2<QuerySnapshot, QuerySnapshot, List<Cliente>>(
      clientiStream,
      fornitoriStream,
      (clientiSnap, fornitoriSnap) {
        // Mappiamo i documenti di entrambe le snapshot in oggetti Cliente
        final List<Cliente> clienti = clientiSnap.docs.map((doc) => Cliente.fromFirestore(doc)).toList();
        final List<Cliente> fornitori = fornitoriSnap.docs.map((doc) => Cliente.fromFirestore(doc)).toList();
        
        // Uniamo le due liste
        final tuttiIContatti = [...clienti, ...fornitori];

        // Ordiniamo la lista unificata per consistenza (es. per ragione sociale)
        tuttiIContatti.sort((a, b) => (a.ragioneSociale ?? '').toLowerCase().compareTo((b.ragioneSociale ?? '').toLowerCase()));

        return tuttiIContatti;
      },
    );

    // 3. Usiamo StreamBuilder sul combinedStream
    return StreamBuilder<List<Cliente>>(
      stream: combinedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Errore: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Nessun contatto nel database.'));
        }

        final tuttiIContatti = snapshot.data!;

        final query = _searchController.text.toLowerCase();
        final contattiFiltrati = query.isEmpty
            ? tuttiIContatti
            : tuttiIContatti.where((contatto) {
                // Mantieni la logica di filtro locale che avevi già
                final ragioneSociale = (contatto.ragioneSociale ?? '').toLowerCase();
                final telefono1 = (contatto.telefono01 ?? '').toLowerCase();
                final telefono2 = (contatto.telefono02 ?? '').toLowerCase();
                
                return ragioneSociale.contains(query) ||
                       telefono1.contains(query) ||
                       telefono2.contains(query);
              }).toList();

        if (contattiFiltrati.isEmpty) {
          return const Center(child: Text('Nessun contatto trovato.'));
        }

        return ListView.builder(
          itemCount: contattiFiltrati.length,
          itemBuilder: (context, index) {
            final contatto = contattiFiltrati[index];
            
            // Aggiungi un'icona per differenziare Cliente/Fornitore
            final isCliente = contatto.tipo == 'cliente';
            final leadingIcon = isCliente ? Icons.person : Icons.factory;
            final iconColor = isCliente ? Colors.blue : Colors.orange;

            return ListTile(
              key: ValueKey(contatto.idCliente),
              leading: Icon(leadingIcon, color: iconColor),
              title: Text(contatto.ragioneSociale ?? 'Senza nome'),
              subtitle: Text(contatto.telefono01 ?? 'Nessun telefono'),
              trailing: Chip(
                // Mostra Ruolo per i fornitori
                label: Text(
                  contatto.tipo == 'fornitore'
                    ? contatto.ruolo ?? 'Fornitore'
                    : '${contatto.conteggioPreventivi} prev.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              onTap: () {
                if (widget.isSelectionMode) {
                  Navigator.of(context).pop(contatto);
                } else {
                  // Apri Dettaglio (la DettaglioContattoScreen dovrà gestire la modifica)
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
      },
    );
  }
}