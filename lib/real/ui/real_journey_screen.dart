import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../ui/layout/adaptive.dart';
import '../../ui/layout/window_size.dart';
import '../../widgets/common.dart';
import '../api_models.dart';
import '../real_state.dart';
import 'real_app.dart';
import 'real_connection_screen.dart';

/// Trámite del modo real: resumen, contexto e historial de
/// `GET /mobile/journeys/:id`, `/context` y `/history`.
///
/// Recorrido: estudio → clínica → revisión → `PENDING_CONFIRMATION`. Cada
/// selección publica `JOURNEY_CONTEXT_UPDATED` y el envío a confirmación
/// `JOURNEY_STATUS_CHANGED`; después se vuelve a leer el trámite.
class RealJourneyScreen extends StatefulWidget {
  final String journeyId;

  /// Abre el selector de estudio al cargar (trámite recién creado).
  final bool pickStudyOnOpen;

  const RealJourneyScreen({super.key, required this.journeyId, this.pickStudyOnOpen = false});

  @override
  State<RealJourneyScreen> createState() => _RealJourneyScreenState();
}

class _RealJourneyScreenState extends State<RealJourneyScreen> with WidgetsBindingObserver {
  JourneyDetail? _detail;
  String? _error;
  bool _busy = false;
  bool _loadingMore = false;
  bool _initialized = false;
  bool _pickedOnOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver a la app (por ejemplo, después de hablar con el Call Center)
  /// se lee de nuevo el trámite para ver el avance de otros canales.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted && !_busy) _load();
  }

  Future<void> _load() async {
    final state = RealScope.of(context);
    setState(() => _error = null);
    try {
      final d = await state.loadJourney(widget.journeyId);
      final studyId = d.context.studyId;
      final clinicId = d.context.clinicId;
      await Future.wait([
        state.loadCatalogs(),
        if (studyId != null) state.resolveStudy(studyId),
        if (clinicId != null) state.resolveClinic(clinicId),
      ]);
      if (!mounted) return;
      setState(() => _detail = d);
      if (widget.pickStudyOnOpen && !_pickedOnOpen && d.context.studyId == null) {
        _pickedOnOpen = true;
        await _pickStudy();
      }
    } on ApiException catch (e) {
      if (!e.isUnauthorized) _onLoadError(humanApiError(e));
    } on ApiNetworkException catch (e) {
      _onLoadError('No se pudo conectar con Salud Digna. (${e.message})');
    }
  }

  /// Con datos ya cargados se conservan y solo se avisa.
  void _onLoadError(String message) {
    if (!mounted) return;
    if (_detail == null) {
      setState(() => _error = message);
    } else {
      showSnack(context, 'No se pudo actualizar: $message', error: true);
    }
  }

  Future<void> _loadMore() async {
    final d = _detail;
    if (d == null || !d.hasMoreHistory) return;
    setState(() => _loadingMore = true);
    try {
      final next = await RealScope.of(context).loadMoreHistory(d);
      if (mounted) setState(() => _detail = next);
    } on ApiException catch (e) {
      if (mounted && !e.isUnauthorized) showSnack(context, humanApiError(e), error: true);
    } on ApiNetworkException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Publica un avance y muestra su resultado. Siempre vuelve a leer el trámite.
  Future<void> _write(Future<WriteResult<EventReceipt>> Function(RealState s, JourneyContext ctx) op,
      {required String doneMessage}) async {
    final d = _detail;
    if (d == null) return;
    final state = RealScope.of(context);
    setState(() => _busy = true);
    final r = await op(state, d.context);
    if (!mounted) return;
    switch (r.status) {
      case WriteStatus.done:
        HapticFeedback.lightImpact();
        showSnack(context, doneMessage);
      case WriteStatus.pending:
        showSnack(context, '${r.message ?? 'No se pudo enviar.'} El cambio queda pendiente para reintentar.',
            error: true);
      case WriteStatus.conflict:
        showSnack(context, r.message ?? 'El trámite cambió desde otro canal.', error: true);
      case WriteStatus.rejected:
        showSnack(context, r.message ?? 'No se pudo hacer el cambio.', error: true);
      case WriteStatus.sessionExpired:
        // La raíz regresa al acceso; el cambio queda pendiente para esta cuenta.
        break;
    }
    setState(() => _busy = false);
    if (state.isLoggedIn) await _load();
  }

  Future<void> _pickStudy() async {
    final state = RealScope.of(context);
    final current = _detail?.context.studyId;
    final chosen = await showAdaptivePicker<StudyItem>(
      context: context,
      builder: (_) => _CatalogPicker<StudyItem>(
        title: 'Elige tu estudio',
        subtitle: 'Precios del catálogo de Salud Digna',
        load: () async {
          await state.loadCatalogs();
          return state.studies.values.toList()..sort((a, b) => a.name.compareTo(b.name));
        },
        label: (s) => s.name,
        subtitleOf: (s) => formatPriceString(s.price),
        icon: Icons.biotech_outlined,
        isSelected: (s) => s.id == current,
      ),
    );
    if (chosen == null || chosen.id == current || !mounted) return;
    await _write((s, ctx) => s.selectStudy(ctx, chosen.id), doneMessage: 'Estudio guardado');
  }

  Future<void> _pickClinic() async {
    final state = RealScope.of(context);
    final current = _detail?.context.clinicId;
    final chosen = await showAdaptivePicker<ClinicItem>(
      context: context,
      builder: (_) => _CatalogPicker<ClinicItem>(
        title: 'Elige tu clínica',
        subtitle: 'Clínicas activas de Salud Digna',
        load: () async {
          await state.loadCatalogs();
          return state.clinics.values.toList()..sort((a, b) => a.name.compareTo(b.name));
        },
        label: (c) => c.name,
        subtitleOf: (c) => c.location,
        icon: Icons.local_hospital_outlined,
        isSelected: (c) => c.id == current,
      ),
    );
    if (chosen == null || chosen.id == current || !mounted) return;
    await _write((s, ctx) => s.selectClinic(ctx, chosen.id), doneMessage: 'Clínica guardada');
  }

  Future<void> _requestConfirmation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('¿Enviar a confirmación?'),
        content: const Text(
            'Tu trámite quedará pendiente de confirmación con el estudio y la clínica '
            'elegidos. Salud Digna lo confirmará después: esto todavía no es una cita '
            'confirmada ni reserva un horario.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _write((s, ctx) => s.requestConfirmation(ctx),
        doneMessage: 'Enviado: pendiente de confirmación');
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('¿Cancelar el trámite?'),
        content: const Text('El trámite se cerrará en todos los canales.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar trámite')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _write((s, ctx) => s.cancelJourney(ctx), doneMessage: 'Trámite cancelado');
  }

  @override
  Widget build(BuildContext context) {
    final state = RealScope.of(context);
    final d = _detail;
    final ws = context.windowSize;
    final pending = state.pendingFor(widget.journeyId);
    final status = d?.summary.status;
    final editable = d != null && ApiJourneyStatus.isEditable(status!) && pending == null;
    final canCancel = d != null && ApiJourneyStatus.isOpen(status!) && pending == null;

    final actions = <Widget>[
      IconButton(
        tooltip: 'Actualizar',
        icon: const Icon(Icons.refresh),
        onPressed: _busy ? null : _load,
      ),
      if (canCancel)
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (v) {
            if (v == 'cancel') _cancel();
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancelar trámite'))],
        ),
    ];

    Widget body;
    if (_error != null) {
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.lg),
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'No se pudo abrir el trámite',
            message: _error!,
            action: FilledButton.tonal(onPressed: _load, child: const Text('Reintentar')),
          ),
        ),
      );
    } else if (d == null) {
      body = ListView(
        padding: const EdgeInsets.all(Space.md),
        children: const [SkeletonCard(height: 160), SizedBox(height: Space.md), SkeletonCard(height: 140)],
      );
    } else {
      final studyId = d.context.studyId;
      final clinicId = d.context.clinicId;
      final study = studyId == null ? null : state.studies[studyId];
      final clinic = clinicId == null ? null : state.clinics[clinicId];
      body = Stack(
        fit: StackFit.expand,
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              key: const PageStorageKey<String>('real-journey'),
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.lg),
              children: [
                _HeaderCard(detail: d, study: study),
                if (pending != null) ...[
                  const SizedBox(height: Space.sm + 4),
                  _PendingCard(operation: pending, onFinished: _load),
                ],
                _StatusNote(status: d.summary.status),
                const SectionTitle('Tu trámite'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _ContextRow(
                        icon: Icons.biotech_outlined,
                        label: 'Estudio',
                        value: studyId == null
                            ? null
                            : study == null
                                ? 'Estudio no disponible en el catálogo'
                                : '${study.name} · ${formatPriceString(study.price)}',
                        enabled: editable && !_busy,
                        onTap: _pickStudy,
                      ),
                      const Divider(indent: 56),
                      _ContextRow(
                        icon: Icons.local_hospital_outlined,
                        label: 'Clínica',
                        value: clinicId == null
                            ? null
                            : clinic == null
                                ? 'Clínica no disponible en el catálogo'
                                : '${clinic.name} · ${clinic.location}',
                        hint: studyId == null ? 'Primero elige el estudio' : null,
                        enabled: editable && !_busy && studyId != null,
                        onTap: _pickClinic,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                _HistoryCard(
                  detail: d,
                  loadingMore: _loadingMore,
                  onLoadMore: _loadMore,
                ),
                const SectionTitle('Todavía no disponible en la app',
                    subtitle: 'La API central aún no lo ofrece al canal móvil'),
                const _UnsupportedCard(),
              ],
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
    }

    final primary = d == null || !editable ? null : _primaryAction(d);
    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        title: const Text('Tu trámite'),
        actions: actions,
      ),
      body: ResponsiveBody(safeBottom: primary == null, child: body),
      bottomNavigationBar: primary == null ? null : BottomActionBar(child: primary),
    );
  }

  /// Acción principal según lo que falta: estudio, clínica o envío.
  Widget _primaryAction(JourneyDetail d) {
    final ctx = d.context;
    final (label, icon, action) = ctx.studyId == null
        ? ('Elige tu estudio', Icons.arrow_forward, _pickStudy)
        : ctx.clinicId == null
            ? ('Elige tu clínica', Icons.arrow_forward, _pickClinic)
            : ('Enviar a confirmación', Icons.send_outlined, _requestConfirmation);
    return FilledButton.icon(
      onPressed: _busy ? null : action,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

// ------------------------------------------------------------ sub-widgets

class _HeaderCard extends StatelessWidget {
  final JourneyDetail detail;
  final StudyItem? study;
  const _HeaderCard({required this.detail, required this.study});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ctx = detail.context;
    final status = detail.summary.status;
    final done = status == ApiJourneyStatus.pendingConfirmation || status == ApiJourneyStatus.completed;
    final completed = done ? 4 : (ctx.clinicId != null ? 2 : (ctx.studyId != null ? 1 : 0));
    final title = ctx.studyId == null
        ? 'Elige tu estudio para empezar'
        : (study?.name ?? 'Estudio no disponible en el catálogo');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveHeader(
              title: Text(title, style: t.titleLarge?.copyWith(fontSize: 20)),
              trailing: StatusChip(status),
            ),
            const SizedBox(height: Space.md),
            StepProgress(
              steps: const ['Estudio', 'Clínica', 'Revisión', 'Confirmación'],
              completed: completed,
              done: done,
            ),
            const SizedBox(height: Space.md),
            Text('Paso actual: ${ApiJourneySteps.label(ctx.currentStep)}',
                style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Expanded(
                  child: SelectableText('Folio ${detail.summary.id}',
                      style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                ),
                IconButton(
                  tooltip: 'Copiar folio',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: detail.summary.id));
                    if (context.mounted) showSnack(context, 'Folio copiado');
                  },
                ),
              ],
            ),
            Text(
              'Actualizado ${formatRelative(ctx.updatedAt).toLowerCase()} · versión ${ctx.version}',
              style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explica los estados en los que el paciente ya no edita.
class _StatusNote extends StatelessWidget {
  final String status;
  const _StatusNote({required this.status});

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      ApiJourneyStatus.pendingConfirmation =>
        'Tu trámite está pendiente de confirmación. Salud Digna lo confirmará; '
            'la app todavía no confirma citas ni reserva horarios.',
      ApiJourneyStatus.completed => 'Este trámite ya se completó.',
      ApiJourneyStatus.cancelled => 'Este trámite fue cancelado.',
      _ => null,
    };
    if (message == null) return const SizedBox.shrink();
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm + 4),
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: s.tertiaryContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_top, color: s.onTertiaryContainer),
            const SizedBox(width: Space.sm + 4),
            Expanded(child: Text(message, style: TextStyle(color: s.onTertiaryContainer))),
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final PendingOperation operation;
  final VoidCallback onFinished;
  const _PendingCard({required this.operation, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Card(
      color: s.errorContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
            child: Text(
              'Este cambio todavía no llega a Salud Digna. Mientras tanto no puedes '
              'hacer otro cambio en este trámite. Si cierras la app, se pierde.',
              style: TextStyle(color: s.onErrorContainer),
            ),
          ),
          PendingOperationTile(operation: operation, onFinished: onFinished),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String? hint;
  final bool enabled;
  final VoidCallback onTap;
  const _ContextRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final empty = value == null;
    return ListTile(
      onTap: enabled ? onTap : null,
      leading: CircleAvatar(
        backgroundColor: empty ? s.surfaceContainerHighest : s.primary.withValues(alpha: 0.12),
        foregroundColor: empty ? s.onSurfaceVariant : s.primary,
        child: Icon(icon, size: 20),
      ),
      title: Text(label, style: t.labelMedium?.copyWith(color: s.onSurfaceVariant)),
      subtitle: Text(
        value ?? hint ?? 'Pendiente de elegir',
        style: t.bodyLarge?.copyWith(
          color: empty ? s.onSurfaceVariant : s.onSurface,
          fontStyle: empty ? FontStyle.italic : null,
        ),
      ),
      trailing: enabled
          ? Text(empty ? 'Elegir' : 'Cambiar', style: t.labelLarge?.copyWith(color: s.primary))
          : (empty ? null : Icon(Icons.check, color: s.primary)),
    );
  }
}

