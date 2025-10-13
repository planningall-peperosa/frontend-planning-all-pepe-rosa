import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  // Keys per SharedPreferences
  static const String _kConfirmHoldMillis = 'settings.confirmHoldMillis';
  static const String _kHapticIntensity   = 'settings.hapticIntensity';

  // Valori di default
  int _confirmHoldMillis = 700; // range consigliato: 300..3000 ms
  int _hapticIntensity   = 120; // range: 1..255
  bool _loaded = false;

  // --- Stato ---
  bool get isLoaded => _loaded;

  // --- Getter canonici ---
  int get confirmHoldMillis => _confirmHoldMillis;
  int get hapticIntensity   => _hapticIntensity;

  // --- Alias legacy (compat con codice esistente) ---
  int get holdConfirmMs      => _confirmHoldMillis;
  int get vibrationStrength  => _hapticIntensity;

  // --- Caricamento iniziale (idempotente) ---
  Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _confirmHoldMillis =
        (sp.getInt(_kConfirmHoldMillis) ?? _confirmHoldMillis).clamp(300, 3000);
    _hapticIntensity =
        (sp.getInt(_kHapticIntensity) ?? _hapticIntensity).clamp(1, 255);
    _loaded = true;
    notifyListeners();
  }

  // --- Setter + persistenza ---
  Future<void> setConfirmHoldMillis(int ms) async {
    _confirmHoldMillis = ms.clamp(300, 3000);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kConfirmHoldMillis, _confirmHoldMillis);
  }

  Future<void> setHapticIntensity(int amp) async {
    _hapticIntensity = amp.clamp(1, 255);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kHapticIntensity, _hapticIntensity);
  }
}
