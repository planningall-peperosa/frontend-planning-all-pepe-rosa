// lib/main.dart
import 'dart:ui';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart'; // 👈 Aggiunto
// --- ALIAS CRUCIALI ---
import 'package:provider/provider.dart' as AppProvider; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
// --- FINE ALIAS ---

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'dart:async';

// --- AGGIUNTE FIREBASE ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'firebase_options.dart';
// --- FINE AGGIUNTE ---

import 'config/app_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

// 🔑 Import del tuo AuthProvider con prefisso AppAuth
import 'providers/auth_provider.dart' as AppAuth; 
import 'providers/log_provider.dart';
import 'providers/dipendenti_provider.dart';
import 'providers/turni_provider.dart';
import 'providers/menu_provider.dart';
import 'providers/clienti_provider.dart';
import 'providers/preventivi_provider.dart';
import 'providers/servizi_provider.dart';
import 'providers/preventivo_builder_provider.dart';

import 'screens/inserisci_turni_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/administration_menu_screen.dart';
import 'screens/crea_preventivo_screen.dart';
import 'screens/archivio_preventivi_screen.dart';
import 'screens/bilancio_screen.dart'; 

import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';

import 'widgets/logo_widget.dart'; 
import 'config/app_theme_dark.dart';

import 'package:fic_frontend/providers/piatti_provider.dart';
import 'package:fic_frontend/providers/menu_templates_provider.dart';

import 'features/segretario/segretario_page.dart';
import 'screens/cerca_cliente_screen.dart';

import 'providers/settings_provider.dart';
import 'providers/segretario_provider.dart';
import 'providers/calendario_eventi_provider.dart';
import 'screens/event_calendar_screen.dart';

import 'providers/pacchetti_eventi_provider.dart';


