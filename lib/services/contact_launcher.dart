import 'package:flutter/services.dart';

import '../models/models.dart';

/// Datos de contacto. Se fijan al compilar desde el archivo .env
/// (SD_WHATSAPP, SD_CALL_CENTER); vacíos, la app abre WhatsApp o el marcador
/// sin número y no lo muestra en pantalla.
class ContactInfo {
  static const whatsapp = String.fromEnvironment('SD_WHATSAPP');
  static const callCenter = String.fromEnvironment('SD_CALL_CENTER');

  /// "55 0000 0000" para mostrar en pantalla; null si no está configurado.
  static String? displayOrNull(String digits) => digits.isEmpty ? null : display(digits);

  /// "55 0000 0000" para mostrar en pantalla.
  static String display(String digits) {
    final d = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    if (d.length != 10) return digits;
    return '${d.substring(0, 2)} ${d.substring(2, 6)} ${d.substring(6)}';
  }
}

/// Abre WhatsApp o el marcador del teléfono a través de un canal nativo
/// (MainActivity.kt), sin dependencias externas.
class ContactLauncher {
  static const _channel = MethodChannel('mx.saluddigna/launch');

  /// Para pruebas: reemplaza la apertura real.
  static Future<bool> Function(Uri uri)? debugOverride;

  /// [simulator]: para la demo, abre WhatsApp Sim (saluddigna-wa://send, mismo
  /// formato que wa.me) en lugar del WhatsApp real, que tiene verificado wa.me.
  static Uri uriFor(String channel, {String? message, bool simulator = false}) {
    if (channel != Channels.whatsapp) return Uri(scheme: 'tel', path: ContactInfo.callCenter);
    final query = {'phone': ContactInfo.whatsapp, 'text': ?message};
    return simulator
        ? Uri(scheme: 'saluddigna-wa', host: 'send', queryParameters: query)
        : Uri.https('wa.me', '/${ContactInfo.whatsapp}', {'text': ?message});
  }

  /// Devuelve false si no hay una aplicación que pueda abrirlo.
  static Future<bool> open(Uri uri) async {
    final override = debugOverride;
    if (override != null) return override(uri);
    try {
      return await _channel.invokeMethod<bool>('open', {'uri': uri.toString()}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
