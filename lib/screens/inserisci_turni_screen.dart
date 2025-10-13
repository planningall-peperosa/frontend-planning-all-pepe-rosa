import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Per AuthProvider
import '../providers/auth_provider.dart';

class TurnoEntry {
  String dipendente; // ex commessa
  String tipoTurno;
  String giorniInput;
  List<int> giorniNumerici;

  TurnoEntry({
    required this.dipendente,
    required this.tipoTurno,
    required this.giorniInput,
    required this.giorniNumerici,
  });
}

class InserisciTurniScreen extends StatefulWidget {
  @override
  _InserisciTurniScreenState createState() => _InserisciTurniScreenState();
}

class _InserisciTurniScreenState extends State<InserisciTurniScreen> {
  final _yearController = TextEditingController(text: DateTime.now().year.toString());
  String? _selectedMonth;
  final _formKey = GlobalKey<FormState>();
  final _giorniController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  List<TurnoEntry> _turniDaInserire = [];
  final List<String> _mesiNomi = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];

  // Stato dinamico
  List<String> _ruoliDisponibili = [];
  List<Map<String, dynamic>> _dipendentiDisponibili = [];
  List<String> _dipendentiFiltrati = [];

  List<Map<String, dynamic>> _tipiTurnoDisponibili = [];
  Map<String, dynamic>? _currentTipoTurno;

  String? _selectedRuolo;
  String? _selectedDipendente;

  String get _baseUrl => AppConfig.currentBaseUrl;

  @override
  void initState() {
    super.initState();
    _selectedMonth = _mesiNomi[DateTime.now().month - 1];
    _fetchDipendentiERuoli();
    _fetchTipiTurnoDaFoglio();
  }

  @override
  void dispose() {
    _yearController.dispose();
    _giorniController.dispose();
    super.dispose();
  }

  List<int> _parseGiorniString(String giorniStr) {
    final Set<int> giorni = {};
    if (giorniStr.trim().isEmpty) return [];
    final parts = giorniStr.split(',');
    for (var part in parts) {
      part = part.trim();
      if (part.contains('-')) {
        final rangeParts = part.split('-');
        if (rangeParts.length == 2) {
          final start = int.tryParse(rangeParts[0]);
          final end = int.tryParse(rangeParts[1]);
          if (start != null && end != null && start <= end) {
            for (int i = start; i <= end; i++) {
              if (i >= 1 && i <= 31) giorni.add(i);
            }
          }
        }
      } else {
        final day = int.tryParse(part);
        if (day != null && day >= 1 && day <= 31) giorni.add(day);
      }
    }
    var sortedList = giorni.toList()..sort();
    print("[DEBUG] Giorni parsati da '$giorniStr': $sortedList");
    return sortedList;
  }

  void _aggiungiTurnoEntry() {
    if (_selectedRuolo == null || _selectedDipendente == null || _currentTipoTurno == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seleziona prima Ruolo, Dipendente e Tipo Turno.'))
      );
      return;
    }
    if (_formKey.currentState!.validate()) {
      final giorniNumerici = _parseGiorniString(_giorniController.text);
      if (giorniNumerici.isEmpty && _giorniController.text.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Formato giorni non valido.'))
        );
        return;
      }
      if (giorniNumerici.isEmpty && _giorniController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Campo giorni è vuoto.'))
        );
        return;
      }
      setState(() {
        _turniDaInserire.add(TurnoEntry(
          dipendente: _selectedDipendente!,
          tipoTurno: _currentTipoTurno?['label'] ?? '',
          giorniInput: _giorniController.text,
          giorniNumerici: giorniNumerici,
        ));
        _giorniController.clear();
      });
      print("[DEBUG] Aggiunto TurnoEntry: Ruolo: $_selectedRuolo, Dipendente: $_selectedDipendente, Tipo: ${_currentTipoTurno?['label']}, Giorni: $giorniNumerici");
    }
  }

  void _rimuoviTurnoEntry(int index) {
    setState(() => _turniDaInserire.removeAt(index));
  }

  Map<String, Map<String, List<int>>> _formattaTurniPerBackend() {
    Map<String, Map<String, List<int>>> turniPerBackend = {};
    for (var entry in _turniDaInserire) {
      turniPerBackend.putIfAbsent(entry.dipendente, () => {});
      turniPerBackend[entry.dipendente]!.putIfAbsent(entry.tipoTurno, () => []);
      var giorniEsistenti = Set<int>.from(turniPerBackend[entry.dipendente]![entry.tipoTurno]!);
      giorniEsistenti.addAll(entry.giorniNumerici);
      turniPerBackend[entry.dipendente]![entry.tipoTurno] = giorniEsistenti.toList()..sort();
    }
    print("[DEBUG] Dati formattati per backend: $turniPerBackend");
    return turniPerBackend;
  }

  void _filtraDipendentiPerRuolo(String? ruolo) {
    if (ruolo == null || ruolo.isEmpty) {
      setState(() { _dipendentiFiltrati = []; _selectedDipendente = null; });
      return;
    }
    final filtrati = _dipendentiDisponibili
        .where((d) => (d['ruolo'] ?? '').toString().toLowerCase() == ruolo.toLowerCase())
        .map((d) => (d['nome_dipendente'] ?? '').toString())
        .where((nome) => nome.isNotEmpty)
        .toList();
    setState(() {
      _dipendentiFiltrati = filtrati;
      _selectedDipendente = null;
    });
  }

  Future<void> _fetchTipiTurnoDaFoglio() async {
    final url = Uri.parse('${AppConfig.currentBaseUrl}/tipi_turno');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> turni = jsonDecode(response.body)["tipi_turno"];
        final List<Map<String, dynamic>> lista = [];
        for (var turno in turni) {
          final String nome = turno["nome"] ?? "";
          final orari = turno["orari"];
          String label = nome;
          String? oraInizio;
          String? oraFine;
          if (orari is List && orari.length >= 2) {
            oraInizio = orari[0];
            oraFine = orari[1];
            label = "$nome : $oraInizio-$oraFine";
          } else if (orari is String && orari.startsWith('[')) {
            try {
              final List<dynamic> parsed = jsonDecode(orari);
              if (parsed.length >= 2) {
                oraInizio = parsed[0];
                oraFine = parsed[1];
                label = "$nome : $oraInizio-$oraFine";
              }
            } catch (_) {}
          }
          lista.add({
            'label': label,
            'nomeTurno': nome,
            'orari': [oraInizio, oraFine],
          });
        }
        setState(() {
          _tipiTurnoDisponibili = lista;
        });
      } else {
        print("[DEBUG] Errore fetch tipi turno: ${response.body}");
      }
    } catch (e) {
      print("[DEBUG] Eccezione fetch tipi turno: $e");
    }
  }

  Future<void> _fetchDipendentiERuoli() async {
    final url = Uri.parse('${AppConfig.currentBaseUrl}/dipendenti');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final dipendenti = data['dipendenti'] as List<dynamic>;
      _dipendentiDisponibili = dipendenti.cast<Map<String, dynamic>>();
      final ruoli = <String>{};
      for (var d in _dipendentiDisponibili) {
        final ruolo = (d['ruolo'] ?? "").toString().trim();
        if (ruolo.isNotEmpty) ruoli.add(ruolo[0].toUpperCase() + ruolo.substring(1).toLowerCase());
      }
      setState(() {
        _ruoliDisponibili = ruoli.toList()..sort();
      });
    }
  }

  Future<void> _submitDataToBackend() async {
    if (_selectedMonth == null || _yearController.text.isEmpty) {
      setState(() => _errorMessage = 'Mese e Anno sono obbligatori.');
      return;
    }
    if (_turniDaInserire.isEmpty) {
      setState(() => _errorMessage = 'Nessun turno inserito.');
      return;
    }
    final int? anno = int.tryParse(_yearController.text);
    if (anno == null || anno < 2020 || anno > 2100) {
      setState(() => _errorMessage = 'Anno non valido.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final turniPayload = _formattaTurniPerBackend();
    if (turniPayload.isEmpty && _turniDaInserire.isNotEmpty) {
      setState(() {
        _errorMessage = "Errore nella formattazione dei turni. Controlla i giorni inseriti.";
        _isLoading = false;
      });
      return;
    }
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String? pinDaInviare = authProvider.pinFornitoAlLogin;
    if (pinDaInviare == null || pinDaInviare.isEmpty) {
      setState(() {
        _errorMessage = "Errore: PIN Admin mancante. Esci e rientra con login.";
        _isLoading = false;
      });
      return;
    }
    final requestBody = jsonEncode({
      'pin': pinDaInviare,
      'mese': _selectedMonth,
      'anno': anno,
      'turni': turniPayload,
    });

    print("[DEBUG] InserisciTurniScreen: Request body: $requestBody");

    try {
      final url = Uri.parse('$_baseUrl/inserisci_turni');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      ).timeout(Duration(seconds: 20));

      print("[DEBUG] InserisciTurniScreen: Response status: ${response.statusCode}");
      print("[DEBUG] InserisciTurniScreen: Response body: ${response.body}");
      if (!mounted) return;
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _successMessage = responseData['message'] ?? 'Turni inviati con successo!';
          _turniDaInserire.clear();
          _isLoading = false;
        });
      } else {
        setState(() {
          var detail = responseData['detail'];
          if (detail is List) {
            _errorMessage = detail.map((e) => e.toString()).join('\n');
          } else if (detail is String) {
            _errorMessage = detail;
          } else {
            _errorMessage = responseData['message'] ?? 'Errore invio turni.';
          }
          _isLoading = false;
        });
      }
    } catch (e, s) {
      print("[DEBUG] InserisciTurniScreen: ECCEZIONE: $e");
      print("[DEBUG] InserisciTurniScreen: StackTrace: $s");
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Errore di connessione o server: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Widget _buildTurniForm() {
    // MODIFICA: Otteniamo il tema e gli stili per usarli nel form.
    final theme = Theme.of(context);
    final inputTextStyle = TextStyle(color: theme.colorScheme.onPrimary, fontSize: 16);
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: theme.colorScheme.primary,
      labelStyle: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.7)),
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: inputDecoration.copyWith(labelText: 'Mese'),
                  dropdownColor: theme.colorScheme.surface,
                  value: _selectedMonth,
                  items: _mesiNomi.map((String mese) {
                    return DropdownMenuItem<String>(value: mese, child: Text(mese));
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() => _selectedMonth = newValue);
                  },
                  validator: (value) => value == null ? 'Seleziona un mese' : null,
                  style: inputTextStyle,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _yearController,
                  style: inputTextStyle,
                  decoration: inputDecoration.copyWith(labelText: 'Anno'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Inserisci l\'anno';
                    final year = int.tryParse(value);
                    if (year == null || year < 2020 || year > 2100) return 'Anno non valido';
                    return null;
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Text('Aggiungi Turno:', style: Theme.of(context).textTheme.titleLarge),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: inputDecoration.copyWith(labelText: 'Ruolo'),
                  dropdownColor: theme.colorScheme.surface,
                  value: _selectedRuolo,
                  items: _ruoliDisponibili.map((ruolo) {
                    return DropdownMenuItem<String>(value: ruolo, child: Text(ruolo));
                  }).toList(),
                  onChanged: (String? newRuolo) {
                    setState(() {
                      _selectedRuolo = newRuolo;
                      _filtraDipendentiPerRuolo(newRuolo);
                    });
                  },
                  validator: (value) => value == null ? 'Seleziona un ruolo' : null,
                  style: inputTextStyle,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: inputDecoration.copyWith(labelText: 'Dipendente'),
                  dropdownColor: theme.colorScheme.surface,
                  value: _selectedDipendente,
                  items: _dipendentiFiltrati.map((nome) {
                    return DropdownMenuItem<String>(value: nome, child: Text(nome));
                  }).toList(),
                  onChanged: (String? nuovoNome) {
                    setState(() {
                      _selectedDipendente = nuovoNome;
                    });
                  },
                  validator: (value) => value == null ? 'Seleziona un dipendente' : null,
                  style: inputTextStyle,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<Map<String, dynamic>>(
                  decoration: inputDecoration.copyWith(labelText: 'Tipo Turno'),
                  dropdownColor: theme.colorScheme.surface,
                  value: _currentTipoTurno,
                  items: _tipiTurnoDisponibili.map((turno) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: turno,
                      child: Text(turno['label'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (Map<String, dynamic>? newValue) => setState(() => _currentTipoTurno = newValue),
                  validator: (value) => value == null ? 'Seleziona tipo turno' : null,
                  style: inputTextStyle,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: _giorniController,
                  style: inputTextStyle,
                  decoration: inputDecoration.copyWith(labelText: 'Giorni (es. 1,2,5-7,10)'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Inserisci i giorni';
                    return null;
                  }
                ),
              ),
            ],
          ),

          SizedBox(height: 10),
          ElevatedButton.icon(
            icon: Icon(Icons.add),
            label: Text('Aggiungi Voce Turno'),
            onPressed: _aggiungiTurnoEntry,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary, // Colore di sfondo
              foregroundColor: theme.colorScheme.onPrimary, // Colore di testo e icona
            ),
          ),
          SizedBox(height: 20),
          Text('Turni da Inviare:', style: Theme.of(context).textTheme.titleLarge),
          _turniDaInserire.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical:8.0), child: Text('Nessun turno aggiunto.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: _turniDaInserire.length,
                  itemBuilder: (context, index) {
                    final entry = _turniDaInserire[index];
                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 4),
                      color: theme.colorScheme.primary, // Imposta lo sfondo della card
                      child: ListTile(
                        // Aggiunge lo stile per rendere il testo leggibile
                        title: Text('${entry.dipendente} - ${entry.tipoTurno}', style: TextStyle(color: theme.colorScheme.onPrimary)),
                        subtitle: Text('${_selectedMonth ?? ""}: ${entry.giorniNumerici.join(", ")}', style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.8))),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: theme.colorScheme.error),
                          onPressed: () => _rimuoviTurnoEntry(index),
                        ),
                      ),
                    );
                  },
                ),
          SizedBox(height: 20),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical:8.0),
              // MODIFICA: Colore testo errore preso dal tema.
              child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
            ),
          if (_successMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical:8.0),
              // MODIFICA: Colore testo successo preso dal tema.
              child: Text(_successMessage!, style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
            ),
          SizedBox(height: 10),
          if (_isLoading)
            Center(child: CircularProgressIndicator())
          else
            Center(
              child: ElevatedButton.icon(
                // MODIFICA: Colori bottone presi dal tema.
                icon: Icon(Icons.calendar_today, color: theme.colorScheme.onSecondary),
                label: Text(
                  'Invia Turni al Calendario',
                  style: TextStyle(color: theme.colorScheme.onSecondary, fontSize: 16)
                ),
                onPressed: _turniDaInserire.isNotEmpty ? _submitDataToBackend : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
              ),
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print("[DEBUG] InserisciTurniScreen: Build UI.");
    return Scaffold(
      appBar: AppBar(
        title: Text('Inserisci Turni'),
        actions: [
          IconButton(
            icon: Icon(Icons.lock_reset),
            tooltip: 'Resetta Form',
            onPressed: () {
              setState(() {
                _isLoading = false;
                _errorMessage = null;
                _successMessage = null;
                _turniDaInserire.clear();
                _currentTipoTurno = null;
                _giorniController.clear();
                _selectedMonth = _mesiNomi[DateTime.now().month - 1];
                _yearController.text = DateTime.now().year.toString();
                _selectedRuolo = null;
                _selectedDipendente = null;
                _dipendentiFiltrati = [];
              });
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _buildTurniForm(),
      ),
    );
  }
}