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

/// Pantalla del trámite del modo real contra la API falsa: recorrido
/// estudio → clínica → revisión → PENDING_CONFIRMATION, historial y errores.
void main() {
  late FakeCentralApi server;
  late RealState state;
  late DateTime now;

  http.Response error(int code, {Map<String, String> headers = const {}}) => http.Response(
      jsonEncode({'statusCode': code, 'message': 'falla $code'}), code, headers: headers);

  final eventsPath = 'POST /mobile/journeys/$fakeJourneyId/events';

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    server = FakeCentralApi();
    now = DateTime.utc(2026, 11, 25, 16);
    late AppConfig config;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      config = await AppConfig.loadForTesting(mockMode: false, rawBaseUrl: 'https://api.example.test');
    });
    state = RealState(
      CentralApi(config.baseUrl, client: MockClient(server.handle)),
      clock: () => now,
      delay: (_) async {},
      log: (_) {},
    );
    await tester.pumpWidget(SaludDignaRealApp(state: state, config: config));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(RealLoginScreen.emailKey), 'ana@example.test');
    await tester.enterText(find.byKey(RealLoginScreen.passwordKey), 'correcta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(text).last);
    await tester.pump();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> openJourney(WidgetTester tester) async {
    await tester.tap(find.text('Demo Glucosa'));
    await tester.pumpAndSettle();
  }

  Future<void> pickClinic(WidgetTester tester) async {
    await tapText(tester, 'Elige tu clínica');
    await tapText(tester, 'Demo Clínica Alameda');
  }

  testWidgets('abre el trámite de Web con su estudio, precio, folio e historial', (tester) async {
    await launch(tester);
    await openJourney(tester);
    expect(find.text('Demo Glucosa'), findsOneWidget);
    expect(find.text(r'Demo Glucosa · $120.00 MXN'), findsOneWidget);
    expect(find.text('Folio $fakeJourneyId'), findsOneWidget);
    expect(find.text('Paso actual: Elegir clínica'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Elige tu clínica'), findsOneWidget);

    await tapText(tester, 'Historial entre canales');
    expect(find.textContaining('Sitio Web (demo-web)'), findsOneWidget);
    await tapText(tester, 'Cargar más');
    expect(find.textContaining('Sitio Web (demo-web)'), findsNWidgets(2));
    expect(find.text('Cargar más'), findsNothing);
    await finish(tester);
  });

  testWidgets('elige clínica, publica el evento y queda en revisión', (tester) async {
    await launch(tester);
    await openJourney(tester);
    await pickClinic(tester);

    final post = server.requests.lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(post.body)['payload'], {'expectedVersion': 2, 'clinicId': fakeClinicId});
    expect(find.textContaining('Demo Clínica Alameda'), findsOneWidget);
    expect(find.text('Paso actual: Revisión'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Enviar a confirmación'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('enviar a confirmación termina en PENDING_CONFIRMATION sin más ediciones',
      (tester) async {
    await launch(tester);
    await openJourney(tester);
    await pickClinic(tester);
    await tapText(tester, 'Enviar a confirmación');
    expect(find.text('¿Enviar a confirmación?'), findsOneWidget);
    await tapText(tester, 'Enviar');

    expect(server.status, 'PENDING_CONFIRMATION');
    expect(find.text('Pendiente de confirmación'), findsOneWidget);
    expect(find.textContaining('la app todavía no confirma citas'), findsOneWidget);
    expect(find.text('Cambiar'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Enviar a confirmación'), findsNothing);
    await finish(tester);
  });

  testWidgets('409: avisa que cambió en otro canal y muestra el contexto vigente', (tester) async {
    await launch(tester);
    await openJourney(tester);
    // Otro canal eligió la clínica mientras tanto.
    server
      ..version = 3
      ..refs['clinicId'] = fakeClinicId
      ..step = 'REVIEW';
    await pickClinic(tester);
    expect(find.text('El trámite cambió desde otro canal. Revisa los datos actualizados.'),
        findsOneWidget);
    expect(find.text('Paso actual: Revisión'), findsOneWidget);
    expect(state.pendingFor(fakeJourneyId), isNull);
    await finish(tester);
  });

  testWidgets('503 al publicar: queda pendiente con aviso y "Reintentar" lo entrega',
      (tester) async {
    await launch(tester);
    await openJourney(tester);
    server.failures[eventsPath] = [error(503), error(503), error(503)];
    await pickClinic(tester);

    expect(find.textContaining('Este cambio todavía no llega a Salud Digna'), findsOneWidget);
    expect(find.text('Selección de clínica'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Elige tu clínica'), findsNothing,
        reason: 'no se permite otro cambio mientras hay uno pendiente');

    await tester.tap(find.byTooltip('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Este cambio todavía no llega'), findsNothing);
    expect(find.text('Paso actual: Revisión'), findsOneWidget);
    expect(server.events, hasLength(1));
    await finish(tester);
  });

  testWidgets('429 largo al publicar: queda pendiente y dice cuándo reintentar', (tester) async {
    await launch(tester);
    await openJourney(tester);
    server.failures[eventsPath] = [error(429, headers: {'retry-after': '60'})];
    await pickClinic(tester);
    expect(find.textContaining('Demasiadas solicitudes. Intenta en 60 s.'), findsWidgets);
    expect(find.textContaining('Reintentar después de'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('lo que la API no ofrece se ve deshabilitado y explicado', (tester) async {
    await launch(tester);
    await openJourney(tester);
    await tester.scrollUntilVisible(find.text('Confirmar la cita'), 200,
        scrollable: find.byType(Scrollable).first);
    for (final title in ['Elegir fecha y hora', 'Confirmar la cita',
        'Avisar por WhatsApp o Call Center desde la app']) {
      final tile = tester.widget<ListTile>(find.ancestor(of: find.text(title), matching: find.byType(ListTile)));
      expect(tile.enabled, isFalse, reason: title);
    }
    expect(find.text('Todavía no disponible en la app'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Nueva cita crea el trámite y abre el selector de estudio del catálogo',
      (tester) async {
    await launch(tester);
    await tapText(tester, 'Nueva cita');
    final create = server.requests.lastWhere((r) => r.url.path == '/api/v1/mobile/journeys' && r.method == 'POST');
    expect(create.body, '{"type":"APPOINTMENT"}');
    expect(create.headers['Idempotency-Key'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(find.text('Elige tu estudio'), findsWidgets);
    expect(find.text(r'$120.00 MXN'), findsOneWidget);
    await finish(tester);
  });

  for (final (name, size, scale) in [
    ('teléfono horizontal', const Size(2400, 1080), 1.0),
    ('teléfono vertical con letra al 200 %', const Size(1080, 2400), 2.0),
  ]) {
    testWidgets('sin desbordes: inicio y trámite en $name', (tester) async {
      await launch(tester);
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await openJourney(tester);
      await pickClinic(tester);
      await tester.scrollUntilVisible(find.text('Confirmar la cita'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }

  testWidgets('sesión vencida al publicar: vuelve al acceso y conserva el cambio', (tester) async {
    await launch(tester);
    await openJourney(tester);
    server.failures[eventsPath] = [error(401)];
    await pickClinic(tester);
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Tu sesión venció. Inicia sesión de nuevo.'), findsOneWidget);

    await tester.enterText(find.byKey(RealLoginScreen.emailKey), 'ana@example.test');
    await tester.enterText(find.byKey(RealLoginScreen.passwordKey), 'correcta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Hay un cambio sin enviar'), findsOneWidget);
    await finish(tester);
  });
}
