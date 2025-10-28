// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:flutter/services.dart'; // Mantenuto per SystemNavigator
import '../widgets/logo_widget.dart';

// AGGIUNTE per stampe di debug e accesso a Firebase
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 🚨 NUOVI CONTROLLER: Email (username) e Password (vecchio PIN)
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    // 🚨 AZIONE CHIAVE: Carica l'ultima email all'avvio
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final lastEmail = Provider.of<AuthProvider>(context, listen: false).lastUsedEmail;
        if (lastEmail != null && lastEmail.isNotEmpty) {
            _emailController.text = lastEmail;
        }
    });
  }


  @override
  void dispose() {
    // 🚨 MODIFICA: Dispose dei nuovi controller
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _performLogin() async {
    // 🚨 MODIFICA: Validazione Email e Password
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci l\'Email (o Nome Utente)')),
      );
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci la Password (o PIN)')),
      );
      return;
    }
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      // 🚨 CHIAMATA MODIFICATA: Login con Email e Password
      await authProvider.login(email, password);

      // >>> STAMPE DI DEBUG SUBITO DOPO LOGIN RIUSCITA <<<
      if (kDebugMode) {
        final app = Firebase.app();
        final user = FirebaseAuth.instance.currentUser;
        debugPrint('[DEBUG] projectId=${app.options.projectId}');
        debugPrint('[DEBUG] uid=${user?.uid}');
        debugPrint('[DEBUG] email=${user?.email}');
      }
      // <<< FINE STAMPE >>>
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
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
    final theme = Theme.of(context);
    final inputTextStyle =
        TextStyle(color: theme.colorScheme.onSurface, fontSize: 18);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // --- CAMPO EMAIL (USERNAME) ---
              TextFormField(
                controller: _emailController,
                style: inputTextStyle,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email (Nome Utente)",
                  //hintText: "es. mario.rossi@ristorante.it",
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                onFieldSubmitted: (_) => _performLogin(),
              ),

              const SizedBox(height: 20),

              // --- CAMPO PASSWORD (PIN) ---
              TextFormField(
                controller: _passwordController,
                style: inputTextStyle,
                keyboardType: TextInputType.visiblePassword,
                obscureText: true,
                obscuringCharacter: '●',
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Password (o PIN)',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                onFieldSubmitted: (_) => _performLogin(),
              ),

              const SizedBox(height: 20),

              _isLoading
                  ? const CircularProgressIndicator()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _performLogin,
                          child: const Text('Login'),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: () => SystemNavigator.pop(),
                          child: const Text('Esci'),
                        ),
                      ],
                    ),
              const SizedBox(height: 36),

              const LogoWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