/// Historial del trámite en el orden del servidor (ascendente), con el canal
/// que registró cada evento (`producerCode`).
class _HistoryCard extends StatelessWidget {
  final JourneyDetail detail;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  const _HistoryCard({required this.detail, required this.loadingMore, required this.onLoadMore});

  static String _detail(HistoryItem e) {
    final d = e.data;
    final parts = <String>[
      if (d['currentStep'] is String) 'Paso: ${ApiJourneySteps.label(d['currentStep'] as String)}',
      if (d['from'] is String && d['to'] is String)
        '${statusHuman(d['from'] as String)} → ${statusHuman(d['to'] as String)}',
      if (d['version'] is int) 'versión ${d['version']}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final items = detail.history;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const PageStorageKey<String>('real-journey-history'),
          leading: Icon(Icons.history, color: s.primary),
          title: Text('Historial entre canales', style: t.titleMedium),
          subtitle: Text(
            items.isEmpty
                ? 'Sin eventos todavía'
                : '${items.length}${detail.hasMoreHistory ? '+' : ''} evento(s)',
            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in items)
              ListTile(
                dense: true,
                leading: Icon(_producerIcon(e.producerCode), color: s.primary),
                title: Text(ApiEventTypes.label(e.type)),
                subtitle: Text([
                  '${Producers.label(e.producerCode)} (${e.producerCode}) · '
                      '${formatRelative(e.occurredAt)}',
                  if (_detail(e).isNotEmpty) _detail(e),
                ].join('\n')),
                isThreeLine: _detail(e).isNotEmpty,
              ),
            if (detail.hasMoreHistory)
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: TextButton.icon(
                  onPressed: loadingMore ? null : onLoadMore,
                  icon: loadingMore
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more),
                  label: const Text('Cargar más'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _producerIcon(String code) => switch (code) {
        Producers.web => Icons.language,
        Producers.mobile => Icons.phone_android,
        Producers.callCenter => Icons.support_agent,
        Producers.whatsapp => Icons.chat_bubble_outline,
        Producers.admin => Icons.admin_panel_settings_outlined,
        _ => Icons.device_unknown,
      };
}

/// Funciones del simulador que la API central todavía no ofrece al canal
/// móvil. Se muestran deshabilitadas, con su explicación.
class _UnsupportedCard extends StatelessWidget {
  const _UnsupportedCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            enabled: false,
            leading: Icon(Icons.schedule),
            title: Text('Elegir fecha y hora'),
            subtitle: Text('No hay consulta de horarios disponibles para el canal móvil.'),
          ),
          Divider(),
          ListTile(
            enabled: false,
            leading: Icon(Icons.event_available_outlined),
            title: Text('Confirmar la cita'),
            subtitle: Text('El trámite llega hasta "pendiente de confirmación"; '
                'la confirmación la hace Salud Digna.'),
          ),
          Divider(),
          ListTile(
            enabled: false,
            leading: Icon(Icons.support_agent),
            title: Text('Avisar por WhatsApp o Call Center desde la app'),
            subtitle: Text('El historial no registra contactos desde la app; '
                'el asesor ve tu avance con tu autorización.'),
          ),
        ],
      ),
    );
  }
}

