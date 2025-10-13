// lib/screens/gestione_preventivi_menu_screen.dart
import 'package:flutter/material.dart';
import 'crea_preventivo_screen.dart';
import 'archivio_preventivi_screen.dart';
import 'cerca_cliente_screen.dart'; // <-- NUOVA IMPORTAZIONE

class GestionePreventiviMenuScreen extends StatelessWidget {
  const GestionePreventiviMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // --- MODIFICA 1: Titolo aggiornato ---
        title: const Text('Gestione Preventivi e Clienti'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMenuItem(
              context,
              icon: Icons.note_add_outlined,
              title: 'Nuovo Preventivo',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreaPreventivoScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
            _buildMenuItem(
              context,
              icon: Icons.archive_outlined, // Coerenza icona
              title: 'Archivio Preventivi',
              onTap: () {
                // Navigazione IMMEDIATA: il refresh versione avverrà in background nella schermata Archivio
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ArchivioPreventiviScreen()),
                );
              },
            ),
            const SizedBox(height: 24),

            // --- MODIFICA 2: Pulsante gestione contatti ---
            _buildMenuItem(
              context,
              icon: Icons.people_alt_outlined,
              title: 'Gestione Contatti',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CercaClienteScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 4,
      ),
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
