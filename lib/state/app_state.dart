import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../models/models.dart';
import '../services/http_orchestrator.dart';
import '../services/mock_orchestrator.dart';
import '../services/orchestrator_client.dart';
import '../services/outbox.dart';

/// Estado global de la app móvil (canal MOBILE_APP).
class AppState extends ChangeNotifier {
  static const _kSession = 'session.v1';
  static const _uuid = Uuid();

  final AppConfig config;
  final Outbox outbox = Outbox();
  late MockOrchestrator _mock;
  late HttpOrchestrator _http;

  PatientSession? session;

  /// Inicio en dos columnas: panel izquierdo plegado. Solo vive en memoria
  /// (se recuerda durante la sesión, no entre reinicios de la app).
  bool homeSidePaneCollapsed = false;

  void setHomeSidePaneCollapsed(bool value) {
    homeSidePaneCollapsed = value;
    notifyListeners();
  }
  /// Trámites del paciente tal como los devolvió el servidor (abiertos y
  /// cerrados). No hay otra fuente: se vuelven a pedir en cada actualización.
  List<Journey> journeys = [];

  /// Trámites pendientes, del más reciente al más antiguo.
  List<Journey> get pendingJourneys =>
      journeys.where((j) => JourneyStatus.isOpen(j.status)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  bool loadingJourneys = false;
  String? lastError;

  AppState(this.config) {
    _mock = MockOrchestrator(config);
    _http = HttpOrchestrator(config);
    config.addListener(notifyListeners);
  }

  OrchestratorClient get client => config.mockMode ? _mock : _http;
  MockOrchestrator get mock => _mock;
  bool get isLoggedIn => session != null;

  Future<void> init() async {
    await outbox.load();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSession);
    if (raw != null) {
      try {
        session = PatientSession.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        session = null;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- identidad

  Future<void> login({
    required List<PatientIdentifier> identifiers,
    required String otp,
  }) async {
    lastError = null;
    final s = await client.verifyIdentity(identifiers: identifiers, otp: otp);
    session = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSession, jsonEncode(s.toJson()));
    notifyListeners();
    await refreshJourneys();
  }

  Future<void> logout() async {
    session = null;
    journeys = [];
    homeSidePaneCollapsed = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSession);
    notifyListeners();
  }

  // -------------------------------------------------------------- consultas

  Future<void> refreshJourneys() async {
    final s = session;
    if (s == null) return;
    loadingJourneys = true;
    lastError = null;
    notifyListeners();
    try {
      final result = await Future.wait([
        client.listJourneys(s, status: 'open'),
        client.listJourneys(s, status: 'closed'),
      ]);
      journeys = [...result[0], ...result[1]];
    } on OrchestratorException catch (e) {
      lastError = e.message;
      if (e.isUnauthorized) await logout();
    } on NetworkException catch (e) {
      lastError = e.message;
    } finally {
      loadingJourneys = false;
      notifyListeners();
    }
  }

  /// Si el servidor rechaza la sesión (expirada o no verificada), se cierra y
  /// la app regresa a la pantalla de identificación.
  Future<T> _authed<T>(Future<T> Function(PatientSession s) call) async {
    final s = session;
    if (s == null) {
      throw const OrchestratorException(401, 'UNAUTHORIZED', 'Sesión no verificada');
    }
    try {
      return await call(s);
    } on OrchestratorException catch (e) {
      if (e.isUnauthorized) await logout();
      rethrow;
    }
  }

  Future<Journey> getJourney(String id) => _authed((s) => client.getJourney(id, s));

  Future<List<CanonicalEvent>> getEvents(String id) =>
      _authed((s) => client.listEvents(id, s));

  // ---------------------------------------------------------------- eventos

  CanonicalEvent buildEvent({
    required String eventType,
    String? journeyId,
    Map<String, dynamic> data = const {},
    int? expectedVersion,
  }) {
    final s = session!;
    // Minimización de datos (sección 6): enviar la referencia menos sensible.
    final ids = s.identifiers.where((i) => i.type == 'PATIENT_ID').toList();
    return CanonicalEvent(
      eventId: 'app-${_uuid.v4()}',
      sourceSystem: Channels.mobileApp,
      patientIdentifiers: ids.isEmpty ? s.identifiers : ids,
      journeyId: journeyId,
      eventType: eventType,
      occurredAt: DateTime.now(),
      data: data,
      expectedVersion: expectedVersion,
    );
  }

  /// Envía un evento vía outbox. Devuelve el ack, o null si quedó en cola.
  Future<EventAck?> sendEvent(CanonicalEvent event) async {
    lastError = null;
    try {
      final ack = await outbox.enqueueAndSend(event, client, session: session);
      return ack;
    } on OrchestratorException catch (e) {
      lastError = e.message;
      if (e.isUnauthorized) await logout();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<int> retryOutbox() async {
    final n = await outbox.flush(client, session: session);
    notifyListeners();
    return n;
  }

  /// Horarios libres para el trámite en la clínica (revalidados por el servidor).
  Future<List<DateTime>> availableSlots(String journeyId, String clinicId) => _authed(
      (s) => client.availableSlots(journeyId: journeyId, clinicId: clinicId, session: s));

  /// Traspaso manual de permisos desde otro canal (limitación conocida).
  Future<void> linkJourney(String code) async {
    await client.linkJourney(code: code.trim(), session: session!);
    await refreshJourneys();
  }

  Future<void> resetDemo() async {
    await _mock.reset();
    await outbox.clear();
    await refreshJourneys();
  }
}
