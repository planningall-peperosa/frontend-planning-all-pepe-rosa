import 'package:flutter/material.dart';

// PASSO 1: Nuova palette di colori "Moderna e Fredda" 🎨
class AppColors {
  // Colori Principali
  static const Color primary = Color.fromARGB(152, 20, 109, 100);      // Blu-petrolio (Teal), professionale e moderno
  static const Color background = Color(0xFF212121);    // Grigio molto scuro (quasi nero) per lo sfondo
  
  // Colori di Accento e Secondari
  static const Color secondary = Color(0xFF4DD0E1);     // Ciano brillante per accenti e pulsanti principali (FAB)
  
  // Colori per Superfici e Testi
  static const Color surface = Color(0xFF37474F);       // Grigio-blu scuro per Card, campi di testo, etc.
  static const Color error = Color(0xFFCF6679);         // Rosso desaturato, standard per temi scuri
  
  // Colori "On" (per testo/icone sopra i colori principali)
  static const Color onPrimary = Colors.white;          // Testo/Icone su colore primario (bianco su teal)
  static const Color onBackground = Colors.white;       // Testo/Icone su colore di sfondo (bianco su grigio scuro)
  static const Color onSurface = Colors.white;          // Testo/Icone su superfici (bianco su grigio-blu)
  static const Color onError = Colors.black;            // Testo/Icone su colore errore (nero su rosso)
  static const Color onSecondary = Colors.black;        // Testo/Icone su colore secondario (nero su ciano)
}

// PASSO 2: Oggetto ThemeData che utilizza la nuova palette
final ThemeData appTheme = ThemeData(
  primarySwatch: null,
  brightness: Brightness.dark,

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
    
    brightness: Brightness.dark,
  ),

  scaffoldBackgroundColor: AppColors.background,
  
  // CORREZIONE 1: Usato CardThemeData al posto di CardTheme
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    elevation: 2.0,
    titleTextStyle: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w400,
      color: AppColors.onPrimary,
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    labelStyle: TextStyle(color: AppColors.onSurface.withOpacity(0.7), fontSize: 16),
    floatingLabelStyle: const TextStyle(
      color: AppColors.secondary,
      fontSize: 14,
    ),
    hintStyle: TextStyle(color: AppColors.onSurface.withOpacity(0.5)),
    errorStyle: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
    
    // CORREZIONE 2: Rimosso 'const' perché withOpacity non è una costante di compilazione
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppColors.onSurface.withOpacity(0.3), width: 1.0),
      borderRadius: BorderRadius.circular(8.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: AppColors.secondary, width: 2.0),
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
  
  textTheme: Typography.material2021(platform: TargetPlatform.android).white.copyWith(
    bodyLarge: const TextStyle(color: AppColors.onBackground),
    bodyMedium: const TextStyle(color: AppColors.onBackground),
    titleMedium: const TextStyle(color: AppColors.onSurface, fontSize: 16),
  ),
  
  drawerTheme: const DrawerThemeData(
    backgroundColor: AppColors.background,
  ),
  
  listTileTheme: const ListTileThemeData(
    iconColor: AppColors.onSurface,
    textColor: AppColors.onSurface,
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
);