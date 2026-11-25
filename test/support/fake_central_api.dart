import 'dart:convert';

import 'package:http/http.dart' as http;

/// Servidor falso de la API central para pruebas. Sigue
/// docs/api-mobile-journeys.md, docs/api-auth.md, docs/api-studies.md y
/// docs/api-clinics.md de jangeltr/salud-digna. No es la API real: nada de lo
/// que se prueba contra él está verificado en producción.

const fakeJourneyId = '00000000-0000-4000-8000-000000000001';
const fakeStudyId = '00000000-0000-4000-8000-000000000201';
const fakeClinicId = '00000000-0000-4000-8000-000000000101';

/// API central falsa que sigue docs/api-mobile-journeys.md: rutas, cuerpos,
/// versión del contexto, idempotencia y errores. [failures] inyecta respuestas
/// para las siguientes solicitudes que coincidan con una ruta.
class FakeCentralApi {
  final requests = <http.Request>[];
  final failures = <String, List<http.Response>>{};
  final accounts = <String, Map<String, dynamic>>{
    'ana@example.test': {'role': 'PATIENT', 'patientId': 'p-ana', 'token': 'jwt-ana'},
    'luis@example.test': {'role': 'PATIENT', 'patientId': 'p-luis', 'token': 'jwt-luis'},
    'asesor@example.test': {'role': 'ADVISOR', 'patientId': null, 'token': 'jwt-asesor'},
    'sinperfil@example.test': {'role': 'PATIENT', 'patientId': null, 'token': 'jwt-sinperfil'},
  };
  int expiresIn = 1800;

  /// Siguientes POST de eventos que fallan sin respuesta (red caída).
  int networkFailures = 0;

  String step = 'SELECT_CLINIC';
  String status = 'IN_PROGRESS';
  int version = 2;
  final refs = <String, String>{'studyId': fakeStudyId};
  final idempotency = <String, String>{};

  /// Trámites creados con POST /mobile/journeys: en DRAFT y SELECT_STUDY.
  final created = <String>{};
  final events = <String, String>{};
  bool linked = true;

  /// La identidad tiene vínculo pero ningún trámite activo: 200 con lista vacía.
  bool linkedButEmpty = false;

  /// Todas las solicitudes fallan sin respuesta (sin red).
  bool networkDownForAll = false;

  http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code,
      headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> get context => {
        'journeyId': fakeJourneyId,
        'currentStep': step,
        'version': version,
        'externalRefs': refs,
        'updatedAt': '2026-11-25T16:00:00.000Z',
      };

  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    if (networkDownForAll) throw http.ClientException('Network is unreachable');
    final path = req.url.path.replaceFirst('/api/v1', '');
    final key = '${req.method} $path';
    for (final entry in failures.entries) {
      if (key.startsWith(entry.key) && entry.value.isNotEmpty) return entry.value.removeAt(0);
    }

    if (key == 'POST /auth/login') {
      final body = jsonDecode(req.body) as Map;
      final acct = accounts[body['email']];
      if (acct == null || body['password'] != 'correcta') {
        return _json({'statusCode': 401, 'message': 'Unauthorized'}, 401);
      }
      return _json({
        'accessToken': acct['token'],
        'tokenType': 'Bearer',
        'expiresIn': expiresIn,
        'user': {'id': 'u-${acct['patientId']}', 'email': body['email'], 'role': acct['role']},
      });
    }

    final auth = req.headers['Authorization'];
    final acct = accounts.entries
        .where((e) => 'Bearer ${e.value['token']}' == auth)
        .map((e) => MapEntry(e.key, e.value))
        .firstOrNull;
    if (path.startsWith('/studies') || path.startsWith('/clinics')) {
      return _catalog(path, req.url.queryParameters);
    }
    if (acct == null) return _json({'statusCode': 401, 'message': 'Unauthorized'}, 401);

    if (key == 'GET /auth/me') {
      final pid = acct.value['patientId'];
      return _json({
        'id': 'u-$pid',
        'email': acct.key,
        'role': acct.value['role'],
        'isActive': true,
        'patientId': pid,
        'patient': pid == null
            ? null
            : {'id': pid, 'firstName': 'Ana', 'lastName': 'Ejemplo', 'email': acct.key, 'phone': null},
      });
    }
    // Solo Ana tiene el trámite vinculado.
    final ownsJourney = acct.value['patientId'] == 'p-ana';

