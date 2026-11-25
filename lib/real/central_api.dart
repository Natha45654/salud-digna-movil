import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, HttpException, IOException;
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'api_models.dart';

/// Cliente de la API central de Salud Digna (Flutter → API central →
/// orquestador).
///
/// Solo envía el JWT del paciente en `Authorization: Bearer`. No envía
/// `X-Channel-Key`, `X-Journey-Grant` ni credenciales institucionales: la API
/// central firma la afirmación de `demo-mobile` y obtiene los permisos.
///
/// Toda falla sale como [ApiException] (respuesta HTTP de error o con forma
/// inesperada) o [ApiNetworkException] (red, TLS o tiempo de espera).
class CentralApi {
  /// Origen HTTPS sin `/api/v1`, por ejemplo `https://api.salud-digna.app`.
  final String baseUrl;
  final Uri _base;
  final http.Client _client;
  final Duration timeout;

  /// Lanza [ArgumentError] si [baseUrl] no es una URL `https://` válida.
  CentralApi(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _base = _parseBase(baseUrl),
        _client = client ?? http.Client();

  static const _prefix = '/api/v1';

  static Uri _parseBase(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'baseUrl', 'La API central solo se consume por https://');
    }
    // Sin barras finales: la ruta se arma como <ruta base>/api/v1/<recurso>.
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
  }

  Uri _uri(String path, [Map<String, String>? query]) => _base.replace(
        path: '${_base.path}$_prefix$path',
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  Map<String, String> _headers({String? token, bool json = false, String? idempotencyKey}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        'Idempotency-Key': ?idempotencyKey,
      };

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw const ApiNetworkException('Tiempo de espera agotado al contactar la API central');
    } on http.ClientException catch (e) {
      // IOClient convierte SocketException y HttpException en ClientException.
      throw ApiNetworkException('Sin conexión con la API central: ${e.message}');
    } on IOException catch (e) {
      // Lo que IOClient no convierte, como HandshakeException (TLS).
      throw ApiNetworkException('Fallo de red con la API central: $e');
    }

    Object? body;
    if (res.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        // UTF-8 o JSON inválidos: se trata como cuerpo ausente.
        body = null;
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        res.statusCode,
        _errorMessage(body) ?? res.reasonPhrase ?? 'Error ${res.statusCode}',
        retryAfter: parseRetryAfter(res.headers['retry-after']),
      );
    }
    if (body is! Map) {
      throw ApiException(res.statusCode, 'Respuesta inesperada de la API central');
    }
    return Map<String, dynamic>.from(body);
  }

  /// Convierte un cuerpo 2xx en modelo. Un campo ausente o de otro tipo se
  /// informa como [ApiException] en lugar de escapar como error de Dart.
  static T _parse<T>(int statusCode, T Function() parse) {
    try {
      return parse();
    } on FormatException catch (e) {
      throw ApiException(statusCode, 'Respuesta inesperada de la API central: ${e.message}');
    } on TypeError {
      throw ApiException(statusCode, 'Respuesta inesperada de la API central');
    }
  }

  /// NestJS devuelve `message` como cadena o como arreglo de mensajes.
  static String? _errorMessage(Object? body) {
    if (body is! Map) return null;
    final m = body['message'];
    if (m is String) return m;
    if (m is List) return m.join('. ');
    final error = body['error'];
    return error is String ? error : null;
  }

  /// Espera máxima que se acepta de `Retry-After`: 2 minutos. Un valor mayor
  /// (o absurdo) se recorta para que la app no quede bloqueada; si el límite
  /// real sigue vigente, el siguiente intento recibe otro 429 con su propio
  /// `Retry-After`.
  static const maxRetryAfter = Duration(minutes: 2);

  /// Interpreta `Retry-After` como segundos o como fecha HTTP.
  ///
  /// - Nulo o vacío: `null`.
  /// - Entero de segundos: cero o negativo da [Duration.zero]; positivo da esa
  ///   duración, recortada a [maxRetryAfter].
  /// - Fecha HTTP: lo que falta desde [now] (UTC); si ya pasó, [Duration.zero].
  /// - Cualquier otra cosa: `null`, sin lanzar.
  @visibleForTesting
  static Duration? parseRetryAfter(String? header, {DateTime? now}) {
    final value = header?.trim();
    if (value == null || value.isEmpty) return null;

    final Duration wait;
    final secs = int.tryParse(value);
    if (secs != null) {
      wait = secs <= 0 ? Duration.zero : Duration(seconds: secs);
    } else {
      final DateTime at;
      try {
        at = HttpDate.parse(value);
      } on HttpException {
        return null;
      } on RangeError {
        // HttpDate.parse (Dart 3.13) lee fuera del texto con entradas
        // truncadas en formato asctime, por ejemplo "Sun Nov ".
        return null;
      }
      final remaining = at.difference((now ?? DateTime.now()).toUtc());
      wait = remaining.isNegative ? Duration.zero : remaining;
    }
    return wait > maxRetryAfter ? maxRetryAfter : wait;
  }

  // ------------------------------------------------------------------ auth

  Future<LoginResult> login(String email, String password) async {
    final body = await _send(() => _client.post(
          _uri('/auth/login'),
          headers: _headers(json: true),
          body: jsonEncode({'email': email, 'password': password}),
        ));
    return _parse(200, () => LoginResult.fromJson(body));
  }

  Future<AccountInfo> me(String token) async {
    final body = await _send(() => _client.get(_uri('/auth/me'), headers: _headers(token: token)));
    return _parse(200, () => AccountInfo.fromJson(body));
  }

  // -------------------------------------------------------------- trámites

  Future<List<JourneySummary>> listJourneys(String token) async {
    final body = await _send(
        () => _client.get(_uri('/mobile/journeys'), headers: _headers(token: token)));
    return _parse(200, () => ((body['items'] as List?) ?? const [])
        .map((e) => JourneySummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList());
  }

  Future<JourneyCreated> createJourney(String token, {required String idempotencyKey}) async {
    final body = await _send(() => _client.post(
          _uri('/mobile/journeys'),
          headers: _headers(token: token, json: true, idempotencyKey: idempotencyKey),
          body: jsonEncode(const {'type': 'APPOINTMENT'}),
        ));
    return _parse(201, () => JourneyCreated.fromJson(body));
  }

  Future<JourneySummary> summary(String token, String journeyId) async {
    final body = await _send(() =>
        _client.get(_uri('/mobile/journeys/${_id(journeyId)}'), headers: _headers(token: token)));
    return _parse(200, () => JourneySummary.fromJson(body));
  }

  Future<JourneyContext> context(String token, String journeyId) async {
    final body = await _send(() => _client.get(
        _uri('/mobile/journeys/${_id(journeyId)}/context'),
        headers: _headers(token: token)));
    return _parse(200, () => JourneyContext.fromJson(body));
  }

  Future<HistoryPage> history(String token, String journeyId,
      {int limit = 20, String? cursor}) async {
    final body = await _send(() => _client.get(
        _uri('/mobile/journeys/${_id(journeyId)}/history',
            {'limit': '$limit', 'cursor': ?cursor}),
        headers: _headers(token: token)));
    return _parse(200, () => HistoryPage.fromJson(body));
  }

  /// Publica el cuerpo tal cual: en un reintento se envía el mismo mapa.
  Future<EventReceipt> publishEvent(
      String token, String journeyId, Map<String, dynamic> event) async {
    final body = await _send(() => _client.post(
          _uri('/mobile/journeys/${_id(journeyId)}/events'),
          headers: _headers(token: token, json: true),
          body: jsonEncode(event),
        ));
    return _parse(201, () => EventReceipt.fromJson(body));
  }

  // -------------------------------------------------------------- catálogos

  /// Todas las páginas de estudios activos (100 por página).
  Future<List<StudyItem>> studies() => _allPages('/studies', StudyItem.fromJson);

  Future<StudyItem> study(String id) async {
    final body = await _send(() => _client.get(_uri('/studies/${_id(id)}'), headers: _headers()));
    return _parse(200, () => StudyItem.fromJson(body));
  }

  Future<List<ClinicItem>> clinics() => _allPages('/clinics', ClinicItem.fromJson);

  Future<ClinicItem> clinic(String id) async {
    final body = await _send(() => _client.get(_uri('/clinics/${_id(id)}'), headers: _headers()));
    return _parse(200, () => ClinicItem.fromJson(body));
  }

  /// Recorre las páginas mientras `hasMore` sea true, con un tope de 20
  /// páginas (2000 registros) como protección ante una respuesta defectuosa.
  Future<List<T>> _allPages<T>(String path, T Function(Map<String, dynamic>) parse) async {
    final out = <T>[];
    for (var page = 1; page <= 20; page++) {
      final body = await _send(() => _client.get(
          _uri(path, {'page': '$page', 'limit': '100'}),
          headers: _headers()));
      out.addAll(_parse(200, () => ((body['items'] as List?) ?? const [])
          .map((e) => parse(Map<String, dynamic>.from(e as Map)))
          .toList()));
      if (body['hasMore'] != true) break;
    }
    return out;
  }

  /// Los UUID van en la ruta: se codifican para no alterar la URL.
  static String _id(String id) => Uri.encodeComponent(id);
}

/// Generadores de identificadores para operaciones de escritura.
class OperationIds {
  static final _random = Random.secure();
  static const _uuid = Uuid();

  /// `Idempotency-Key`: 32 bytes criptográficamente aleatorios en base64url
  /// sin relleno (43 caracteres).
  static String idempotencyKey() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// `externalEventId` opaco, sin datos personales.
  static String externalEventId() => 'app-${_uuid.v4()}';

  /// UTC con milisegundos, por ejemplo `2026-11-25T15:30:00.123Z`.
  static String utcNow([DateTime? now]) {
    final d = (now ?? DateTime.now()).toUtc();
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond)
        .toIso8601String();
  }
}
