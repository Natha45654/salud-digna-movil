import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/real/central_api.dart';

/// Configuración: el modo y la URL vienen del compilado; claves separadas.
void main() {
  test('sin URL usa la API central de producción, sin /api/v1', () async {
    SharedPreferences.setMockInitialValues({});
    final cfg = await AppConfig.loadForTesting(mockMode: false);
    expect(cfg.baseUrl, 'https://api.salud-digna.app');
    expect(cfg.baseUrlError, isNull);
  });

  test('si la URL trae /api/v1 se quita y el cliente lo añade una sola vez', () async {
    SharedPreferences.setMockInitialValues({});
    final cfg = await AppConfig.loadForTesting(
        mockMode: false, rawBaseUrl: ' https://api.example.test/api/v1/ ');
    expect(cfg.baseUrl, 'https://api.example.test');
    final api = CentralApi(cfg.baseUrl);
    expect(api.baseUrl, 'https://api.example.test');
  });

  test('una URL sin https se marca como inválida', () async {
    SharedPreferences.setMockInitialValues({});
    final cfg = await AppConfig.loadForTesting(mockMode: false, rawBaseUrl: 'http://api.example.test');
    expect(cfg.baseUrlError, contains('https://'));
  });

  test('lo guardado por versiones anteriores no cambia el modo ni la URL y se borra', () async {
    SharedPreferences.setMockInitialValues({
      'cfg.mockMode': false,
      'cfg.baseUrl': 'http://10.0.2.2:3300',
      'cfg.channelKey': 'clave-vieja',
      'session.v1': '{}',
      'outbox.v1': '[]',
    });
    final cfg = await AppConfig.loadForTesting(mockMode: true);
    expect(cfg.mockMode, isTrue);
    expect(cfg.baseUrl, 'https://api.salud-digna.app');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('las herramientas del simulador se guardan con prefijo mock.', () async {
    SharedPreferences.setMockInitialValues({});
    final cfg = await AppConfig.loadForTesting();
    await cfg.update(mockFailures: true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'mock.cfg.mockFail'});
  });
}
