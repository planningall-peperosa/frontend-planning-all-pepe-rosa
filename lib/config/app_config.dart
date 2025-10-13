// lib/config/app_config.dart
// VERSIONE FINALE CON CACHE DATI

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Environment { production, development }

class AppConfig {

  //static const String prodBaseUrl = "http://127.0.0.1:8000";
  
  //static const String devBaseUrl = "https://backend-planning-all-pepe-rosa.onrender.com";

  static const String devBaseUrl = "http://127.0.0.1:8000";

  static const String prodBaseUrl = "https://backend-planning-all-pepe-rosa.onrender.com";

  static const String _envPrefsKey = 'app_environment_preference_v2';
  static const String _lastDriveVersionKey = 'lastDriveVersion';
  static const String _lastDriveTimestampKey = 'lastDriveTimestamp';

  static Environment _currentEnvironment = Environment.production;
  static String _currentBaseUrl = prodBaseUrl;

  static String? _lastDriveVersion;
  static String? _lastDriveTimestamp;

  // Indica se serve mostrare la scelta ambiente (solo debug)
  static bool _needsEnvSelection = false;

  static String get currentBaseUrl => _currentBaseUrl;
  static Environment get currentEnvironment => _currentEnvironment;
  static bool get isDevelopmentEnv => _currentEnvironment == Environment.development;
  static String? get lastDriveVersion => _lastDriveVersion;
  static String? get lastDriveTimestamp => _lastDriveTimestamp;
  static bool get needsEnvSelection => _needsEnvSelection;

  static Future<void> loadEnvironment() async {
    // ignore: avoid_print
    print("[DEBUG AppConfig] Caricamento configurazioni ambiente e changelog...");
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (!kDebugMode) {
      // In release forziamo produzione, senza selezione
      _currentEnvironment = Environment.production;
      _currentBaseUrl = prodBaseUrl;
      _needsEnvSelection = false;
      _lastDriveVersion = prefs.getString(_lastDriveVersionKey);
      _lastDriveTimestamp = prefs.getString(_lastDriveTimestampKey);
      return;
    }

    try {
      final String? savedEnvName = prefs.getString(_envPrefsKey);
      if (savedEnvName != null) {
        _currentEnvironment = Environment.values.firstWhere(
          (e) => e.name == savedEnvName,
          orElse: () => Environment.production,
        );
        _currentBaseUrl =
            (_currentEnvironment == Environment.development) ? devBaseUrl : prodBaseUrl;
        _needsEnvSelection = false;
      } else {
        // Niente valore salvato: chiedi selezione PRIMA del login
        _currentEnvironment = Environment.production;
        _currentBaseUrl = prodBaseUrl;
        _needsEnvSelection = true; // trigger RootGate -> EnvSelectorScreen
      }
    } catch (e) {
      _currentEnvironment = Environment.production;
      _currentBaseUrl = prodBaseUrl;
      _needsEnvSelection = true;
    }

    _lastDriveVersion = prefs.getString(_lastDriveVersionKey);
    _lastDriveTimestamp = prefs.getString(_lastDriveTimestampKey);
    // ignore: avoid_print
    print("[DEBUG AppConfig] Ultima Drive Version caricata da disco: $_lastDriveVersion");
  }

  // --- GESTIONE AMBIENTE & CHANGELOG ---

  static Future<void> setEnvironment(BuildContext context, Environment newEnv) async {
    if (_currentEnvironment == newEnv) {
      _needsEnvSelection = false;
      return;
    }
    _currentEnvironment = newEnv;
    _currentBaseUrl = (newEnv == Environment.development) ? devBaseUrl : prodBaseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_envPrefsKey, _currentEnvironment.name);
    _needsEnvSelection = false; // scelta fatta
    await resetDriveChangelog();
  }

  static Future<void> updateDriveChangelog(String? version, String? timestamp) async {
    _lastDriveVersion = version;
    _lastDriveTimestamp = timestamp;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (version != null) {
        await prefs.setString(_lastDriveVersionKey, version);
      } else {
        await prefs.remove(_lastDriveVersionKey);
      }
      if (timestamp != null) {
        await prefs.setString(_lastDriveTimestampKey, timestamp);
      } else {
        await prefs.remove(_lastDriveTimestampKey);
      }
      // ignore: avoid_print
      print("[DEBUG AppConfig] Changelog Drive aggiornato e SALVATO SU DISCO: Version=$version");
    } catch (e) {
      // ignore: avoid_print
      print("[ERROR AppConfig] Impossibile salvare il changelog su disco: $e");
    }
  }

  static Future<void> resetDriveChangelog() async {
    _lastDriveVersion = null;
    _lastDriveTimestamp = null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastDriveVersionKey);
      await prefs.remove(_lastDriveTimestampKey);
      // ignore: avoid_print
      print("[DEBUG AppConfig] Changelog e cache dati resettati su disco.");
    } catch (e) {
      // ignore: avoid_print
      print("[ERROR AppConfig] Impossibile resettare il changelog su disco: $e");
    }
  }
}
