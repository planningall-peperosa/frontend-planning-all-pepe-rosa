import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:flutter/services.dart';

import '../widgets/logo_widget.dart';

class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  String? _selectedNome;
  bool _isLoading = false;
  List<String> _nomiDipendenti = [];
  bool _isLoadingNomi = true;
  String? _erroreNomi;

  @override
  void initState() {
    super.initState();
    _fetchNomiDipendenti();
  }

  Future<void> _fetchNomiDipendenti() async {
    if (!mounted) return;
    setState(() {
      _isLoadingNomi = true;
      _erroreNomi = null;
    });
    try {
      final response =
          await http.get(Uri.parse('${AppConfig.currentBaseUrl}/dipendenti'));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        List<dynamic> dipendentiList;

        if (decodedData is List) {
          dipendentiList = decodedData;
        } else if (decodedData is Map<String, dynamic>) {
          if (decodedData.containsKey('dipendenti')) {
            dipendentiList = decodedData['dipendenti'] as List<dynamic>;
          } else if (decodedData.containsKey('data')) {
            dipendentiList = decodedData['data'] as List<dynamic>;
          } else {
            throw Exception("Formato JSON non riconosciuto.");
          }
        } else {
          throw Exception("Formato della risposta non valido.");
        }

        setState(() {
          _nomiDipendenti = dipendentiList
              .map((e) => e['nome_dipendente'].toString())
              .toList();
          if (_nomiDipendenti.isNotEmpty) {
            _selectedNome = _nomiDipendenti[0];
          }
        });
      } else {
        setState(() {
          _erroreNomi = "Errore caricamento nomi (${response.statusCode})";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroreNomi = "Errore di rete: $e";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingNomi = false;
      });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _performLogin() async {
    if (_selectedNome == null || _selectedNome!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Seleziona il tuo nome')));
      return;
    }
    if (_pinController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Inserisci il PIN')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      await authProvider.login(_selectedNome!, _pinController.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst("Exception: ", ""))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // MODIFICA: Otteniamo il tema per usare i colori.
    final theme = Theme.of(context);
    final inputTextStyle = TextStyle(color: theme.colorScheme.onSurface, fontSize: 18);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (_isLoadingNomi)
                Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    // MODIFICA: Colore testo preso dal tema per la visibilità.
                    Text("Caricamento dipendenti...", style: TextStyle(color: theme.colorScheme.onBackground)),
                  ],
                )
              else if (_erroreNomi != null)
                Text(_erroreNomi!,
                    // MODIFICA: Colore testo errore preso dal tema.
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold))
              else
                DropdownButtonFormField<String>(
                  value: _selectedNome,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: "Seleziona il tuo nome",
                    filled: true,
                    // MODIFICA: Colore sfondo preso dal tema.
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  items: _nomiDipendenti
                      .map((nome) => DropdownMenuItem<String>(
                            value: nome,
                            // MODIFICA: Colore testo preso dal tema.
                            child: Text(nome, style: TextStyle(color: theme.colorScheme.onSurface)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedNome = v),
                  // MODIFICA: Colore sfondo menu a tendina preso dal tema.
                  dropdownColor: theme.colorScheme.surface,
                ),
              SizedBox(height: 20),
              TextFormField(
                controller: _pinController,
                style: inputTextStyle,
                keyboardType: TextInputType.number,
                obscureText: true,
                obscuringCharacter: '●',
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  filled: true,
                  // MODIFICA: Colore sfondo preso dal tema.
                  fillColor: theme.colorScheme.surface,
                   border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                ),
                onFieldSubmitted: (_) => _performLogin(),
              ),
              SizedBox(height: 20),
              _isLoading
                  ? CircularProgressIndicator()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Questi bottoni usano lo stile globale del tema.
                        ElevatedButton(
                          onPressed: _performLogin,
                          child: Text('Login'),
                        ),
                        SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: () => SystemNavigator.pop(),
                          child: Text('Esci'),
                        ),
                      ],
                    ),
              SizedBox(height: 36),
              
              LogoWidget(),

            ],
          ),
        ),
      ),
    );
  }
}