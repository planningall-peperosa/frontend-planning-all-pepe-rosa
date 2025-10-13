import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class HapticsService {
  HapticsService._();
  static final HapticsService _i = HapticsService._();
  factory HapticsService() => _i;

  Timer? _holdTimer;

  int _mapAmp(int percent) {
    final p = percent.clamp(0, 100);
    final amp = (p / 100 * 255).round();
    return amp.clamp(1, 255);
  }

  Future<void> preview(int strengthPercent, int millis) async {
    if (Platform.isAndroid) {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;
      final hasAmp = await Vibration.hasAmplitudeControl() ?? false;
      if (hasAmp) {
        await Vibration.vibrate(duration: millis, amplitude: _mapAmp(strengthPercent));
      } else {
        await Vibration.vibrate(duration: millis);
      }
    } else {
      // iOS: intensità non regolabile
      await HapticFeedback.mediumImpact();
      await Future.delayed(Duration(milliseconds: millis));
      await HapticFeedback.mediumImpact();
    }
  }

  Future<void> startHoldingFeedback(int strengthPercent) async {
    await stopHoldingFeedback();

    if (Platform.isAndroid) {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;
      final hasAmp = await Vibration.hasAmplitudeControl() ?? false;
      final amp = _mapAmp(strengthPercent);

      // piccoli impulsi ripetuti, per una sensazione continua
      _holdTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (hasAmp) {
          Vibration.vibrate(duration: 60, amplitude: amp);
        } else {
          Vibration.vibrate(duration: 60);
        }
      });
    } else {
      _holdTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        HapticFeedback.mediumImpact();
      });
    }
  }

  Future<void> stopHoldingFeedback() async {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (Platform.isAndroid) {
      await Vibration.cancel();
    }
  }

  Future<void> success() async {
    if (Platform.isAndroid) {
      final hasAmp = await Vibration.hasAmplitudeControl() ?? false;
      if (hasAmp) {
        await Vibration.vibrate(
          pattern: [0, 40, 60, 70],
          intensities: [0, 200, 0, 255],
        );
      } else {
        await Vibration.vibrate(pattern: [0, 40, 60, 70]);
      }
    } else {
      await HapticFeedback.heavyImpact();
      await HapticFeedback.selectionClick();
    }
  }

  Future<void> cancelTap() async {
    if (Platform.isAndroid) {
      await Vibration.vibrate(duration: 25);
    } else {
      await HapticFeedback.selectionClick();
    }
  }
}
