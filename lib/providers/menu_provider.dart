// lib/providers/menu_provider.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- MODIFICA

// Importa i modelli aggiornati
import '../models/piatto.dart';
import '../models/menu_template.dart';
// import '../services/menu_service.dart'; // <-- MODIFICA: Non più necessario

class MenuProvider extends ChangeNotifier {
  // --- MODIFICA: Usiamo Firestore invece del vecchio service ---
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Piatto> _piatti = [];
  List<String> _categorie = [];
  List<MenuTemplate> _menuTemplates = [];

  bool _isLoading = false;
  String? _errore;

  List<Piatto> get tuttiIpiatti => _piatti;
  List<String> get tutteLeCategorie => _categorie;
  List<MenuTemplate> get tuttiIMenuTemplates => _menuTemplates;
  bool get isLoading => _isLoading;
  String? get errore => _errore;

  /// Metodo principale per caricare tutti i dati necessari per la sezione menu da Firestore.
  Future<void> caricaDatiMenu() async {
    if (_isLoading) return;

    _isLoading = true;
    _errore = null;
    notifyListeners();

    try {
      // Eseguiamo le due chiamate a Firestore in parallelo per efficienza
      final results = await Future.wait([
        _firestore.collection('piatti').get(),
        _firestore.collection('menu_templates').get(),
      ]);

      final piattiSnapshot = results[0] as QuerySnapshot;
      final templatesSnapshot = results[1] as QuerySnapshot;

      // --- MODIFICA CHIAVE: Usiamo il costruttore .fromFirestore ---
      _piatti = piattiSnapshot.docs.map((doc) => Piatto.fromFirestore(doc)).toList();
      
      _menuTemplates = templatesSnapshot.docs.map((doc) => MenuTemplate.fromFirestore(doc)).toList();
      
      // Estraiamo le categorie (generi) direttamente dai piatti caricati
      _categorie = _piatti.map((p) => p.genere).toSet().toList()..sort();
      
      if (kDebugMode) {
        print("[MenuProvider] Dati caricati: ${_piatti.length} piatti, ${_categorie.length} categorie, ${_menuTemplates.length} templates.");
      }

    } catch (e) {
      if (kDebugMode) {
        print("[MenuProvider] ERRORE durante il caricamento dei dati: $e");
      }
      _errore = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}