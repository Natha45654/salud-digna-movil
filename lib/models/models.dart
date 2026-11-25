/// Modelos del contrato con el orquestador omnicanal.
///
/// Basados en el documento "Arquitectura acordada del orquestador omnicanal"
/// (secciones 5, 6, 7, 8 y 9). Los nombres de campos son los propuestos en
/// ese documento; cualquier cambio del backend debe reflejarse aquí.
library;

/// Identificador tipado de paciente (sección 6 del documento de arquitectura).
class PatientIdentifier {
  final String type; // PATIENT_ID | PHONE | EMAIL (lo que entrega la página oficial)
  final String value;

  const PatientIdentifier({required this.type, required this.value});

  Map<String, dynamic> toJson() => {'type': type, 'value': value};

  factory PatientIdentifier.fromJson(Map<String, dynamic> json) =>
      PatientIdentifier(
        type: json['type'] as String,
        value: json['value'] as String,
      );

  @override
  String toString() => '$type:$value';
}

/// Canales reconocidos por el orquestador.
class Channels {
  static const web = 'WEB';
  static const mobileApp = 'MOBILE_APP';
  static const whatsapp = 'WHATSAPP';
  static const callCenter = 'CALL_CENTER';
  static const clinic = 'CLINIC';

  static String label(String code) => switch (code) {
        web => 'Sitio Web',
        mobileApp => 'App móvil',
        whatsapp => 'WhatsApp',
        callCenter => 'Call Center',
        clinic => 'Clínica',
        _ => code,
      };
}

/// Catálogo canónico de eventos de negocio (sección 9 y 12 del documento).
class EventTypes {
  static const journeyStarted = 'JOURNEY_STARTED';
  static const studySelected = 'STUDY_SELECTED';
  static const clinicSelected = 'CLINIC_SELECTED';
  static const slotSelected = 'SLOT_SELECTED';
  static const identityVerified = 'IDENTITY_VERIFIED';
  static const contextResumed = 'CONTEXT_RESUMED';
  static const requestResumed = 'REQUEST_RESUMED';
  static const channelSwitched = 'CHANNEL_SWITCHED';
  static const contactInitiated = 'CONTACT_INITIATED';
  static const confirmationRequested = 'CONFIRMATION_REQUESTED';
  static const appointmentConfirmed = 'APPOINTMENT_CONFIRMED';
  static const journeyCancelled = 'JOURNEY_CANCELLED';

  static String label(String code) => switch (code) {
        journeyStarted => 'Trámite iniciado',
        studySelected => 'Estudio seleccionado',
        clinicSelected => 'Clínica seleccionada',
        slotSelected => 'Horario seleccionado',
        identityVerified => 'Identidad verificada',
        contextResumed => 'Trámite retomado en otro canal',
        requestResumed => 'Trámite retomado',
        channelSwitched => 'Cambio de canal',
        contactInitiated => 'Contacto con Salud Digna',
        confirmationRequested => 'Confirmación solicitada',
        appointmentConfirmed => 'Cita confirmada',
        journeyCancelled => 'Trámite cancelado',
        _ => code,
      };
}

/// Estados del trámite y sus transiciones válidas.
class JourneyStatus {
  static const iniciado = 'INICIADO';
  static const enCaptura = 'EN_CAPTURA';
  static const pendienteConfirmacion = 'PENDIENTE_CONFIRMACION';
  static const confirmado = 'CONFIRMADO';
  static const cancelado = 'CANCELADO';

  static String label(String code) => switch (code) {
        iniciado => 'Iniciado',
        enCaptura => 'En captura',
        pendienteConfirmacion => 'Pendiente de confirmación',
        confirmado => 'Confirmado',
        cancelado => 'Cancelado',
        _ => code,
      };

  static bool isOpen(String code) =>
      code != confirmado && code != cancelado;
}

/// Evento canónico (sección 8 del documento de arquitectura).
class CanonicalEvent {
  final String eventId;
  final String sourceSystem;
  final List<PatientIdentifier> patientIdentifiers;
  final String? journeyId;
  final String eventType;
  final DateTime occurredAt;
  final Map<String, dynamic> data;

  /// Control optimista de concurrencia (requisito 12 "Concurrencia").
  final int? expectedVersion;

