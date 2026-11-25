import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'real/central_api.dart';
import 'real/real_state.dart';
import 'real/ui/real_app.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';

/// App móvil de Salud Digna, canal móvil del sistema omnicanal.
///
/// `MOCK_MODE` (al compilar) elige el flujo:
/// - true: orquestador simulado en el dispositivo ([SaludDignaApp]).
/// - false: API central de Salud Digna ([SaludDignaRealApp]), solo con el
///   JWT del paciente.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  if (!config.mockMode) {
    final error = config.baseUrlError;
    if (error != null) {
      runApp(ConfigErrorApp(message: error));
      return;
    }
    runApp(SaludDignaRealApp(state: RealState(CentralApi(config.baseUrl)), config: config));
    return;
  }
  final state = AppState(config);
  await state.init();
  runApp(SaludDignaApp(state: state));
}

/// Acceso al estado del modo simulado sin dependencias externas.
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
