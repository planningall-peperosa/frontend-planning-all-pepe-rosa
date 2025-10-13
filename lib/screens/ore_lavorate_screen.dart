import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Per AuthProvider
import '../services/ore_lavorate_service.dart';
import '../providers/auth_provider.dart';


// Modello per le richieste
class ReportRequest {
  final String nomeDipendente;
  final DateTime dataInizio;
  final DateTime dataFine;

  ReportRequest({
    required this.nomeDipendente,
    required this.dataInizio,
    required this.dataFine,
  });
}

// NUOVO: Modello più flessibile per il riepilogo dei turni
class TurnoSummary {
  final Map<String, int> tipiTurno;
  final int sabati;
  final int domeniche;

  TurnoSummary({
    required this.tipiTurno,
    this.sabati = 0,
    this.domeniche = 0,
  });
}

class OreLavorateScreen extends StatefulWidget {
  const OreLavorateScreen({Key? key}) : super(key: key);

  @override
  _OreLavorateScreenState createState() => _OreLavorateScreenState();
}

class _OreLavorateScreenState extends State<OreLavorateScreen> {
  final OreLavorateService _oreLavorateService = OreLavorateService();

  // Stato UI
  bool _isLoadingDipendenti = true;
  bool _isCalculating = false;
  String? _errorMessage;
  bool _mostraSoloRisultati = false; 

  // Dati per i filtri
  List<Map<String, dynamic>> _dipendentiDisponibili = [];
  List<String> _ruoliDisponibili = [];
  List<String> _dipendentiFiltrati = [];
  String? _selectedRuolo;
  String? _selectedDipendente;
  DateTime _dataInizio = DateTime.now().subtract(const Duration(days: 30));
  DateTime _dataFine = DateTime.now();

  // Liste per richieste e risultati
  final List<ReportRequest> _richiesteDaCalcolare = [];
  List<Map<String, dynamic>> _risultatiReport = [];


  @override
  void initState() {
    super.initState();
    _fetchDipendentiERuoli();
  }

  Future<void> _fetchDipendentiERuoli() async {
    try {
      final dipendenti = await _oreLavorateService.getDipendenti();
      if (mounted) {
        final ruoli = <String>{};
        _dipendentiDisponibili = dipendenti.where((d) => d['nome_dipendente'] != null && d['nome_dipendente'].isNotEmpty).toList();
        
        for (var d in _dipendentiDisponibili) {
          final ruolo = (d['ruolo'] ?? "").toString().trim();
          if (ruolo.isNotEmpty) {
            ruoli.add(ruolo[0].toUpperCase() + ruolo.substring(1).toLowerCase());
          }
        }

        setState(() {
          _ruoliDisponibili = ruoli.toList()..sort();
          _isLoadingDipendenti = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Errore caricamento dipendenti: ${e.toString()}";
          _isLoadingDipendenti = false;
        });
      }
    }
  }