final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      print(details.exceptionAsString());
      if (details.stack != null) print(details.stack);
    }
  };

  await initializeDateFormatting('it_IT', null);
  await AppConfig.loadEnvironment();

  runApp(
    ProviderScope(
      child: AppProvider.MultiProvider(
        providers: [
          AppProvider.ChangeNotifierProvider(create: (context) => AppAuth.AuthProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => LogProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => TurniProvider()),
          AppProvider.ChangeNotifierProvider(create: (ctx) => DipendentiProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => MenuProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => ClientiProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => PreventiviProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => ServiziProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => PreventivoBuilderProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => PiattiProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => MenuTemplatesProvider()),
          AppProvider.ChangeNotifierProvider(create: (context) => SettingsProvider()..load()),
          AppProvider.ChangeNotifierProvider(create: (_) => SegretarioProvider()),
          AppProvider.ChangeNotifierProvider(create: (_) => CalendarioEventiProvider()),
          AppProvider.ChangeNotifierProvider(create: (_) => PacchettiEventiProvider()),
        ],
        child: MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'planning_all-pepe_rosa',
      theme: appTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', ''),
      ],
      builder: (context, child) {
        Widget wrapped = SafeArea(
          top: false,
          bottom: true,
          child: child ?? const SizedBox.shrink(),
        );
        if (kDebugMode && AppConfig.isDevelopmentEnv) {
          wrapped = Banner(
            message: "DEV",
            location: BannerLocation.topStart,
            color: Colors.orange.withOpacity(0.9),
            child: wrapped,
          );
        }
        return wrapped;
      },
      home: const AuthGate(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final ScrollController _logScrollController = ScrollController();
  Timer? _sessionTimer;
  DateTime? _loginTime;
  late final AppAuth.AuthProvider _authProvider; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authProvider = AppProvider.Provider.of<AppAuth.AuthProvider>(context, listen: false); 
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kDebugMode && AppConfig.isDevelopmentEnv) {
        final logProvider = AppProvider.Provider.of<LogProvider>(context, listen: false);
        logProvider.addLog("Ambiente: ${AppConfig.currentEnvironment.name.toUpperCase()}");
      }
      _setupLoginSession();
    });
  }

  void _setupLoginSession() {
    if (_authProvider.isAuthenticated) {
      _loginTime = DateTime.now();
      _startSessionTimer();
    }
    _authProvider.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_authProvider.isAuthenticated) {
      _loginTime = DateTime.now();
      _startSessionTimer();
    } else {
      _sessionTimer?.cancel();
      _loginTime = null;
    }
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_loginTime == null) return;
      final diff = DateTime.now().difference(_loginTime!);
      if (diff >= const Duration(hours: 2) && _authProvider.isAuthenticated) {
        _authProvider.logout();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logScrollController.dispose();
    _authProvider.removeListener(_onAuthChanged);
    _sessionTimer?.cancel();
    super.dispose();
  }

  // 🔹 Apertura preventivo
  void _openPreventivo(String idPreventivo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreaPreventivoScreen(preventivoId: idPreventivo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      drawer: _buildDrawer(context),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          Text(
            'Prossimi eventi',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          ProssimiEventiList(),
          SizedBox(height: 24),
          Center(child: Padding(padding: EdgeInsets.all(16.0), child: LogoWidget())),
        ],
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: AppProvider.Consumer<AppAuth.AuthProvider>(
        builder: (context, authProvider, _) {
          final menuVoci = [
            {"nome": "Calendario Eventi", "icon": Icons.calendar_month, "widget": const EventCalendarScreen()},
            {"nome": "Preventivi", "icon": Icons.inventory_2_outlined, "widget": const ArchivioPreventiviScreen()},
            {"nome": "Segretario", "icon": Icons.checklist_rounded, "widget": SegretarioPage()},
            {"nome": "Bilancio", "icon": Icons.account_balance, "widget": const BilancioScreen()},
            {"nome": "Contatti", "icon": Icons.contacts_rounded, "widget": const CercaClienteScreen()},
            {"nome": "Setup", "icon": Icons.settings, "widget": SetupScreen()},
          ];

          List<Widget> menuTiles = [];
          for (final voce in menuVoci) {
            if (authProvider.userRuolo == 'admin' || authProvider.isFunzioneAutorizzata(voce["nome"].toString())) {
              menuTiles.add(ListTile(
                leading: Icon(voce["icon"] as IconData, color: Colors.black),
                title: Text(voce["nome"].toString(), style: const TextStyle(color: Colors.black)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => voce["widget"] as Widget));
                },
              ));
            }
          }
          menuTiles.add(const Divider(color: Colors.black));
          menuTiles.add(ListTile(
            leading: const Icon(Icons.logout, color: Colors.black),
            title: const Text('Logout', style: TextStyle(color: Colors.black)),
            onTap: () {
              AppProvider.Provider.of<AppAuth.AuthProvider>(context, listen: false).logout();
            },
          ));

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(color: Colors.white),
                child: Text('Menu Principale', style: TextStyle(color: Colors.black, fontSize: 24)),
              ),
              const Divider(color: Colors.black, height: 1, thickness: 1),
              ...menuTiles,
            ],
          );
        },
      ),
    );
  }  
}


