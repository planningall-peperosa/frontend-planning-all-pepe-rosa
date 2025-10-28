import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../models/evento_calendario.dart';
import '../providers/calendario_eventi_provider.dart';
import 'crea_preventivo_screen.dart'; // Per navigare alla modifica

// Helper per table_calendar
bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}


class EventCalendarScreen extends StatefulWidget {
  const EventCalendarScreen({super.key});

  @override
  State<EventCalendarScreen> createState() => _EventCalendarScreenState();
}

class _EventCalendarScreenState extends State<EventCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final CalendarFormat _calendarFormat = CalendarFormat.month;

  // 🚨 LINEA CHIAVE: Tonalità del colore rosa pastello per gli eventi
  final Color _eventDayColor = const Color(0xFFF4C4D7); 
  // 🚨 NUOVO COLORE: Grigio medio per il weekend (ad esempio #E0E0E0)
  final Color _weekendDayColor = const Color(0xFFE0E0E0); 

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  // --- FUNZIONE: TORNA AL MESE CORRENTE ---
  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedDay = now;
      _selectedDay = now;
    });
  }

  // Helper per table_calendar
  List<EventoCalendario> _getEventsForDay(DateTime day) {
    final provider = context.read<CalendarioEventiProvider>();
    return provider.getEventsForDay(day);
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }
  }

  // Funzione helper per ottenere il colore del pallino in base allo stato
  Color _getMarkerColor(EventoCalendario evento) {
    // CONTROLLO SICURO: pulisce e mette in minuscolo solo per il confronto
    final cleanedStato = evento.stato.trim().toLowerCase();
    
    if (cleanedStato == 'confermato') {
      return Colors.green.shade600;
    }
    // Se è "bozza" o qualsiasi altra cosa, è rosso.
    return Colors.red.shade600;
  }
  
  // Funzione helper per capitalizzare la prima lettera di una stringa
  String _capitalize(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);


  @override
  Widget build(BuildContext context) {
    // Verifichiamo se il mese visualizzato è il mese attuale
    final isCurrentMonth = _focusedDay.year == DateTime.now().year && _focusedDay.month == DateTime.now().month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario Eventi'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Consumer<CalendarioEventiProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.eventiGrouped.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.pink));
          }

          final selectedEvents = _getEventsForDay(_selectedDay ?? DateTime.now());

          return Column(
            children: [
              // --- MODIFICA CHIAVE 1: Rimuovi la label del mese e lascia solo il pulsante ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  // Centra gli elementi (o li sposta a destra)
                  mainAxisAlignment: isCurrentMonth ? MainAxisAlignment.end : MainAxisAlignment.end,
                  children: [
                    // Rimosso il Text(currentMonthYear) che duplicava il titolo del calendario.
                    
                    // Mostra il pulsante "Oggi" solo se non è già il mese corrente
                    if (!isCurrentMonth)
                      ElevatedButton(
                        onPressed: _goToToday,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.secondary,
                          foregroundColor: Theme.of(context).colorScheme.onSecondary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Oggi',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
              // --- CALENDARIO ---
              TableCalendar<EventoCalendario>(
                // Rimosso key
                locale: 'it_IT',
                firstDay: DateTime.utc(2023, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _calendarFormat, 
                eventLoader: _getEventsForDay,
                
                // Inizio settimana Lunedì
                startingDayOfWeek: StartingDayOfWeek.monday,
                
                // Stili e Intestazione
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false, 
                  titleCentered: true,
                  // titleVisible: false, rimosso precedentemente perché non supportato.
                ),
                
                // CALENDAR STYLE
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: true,
                  outsideTextStyle: TextStyle(color: Colors.black87), 
                ),
                
                // Implementazione Colore Weekend, Eventi (celle) e MARKER (pallino/rettangolo)
                calendarBuilders: CalendarBuilders(
                  
                  // BUILDER MARKER: Rettangolo
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) {
                      return null;
                    }

                    // Costruisce una lista di rettangoli, uno per ogni evento
                    return Positioned(
                      bottom: 7.0, 
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: events.map((event) {
                          // CHIAMATA AL METODO PER OTTENERE IL COLORE IN BASE ALLO STATO
                          Color markerColor = _getMarkerColor(event);

                          return Container(
                            width: 15.0, 
                            height: 10.0, 
                            margin: const EdgeInsets.symmetric(horizontal: 1.0), 
                            decoration: BoxDecoration(
                              color: markerColor, 
                              shape: BoxShape.rectangle, 
                              borderRadius: BorderRadius.circular(2.0), // Bordo leggermente arrotondato
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                  
                  // Per i giorni del mese precedente/successivo
                  outsideBuilder: (context, day, focusedDay) {
                    final events = _getEventsForDay(day);
                    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
                    
                    Color bgColor;
                    
                    if (events.isNotEmpty) {
                      bgColor = _eventDayColor; // Rosa per eventi
                    } 
                    else if (isWeekend) {
                      bgColor = _weekendDayColor; 
                    } 
                    else {
                      bgColor = Colors.white; 
                    }
                    
                    return Container(
                      margin: const EdgeInsets.all(6.0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        '${day.day}',
                        // 🔑 MODIFICATO: Aumento font size
                        style: const TextStyle(color: Colors.black54, fontSize: 16.0), 
                      ),
                    );
                  },
                  
                  // Per i giorni del mese attuale (non selezionati e non "oggi")
                  defaultBuilder: (context, day, focusedDay) {
                    final isSelected = isSameDay(_selectedDay, day);
                    final isToday = isSameDay(DateTime.now(), day);

                    if (isSelected || isToday) return null; 
                    
                    final events = _getEventsForDay(day);
                    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
                    
                    Color bgColor;
                    
                    if (events.isNotEmpty) {
                      bgColor = _eventDayColor; // Rosa per eventi
                    } else if (isWeekend) {
                      bgColor = _weekendDayColor; // Grigio per weekend
                    } else {
                      bgColor = Colors.white; 
                    }
                    
                    return Container(
                      margin: const EdgeInsets.all(6.0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        '${day.day}',
                        // 🔑 MODIFICATO: Aumento font size
                        style: const TextStyle(color: Colors.black87, fontSize: 16.0),
                      ),
                    );
                  },

                  // selectedBuilder: Bordo visibile, sfondo corretto (come richiesto)
                  selectedBuilder: (context, day, focusedDay) {
                    final events = _getEventsForDay(day);
                    final isEventDay = events.isNotEmpty;
                    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

                    Color bgColor = Colors.white; // Default: bianco per giorni feriali
                    
                    if (isEventDay) {
                        bgColor = _eventDayColor; 
                    } else if (isWeekend) {
                        bgColor = _weekendDayColor; // Colore weekend
                    }
                    
                    return Container(
                      margin: const EdgeInsets.all(6.0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bgColor, 
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.pink.shade700, width: 2.0), 
                      ),
                      child: Text(
                        '${day.day}',
                        // 🔑 MODIFICATO: Aumento font size
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16.0),
                      ),
                    );
                  },

                  // todayBuilder: Mantiene lo stile per oggi (con bordo)
                  todayBuilder: (context, day, focusedDay) {
                      final events = _getEventsForDay(day);
                      final isEventDay = events.isNotEmpty;
                      final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

                      Color baseColor = Theme.of(context).colorScheme.secondary.withOpacity(0.3);
                      
                      if (isEventDay) {
                          baseColor = _eventDayColor; 
                      } else if (isWeekend) {
                          baseColor = _weekendDayColor; // Colore weekend
                      } else {
                          // Giorno feriale senza eventi: mantiene il colore Today leggermente opaco.
                      }

                      return Container(
                        margin: const EdgeInsets.all(6.0),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: baseColor, 
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.pink.shade700, width: 1.0), 
                        ),
                        child: Text(
                          '${day.day}',
                          // 🔑 MODIFICATO: Aumento font size
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16.0),
                        ),
                      );
                   },
                ),
                
                // Funzione di selezione
                onDaySelected: _onDaySelected,
                // L'aggiornamento di _focusedDay è qui e forza il ri-render
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                  });
                },
              ),
              
              const Divider(height: 1),

              // --- LISTA EVENTI SELEZIONATI ---
              Expanded(
                child: selectedEvents.isEmpty
                    ? Center(child: Text('Nessun evento per il ${DateFormat('dd/MM/yyyy').format(_selectedDay!)}.'))
                    : ListView.builder(
                        itemCount: selectedEvents.length,
                        itemBuilder: (context, index) {
                          final evento = selectedEvents[index];
                          
                          // Pulizia per la visualizzazione e il colore
                          final cleanedStatoForColor = evento.stato.trim().toLowerCase();
                          final displayStato = _capitalize(evento.stato.trim());
                          
                          // Tipo pasto in MAIUSCOLO per visualizzazione
                          final displayTipoPasto = evento.tipoPasto.toUpperCase();
                          
                          final statoColor = cleanedStatoForColor == 'confermato' ? Colors.green.shade600 : Colors.red.shade600;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(evento.tipoPasto.isNotEmpty ? evento.tipoPasto[0].toUpperCase() : 'E'), 
                              ),
                              title: Text(evento.nomeEvento),
                              subtitle: RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
                                  children: <TextSpan>[
                                    TextSpan(
                                      text: '$displayStato',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: statoColor),
                                    ),
                                    // Aggiunti 2 spazi attorno a | e uso di displayTipoPasto MAIUSCOLO
                                    TextSpan(text: '  |  Tipo: $displayTipoPasto  |  Ospiti: ${evento.numeroOspiti}  |  Cliente: ${evento.clienteNome}'),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                // Naviga alla schermata di modifica del preventivo
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CreaPreventivoScreen(preventivoId: evento.id),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}