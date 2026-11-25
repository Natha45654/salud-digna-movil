import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/main.dart';
import 'package:salud_digna_movil/models/models.dart';
import 'package:salud_digna_movil/services/http_orchestrator.dart';
import 'package:salud_digna_movil/state/app_state.dart';
import 'package:salud_digna_movil/widgets/common.dart';
import 'package:salud_digna_movil/widgets/patient_blocks.dart';

/// Trámites pendientes desde "Retomar trámite de otro canal", sin código
/// adicional tras verificarse.
/// Fuente de datos: el orquestador simulado de la app (decisión del equipo
/// mientras el orquestador real no expone la consulta por paciente).
void main() {
  const ana = [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456')];
  const luis = [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-654321')];

  Future<AppState> newState(WidgetTester tester,
      {List<PatientIdentifier> who = ana, String otp = '123456', Map<String, Object>? prefs}) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(prefs ?? {});
      state = AppState(await AppConfig.load());
      await state.init();
      if (prefs == null) await state.login(identifiers: who, otp: otp);
    });
    return state;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester, [Size size = const Size(412, 915)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Crea para Ana un trámite que solo tiene estudio (falta clínica), y lo deja
  /// como el más reciente.
  Future<String> anaJourneyWithStudy(WidgetTester tester, AppState state) async {
    late String id;
    await tester.runAsync(() async {
      final ack = await state.sendEvent(state.buildEvent(
        eventType: EventTypes.journeyStarted,
        data: const {'journeyType': 'APPOINTMENT_BOOKING'},
      ));
      id = ack!.journeyId;
      await state.sendEvent(state.buildEvent(
        eventType: EventTypes.studySelected,
        journeyId: id,
        data: const {'studyId': 'STD-004', 'studyName': 'Rayos X de tórax', 'price': 180},
        expectedVersion: 1,
      ));
      await state.refreshJourneys();
    });
    return id;
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
  }

  /// Abre "Retomar trámite de otro canal" desde Inicio.
  Future<void> openPending(WidgetTester tester) async {
    await scrollTo(tester, find.text('Retomar trámite de otro canal'));
    await tester.tap(find.text('Retomar trámite de otro canal'));
    await settle(tester);
  }

  testWidgets('Inicio: paciente, "Tus citas", "Nueva cita" y "Retomar", en ese orden', (tester) async {
    phone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    double top(Finder f) => tester.getTopLeft(f).dy;
    final hello = top(find.text('Hola, Ana'));
    final patient = top(find.text('Verificada'));
    final appointments = top(find.text('Tus citas'));
    final newOne = top(find.text('Nueva cita'));
    final resume = top(find.text('Retomar trámite de otro canal'));
    expect(hello < patient && patient < appointments && appointments < newOne && newOne < resume,
        isTrue);
    // Ningún rastro de la sección quitada.
    expect(find.text('Continúa donde te quedaste'), findsNothing);
    expect(find.text('Tu avance se guarda aunque cambies de canal'), findsNothing);
    expect(find.byType(PendingJourneyCard), findsNothing);
  });

  testWidgets('1. "Retomar" lista los pendientes sin escribir ningún código', (tester) async {
    phone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await openPending(tester);
    expect(find.text('Trámites pendientes'), findsOneWidget);
    expect(find.byType(PendingJourneyCard), findsWidgets);
    expect(find.byType(TextField), findsNothing, reason: 'ya no se pide código');
  });

  testWidgets('La vista muestra "cargando" mientras pide los trámites', (tester) async {
    phone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await scrollTo(tester, find.text('Retomar trámite de otro canal'));
    await tester.tap(find.text('Retomar trámite de otro canal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final sheet = find.ancestor(of: find.text('Trámites pendientes'), matching: find.byType(Column)).first;
    expect(find.descendant(of: sheet, matching: find.byType(SkeletonCard)), findsWidgets);
    await settle(tester);
    expect(find.descendant(of: sheet, matching: find.byType(PendingJourneyCard)), findsWidgets);
  });

  testWidgets('La vista muestra el error de red con "Reintentar"', (tester) async {
    phone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await tester.runAsync(() => state.config.update(mockFailures: true));
    await openPending(tester);
    final sheet = find.ancestor(of: find.text('Trámites pendientes'), matching: find.byType(Column)).first;
    expect(find.descendant(of: sheet, matching: find.byType(ErrorBanner)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Reintentar')), findsOneWidget);

    // Al volver la conexión, reintentar muestra los trámites.
    await tester.runAsync(() => state.config.update(mockFailures: false));
    await tester.tap(find.descendant(of: sheet, matching: find.text('Reintentar')));
    await settle(tester);
    expect(find.descendant(of: sheet, matching: find.byType(ErrorBanner)), findsNothing);
    expect(find.descendant(of: sheet, matching: find.byType(PendingJourneyCard)), findsWidgets);
  });

  testWidgets('2. Un trámite de otro canal aparece con su etapa y contexto reales', (tester) async {
    phone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await openPending(tester);
    // El de Ana viene de Web → WhatsApp con estudio, clínica y horario.
    expect(find.text('Ultrasonido abdominal'), findsOneWidget);
    expect(find.text('Salud Digna Guadalajara Centro'), findsOneWidget);
    expect(find.text('Lista para confirmar'), findsOneWidget);
    expect(find.textContaining('Lo dejaste en WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirma tu cita'), findsOneWidget);
  });

  testWidgets('La ventana lista los pendientes del más reciente al más antiguo', (tester) async {
    phone(tester);
    final state = await newState(tester);
    await anaJourneyWithStudy(tester, state);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await scrollTo(tester, find.text('Retomar trámite de otro canal'));
    await tester.tap(find.text('Retomar trámite de otro canal'));
    await settle(tester);

    final sheet = find.ancestor(of: find.text('Trámites pendientes'), matching: find.byType(Column)).first;
    final cards = find.descendant(of: sheet, matching: find.byType(PendingJourneyCard));
    expect(cards, findsNWidgets(2));
    final titles = cards
        .evaluate()
        .map((e) => (e.widget as PendingJourneyCard).journey.updatedAt)
        .toList();
    expect(titles[0].isAfter(titles[1]), isTrue, reason: 'descendente por fecha');
    final first = (cards.evaluate().first.widget as PendingJourneyCard).journey;
    expect(first.study?['studyName'], 'Rayos X de tórax', reason: 'el más reciente va primero');
  });

  testWidgets('La ventana es responsiva: hoja inferior en vertical, panel lateral en horizontal',
      (tester) async {
    phone(tester, const Size(915, 412));
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await tester.tap(find.text('Retomar trámite de otro canal'));
    await settle(tester);
    final title = tester.getRect(find.text('Trámites pendientes'));
    expect(title.left, greaterThan(915 / 2), reason: 'en horizontal entra por la derecha');
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sin trámites pendientes, la vista lo explica (el botón sigue visible)', (tester) async {
    phone(tester);
    final state = await newState(tester, who: luis, otp: '654321');
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    expect(find.text('Retomar trámite de otro canal'), findsOneWidget);
    await openPending(tester);
    expect(find.text('No tienes trámites pendientes'), findsOneWidget);
    expect(find.byType(PendingJourneyCard), findsNothing);
  });

  testWidgets('3. Continuar abre el paso exacto con los datos previos y registra la reanudación',
      (tester) async {
    phone(tester);
    final state = await newState(tester);
    final id = await anaJourneyWithStudy(tester, state);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await openPending(tester);

    // Botón del trámite nuevo (falta clínica).
    await tester.tap(find.widgetWithText(FilledButton, 'Elige tu clínica').first);
    await settle(tester);
    expect(find.text('Elige tu clínica'), findsWidgets, reason: 'se abre el selector de clínica');
    expect(find.text('Salud Digna Tlajomulco'), findsOneWidget);

    late List<CanonicalEvent> events;
    await tester.runAsync(() async => events = await state.getEvents(id));
    final resumed = events.where((e) => e.eventType == EventTypes.requestResumed).toList();
    expect(resumed, hasLength(1));
    expect(resumed.single.data['toChannel'], Channels.mobileApp);
    // Iniciado en la app: no hay cambio de canal.
    expect(events.where((e) => e.eventType == EventTypes.channelSwitched), isEmpty);

    // Datos previos cargados detrás del selector.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.textContaining('Rayos X de tórax'), findsWidgets);
  });

  testWidgets('Desde otro canal se registran REQUEST_RESUMED y CHANNEL_SWITCHED con origen y destino',
      (tester) async {
    phone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    await openPending(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirma tu cita'));
    await settle(tester);

    late List<CanonicalEvent> events;
    await tester.runAsync(() async => events = await state.getEvents('ATN-2026-001'));
    final switched = events.where((e) => e.eventType == EventTypes.channelSwitched).single;
    expect(switched.data['fromChannel'], Channels.whatsapp);
    expect(switched.data['toChannel'], Channels.mobileApp);
    expect(events.where((e) => e.eventType == EventTypes.requestResumed), hasLength(1));
    // Confirmar no se abre solo: la acción principal queda a la vista.
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // deja expirar avisos en pantalla
  });

  testWidgets('4. Sin citas, "Tus citas" lo explica y "Nueva cita" queda debajo', (tester) async {
    phone(tester);
    final state = await newState(tester, who: luis, otp: '654321');
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    expect(find.text('Aún no tienes citas confirmadas'), findsOneWidget);
    expect(find.text('Agendar mi primera cita'), findsNothing, reason: 'sin acción repetida');
    expect(tester.getTopLeft(find.text('Nueva cita')).dy,
        greaterThan(tester.getTopLeft(find.text('Aún no tienes citas confirmadas')).dy));
  });

  testWidgets('5. Sesión expirada: el servidor rechaza y la app vuelve a la identificación',
      (tester) async {
    phone(tester);
    final expired = jsonEncode({
      'patientRef': 'PAT-0001',
      'displayName': 'Ana García',
      'token': 'expirado',
      'verificationLevel': 'VERIFIED',
      'identifiers': [ana.first.toJson()],
    });
    final state = await newState(tester, prefs: {'session.v1': expired});
    expect(state.isLoggedIn, isTrue);
    await tester.pumpWidget(SaludDignaApp(state: state));
    await settle(tester);
    expect(state.isLoggedIn, isFalse);
    expect(find.text('Identifícate'), findsOneWidget);
  });

  test('El cliente pide los trámites sin ningún identificador de paciente', () async {
    SharedPreferences.setMockInitialValues({});
    final config = await AppConfig.load();
    await config.update(baseUrl: 'http://backend.test', mockMode: false);
    final seen = <Uri>[];
    final client = HttpOrchestrator(config, client: MockClient((req) async {
      seen.add(req.url);
      return http.Response(jsonEncode({'journeys': []}), 200,
          headers: {'content-type': 'application/json'});
    }));
    const session = PatientSession(
      patientRef: 'PAT-0001',
      displayName: 'Ana García',
      token: 'tok',
      verificationLevel: 'VERIFIED',
      identifiers: ana,
    );
    await client.listJourneys(session, status: 'open');
    expect(seen.single.path, '/api/v1/me/journeys');
    expect(seen.single.queryParameters, {'status': 'open'});
    expect(seen.single.toString().contains('PAT-0001'), isFalse);
    expect(seen.single.toString().contains('SD-123456'), isFalse);
  });
}
