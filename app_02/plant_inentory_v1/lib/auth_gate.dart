// lib/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/sign_in_screen.dart';
import 'screens/plant_list_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final GoTrueClient _auth;
  AuthState? _lastEvent;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _auth = Supabase.instance.client.auth;

    // Kick off initial restore; Supabase usually does this automatically,
    // but we show a splash until the first tick so UI doesn't flicker.
    Future.microtask(() async {
      try {
        // No explicit call needed; currentSession will be populated if a session exists.
      } finally {
        if (mounted) setState(() => _restoring = false);
      }
    });

    _auth.onAuthStateChange.listen((event) {
      setState(() {
        _lastEvent = event;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = _auth.currentSession;
    if (session == null) {
      return const SignInScreen();
    }

    // Signed in → your main app screen
    return const PlantListScreen();
  }
}
