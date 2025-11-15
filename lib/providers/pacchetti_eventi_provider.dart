import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pacchetto_evento.dart';

class PacchettiEventiProvider extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  String? _error;
  List<PacchettoEvento> _items = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<PacchettoEvento> get items => _items;

  Future<void> fetch() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snap = await _db.collection('pacchetti_eventi')
          .orderBy('nome_evento', descending: false)
          .get();

      _items = snap.docs.map((d) => PacchettoEvento.fromFirestore(d)).toList();
    } catch (e) {
      _error = 'Errore caricamento eventi: $e';
      _items = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> add(Map<String, dynamic> payload) async {
    try {
      await _db.collection('pacchetti_eventi').add({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await fetch();
      return true;
    } catch (e) {
      _error = 'Errore creazione evento: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> update(String id, Map<String, dynamic> payload) async {
    try {
      await _db.collection('pacchetti_eventi').doc(id).update({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await fetch();
      return true;
    } catch (e) {
      _error = 'Errore aggiornamento evento: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(String id) async {
    try {
      await _db.collection('pacchetti_eventi').doc(id).delete();
      _items.removeWhere((e) => e.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Errore eliminazione evento: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> duplicate(PacchettoEvento src) async {
    try {
      final payload = {
        'nome_evento': (src.nome.isNotEmpty ? src.nome : 'Senza nome') + ' (copia)',
        'descrizione_1': src.descrizione_1,
        'descrizione_2': src.descrizione_2,
        'descrizione_3': src.descrizione_3,
        'proposta_gastronomica': src.propostaGastronomica,
        'prezzo': src.prezzoFisso,
      };
      await _db.collection('pacchetti_eventi').add({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await fetch();
      return true;
    } catch (e) {
      _error = 'Errore duplicazione: $e';
      notifyListeners();
      return false;
    }
  }

}
