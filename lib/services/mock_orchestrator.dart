import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../data/catalog.dart';
import '../models/models.dart';
import 'orchestrator_client.dart';

/// Orquestador simulado que corre dentro de la app.
///
/// Implementa los mismos contratos que [HttpOrchestrator] y aplica las reglas
/// no negociables de la sección 12 del documento de arquitectura:
///
/// - Identidad verificada: solo entrega trámites tras OTP válido y solo los del
///   paciente autenticado (403 en caso contrario).
/// - Idempotencia: un `eventId` repetido no duplica eventos (`duplicate: true`).
/// - Concurrencia: `expectedVersion` distinto a la versión actual → 409.
/// - Semántica de negocio: transiciones de estado explícitas.
/// - Persistencia durable: el estado se guarda en SharedPreferences, así la
///   demo sobrevive al cierre de la app.
///
/// Disponibilidad de horarios (DEMO, ver [availableSlots]): un horario se
/// identifica por clínica + fecha + hora y queda ocupado mientras exista una
/// cita confirmada en él. Al cancelar se libera. Se revalida al elegir horario
/// y al confirmar (también cuando la confirmación sale del outbox tras una
/// caída). La autoridad real es el sistema de citas de Salud Digna.
///
/// Viene sembrado con el recorrido de Ana (Web → WhatsApp) descrito en el reto:
/// cotizó un ultrasonido y eligió clínica en Web, retomó en WhatsApp y eligió
/// horario, pero no confirmó. La app móvil debe permitirle concluir.
class MockOrchestrator implements OrchestratorClient {
  static const _kStore = 'mock.store.v1';
  static const _uuid = Uuid();
  final AppConfig config;

  final Map<String, _MasterPatient> _patients = {};
  final Map<String, _JourneyRecord> _journeys = {};
  final Map<String, String> _tokens = {}; // token -> patientRef

  /// DEMO: horarios ya tomados por pacientes de otros canales (no pasan por
  /// esta app). Se recalculan respecto al día actual en cada arranque.
  final Set<String> _externalBookings = {};
  bool _loaded = false;

  MockOrchestrator(this.config);

