import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/evento_calendario.dart';
import 'package:flutter/foundation.dart'; 

// Helper per rimuovere l'ora e rendere la data comparabile
bool isSameDay(DateTime a, DateTime b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class CalendarioEventiProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Mappa di tutti gli eventi, raggruppati per giorno
  Map<DateTime, List<EventoCalendario>> _eventiGrouped = {};
  
  List<EventoCalendario> _eventiList = []; 
  bool _isLoading = false;

  Map<DateTime, List<EventoCalendario>> get eventiGrouped => _eventiGrouped;
  bool get isLoading => _isLoading;

  StreamSubscription<QuerySnapshot>? _eventiSubscription;

  CalendarioEventiProvider() {
    startEventStream();
  }

  @override
  void dispose() {
    _eventiSubscription?.cancel();
    super.dispose();
  }
  
  /// Avvia l'ascolto in tempo reale di tutti i preventivi futuri e attuali da Firestore.
  void startEventStream() {
    if (_eventiSubscription != null) {
      _eventiSubscription!.cancel();
    }
    _isLoading = true;
    notifyListeners();

    // Query per tutti i preventivi futuri (o recenti passati) ordinati per data evento.
    // Usiamo come punto di partenza un mese nel passato per mostrare gli eventi recenti.
    final oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
    
    // NOTA: Se 'data_evento' è salvato come Timestamp, devi usare Timestamp qui:
    final query = _firestore.collection('preventivi')
        .where('data_evento', isGreaterThanOrEqualTo: Timestamp.fromDate(oneMonthAgo))
        .orderBy('data_evento', descending: false);

    _eventiSubscription = query.snapshots().listen((snapshot) {
      _eventiList = [];
      final Map<DateTime, List<EventoCalendario>> newEventiGrouped = {};
      
      for (var doc in snapshot.docs) {
        try {
          final evento = EventoCalendario.fromFirestore(doc);
          _eventiList.add(evento);
          
          // La data è già normalizzata in EventoCalendario.fromFirestore (mezzanotte UTC)
          final normalizedDate = evento.dataEvento;
          
          if (newEventiGrouped[normalizedDate] == null) {
            newEventiGrouped[normalizedDate] = [];
          }
          newEventiGrouped[normalizedDate]!.add(evento);
        } catch (e) {
          if (kDebugMode) {
            print("Errore nel parsing del preventivo ${doc.id}: $e");
          }
        }
      }
      
      _eventiGrouped = newEventiGrouped;
      _isLoading = false;
      notifyListeners();
    }, onError: (error) {
      if (kDebugMode) {
        print("Errore nello stream degli eventi: $error");
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Restituisce la lista di eventi per una data specifica.
  List<EventoCalendario> getEventsForDay(DateTime day) {
    // Normalizziamo la data da cercare (mezzanotte UTC)
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);
    return _eventiGrouped[normalizedDay] ?? [];
  }
  
  // Non servono metodi CRUD per gli eventi, perché la creazione/modifica avviene
  // tramite le schermate CreaPreventivoScreen.
}
