// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/app_config.dart';

// 🚨 NUOVI IMPORT PER FIREBASE AUTH, FIRESTORE e SHARED PREFERENCES
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Per salvare l'ultima email

class AutorizzazioneApp {
  final String nome;
  final int stato;

  AutorizzazioneApp({required this.nome, required this.stato});

  factory AutorizzazioneApp.fromJson(Map<String, dynamic> json) {
    final statoValue = json['stato'];
    int statoInt;
    if (statoValue is int) {
      statoInt = statoValue;
    } else if (statoValue is String) {
      statoInt = int.tryParse(statoValue) ?? 0;
    } else {
      statoInt = 0;
    }
    
    return AutorizzazioneApp(
      nome: json['nome'] ?? '',
      stato: statoInt,
    );
  }
}


class AuthProvider extends ChangeNotifier {
  // Configurazione Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stato e Dettagli Utente
  bool _isAuthenticated = false;
  // 🚨 NUOVO CAMPO: Per sapere quando lo stato iniziale è stato caricato
  bool _isAuthReady = false; 
  String? _user; 
  String? _pinFornitoAlLogin; 
  String? _userRuolo;
  String? _idUnico; 
  String? _nomeDipendente;

  // 🚨 NUOVO CAMPO: Ultima email usata
  String? _lastUsedEmail;
  static const String _lastEmailKey = 'last_login_email';

  // Stato Loading Legacy
  String get _baseUrl => AppConfig.currentBaseUrl;
  bool _isLoading = false;

  // Autorizzazioni Legacy
  List<AutorizzazioneApp> _autorizzazioniApp = [];
  Map<String, dynamic>? lastLoginResponseData;
  List<String> _funzioniAutorizzate = [];

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  // 🚨 NUOVO GETTER
  bool get isAuthReady => _isAuthReady;
  String? get user => _user;
  String? get pinFornitoAlLogin => _pinFornitoAlLogin;
  String? get userRuolo => _userRuolo;
  String? get idUnico => _idUnico;
  String? get nomeDipendente => _nomeDipendente;
  bool get isLoading => _isLoading;
  List<AutorizzazioneApp> get autorizzazioniApp => _autorizzazioniApp;
  List<String> get funzioniAutorizzate => List.unmodifiable(_funzioniAutorizzate);
  String? get lastUsedEmail => _lastUsedEmail;


  // 🚨 MODIFICA COSTRUTTORE: Avvia il listener e gestisce _isAuthReady
  AuthProvider() {
    _loadLastUsedEmail();
    
    // LISTENER: Usa listen per catturare il primo stato
    _auth.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        // Utente autenticato, carichiamo i dettagli (ruolo) da Firestore
        await _loadUserDetails(firebaseUser);
      } else {
        // Utente disconnesso
        logout(silent: true);
      }
      // 🚨 FONDAMENTALE: Imposta isAuthReady a true DOPO il primo evento
      if (!_isAuthReady) {
        _isAuthReady = true;
        notifyListeners();
      }
    });
  }

  // 🚨 NUOVO METODO: Carica l'ultima email salvata
  Future<void> _loadLastUsedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    _lastUsedEmail = prefs.getString(_lastEmailKey);
    notifyListeners();
  }

  // 🚨 NUOVO METODO: Salva l'email in caso di successo
  Future<void> _saveLastUsedEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastEmailKey, email.trim());
    _lastUsedEmail = email.trim();
  }


  // Helper per caricare i dettagli da Firestore
  Future<void> _loadUserDetails(User firebaseUser) async {
    try {
      final userDoc = await _firestore.collection('users').doc(firebaseUser.uid).get();

      // 🚨 CRITICO: Se il documento utente non esiste in Firestore, neghiamo l'accesso.
      if (!userDoc.exists) {
        throw Exception('Dettagli utente non trovati su Firestore. Accesso negato.');
      }

      final data = userDoc.data()!;
      
      _isAuthenticated = true;
      _user = firebaseUser.email; 
      _idUnico = firebaseUser.uid; 
      _userRuolo = (data['ruolo'] ?? 'dipendente').toString().toLowerCase().trim();
      _nomeDipendente = data['nome_display'] ?? firebaseUser.email?.split('@').first;

      // Aggiorniamo le autorizzazioni
      if (_userRuolo != "admin") {
        await _fetchAutorizzazioniMenu(); 
      } else {
        _funzioniAutorizzate.clear();
      }
      
    } catch (e) {
      print('[AuthProvider] Errore caricamento dettagli/ruolo da Firestore: $e');
      logout(silent: true);
    } finally {
      notifyListeners();
    }
  }


  bool isFunzioneAutorizzata(String nomeFunzione) {
    if (_userRuolo == 'admin') return true;
    return _funzioniAutorizzate.contains(nomeFunzione);
  }

  // Mantenuto per la logica di autorizzazione (Legacy)
  Future<void> _fetchAutorizzazioniMenu() async {
    _funzioniAutorizzate.clear();
    if (_userRuolo == 'admin') {
      notifyListeners();
      return;
    }
    try {
      final url = Uri.parse('$_baseUrl/autorizzazioni-app?nome_dipendente=$_nomeDipendente');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final dynamic decodedData = json.decode(response.body);
        List<dynamic> lista;

        if (decodedData is List) {
          lista = decodedData;
        } else if (decodedData is Map<String, dynamic>) {
          if (decodedData.containsKey('autorizzazioni')) {
            lista = decodedData['autorizzazioni'] as List;
          } else if (decodedData.containsKey('data')) {
            lista = decodedData['data'] as List;
          } else {
            throw Exception("Formato JSON non riconosciuto per le autorizzazioni.");
          }
        } else {
          throw Exception("Tipo di risposta non valido per le autorizzazioni.");
        }

        _funzioniAutorizzate = lista
            .where((e) => e['stato'] == 2 || e['stato'] == '2')
            .map<String>((e) => e['nome'] as String)
            .toList();
      } else {
        print('[AuthProvider] Errore caricamento autorizzazioni-app: ${response.statusCode}');
      }
    } catch (e) {
      print('[AuthProvider] Eccezione durante fetch autorizzazioni: $e');
      throw Exception("Impossibile caricare le autorizzazioni utente.");
    }
    notifyListeners();
  }

  // 🚨 MODIFICA CRITICA: Login con Firebase Email/Password
  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password, 
      ).timeout(const Duration(seconds: 10));

      // 🚨 AZIONE CHIAVE: Salva l'email solo se il login Firebase ha successo
      await _saveLastUsedEmail(email); 
      
      // La fase di autorizzazione (caricamento dettagli utente) è gestita automaticamente dal listener
      
    } on FirebaseAuthException catch (e) {
      logout(silent: true);
      String message;
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Email o Password (PIN) non validi.';
      } else {
        message = 'Errore di autenticazione: ${e.message}';
      }
      throw Exception(message);
      
    } catch (e) {
      logout(silent: true);
      throw Exception('Errore di rete o imprevisto: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 🚨 MODIFICA: Logout con Firebase Auth
  void logout({bool silent = false}) async {
    try {
      await _auth.signOut();
    } catch (e) {
      print('[AuthProvider] Errore durante il logout Firebase: $e');
    }
    
    // Aggiornamento dello stato locale
    _isAuthenticated = false;
    _user = null;
    _userRuolo = null;
    _pinFornitoAlLogin = null;
    _idUnico = null;
    _nomeDipendente = null;
    _funzioniAutorizzate.clear();
    lastLoginResponseData = null;
    
    if (!silent) {
      notifyListeners();
    }
  }
}