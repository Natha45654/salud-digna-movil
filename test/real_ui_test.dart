import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/real/central_api.dart';
import 'package:salud_digna_movil/real/real_state.dart';
import 'package:salud_digna_movil/real/ui/real_app.dart';
import 'package:salud_digna_movil/real/ui/real_login_screen.dart';

import 'support/fake_central_api.dart';

/// Interfaz del modo real contra la API falsa: acceso, inicio y los errores
/// conocidos. Cada error debe mostrar un mensaje comprensible.
void main() {
  late FakeCentralApi server;
  late RealState state;
  late DateTime now;
  late List<String> logs;

  http.Response error(int code, {Map<String, String> headers = const {}}) => http.Response(
      jsonEncode({'statusCode': code, 'message': 'falla $code'}), code, headers: headers);

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    server = FakeCentralApi();
    now = DateTime.utc(2026, 11, 25, 16);
    logs = [];
    late AppConfig config;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      config = await AppConfig.loadForTesting(mockMode: false, rawBaseUrl: 'https://api.example.test');
    });
    state = RealState(
      CentralApi(config.baseUrl, client: MockClient(server.handle)),
      clock: () => now,
      delay: (_) async {},
      log: logs.add,
    );
    await tester.pumpWidget(SaludDignaRealApp(state: state, config: config));
    await tester.pumpAndSettle();
  }

  /// Retira la app y cancela el temporizador de vencimiento de la sesión.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  Future<void> login(WidgetTester tester,
      {String email = 'ana@example.test', String password = 'correcta'}) async {
    await tester.enterText(find.byKey(RealLoginScreen.emailKey), email);
    await tester.enterText(find.byKey(RealLoginScreen.passwordKey), password);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
  }

  testWidgets('entra con correo y contraseña y muestra el trámite recuperado', (tester) async {
    await launch(tester);
    expect(find.text('Inicia sesión'), findsOneWidget);
    await login(tester);

    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Demo Glucosa'), findsOneWidget);
    expect(find.text('En progreso'), findsOneWidget);
    expect(find.text('Paso: Elegir clínica'), findsOneWidget);
    expect(find.textContaining('Folio 00000000'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('contraseña incorrecta: mensaje claro y sigue en el acceso', (tester) async {
    await launch(tester);
    await login(tester, password: 'mala');
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(find.text('Inicia sesión'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('429 al entrar indica en cuántos segundos reintentar', (tester) async {
    await launch(tester);
    server.failures['POST /auth/login'] = [error(429, headers: {'retry-after': '30'})];
    await login(tester);
    expect(find.text('Demasiadas solicitudes. Intenta en 30 s.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('cuenta que no es de paciente: se rechaza con explicación', (tester) async {
    await launch(tester);
    await login(tester, email: 'asesor@example.test');
    expect(find.text('Esta app es solo para cuentas de paciente.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('401 con token vencido: regresa al acceso con aviso', (tester) async {
    await launch(tester);
    server.failures['GET /mobile/journeys'] = [error(401)];
    await login(tester);
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Tu sesión venció. Inicia sesión de nuevo.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('JWT vencido por tiempo: no se llama a la API y se pide entrar de nuevo',
      (tester) async {
    await launch(tester);
    await login(tester);
    expect(find.text('Hola, Ana'), findsOneWidget);
    final calls = server.requests.length;
    now = now.add(const Duration(minutes: 30));
    await state.refreshJourneys();
    await tester.pumpAndSettle();
    expect(find.text('Tu sesión venció. Inicia sesión de nuevo.'), findsOneWidget);
    expect(server.requests.length, calls);
    await finish(tester);
  });

  testWidgets('404 al listar: "sin trámites vinculados" en pantalla y distinguible en el registro',
      (tester) async {
    await launch(tester);
    server.linked = false;
    await login(tester);
    expect(find.text('Aún no tienes trámites vinculados'), findsOneWidget);
    expect(logs.where((l) => l.contains('GET /mobile/journeys → 404')), hasLength(1));
    await finish(tester);
  });

  testWidgets('200 sin trámites se registra distinto de un 404', (tester) async {
    await launch(tester);
    server.linkedButEmpty = true;
    await login(tester);
    expect(find.text('No tienes trámites activos'), findsOneWidget);
    expect(logs.where((l) => l.contains('→ 200 con 0 trámite(s)')), hasLength(1));
    expect(logs.where((l) => l.contains('→ 404')), isEmpty);
    await finish(tester);
  });

  for (final (code, text) in [
    (502, 'Falló la comunicación con el orquestador. Intenta de nuevo.'),
    (503, 'La integración no está disponible por ahora. Intenta de nuevo.'),
  ]) {
    testWidgets('$code al listar: aviso con "Reintentar" que sí recupera', (tester) async {
      await launch(tester);
      server.failures['GET /mobile/journeys'] = [error(code)];
      await login(tester);
      expect(find.text(text), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text(text), findsNothing);
      expect(find.text('Demo Glucosa'), findsOneWidget);
      await finish(tester);
    });
  }

  testWidgets('429 al listar muestra cuándo reintentar', (tester) async {
    await launch(tester);
    server.failures['GET /mobile/journeys'] = [error(429, headers: {'retry-after': '20'})];
    await login(tester);
    expect(find.text('Demasiadas solicitudes. Intenta en 20 s.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('sin conexión al entrar: mensaje comprensible', (tester) async {
    await launch(tester);
    server.networkDownForAll = true;
    await login(tester);
    expect(find.textContaining('No se pudo conectar con Salud Digna'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('cerrar sesión vuelve al acceso', (tester) async {
    await launch(tester);
    await login(tester);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(state.session, isNull);
    await finish(tester);
  });

  testWidgets('el registro nunca contiene el JWT ni la contraseña', (tester) async {
    await launch(tester);
    server.linked = false;
    await login(tester);
    await state.refreshJourneys();
    await tester.pumpAndSettle();
    expect(logs, isNotEmpty);
    for (final l in logs) {
      expect(l, isNot(contains('jwt-ana')));
      expect(l, isNot(contains('correcta')));
      expect(l, isNot(contains('ana@example.test')));
    }
    await finish(tester);
  });

  testWidgets('URL sin https: la app explica el error de configuración', (tester) async {
    await tester.pumpWidget(const ConfigErrorApp(
        message: 'CHANNEL_BACKEND_URL debe usar https://: http://api.example.test'));
    expect(find.text('La app no está bien configurada'), findsOneWidget);
    expect(find.textContaining('https://'), findsWidgets);
  });
}
