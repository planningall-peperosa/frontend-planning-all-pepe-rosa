// lib/config/app_theme_dark.dart

import 'package:flutter/material.dart';

// PASSO 1: Palette di colori personalizzata estratta dal tuo codice.
// Questi sono i colori che la tua app sta attualmente utilizzando.
class AppColors {
  // Colori Principali
  static const Color primary = Color(0xFFEA80FC);      // Rosa/Viola per AppBar, Drawer, Dialoghi
  static const Color background = Color(0xFFB000B0);    // Viola scuro per lo sfondo principale e DrawerHeader
  
  // Colori di Accento e Secondari
  static const Color accentBlue = Colors.blue;          // Blu usato per le etichette dei TextField
  static const Color accentPink = Colors.pinkAccent;    // Rosa/accento definito nel ColorScheme
  
  // Colori per Superfici e Testi
  static const Color surface = Colors.white;            // Sfondo per Card, campi di testo, etc.
  static const Color error = Color(0xFFB71C1C);         // Rosso scuro per errori (ho usato un rosso standard invece di shade)
  
  // Colori "On" (per testo/icone sopra i colori principali)
  static const Color onPrimary = Color.fromARGB(255, 13, 13, 13);          // Testo/Icone su colore primario
  static const Color onBackground = Color.fromARGB(255, 0, 0, 0);       // Testo/Icone su colore di sfondo
  static const Color onSurface = Colors.black;          // Testo/Icone su superfici (es. testo nero su sfondo bianco)
  static const Color onError = Colors.white;            // Testo/Icone su colore di errore
  static const Color onAccent = Colors.white;           // Testo/Icone su colori di accento
  
  // Colori per Testi specifici e Bordi
  static const Color textGreyLabel = Color(0xFF757575); // Grigio per le etichette dei TextField (equivale a Colors.grey[600])
  static const Color textGreyHint = Color(0xFFBDBDBD);  // Grigio per gli hint (equivale a Colors.grey[500])
  static const Color border = Colors.black;
}

// PASSO 2: Oggetto ThemeData che utilizza la palette di colori definita sopra.
final ThemeData appTheme = ThemeData(
  // Impostiamo `primarySwatch` a null perché stiamo fornendo un `colorScheme` completo.
  primarySwatch: null,
  brightness: Brightness.light,

  // Lo schema di colori è il cuore del tema.
  colorScheme: const ColorScheme(
    primary: AppColors.primary,
    secondary: AppColors.accentPink,
    background: AppColors.background,
    surface: AppColors.surface,
    error: AppColors.error,
    
    onPrimary: AppColors.onPrimary,
    onSecondary: AppColors.onAccent, // Testo su colore secondario
    onBackground: AppColors.onBackground,
    onSurface: AppColors.onSurface,
    onError: AppColors.onError,
    
    brightness: Brightness.light,
  ),

  // Definizioni globali per i widget
  scaffoldBackgroundColor: AppColors.background,

  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary, // Colore per icone e testo del titolo di default
    elevation: 2.0,
    titleTextStyle: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w300,
      color: AppColors.onPrimary, // Colore specifico per il titolo
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    labelStyle: const TextStyle(color: AppColors.textGreyLabel, fontSize: 16),
    floatingLabelStyle: const TextStyle(
      color: AppColors.accentBlue, // Colore blu quando il campo ha il focus
      fontSize: 14,
    ),
    hintStyle: const TextStyle(color: AppColors.textGreyHint),
    errorStyle: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
    
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6), width: 1.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.border, width: 2.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      borderRadius: BorderRadius.circular(8.0),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.error, width: 2.5),
      borderRadius: BorderRadius.circular(8.0),
    ),
  ),
  
  textTheme: Typography.material2021(platform: TargetPlatform.android).black.copyWith(
    // Definisci qui gli stili di testo globali usando i colori del tema
    titleMedium: const TextStyle(color: AppColors.onSurface, fontSize: 14), // Testo nero su sfondi bianchi
    bodyLarge: const TextStyle(color: AppColors.onBackground, fontSize: 13), // Testo bianco su sfondi viola
    bodyMedium: const TextStyle(color: AppColors.onBackground, fontSize: 14), // Testo bianco su sfondi viola
  ),
  
  // Stili per altri widget comuni
  drawerTheme: const DrawerThemeData(
    backgroundColor: AppColors.primary,
  ),
  
  listTileTheme: const ListTileThemeData(
    iconColor: AppColors.onPrimary,
    textColor: AppColors.onPrimary,
  ),
  
  dividerTheme: DividerThemeData(
    color: AppColors.onPrimary.withOpacity(0.5),
    thickness: 1,
  ),
);