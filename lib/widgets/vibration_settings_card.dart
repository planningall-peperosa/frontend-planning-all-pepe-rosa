import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import '../providers/settings_provider.dart';

class VibrationSettingsCard extends StatefulWidget {
  const VibrationSettingsCard({super.key});

  @override
  State<VibrationSettingsCard> createState() => _VibrationSettingsCardState();
}

class _VibrationSettingsCardState extends State<VibrationSettingsCard> {
  Timer? _vibeTimer;         // vibrazione “continua” durante l’hold
  Timer? _completeTimer;     // timer che scatta quando superi la durata richiesta
  DateTime? _pressedAt;
  bool _confirmTriggered = false;
  bool _holding = false;

  @override
  void dispose() {
    _stopAll();
    super.dispose();
  }

  void _stopAll() {
    _vibeTimer?.cancel();
    _vibeTimer = null;
    _completeTimer?.cancel();
    _completeTimer = null;
    _pressedAt = null;
    _confirmTriggered = false;
    _holding = false;
  }

  Future<void> _twoShortPulses(int amp) async {
    final canVibrate = await Vibration.hasVibrator() ?? false;
    final hasAmp = await Vibration.hasAmplitudeControl() ?? false;

    if (canVibrate) {
      // due colpi brevi separati da 200ms
      if (hasAmp) {
        await Vibration.vibrate(pattern: [0, 30, 200, 30], intensities: [amp, amp]);
      } else {
        await Vibration.vibrate(pattern: [0, 30, 200, 30]);
      }
    } else {
      // fallback generic haptic
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.vibrate();
    }
  }

  Future<void> _startHoldTest(BuildContext context) async {
    if (_holding) return;
    final settings = context.read<SettingsProvider>();
    final int holdMs = settings.confirmHoldMillis;
    final int amp = settings.hapticIntensity.clamp(1, 255);

    _stopAll(); // pulizia
    _holding = true;
    _pressedAt = DateTime.now();
    _confirmTriggered = false;

    // vibrazione “continua” (via piccole vibrazioni ripetute)
    final canVibrate = await Vibration.hasVibrator() ?? false;
    final hasAmp = await Vibration.hasAmplitudeControl() ?? false;

    _vibeTimer = Timer.periodic(const Duration(milliseconds: 35), (_) {
      if (!mounted) return;
      if (canVibrate) {
        if (hasAmp) {
          Vibration.vibrate(duration: 10, amplitude: amp);
        } else {
          Vibration.vibrate(duration: 10);
        }
      } else {
        HapticFeedback.vibrate();
      }
    });

    // quando raggiungi la durata richiesta → conferma
    _completeTimer = Timer(Duration(milliseconds: holdMs), () async {
      if (!mounted) return;
      _confirmTriggered = true;

      // stop vibrazione continua
      _vibeTimer?.cancel();
      _vibeTimer = null;

      // due colpi di conferma
      await _twoShortPulses(amp);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anteprima: pressione prolungata confermata')),
      );
    });
  }

  void _endHoldTest() {
    // rilascio: se non hai ancora raggiunto il tempo minimo, annullo tutto senza conferma
    if (!_confirmTriggered) {
      _stopAll();
      return;
    }
    // se la conferma è già scattata, mi limito a pulire timer/stato
    _stopAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    String _fmtMs(int ms) {
      final sec = (ms / 1000.0);
      return sec.toStringAsFixed(sec.truncateToDouble() == sec ? 0 : 1) + ' s';
    }

    return Card(
      color: theme.colorScheme.primary,
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.vibration, color: theme.colorScheme.onPrimary),
            title: Text('Vibrazione e conferma', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
            subtitle: Text('Personalizza pressione prolungata e intensità vibrazione', style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.85))),
          ),

          // Contenuto
          Container(
            width: double.infinity,
            color: theme.colorScheme.background,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Durata pressione
                Text('Durata pressione per conferma: ${_fmtMs(settings.confirmHoldMillis)}',
                    style: theme.textTheme.bodyMedium),
                Slider(
                  value: settings.confirmHoldMillis.toDouble(),
                  min: 400,
                  max: 3000,
                  divisions: 26, // step di ~100ms
                  label: _fmtMs(settings.confirmHoldMillis),
                  onChanged: (v) => context.read<SettingsProvider>().setConfirmHoldMillis(v.round()),
                ),
                const SizedBox(height: 8),

                // Intensità (solo Android ha pieno controllo, ma la salviamo comunque)
                Text('Intensità vibrazione: ${settings.hapticIntensity}',
                    style: theme.textTheme.bodyMedium),
                Slider(
                  value: settings.hapticIntensity.toDouble().clamp(1, 255),
                  min: 1,
                  max: 255,
                  divisions: 254,
                  label: settings.hapticIntensity.toString(),
                  onChanged: (v) => context.read<SettingsProvider>().setHapticIntensity(v.round()),
                ),
                const SizedBox(height: 12),

                // AREA DI TEST: TENERE PREMUTO
                Center(
                  child: GestureDetector(
                    onTapDown: (_) => _startHoldTest(context),
                    onTapUp: (_) => _endHoldTest(),
                    onTapCancel: () => _endHoldTest(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _holding ? theme.colorScheme.primaryContainer : Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.black12),
                        boxShadow: _holding
                            ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _holding ? 'Continua a tenere premuto…' : 'Tieni premuto per provare',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
