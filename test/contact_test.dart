import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/core/theme.dart';
import 'package:salud_digna_movil/main.dart';
import 'package:salud_digna_movil/models/models.dart';
import 'package:salud_digna_movil/screens/journey_screen.dart';
import 'package:salud_digna_movil/services/contact_launcher.dart';
import 'package:salud_digna_movil/state/app_state.dart';

/// "¿Necesitas ayuda?": registra CONTACT_INITIATED antes de abrir el canal.
void main() {
  late List<Uri> opened;
  var result = true;

  setUp(() {
    opened = [];
    result = true;
    ContactLauncher.debugOverride = (uri) async {
      opened.add(uri);
      return result;
    };
  });
  tearDown(() => ContactLauncher.debugOverride = null);

  Future<AppState> newState(WidgetTester tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState(await AppConfig.load());
      await state.init();
      await state.login(
        identifiers: const [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456')],
        otp: '123456',
      );
    });
    return state;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const JourneyScreen(journeyId: 'ATN-2026-001'),
      ),
    ));
    await settle(tester);
  }

  Future<void> tapTile(WidgetTester tester, String text) async {
    final tile = find.widgetWithText(ListTile, text);
    await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);
  }

  testWidgets('WhatsApp: registra el contacto con canal y paso, y abre wa.me', (tester) async {
    final state = await newState(tester);
    await open(tester, state);
    await tapTile(tester, 'Escribir por WhatsApp');

    expect(opened.single.host, 'wa.me');
    expect(opened.single.queryParameters['text'], contains('Ultrasonido abdominal'));
    expect(opened.single.toString(), isNot(contains('ATN-2026-001')),
        reason: 'el paciente no ve ni comparte el id del trámite');

    late List<CanonicalEvent> events;
    await tester.runAsync(() async => events = await state.getEvents('ATN-2026-001'));
    final contact = events.where((e) => e.eventType == EventTypes.contactInitiated).single;
    expect(contact.data['channel'], Channels.whatsapp);
    expect(contact.data['step'], 'CONFIRM_APPOINTMENT');
    expect(contact.sourceSystem, Channels.mobileApp);
  });

  testWidgets('Si otro canal escribió antes, el contacto se registra con la versión vigente',
      (tester) async {
    final state = await newState(tester);
    await open(tester, state);
    // Cambio desde otro lado después de abrir la pantalla: la versión avanza.
    await tester.runAsync(() => state.sendEvent(state.buildEvent(
          eventType: EventTypes.requestResumed,
          journeyId: 'ATN-2026-001',
          data: const {'fromChannel': Channels.whatsapp, 'toChannel': Channels.mobileApp},
        )));
    await tapTile(tester, 'Escribir por WhatsApp');
    expect(opened, hasLength(1));
    late List<CanonicalEvent> events;
    await tester.runAsync(() async => events = await state.getEvents('ATN-2026-001'));
    expect(events.where((e) => e.eventType == EventTypes.contactInitiated), hasLength(1));
  });

  testWidgets('Demo: con el simulador activado abre WhatsApp Sim con el mismo mensaje', (tester) async {
    final state = await newState(tester);
    await tester.runAsync(() => state.config.update(whatsappSimulator: true));
    await open(tester, state);
    await tapTile(tester, 'Escribir por WhatsApp');

    final uri = opened.single;
    expect(uri.scheme, 'saluddigna-wa');
    expect(uri.host, 'send');
    expect(uri.queryParameters['phone'], ContactInfo.whatsapp);
    expect(uri.queryParameters['text'], contains('Ultrasonido abdominal'));
    expect(uri.toString(), isNot(contains('ATN-2026-001')));
    late List<CanonicalEvent> events;
    await tester.runAsync(() async => events = await state.getEvents('ATN-2026-001'));
    expect(events.where((e) => e.eventType == EventTypes.contactInitiated), hasLength(1),
        reason: 'el contacto se registra igual que con el WhatsApp real');
  });

  testWidgets('Call Center: abre el marcador sin llamar', (tester) async {
    final state = await newState(tester);
    await open(tester, state);
    await tapTile(tester, 'Llamar al Call Center');
    expect(opened.single.scheme, 'tel');
    expect(opened.single.path, ContactInfo.callCenter);
  });

  testWidgets('Si no se puede abrir, muestra el número para contactar', (tester) async {
    result = false;
    final state = await newState(tester);
    await open(tester, state);
    await tapTile(tester, 'Escribir por WhatsApp');
    expect(find.textContaining('No se pudo abrir WhatsApp'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('En una cita confirmada se puede contactar sin modificar el trámite', (tester) async {
    final state = await newState(tester);
    await tester.runAsync(() => state.sendEvent(state.buildEvent(
          eventType: EventTypes.confirmationRequested,
          journeyId: 'ATN-2026-001',
        )));
    await open(tester, state);
    await tapTile(tester, 'Llamar al Call Center');
    expect(opened, hasLength(1));
    late List<CanonicalEvent> events;
    await tester.runAsync(() async => events = await state.getEvents('ATN-2026-001'));
    expect(events.where((e) => e.eventType == EventTypes.contactInitiated), isEmpty);
    expect(find.textContaining('no admite'), findsNothing);
  });
}
