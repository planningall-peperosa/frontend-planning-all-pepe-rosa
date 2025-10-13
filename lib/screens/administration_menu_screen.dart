import 'package:flutter/material.dart';
import 'ore_lavorate_screen.dart'; 

class AdministrationMenuScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Accediamo al tema per usare i colori centralizzati
    final theme = Theme.of(context);

    return Scaffold(
      // MODIFICA: Colore di sfondo preso dal tema.
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        // MODIFICA: Colore di sfondo dell'AppBar preso dal tema.
        backgroundColor: theme.colorScheme.primary,
        title: Text(
          'Administration',
          style: TextStyle(
            fontSize: 36,
            // MODIFICA: Colore del testo preso dal tema.
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w400,
            letterSpacing: 1.2,
          ),
        ),
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 80,
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 36, left: 16, right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminCardButton(
              icon: Icons.access_time_rounded,
              label: 'Ore Dipendenti',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => OreLavorateScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
            _AdminCardButton(
              icon: Icons.help_outline,
              label: 'Da definire',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PlaceholderScreen(title: "Da definire"),
                  ),
                );
              },
            ),
          ],

        ),
      ),
    );
  }
}

class _AdminCardButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AdminCardButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Accediamo al tema per usare i colori centralizzati
    final theme = Theme.of(context);

    return Material(
      // MODIFICA: Colore del pulsante preso dal tema.
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 70,
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              // MODIFICA: Colore dell'icona preso dal tema (colore secondario/accento).
              Icon(icon, size: 34, color: theme.colorScheme.secondary),
              SizedBox(width: 18),
              Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  // MODIFICA: Colore del testo preso dal tema.
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({required this.title});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      // L'AppBar usa automaticamente lo stile del tema globale
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          'In costruzione',
          // MODIFICA: Il grigio hardcoded è stato sostituito con un colore
          // del tema per garantire la leggibilità sullo sfondo scuro.
          style: TextStyle(
            fontSize: 24, 
            color: theme.colorScheme.onBackground.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}