// lib/providers/clienti_provider.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../models/cliente.dart';
// Rimuoviamo l'import di '../services/clienti_service.dart';

class ClientiProvider extends ChangeNotifier {
  // 1. Istanza di Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = false;
  String? _error;
  
  List<Cliente> _contattiTrovati = [];
  Map<String, int> _conteggiReali = {}; 
  String? _verifyingCountForClientId; 
  
  List<String> _ruoliServizi = [
    'Pasticceria', 
    'Fiorista', 
    'Allestimento',
    'Fotografo', 
    'Musica', 
    'DJ', 
    'Location', 
    'Tovagliato',
    'Fornitore alimentare',
    'Altro',
  ]; 
  
  bool _isLoadingRuoli = false;
  List<Cliente> _tuttiContatti = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Cliente> get contattiTrovati => _contattiTrovati;
  Map<String, int> get conteggiReali => _conteggiReali;
  String? get verifyingCountForClientId => _verifyingCountForClientId;
  List<String> get ruoliServizi => _ruoliServizi;
  bool get isLoadingRuoli => _isLoadingRuoli;
  List<Cliente> get tuttiContatti => _tuttiContatti;


  // ----------------------------------------------------
  // NUOVO METODO: CONTROLLO DUPLICATI SU FIRESTORE
  // ----------------------------------------------------

  // Restituisce una lista di contatti che matchano nome o telefono
  Future<List<Cliente>> checkDuplicateContact({
    required String ragioneSociale, 
    required String telefono01, 
    String? currentContactId, // ID del contatto corrente se siamo in modalità modifica
  }) async {
    if (ragioneSociale.isEmpty && telefono01.isEmpty) return [];

    // NOTA: Firestore non supporta query OR su campi diversi o query non case-sensitive
    // La nostra query sarà APPROSSIMATIVA (solo startAt/endAt sul nome) e PRECISA (sul telefono).
    // Dobbiamo eseguire due query separate per nome e telefono e combinarle.

    final Set<String> matchingIds = {};
    final List<Cliente> matchingContacts = [];

    // Query 1: Ricerca per nome (case-sensitive ma con range, per simulare "inizia con")
    final cleanNome = ragioneSociale.trim().toLowerCase();
    if (cleanNome.isNotEmpty) {
        final startAt = cleanNome;
        final endAt = cleanNome + '\uf8ff';

        for (final collection in ['clienti', 'fornitori']) {
            final nomeSnapshot = await _firestore
                .collection(collection)
                .orderBy('ragione_sociale')
                .startAt([startAt])
                .endAt([endAt])
                .get();

            for (final doc in nomeSnapshot.docs) {
                // Filtriamo per i contatti che non sono quello che stiamo modificando
                if (doc.id != currentContactId && matchingIds.add(doc.id)) {
                    matchingContacts.add(Cliente.fromFirestore(doc));
                }
            }
        }
    }

    // Query 2: Ricerca per telefono (precisa)
    final cleanTel = telefono01.trim();
    if (cleanTel.isNotEmpty) {
        for (final collection in ['clienti', 'fornitori']) {
            final telSnapshot = await _firestore
                .collection(collection)
                .where('telefono_01', isEqualTo: cleanTel)
                .limit(1)
                .get();

            for (final doc in telSnapshot.docs) {
                // Aggiungiamo solo se non è l'ID corrente e non è già stato aggiunto
                if (doc.id != currentContactId && matchingIds.add(doc.id)) {
                    matchingContacts.add(Cliente.fromFirestore(doc));
                }
            }
        }
    }
    
    return matchingContacts;
  }
  
  // ----------------------------------------------------
  // LOGICA DI CARICAMENTO COMPLETO
  // ----------------------------------------------------
  
