import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login.dart'; // 👈 login page import
import 'screens/dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseInitError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    firebaseInitError = error.toString();
  }

  runApp(MyApp(firebaseInitError: firebaseInitError));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.firebaseInitError});

  final String? firebaseInitError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taaj Royal Contract',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyP, control: true):
                () {},
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                () {},
            const SingleActivator(LogicalKeyboardKey.keyP,
                control: true, shift: true): () {},
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: AuthGate(
        firebaseReady: firebaseInitError == null,
        startupError: firebaseInitError,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.firebaseReady,
    this.startupError,
  });

  final bool firebaseReady;
  final String? startupError;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const String _sessionExpiryKey = 'auth_session_expiry_ms';

  late final Future<bool> _allowDashboardFuture;

  @override
  void initState() {
    super.initState();
    _allowDashboardFuture = _canOpenDashboard();
  }

  Future<bool> _canOpenDashboard() async {
    if (!widget.firebaseReady) {
      return false;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final expiryMs = prefs.getInt(_sessionExpiryKey);
    if (expiryMs == null) {
      // Backward compatibility: give an initial 24h session to current users.
      await prefs.setInt(
        _sessionExpiryKey,
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
      return true;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs <= expiryMs) {
      return true;
    }

    await FirebaseAuth.instance.signOut();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseReady) {
      return LoginPage(
        firebaseReady: false,
        startupError: widget.startupError,
      );
    }

    return FutureBuilder<bool>(
      future: _allowDashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final allowDashboard = snapshot.data ?? false;
        if (allowDashboard) {
          return const Dashboard();
        }

        return LoginPage(
          firebaseReady: true,
          startupError: widget.startupError,
        );
      },
    );
  }
}
