// lib/main.dart
import 'dart:ui';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'dart:async';

// --- AGGIUNTA: IMPORT PER FIREBASE ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'firebase_options.dart';
// --- FINE AGGIUNTA ---

import 'config/app_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

// 🔑 CORREZIONE 1: Import del tuo Provider con un prefisso per risolvere il conflitto
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

import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';

// 🔑 CORREZIONE 2: Aggiunto l'apice e il punto e virgola mancanti
import 'widgets/logo_widget.dart'; 
import 'config/app_theme_dark.dart';

// 🚨 CORREZIONE: RIMOSSA l'importazione errata 'package:path_provider/path.dart';

import 'package:fic_frontend/providers/piatti_provider.dart';
import 'package:fic_frontend/providers/menu_templates_provider.dart';

// --- AGGIUNTA: import pagina Segretario ---
import 'features/segretario/segretario_page.dart';
import 'screens/cerca_cliente_screen.dart';

import 'providers/settings_provider.dart';
import 'providers/segretario_provider.dart';

import 'providers/calendario_eventi_provider.dart';
import 'screens/event_calendar_screen.dart';


// NOTA: 'AppColors' non è definito in questo file, 
// lo lascio commentato o sostituito con Colors.white per la compilazione.

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- AGGIUNTA: INIZIALIZZAZIONE FIREBASE ---
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // --- FINE AGGIUNTA ---

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
    MultiProvider(
      providers: [
        // 🔑 CORREZIONE 1: Usa il prefisso AppAuth
        ChangeNotifierProvider(create: (context) => AppAuth.AuthProvider()),
        ChangeNotifierProvider(create: (context) => LogProvider()),
        ChangeNotifierProvider(create: (context) => TurniProvider()),
        ChangeNotifierProvider(create: (ctx) => DipendentiProvider()),
        ChangeNotifierProvider(create: (context) => MenuProvider()),
        ChangeNotifierProvider(create: (context) => ClientiProvider()),
        ChangeNotifierProvider(create: (context) => PreventiviProvider()),
        ChangeNotifierProvider(create: (context) => ServiziProvider()),
        ChangeNotifierProvider(create: (context) => PreventivoBuilderProvider()),
        ChangeNotifierProvider(create: (context) => PiattiProvider()),
        ChangeNotifierProvider(create: (context) => MenuTemplatesProvider()),
        ChangeNotifierProvider(create: (context) => SettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => SegretarioProvider()),
        ChangeNotifierProvider(create: (_) => CalendarioEventiProvider()),
      ],
      child: MyApp(),
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
        GlobalWidgetsLocalizations.delegate, // <-- CORRETTO
        GlobalCupertinoLocalizations.delegate, // <-- CORRETTO
      ],
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', ''),
      ],
      builder: (context, child) {
        // SafeArea globale
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
      home: const RootGate(),
    );
  }
}

/// Selettore ambiente PRIMA del login (sempre in debug).
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}
class _RootGateState extends State<RootGate> {
  bool _envChosen = false;
  @override
  Widget build(BuildContext context) {
    if (kDebugMode && !_envChosen) {
      return EnvSelectorScreen(onApplied: () => setState(() => _envChosen = true));
    }
    return const AuthGate();
  }
}