// Estrae SOLO la ragione sociale del cliente dai vari formati possibili
String _estraiRagioneSociale(Map<String, dynamic> data) {
  // 1) campi diretti
  final direct = data['ragione_sociale'] ?? data['cliente_nome'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();

  // 2) oggetto annidato "cliente"
  final c = data['cliente'];
  if (c is Map) {
    final m = Map<String, dynamic>.from(c);
    final cand = m['ragione_sociale'] ?? m['ragioneSociale'] ?? m['nome'] ?? m['ragione'];
    if (cand is String && cand.trim().isNotEmpty) return cand.trim();
  } else if (c is String) {
    // 3) fallback: prova a pescare "ragione sociale" da una stringa lunga
    final match = RegExp(r'ragione[_ ]?sociale\s*[:=]\s*([^,}\n]+)', caseSensitive: false).firstMatch(c);
    if (match != null) return match.group(1)!.trim();
  }

  return '';
}



// === NEW: estrae il nome del pacchetto fisso direttamente dal documento preventivo ===
String _estraiNomePacchettoFisso(Map<String, dynamic> data) {
  // 1) chiavi dirette testate in app e provider
  final keysDirette = [
    'pacchetto_evento_nome',
    'nome_pacchetto',
    'pacchetto_nome',
    'nomePacchetto',
    'nomePacchettoFisso',
    'pacchetto',            // alcuni salvataggi usano semplicemente "pacchetto": "Kids party"
    'tipo_evento',          // a volte usato per il label del pacchetto
    'tipoEvento',
  ];
  for (final k in keysDirette) {
    final v = data[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }

  // 2) mappa annidata
  final nested = data['pacchetto_evento'];
  if (nested is Map) {
    final m = nested.cast<String, dynamic>();
    final n = m['nome_evento'] ?? m['nome'] ?? m['titolo'];
    if (n is String && n.trim().isNotEmpty) return n.trim();
  }

  return '';
}



// --- helper per estrarre la dicitura tipo evento (pranzo/cena o nome pacchetto) ---
String estraiTipoEvento(Map<String, dynamic> data) {
  // A) Se è un menù a portate (campo "tipo_pasto" o "tipoPasto")
  final tipoPasto = data['tipo_pasto'] ?? data['tipoPasto'];
  if (tipoPasto is String && tipoPasto.trim().isNotEmpty) {
    return tipoPasto.toLowerCase().contains('pranzo')
        ? 'Pranzo'
        : tipoPasto.toLowerCase().contains('cena')
            ? 'Cena'
            : tipoPasto;
  }

  // B) Se è un menù a pacchetto (campo "pacchetto_evento" o "pacchetto")
  final pacchetto = data['pacchetto_evento'] ?? data['pacchetto'];
  if (pacchetto is Map) {
    final nomePacchetto = pacchetto['nome_evento'] ?? pacchetto['nome'] ?? pacchetto['titolo'];
    if (nomePacchetto is String && nomePacchetto.trim().isNotEmpty) {
      return nomePacchetto.trim();
    }
  } else if (pacchetto is String && pacchetto.trim().isNotEmpty) {
    return pacchetto.trim();
  }

  // Nessuna informazione disponibile
  return '';
}



// 🔹 WIDGET "PROSSIMI EVENTI"
class ProssimiEventiList extends StatelessWidget {
  const ProssimiEventiList({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final query = FirebaseFirestore.instance
        .collection('preventivi')
        .where('data_evento', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .orderBy('data_evento')
        .limit(3);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snap.hasError) {
          debugPrint('[PROSSIMI_EVENTI] Stream error: ${snap.error}');
          return Text('Errore: ${snap.error}');
        }

        final docs = snap.data?.docs ?? [];
        debugPrint('[PROSSIMI_EVENTI] Docs ricevuti: ${docs.length}');
        if (docs.isEmpty) return const Text('Nessun evento in programma.');

        return Column(
          children: docs.map((d) {
            final data = d.data();
            DateTime? dt;
            final rawDate = data['data_evento'];
            if (rawDate is Timestamp) dt = rawDate.toDate();

            final titolo = (data['nome_evento'] ?? data['titolo'] ?? 'Evento').toString();
            final cliente = _estraiRagioneSociale(data);
            final dateStr = (dt != null) ? DateFormat('dd/MM/yyyy').format(dt) : '';

            // 🔎 LOG PER OGNI EVENTO
            debugPrint('[PROSSIMI_EVENTI] Doc ${d.id} '
                'titolo="$titolo" data_evento=$rawDate '
                'cliente="$cliente" '
                'pacchetto_evento_id="${data['pacchetto_evento_id']}" '
                'pacchettoId="${data['pacchettoId']}" '
                'tipo_pasto="${data['tipo_pasto']}" pasto="${data['pasto']}"');

            return Card(
              elevation: 5,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: _DateBadge(date: dt), // usa il tuo badge esistente
                title: Text(
                  titolo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cliente.isNotEmpty)
                      Text(
                        cliente,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        const SizedBox(width: 8),
                        _DettaglioEventoInline(data: data),
                      ],
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreaPreventivoScreen(preventivoId: d.id),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ===== Helpers =====

  static String _estraiRagioneSociale(Map<String, dynamic> data) {
    // Oggetto cliente incorporato
    final clienteField = data['cliente'];
    if (clienteField is Map) {
      final m = clienteField.cast<String, dynamic>();
      final byKey = (m['ragione_sociale'] ??
          m['ragioneSociale'] ??
          m['nome'] ??
          m['display_name'] ??
          m['displayName']);
      if (byKey is String && byKey.trim().isNotEmpty) return byKey.trim();
    }
    if (clienteField is String && clienteField.trim().isNotEmpty) {
      return clienteField.trim();
    }

    // Altre chiavi comuni nel documento
    final altKeys = [
      'cliente_ragione_sociale',
      'ragione_sociale',
      'ragioneSociale',
      'cliente_nome',
      'clienteName',
      'nome_cliente',
    ];
    for (final k in altKeys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static String _estraiPasto(Map<String, dynamic> data) {
    final pasto = (data['tipo_pasto'] ?? data['pasto'] ?? '').toString().trim().toLowerCase();
    if (pasto.isEmpty) return '';
    if (pasto.contains('pranzo')) return 'Pranzo';
    if (pasto.contains('cena')) return 'Cena';
    return pasto[0].toUpperCase() + pasto.substring(1);
  }
}

/// Widget inline che decide cosa mostrare accanto alla data:
/// - Se c'è `pacchetto_evento_id`, risolve il nome del pacchetto da `pacchetti_eventi/{id}`
/// - Altrimenti mostra Pranzo/Cena (se presente)
/// Widget inline che decide cosa mostrare accanto alla data:
/// 1) Se c'è `pacchetto_evento_id`, risolve il nome del pacchetto da `pacchetti_eventi/{id}`
/// 2) Altrimenti, se nel documento c'è già il nome del pacchetto (mappa/stringa), lo mostra direttamente
/// 3) Se non è un pacchetto, mostra Pranzo/Cena se presente
class _DettaglioEventoInline extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DettaglioEventoInline({required this.data});

  @override
  Widget build(BuildContext context) {
    // A) prima prova a leggere SUBITO il nome del pacchetto dal doc
    final nomePacchetto = _estraiNomePacchettoFisso(data);
    if (nomePacchetto.isNotEmpty) {
      return Text('• $nomePacchetto', style: const TextStyle(color: Colors.black54));
    }

    // B) altrimenti, se c'è un id, fai il lookup su "pacchetti_eventi"
    final pacchettoId = data['pacchetto_evento_id'] ?? data['pacchettoId'];
    if (pacchettoId is String && pacchettoId.isNotEmpty) {
      final future = FirebaseFirestore.instance
          .collection('pacchetti_eventi')
          .doc(pacchettoId)
          .get();

      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(width: 12, height: 12);
          }
          String label = 'Pacchetto';
          if (snap.hasData && snap.data!.exists) {
            final m = snap.data!.data();
            final n = (m?['nome_evento'] ?? m?['nome'] ?? m?['titolo']);
            if (n is String && n.trim().isNotEmpty) {
              label = n.trim();
            }
          }
          return Text('• $label', style: const TextStyle(color: Colors.black54));
        },
      );
    }

    // C) fallback: Pranzo/Cena
    final pasto = ProssimiEventiList._estraiPasto(data);
    if (pasto.isEmpty) return const SizedBox.shrink();
    return Text('• $pasto', style: const TextStyle(color: Colors.black54));
  }
}


class _DateBadge extends StatelessWidget {
  final DateTime? date;
  const _DateBadge({this.date});

  @override
  Widget build(BuildContext context) {
    if (date == null) return const CircleAvatar(child: Icon(Icons.event));
    final month = _itShortMonth(date!.month);
    final day = date!.day.toString().padLeft(2, '0');
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🔹 Mese in NERO (come richiesto)
          Text(month, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
          Text(day, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  String _itShortMonth(int m) {
    const mesi = ['GEN','FEB','MAR','APR','MAG','GIU','LUG','AGO','SET','OTT','NOV','DIC'];
    return (m >= 1 && m <= 12) ? mesi[m - 1] : '---';
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) return const MainScreen(); 
        return LoginScreen(); 
      },
    );
  }
}
