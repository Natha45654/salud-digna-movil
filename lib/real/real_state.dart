import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_models.dart';
import 'central_api.dart';

/// Rechazo del inicio de sesión que no es un error HTTP: credenciales
/// incorrectas, rol distinto de PATIENT o cuenta sin perfil de paciente.
class RealAuthException implements Exception {
  final String message;
  const RealAuthException(this.message);

  @override
  String toString() => message;
}

enum PendingKind { createJourney, publishEvent }

/// Escritura que todavía no tiene resultado confirmado. En un reintento se
/// envía exactamente lo mismo: la misma `Idempotency-Key` o el mismo cuerpo
/// del evento (mismo `externalEventId`, `occurredAt` y `expectedVersion`).
class PendingOperation {
  final PendingKind kind;
  final String? journeyId;
  final String? idempotencyKey;
  final Map<String, dynamic>? event;

  /// Descripción para el paciente, por ejemplo "Selección de clínica".
  final String label;

  int attempts = 0;
  String? lastError;

  /// Con un 429, no reintentar antes de este momento.
  DateTime? notBefore;

  PendingOperation.create({required this.idempotencyKey, this.label = 'Nuevo trámite'})
      : kind = PendingKind.createJourney,
        journeyId = null,
        event = null;

  PendingOperation.event({
    required String this.journeyId,
    required Map<String, dynamic> this.event,
    required this.label,
  })  : kind = PendingKind.publishEvent,
        idempotencyKey = null;

  String get _slot => journeyId ?? RealState._createSlot;
}

enum WriteStatus {
  /// El servidor aceptó la operación.
  done,

  /// Red, 5xx o 429: la operación se conserva para reintentarla igual.
  pending,

  /// 409: el trámite cambió en otro canal. Se descartó la operación y se
  /// volvió a leer el contexto.
  conflict,

  /// 400, 403 o 404: el servidor la rechazó. Se descartó la operación.
  rejected,

  /// 401 o JWT vencido: la operación se conserva hasta iniciar sesión de nuevo
  /// con la misma cuenta.
  sessionExpired,
}

class WriteResult<T> {
  final WriteStatus status;
  final T? value;
  final String? message;

  /// Contexto vigente leído después de publicar o de un conflicto, si se pudo leer.
  final JourneyContext? context;

  const WriteResult(this.status, {this.value, this.message, this.context});

  bool get isDone => status == WriteStatus.done;
}

/// Detalle de un trámite: resumen, contexto y la parte cargada del historial.
class JourneyDetail {
  final JourneySummary summary;
  final JourneyContext context;
  final List<HistoryItem> history;
  final String? nextCursor;

  const JourneyDetail({
    required this.summary,
    required this.context,
    required this.history,
    required this.nextCursor,
  });

  bool get hasMoreHistory => nextCursor != null;
}

/// Estado del modo real (API central). Independiente del modo simulado: no lee
/// ni escribe `SharedPreferences`.
///
/// - El JWT vive solo en memoria y se descarta al cerrar sesión o al vencer.
/// - Las escrituras pendientes se guardan en memoria por cuenta y entorno
///   (URL de la API + `patientId`). Al vencer la sesión se conservan; al cerrar
///   sesión se eliminan. Nunca se reenvían con la sesión de otra cuenta.
class RealState extends ChangeNotifier {
  final CentralApi api;

  /// Espera entre reintentos; reemplazable en pruebas.
  final Future<void> Function(Duration) delay;
  final DateTime Function() clock;

  /// Intentos automáticos de una misma escritura ante red, 5xx o 429 corto.
  final int maxAttempts;

  /// Registro de depuración. Por omisión escribe solo en compilaciones de
  /// depuración. Nunca recibe el JWT, la contraseña ni datos del paciente.
  final void Function(String message) log;

  /// Un `Retry-After` de hasta este valor se espera automáticamente; uno mayor
  /// deja la operación pendiente para que el paciente la reintente.
  final Duration autoRetryAfterLimit;

  /// Margen para tratar el JWT como vencido antes de su expiración real.
  static const expiryMargin = Duration(seconds: 30);

  static const _createSlot = '__create__';

  /// Contextos que se leen al refrescar la lista de trámites (para mostrar
  /// estudio y clínica en el inicio). El resto se lee al abrir el trámite.
  static const prefetchContexts = 10;