  Future<void> fetchAllContacts({bool force = false}) async {
    // Evitiamo ricaricamenti inutili se la lista è già popolata
    if (_tuttiContatti.isNotEmpty && !force) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // 1. Fetch di tutti i Clienti
      final clientiSnapshot = await _firestore.collection('clienti').get();
      final List<Cliente> clienti = clientiSnapshot.docs
          .map((doc) => Cliente.fromFirestore(doc))
          .toList();
      
      // 2. Fetch di tutti i Fornitori
      final fornitoriSnapshot = await _firestore.collection('fornitori').get();
      final List<Cliente> fornitori = fornitoriSnapshot.docs
          .map((doc) => Cliente.fromFirestore(doc))
          .toList();

      // 3. Unifichiamo e ordiniamo (opzionale)
      _tuttiContatti = [...clienti, ...fornitori];
      // Ordiniamo per ragione sociale per visualizzazione
      _tuttiContatti.sort((a, b) => (a.ragioneSociale ?? '').toLowerCase().compareTo((b.ragioneSociale ?? '').toLowerCase()));
      
      if (_tuttiContatti.isEmpty) _error = "Nessun contatto archiviato.";

    } catch (e) {
      _error = 'Errore nel caricamento di tutti i contatti: $e';
      _tuttiContatti = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }


  Future<void> cercaContatti(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.length < 3) {
      _contattiTrovati = [];
      notifyListeners();
      return;
    }
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final startAt = cleanQuery;
      final endAt = cleanQuery + '\uf8ff';

      final clientiSnapshot = await _firestore
          .collection('clienti')
          .orderBy('ragione_sociale')
          .startAt([startAt])
          .endAt([endAt])
          .limit(20) 
          .get();

      final fornitoriSnapshot = await _firestore
          .collection('fornitori')
          .orderBy('ragione_sociale')
          .startAt([startAt])
          .endAt([endAt])
          .limit(20) 
          .get();
      
      final List<Cliente> clienti = clientiSnapshot.docs
          .map((doc) => Cliente.fromFirestore(doc))
          .toList();
      
      final List<Cliente> fornitori = fornitoriSnapshot.docs
          .map((doc) => Cliente.fromFirestore(doc))
          .toList();

      _contattiTrovati = [...clienti, ...fornitori];
      
      if (_contattiTrovati.isEmpty) _error = "Nessun contatto trovato.";

    } catch (e) {
      _error = 'Errore di ricerca su Firebase: $e';
      _contattiTrovati = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Cliente?> cercaClientePerTelefono(String telefono) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    final cleanTelefono = telefono.trim();

    try {
      final snapshot = await _firestore
          .collection('clienti')
          .where('telefono_01', isEqualTo: cleanTelefono)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null; 
      }

      return Cliente.fromFirestore(snapshot.docs.first);
      
    } catch (e) {
      _error = 'Errore imprevisto nella ricerca per telefono: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Cliente?> aggiornaContatto(String idContatto, String tipoContatto, Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    final collectionName = tipoContatto == 'cliente' ? 'clienti' : 'fornitori';
    
    try {
      await _firestore.collection(collectionName).doc(idContatto).update(data);

      final updatedDoc = await _firestore.collection(collectionName).doc(idContatto).get();
      final Cliente contattoAggiornato = Cliente.fromFirestore(updatedDoc);
      
      final index = _contattiTrovati.indexWhere((c) => c.idCliente == idContatto);
      if (index != -1) {
        _contattiTrovati[index] = contattoAggiornato;
      }
      return contattoAggiornato;
      
    } catch (e) {
      _error = 'Errore nell\'aggiornamento del contatto: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> eliminaContatto(String idContatto, String tipoContatto) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    final collectionName = tipoContatto == 'cliente' ? 'clienti' : 'fornitori';

    try {
      await _firestore.collection(collectionName).doc(idContatto).delete();
      
      _contattiTrovati.removeWhere((c) => c.idCliente == idContatto);
      return true;
    } catch (e) {
      _error = 'Errore nell\'eliminazione del contatto: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _contattiTrovati = [];
    _error = null;
    _conteggiReali = {};
    _verifyingCountForClientId = null;
    notifyListeners();
  }

  void clearState() {
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> caricaRuoliServizi() async {
    if (_ruoliServizi.isNotEmpty) return; 
    
    _isLoadingRuoli = true;
    notifyListeners();
    
    _isLoadingRuoli = false;
    notifyListeners();
  }
}