  // ---------------------------------------------------------------- seeding

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    _seedPatients();
    _seedExternalBookings();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStore);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final j in (map['journeys'] as List)) {
          final rec = _JourneyRecord.fromJson(Map<String, dynamic>.from(j));
          _journeys[rec.journeyId] = rec;
        }
        return;
      } catch (_) {
        // Si el almacenamiento está corrupto, se vuelve a sembrar.
      }
    }
    _seedAnaJourney();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kStore,
      jsonEncode({'journeys': _journeys.values.map((j) => j.toJson()).toList()}),
    );
  }

  /// Restablece el escenario de demostración.
  Future<void> reset() async {
    _journeys.clear();
    _seedAnaJourney();
    await _persist();
  }

  void _seedPatients() {
    _patients.clear();
    _patients['PAT-0001'] = _MasterPatient(
      patientRef: 'PAT-0001',
      displayName: 'Ana García',
      otp: '123456',
      identifiers: const [
        PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456'),
        PatientIdentifier(type: 'PHONE', value: '+525512345678'),
        PatientIdentifier(type: 'EMAIL', value: 'ana.garcia@example.com'),
      ],
    );
    _patients['PAT-0002'] = _MasterPatient(
      patientRef: 'PAT-0002',
      displayName: 'Luis Hernández',
      otp: '654321',
      identifiers: const [
        PatientIdentifier(type: 'PATIENT_ID', value: 'SD-654321'),
        PatientIdentifier(type: 'PHONE', value: '+523312345678'),
        PatientIdentifier(type: 'EMAIL', value: 'luis.hernandez@example.com'),
      ],
    );
  }

  /// Clave de disponibilidad: clínica + fecha + hora (hora local, a minutos).
  static String slotKey(String clinicId, DateTime slot) {
    final l = slot.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '$clinicId|${l.year}-${two(l.month)}-${two(l.day)}T${two(l.hour)}:${two(l.minute)}';
  }

  void _seedExternalBookings() {
    _externalBookings.clear();
    final slots = catalogSlots();
    final tomorrow = slots.first;
    // Guadalajara Centro: mañana 09:00 y 11:00 tomados por otros canales.
    for (final h in const [9, 11]) {
      _externalBookings.add(slotKey('CLI-012',
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h)));
    }
    // Tlajomulco: mañana sin horarios (muestra el estado vacío del selector).
    for (final s in slots.where((d) => d.day == tomorrow.day)) {
      _externalBookings.add(slotKey('CLI-015', s));
    }
  }

  /// Quién ocupa un horario: id del trámite confirmado, 'EXTERNAL' o null.
  String? _occupant(String key) {
    if (_externalBookings.contains(key)) return 'EXTERNAL';
    for (final rec in _journeys.values) {
      if (rec.status != JourneyStatus.confirmado) continue;
      final k = rec.bookingKey;
      if (k != null && k == key) return rec.journeyId;
    }
    return null;
  }

  bool _takenByOther(String key, String journeyId) {
    final who = _occupant(key);
    return who != null && who != journeyId;
  }

  /// Proyección con disponibilidad: si el horario elegido ya lo tomó otro
  /// paciente, el trámite vuelve a pedir horario (sin perder lo demás).
  Journey _project(_JourneyRecord rec) {
    final j = rec.toJourney();
    final key = rec.bookingKey;
    if (!JourneyStatus.isOpen(j.status) || key == null || !_takenByOther(key, rec.journeyId)) {
      return j;
    }
    return Journey(
      journeyId: j.journeyId,
      patientRef: j.patientRef,
      type: j.type,
      status: JourneyStatus.enCaptura,
      version: j.version,
      lastChannel: j.lastChannel,
      updatedAt: j.updatedAt,
      channels: j.channels,
      context: {...j.context, 'slotUnavailable': true},
      pendingFields: [...j.pendingFields, 'horario'],
      nextStep: const NextStep(code: 'SELECT_SLOT', label: 'Elige un horario'),
    );
  }

  void _seedAnaJourney() {
    final t0 = DateTime.now().subtract(const Duration(hours: 5));
    final ids = [const PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456')];
    final rec = _JourneyRecord(journeyId: 'ATN-2026-001', patientRef: 'PAT-0001');
    final seed = <CanonicalEvent>[
      CanonicalEvent(
        eventId: 'web-0001',
        sourceSystem: Channels.web,
        patientIdentifiers: ids,
        journeyId: rec.journeyId,
        eventType: EventTypes.journeyStarted,
        occurredAt: t0,
        data: const {'journeyType': 'APPOINTMENT_BOOKING'},
      ),
      CanonicalEvent(
        eventId: 'web-0002',
        sourceSystem: Channels.web,
        patientIdentifiers: ids,
        journeyId: rec.journeyId,
        eventType: EventTypes.studySelected,
        occurredAt: t0.add(const Duration(minutes: 2)),
        data: studies.first.toJson(),
      ),
      CanonicalEvent(
        eventId: 'web-0003',
        sourceSystem: Channels.web,
        patientIdentifiers: ids,
        journeyId: rec.journeyId,
        eventType: EventTypes.clinicSelected,
        occurredAt: t0.add(const Duration(minutes: 4)),
        data: clinics.first.toJson(),
      ),
      CanonicalEvent(
        eventId: 'wa-0001',
        sourceSystem: Channels.whatsapp,
        patientIdentifiers: const [
          PatientIdentifier(type: 'PHONE', value: '+525512345678'),
        ],
        journeyId: rec.journeyId,
        eventType: EventTypes.contextResumed,
        occurredAt: t0.add(const Duration(hours: 2)),
        data: const {'previousChannel': Channels.web},
      ),
      CanonicalEvent(
        eventId: 'wa-0002',
        sourceSystem: Channels.whatsapp,
        patientIdentifiers: const [
          PatientIdentifier(type: 'PHONE', value: '+525512345678'),
        ],
        journeyId: rec.journeyId,
        eventType: EventTypes.slotSelected,
        occurredAt: t0.add(const Duration(hours: 2, minutes: 3)),
        data: {'slotStart': catalogSlots()[2].toIso8601String()},
      ),
    ];
    for (final e in seed) {
      rec.apply(e);
    }
    _journeys[rec.journeyId] = rec;
  }

  // ----------------------------------------------------------------- helpers

  Future<void> _maybeFail() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (config.mockFailures) {
      throw const NetworkException(
          'Fallo simulado del orquestador (modo "simular caída" activo)');
    }
  }

  _MasterPatient? _resolve(List<PatientIdentifier> ids) {
    final matches = <_MasterPatient>{};
    for (final p in _patients.values) {
      for (final id in ids) {
        if (p.identifiers.any((x) => x.type == id.type && x.value == id.value)) {
          matches.add(p);
        }
      }
    }
    // Regla de seguridad (sección 6): ante coincidencias ambiguas no vincular.
    return matches.length == 1 ? matches.first : null;
  }

  String _requirePatient(PatientSession session) {
    final ref = _tokens[session.token];
    if (ref == null || ref != session.patientRef) {
      // Los tokens viven en memoria; al reiniciar la app se vuelve a emitir
      // uno equivalente si la sesión persistida es coherente con el maestro.
      final p = _patients[session.patientRef];
      if (p != null && session.token.startsWith('mock-')) {
        _tokens[session.token] = p.patientRef;
        return p.patientRef;
      }
      throw const OrchestratorException(401, 'UNAUTHORIZED', 'Sesión inválida');
    }
    return ref;
  }

  // --------------------------------------------------------------- contracts

  @override
  Future<PatientSession> verifyIdentity({
    required List<PatientIdentifier> identifiers,
    required String otp,
  }) async {
    await _ensureLoaded();
    await _maybeFail();
    final p = _resolve(identifiers);
    if (p == null) {
      throw const OrchestratorException(404, 'PATIENT_NOT_FOUND',
          'No se encontró un paciente único con esos identificadores');
    }
    if (p.otp != otp) {
      throw const OrchestratorException(
          401, 'INVALID_OTP', 'Código de verificación incorrecto');
    }
    final token = 'mock-${_uuid.v4()}';
    _tokens[token] = p.patientRef;
    return PatientSession(
      patientRef: p.patientRef,
      displayName: p.displayName,
      token: token,
      verificationLevel: 'VERIFIED',
      identifiers: p.identifiers,
    );
  }

  @override
  Future<EventAck> publishEvent(CanonicalEvent event,
      {PatientSession? session}) async {
    await _ensureLoaded();
    await _maybeFail();

    // Resolución de identidad por identificadores tipados.
    final patient = _resolve(event.patientIdentifiers);
    if (patient == null) {
      throw const OrchestratorException(422, 'IDENTITY_UNRESOLVED',
          'Los identificadores no resuelven a un paciente único');
    }
    if (session != null && _requirePatient(session) != patient.patientRef) {
      throw const OrchestratorException(
          403, 'FORBIDDEN', 'El paciente autenticado no coincide con el evento');
    }

    // Idempotencia por eventId en toda la base.
    for (final rec in _journeys.values) {
      if (rec.events.any((e) => e.eventId == event.eventId)) {
        return EventAck(
          accepted: true,
          duplicate: true,
          journeyId: rec.journeyId,
          version: rec.version,
          status: rec.status,
        );
      }
    }

    _JourneyRecord rec;
    if (event.eventType == EventTypes.journeyStarted) {
      final id = event.journeyId ??
          'ATN-${DateTime.now().year}-${(_journeys.length + 1).toString().padLeft(3, '0')}';
      if (_journeys.containsKey(id)) {
        throw OrchestratorException(
            409, 'JOURNEY_EXISTS', 'El trámite $id ya existe');
      }
      rec = _JourneyRecord(journeyId: id, patientRef: patient.patientRef);
      _journeys[id] = rec;
    } else {
      final id = event.journeyId;
      if (id == null || !_journeys.containsKey(id)) {
        throw const OrchestratorException(
            404, 'JOURNEY_NOT_FOUND', 'El trámite indicado no existe');
      }
      rec = _journeys[id]!;
      if (rec.patientRef != patient.patientRef) {
        throw const OrchestratorException(
            403, 'FORBIDDEN', 'El trámite pertenece a otro paciente');
      }
    }

    // Control optimista de concurrencia.
    if (event.expectedVersion != null && event.expectedVersion != rec.version) {
      throw OrchestratorException(409, 'VERSION_CONFLICT',
          'El trámite cambió (versión actual ${rec.version}, esperada ${event.expectedVersion}). Recarga el contexto.');
    }

    final error = rec.validateTransition(event.eventType);
    if (error != null) {
      throw OrchestratorException(422, 'INVALID_TRANSITION', error);
    }

    // Disponibilidad (DEMO): se revalida al elegir horario y al confirmar.
    // Si otro paciente ya lo tomó, no se aplica nada: el trámite queda igual.
    String? keyToCheck;
    if (event.eventType == EventTypes.slotSelected) {
      final clinicId = rec.clinicId;
      final raw = event.data['slotStart'];
      if (clinicId != null && raw is String) {
        final slot = DateTime.tryParse(raw);
        if (slot != null) keyToCheck = slotKey(clinicId, slot);
      }
    } else if (event.eventType == EventTypes.confirmationRequested) {
      keyToCheck = rec.bookingKey;
    }
    if (keyToCheck != null && _takenByOther(keyToCheck, rec.journeyId)) {
      throw const OrchestratorException(409, OrchestratorException.slotUnavailableCode,
          OrchestratorException.slotUnavailableMessage);
    }

    rec.apply(CanonicalEvent(
      eventId: event.eventId,
      sourceSystem: event.sourceSystem,
      patientIdentifiers: event.patientIdentifiers,
      journeyId: rec.journeyId,
      eventType: event.eventType,
      occurredAt: event.occurredAt,
      data: event.data,
    ));

    // El sistema oficial de citas confirma: el simulador responde con un
    // evento de confirmación como si viniera del sistema autorizado.
    if (event.eventType == EventTypes.confirmationRequested) {
      rec.apply(CanonicalEvent(
        eventId: 'sys-${_uuid.v4()}',
        sourceSystem: 'APPOINTMENT_SYSTEM',
        patientIdentifiers: event.patientIdentifiers,
        journeyId: rec.journeyId,
        eventType: EventTypes.appointmentConfirmed,
        occurredAt: DateTime.now(),
        data: {
          'appointmentId': 'CITA-${_uuid.v4().substring(0, 8).toUpperCase()}',
          'confirmedVia': event.sourceSystem,
        },
      ));
    }

    await _persist();
    return EventAck(
      accepted: true,
      duplicate: false,
      journeyId: rec.journeyId,
      version: rec.version,
      status: rec.status,
    );
  }

  @override
  Future<List<Journey>> listJourneys(PatientSession session, {String status = 'all'}) async {
    await _ensureLoaded();
    await _maybeFail();
    // El paciente sale de la sesión verificada (401 si no es válida).
    final ref = _requirePatient(session);
    final list = _journeys.values
        .where((j) => j.patientRef == ref)
        .map(_project)
        .where((j) => switch (status) {
              'open' => JourneyStatus.isOpen(j.status),
              'closed' => !JourneyStatus.isOpen(j.status),
              _ => true,
            })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<Journey> getJourney(String journeyId, PatientSession session) async {
    await _ensureLoaded();
    await _maybeFail();
    final ref = _requirePatient(session);
    final rec = _journeys[journeyId];
    if (rec == null) {
      throw const OrchestratorException(
          404, 'JOURNEY_NOT_FOUND', 'El trámite no existe');
    }
    if (rec.patientRef != ref) {
      throw const OrchestratorException(
          403, 'FORBIDDEN', 'No tienes acceso a este trámite');
    }
    return _project(rec);
  }

  /// DEMO: horarios libres en la clínica para este trámite. Los ocupados (por
  /// citas confirmadas de cualquier paciente o por otros canales) no se listan.
  @override
  Future<List<DateTime>> availableSlots({
    required String journeyId,
    required String clinicId,
    required PatientSession session,
  }) async {
    final j = await getJourney(journeyId, session);
    return [
      for (final slot in catalogSlots())
        if (!_takenByOther(slotKey(clinicId, slot), j.journeyId)) slot,
    ];
  }

  @override
  Future<List<CanonicalEvent>> listEvents(
      String journeyId, PatientSession session) async {
    final j = await getJourney(journeyId, session);
    return List.unmodifiable(_journeys[j.journeyId]!.events);
  }

  /// En el simulador el código de acceso de demo es el propio id del trámite
  /// (o su forma codificada "id:grant" en base64url, como en el backend real).
  @override
  Future<void> linkJourney(
      {required String code, required PatientSession session}) async {
    await _ensureLoaded();
    await _maybeFail();
    final ref = _requirePatient(session);
    var journeyId = code.trim();
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(journeyId)));
      if (decoded.contains(':')) journeyId = decoded.split(':').first;
    } catch (_) {
      // no estaba codificado: se usa tal cual
    }
    final rec = _journeys[journeyId];
    if (rec == null) {
      throw const OrchestratorException(
          404, 'CODE_INVALID', 'El código de acceso no es válido');
    }
    if (rec.patientRef != ref) {
      throw const OrchestratorException(
          403, 'FORBIDDEN', 'El trámite pertenece a otro paciente');
    }
  }
}

