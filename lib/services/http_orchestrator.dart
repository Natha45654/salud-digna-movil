import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../models/models.dart';
import 'orchestrator_client.dart';

/// Cliente HTTP real contra el backend del canal móvil (que a su vez habla con
/// el orquestador usando la API key del canal).
///
/// Cabeceras enviadas en cada solicitud (sección 5: "autenticación de la
/// aplicación, autorización por paciente y rol, versionado e identificadores
/// de solicitud"):
///
/// - `X-Channel-Id: MOBILE_APP`      identifica la aplicación emisora.
/// - `X-Channel-Key: <clave>`        credencial de ChannelIntegration.
/// - `X-Request-Id: <uuid>`          identificador de solicitud para auditoría.
/// - `Idempotency-Key: <eventId>`    solo en POST de eventos.
/// - `Authorization: Bearer <token>` token de paciente tras verificación.
class HttpOrchestrator implements OrchestratorClient {
  final AppConfig config;
  final http.Client _client;
  static const _uuid = Uuid();
  static const _timeout = Duration(seconds: 8);

  HttpOrchestrator(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('${config.baseUrl}$path');

  Map<String, String> _headers({PatientSession? session, String? idempotencyKey}) =>
      {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Channel-Id': Channels.mobileApp,
        'X-Channel-Key': config.channelKey,
        'X-Request-Id': _uuid.v4(),
        'Idempotency-Key': ?idempotencyKey,
        if (session != null) 'Authorization': 'Bearer ${session.token}',
      };

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(_timeout);
    } on TimeoutException {
      throw NetworkException('Tiempo de espera agotado al contactar al orquestador');
    } on http.ClientException catch (e) {
      throw NetworkException('Sin conexión con el orquestador: ${e.message}');
    } catch (e) {
      throw NetworkException('Fallo de red: $e');
    }

    if (res.statusCode >= 500) {
      throw NetworkException('Orquestador respondió ${res.statusCode}');
    }
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final map = body is Map ? body : const {};
      throw OrchestratorException(
        res.statusCode,
        (map['code'] ?? map['error'] ?? 'ERROR').toString(),
        (map['message'] ?? res.reasonPhrase ?? 'Error').toString(),
      );
    }
    return body;
  }

  @override
  Future<PatientSession> verifyIdentity({
    required List<PatientIdentifier> identifiers,
    required String otp,
  }) async {
    final body = await _send(() => _client.post(
          _uri('/api/v1/identity/verify'),
          headers: _headers(),
          body: jsonEncode({
            'channel': Channels.mobileApp,
            'patientIdentifiers': identifiers.map((e) => e.toJson()).toList(),
            'otp': otp,
          }),
        ));
    return PatientSession.fromJson(Map<String, dynamic>.from(body as Map));
  }

  @override
  Future<EventAck> publishEvent(CanonicalEvent event,
      {PatientSession? session}) async {
    final body = await _send(() => _client.post(
          _uri('/api/v1/integrations/events'),
          headers: _headers(session: session, idempotencyKey: event.eventId),
          body: jsonEncode(event.toJson()),
        ));
    return EventAck.fromJson(Map<String, dynamic>.from(body as Map));
  }

  @override
  Future<List<Journey>> listJourneys(PatientSession session, {String status = 'all'}) async {
    final body = await _send(() => _client.get(
          _uri('/api/v1/me/journeys?status=${Uri.encodeQueryComponent(status)}'),
          headers: _headers(session: session),
        ));
    final list = body is Map ? body['journeys'] ?? body['items'] : body;
    return (list as List)
        .map((e) => Journey.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<Journey> getJourney(String journeyId, PatientSession session) async {
    final body = await _send(() => _client.get(
          _uri('/api/v1/journeys/$journeyId'),
          headers: _headers(session: session),
        ));
    return Journey.fromJson(Map<String, dynamic>.from(body as Map));
  }

  @override
  Future<List<CanonicalEvent>> listEvents(
      String journeyId, PatientSession session) async {
    final body = await _send(() => _client.get(
          _uri('/api/v1/journeys/$journeyId/events'),
          headers: _headers(session: session),
        ));
    final list = body is Map ? body['events'] ?? body['items'] : body;
    return (list as List)
        .map((e) => CanonicalEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> linkJourney(
      {required String code, required PatientSession session}) async {
    await _send(() => _client.post(
          _uri('/api/v1/journeys/link'),
          headers: _headers(session: session),
          body: jsonEncode({'code': code}),
        ));
  }

  @override
  Future<List<DateTime>> availableSlots({
    required String journeyId,
    required String clinicId,
    required PatientSession session,
  }) async {
    final body = await _send(() => _client.get(
          _uri('/api/v1/journeys/$journeyId/availability?clinicId=${Uri.encodeQueryComponent(clinicId)}'),
          headers: _headers(session: session),
        ));
    final list = body is Map ? body['slots'] ?? const [] : body;
    return (list as List).map((e) => DateTime.parse(e as String)).toList();
  }
}
