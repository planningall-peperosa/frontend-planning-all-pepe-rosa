// lib/providers/menu_provider.dart
import 'package:flutter/foundation.dart';
// Importa i modelli che abbiamo appena creato
import '../models/piatto.dart';
import '../models/menu_template.dart';
import '../services/menu_service.dart';

class MenuProvider extends ChangeNotifier {
  final MenuService _menuService = MenuService();

  // Ora usiamo i nostri modelli invece di 'dynamic'!
  List<Piatto> _piatti = [];
  List<String> _categorie = [];
  List<MenuTemplate> _menuTemplates = [];

  bool _isLoading = false;
  String? _errore;

  // I getters ora restituiscono liste tipizzate
  List<Piatto> get tuttiIpiatti => _piatti;
  List<String> get tutteLeCategorie => _categorie;
  List<MenuTemplate> get tuttiIMenuTemplates => _menuTemplates;
  bool get isLoading => _isLoading;
  String? get errore => _errore;

  /// Metodo principale per caricare tutti i dati necessari per la sezione menu.
  Future<void> caricaDatiMenu() async {
    if (_isLoading) return;

    _isLoading = true;
    _errore = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _menuService.getMenuData(),
        _menuService.getMenuTemplates(),
      ]);

      final menuData = results[0] as Map<String, dynamic>;
      final menuTemplatesData = results[1] as List<dynamic>;

      // Convertiamo i dati JSON in liste di oggetti usando i nostri factory constructor
      _piatti = (menuData['piatti'] as List? ?? [])
          .map((json) => Piatto.fromJson(json))
          .toList();
      
      _categorie = List<String>.from(menuData['categorie'] ?? []);

      _menuTemplates = (menuTemplatesData)
          .map((json) => MenuTemplate.fromJson(json))
          .toList();
      
      print("[MenuProvider] Dati caricati: ${_piatti.length} piatti, ${_categorie.length} categorie, ${_menuTemplates.length} templates.");

    } catch (e) {
      print("[MenuProvider] ERRORE durante il caricamento dei dati: $e");
      _errore = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}