    if (key == 'GET /mobile/journeys') {
      if (!linked || !ownsJourney) return _json({'statusCode': 404, 'message': 'Not Found'}, 404);
      if (linkedButEmpty) return _json({'items': []});
      return _json({
        'items': [_summary],
      });
    }
    if (key == 'POST /mobile/journeys') {
      final k = req.headers['Idempotency-Key'];
      if (k == null) return _json({'message': 'Idempotency-Key requerido'}, 400);
      final id = idempotency.putIfAbsent(k, () => '00000000-0000-4000-8000-00000000090${idempotency.length}');
      created.add(id);
      return _json({'id': id, 'status': 'DRAFT'}, 201);
    }
    final createdMatch = RegExp(r'^/mobile/journeys/([0-9a-f-]{36})(/context|/history)?$').firstMatch(path);
    if (req.method == 'GET' && createdMatch != null && created.contains(createdMatch[1])) {
      final id = createdMatch[1]!;
      return switch (createdMatch[2]) {
        '/context' => _json({
            'journeyId': id, 'currentStep': 'SELECT_STUDY', 'version': 1,
            'externalRefs': <String, String>{}, 'updatedAt': '2026-11-25T16:00:00.000Z',
          }),
        '/history' => _json({
            'items': [
              {'id': 'c1', 'type': 'JOURNEY_CREATED', 'producerCode': 'demo-mobile',
               'occurredAt': '2026-11-25T16:00:00.000Z', 'receivedAt': '2026-11-25T16:00:00.100Z',
               'schemaVersion': 1, 'data': {'version': 1}},
            ],
          }),
        _ => _json({'id': id, 'type': 'APPOINTMENT', 'status': 'DRAFT',
            'createdAt': '2026-11-25T16:00:00.000Z', 'updatedAt': '2026-11-25T16:00:00.000Z'}),
      };
    }
    if (!ownsJourney) return _json({'statusCode': 404, 'message': 'Not Found'}, 404);
    if (key == 'GET /mobile/journeys/$fakeJourneyId') return _json(_summary);
    if (key == 'GET /mobile/journeys/$fakeJourneyId/context') return _json(context);
    if (key == 'GET /mobile/journeys/$fakeJourneyId/history') {
      final cursor = req.url.queryParameters['cursor'];
      final first = {
        'id': 'e1', 'type': 'JOURNEY_CREATED', 'producerCode': 'demo-web',
        'occurredAt': '2026-11-25T15:00:00.000Z', 'receivedAt': '2026-11-25T15:00:00.100Z',
        'schemaVersion': 1, 'data': {'version': 1},
      };
      final second = {
        'id': 'e2', 'type': 'JOURNEY_CONTEXT_UPDATED', 'producerCode': 'demo-web',
        'occurredAt': '2026-11-25T15:01:00.000Z', 'receivedAt': '2026-11-25T15:01:00.100Z',
        'schemaVersion': 1, 'data': {'version': 2, 'currentStep': 'SELECT_CLINIC'},
      };
      return cursor == null
          ? _json({'items': [first], 'nextCursor': 'c2'})
          : _json({'items': [second]});
    }
    if (key == 'POST /mobile/journeys/$fakeJourneyId/events') {
      if (networkFailures > 0) {
        networkFailures--;
        throw http.ClientException('Connection reset');
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final id = body['externalEventId'] as String;
      final previous = events[id];
      if (previous != null) {
        return previous == req.body
            ? _json({'id': 'evt-$id', 'journeyId': fakeJourneyId}, 201)
            : _json({'message': 'ID de evento reutilizado'}, 409);
      }
      final payload = body['payload'] as Map<String, dynamic>;
      if (payload['expectedVersion'] != version) {
        return _json({'message': 'Versión obsoleta'}, 409);
      }
      events[id] = req.body;
      version++;
      if (payload['studyId'] != null) {
        refs
          ..clear()
          ..['studyId'] = payload['studyId'] as String;
        step = 'SELECT_CLINIC';
      }
      if (payload['clinicId'] != null) {
        refs['clinicId'] = payload['clinicId'] as String;
        step = 'REVIEW';
      }
      if (payload['to'] != null) status = payload['to'] as String;
      return _json({'id': 'evt-$id', 'journeyId': fakeJourneyId}, 201);
    }
    return _json({'statusCode': 404, 'message': 'Cannot ${req.method} $path'}, 404);
  }

  Map<String, dynamic> get _summary => {
        'id': fakeJourneyId,
        'type': 'APPOINTMENT',
        'status': status,
        'createdAt': '2026-11-25T15:00:00.000Z',
        'updatedAt': '2026-11-25T16:00:00.000Z',
      };

  http.Response _catalog(String path, Map<String, String> q) {
    if (path == '/studies') {
      return _json({
        'page': int.parse(q['page'] ?? '1'), 'limit': 100, 'hasMore': false,
        'items': [
          {'id': fakeStudyId, 'name': 'Demo Glucosa', 'description': null, 'price': '120.00', 'isActive': true},
        ],
      });
    }
    if (path == '/clinics') {
      return _json({
        'page': 1, 'limit': 100, 'hasMore': false,
        'items': [
          {'id': fakeClinicId, 'name': 'Demo Clínica Alameda', 'address': 'Avenida Ejemplo 101',
           'city': 'Ciudad Ejemplo', 'state': 'Estado Ejemplo', 'isActive': true},
        ],
      });
    }
    return _json({'statusCode': 404, 'message': 'Not Found'}, 404);
  }
}
