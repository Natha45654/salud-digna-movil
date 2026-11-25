import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuración de conexión con el orquestador.
///
/// - [baseUrl]: URL del backend del canal móvil (mobile_channel_backend,
///   puerto 3300). Ese backend es quien guarda la API key del orquestador.
/// - [mockMode]: si es true, la app usa un orquestador simulado en memoria
///   que implementa los mismos contratos. Permite demostrar la app aunque el
///   backend aún no exponga los endpoints.
class AppConfig extends ChangeNotifier {
  static const _kBaseUrl = 'cfg.baseUrl';
  static const _kMockMode = 'cfg.mockMode';
  static const _kMockFail = 'cfg.mockFail';
  static const _kWhatsappSimulator = 'cfg.whatsappSimulator';

  String baseUrl;
  bool mockMode;

  /// Solo en modo simulado: hace fallar las llamadas para probar el outbox.
  bool mockFailures;

  /// Demo: "¿Necesitas ayuda?" abre el simulador de WhatsApp (WhatsApp Sim,
  /// saluddigna-wa://) en lugar de wa.me, que en el teléfono abre el WhatsApp real.
  bool whatsappSimulator;

  AppConfig._({
    required this.baseUrl,
    required this.mockMode,
    required this.mockFailures,
    required this.whatsappSimulator,
  });

  /// Valores por defecto fijados al compilar desde el archivo .env
  /// (ver .env.example):
  ///   flutter build apk --dart-define-from-file=.env
  /// Una variable vacía equivale a no definida. Sin URL ni clave, la app solo
  /// funciona en modo simulado hasta configurarlas en la pantalla Conexión.
  static const _envBaseUrl = String.fromEnvironment('CHANNEL_BACKEND_URL');
  static const _envMockMode = bool.fromEnvironment('MOCK_MODE', defaultValue: true);
  static const _envWhatsappSimulator = bool.fromEnvironment('WHATSAPP_SIMULATOR');

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig._(
      baseUrl: prefs.getString(_kBaseUrl) ?? _envBaseUrl,
      mockMode: prefs.getBool(_kMockMode) ?? _envMockMode,
      mockFailures: prefs.getBool(_kMockFail) ?? false,
      whatsappSimulator: prefs.getBool(_kWhatsappSimulator) ?? _envWhatsappSimulator,
    );
  }

  Future<void> update({
    String? baseUrl,
    bool? mockMode,
    bool? mockFailures,
    bool? whatsappSimulator,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      await prefs.setString(_kBaseUrl, this.baseUrl);
    }
    if (mockMode != null) {
      this.mockMode = mockMode;
      await prefs.setBool(_kMockMode, mockMode);
    }
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
