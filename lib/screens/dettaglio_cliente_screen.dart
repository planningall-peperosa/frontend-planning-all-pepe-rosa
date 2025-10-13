// lib/screens/dettaglio_cliente_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../providers/preventivi_provider.dart';

class DettaglioClienteScreen extends StatefulWidget {
  final Cliente cliente;
  const DettaglioClienteScreen({super.key, required this.cliente});

  @override
  State<DettaglioClienteScreen> createState() => _DettaglioClienteScreenState();
}

class _DettaglioClienteScreenState extends State<DettaglioClienteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Carica i preventivi associati al cliente
      Provider.of<PreventiviProvider>(context, listen: false)
          .caricaPreventiviPerCliente(widget.cliente.idCliente);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cliente.ragioneSociale ?? 'Dettaglio Contatto'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Anagrafica Cliente", style: theme.textTheme.titleLarge),
            const Divider(height: 24),
            _buildInfoRow(Icons.person, "Ragione Sociale", widget.cliente.ragioneSociale),
            _buildInfoRow(Icons.badge, "Referente", widget.cliente.referente),
            _buildInfoRow(Icons.phone, "Telefono", widget.cliente.telefono01),
            _buildInfoRow(Icons.email, "Email", widget.cliente.mail),
            const SizedBox(height: 32),

            Text("Preventivi Associati", style: theme.textTheme.titleLarge),
            const Divider(height: 24),

            Consumer<PreventiviProvider>(
              builder: (context, provider, child) {
                if (provider.isSearching) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.errorSearching != null) {
                  return Center(child: Text("Errore: ${provider.errorSearching}"));
                }
                if (provider.risultatiRicerca.isEmpty) {
                  return const Center(child: Text("Nessun preventivo trovato per questo cliente."));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: provider.risultatiRicerca.length,
                  itemBuilder: (context, index) {
                    final preventivo = provider.risultatiRicerca[index];
                    final isBozza = preventivo.status.toLowerCase() == 'bozza';

                    final nomeEvento = (preventivo.nomeEvento ?? '').trim();
                    final dataEventoStr = DateFormat('dd/MM/yyyy').format(preventivo.dataEvento);
                    final dataCreazioneStr = DateFormat('dd/MM/yyyy').format(preventivo.dataCreazione);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      // Evita usare primary come background per non perdere contrasto
                      color: isBozza ? theme.colorScheme.surface : theme.cardColor,
                      child: ListTile(
                        leading: Icon(isBozza ? Icons.edit_note : Icons.check_circle_outline),
                        title: Text(
                          nomeEvento.isNotEmpty ? nomeEvento : "Evento del $dataEventoStr",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          nomeEvento.isNotEmpty
                              ? "Evento del $dataEventoStr • Creato il $dataCreazioneStr"
                              : "Creato il $dataCreazioneStr",
                        ),
                        trailing: Chip(label: Text(preventivo.status)),
                        onTap: () {
                          // TODO: sostituisci con la tua navigazione al dettaglio preventivo
                          // es: _apriDettaglioPreventivo(preventivo);
                          // oppure Navigator.pushNamed(context, '/preventivi/dettaglio', arguments: preventivo.preventivoId);
                          // Per ora lascio un print:
                          // ignore: avoid_print
                          print("Apro preventivo ID: ${preventivo.preventivoId}");
                        },
                      ),
                    );
                  },
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600),
          const SizedBox(width: 16),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