class _MasterPatient {
  final String patientRef;
  final String displayName;
  final String otp;
  final List<PatientIdentifier> identifiers;
  const _MasterPatient({
    required this.patientRef,
    required this.displayName,
    required this.otp,
    required this.identifiers,
  });
}

/// Registro interno: Journey + JourneyContext + JourneyEvent[].
class _JourneyRecord {
  final String journeyId;
  final String patientRef;
  final List<CanonicalEvent> events = [];
  String status = JourneyStatus.iniciado;
  int version = 0;
  Map<String, dynamic> context = {};
  final List<String> channels = [];
  String lastChannel = '';
  DateTime updatedAt = DateTime.now();

  _JourneyRecord({required this.journeyId, required this.patientRef});

  String? validateTransition(String eventType) {
    // Una cita confirmada puede cancelarse; lo demás queda cerrado.
    if (status == JourneyStatus.confirmado &&
        eventType == EventTypes.journeyCancelled) {
      return null;
    }
    if (!JourneyStatus.isOpen(status) &&
        eventType != EventTypes.contextResumed) {
      return 'El trámite está ${JourneyStatus.label(status).toLowerCase()} y no admite más cambios';
    }
    switch (eventType) {
      case EventTypes.journeyStarted:
        return events.isEmpty ? null : 'El trámite ya fue iniciado';
      case EventTypes.confirmationRequested:
        final missing = _pendingFields();
        return missing.isEmpty
            ? null
            : 'Faltan datos para confirmar: ${missing.join(', ')}';
      case EventTypes.appointmentConfirmed:
        return status == JourneyStatus.pendienteConfirmacion
            ? null
            : 'Solo se confirma un trámite pendiente de confirmación';
      default:
        return null;
    }
  }