  RealState(
    this.api, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
    this.maxAttempts = 3,
    this.autoRetryAfterLimit = const Duration(seconds: 10),
    void Function(String message)? log,
  })  : delay = delay ?? Future<void>.delayed,
        clock = clock ?? DateTime.now,
        log = log ?? _debugLog;

  static void _debugLog(String message) {
    if (kDebugMode) debugPrint(message);
  }

  // ---------------------------------------------------------------- sesión

  ApiSession? _session;
  Timer? _expiryTimer;

  ApiSession? get session => _session;
  bool get isLoggedIn => _session != null;

  /// Aviso para la pantalla de acceso, por ejemplo cuando venció la sesión.
  String? notice;

  String get _owner => '${api.baseUrl}|${_session!.patientId}';

  /// Inicia sesión con correo y contraseña (`POST /auth/login` y `GET /auth/me`).
  ///
  /// Lanza [RealAuthException], [ApiException] (por ejemplo 429 con
  /// `retryAfter`) o [ApiNetworkException].
  Future<void> login(String email, String password) async {
    final LoginResult result;
    try {
      result = await api.login(email.trim(), password);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        throw const RealAuthException('Correo o contraseña incorrectos.');
      }
      rethrow;
    }
    if (result.tokenType.toLowerCase() != 'bearer') {
      throw RealAuthException('Tipo de token no admitido: ${result.tokenType}');
    }
    if (result.role != 'PATIENT') {
      throw const RealAuthException('Esta app es solo para cuentas de paciente.');
    }
    final account = await api.me(result.accessToken);
    if (account.role != 'PATIENT' || !account.isActive) {
      throw const RealAuthException('Esta app es solo para cuentas de paciente activas.');
    }
    if (account.patientId == null) {
      throw const RealAuthException('Tu cuenta no tiene un perfil de paciente vinculado.');
    }

    var lifetime = Duration(seconds: result.expiresIn) - expiryMargin;
    if (lifetime.isNegative) lifetime = Duration.zero;
    _session = ApiSession(
      accessToken: result.accessToken,
      expiresAt: clock().add(lifetime),
      account: account,
    );
    notice = null;
    _expiryTimer?.cancel();
    _expiryTimer = Timer(lifetime, () => _expire());
    notifyListeners();
  }

  /// Cierra sesión: descarta el JWT, los datos cargados y las escrituras
  /// pendientes de esta cuenta.
  void logout() {
    if (_session != null) _pending.remove(_owner);
    _clearSession();
    notice = null;
    notifyListeners();
  }

  /// Sesión vencida o rechazada (401): se suspenden las operaciones y se pide
  /// iniciar sesión de nuevo. Las escrituras pendientes se conservan.
  void _expire([String message = 'Tu sesión venció. Inicia sesión de nuevo.']) {
    if (_session == null) return;
    _clearSession();
    notice = message;
    notifyListeners();
  }

  void _clearSession() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _session = null;
    journeys = [];
    contexts.clear();
    journeysError = null;
    notLinked = false;
    studies.clear();
    clinics.clear();
    _unavailableStudies.clear();
    _unavailableClinics.clear();
    catalogsLoaded = false;
  }

  /// Token vigente, o [ApiException] 401 tras suspender la sesión.
  String _token() {
    final s = _session;
    if (s == null) throw const ApiException(401, 'Sesión no iniciada');
    if (s.isExpired(clock())) {
      _expire();
      throw const ApiException(401, 'Sesión vencida');
    }
    return s.accessToken;
  }

  /// Lecturas autenticadas: un 401 suspende la sesión.
  Future<T> _authed<T>(Future<T> Function(String token) call) async {
    try {
      return await call(_token());
    } on ApiException catch (e) {
      if (e.isUnauthorized) _expire();
      rethrow;
    }
  }

  // -------------------------------------------------------------- trámites

  /// Trámites activos del paciente (`GET /mobile/journeys`), del más reciente
  /// al más antiguo según el servidor.
  List<JourneySummary> journeys = [];

  /// Último contexto leído por trámite.
  final Map<String, JourneyContext> contexts = {};

  bool loadingJourneys = false;
  String? journeysError;

  /// `404` al listar: la identidad institucional aún no tiene trámites
  /// vinculados. No es un error; crear un trámite establece el vínculo.
  bool notLinked = false;

  Future<void> refreshJourneys() async {
    if (_session == null) return;
    loadingJourneys = true;
    journeysError = null;
    notifyListeners();
    try {
      journeys = await _authed(api.listJourneys);
      notLinked = false;
      log('[modo real] GET /mobile/journeys → 200 con ${journeys.length} trámite(s).');
    } on ApiException catch (e) {
      if (e.isNotFound) {
        journeys = [];
        notLinked = true;
        // La pantalla dice lo mismo que con un 200 vacío, pero no es lo mismo:
        // un 404 indica que la identidad institucional no tiene vínculo. Si el
        // paciente debería tener trámites, hay que revisarlo en el servidor.
        log('[modo real] GET /mobile/journeys → 404 «${e.message}»: identidad sin '
            'vínculo o trámites inaccesibles. Se muestra "sin trámites vinculados". '
            'Si este paciente debería tener trámites, revisar su vínculo institucional '
            'en el servidor.');
      } else if (!e.isUnauthorized) {
        journeysError = humanApiError(e);
        log('[modo real] GET /mobile/journeys → ${e.statusCode} «${e.message}».');
      } else {
        log('[modo real] GET /mobile/journeys → 401: sesión suspendida.');
      }
    } on ApiNetworkException catch (e) {
      journeysError = e.message;
      log('[modo real] GET /mobile/journeys → sin respuesta: ${e.message}');
    } finally {
      loadingJourneys = false;
      notifyListeners();
    }
    if (_session == null) return;
    await Future.wait([
      loadCatalogs(),
      for (final j in journeys.take(prefetchContexts)) _prefetchContext(j.id),
    ]);
  }

  Future<void> _prefetchContext(String journeyId) async {
    try {
      contexts[journeyId] = await _authed((t) => api.context(t, journeyId));
      notifyListeners();
    } on ApiException {
      // La tarjeta del inicio se muestra sin estudio ni clínica.
    } on ApiNetworkException {
      // Igual: el detalle se vuelve a leer al abrir el trámite.
    }
  }

  /// Resumen, contexto y primera página del historial de un trámite.
  /// Lanza [ApiException] o [ApiNetworkException].
  Future<JourneyDetail> loadJourney(String journeyId, {int historyLimit = 20}) async {
    final results = await Future.wait([
      _authed((t) => api.summary(t, journeyId)),
      _authed((t) => api.context(t, journeyId)),
      _authed((t) => api.history(t, journeyId, limit: historyLimit)),
    ]);
    final summary = results[0] as JourneySummary;
    final context = results[1] as JourneyContext;
    final page = results[2] as HistoryPage;
    _remember(summary, context);
    return JourneyDetail(
      summary: summary,
      context: context,
      history: page.items,
      nextCursor: page.nextCursor,
    );
  }

  /// Agrega la siguiente página del historial (orden ascendente del servidor).
  Future<JourneyDetail> loadMoreHistory(JourneyDetail detail, {int historyLimit = 20}) async {
    final cursor = detail.nextCursor;
    if (cursor == null) return detail;
    final page = await _authed(
        (t) => api.history(t, detail.summary.id, limit: historyLimit, cursor: cursor));
    return JourneyDetail(
      summary: detail.summary,
      context: detail.context,
      history: [...detail.history, ...page.items],
      nextCursor: page.nextCursor,
    );
  }

  void _remember(JourneySummary summary, JourneyContext context) {
    contexts[summary.id] = context;
    final i = journeys.indexWhere((j) => j.id == summary.id);
    if (i >= 0) {
      journeys = [...journeys]..[i] = summary;
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- catálogos

  final Map<String, StudyItem> studies = {};
  final Map<String, ClinicItem> clinics = {};
  bool catalogsLoaded = false;
  final Set<String> _unavailableStudies = {};
  final Set<String> _unavailableClinics = {};

  /// Estudios y clínicas activos. Los errores no se propagan: sin catálogo, la
  /// app muestra el identificador y vuelve a intentarlo en la siguiente carga.
  Future<void> loadCatalogs({bool force = false}) async {
    if (catalogsLoaded && !force) return;
    try {
      final results = await Future.wait([api.studies(), api.clinics()]);
      studies
        ..clear()
        ..addEntries((results[0] as List<StudyItem>).map((s) => MapEntry(s.id, s)));
      clinics
        ..clear()
        ..addEntries((results[1] as List<ClinicItem>).map((c) => MapEntry(c.id, c)));
      catalogsLoaded = true;
      notifyListeners();
    } on ApiException {
      catalogsLoaded = false;
    } on ApiNetworkException {
      catalogsLoaded = false;
    }
  }

  /// Estudio por UUID: del catálogo o, si no está (inactivo o no cargado),
  /// `GET /studies/:id`. `null` si no existe o no está disponible.
  Future<StudyItem?> resolveStudy(String id) async {
    final known = studies[id];
    if (known != null || _unavailableStudies.contains(id)) return known;
    try {
      final s = await api.study(id);
      studies[id] = s;
      return s;
    } on ApiException catch (e) {
      if (e.isNotFound) _unavailableStudies.add(id);
      return null;
    } on ApiNetworkException {
      return null;
    }
  }

  Future<ClinicItem?> resolveClinic(String id) async {
    final known = clinics[id];
    if (known != null || _unavailableClinics.contains(id)) return known;
    try {
      final c = await api.clinic(id);
      clinics[id] = c;
      return c;
    } on ApiException catch (e) {
      if (e.isNotFound) _unavailableClinics.add(id);
      return null;
    } on ApiNetworkException {
      return null;
    }
  }

  // --------------------------------------------------------------- escritura

  /// Pendientes por dueño (`<url>|<patientId>`) y por ranura (UUID del trámite
  /// o la creación). Una ranura admite una sola operación a la vez.
  final Map<String, Map<String, PendingOperation>> _pending = {};

  Map<String, PendingOperation> get _mine =>
      _session == null ? const {} : (_pending[_owner] ??= {});

  PendingOperation? pendingFor(String journeyId) => _mine[journeyId];
  PendingOperation? get pendingCreate => _mine[_createSlot];
  List<PendingOperation> get pendingOperations => List.unmodifiable(_mine.values);

  void discardPending(PendingOperation op) {
    if (_mine.remove(op._slot) != null) notifyListeners();
  }

  /// Crea un trámite (`POST /mobile/journeys`). Si hay una creación pendiente,
  /// la reintenta con su misma `Idempotency-Key` en lugar de crear otra.
  Future<WriteResult<String>> createJourney() async {
    if (_session == null) return const WriteResult(WriteStatus.sessionExpired);
    final op = pendingCreate ??
        (_mine[_createSlot] = PendingOperation.create(idempotencyKey: OperationIds.idempotencyKey()));
    final r = await _execute(op);
    if (r.status != WriteStatus.done) return WriteResult(r.status, message: r.message);
    return WriteResult(WriteStatus.done, value: (r.value as JourneyCreated).id);
  }

  Future<WriteResult<EventReceipt>> selectStudy(JourneyContext ctx, String studyId) =>
      _publish(ctx, 'Selección de estudio', ApiEventTypes.contextUpdated, {'studyId': studyId});

  Future<WriteResult<EventReceipt>> selectClinic(JourneyContext ctx, String clinicId) =>
      _publish(ctx, 'Selección de clínica', ApiEventTypes.contextUpdated, {'clinicId': clinicId});

  /// Deja el trámite en `PENDING_CONFIRMATION`. El servidor exige estudio y
  /// clínica, y el estado `IN_PROGRESS`.
  Future<WriteResult<EventReceipt>> requestConfirmation(JourneyContext ctx) => _publish(
      ctx, 'Envío a confirmación', ApiEventTypes.statusChanged,
      {'to': ApiJourneyStatus.pendingConfirmation});

  Future<WriteResult<EventReceipt>> cancelJourney(JourneyContext ctx) => _publish(
      ctx, 'Cancelación', ApiEventTypes.statusChanged, {'to': ApiJourneyStatus.cancelled});

  Future<WriteResult<EventReceipt>> _publish(
      JourneyContext ctx, String label, String type, Map<String, dynamic> fields) async {
    if (_session == null) return const WriteResult(WriteStatus.sessionExpired);
    final existing = pendingFor(ctx.journeyId);
    if (existing != null) {
      return WriteResult(WriteStatus.rejected,
          message: 'Hay un cambio sin confirmar (${existing.label}). '
              'Reintenta su envío o descártalo antes de hacer otro.');
    }
    // Se arma una sola vez: los reintentos envían este mismo mapa.
    final op = PendingOperation.event(
      journeyId: ctx.journeyId,
      label: label,
      event: Map.unmodifiable({
        'externalEventId': OperationIds.externalEventId(),
        'type': type,
        'schemaVersion': 1,
        'occurredAt': OperationIds.utcNow(clock()),
        'payload': Map<String, dynamic>.unmodifiable({'expectedVersion': ctx.version, ...fields}),
      }),
    );
    _mine[op._slot] = op;
    notifyListeners();
    return _finishEvent(op, await _execute(op));
  }

  /// Reintenta una escritura pendiente con el mismo contenido.
  Future<WriteResult<Object>> retryPending(PendingOperation op) async {
    if (_session == null) return const WriteResult(WriteStatus.sessionExpired);
    if (!identical(_mine[op._slot], op)) {
      return const WriteResult(WriteStatus.rejected, message: 'La operación ya no está pendiente.');
    }
    final r = await _execute(op);
    if (op.kind == PendingKind.createJourney) {
      return WriteResult(r.status,
          value: r.isDone ? (r.value as JourneyCreated).id : null, message: r.message);
    }
    return _finishEvent(op, r);
  }

  /// Tras publicar o ante un 409, vuelve a leer el contexto vigente.
  Future<WriteResult<EventReceipt>> _finishEvent(
      PendingOperation op, _Attempt r) async {
    if (r.status != WriteStatus.done && r.status != WriteStatus.conflict) {
      return WriteResult(r.status, message: r.message);
    }
    JourneyContext? fresh;
    try {
      final ctx = await _authed((t) => api.context(t, op.journeyId!));
      contexts[op.journeyId!] = ctx;
      fresh = ctx;
      notifyListeners();
    } on ApiException {
      // Se informa el resultado de la escritura aunque no se pudo releer.
    } on ApiNetworkException {
      // Igual: la pantalla vuelve a leer el trámite.
    }
    return WriteResult(r.status,
        value: r.isDone ? r.value as EventReceipt : null, message: r.message, context: fresh);
  }

  /// Envía [op] con reintentos controlados. Solo la quita de pendientes cuando
  /// el servidor dio una respuesta definitiva.
  Future<_Attempt> _execute(PendingOperation op) async {
    final now = clock();
    final notBefore = op.notBefore;
    if (notBefore != null && now.isBefore(notBefore)) {
      final secs = (notBefore.difference(now).inMilliseconds / 1000).ceil();
      return _Attempt(WriteStatus.pending, message: 'Demasiadas solicitudes. Intenta en $secs s.');
    }
    op.notBefore = null;

    for (var attempt = 1;; attempt++) {
      final String token;
      try {
        token = _token();
      } on ApiException {
        return const _Attempt(WriteStatus.sessionExpired,
            message: 'Tu sesión venció. Inicia sesión de nuevo para enviar el cambio pendiente.');
      }
      op.attempts++;
      Duration? wait;
      try {
        final Object value = switch (op.kind) {
          PendingKind.createJourney =>
            await api.createJourney(token, idempotencyKey: op.idempotencyKey!),
          PendingKind.publishEvent => await api.publishEvent(token, op.journeyId!, op.event!),
        };
        _resolve(op);
        return _Attempt(WriteStatus.done, value: value);
      } on ApiNetworkException catch (e) {
        op.lastError = e.message;
        wait = _backoff(attempt);
      } on ApiException catch (e) {
        op.lastError = humanApiError(e);
        if (e.isUnauthorized) {
          _expire();
          return _Attempt(WriteStatus.sessionExpired, message: op.lastError);
        }
        if (e.isRateLimited) {
          final retryAfter = e.retryAfter ?? _backoff(attempt);
          if (retryAfter > autoRetryAfterLimit) {
            op.notBefore = clock().add(retryAfter);
            notifyListeners();
            return _Attempt(WriteStatus.pending, message: op.lastError);
          }
          wait = retryAfter;
        } else if (e.statusCode >= 500) {
          wait = _backoff(attempt);
        } else {
          _resolve(op);
          return _Attempt(e.isConflict ? WriteStatus.conflict : WriteStatus.rejected,
              message: op.lastError);
        }
      }
      if (attempt >= maxAttempts) {
        notifyListeners();
        return _Attempt(WriteStatus.pending, message: op.lastError);
      }
      await delay(wait);
    }
  }

  /// 1 s, 2 s, 4 s…
  static Duration _backoff(int attempt) => Duration(seconds: 1 << (attempt - 1));

  void _resolve(PendingOperation op) {
    for (final slots in _pending.values) {
      if (identical(slots[op._slot], op)) slots.remove(op._slot);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}

class _Attempt {
  final WriteStatus status;
  final Object? value;
  final String? message;
  const _Attempt(this.status, {this.value, this.message});

  bool get isDone => status == WriteStatus.done;
}