class EnvSelectorScreen extends StatefulWidget {
  final VoidCallback onApplied;
  const EnvSelectorScreen({super.key, required this.onApplied});
  @override
  State<EnvSelectorScreen> createState() => _EnvSelectorScreenState();
}
class _EnvSelectorScreenState extends State<EnvSelectorScreen> {
  Environment _selected = AppConfig.currentEnvironment;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Seleziona Ambiente Backend')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RadioListTile<Environment>(
              title: const Text('Produzione'),
              subtitle: Text(AppConfig.prodBaseUrl, style: const TextStyle(fontSize: 12)),
              value: Environment.production,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
            ),
            RadioListTile<Environment>(
              title: const Text('Sviluppo'),
              subtitle: Text(AppConfig.devBaseUrl, style: const TextStyle(fontSize: 12)),
              value: Environment.development,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await AppConfig.setEnvironment(context, _selected);
                  widget.onApplied();
                },
                child: const Text('Conferma e continua'),
              ),
            ),
          ],
        ),
      ),
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
  // 🔑 Modificato tipo per usare il prefisso AppAuth
  late final AppAuth.AuthProvider _authProvider; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🔑 Modificato il cast
    _authProvider = Provider.of<AppAuth.AuthProvider>(context, listen: false); 
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kDebugMode && AppConfig.isDevelopmentEnv) {
        final logProvider = Provider.of<LogProvider>(context, listen: false);
        logProvider.addLog("Ambiente: ${AppConfig.currentEnvironment.name.toUpperCase()} - URL Server: ${AppConfig.currentBaseUrl}");
      }
      _setupLoginSession();
      Provider.of<PreventiviProvider>(context, listen: false).caricaCacheIniziale();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Provider.of<PreventiviProvider>(context, listen: false).verificaVersioneCache();
    }
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

  Future<void> _mostraDialogoAmbiente() async {
    await showEnvironmentSelectorDialog(context);
    if (!mounted) return;
    setState(() {}); // aggiorna label bottone AppBar
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    logProvider.addLog("Ambiente impostato a: ${AppConfig.currentEnvironment.name.toUpperCase()} - URL: ${AppConfig.currentBaseUrl}");
  }

  @override
  Widget build(BuildContext context) {
    final String envLabel = AppConfig.isDevelopmentEnv ? 'SVILUPPO' : 'PRODUZIONE';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('planning_all-pepe_rosa'),
        actions: [
          TextButton.icon(
            onPressed: _mostraDialogoAmbiente,
            icon: const Icon(Icons.settings_ethernet_rounded, size: 20),
            label: Text('Ambiente: $envLabel'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
      drawer: Drawer(
        // Sostituisci AppColors.surface con un colore noto se non è definito
        backgroundColor: Colors.white, 
        // 🔑 CORREZIONE 3: Uso del prefisso AppAuth nel Consumer
        child: Consumer<AppAuth.AuthProvider>(
          builder: (context, authProvider, _) {
            // 🔑 CORREZIONE 4: L'oggetto authProvider è ora tipizzato correttamente, i metodi sono validi
            final menuVoci = [
              // 🚨 NUOVA VOCE: CALENDARIO EVENTI
              {
                "nome": "Calendario Eventi",
                "icon": Icons.calendar_month,
                "widget": const EventCalendarScreen(),
              },
              {
                "nome": "Preventivi",
                "icon": Icons.inventory_2_outlined,
                "widget": const ArchivioPreventiviScreen(),
              },
              {
                "nome": "Segretario",
                "icon": Icons.checklist_rounded,
                "widget": SegretarioPage(),
              },
              {
                "nome": "Contatti",
                "icon": Icons.contacts_rounded,
                "widget": const CercaClienteScreen(),
              },
              {
                "nome": "Inserimento turni",
                "icon": Icons.calendar_today,
                "widget": InserisciTurniScreen(),
              },
              {
                "nome": "Administration",
                "icon": Icons.admin_panel_settings,
                "widget": AdministrationMenuScreen(),
              },
              {
                "nome": "Setup",
                "icon": Icons.settings,
                "widget": SetupScreen(),
              },
            ];

            List<Widget> menuTiles = [];
            for (final voce in menuVoci) {
              if (authProvider.userRuolo == 'admin' ||
                  authProvider.isFunzioneAutorizzata(voce["nome"].toString())) {
                menuTiles.add(
                  ListTile(
                    leading: Icon(
                      voce["icon"] as IconData,
                      color:Colors.black,
                    ),
                    title: Text(
                      voce["nome"].toString(),
                      style: const TextStyle(color: Colors.black),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => voce["widget"] as Widget,
                        ),
                      );
                    },
                  ),
                );
              }
            }
            menuTiles.add(
              const Divider(color: Colors.black),
            );
            menuTiles.add(
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.black),
                title: const Text('Logout', style: TextStyle(color: Colors.black)),
                onTap: () {
                  // 🔑 Uso del prefisso AppAuth
                  Provider.of<AppAuth.AuthProvider>(context, listen: false).logout(); 
                },
              ),
            );

            return ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                DrawerHeader(
                  margin: EdgeInsets.zero, // <-- rimuove la riga/spazio extra sotto l'header
                  // Sostituisci AppColors.surface con un colore noto se non è definito
                  decoration: const BoxDecoration(color: Colors.white), 
                  child: const Text(
                    'Menu Principale',
                    style: TextStyle(color: Colors.black, fontSize: 24),
                  ),
                ),
                const Divider(color: Colors.black, height: 1, thickness: 1),
                ...menuTiles,
              ],
            );
          },
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          // 🔑 CORREZIONE 5: LogoWidget è un widget valido ora
          child: LogoWidget(),
        ),
      ),
    );
  }
}