  const CanonicalEvent({
    required this.eventId,
    required this.sourceSystem,
    required this.patientIdentifiers,
    required this.journeyId,
    required this.eventType,
    required this.occurredAt,
    this.data = const {},
    this.expectedVersion,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'sourceSystem': sourceSystem,
        'patientIdentifiers':
            patientIdentifiers.map((e) => e.toJson()).toList(),
        if (journeyId != null) 'journeyId': journeyId,
        'eventType': eventType,
        'occurredAt': occurredAt.toIso8601String(),
        'data': data,
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
      };

  factory CanonicalEvent.fromJson(Map<String, dynamic> json) => CanonicalEvent(
        eventId: json['eventId'] as String,
        sourceSystem: json['sourceSystem'] as String,
        patientIdentifiers: ((json['patientIdentifiers'] as List?) ?? [])
            .map((e) => PatientIdentifier.fromJson(e as Map<String, dynamic>))
            .toList(),
        journeyId: json['journeyId'] as String?,
        eventType: json['eventType'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        data: Map<String, dynamic>.from((json['data'] as Map?) ?? {}),
        expectedVersion: json['expectedVersion'] as int?,
      );
}

/// Respuesta del orquestador al registrar un evento.
class EventAck {
  final bool accepted;
  final bool duplicate;
  final String journeyId;
  final int version;
  final String status;

  const EventAck({
    required this.accepted,
    required this.duplicate,
    required this.journeyId,
    required this.version,
    required this.status,
  });

  factory EventAck.fromJson(Map<String, dynamic> json) => EventAck(
        accepted: json['accepted'] as bool? ?? true,
        duplicate: json['duplicate'] as bool? ?? false,
        journeyId: json['journeyId'] as String,
        version: json['version'] as int,
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'duplicate': duplicate,
        'journeyId': journeyId,
        'version': version,
        'status': status,
      };
}

/// Próximo paso permitido que el orquestador le sugiere al canal.
class NextStep {
  final String code;
  final String label;

  const NextStep({required this.code, required this.label});

  factory NextStep.fromJson(Map<String, dynamic> json) => NextStep(
        code: json['code'] as String,
        label: json['label'] as String,
      );

  Map<String, dynamic> toJson() => {'code': code, 'label': label};
}

/// Proyección de contexto de un trámite (entidades Journey + JourneyContext).
class Journey {
  final String journeyId;
  final String patientRef;
  final String type;
  final String status;
  final int version;
  final String lastChannel;
  final DateTime updatedAt;
  final List<String> channels;
  final Map<String, dynamic> context;
  final List<String> pendingFields;
  final NextStep? nextStep;

  const Journey({
    required this.journeyId,
    required this.patientRef,
    required this.type,
    required this.status,
    required this.version,
    required this.lastChannel,
    required this.updatedAt,
    required this.channels,
    required this.context,
    required this.pendingFields,
    required this.nextStep,
  });

  Map<String, dynamic>? get study => _map('study');
  Map<String, dynamic>? get clinic => _map('clinic');
  Map<String, dynamic>? get slot => _map('slot');
  Map<String, dynamic>? get appointment => _map('appointment');

  Map<String, dynamic>? _map(String key) {
    final v = context[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  factory Journey.fromJson(Map<String, dynamic> json) => Journey(
        journeyId: json['journeyId'] as String,
        patientRef: json['patientRef'] as String,
        type: json['type'] as String? ?? 'APPOINTMENT_BOOKING',
        status: json['status'] as String,
        version: json['version'] as int,
        lastChannel: json['lastChannel'] as String? ?? '',
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        channels: List<String>.from((json['channels'] as List?) ?? []),
        context: Map<String, dynamic>.from((json['context'] as Map?) ?? {}),
        pendingFields:
            List<String>.from((json['pendingFields'] as List?) ?? []),
        nextStep: json['nextStep'] == null
            ? null
            : NextStep.fromJson(json['nextStep'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'journeyId': journeyId,
        'patientRef': patientRef,
        'type': type,
        'status': status,
        'version': version,
        'lastChannel': lastChannel,
        'updatedAt': updatedAt.toIso8601String(),
        'channels': channels,
        'context': context,
        'pendingFields': pendingFields,
        if (nextStep != null) 'nextStep': nextStep!.toJson(),
      };
}

/// Sesión del paciente una vez verificada su identidad.
class PatientSession {
  final String patientRef;
  final String displayName;
  final String token;
  final String verificationLevel; // UNVERIFIED | VERIFIED
  final List<PatientIdentifier> identifiers;

  const PatientSession({
    required this.patientRef,
    required this.displayName,
    required this.token,
    required this.verificationLevel,
    required this.identifiers,
  });

  factory PatientSession.fromJson(Map<String, dynamic> json) => PatientSession(
        patientRef: json['patientRef'] as String,
        displayName: json['displayName'] as String? ?? 'Paciente',
        token: json['token'] as String,
        verificationLevel: json['verificationLevel'] as String? ?? 'VERIFIED',
        identifiers: ((json['identifiers'] as List?) ?? [])
            .map((e) => PatientIdentifier.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'patientRef': patientRef,
        'displayName': displayName,
        'token': token,
        'verificationLevel': verificationLevel,
        'identifiers': identifiers.map((e) => e.toJson()).toList(),
      };
}

/// Error de negocio devuelto por el orquestador.
class OrchestratorException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const OrchestratorException(this.statusCode, this.code, this.message);

  bool get isConflict => statusCode == 409;

  /// El horario elegido ya no está disponible en esa clínica (otro paciente,
  /// por cualquier canal, lo tomó primero). Hay que elegir otro.
  bool get isSlotUnavailable => code == slotUnavailableCode;
  static const slotUnavailableCode = 'SLOT_UNAVAILABLE';
  static const slotUnavailableMessage = 'Ese horario ya no está disponible en esta clínica';
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => '[$statusCode $code] $message';
}

/// Error de red: el evento debe quedar en el outbox y reintentarse.
class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);

  @override
  String toString() => message;
}
