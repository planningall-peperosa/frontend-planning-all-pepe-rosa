// lib/screens/cerca_cliente_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cliente.dart';
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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('clienti').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Errore: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Nessun contatto nel database.'));
        }

        final tuttiIContatti = snapshot.data!.docs.map((doc) {
          return Cliente.fromFirestore(doc);
        }).toList();

        final query = _searchController.text.toLowerCase();
        final contattiFiltrati = query.isEmpty
            ? tuttiIContatti
            : tuttiIContatti.where((contatto) {
                // Utilizziamo i nomi corretti delle proprietà della classe Cliente
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
            return ListTile(
              key: ValueKey(contatto.idCliente),
              leading: const Icon(Icons.person),
              title: Text(contatto.ragioneSociale ?? 'Senza nome'),
              subtitle: Text(contatto.telefono01 ?? 'Nessun telefono'),
              trailing: Chip(
                label: Text('${contatto.conteggioPreventivi} prev.'),
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
      },
    );
  }
}