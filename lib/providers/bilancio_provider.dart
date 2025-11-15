// lib/providers/bilancio_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async'; 
import 'package:flutter/foundation.dart'; 
import '../models/bilancio_models.dart';
import '../repositories/bilancio_repository.dart';

// Provider per l'istanza del Repository (non ha bisogno di dipendere da altri providers)
final bilancioRepositoryProvider = Provider((ref) => BilancioRepository());


// 🔑 FIX/DEBUG: Provider per lo stream delle Categorie
final categorieStreamProvider = StreamProvider.autoDispose<List<SpesaCategoria>>((ref) {
  final repository = ref.watch(bilancioRepositoryProvider);
  
  if (kDebugMode) print('--- DEBUG CATEGORIE: Avvio stream ---');

  // Ascolta lo stream e aggiunge log per debuggarne lo stato
  return repository.getCategorieStream().handleError((error, stackTrace) {
    if (kDebugMode) {
      print('🚨 DEBUG CATEGORIE: ERRORE NELLO STREAM: $error');
      print('Stack: $stackTrace');
    }
    // Rilancia l'errore affinché .when() nella UI lo intercetti
    throw error;
  }).map((categories) {
    if (kDebugMode) print('✅ DEBUG CATEGORIE: Dati ricevuti (${categories.length} categorie)');
    return categories;
  });
});


class BilancioState {
  final DateTime startDate;
  final DateTime endDate;
  final double entrate;
  final double totaleSpese;
  final List<SpesaRegistrata> spese;
  final List<Map<String, dynamic>> preventiviDetails;
  final bool isLoading;

  BilancioState({
    required this.startDate,
    required this.endDate,
    this.entrate = 0.0,
    this.totaleSpese = 0.0,
    this.spese = const [],
    this.preventiviDetails = const [],
    this.isLoading = false,
  });

  BilancioState copyWith({
    DateTime? startDate,
    DateTime? endDate,
    double? entrate,
    double? totaleSpese,
    List<SpesaRegistrata>? spese,
    List<Map<String, dynamic>>? preventiviDetails,
    bool? isLoading,
  }) {
    return BilancioState(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      entrate: entrate ?? this.entrate,
      totaleSpese: totaleSpese ?? this.totaleSpese,
      spese: spese ?? this.spese,
      preventiviDetails: preventiviDetails ?? this.preventiviDetails,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// StateNotifierProvider per gestire la logica del Bilancio nel tempo
final bilancioProvider = StateNotifierProvider.autoDispose<BilancioNotifier, BilancioState>((ref) {
  final repository = ref.watch(bilancioRepositoryProvider);
  return BilancioNotifier(repository);
});


class BilancioNotifier extends StateNotifier<BilancioState> {
  final BilancioRepository _repository; 
  StreamSubscription<List<SpesaRegistrata>>? _speseSubscription;

  BilancioNotifier(this._repository)
      : super(BilancioState(
          startDate: DateTime(DateTime.now().year, DateTime.now().month, 1),
          endDate: DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
        )) {
    refreshBilancioData(); 
  }

  @override
  void dispose() {
    _speseSubscription?.cancel();
    super.dispose(); 
  }


  Future<List<SpesaCategoria>> fetchCategoriesForDialog() async {
     try {
        final categories = await _repository.getCategorieStream().first;
        if (kDebugMode) print('✅ DIALOG FETCH: Categorie caricate tramite Future.');
        return categories;
     } catch(e) {
        if (kDebugMode) print('🚨 DIALOG FETCH: Errore nel caricare le categorie: $e');
        return [];
     }
  }



  /// Avvia l'ascolto reattivo delle spese e ricarica le entrate.
  void refreshBilancioData() { 
    _speseSubscription?.cancel();
    state = state.copyWith(isLoading: true);
    
    _loadEntrateAndDetails();

    // Ascolta lo stream delle spese (reattivo)
    _speseSubscription = _repository.getSpeseByPeriod(
      start: state.startDate, 
      end: state.endDate,
    ).listen((spese) {
      final totaleSpese = spese.fold(0.0, (sum, spesa) => sum + spesa.importo);
      // 🔑 DEBUG: Dati Spese ricevuti
      if (kDebugMode) print('✅ DEBUG SPESE: Dati ricevuti (${spese.length} spese)');
      
      // Aggiornamento dello stato
      state = state.copyWith(
        spese: spese,
        totaleSpese: totaleSpese,
        isLoading: false,
      );
    }, onError: (error, stackTrace) { // 🔑 Aggiunto error e stackTrace
      if (kDebugMode) {
        print('🚨 DEBUG SPESE: ERRORE NELLO STREAM: $error');
        print('Stack: $stackTrace');
      }
      state = state.copyWith(isLoading: false);
    });
  }

  /// Carica le entrate e i dettagli dei preventivi.
  Future<void> _loadEntrateAndDetails() async {
    final result = await _repository.calculateEntrateWithDetails(
      start: state.startDate,
      end: state.endDate,
    );
    state = state.copyWith(
      entrate: result['total'] as double,
      preventiviDetails: result['details'] as List<Map<String, dynamic>>,
    );
  }

  /// Aggiorna il periodo di tempo e riavvia il listener delle spese.
  void updatePeriod(DateTime start, DateTime end) {
    final newStart = start.isBefore(end) ? start : end;
    final newEnd = end.isAfter(start) ? end : start;

    if (state.startDate == newStart && state.endDate == newEnd) return;
    
    state = state.copyWith(startDate: newStart, endDate: newEnd);
    refreshBilancioData();
  }
}
