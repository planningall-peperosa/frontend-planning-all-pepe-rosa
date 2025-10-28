// lib/providers/segretario_provider.dart

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // Facoltativo: non usato direttamente qui
import '../models/promemoria_item.dart';
import '../models/servizio_selezionato.dart';
import '../models/configurazione_segretario.dart';
import 'dart:async';
import 'package:intl/intl.dart';

// ✅ Estendi ChangeNotifier correttamente
class SegretarioProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<PromemoriaItem> _items = [];
  bool _isLoading = false;
  String? _error;

  ConfigurazioneSegretario _config = ConfigurazioneSegretario.defaultConfig();

  List<PromemoriaItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ConfigurazioneSegretario get config => _config;

  Future<void> loadConfig() async {
    try {
      final doc =
          await _firestore.collection('configurazione').doc('segretario').get();
      if (doc.exists) {
        _config = ConfigurazioneSegretario.fromMap(doc.data()!, doc.id);
      }
    } catch (e) {
      debugPrint('Errore caricamento configurazione segretario: $e');
      _config = ConfigurazioneSegretario.defaultConfig();
    }
  }



  Future<void> fetchPromemoria() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    await loadConfig(); 

    try {
      final now = DateTime.now().toUtc();
      
      // Calcola l'inizio del giorno (00:00:00) per oggi e la data limite
      final DateTime startDay = DateTime.utc(now.year, now.month, now.day); 
      final DateTime limitDay = startDay.add(Duration(days: _config.finestraGiorniToDo + 1));
      
      // 🚨 CORREZIONE: Converti le date di inizio/fine in Timestamp per la query
      final Timestamp startTimestamp = Timestamp.fromDate(startDay);
      final Timestamp limitTimestamp = Timestamp.fromDate(limitDay);

      print('--- SEGRETARIO DIAGNOSTICA ---');
      print('Query Range: ${startDay.toIso8601String()} a ${limitDay.toIso8601String()}');


      // 🚨 MODIFICA CRITICA: Query su campo Timestamp
      final snapshot = await _firestore.collection('preventivi')
          .where('data_evento', isGreaterThanOrEqualTo: startTimestamp)
          .where('data_evento', isLessThan: limitTimestamp) // < usiamo 'isLessThan' per escludere il giorno limite
          .orderBy('data_evento', descending: false)
          .get();
      
      print('Trovati ${snapshot.docs.length} preventivi.');

      final List<PromemoriaItem> promemoria = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final preventivoId = doc.id;

        // 🚨 ESTRAZIONE E CAST ROBUSTO PER OSPITI E TIPO PASTO
        final tipoPasto = data['tipo_pasto'] as String?;
        final numeroOspitiRaw = data['numero_ospiti'];
        final int numeroOspiti = (numeroOspitiRaw is num) 
            ? numeroOspitiRaw.toInt()
            : (numeroOspitiRaw is String)
                ? int.tryParse(numeroOspitiRaw) ?? 0
                : 0;

        // 🚨 DIAGNOSTICA OSPITI: Stampa il valore letto dal DB
        debugPrint('[DEBUG OSPITI] Preventivo ID: $preventivoId, Ospiti letti: $numeroOspiti');
        
        final Timestamp? dataEventoTimestamp = data['data_evento'] as Timestamp?; 
        final DateTime? dtEvento = dataEventoTimestamp?.toDate(); 
        final List<dynamic>? serviziExtraRaw = 
            (data['servizi'] as List<dynamic>?) ?? 
            (data['servizi_extra'] as List<dynamic>?); // Fallback al nome precedente
        
        // Final check per l'output di diagnostica
        if (serviziExtraRaw == null || serviziExtraRaw.isEmpty) continue;
        if (dtEvento == null) continue;
        
        final int giorniRimasti = dtEvento.difference(startDay).inDays;

        for (int i = 0; i < serviziExtraRaw.length; i++) {
            final Map<String, dynamic> rawService = serviziExtraRaw[i] as Map<String, dynamic>;
            final servizio = ServizioSelezionato.fromJson(rawService);

            if (giorniRimasti < 0) continue; 
            if (giorniRimasti > _config.finestraGiorniToDo) continue; 

            String statoCalcolato = servizio.isContattato 
                ? 'done'
                : (giorniRimasti <= _config.finestraGiorniUrgente ? 'urgente' : 'todo');
            
            print('✅ Promemoria aggiunto per ${servizio.ruolo} ($giorniRimasti giorni rimanenti).');

            final fornitoreNome = servizio.fornitore?.ragioneSociale ?? 'Sconosciuto';
            final clienteNome = data['nome_cliente'] as String? ?? 'N/A';
            
            promemoria.add(PromemoriaItem.fromMap({
                'preventivo_id': preventivoId,
                'servizio_id': servizio.ruolo,
                'data_evento': dtEvento.toIso8601String(), 
                'ruolo': servizio.ruolo,
                'fornitore': fornitoreNome,
                'is_contattato': servizio.isContattato,
                'id': '$preventivoId-${servizio.ruolo}', 
                'deadline': DateFormat('dd/MM/yyyy').format(dtEvento),
                'stato_calcolato': statoCalcolato,
                'titolo': '$clienteNome — ${data['nome_evento'] ?? 'Evento'}', 
                'descrizione': '${servizio.ruolo.toUpperCase()} • $fornitoreNome',
                'telefono': servizio.fornitore?.telefono01,
                'email': servizio.fornitore?.mail,
                'tipo_pasto': tipoPasto, 
                'note_servizio': servizio.note,
                'numero_ospiti': numeroOspiti, // ✅ Passa il dato ospite
            }));
          }
        }
      
      _items = promemoria;
      print('--- RISULTATO FINALE: Aggiunti ${_items.length} promemoria. ---');

    } catch (e) {
      _error = "Errore nel calcolo promemoria: ${e.toString()}";
      print('❌ ERRORE FATALE NEL FETCH: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> marcaAzioneDone({
    required String preventivoId,
    required String servizioRuolo,
  }) async {
    _error = null;
    final docRef = _firestore.collection('preventivi').doc(preventivoId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      _error = 'Preventivo non trovato.';
      return false;
    }

    final data = docSnapshot.data()!;
    // 🚨 CORREZIONE: Cerca sia in 'servizi' che in 'servizi_extra'
    final List<dynamic>? serviziExtraRaw = 
        (data['servizi'] as List<dynamic>?) ?? 
        (data['servizi_extra'] as List<dynamic>?);
    
    if (serviziExtraRaw == null) {
      _error = 'Servizi extra non trovati nel preventivo.';
      return false;
    }

    int serviceIndex = -1;
    for (int i = 0; i < serviziExtraRaw.length; i++) {
      final rawService = serviziExtraRaw[i] as Map<String, dynamic>;
      if ((rawService['ruolo'] as String?)?.toLowerCase() == servizioRuolo.toLowerCase()) {
        serviceIndex = i;
        break;
      }
    }

    if (serviceIndex == -1) {
      _error = 'Servizio ($servizioRuolo) non trovato nel preventivo.';
      return false;
    }
    
    try {
        final Map<String, dynamic> currentService = Map.from(serviziExtraRaw[serviceIndex] as Map);
        
        final updatedService = ServizioSelezionato.fromJson(currentService).copyWith(
            isContattato: true,
            dataUltimoContatto: DateTime.now().toUtc(),
        );

        serviziExtraRaw[serviceIndex] = updatedService.toJson();

        // 🚨 ATTENZIONE: Aggiorna il campo corretto su Firestore ('servizi' o 'servizi_extra'). 
        // Poiché il PreventivoBuilderProvider usa 'servizi', aggiorniamo quello.
        await docRef.update({
            'servizi': serviziExtraRaw, 
        });

        await fetchPromemoria(); 
        return true;

    } catch (e) {
      _error = 'Errore durante l\'aggiornamento dello stato del servizio: $e';
      return false;
    }
  }



  // ✅ Update Config
  Future<bool> updateConfig(int giorniToDo, int giorniUrgente) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _firestore.collection('configurazione').doc('segretario').set({
        'finestra_giorni_todo': giorniToDo,
        'finestra_giorni_urgente': giorniUrgente,
      });

      await loadConfig();
      await fetchPromemoria();
      return true;
    } catch (e) {
      _error = 'Errore nell\'aggiornamento della configurazione: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
