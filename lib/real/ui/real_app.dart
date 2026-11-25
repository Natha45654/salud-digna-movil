import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../real_state.dart';
import 'real_home_screen.dart';
import 'real_login_screen.dart';

/// Acceso al estado del modo real desde las pantallas.
class RealScope extends InheritedNotifier<RealState> {
  final AppConfig config;

  const RealScope({
    super.key,
    required RealState state,
    required this.config,
    required super.child,
  }) : super(notifier: state);

  static RealState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RealScope>()!.notifier!;

  static AppConfig configOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RealScope>()!.config;
}

/// App en modo real (`MOCK_MODE=false`): API central de Salud Digna.
class SaludDignaRealApp extends StatelessWidget {
  final RealState state;
  final AppConfig config;

  const SaludDignaRealApp({super.key, required this.state, required this.config});

  @override
  Widget build(BuildContext context) {
    return RealScope(
      state: state,
      config: config,
      child: MaterialApp(
        title: 'Salud Digna',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const _RealRoot(),
      ),
    );
  }
}

class _RealRoot extends StatelessWidget {
  const _RealRoot();

  @override
  Widget build(BuildContext context) {
    final state = RealScope.of(context);
    if (!state.isLoggedIn) {
      // Sesión cerrada o vencida: se descartan las pantallas abiertas encima
      // para regresar al acceso.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = Navigator.maybeOf(context);
        if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
      });
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: state.isLoggedIn
          ? const RealHomeScreen(key: ValueKey('real-home'))
          : const RealLoginScreen(key: ValueKey('real-login')),
    );
  }
}

/// `CHANNEL_BACKEND_URL` inválida en un APK del modo real: se explica en lugar
/// de intentar conectarse.
class ConfigErrorApp extends StatelessWidget {
  final String message;
  const ConfigErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salud Digna',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.lg),
              child: EmptyState(
                icon: Icons.settings_suggest_outlined,
                title: 'La app no está bien configurada',
                message: '$message\n\nVuelve a compilar con una CHANNEL_BACKEND_URL '
                    'que empiece con https:// (ver .env.example).',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
