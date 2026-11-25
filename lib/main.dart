import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';

/// App móvil de Salud Digna (simulador del canal MOBILE_APP).
///
/// Esta app no reemplaza la app real: es el módulo de canal descrito en la
/// Opción A del documento de arquitectura. Notifica eventos de negocio al
/// orquestador (a través del backend del canal) y consulta trámites,
/// contexto e historial.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final state = AppState(config);
  await state.init();
  runApp(SaludDignaApp(state: state));
}

/// Acceso al estado global sin dependencias externas.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class SaludDignaApp extends StatelessWidget {
  final AppState state;
  const SaludDignaApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Salud Digna',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) {
      // Sesión cerrada o expirada: se descartan las pantallas abiertas encima
      // (por ejemplo, un trámite) para regresar a la identificación.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = Navigator.maybeOf(context);
        if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
      });
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: state.isLoggedIn
          ? const HomeScreen(key: ValueKey('home'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}
