import 'dart:convert';
import 'dart:io' show HandshakeException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:salud_digna_movil/real/api_models.dart';
import 'package:salud_digna_movil/real/central_api.dart';

/// Cliente de la API central: Retry-After y manejo de errores de transporte.
void main() {
  group('parseRetryAfter', () {
    final now = DateTime.utc(2026, 11, 25, 16, 0, 0);
    Duration? parse(String? h) => CentralApi.parseRetryAfter(h, now: now);

    test('nulo o vacío devuelve null', () {
      expect(parse(null), isNull);
      expect(parse(''), isNull);
      expect(parse('   '), isNull);
    });

    test('segundos: cero o negativo es Duration.zero, positivo es esa duración', () {
      expect(parse('0'), Duration.zero);
      expect(parse('-5'), Duration.zero);
      expect(parse('30'), const Duration(seconds: 30));
      expect(parse(' 45 '), const Duration(seconds: 45));
    });

    test('fecha HTTP: lo que falta desde ahora en UTC, o cero si ya pasó', () {
      expect(parse('Wed, 25 Nov 2026 16:01:30 GMT'), const Duration(seconds: 90));
      expect(parse('Wed, 25 Nov 2026 15:00:00 GMT'), Duration.zero);
      expect(parse('Wed Nov 25 16:00:10 2026'), const Duration(seconds: 10));
    });

    test('se recorta al máximo documentado', () {
      expect(parse('86400'), CentralApi.maxRetryAfter);
      expect(parse('Thu, 26 Nov 2026 16:00:00 GMT'), CentralApi.maxRetryAfter);
    });

    test('lo que no se puede interpretar devuelve null sin lanzar', () {
      expect(parse('mañana'), isNull);
      expect(parse('1.5'), isNull);
      // Entrada que hace lanzar RangeError a HttpDate.parse.
      expect(parse('Sun Nov '), isNull);
    });
  });

  group('errores', () {
    CentralApi api(MockClientHandler handler) =>
        CentralApi('https://api.example.test/', client: MockClient(handler));

    test('rechaza una URL base que no sea https', () {
      expect(() => CentralApi('http://api.example.test'), throwsArgumentError);
      expect(() => CentralApi('no es url'), throwsArgumentError);
    });

    test('arma la ruta con /api/v1 una sola vez aunque la base termine en /', () async {
      late Uri seen;
      await api((req) async {
        seen = req.url;
        return http.Response('{"items":[]}', 200);
      }).listJourneys('tok');
      expect(seen.toString(), 'https://api.example.test/api/v1/mobile/journeys');
    });

    test('429 conserva Retry-After y el mensaje de NestJS', () async {
      final call = api((_) async => http.Response(
          jsonEncode({'statusCode': 429, 'message': 'Too Many Requests'}), 429,
          headers: {'retry-after': '12'}));
      await expectLater(
        call.listJourneys('tok'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 12))
            .having((e) => e.message, 'message', 'Too Many Requests')),
      );
    });

    test('400 con arreglo de mensajes los une', () async {
      final call = api((_) async => http.Response(
          jsonEncode({'message': ['email inválido', 'password requerido'], 'error': 'Bad Request'}), 400,
          // Sin charset, http.Response codificaría el texto en latin1.
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await expectLater(
        call.login('x', 'y'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'email inválido. password requerido')),
      );
    });

    test('error con cuerpo no JSON usa el código HTTP', () async {
      final call = api((_) async => http.Response.bytes([0xff, 0xfe], 502));
      await expectLater(
        call.listJourneys('tok'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502)),
      );
    });

    test('2xx con un campo faltante sale como ApiException, no como TypeError', () async {
      final call = api((_) async => http.Response(jsonEncode({'id': 'x'}), 201));
      await expectLater(
        call.createJourney('tok', idempotencyKey: 'k'),
        throwsA(isA<ApiException>()),
      );
    });

    test('2xx sin cuerpo JSON sale como ApiException', () async {
      final call = api((_) async => http.Response('', 204));
      await expectLater(call.me('tok'), throwsA(isA<ApiException>()));
    });

    test('ClientException y errores TLS salen como ApiNetworkException', () async {
      await expectLater(
        api((_) async => throw http.ClientException('sin red')).listJourneys('tok'),
        throwsA(isA<ApiNetworkException>()),
      );
      await expectLater(
        api((_) async => throw const HandshakeException('certificado')).listJourneys('tok'),
        throwsA(isA<ApiNetworkException>()),
      );
    });

    test('un error de programación no se disfraza de fallo de red', () async {
      await expectLater(
        api((_) async => throw StateError('bug')).listJourneys('tok'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
