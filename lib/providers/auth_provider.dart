// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/app_config.dart';

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
  bool _isAuthenticated = false;
  String? _user;
  String? _pinFornitoAlLogin;
  String? _userRuolo;
  String? _idUnico;
  String? _nomeDipendente;

  bool get isAuthenticated => _isAuthenticated;
  String? get user => _user;
  String? get pinFornitoAlLogin => _pinFornitoAlLogin;
  String? get userRuolo => _userRuolo;
  String? get idUnico => _idUnico;
  String? get nomeDipendente => _nomeDipendente;

  String get _baseUrl => AppConfig.currentBaseUrl;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<AutorizzazioneApp> _autorizzazioniApp = [];
  List<AutorizzazioneApp> get autorizzazioniApp => _autorizzazioniApp;

  Map<String, dynamic>? lastLoginResponseData;

  List<String> _funzioniAutorizzate = [];
  List<String> get funzioniAutorizzate => List.unmodifiable(_funzioniAutorizzate);

  bool isFunzioneAutorizzata(String nomeFunzione) {
    if (_userRuolo == 'admin') return true;
    return _funzioniAutorizzate.contains(nomeFunzione);
  }

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

  Future<void> login(String nomeDipendente, String pin) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/authenticate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nome_dipendente': nomeDipendente, 'pin': pin}),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['authenticated'] == true) {
          final String returnedNome = data['dipendente']?['nome_dipendente'] ?? '';

          if (returnedNome != nomeDipendente) {
            throw Exception('PIN non corretto per l\'utente selezionato.');
          }

          _isAuthenticated = true;
          _user = data['dipendente']?['nome_dipendente'] ?? '';
          _userRuolo = (data['dipendente']?['ruolo'] ?? '').toString().toLowerCase().trim();
          _pinFornitoAlLogin = pin;
          lastLoginResponseData = data;
          _idUnico = data['dipendente']?['id_unico']?.toString() ?? '';
          _nomeDipendente = data['dipendente']?['nome_dipendente'] ?? '';
          
          if (_userRuolo != "admin") {
            await _fetchAutorizzazioniMenu();
          } else {
            _funzioniAutorizzate.clear();
          }
        } else {
          throw Exception(data['message'] ?? 'PIN non valido o utente non riconosciuto.');
        }
      } else {
        String errorMessage = 'Errore di autenticazione dal server.';
        try {
          final data = jsonDecode(response.body);
          errorMessage = data['detail'] ?? data['message'] ?? errorMessage;
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      logout();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    _isAuthenticated = false;
    _user = null;
    _userRuolo = null;
    _pinFornitoAlLogin = null;
    _idUnico = null;
    _nomeDipendente = null;
    _funzioniAutorizzate.clear();
    lastLoginResponseData = null;
    notifyListeners();
  }
}
