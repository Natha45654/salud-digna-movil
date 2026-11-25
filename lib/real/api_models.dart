/// Modelos del contrato de la API central (modo real).
///
/// Fuente: docs/api-auth.md, docs/api-mobile-journeys.md, docs/api-studies.md,
/// docs/api-clinics.md y docs/openapi.json del repositorio de la API central.
/// Solo se leen los campos documentados; no se completan campos ausentes.
library;

/// Estados de `JourneyStatus` del orquestador.
class ApiJourneyStatus {
  static const draft = 'DRAFT';
  static const inProgress = 'IN_PROGRESS';
  static const pendingConfirmation = 'PENDING_CONFIRMATION';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';

  /// Estados en los que el trámite admite avances del paciente.
  static bool isEditable(String s) => s == draft || s == inProgress;

  /// Estados en los que se admite la cancelación ("desde un estado abierto").
  static bool isOpen(String s) => s == draft || s == inProgress || s == pendingConfirmation;
}

/// Pasos (`currentStep`) del contexto de un trámite `APPOINTMENT`.
class ApiJourneySteps {
  static const selectStudy = 'SELECT_STUDY';
  static const selectClinic = 'SELECT_CLINIC';
  static const selectDatetime = 'SELECT_DATETIME';
  static const review = 'REVIEW';
  static const confirmed = 'CONFIRMED';

  static String label(String step) => switch (step) {
        selectStudy => 'Elegir estudio',
        selectClinic => 'Elegir clínica',
        selectDatetime => 'Elegir fecha y hora',
        review => 'Revisión',
        confirmed => 'Confirmado',
        _ => step,
      };
}

/// Tipos de evento del historial y de publicación.
class ApiEventTypes {
  static const created = 'JOURNEY_CREATED';
  static const contextUpdated = 'JOURNEY_CONTEXT_UPDATED';
  static const statusChanged = 'JOURNEY_STATUS_CHANGED';
  static const appointmentConfirmed = 'APPOINTMENT_CONFIRMED';

  static String label(String type) => switch (type) {
        created => 'Trámite iniciado',
        contextUpdated => 'Datos del trámite actualizados',
        statusChanged => 'Cambio de estado',
        appointmentConfirmed => 'Cita confirmada',
        _ => type,
      };
}

/// Canales registrados en el orquestador (`producerCode`).
class Producers {
  static const web = 'demo-web';
  static const mobile = 'demo-mobile';
  static const callCenter = 'demo-callcenter';
  static const whatsapp = 'demo-whatsapp';
  static const admin = 'demo-admin';

  static String label(String code) => switch (code) {
        web => 'Sitio Web',
        mobile => 'App móvil',
        callCenter => 'Call Center',
        whatsapp => 'WhatsApp',
        admin => 'Administración',
        _ => code,
      };
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String _str(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is String) return v;
  throw FormatException('Campo "$key" ausente o inválido en la respuesta');
}

String? _optStr(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is String ? v : null;
}

DateTime _date(Map<String, dynamic> json, String key) => DateTime.parse(_str(json, key));

// ------------------------------------------------------------------ auth

/// Respuesta de `POST /auth/login`.
class LoginResult {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String userId;
  final String email;
  final String role;

  const LoginResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.userId,
    required this.email,
    required this.role,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    return LoginResult(
      accessToken: _str(json, 'accessToken'),
      tokenType: _optStr(json, 'tokenType') ?? 'Bearer',
      expiresIn: (json['expiresIn'] as num).toInt(),
      userId: _str(user, 'id'),
      email: _str(user, 'email'),
      role: _str(user, 'role'),
    );
  }
}

/// Perfil del paciente vinculado a la cuenta.
class PatientProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;

  const PatientProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
        id: _str(json, 'id'),
        firstName: _optStr(json, 'firstName') ?? '',
        lastName: _optStr(json, 'lastName') ?? '',
        email: _optStr(json, 'email'),
        phone: _optStr(json, 'phone'),
      );
}

/// Respuesta de `GET /auth/me`.
class AccountInfo {
  final String id;
  final String email;
  final String role;
  final bool isActive;

  /// Identificador institucional del paciente (no el UUID de la cuenta).
  final String? patientId;
  final PatientProfile? patient;

  const AccountInfo({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    required this.patientId,
    required this.patient,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
        id: _str(json, 'id'),
        email: _str(json, 'email'),
        role: _str(json, 'role'),
        isActive: json['isActive'] as bool? ?? false,
        patientId: _optStr(json, 'patientId'),
        patient: json['patient'] is Map ? PatientProfile.fromJson(_map(json['patient'])) : null,
      );
}

/// Sesión del paciente en modo real. Vive solo en memoria: el JWT nunca se
/// escribe en disco.
class ApiSession {
  final String accessToken;
  final DateTime expiresAt;
  final AccountInfo account;

  const ApiSession({required this.accessToken, required this.expiresAt, required this.account});

  String get patientId => account.patientId!;
  String get displayName => account.patient?.fullName.isNotEmpty == true
      ? account.patient!.fullName
      : account.email;

