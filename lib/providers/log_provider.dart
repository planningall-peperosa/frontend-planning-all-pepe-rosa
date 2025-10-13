import 'package:flutter/foundation.dart';

class LogProvider extends ChangeNotifier {
  final StringBuffer _logBuffer = StringBuffer();

  String get log => _logBuffer.toString();

  void addLog(String message) {
    final now = DateTime.now();
    final timestamp = "[${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}]";
    _logBuffer.writeln("$timestamp $message");
    notifyListeners();
  }

  void clear() {
    _logBuffer.clear();
    notifyListeners();
  }
}