  String? get clinicId {
    final c = context['clinic'];
    return c is Map ? c['clinicId'] as String? : null;
  }

  /// Clave clínica + fecha + hora del horario elegido, si hay ambos.
  String? get bookingKey {
    final c = clinicId;
    final s = context['slot'];
    final raw = s is Map ? s['slotStart'] : null;
    if (c == null || raw is! String) return null;
    final slot = DateTime.tryParse(raw);
    return slot == null ? null : MockOrchestrator.slotKey(c, slot);
  }

  List<String> _pendingFields() => [
        if (context['study'] == null) 'estudio',
        if (context['clinic'] == null) 'clínica',
        if (context['slot'] == null) 'horario',
      ];

  void apply(CanonicalEvent e) {
    events.add(e);
    version++;
    updatedAt = e.occurredAt;
    lastChannel = e.sourceSystem;
    if (!channels.contains(e.sourceSystem)) channels.add(e.sourceSystem);

    switch (e.eventType) {
      case EventTypes.studySelected:
        context['study'] = e.data;
      case EventTypes.clinicSelected:
        context['clinic'] = e.data;
      case EventTypes.slotSelected:
        context['slot'] = e.data;
      case EventTypes.appointmentConfirmed:
        context['appointment'] = e.data;
        status = JourneyStatus.confirmado;
        return;
      case EventTypes.journeyCancelled:
        status = JourneyStatus.cancelado;
        return;
    }
    if (status != JourneyStatus.confirmado && status != JourneyStatus.cancelado) {
      status = _pendingFields().isEmpty
          ? JourneyStatus.pendienteConfirmacion
          : (events.length > 1 ? JourneyStatus.enCaptura : JourneyStatus.iniciado);
    }
  }

