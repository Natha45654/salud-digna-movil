import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuración de la app.
///
/// El modo y la URL de la API se fijan **al compilar** y no se pueden cambiar
/// desde la app (ver `.env.example`):
///
/// - [mockMode] (`MOCK_MODE`): true usa el orquestador simulado en el
///   dispositivo; false usa la API central real. Por omisión, true.
/// - [baseUrl] (`CHANNEL_BACKEND_URL`): origen HTTPS de la API central, sin
///   `/api/v1`, que el cliente añade por su cuenta. Por omisión,
///   [productionBaseUrl].
///
/// Solo las herramientas de demostración ([mockFailures], [whatsappSimulator])
/// se guardan en el dispositivo. Las claves del simulador llevan el prefijo
/// `mock.`; el modo real no guarda nada en disco.
class AppConfig extends ChangeNotifier {
  static const _kMockFail = 'mock.cfg.mockFail';
  static const _kWhatsappSimulator = 'cfg.whatsappSimulator';

  /// Claves de versiones anteriores, que dejaban cambiar el modo y la URL desde
  /// la app y guardaban la clave de canal. Se borran al arrancar.
  static const _legacyKeys = [
    'cfg.baseUrl',
    'cfg.channelKey',
    'cfg.mockMode',
    'cfg.mockFail',
    'session.v1',
    'outbox.v1',
  ];

  /// API central del Hackatec. El cliente le añade `/api/v1`.
  static const productionBaseUrl = 'https://api.salud-digna.app';

  final bool mockMode;

  /// Origen normalizado de la API central (sin `/` final ni `/api/v1`).
  final String baseUrl;

  /// Por qué [baseUrl] no se puede usar, o null si es válida. Solo importa en
  /// modo real.
  final String? baseUrlError;

  /// Solo en modo simulado: hace fallar las llamadas para probar el outbox.
  bool mockFailures;

  /// Demo: "¿Necesitas ayuda?" abre el simulador de WhatsApp (WhatsApp Sim,
  /// saluddigna-wa://) en lugar de wa.me, que en el teléfono abre el WhatsApp real.
  bool whatsappSimulator;

  AppConfig._({
    required this.mockMode,
    required this.baseUrl,
    required this.baseUrlError,
    required this.mockFailures,
    required this.whatsappSimulator,
  });

  static const _envBaseUrl = String.fromEnvironment('CHANNEL_BACKEND_URL');
  static const _envMockMode = bool.fromEnvironment('MOCK_MODE', defaultValue: true);
  static const _envWhatsappSimulator = bool.fromEnvironment('WHATSAPP_SIMULATOR');

  static Future<AppConfig> load() => _load(mockMode: _envMockMode, rawBaseUrl: _envBaseUrl);

  /// Para pruebas: el modo y la URL que en la app vienen del compilado.
  @visibleForTesting
  static Future<AppConfig> loadForTesting({bool mockMode = true, String rawBaseUrl = ''}) =>
      _load(mockMode: mockMode, rawBaseUrl: rawBaseUrl);

  static Future<AppConfig> _load({required bool mockMode, required String rawBaseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _legacyKeys) {
      await prefs.remove(k);
    }
    final url = normalizeBaseUrl(rawBaseUrl.isEmpty ? productionBaseUrl : rawBaseUrl);
    return AppConfig._(
      mockMode: mockMode,
      baseUrl: url,
      baseUrlError: validateBaseUrl(url),
      mockFailures: prefs.getBool(_kMockFail) ?? false,
      whatsappSimulator: prefs.getBool(_kWhatsappSimulator) ?? _envWhatsappSimulator,
    );
  }

  /// Quita espacios, barras finales y el prefijo `/api/v1` si se escribió.
  static String normalizeBaseUrl(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.endsWith('/api/v1')) u = u.substring(0, u.length - '/api/v1'.length);
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  /// La integración real solo admite HTTPS: sin tráfico en claro.
  static String? validateBaseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'CHANNEL_BACKEND_URL no es una URL válida: $url';
    if (uri.scheme != 'https') return 'CHANNEL_BACKEND_URL debe usar https://: $url';
    return null;
  }

  Future<void> update({bool? mockFailures, bool? whatsappSimulator}) async {
    final prefs = await SharedPreferences.getInstance();
    if (mockFailures != null) {
      this.mockFailures = mockFailures;
      await prefs.setBool(_kMockFail, mockFailures);
    }
    if (whatsappSimulator != null) {
      this.whatsappSimulator = whatsappSimulator;
      await prefs.setBool(_kWhatsappSimulator, whatsappSimulator);
    }
    notifyListeners();
  }
}
