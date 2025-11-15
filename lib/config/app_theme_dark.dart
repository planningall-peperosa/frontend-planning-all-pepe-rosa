import 'package:flutter/material.dart';

// PASSO 1: Nuova palette di colori "Moderna e Fredda" 🎨
class AppColors {
  // Colori Principali
  static const Color primary = Colors.white;      // Blu-petrolio (Teal), professionale e moderno
  static const Color background = Color.fromARGB(255, 254, 212, 255);   // MODIFICATO: rosa chiarissimo per lo sfondo
  // Colori di Accento e Secondari
  static const Color secondary = Color(0xFFFFFFFF);     //  per accenti e pulsanti principali (FAB)
  
  // Colori per Superfici e Testi
  static const Color surface =  Color.fromARGB(255, 244, 181, 245);       // rosa chiaro per Card, campi di testo, etc.
  static const Color error = Color(0xFFFFFFFF);         // Rosso desaturato, standard per temi scuri
  
  // Colori "On" (per testo/icone sopra i colori principali)
  static const Color onPrimary = Colors.black;          // Testo/Icone su colore primario (bianco su teal)
  static const Color onBackground = Colors.black;       // Testo/Icone su colore di sfondo (nero)
  static const Color onSurface = Colors.black;          // Testo/Icone su superfici (nero)
  static const Color onError = Colors.black;            // Testo/Icone su colore errore (nero)
  static const Color onSecondary = Colors.black;        // Testo/Icone su colore secondario (nero)
}

// PASSO 2: Oggetto ThemeData che utilizza la nuova palette
final ThemeData appTheme = ThemeData(
  primarySwatch: null,
  brightness: Brightness.light, // MODIFICATO

  colorScheme: const ColorScheme(
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    background: AppColors.background,
    surface: AppColors.surface,
    error: AppColors.error,
    
    onPrimary: AppColors.onPrimary,
    onSecondary: AppColors.onSecondary,
    onBackground: AppColors.onBackground,
    onSurface: AppColors.onSurface,
    onError: AppColors.onError,

    brightness: Brightness.light, // MODIFICATO
  ),

  // AppBar
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.onBackground,
    elevation: 0,
    centerTitle: true,
  ),

  // Scaffold
  scaffoldBackgroundColor: AppColors.background,




  // --- MODIFICA CHIAVE QUI ---
  // Il colore della card ora usa il colore 'surface' (grigio chiaro).
  cardTheme: CardThemeData(
    color: AppColors.surface, // MODIFICATO
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
  ),
  // --- FINE MODIFICA ---


  // Icone
  iconTheme: const IconThemeData(
    color: AppColors.onSurface,
    size: 24,
  ),

  // Testi
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.onBackground),
    displayMedium: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: AppColors.onBackground),
    displaySmall: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.onBackground),

    headlineMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onBackground),
    headlineSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onBackground),

    titleLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onBackground),

    bodyLarge: TextStyle(fontSize: 13, color: AppColors.onSurface),
    bodyMedium: TextStyle(fontSize: 11, color: AppColors.onSurface),
    bodySmall: TextStyle(fontSize: 10, color: AppColors.onSurface),

    labelLarge: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onPrimary),
    labelMedium: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.onPrimary),
    labelSmall: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.onPrimary),
  ),

  // Input (TextField, ecc.)
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    hintStyle: const TextStyle(color: AppColors.onSurface),
    labelStyle: const TextStyle(color: AppColors.onSurface),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppColors.onSurface.withOpacity(0.2)),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.onPrimary, width: 1.5),
      borderRadius: BorderRadius.circular(8),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.error),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      borderRadius: BorderRadius.circular(8),
    ),
  ),

  // FloatingActionButton (se usato)
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
  ),

  // Chip
  chipTheme: const ChipThemeData(
    backgroundColor: AppColors.surface,
    disabledColor: AppColors.surface,
    selectedColor: AppColors.primary,
    secondarySelectedColor: AppColors.secondary,
    labelStyle: TextStyle(color: AppColors.onSurface),
    secondaryLabelStyle: TextStyle(color: AppColors.onSecondary),
    brightness: Brightness.light, // MODIFICATO
  ),

  // Selezione (ListTile ecc.)
  listTileTheme: const ListTileThemeData(
    iconColor: AppColors.onSurface,
    textColor: AppColors.onSurface,
    titleTextStyle: TextStyle(color: AppColors.onSurface),     // forza titolo nero
    subtitleTextStyle: TextStyle(color: AppColors.onSurface),  // forza sottotitolo/placeholder nero
  ),
  
  dividerTheme: DividerThemeData(
    color: AppColors.onSurface.withOpacity(0.2),
    thickness: 1,
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  ),

  // Outlined/Text buttons: testo e icone neri (es. telefono/mail)
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.onSurface,
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.onSurface,
    ),
  ),

  // SnackBar rosa con testo nero + floating e bordo arrotondato
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFFFFC0CB),
    contentTextStyle: TextStyle(color: Colors.black),
    actionTextColor: Colors.black,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),

  // RadioButton: pallino sempre visibile (nero)
  radioTheme: const RadioThemeData(
    fillColor: MaterialStatePropertyAll(Colors.black),
  ),
);