  NextStep? _nextStep() => switch (status) {
        JourneyStatus.confirmado => const NextStep(
            code: 'VIEW_APPOINTMENT', label: 'Tu cita está confirmada'),
        JourneyStatus.cancelado => null,
        _ when context['study'] == null =>
          const NextStep(code: 'SELECT_STUDY', label: 'Elige tu estudio'),
        _ when context['clinic'] == null =>
          const NextStep(code: 'SELECT_CLINIC', label: 'Elige tu clínica'),
        _ when context['slot'] == null =>
          const NextStep(code: 'SELECT_SLOT', label: 'Elige un horario'),
        _ => const NextStep(
            code: 'CONFIRM_APPOINTMENT', label: 'Confirma tu cita'),
      };

  Journey toJourney() => Journey(
        journeyId: journeyId,
        patientRef: patientRef,
        type: 'APPOINTMENT_BOOKING',
        status: status,
        version: version,
        lastChannel: lastChannel,
        updatedAt: updatedAt,
        channels: List.of(channels),
        context: Map.of(context),
        pendingFields: _pendingFields(),
        nextStep: _nextStep(),
      );

  Map<String, dynamic> toJson() => {
        'journeyId': journeyId,
        'patientRef': patientRef,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory _JourneyRecord.fromJson(Map<String, dynamic> json) {
    final rec = _JourneyRecord(
      journeyId: json['journeyId'] as String,
      patientRef: json['patientRef'] as String,
    );
    for (final e in (json['events'] as List)) {
      rec.apply(CanonicalEvent.fromJson(Map<String, dynamic>.from(e as Map)));
    }
    return rec;
  }
}