/// Selector de un catálogo (estudios o clínicas) cargado desde la API.
class _CatalogPicker<T> extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<List<T>> Function() load;
  final String Function(T) label;
  final String Function(T) subtitleOf;
  final IconData icon;
  final bool Function(T) isSelected;

  const _CatalogPicker({
    required this.title,
    required this.subtitle,
    required this.load,
    required this.label,
    required this.subtitleOf,
    required this.icon,
    required this.isSelected,
  });

  @override
  State<_CatalogPicker<T>> createState() => _CatalogPickerState<T>();
}

class _CatalogPickerState<T> extends State<_CatalogPicker<T>> {
  late Future<List<T>> _items = widget.load();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
            child: Column(
              children: [
                Text(widget.title, style: t.titleLarge),
                Text(widget.subtitle, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
              ],
            ),
          ),
          Flexible(
            child: FutureBuilder<List<T>>(
              future: _items,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(Space.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'No se pudo cargar el catálogo',
                    message: 'Revisa tu conexión e intenta de nuevo.',
                    action: FilledButton.tonal(
                      onPressed: () => setState(() => _items = widget.load()),
                      child: const Text('Reintentar'),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(indent: 72),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    final selected = widget.isSelected(it);
                    return ListTile(
                      selected: selected,
                      leading: CircleAvatar(
                        backgroundColor: selected ? s.primary : s.surfaceContainerHighest,
                        foregroundColor: selected ? s.onPrimary : s.onSurfaceVariant,
                        child: Icon(widget.icon, size: 20),
                      ),
                      title: Text(widget.label(it)),
                      subtitle: Text(widget.subtitleOf(it)),
                      trailing: selected ? Icon(Icons.check, color: s.primary) : null,
                      onTap: () => Navigator.pop(context, it),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
