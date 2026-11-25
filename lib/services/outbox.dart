import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'orchestrator_client.dart';

/// Entrada pendiente en el outbox del canal.
class OutboxEntry {
  final CanonicalEvent event;
  int attempts;
  String? lastError;
  DateTime? lastAttemptAt;

  OutboxEntry(this.event, {this.attempts = 0, this.lastError, this.lastAttemptAt});

  Map<String, dynamic> toJson() => {
        'event': event.toJson(),
        'attempts': attempts,
        'lastError': lastError,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> json) => OutboxEntry(
        CanonicalEvent.fromJson(Map<String, dynamic>.from(json['event'] as Map)),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['lastError'] as String?,
        lastAttemptAt: json['lastAttemptAt'] == null
            ? null
            : DateTime.parse(json['lastAttemptAt'] as String),
      );
}

/// Outbox persistente: "el canal no debe perder eventos si la API falla"
/// (requisito 12, Entrega confiable).
///
/// Cada evento se guarda localmente antes de enviarse. Si la red falla, el
/// evento queda en cola y se reintenta; como el orquestador es idempotente
/// por `eventId`, un reintento nunca duplica. Los errores de negocio
/// (4xx: conflicto de versión, transición inválida, no autorizado) no se
/// reintentan: se descartan y se informan al usuario.
class Outbox extends ChangeNotifier {
  static const _kKey = 'outbox.v1';
  final List<OutboxEntry> _entries = [];
  bool _flushing = false;

  List<OutboxEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;
  bool get flushing => _flushing;

  /// Rechazos de negocio del último reenvío (por ejemplo, el horario se ocupó
  /// mientras no había conexión). La app los muestra al paciente.
  final List<OrchestratorException> lastRejections = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    _entries.clear();
    if (raw != null) {
      for (final e in (jsonDecode(raw) as List)) {
        _entries.add(OutboxEntry.fromJson(Map<String, dynamic>.from(e as Map)));
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  /// Encola y trata de enviar de inmediato. Devuelve el ack si el envío fue
  /// exitoso, o null si quedó pendiente por fallo de red.
  /// Lanza [OrchestratorException] si el orquestador rechazó el evento.
  Future<EventAck?> enqueueAndSend(
    CanonicalEvent event,
    OrchestratorClient client, {
    PatientSession? session,
  }) async {
    final entry = OutboxEntry(event);
    _entries.add(entry);
    await _save();
    return _trySend(entry, client, session: session);
  }

  Future<EventAck?> _trySend(
    OutboxEntry entry,
    OrchestratorClient client, {
    PatientSession? session,
  }) async {
    entry.attempts++;
    entry.lastAttemptAt = DateTime.now();
    try {
      final ack = await client.publishEvent(entry.event, session: session);
      _entries.remove(entry);
      await _save();
      return ack;
    } on NetworkException catch (e) {
      entry.lastError = e.message;
      await _save();
      return null;
    } on OrchestratorException {
      // Rechazo de negocio: no tiene sentido reintentar.
      _entries.remove(entry);
      await _save();
      rethrow;
    }
  }

  /// Reintenta todo lo pendiente en orden. Devuelve cuántos se entregaron.
  Future<int> flush(OrchestratorClient client, {PatientSession? session}) async {
    if (_flushing) return 0;
    _flushing = true;
    lastRejections.clear();
    notifyListeners();
    var delivered = 0;
    try {
      for (final entry in List.of(_entries)) {
        try {
          final ack = await _trySend(entry, client, session: session);
          if (ack != null) delivered++;
          if (ack == null) break; // sigue sin red: no insistir en bucle
        } on OrchestratorException catch (e) {
          // Ya se descartó: el servidor revalidó y no lo aceptó (no se confirma
          // a ciegas). Se guarda para avisar al paciente y continuar.
          lastRejections.add(e);
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
    return delivered;
  }

  Future<void> discard(OutboxEntry entry) async {
    _entries.remove(entry);
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    await _save();
  }
}
