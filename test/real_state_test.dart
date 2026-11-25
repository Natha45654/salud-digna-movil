import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:salud_digna_movil/real/api_models.dart';
import 'package:salud_digna_movil/real/central_api.dart';
import 'package:salud_digna_movil/real/real_state.dart';

import 'support/fake_central_api.dart';

void main() {
  late FakeCentralApi server;
  late RealState state;
  late DateTime now;
  late List<Duration> waits;

  setUp(() {
    server = FakeCentralApi();
    now = DateTime.utc(2026, 11, 25, 16);
    waits = [];
    state = RealState(
      CentralApi('https://api.example.test', client: MockClient(server.handle)),
      clock: () => now,
      delay: (d) async => waits.add(d),
    );
  });
  tearDown(() => state.dispose());

  http.Response error(int code, {Map<String, String> headers = const {}}) =>
      http.Response(jsonEncode({'statusCode': code, 'message': 'falla $code'}), code, headers: headers);

  Future<JourneyContext> loginAndContext([String email = 'ana@example.test']) async {
    await state.login(email, 'correcta');
    return (await state.loadJourney(fakeJourneyId)).context;
  }

  group('Sesión', () {
    test('inicia sesión con correo y contraseña y usa patientId, no el UUID de la cuenta', () async {
      await state.login(' ana@example.test ', 'correcta');
      expect(state.isLoggedIn, isTrue);
      expect(state.session!.patientId, 'p-ana');
      expect(state.session!.account.id, isNot('p-ana'));
      final login = server.requests.first;
      expect(login.url.path, '/api/v1/auth/login');
      expect(jsonDecode(login.body), {'email': 'ana@example.test', 'password': 'correcta'});
      expect(server.requests[1].headers['Authorization'], 'Bearer jwt-ana');
    });

    test('credenciales incorrectas, rol distinto o cuenta sin perfil se rechazan', () async {
      await expectLater(state.login('ana@example.test', 'mala'), throwsA(isA<RealAuthException>()));
      await expectLater(state.login('asesor@example.test', 'correcta'), throwsA(isA<RealAuthException>()));
      await expectLater(state.login('sinperfil@example.test', 'correcta'), throwsA(isA<RealAuthException>()));
      expect(state.isLoggedIn, isFalse);
    });

    test('ninguna solicitud lleva cabeceras de canal, grants ni acreditaciones', () async {
      final ctx = await loginAndContext();
      await state.refreshJourneys();
      await state.selectClinic(ctx, fakeClinicId);
      for (final r in server.requests) {
        final names = r.headers.keys.map((k) => k.toLowerCase());
        expect(names, isNot(contains('x-channel-key')));
        expect(names, isNot(contains('x-journey-grant')));
        expect(names.where((n) => n.startsWith('x-patient-assertion')), isEmpty);
      }
    });

    test('el JWT vencido suspende la sesión antes de llamar a la API', () async {
      server.expiresIn = 60;
      await state.login('ana@example.test', 'correcta');
      final calls = server.requests.length;
      now = now.add(const Duration(seconds: 31)); // 60 s - 30 s de margen
      await state.refreshJourneys();
      expect(state.isLoggedIn, isFalse);
      expect(state.notice, contains('venció'));
      expect(server.requests.length, calls);
    });

    test('un 401 en una lectura suspende la sesión', () async {
      await state.login('ana@example.test', 'correcta');
      server.failures['GET /mobile/journeys'] = [error(401)];
      await state.refreshJourneys();
      expect(state.isLoggedIn, isFalse);
      expect(state.notice, isNotNull);
    });
  });

  group('Trámites y catálogos', () {
    test('recupera los trámites, sus contextos y los catálogos con precio como cadena', () async {
      await state.login('ana@example.test', 'correcta');
      await state.refreshJourneys();
      expect(state.journeys.single.id, fakeJourneyId);
      expect(state.contexts[fakeJourneyId]!.studyId, fakeStudyId);
      expect(state.studies[fakeStudyId]!.price, '120.00');
      expect(formatPriceString(state.studies[fakeStudyId]!.price), r'$120.00 MXN');
      expect(state.clinics[fakeClinicId]!.name, 'Demo Clínica Alameda');
    });

    test('404 al listar significa identidad sin trámites vinculados, no un error', () async {
      server.linked = false;
      await state.login('ana@example.test', 'correcta');
      await state.refreshJourneys();
      expect(state.notLinked, isTrue);
      expect(state.journeysError, isNull);
      expect(state.journeys, isEmpty);
    });

    test('el historial se pagina con nextCursor', () async {
      await state.login('ana@example.test', 'correcta');
      var detail = await state.loadJourney(fakeJourneyId);
      expect(detail.history.map((e) => e.id), ['e1']);
      expect(detail.hasMoreHistory, isTrue);
      detail = await state.loadMoreHistory(detail);
      expect(detail.history.map((e) => e.id), ['e1', 'e2']);
      expect(detail.hasMoreHistory, isFalse);
      expect(server.requests.last.url.queryParameters, {'limit': '20', 'cursor': 'c2'});
    });

    test('una referencia fuera del catálogo se consulta por UUID y un 404 se recuerda', () async {
      await state.login('ana@example.test', 'correcta');
      expect(await state.resolveStudy('00000000-0000-4000-8000-000000000999'), isNull);
      final calls = server.requests.length;
      expect(await state.resolveStudy('00000000-0000-4000-8000-000000000999'), isNull);
      expect(server.requests.length, calls);
    });
  });

  group('Escrituras', () {
    test('el evento de clínica sigue el contrato y después se lee el contexto vigente', () async {
      final ctx = await loginAndContext();
      final r = await state.selectClinic(ctx, fakeClinicId);
      expect(r.status, WriteStatus.done);

      final post = server.requests.firstWhere((q) => q.method == 'POST' && q.url.path.endsWith('/events'));
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body.keys, unorderedEquals(['externalEventId', 'type', 'schemaVersion', 'occurredAt', 'payload']));
      expect(body['externalEventId'], matches(RegExp(r'^(?!system:)[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$')));
      expect(body['type'], 'JOURNEY_CONTEXT_UPDATED');
      expect(body['schemaVersion'], 1);
      expect(body['occurredAt'], '2026-11-25T16:00:00.000Z');
      expect(body['payload'], {'expectedVersion': 2, 'clinicId': fakeClinicId});

      expect(server.requests.last.url.path, endsWith('/context'));
      expect(r.context!.currentStep, 'REVIEW');
      expect(r.context!.version, 3);
      expect(state.pendingFor(fakeJourneyId), isNull);
    });

    test('enviar a confirmación publica JOURNEY_STATUS_CHANGED con to', () async {
      server
        ..refs['clinicId'] = fakeClinicId
        ..step = 'REVIEW';
      final ctx = await loginAndContext();
      final r = await state.requestConfirmation(ctx);
      expect(r.status, WriteStatus.done);
      final body = jsonDecode(server.requests
          .lastWhere((q) => q.url.path.endsWith('/events'))
          .body) as Map<String, dynamic>;
      expect(body['type'], 'JOURNEY_STATUS_CHANGED');
      expect(body['payload'], {'expectedVersion': 2, 'to': 'PENDING_CONFIRMATION'});
      expect(server.status, 'PENDING_CONFIRMATION');
    });

    test('ante 503 y 504 reintenta con el mismo cuerpo y luego entrega una sola vez', () async {
      final ctx = await loginAndContext();
      server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [error(503), error(504)];
      final r = await state.selectClinic(ctx, fakeClinicId);
      expect(r.status, WriteStatus.done);
      final bodies = server.requests
          .where((q) => q.url.path.endsWith('/events'))
          .map((q) => q.body)
          .toSet();
      expect(bodies, hasLength(1), reason: 'mismo id, fecha, versión y payload en cada intento');
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 2)]);
      expect(server.version, 3);
    });

    test('un fallo de red se reintenta con el mismo cuerpo', () async {
      final ctx = await loginAndContext();
      server.networkFailures = 1;
      final r = await state.selectClinic(ctx, fakeClinicId);
      expect(r.status, WriteStatus.done);
      expect(waits, [const Duration(seconds: 1)]);
      expect(server.events, hasLength(1));
    });

    test('si los reintentos se agotan, queda pendiente y el reintento manual envía lo mismo', () async {
      final ctx = await loginAndContext();
      server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [error(503), error(503), error(503)];
      final r = await state.selectClinic(ctx, fakeClinicId);
      expect(r.status, WriteStatus.pending);
      final op = state.pendingFor(fakeJourneyId)!;
      expect(op.attempts, 3);

      final again = await state.selectStudy(ctx, fakeStudyId);
      expect(again.status, WriteStatus.rejected, reason: 'una sola operación pendiente por trámite');

      final retried = await state.retryPending(op);
      expect(retried.status, WriteStatus.done);
      expect(server.requests.where((q) => q.url.path.endsWith('/events')).map((q) => q.body).toSet(),
          hasLength(1));
      expect(state.pendingFor(fakeJourneyId), isNull);
    });

    test('409 descarta la operación y vuelve a leer el contexto', () async {
      final ctx = await loginAndContext();
      server.version = 3; // otro canal avanzó
      final r = await state.selectClinic(ctx, fakeClinicId);
      expect(r.status, WriteStatus.conflict);
      expect(r.context!.version, 3);
      expect(state.pendingFor(fakeJourneyId), isNull);
    });

    test('429 con Retry-After corto espera y reintenta; largo deja la operación en espera', () async {
      final ctx = await loginAndContext();
      server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [
        error(429, headers: {'retry-after': '3'}),
      ];
      expect((await state.selectClinic(ctx, fakeClinicId)).status, WriteStatus.done);
      expect(waits, [const Duration(seconds: 3)]);

      final ctx2 = state.contexts[fakeJourneyId]!;
      server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [
        error(429, headers: {'retry-after': '60'}),
      ];
      final r = await state.requestConfirmation(ctx2);
      expect(r.status, WriteStatus.pending);
      final op = state.pendingFor(fakeJourneyId)!;
      final calls = server.requests.length;
      final early = await state.retryPending(op);
      expect(early.status, WriteStatus.pending);
      expect(server.requests.length, calls, reason: 'no reintenta antes de Retry-After');
      now = now.add(const Duration(seconds: 61));
      expect((await state.retryPending(op)).status, WriteStatus.done);
    });

    test('400, 403 y 404 se descartan sin reintentar', () async {
      final ctx = await loginAndContext();
      for (final code in [400, 403, 404]) {
        server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [error(code)];
        final r = await state.selectClinic(ctx, fakeClinicId);
        expect(r.status, WriteStatus.rejected, reason: '$code');
        expect(state.pendingFor(fakeJourneyId), isNull);
      }
      expect(waits, isEmpty);
    });

    test('la creación conserva su Idempotency-Key entre reintentos', () async {
      await state.login('ana@example.test', 'correcta');
      server.failures['POST /mobile/journeys'] = [error(503), error(503), error(503)];
      expect((await state.createJourney()).status, WriteStatus.pending);
      final r = await state.createJourney();
      expect(r.status, WriteStatus.done);

      final creates = server.requests.where((q) => q.method == 'POST' && q.url.path == '/api/v1/mobile/journeys');
      final keys = creates.map((q) => q.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(1));
      expect(keys.single, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(creates.map((q) => q.body).toSet(), {'{"type":"APPOINTMENT"}'});
      expect(server.idempotency, hasLength(1));
    });

    test('dos creaciones distintas usan claves distintas', () async {
      await state.login('ana@example.test', 'correcta');
      final a = await state.createJourney();
      final b = await state.createJourney();
      expect(a.value, isNot(b.value));
    });
  });

  group('Aislamiento por cuenta', () {
    test('401 al publicar conserva la operación solo para la misma cuenta', () async {
      final ctx = await loginAndContext();
      server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [error(401)];
      final r = await state.selectClinic(ctx, fakeClinicId);
      expect(r.status, WriteStatus.sessionExpired);
      expect(state.isLoggedIn, isFalse);

      await state.login('luis@example.test', 'correcta');
      expect(state.pendingOperations, isEmpty, reason: 'Luis no ve ni reenvía lo de Ana');
      state.logout();

      await state.login('ana@example.test', 'correcta');
      final op = state.pendingFor(fakeJourneyId);
      expect(op, isNotNull);
      expect((await state.retryPending(op!)).status, WriteStatus.done);
    });

    test('cerrar sesión elimina las operaciones pendientes y los datos cargados', () async {
      final ctx = await loginAndContext();
      server.failures['POST /mobile/journeys/$fakeJourneyId/events'] = [error(503), error(503), error(503)];
      await state.selectClinic(ctx, fakeClinicId);
      expect(state.pendingFor(fakeJourneyId), isNotNull);
      state.logout();
      expect(state.session, isNull);
      expect(state.contexts, isEmpty);
      await state.login('ana@example.test', 'correcta');
      expect(state.pendingOperations, isEmpty);
    });
  });
}
