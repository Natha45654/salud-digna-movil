import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/models/models.dart';
import 'package:salud_digna_movil/services/mock_orchestrator.dart';
import 'package:salud_digna_movil/services/outbox.dart';

/// Pruebas de las reglas no negociables (sección 12 del documento de
/// arquitectura) aplicadas por el orquestador simulado. Cuando exista el
/// backend NestJS, estas mismas pruebas deberían pasar contra él.
void main() {
  late MockOrchestrator orch;
  late AppConfig config;

  const ana = [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456')];
  const luis = [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-654321')];

  CanonicalEvent ev(
    String type, {
    String? journeyId,
    String id = 'app-1',
    Map<String, dynamic> data = const {},
    int? expectedVersion,
    List<PatientIdentifier> ids = ana,
  }) =>
      CanonicalEvent(
        eventId: id,
        sourceSystem: Channels.mobileApp,
        patientIdentifiers: ids,
        journeyId: journeyId,
        eventType: type,
        occurredAt: DateTime.now(),
        data: data,
        expectedVersion: expectedVersion,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    config = await AppConfig.load();
    orch = MockOrchestrator(config);
  });

  group('Identidad', () {
    test('OTP válido devuelve sesión verificada', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      expect(s.patientRef, 'PAT-0001');
      expect(s.verificationLevel, 'VERIFIED');
    });

    test('OTP inválido se rechaza con 401', () async {
      expect(
        () => orch.verifyIdentity(identifiers: ana, otp: '000000'),
        throwsA(isA<OrchestratorException>()
            .having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('identificador desconocido no resuelve', () async {
      expect(
        () => orch.verifyIdentity(
          identifiers: const [PatientIdentifier(type: 'PHONE', value: '+520000')],
          otp: '123456',
        ),
        throwsA(isA<OrchestratorException>()
            .having((e) => e.statusCode, 'status', 404)),
      );
    });

    test('un paciente no ve los trámites de otro', () async {
      final sLuis = await orch.verifyIdentity(identifiers: luis, otp: '654321');
      expect(await orch.listJourneys(sLuis), isEmpty);
      expect(
        () => orch.getJourney('ATN-2026-001', sLuis),
        throwsA(isA<OrchestratorException>()
            .having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('Continuidad Web → WhatsApp → App', () {
    test('Ana recupera el trámite sembrado con su contexto', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final js = await orch.listJourneys(s);
      expect(js, hasLength(1));
      final j = js.first;
      expect(j.status, JourneyStatus.pendienteConfirmacion);
      expect(j.channels, containsAll([Channels.web, Channels.whatsapp]));
      expect(j.study?['studyId'], 'STD-001');
      expect(j.clinic?['clinicId'], 'CLI-012');
      expect(j.slot, isNotNull);
      expect(j.nextStep?.code, 'CONFIRM_APPOINTMENT');
    });

    test('la app confirma y el sistema de citas cierra el trámite', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final j = await orch.getJourney('ATN-2026-001', s);
      final ack = await orch.publishEvent(
        ev(EventTypes.confirmationRequested,
            journeyId: j.journeyId, expectedVersion: j.version),
        session: s,
      );
      expect(ack.status, JourneyStatus.confirmado);
      final j2 = await orch.getJourney('ATN-2026-001', s);
      expect(j2.appointment?['appointmentId'], isNotNull);
      final events = await orch.listEvents('ATN-2026-001', s);
      expect(events.last.eventType, EventTypes.appointmentConfirmed);
      expect(events.last.sourceSystem, 'APPOINTMENT_SYSTEM');
    });
  });

  group('Reglas del motor de estado', () {
    test('eventos idempotentes: el mismo eventId no duplica', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final before = (await orch.listEvents('ATN-2026-001', s)).length;
      final e = ev(EventTypes.contextResumed,
          journeyId: 'ATN-2026-001', id: 'app-dup');
      final a1 = await orch.publishEvent(e, session: s);
      final a2 = await orch.publishEvent(e, session: s);
      expect(a1.duplicate, isFalse);
      expect(a2.duplicate, isTrue);
      expect(a2.version, a1.version);
      final after = (await orch.listEvents('ATN-2026-001', s)).length;
      expect(after, before + 1);
    });

    test('control optimista: versión desactualizada → 409', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final j = await orch.getJourney('ATN-2026-001', s);
      expect(
        () => orch.publishEvent(
          ev(EventTypes.clinicSelected,
              journeyId: j.journeyId,
              data: const {'clinicId': 'CLI-020'},
              expectedVersion: j.version - 1),
          session: s,
        ),
        throwsA(isA<OrchestratorException>().having((e) => e.isConflict, 'conflict', true)),
      );
    });

    test('no se confirma con datos incompletos', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final start = await orch.publishEvent(
        ev(EventTypes.journeyStarted, id: 'app-start'),
        session: s,
      );
      expect(start.status, JourneyStatus.iniciado);
      expect(
        () => orch.publishEvent(
          ev(EventTypes.confirmationRequested,
              journeyId: start.journeyId, id: 'app-confirm'),
          session: s,
        ),
        throwsA(isA<OrchestratorException>()
            .having((e) => e.code, 'code', 'INVALID_TRANSITION')),
      );
    });

    test('trámite confirmado ya no admite cambios', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      await orch.publishEvent(
        ev(EventTypes.confirmationRequested, journeyId: 'ATN-2026-001', id: 'c1'),
        session: s,
      );
      expect(
        () => orch.publishEvent(
          ev(EventTypes.slotSelected,
              journeyId: 'ATN-2026-001', id: 'c2', data: const {'slotStart': 'x'}),
          session: s,
        ),
        throwsA(isA<OrchestratorException>()
            .having((e) => e.code, 'code', 'INVALID_TRANSITION')),
      );
    });

    test('una cita confirmada puede cancelarse', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      await orch.publishEvent(
        ev(EventTypes.confirmationRequested, journeyId: 'ATN-2026-001', id: 'cc1'),
        session: s,
      );
      final ack = await orch.publishEvent(
        ev(EventTypes.journeyCancelled,
            journeyId: 'ATN-2026-001', id: 'cc2', data: const {'reason': 'CANCELLED_BY_PATIENT'}),
        session: s,
      );
      expect(ack.status, JourneyStatus.cancelado);
    });

    test('identificación por correo electrónico', () async {
      final s = await orch.verifyIdentity(
        identifiers: const [PatientIdentifier(type: 'EMAIL', value: 'ana.garcia@example.com')],
        otp: '123456',
      );
      expect(s.patientRef, 'PAT-0001');
    });

    test('el estado sobrevive a un reinicio (persistencia durable)', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      await orch.publishEvent(
        ev(EventTypes.confirmationRequested, journeyId: 'ATN-2026-001', id: 'p1'),
        session: s,
      );
      final orch2 = MockOrchestrator(config);
      final s2 = await orch2.verifyIdentity(identifiers: ana, otp: '123456');
      final j = await orch2.getJourney('ATN-2026-001', s2);
      expect(j.status, JourneyStatus.confirmado);
    });
  });

  group('Disponibilidad de horarios (demo)', () {
    const clinic = {'clinicId': 'CLI-012', 'clinicName': 'Salud Digna Guadalajara Centro'};
    const study = {'studyId': 'STD-004', 'studyName': 'Rayos X de tórax', 'price': 180};

    Future<String> luisJourney(PatientSession sLuis, {DateTime? slot}) async {
      final start = await orch.publishEvent(ev(EventTypes.journeyStarted, id: 'l-start', ids: luis), session: sLuis);
      final id = start.journeyId;
      await orch.publishEvent(ev(EventTypes.studySelected, journeyId: id, id: 'l-study', ids: luis, data: study), session: sLuis);
      await orch.publishEvent(ev(EventTypes.clinicSelected, journeyId: id, id: 'l-clinic', ids: luis, data: clinic), session: sLuis);
      if (slot != null) {
        await orch.publishEvent(
            ev(EventTypes.slotSelected, journeyId: id, id: 'l-slot', ids: luis, data: {'slotStart': slot.toIso8601String()}),
            session: sLuis);
      }
      return id;
    }

    test('cancelar una cita confirmada libera el horario', () async {
      final sAna = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final anaSlot = DateTime.parse(
          (await orch.getJourney('ATN-2026-001', sAna)).slot!['slotStart'] as String);
      await orch.publishEvent(ev(EventTypes.confirmationRequested, journeyId: 'ATN-2026-001', id: 'a-confirm'),
          session: sAna);

      final sLuis = await orch.verifyIdentity(identifiers: luis, otp: '654321');
      final luisId = await luisJourney(sLuis);
      var free = await orch.availableSlots(journeyId: luisId, clinicId: 'CLI-012', session: sLuis);
      expect(free.any((d) => d.isAtSameMomentAs(anaSlot)), isFalse,
          reason: 'el horario confirmado por Ana no se ofrece a otros');

      await orch.publishEvent(
          ev(EventTypes.journeyCancelled, journeyId: 'ATN-2026-001', id: 'a-cancel',
              data: const {'reason': 'CANCELLED_BY_PATIENT'}),
          session: sAna);
      free = await orch.availableSlots(journeyId: luisId, clinicId: 'CLI-012', session: sLuis);
      expect(free.any((d) => d.isAtSameMomentAs(anaSlot)), isTrue,
          reason: 'al cancelar, el horario vuelve a estar disponible');
    });

    test('confirmar un horario ya tomado falla con mensaje claro y sin dejar el trámite a medias',
        () async {
      final sAna = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final anaSlot = DateTime.parse(
          (await orch.getJourney('ATN-2026-001', sAna)).slot!['slotStart'] as String);

      // Luis elige el mismo horario mientras aún está libre.
      final sLuis = await orch.verifyIdentity(identifiers: luis, otp: '654321');
      final luisId = await luisJourney(sLuis, slot: anaSlot);
      // Ana confirma primero (otro canal ganaría igual: la regla es del servidor).
      await orch.publishEvent(ev(EventTypes.confirmationRequested, journeyId: 'ATN-2026-001', id: 'a-confirm'),
          session: sAna);

      final before = await orch.getJourney(luisId, sLuis);
      await expectLater(
        orch.publishEvent(ev(EventTypes.confirmationRequested, journeyId: luisId, id: 'l-confirm', ids: luis),
            session: sLuis),
        throwsA(isA<OrchestratorException>()
            .having((e) => e.code, 'code', OrchestratorException.slotUnavailableCode)
            .having((e) => e.message, 'message', 'Ese horario ya no está disponible en esta clínica')),
      );

      final after = await orch.getJourney(luisId, sLuis);
      expect(after.status, isNot(JourneyStatus.confirmado));
      expect(after.appointment, isNull, reason: 'no se generó folio');
      expect(after.version, before.version, reason: 'no se aplicó ningún evento');
      expect(after.nextStep?.code, 'SELECT_SLOT', reason: 'se le pide elegir otro horario');
      expect(after.context['slotUnavailable'], isTrue);
    });

    test('reenvío desde el outbox tras una caída: no confirma un horario que se ocupó',
        () async {
      final sAna = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final anaSlot = DateTime.parse(
          (await orch.getJourney('ATN-2026-001', sAna)).slot!['slotStart'] as String);
      final sLuis = await orch.verifyIdentity(identifiers: luis, otp: '654321');
      final luisId = await luisJourney(sLuis, slot: anaSlot);

      // Luis confirma sin conexión: el evento queda en el outbox.
      final outbox = Outbox();
      await outbox.load();
      await config.update(mockFailures: true);
      final queued = await outbox.enqueueAndSend(
          ev(EventTypes.confirmationRequested, journeyId: luisId, id: 'l-offline', ids: luis),
          orch,
          session: sLuis);
      expect(queued, isNull);

      // Mientras tanto Ana confirma ese mismo horario.
      await config.update(mockFailures: false);
      await orch.publishEvent(ev(EventTypes.confirmationRequested, journeyId: 'ATN-2026-001', id: 'a-confirm'),
          session: sAna);

      // Al volver la conexión, el servidor revalida y rechaza; se avisa.
      final delivered = await outbox.flush(orch, session: sLuis);
      expect(delivered, 0);
      expect(outbox.isEmpty, isTrue);
      expect(outbox.lastRejections.single.isSlotUnavailable, isTrue);
      final after = await orch.getJourney(luisId, sLuis);
      expect(after.status, isNot(JourneyStatus.confirmado));
      expect(after.nextStep?.code, 'SELECT_SLOT');
    });

    test('la lista no incluye horarios ocupados', () async {
      final sAna = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final free = await orch.availableSlots(journeyId: 'ATN-2026-001', clinicId: 'CLI-012', session: sAna);
      final tomorrow = free.first;
      bool has(int h) => free.any((d) => d.day == tomorrow.day && d.hour == h);
      expect(has(9), isFalse);
      expect(has(11), isFalse);
      expect(has(10), isTrue, reason: 'su propio horario sigue disponible para ella');
      // Tlajomulco no tiene horarios mañana (demo del estado vacío).
      final tlajo = await orch.availableSlots(journeyId: 'ATN-2026-001', clinicId: 'CLI-015', session: sAna);
      expect(tlajo.where((d) => d.day == tomorrow.day), isEmpty);
    });
  });

  group('Outbox (entrega confiable)', () {
    test('si el orquestador cae, el evento queda en cola y luego se entrega',
        () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final outbox = Outbox();
      await outbox.load();

      await config.update(mockFailures: true);
      final ack = await outbox.enqueueAndSend(
        ev(EventTypes.contextResumed, journeyId: 'ATN-2026-001', id: 'ob-1'),
        orch,
        session: s,
      );
      expect(ack, isNull);
      expect(outbox.length, 1);
      expect(outbox.entries.first.lastError, isNotNull);

      await config.update(mockFailures: false);
      final delivered = await outbox.flush(orch, session: s);
      expect(delivered, 1);
      expect(outbox.isEmpty, isTrue);

      final events = await orch.listEvents('ATN-2026-001', s);
      expect(events.any((e) => e.eventId == 'ob-1'), isTrue);
    });

    test('un rechazo de negocio no se reintenta', () async {
      final s = await orch.verifyIdentity(identifiers: ana, otp: '123456');
      final outbox = Outbox();
      await outbox.load();
      expect(
        () => outbox.enqueueAndSend(
          ev(EventTypes.slotSelected, journeyId: 'NO-EXISTE', id: 'ob-2'),
          orch,
          session: s,
        ),
        throwsA(isA<OrchestratorException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(outbox.isEmpty, isTrue);
    });
  });
}