  void _filtraDipendentiPerRuolo(String? ruolo) {
    if (ruolo == null || ruolo.isEmpty) {
      setState(() {
        _dipendentiFiltrati = [];
        _selectedDipendente = null;
      });
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

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _dataInizio : _dataFine,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _dataInizio = picked;
        } else {
          _dataFine = picked;
        }
      });
    }
  }
  
  void _aggiungiRichiestaAlReport() {
    if (_selectedDipendente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un ruolo e un dipendente.')),
      );
      return;
    }
    
    bool esisteGia = _richiesteDaCalcolare.any((req) => 
        req.nomeDipendente == _selectedDipendente &&
        req.dataInizio.isAtSameMomentAs(_dataInizio) &&
        req.dataFine.isAtSameMomentAs(_dataFine));

    if (esisteGia) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questa richiesta è già stata aggiunta alla lista.')),
      );
      return;
    }

    setState(() {
      _richiesteDaCalcolare.add(ReportRequest(
        nomeDipendente: _selectedDipendente!,
        dataInizio: _dataInizio,
        dataFine: _dataFine,
      ));
    });
  }

  Future<void> _generaReportMultiplo() async {
    if (_richiesteDaCalcolare.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.pinFornitoAlLogin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN admin non trovato. Esegui nuovamente il login.')),
      );
      return;
    }

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
      _risultatiReport = [];
    });

    List<Map<String, dynamic>> risultatiTemporanei = [];
    String? erroreGlobale;

    for (final richiesta in _richiesteDaCalcolare) {
      try {
        final risultato = await _oreLavorateService.calcolaOre(
          pin: authProvider.pinFornitoAlLogin!,
          nomeDipendente: richiesta.nomeDipendente,
          dataInizio: DateFormat('yyyy-MM-dd').format(richiesta.dataInizio),
          dataFine: DateFormat('yyyy-MM-dd').format(richiesta.dataFine),
        );
        risultatiTemporanei.add(risultato);
      } catch (e) {
        erroreGlobale = "Errore durante il calcolo per ${richiesta.nomeDipendente}: ${e.toString().replaceFirst("Exception: ", "")}";
        break;
      }
    }

    if (mounted) {
      setState(() {
        if (erroreGlobale != null) {
          _errorMessage = erroreGlobale;
        } else {
          _risultatiReport = risultatiTemporanei;
          _mostraSoloRisultati = true;
        }
        _isCalculating = false;
      });
    }
  }

  void _iniziaNuovoCalcolo() {
    setState(() {
      _richiesteDaCalcolare.clear();
      _risultatiReport.clear();
      _errorMessage = null;
      _mostraSoloRisultati = false;
    });
  }

  TurnoSummary _calcolaRiepilogoTurni(List<dynamic> turni) {
    final Map<String, int> tipiTurno = {};
    int sabati = 0;
    int domeniche = 0;

    for (var turno in turni) {
      final orarioInizio = turno['orario_inizio'] as String?;
      final orarioFine = turno['orario_fine'] as String?;
      if (orarioInizio != null && orarioFine != null) {
        final tipoOrario = "$orarioInizio - $orarioFine";
        tipiTurno[tipoOrario] = (tipiTurno[tipoOrario] ?? 0) + 1;
      }

      try {
        final dataTurno = DateFormat('dd/MM/yyyy').parse(turno['data']);
        if (dataTurno.weekday == DateTime.saturday) {
          sabati++;
        }
        if (dataTurno.weekday == DateTime.sunday) {
          domeniche++;
        }
      } catch (e) {
        print("Errore parsing data per conteggio giorno settimana: ${turno['data']}");
      }
    }
    return TurnoSummary(tipiTurno: tipiTurno, sabati: sabati, domeniche: domeniche);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calcolo Ore Dipendenti'),
        leading: _mostraSoloRisultati
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Torna al calcolo',
                onPressed: _iniziaNuovoCalcolo,
              )
            : null,
        actions: const [],
      ),
      body: _isLoadingDipendenti
          ? const Center(child: CircularProgressIndicator())
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    if (_mostraSoloRisultati) {
      return _buildVistaRisultati();
    } else {
      return _buildVistaPreparazione();
    }
  }
  
  Widget _buildVistaPreparazione() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildFiltriCard(),
          const SizedBox(height: 12),
          Expanded(child: _buildListaRichieste()),
          const SizedBox(height: 12),
          if (_richiesteDaCalcolare.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Genera Report'),
              onPressed: _isCalculating ? null : _generaReportMultiplo,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.onSecondary,
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          if (_isCalculating)
            const Padding(
              padding: EdgeInsets.only(top: 16.0),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildVistaRisultati() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: _isCalculating
          ? const Center(child: CircularProgressIndicator())
          : _buildRisultati(),
    );
  }

  Widget _buildFiltriCard() {
    final theme = Theme.of(context);
    final inputTextStyle = TextStyle(color: theme.colorScheme.onSurface, fontSize: 16);
    final inputDecoration = InputDecoration(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Card(
      color: theme.colorScheme.primary,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: inputDecoration.copyWith(labelText: 'Ruolo', fillColor: theme.colorScheme.surface),
                    dropdownColor: theme.colorScheme.surface,
                    value: _selectedRuolo,
                    items: _ruoliDisponibili.map((ruolo) => DropdownMenuItem<String>(value: ruolo, child: Text(ruolo, style: inputTextStyle))).toList(),
                    onChanged: (value) => setState(() { _selectedRuolo = value; _filtraDipendentiPerRuolo(value); }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: inputDecoration.copyWith(labelText: 'Dipendente', fillColor: _selectedRuolo == null ? theme.disabledColor : theme.colorScheme.surface),
                    dropdownColor: theme.colorScheme.surface,
                    value: _selectedDipendente,
                    onChanged: _selectedRuolo == null ? null : (value) => setState(() => _selectedDipendente = value),
                    items: _dipendentiFiltrati.map((nome) => DropdownMenuItem<String>(value: nome, child: Text(nome, style: inputTextStyle))).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildDateField("Da:", _dataInizio, true)),
                const SizedBox(width: 12),
                Expanded(child: _buildDateField("A:", _dataFine, false)),
              ],
            ),
            const SizedBox(height: 8),
            _buildBarraDateNavigator(),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Aggiungi al Report'),
              onPressed: _isCalculating ? null : _aggiungiRichiestaAlReport,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaRichieste() {
    final theme = Theme.of(context);
    if (_richiesteDaCalcolare.isEmpty) {
      // MODIFICA: Usiamo onBackground per il testo su sfondo scuro
      return Center(child: Text('Aggiungi una o più richieste per generare un report.', style: TextStyle(color: theme.colorScheme.onBackground)));
    }
    return ListView.builder(
      itemCount: _richiesteDaCalcolare.length,
      itemBuilder: (context, index) {
        final richiesta = _richiesteDaCalcolare[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title: Text(richiesta.nomeDipendente),
            subtitle: Text('Periodo: ${DateFormat('dd/MM/yy').format(richiesta.dataInizio)} - ${DateFormat('dd/MM/yy').format(richiesta.dataFine)}'),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: _isCalculating ? null : () => setState(() => _richiesteDaCalcolare.removeAt(index)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRisultati() {
    final theme = Theme.of(context);
    if (_errorMessage != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(8.0), child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error, fontSize: 16), textAlign: TextAlign.center)));
    }
    if (_risultatiReport.isEmpty) {
      // MODIFICA: Usiamo onBackground per il testo su sfondo scuro
      return Center(child: Text("Nessun risultato da mostrare.", style: TextStyle(color: theme.colorScheme.onBackground)));
    }
    return ListView.builder(
      itemCount: _risultatiReport.length,
      itemBuilder: (context, index) {
        final report = _risultatiReport[index];
        return _buildSingoloReportCard(report);
      },
    );
  }

  Widget _buildSingoloReportCard(Map<String, dynamic> reportData) {
    final theme = Theme.of(context);
    final List<dynamic> reportDettagliato = reportData['report_dettagliato'] ?? [];
    final summary = _calcolaRiepilogoTurni(reportDettagliato);

    // Definiamo stili di testo bianchi per la leggibilità sulla card fucsia
    final onPrimaryTextStyle = TextStyle(color: theme.colorScheme.onPrimary);
    final onPrimaryBoldTextStyle = TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 13);
    final onPrimaryLightTextStyle = TextStyle(color: theme.colorScheme.onPrimary, fontSize: 14);

    return Card(
      // MODIFICA: La card ora usa il colore primario del tema.
      color: theme.colorScheme.primary,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            _buildRiepilogo(reportData, onPrimary: true), // Passiamo un flag per lo stile
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Divider(height: 1, color: theme.colorScheme.onPrimary.withOpacity(0.2)),
            ),
            _buildTurnoSummaryWidget(summary),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Divider(height: 1, color: theme.colorScheme.onPrimary.withOpacity(0.2)),
            ),
            if (reportDettagliato.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Nessun turno trovato in questo periodo.', style: onPrimaryTextStyle),
              )
            else
              ...reportDettagliato.map((turno) {
                String giorno = "";
                String mese = "";
                try {
                  final dataTurno = DateFormat('dd/MM/yyyy').parse(turno['data']);
                  giorno = DateFormat('d').format(dataTurno);
                  mese = DateFormat('MMM', 'it_IT').format(dataTurno).toUpperCase();
                } catch (e) {
                  giorno = turno['data'].substring(0, 2);
                  mese = "ERR";
                }

                return ListTile(
                  leading: CircleAvatar(
                    // Sfondo più chiaro per contrasto
                    backgroundColor: theme.colorScheme.surface,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(giorno, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary)),
                        Text(mese, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                  title: Text(turno['titolo_evento'] ?? 'Turno', style: onPrimaryLightTextStyle),
                  subtitle: Text('Dalle ${turno['orario_inizio']} alle ${turno['orario_fine']}', style: onPrimaryTextStyle.copyWith(fontSize: 12)),
                  trailing: Text(
                    turno['durata_formattata'] ?? '',
                    style: onPrimaryBoldTextStyle,
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnoSummaryWidget(TurnoSummary summary) {
    final theme = Theme.of(context);
    final tipiOrarioOrdinati = summary.tipiTurno.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    // Stili per i Chip sulla card fucsia
    final chipStyle = TextStyle(color: theme.colorScheme.primary);
    final chipAvatarStyle = TextStyle(color: theme.colorScheme.surface, fontSize: 12);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: [
          ...tipiOrarioOrdinati.map((tipo) => Chip(
            backgroundColor: theme.colorScheme.surface,
            avatar: CircleAvatar(backgroundColor: theme.colorScheme.secondary, child: Text('${summary.tipiTurno[tipo]}', style: chipAvatarStyle)),
            label: Text(tipo, style: chipStyle),
          )),
          if (summary.sabati > 0)
            Chip(
              backgroundColor: theme.colorScheme.surface,
              avatar: CircleAvatar(backgroundColor: theme.colorScheme.secondary, child: Text('${summary.sabati}', style: chipAvatarStyle)),
              label: Text('Sabato', style: chipStyle),
            ),
          if (summary.domeniche > 0)
            Chip(
              backgroundColor: theme.colorScheme.surface,
              avatar: CircleAvatar(backgroundColor: theme.colorScheme.secondary, child: Text('${summary.domeniche}', style: chipAvatarStyle)),
              label: Text('Domenica', style: chipStyle),
            ),
        ],
      ),
    );
  }

  Widget _buildRiepilogo(Map<String, dynamic> reportData, {bool onPrimary = false}) {
    final theme = Theme.of(context);
    // Scegliamo il set di colori in base al background
    final textColor = onPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final totalColor = onPrimary ? theme.colorScheme.surface : theme.colorScheme.secondary;

    String periodoDaMostrare = '';
    final String? periodoOriginale = reportData['periodo'];

    if (periodoOriginale != null) {
      try {
        final parts = periodoOriginale.split(' al ');
        final fromStr = parts[0].replaceAll('Dal ', '');
        final toStr = parts[1];
        final fromDate = DateTime.parse(fromStr);
        final toDate = DateTime.parse(toStr);

        final int giorniTotali = toDate.difference(fromDate).inDays + 1;
        final String giorniLabel = giorniTotali == 1 ? 'giorno' : 'giorni';

        final formatter = DateFormat('dd/MM/yy', 'it_IT');
        final fromFormatted = formatter.format(fromDate);
        final toFormatted = formatter.format(toDate);

        periodoDaMostrare = 'Dal $fromFormatted al $toFormatted ($giorniTotali $giorniLabel)';
      } catch (e) {
        periodoDaMostrare = periodoOriginale;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reportData['nome_dipendente'] ?? 'N/D',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  periodoDaMostrare,
                  style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Totale',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textColor.withOpacity(0.8)),
                ),
                Text(
                  reportData['totale_ore_formattato'] ?? '0 ore',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: totalColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(String label, DateTime date, bool isStartDate) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _selectDate(context, isStartDate),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: theme.colorScheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        child: Text(
          DateFormat('dd/MM/yyyy', 'it_IT').format(date),
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildBarraDateNavigator() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.arrow_left),
              label: const Text("Indietro"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
                elevation: 2,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                setState(() {
                  final prevMonth = DateTime(_dataInizio.year, _dataInizio.month - 1, 1);
                  final lastDayPrevMonth = DateTime(prevMonth.year, prevMonth.month + 1, 0);
                  _dataInizio = DateTime(prevMonth.year, prevMonth.month, 1);
                  _dataFine = DateTime(lastDayPrevMonth.year, lastDayPrevMonth.month, lastDayPrevMonth.day);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.today),
              label: Text("${toBeginningOfSentenceCase(DateFormat.MMMM('it_IT').format(DateTime.now()))}"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary.withOpacity(0.8),
                foregroundColor: theme.colorScheme.onSecondary,
                elevation: 2,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                setState(() {
                  final now = DateTime.now();
                  _dataInizio = DateTime(now.year, now.month, 1);
                  _dataFine = now;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.arrow_right),
              label: const Text("Avanti"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
                elevation: 2,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                setState(() {
                  final nextMonth = DateTime(_dataInizio.year, _dataInizio.month + 1, 1);
                  final lastDayNextMonth = DateTime(nextMonth.year, nextMonth.month + 1, 0);
                  _dataInizio = DateTime(nextMonth.year, nextMonth.month, 1);
                  _dataFine = DateTime(lastDayNextMonth.year, lastDayNextMonth.month, lastDayNextMonth.day);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

}