  bool isExpired([DateTime? now]) => !(now ?? DateTime.now()).isBefore(expiresAt);
}

// -------------------------------------------------------------- trámites

/// Elemento de `GET /mobile/journeys` y respuesta de `GET /mobile/journeys/:id`.
class JourneySummary {
  final String id;
  final String type;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JourneySummary({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JourneySummary.fromJson(Map<String, dynamic> json) => JourneySummary(
        id: _str(json, 'id'),
        type: _str(json, 'type'),
        status: _str(json, 'status'),
        createdAt: _date(json, 'createdAt'),
        updatedAt: _date(json, 'updatedAt'),
      );
}

/// Respuesta de `POST /mobile/journeys`.
class JourneyCreated {
  final String id;
  final String status;
  const JourneyCreated({required this.id, required this.status});

  factory JourneyCreated.fromJson(Map<String, dynamic> json) =>
      JourneyCreated(id: _str(json, 'id'), status: _str(json, 'status'));
}

/// Respuesta de `GET /mobile/journeys/:id/context`.
class JourneyContext {
  final String journeyId;
  final String currentStep;
  final int version;
  final String? studyId;
  final String? clinicId;
  final String? appointmentId;
  final DateTime updatedAt;

  const JourneyContext({
    required this.journeyId,
    required this.currentStep,
    required this.version,
    required this.studyId,
    required this.clinicId,
    required this.appointmentId,
    required this.updatedAt,
  });

  factory JourneyContext.fromJson(Map<String, dynamic> json) {
    final refs = _map(json['externalRefs']);
    return JourneyContext(
      journeyId: _str(json, 'journeyId'),
      currentStep: _str(json, 'currentStep'),
      version: (json['version'] as num).toInt(),
      studyId: _optStr(refs, 'studyId'),
      clinicId: _optStr(refs, 'clinicId'),
      appointmentId: _optStr(refs, 'appointmentId'),
      updatedAt: _date(json, 'updatedAt'),
    );
  }
}

/// Elemento del historial (`GET /mobile/journeys/:id/history`).
class HistoryItem {
  final String id;
  final String type;
  final String producerCode;
  final DateTime occurredAt;
  final DateTime receivedAt;
  final int schemaVersion;
  final Map<String, dynamic> data;

  const HistoryItem({
    required this.id,
    required this.type,
    required this.producerCode,
    required this.occurredAt,
    required this.receivedAt,
    required this.schemaVersion,
    required this.data,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: _str(json, 'id'),
        type: _str(json, 'type'),
        producerCode: _str(json, 'producerCode'),
        occurredAt: _date(json, 'occurredAt'),
        receivedAt: _date(json, 'receivedAt'),
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        data: _map(json['data']),
      );
}

class HistoryPage {
  final List<HistoryItem> items;
  final String? nextCursor;
  const HistoryPage(this.items, this.nextCursor);

  factory HistoryPage.fromJson(Map<String, dynamic> json) => HistoryPage(
        ((json['items'] as List?) ?? const [])
            .map((e) => HistoryItem.fromJson(_map(e)))
            .toList(),
        _optStr(json, 'nextCursor'),
      );
}

/// Respuesta de `POST /mobile/journeys/:id/events`.
class EventReceipt {
  final String id;
  final String journeyId;
  const EventReceipt({required this.id, required this.journeyId});

  factory EventReceipt.fromJson(Map<String, dynamic> json) =>
      EventReceipt(id: _str(json, 'id'), journeyId: _str(json, 'journeyId'));
}

// -------------------------------------------------------------- catálogos

/// Estudio del catálogo. `price` se conserva como cadena decimal ("120.00").
class StudyItem {
  final String id;
  final String name;
  final String? description;
  final String price;

  const StudyItem({required this.id, required this.name, this.description, required this.price});

  factory StudyItem.fromJson(Map<String, dynamic> json) => StudyItem(
        id: _str(json, 'id'),
        name: _str(json, 'name'),
        description: _optStr(json, 'description'),
        price: _str(json, 'price'),
      );
}

class ClinicItem {
  final String id;
  final String name;
  final String address;
  final String city;
  final String state;

  const ClinicItem({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
  });

  String get location => [city, state].where((p) => p.isNotEmpty).join(', ');

  factory ClinicItem.fromJson(Map<String, dynamic> json) => ClinicItem(
        id: _str(json, 'id'),
        name: _str(json, 'name'),
        address: _optStr(json, 'address') ?? '',
        city: _optStr(json, 'city') ?? '',
        state: _optStr(json, 'state') ?? '',
      );
}

/// "$120.00 MXN" a partir de la cadena decimal, sin pasar por punto flotante.
String formatPriceString(String price) {
  final zero = RegExp(r'^0+(\.0+)?$').hasMatch(price.trim());
  return zero ? 'Sin costo' : '\$$price MXN';
}

// ----------------------------------------------------------------- errores

/// Error HTTP de la API central.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Segundos de `Retry-After` en un 429.
  final Duration? retryAfter;

  const ApiException(this.statusCode, this.message, {this.retryAfter});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;

  /// 5xx: el servicio falló y la misma operación se puede reintentar.
  bool get isRetryable => statusCode >= 500 || statusCode == 429;

  @override
  String toString() => '[$statusCode] $message';
}

/// Fallo de red o tiempo de espera: la operación se conserva para reintento.
class ApiNetworkException implements Exception {
  final String message;
  const ApiNetworkException(this.message);

  @override
  String toString() => message;
}

/// Mensaje para el paciente según el código HTTP (sección de errores del contrato).
String humanApiError(ApiException e) => switch (e.statusCode) {
      400 => 'Datos inválidos: ${e.message}',
      401 => 'Tu sesión venció. Inicia sesión de nuevo.',
      403 => 'Tu cuenta no tiene autorización para esta operación.',
      404 => 'El trámite o recurso no está disponible para tu cuenta.',
      409 => 'El trámite cambió desde otro canal. Revisa los datos actualizados.',
      429 => e.retryAfter == null
          ? 'Demasiadas solicitudes. Intenta en unos momentos.'
          : 'Demasiadas solicitudes. Intenta en ${e.retryAfter!.inSeconds} s.',
      502 => 'Falló la comunicación con el orquestador. Intenta de nuevo.',
      503 => 'La integración no está disponible por ahora. Intenta de nuevo.',
      504 => 'El orquestador tardó demasiado. Intenta de nuevo.',
      _ => e.message,
    };
