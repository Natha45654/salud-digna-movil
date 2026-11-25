import '../models/models.dart';

/// Contrato que la app móvil usa para hablar con el orquestador.
///
/// Corresponde a los contratos REST de la sección 5 del documento de
/// arquitectura más un endpoint de verificación de identidad (sección 6):
///
/// | Método | Ruta                                   | Implementación         |
/// |--------|----------------------------------------|------------------------|
/// | POST   | /api/v1/identity/verify                | [verifyIdentity]       |
/// | POST   | /api/v1/integrations/events            | [publishEvent]         |
/// | GET    | /api/v1/me/journeys?status=            | [listJourneys]         |
/// | GET    | /api/v1/journeys/{id}                  | [getJourney]           |
/// | GET    | /api/v1/journeys/{id}/events           | [listEvents]           |
/// | GET    | /api/v1/journeys/{id}/availability     | [availableSlots]       |
///
/// Solo lo implementa el orquestador simulado ([MockOrchestrator]). Estas
/// rutas no existen en la API central; el modo real usa `lib/real/`.
abstract class OrchestratorClient {
  /// Valida identidad del paciente con identificadores tipados + OTP.
  /// Devuelve una sesión con token de paciente y nivel de verificación.
  Future<PatientSession> verifyIdentity({
    required List<PatientIdentifier> identifiers,
    required String otp,
  });

  /// Registra un evento de negocio. Debe ser idempotente por `eventId`.
  Future<EventAck> publishEvent(CanonicalEvent event, {PatientSession? session});

  /// Trámites del paciente de la sesión verificada. El cliente no envía ningún
  /// identificador de paciente: el servidor lo resuelve a partir de la sesión y
  /// filtra por él. Sin sesión válida responde 401.
  ///
  /// [status]: `open` (pendientes), `closed` (confirmados o cancelados) o `all`.
  Future<List<Journey>> listJourneys(PatientSession session, {String status = 'all'});

  /// Estado, contexto y próximo paso del trámite.
  Future<Journey> getJourney(String journeyId, PatientSession session);

  /// Cronología inmutable del trámite.
  Future<List<CanonicalEvent>> listEvents(
      String journeyId, PatientSession session);

  /// Horarios disponibles para el trámite en una clínica (clínica + fecha +
  /// hora). Solo devuelve los libres; los ocupados no se incluyen.
  ///
  /// DEMO: la autoridad real de la disponibilidad es el sistema de citas de
  /// Salud Digna. Aquí la calcula el backend del canal (o el simulador) y la
  /// revalida al elegir y al confirmar.
  Future<List<DateTime>> availableSlots({
    required String journeyId,
    required String clinicId,
    required PatientSession session,
  });
}