Future<void> showEnvironmentSelectorDialog(BuildContext context) async {
  if (!kDebugMode) return; 
  Environment selectedEnvInDialog = AppConfig.currentEnvironment; 
  
  await showDialog(
    context: context,
    barrierDismissible: false, 
    builder: (BuildContext dialogContext) {
      final theme = Theme.of(dialogContext);
      return StatefulBuilder( 
        builder: (BuildContext context, StateSetter setStateDialog) {
          return AlertDialog(
            backgroundColor: theme.colorScheme.primary,
            title: Text('Seleziona Ambiente Backend', style: TextStyle(color: theme.colorScheme.onPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RadioListTile<Environment>(
                  title: Text('Produzione', style: TextStyle(color: theme.colorScheme.onPrimary)), 
                  subtitle: Text(AppConfig.prodBaseUrl, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimary.withOpacity(0.7))),
                  value: Environment.production,
                  groupValue: selectedEnvInDialog,
                  activeColor: theme.colorScheme.onPrimary,
                  onChanged: (Environment? value) {
                    if (value != null) setStateDialog(() => selectedEnvInDialog = value);
                  },
                ),
                RadioListTile<Environment>(
                  title: Text('Sviluppo Locale', style: TextStyle(color: theme.colorScheme.onPrimary)), 
                  subtitle: Text(AppConfig.devBaseUrl, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimary.withOpacity(0.7))),
                  value: Environment.development,
                  groupValue: selectedEnvInDialog,
                  activeColor: theme.colorScheme.onPrimary,
                  onChanged: (Environment? value) {
                    if (value != null) setStateDialog(() => selectedEnvInDialog = value);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  "Ambiente attuale: ${AppConfig.currentEnvironment.name}", 
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppConfig.isDevelopmentEnv ? Colors.orange : Colors.green),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Annulla'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              ElevatedButton(
                child: const Text('Applica'), 
                onPressed: () async {
                  await AppConfig.setEnvironment(context, selectedEnvInDialog); 
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(); 
                },
              ),
            ],
          );
        }
      );
    },
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  
  @override
  Widget build(BuildContext context) {
    // 🔑 CORREZIONE DEL PROBLEMA DI AUTENTICAZIONE INIZIALE
    // Usa StreamBuilder per attendere che Firebase carichi lo stato persistente
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // 1. In attesa: Mostra un indicatore di caricamento mentre Firebase verifica lo stato
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Utente loggato (snapshot.hasData è vero quando la sessione è valida)
        if (snapshot.hasData && snapshot.data != null) {
          // Sessione trovata: Continua alla MainScreen (dove l'app funziona)
          return const MainScreen(); 
        } 
        
        // 3. Nessun utente loggato
        else {
          // Nessuna sessione: Mostra la schermata di Login
          return LoginScreen(); 
        }
      },
    );
  }
}