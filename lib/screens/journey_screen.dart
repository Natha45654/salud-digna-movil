import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/catalog.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/contact_launcher.dart';
import '../ui/layout/adaptive.dart';
import '../ui/layout/window_size.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

/// Detalle de un trámite: contexto vigente, próximo paso y línea de tiempo
/// (GET /journeys/{id} y GET /journeys/{id}/events).
///
/// UX: el paciente ve en qué paso va (barra de progreso), qué le falta
/// (filas "Pendiente" tocables) y una sola acción principal fija abajo.
/// El identificador técnico del trámite no se muestra al paciente.
class JourneyScreen extends StatefulWidget {
  final String journeyId;

  /// Se abre para continuar un trámite pendiente: registra REQUEST_RESUMED y
  /// CHANNEL_SWITCHED y abre directamente el paso donde quedó.
  final bool resume;
  const JourneyScreen({super.key, required this.journeyId, this.resume = false});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  Journey? _journey;
  List<CanonicalEvent> _events = [];
  String? _error;
  bool _busy = false;
  bool _resumedNotified = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    setState(() => _error = null);
    try {
      final j = await state.getJourney(widget.journeyId);
      final ev = await state.getEvents(widget.journeyId);
      if (!mounted) return;
      setState(() {
        _journey = j;
        _events = ev.reversed.toList();
      });
      await _notifyResumeIfNeeded(j);
    } on OrchestratorException catch (e) {
      _onLoadError(e.message);
    } on NetworkException catch (e) {
      _onLoadError(e.message);
    }
  }

  /// Si ya había contexto cargado, se conserva (información parcial) y solo
  /// se avisa; si no, se muestra la vista de error con reintento.
  void _onLoadError(String message) {
    if (!mounted) return;
    if (_journey == null) {
      setState(() => _error = message);
    } else {
      showSnack(context, 'No se pudo actualizar: $message', error: true);
    }
  }

  /// Al continuar un trámite pendiente: registra REQUEST_RESUMED y, si viene
  /// de otro canal, CHANNEL_SWITCHED (origen y destino). Cada evento lleva la
  /// versión del contexto para que el servidor rechace un estado desactualizado.
  /// Después abre el paso exacto donde quedó.
  Future<void> _notifyResumeIfNeeded(Journey j) async {
    if (_resumedNotified || !widget.resume) return;
    if (!JourneyStatus.isOpen(j.status)) return;
    _resumedNotified = true;
    final state = AppScope.of(context);
    final from = j.lastChannel;
    final channels = {'fromChannel': from, 'toChannel': Channels.mobileApp};
    try {
      var ack = await state.sendEvent(state.buildEvent(
        eventType: EventTypes.requestResumed,
        journeyId: j.journeyId,
        data: channels,
        expectedVersion: j.version,
      ));
      if (ack != null && from != Channels.mobileApp) {
        ack = await state.sendEvent(state.buildEvent(
          eventType: EventTypes.channelSwitched,
          journeyId: j.journeyId,
          data: channels,
          expectedVersion: ack.version,
        ));
      }
      if (ack != null && mounted) {
        final j2 = await state.getJourney(widget.journeyId);
        final ev = await state.getEvents(widget.journeyId);
        if (mounted) {
          setState(() {
            _journey = j2;
            _events = ev.reversed.toList();
          });
        }
      }
    } on OrchestratorException catch (e) {
      // Estado desactualizado u otro rechazo: se informa y se recarga.
      if (mounted) showSnack(context, e.message, error: true);
      if (e.isConflict && mounted) await _load();
    } on NetworkException {
      // Sin red: los eventos quedan en el outbox y se reenvían después.
    }
    if (mounted) await _openNextStep();
  }

  /// Abre el selector del dato que falta (estudio, clínica u horario).
  Future<void> _openNextStep() async {
    final step = _journey?.nextStep?.code;
    switch (step) {
      case 'SELECT_STUDY':
        await _pickStudy();
      case 'SELECT_CLINIC':
        await _pickClinic();
      case 'SELECT_SLOT':
        await _pickSlot();
      default:
        break; // Confirmar o ver la cita: la acción principal ya está a la vista.
    }
  }

  Future<void> _send(String eventType, Map<String, dynamic> data) async {
    final state = AppScope.of(context);
    final j = _journey!;
    setState(() => _busy = true);
    try {
      final ack = await state.sendEvent(state.buildEvent(
        eventType: eventType,
        journeyId: j.journeyId,
        data: data,
        expectedVersion: j.version,
      ));
      if (!mounted) return;
      if (ack == null) {
        showSnack(context,
            'Sin conexión: el cambio quedó en cola y se reenviará (${state.outbox.length} pendientes)',
            error: true);
      } else if (ack.duplicate) {
        showSnack(context, 'Este cambio ya estaba registrado');
      } else if (eventType == EventTypes.confirmationRequested &&
          ack.status == JourneyStatus.confirmado) {
        HapticFeedback.mediumImpact();
        showSnack(context, '¡Cita confirmada!');
      }
      await _load();
    } on OrchestratorException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
      if (e.isConflict) await _load();
      // Otro paciente tomó el horario primero: no se confirmó nada. Se recarga
      // la lista de horarios para que elija otro.
      if (e.isSlotUnavailable && mounted) {
        setState(() => _busy = false);
        await _pickSlot();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickStudy() async {
    final current = _journey?.study?['studyId'] as String?;
    final st = await showAdaptivePicker<Study>(
      context: context,
      builder: (_) => _PickerSheet<Study>(
        title: 'Elige tu estudio',
        subtitle: 'Precios de referencia',
        items: studies,
        label: (s) => s.name,
        subtitleOf: (s) => formatMoney(s.price),
        icon: Icons.biotech_outlined,
        isSelected: (s) => s.id == current,
      ),
    );
    if (st != null) await _send(EventTypes.studySelected, st.toJson());
  }

  Future<void> _pickClinic() async {
    final current = _journey?.clinic?['clinicId'] as String?;
    final c = await showAdaptivePicker<Clinic>(
      context: context,
      builder: (_) => _PickerSheet<Clinic>(
        title: 'Elige tu clínica',
        subtitle: 'Cerca de ti',
        items: clinics,
        label: (c) => c.name,
        subtitleOf: (c) => c.city,
        icon: Icons.local_hospital_outlined,
        isSelected: (c) => c.id == current,
      ),
    );
    if (c != null) await _send(EventTypes.clinicSelected, c.toJson());
  }

  Future<void> _pickSlot() async {
    final j = _journey;
    if (j == null) return;
    final clinicId = j.clinic?['clinicId'] as String?;
    if (clinicId == null) {
      showSnack(context, 'Primero elige una clínica.');
      await _pickClinic();
      return;
    }
    final raw = j.slot?['slotStart'] as String?;
    final current = raw == null ? null : DateTime.tryParse(raw);
    final state = AppScope.of(context);
    final choice = await showAdaptivePicker<_SlotChoice>(
      context: context,
      builder: (_) => _SlotPicker(
        clinicName: j.clinic?['clinicName'] as String? ?? '',
        current: current,
        load: () => state.availableSlots(j.journeyId, clinicId),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.changeClinic) {
      await _pickClinic();
      return;
    }
    await _send(EventTypes.slotSelected, {'slotStart': choice.slot!.toIso8601String()});
  }

  Future<void> _confirm() async {
    final j = _journey!;
    final slotRaw = j.slot?['slotStart'] as String?;
    final slot = slotRaw == null ? null : DateTime.tryParse(slotRaw);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.event_available_outlined),
        title: const Text('Confirmar cita'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryLine(Icons.biotech_outlined, '${j.study?['studyName'] ?? ''}'),
            _SummaryLine(Icons.local_hospital_outlined, '${j.clinic?['clinicName'] ?? ''}'),
            if (slot != null) _SummaryLine(Icons.schedule, formatRelative(slot)),
            const SizedBox(height: Space.sm),
            const Text('Se enviará la solicitud al sistema de citas. ¿Deseas confirmar?'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) {
      await _send(EventTypes.confirmationRequested, {'channel': Channels.mobileApp});
    }
  }

  Future<void> _cancel() async {
    final confirmed = _journey?.status == JourneyStatus.confirmado;
    final title = confirmed ? 'Cancelar cita' : 'Cancelar trámite';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: Icon(Icons.warning_amber_outlined, color: Theme.of(ctx).colorScheme.error),
        title: Text(title),
        content: Text(confirmed
            ? 'Tu cita quedará cancelada y se liberará el horario. Podrás agendar una nueva cuando quieras.'
            : 'El trámite quedará cancelado en todos los canales. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _send(EventTypes.journeyCancelled, {'reason': confirmed ? 'CANCELLED_BY_PATIENT' : 'ABANDONED_BY_PATIENT'});
    }
  }

  /// "¿Necesitas ayuda?": antes de abrir WhatsApp o el marcador registra
  /// CONTACT_INITIATED con el canal y el paso actual, para que el asesor vea
  /// de dónde viene el paciente. Solo en trámites abiertos (el orquestador no
  /// admite cambios en uno cerrado); el contacto se abre en cualquier caso.
  Future<void> _contact(String channel) async {
    final state = AppScope.of(context);
    final j = _journey!;
    if (JourneyStatus.isOpen(j.status)) {
      Future<void> register(int version) => state.sendEvent(state.buildEvent(
            eventType: EventTypes.contactInitiated,
            journeyId: j.journeyId,
            data: {'channel': channel, 'step': j.nextStep?.code},
            expectedVersion: version,
          ));
      try {
        try {
          await register(j.version);
        } on OrchestratorException catch (e) {
          // Otro canal escribió antes: se reintenta una vez con la versión vigente.
          if (!e.isConflict) rethrow;
          await register((await state.getJourney(j.journeyId)).version);
        }
      } on OrchestratorException {
        // No impide el contacto: el paciente debe poder pedir ayuda.
      }
    }
    final study = j.study?['studyName'];
    final opened = await ContactLauncher.open(ContactLauncher.uriFor(
      channel,
      message: 'Hola, necesito ayuda con mi cita'
          '${study != null ? ' de $study' : ''}. La inicié en la app de Salud Digna.',
      simulator: state.config.whatsappSimulator,
    ));
    if (!mounted) return;
    if (!opened) {
      showSnack(context, _contactError(channel), error: true);
    }
    await _load();
  }

  /// Mensaje cuando no hay aplicación para abrir el contacto; el número solo
  /// se menciona si está configurado (SD_WHATSAPP / SD_CALL_CENTER).
  static String _contactError(String channel) {
    if (channel == Channels.whatsapp) {
      final n = ContactInfo.displayOrNull(ContactInfo.whatsapp);
      return n == null ? 'No se pudo abrir WhatsApp.' : 'No se pudo abrir WhatsApp. Escríbenos al $n.';
    }
    final n = ContactInfo.displayOrNull(ContactInfo.callCenter);
    return n == null ? 'No se pudo abrir el teléfono.' : 'No se pudo abrir el teléfono. Llámanos al $n.';
  }

  @override
  Widget build(BuildContext context) {
    final j = _journey;
    final open = j != null && JourneyStatus.isOpen(j.status);
    final ws = context.windowSize;

    final appBarActions = <Widget>[
      IconButton(
        tooltip: 'Actualizar',
        icon: const Icon(Icons.refresh),
        onPressed: _busy ? null : _load,
      ),
      IconButton(
        tooltip: 'Conexión',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
      if (open)
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (v) {
            if (v == 'cancel') _cancel();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'cancel', child: Text('Cancelar trámite')),
          ],
        ),
    ];

    final busyOverlay = Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.08),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );

    // Bloques del trámite: los mismos en ambos layouts.
    List<Widget> summaryBlocks(Journey j) => [
          _HeaderCard(journey: j),
          if (j.status == JourneyStatus.confirmado) ...[
            const SizedBox(height: Space.sm + 4),
            _AppointmentCard(journey: j),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Cancelar cita'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ];
    List<Widget> detailBlocks(Journey j) => [
          const SectionTitle('Tu trámite'),
          _ContextCard(
            journey: j,
            busy: _busy,
            onPickStudy: _pickStudy,
            onPickClinic: _pickClinic,
            onPickSlot: _pickSlot,
          ),
          const SizedBox(height: Space.md),
          // Plegado por omisión: no compite con la acción principal.
          _Timeline(events: _events),
          const SectionTitle('¿Necesitas ayuda?',
              subtitle: 'El asesor verá en qué paso vas, sin que lo repitas'),
          _HelpCard(busy: _busy, onContact: _contact),
        ];
    Widget nextStep(Journey j) => _NextStepButton(
          journey: j,
          busy: _busy,
          onPickStudy: _pickStudy,
          onPickClinic: _pickClinic,
          onPickSlot: _pickSlot,
          onConfirm: _confirm,
        );

    // Dos paneles (alto compacto): resumen y acción principal a la izquierda,
    // siempre visibles; datos e historial a la derecha. Sin barra al pie.
    if (j != null && _error == null && ws.useTwoPane) {
      return Scaffold(
        appBar: ContentAppBar(
          compact: true,
          maxContentWidth: double.infinity,
          title: const Text('Agendar cita'),
          actions: appBarActions,
        ),
        body: Stack(
          children: [
            TwoPaneLayout(
              side: PaneWithPinnedAction(
                scrollKey: const PageStorageKey<String>('journey-summary'),
                action: open ? nextStep(j) : null,
                children: summaryBlocks(j),
              ),
              main: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  key: const PageStorageKey<String>('journey-detail'),
                  padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
                  children: detailBlocks(j),
                ),
              ),
            ),
            if (_busy) busyOverlay,
          ],
        ),
      );
    }

    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        title: const Text('Agendar cita'),
        actions: appBarActions,
      ),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : j == null
              ? const _LoadingView()
              : ResponsiveBody(
                  safeBottom: !open,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          key: const PageStorageKey<String>('journey-detail'),
                          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.lg),
                          children: [...summaryBlocks(j), ...detailBlocks(j)],
                        ),
                      ),
                      if (_busy) busyOverlay,
                    ],
                  ),
                ),
      bottomNavigationBar: !open ? null : BottomActionBar(child: nextStep(j)),
    );
  }
}

// ------------------------------------------------------------ sub-widgets

class _HeaderCard extends StatelessWidget {
  final Journey journey;
  const _HeaderCard({required this.journey});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final completed =
        [journey.study, journey.clinic, journey.slot].where((x) => x != null).length;
    final done = journey.status == JourneyStatus.confirmado;
    final study = journey.study?['studyName'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveHeader(
              title: Text(study ?? 'Elige tu estudio para empezar',
                  style: t.titleLarge?.copyWith(fontSize: 20)),
              trailing: StatusChip(journey.status),
            ),
            const SizedBox(height: Space.md),
            StepProgress(
              steps: const ['Estudio', 'Clínica', 'Horario', 'Confirmar'],
              completed: completed,
              done: done,
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Canales:', style: t.labelMedium?.copyWith(color: s.onSurfaceVariant)),
                for (final c in journey.channels) ChannelChip(c),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Actualizado ${formatRelative(journey.updatedAt).toLowerCase()}',
              style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  final Journey journey;
  final bool busy;
  final VoidCallback onPickStudy;
  final VoidCallback onPickClinic;
  final VoidCallback onPickSlot;
  const _ContextCard({
    required this.journey,
    required this.busy,
    required this.onPickStudy,
    required this.onPickClinic,
    required this.onPickSlot,
  });

  @override
  Widget build(BuildContext context) {
    final open = JourneyStatus.isOpen(journey.status);
    final study = journey.study;
    final clinic = journey.clinic;
    final slotRaw = journey.slot?['slotStart'] as String?;
    final slot = slotRaw == null ? null : DateTime.tryParse(slotRaw);
    final price = study?['price'];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ContextRow(
            icon: Icons.biotech_outlined,
            label: 'Estudio',
            value: study == null
                ? null
                : '${study['studyName']}${price is num ? ' · ${formatMoney(price)}' : ''}',
            enabled: open && !busy,
            onTap: onPickStudy,
          ),
          const Divider(indent: 56),
          _ContextRow(
            icon: Icons.local_hospital_outlined,
            label: 'Clínica',
            value: clinic?['clinicName'] as String?,
            enabled: open && !busy,
            onTap: onPickClinic,
          ),
          const Divider(indent: 56),
          _ContextRow(
            icon: Icons.schedule,
            label: 'Horario',
            value: slot == null ? null : formatRelative(slot),
            warning: open && journey.context['slotUnavailable'] == true
                ? OrchestratorException.slotUnavailableMessage
                : null,
            enabled: open && !busy,
            onTap: onPickSlot,
          ),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool enabled;
  final VoidCallback onTap;
  final String? warning;
  const _ContextRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pending = value == null;
    final actionLabel = pending ? 'Elegir' : 'Cambiar';
    // Con poco ancho para la escala de letra, la acción de la derecha pasa a
    // ser un ícono para no dejar sin espacio al valor (la fila entera sigue
    // siendo tocable y el lector de pantalla anuncia "Elegir" o "Cambiar").
    final compact = MediaQuery.sizeOf(context).width <
        LayoutTokens.inlineActionMinWidth * textScaleOf(context);
    return ListTile(
      onTap: enabled ? onTap : null,
      leading: CircleAvatar(
        backgroundColor: pending ? s.surfaceContainerHighest : s.primary.withValues(alpha: 0.12),
        foregroundColor: pending ? s.onSurfaceVariant : s.primary,
        child: Icon(icon, size: 20),
      ),
      title: Text(label, style: t.labelMedium?.copyWith(color: s.onSurfaceVariant)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value ?? 'Pendiente de elegir',
            style: t.bodyLarge?.copyWith(
              color: pending ? s.onSurfaceVariant : s.onSurface,
              fontStyle: pending ? FontStyle.italic : null,
              decoration: warning != null ? TextDecoration.lineThrough : null,
            ),
          ),
          if (warning != null)
            Text(warning!, style: t.bodySmall?.copyWith(color: s.error)),
        ],
      ),
      trailing: enabled
          ? (compact
              ? Icon(Icons.chevron_right, color: s.primary, semanticLabel: actionLabel)
              : Text(actionLabel, style: t.labelLarge?.copyWith(color: s.primary)))
          : (pending ? null : Icon(Icons.check, color: s.primary)),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Journey journey;
  const _AppointmentCard({required this.journey});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final appt = journey.appointment ?? const {};
    final folio = '${appt['appointmentId'] ?? '—'}';
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: s.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: s.primary, size: 40),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cita confirmada',
                    style: t.titleMedium?.copyWith(color: s.onPrimaryContainer)),
                Text('Folio $folio',
                    style: t.titleLarge?.copyWith(color: s.onPrimaryContainer, fontSize: 18)),
                Text('Presenta este folio en recepción.',
                    style: t.bodySmall?.copyWith(color: s.onPrimaryContainer)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar folio',
            icon: Icon(Icons.copy_outlined, color: s.onPrimaryContainer),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: folio));
              if (context.mounted) showSnack(context, 'Folio copiado');
            },
          ),
        ],
      ),
    );
  }
}

class _NextStepButton extends StatelessWidget {
  final Journey journey;
  final bool busy;
  final VoidCallback onPickStudy;
  final VoidCallback onPickClinic;
  final VoidCallback onPickSlot;
  final VoidCallback onConfirm;
  const _NextStepButton({
    required this.journey,
    required this.busy,
    required this.onPickStudy,
    required this.onPickClinic,
    required this.onPickSlot,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final step = journey.nextStep;
    if (step == null) return const SizedBox.shrink();
    final action = switch (step.code) {
      'SELECT_STUDY' => onPickStudy,
      'SELECT_CLINIC' => onPickClinic,
      'SELECT_SLOT' => onPickSlot,
      'CONFIRM_APPOINTMENT' => onConfirm,
      _ => null,
    };
    final isConfirm = step.code == 'CONFIRM_APPOINTMENT';
    return FilledButton.icon(
      onPressed: busy || action == null ? null : action,
      icon: Icon(isConfirm ? Icons.check_circle_outline : Icons.arrow_forward),
      label: Text(step.label),
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<CanonicalEvent> events;
  const _Timeline({required this.events});

  String _detail(CanonicalEvent e) {
    final d = e.data;
    return switch (e.eventType) {
      EventTypes.studySelected => '${d['studyName'] ?? d['studyId'] ?? ''}',
      EventTypes.clinicSelected => '${d['clinicName'] ?? d['clinicId'] ?? ''}',
      EventTypes.slotSelected => d['slotStart'] is String
          ? formatRelative(DateTime.parse(d['slotStart'] as String))
          : '',
      EventTypes.contextResumed =>
        'Venía de ${Channels.label('${d['previousChannel'] ?? ''}')}',
      EventTypes.requestResumed =>
        'Venía de ${channelLabel('${d['fromChannel'] ?? ''}')}',
      EventTypes.channelSwitched =>
        'De ${channelLabel('${d['fromChannel'] ?? ''}')} a ${channelLabel('${d['toChannel'] ?? ''}')}',
      EventTypes.appointmentConfirmed => 'Folio ${d['appointmentId'] ?? ''}',
      EventTypes.contactInitiated => 'Por ${channelLabel('${d['channel'] ?? ''}')}',
      _ => '',
    };
  }

  /// "6 eventos, último hoy 15:49". La lista llega del más reciente al más antiguo.
  String _summary() {
    final n = events.length;
    final count = n == 1 ? '1 evento' : '$n eventos';
    return '$count, último ${formatShortRelative(events.first.occurredAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // La clave conserva abierto/cerrado al girar la pantalla.
          key: const PageStorageKey<String>('journey-history'),
          initiallyExpanded: false,
          leading: Icon(Icons.history, color: s.primary),
          title: Text('Historial de atención', style: t.titleMedium),
          subtitle: Text(
            events.isEmpty ? 'Sin eventos todavía' : _summary(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
          ),
          childrenPadding: const EdgeInsets.only(bottom: Space.sm),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xs),
              child: Text(
                'Todo lo que ha pasado con este trámite, en cualquier canal',
                style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
              ),
            ),
            for (var i = 0; i < events.length; i++)
              _TimelineRow(
                event: events[i],
                detail: _detail(events[i]),
                isFirst: i == 0,
                isLast: i == events.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

/// Contactar a Salud Digna por WhatsApp o Call Center.
class _HelpCard extends StatelessWidget {
  final bool busy;
  final Future<void> Function(String channel) onContact;

  const _HelpCard({required this.busy, required this.onContact});

  static Widget? _number(String digits) {
    final n = ContactInfo.displayOrNull(digits);
    return n == null ? null : Text(n);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(channelIcon(Channels.whatsapp), color: s.primary),
            title: const Text('Escribir por WhatsApp'),
            subtitle: _number(ContactInfo.whatsapp),
            trailing: const Icon(Icons.open_in_new),
            enabled: !busy,
            onTap: () => onContact(Channels.whatsapp),
          ),
          const Divider(),
          ListTile(
            leading: Icon(channelIcon(Channels.callCenter), color: s.primary),
            title: const Text('Llamar al Call Center'),
            subtitle: _number(ContactInfo.callCenter),
            trailing: const Icon(Icons.open_in_new),
            enabled: !busy,
            onTap: () => onContact(Channels.callCenter),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final CanonicalEvent event;
  final String detail;
  final bool isFirst;
  final bool isLast;
  const _TimelineRow({
    required this.event,
    required this.detail,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final isApp = event.sourceSystem == Channels.mobileApp;
    final isSystem = event.sourceSystem == 'APPOINTMENT_SYSTEM';
    final color = isSystem ? s.tertiary : (isApp ? s.primary : s.secondary);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              children: [
                Expanded(
                  child: Container(width: 2, color: isFirst ? Colors.transparent : s.outlineVariant),
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: isFirst ? 1 : 0.15),
                  foregroundColor: isFirst ? s.onPrimary : color,
                  child: Icon(channelIcon(event.sourceSystem), size: 16),
                ),
                Expanded(
                  child: Container(width: 2, color: isLast ? Colors.transparent : s.outlineVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, Space.sm + 4, Space.md, Space.sm + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(EventTypes.label(event.eventType),
                      style: t.bodyLarge?.copyWith(fontWeight: isFirst ? FontWeight.w600 : null)),
                  if (detail.isNotEmpty)
                    Text(detail, style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(
                    '${channelLabel(event.sourceSystem)} · ${formatRelative(event.occurredAt)}',
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<T> items;
  final String Function(T) label;
  final String Function(T)? subtitleOf;
  final IconData icon;
  final bool Function(T) isSelected;
  const _PickerSheet({
    required this.title,
    this.subtitle,
    required this.items,
    required this.label,
    this.subtitleOf,
    required this.icon,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: Column(
                children: [
                  Text(title, style: t.titleLarge),
                  if (subtitle != null)
                    Text(subtitle!, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(indent: 72),
                itemBuilder: (context, i) {
                  final it = items[i];
                  final selected = isSelected(it);
                  return ListTile(
                    selected: selected,
                    leading: CircleAvatar(
                      backgroundColor: selected ? s.primary : s.surfaceContainerHighest,
                      foregroundColor: selected ? s.onPrimary : s.onSurfaceVariant,
                      child: Icon(icon, size: 20),
                    ),
                    title: Text(label(it)),
                    subtitle: subtitleOf == null ? null : Text(subtitleOf!(it)),
                    trailing: selected ? Icon(Icons.check, color: s.primary) : null,
                    onTap: () => Navigator.pop(context, it),
                  );
                },
              ),
            ),
          ],
        ),
    );
  }
}

/// Resultado del selector de horarios: un horario o "cambiar clínica".
class _SlotChoice {
  final DateTime? slot;
  final bool changeClinic;
  const _SlotChoice.slot(DateTime this.slot) : changeClinic = false;
  const _SlotChoice.changeClinic()
      : slot = null,
        changeClinic = true;
}

/// Selector de horarios: días como chips y, por día, solo los horarios libres
/// en la clínica (los ocupados no se muestran). Si un día no tiene horarios,
/// ofrece ver otro día o cambiar de clínica.
class _SlotPicker extends StatefulWidget {
  final String clinicName;
  final DateTime? current;
  final Future<List<DateTime>> Function() load;
  const _SlotPicker({required this.clinicName, required this.current, required this.load});

  @override
  State<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<_SlotPicker> {
  late final List<DateTime> _days;
  List<DateTime>? _slots;
  String? _error;
  int _day = 0;

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _days = [
      for (final d in catalogSlots())
        if (seen.add('${d.year}-${d.month}-${d.day}')) DateTime(d.year, d.month, d.day),
    ];
    final c = widget.current;
    if (c != null) {
      final i = _days.indexWhere((d) => d.year == c.year && d.month == c.month && d.day == c.day);
      if (i >= 0) _day = i;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _slots = null;
      _error = null;
    });
    try {
      final r = await widget.load();
      if (mounted) setState(() => _slots = r);
    } on OrchestratorException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NetworkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final day = _days[_day];
    final daySlots = (_slots ?? const <DateTime>[])
        .where((d) => d.year == day.year && d.month == day.month && d.day == day.day)
        .toList();

    Widget body;
    if (_error != null) {
      body = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los horarios',
        message: _error!,
        action: FilledButton.tonal(onPressed: _fetch, child: const Text('Reintentar')),
      );
    } else if (_slots == null) {
      body = const Padding(
        padding: EdgeInsets.all(Space.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (daySlots.isEmpty) {
      body = EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'No hay horarios disponibles',
        message: 'No hay horarios disponibles en esta clínica para este día.',
        action: Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            if (_day < _days.length - 1)
              FilledButton.tonal(
                onPressed: () => setState(() => _day++),
                child: const Text('Ver otro día'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, const _SlotChoice.changeClinic()),
              child: const Text('Cambiar clínica'),
            ),
          ],
        ),
      );
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        // El selector completo se desplaza como una sola lista.
        physics: const NeverScrollableScrollPhysics(),
        itemCount: daySlots.length,
        separatorBuilder: (_, _) => const Divider(indent: 72),
        itemBuilder: (context, i) {
          final slot = daySlots[i];
          final c = widget.current;
          final selected = c != null && slot.isAtSameMomentAs(c);
          String two(int n) => n.toString().padLeft(2, '0');
          return ListTile(
            selected: selected,
            leading: CircleAvatar(
              backgroundColor: selected ? s.primary : s.surfaceContainerHighest,
              foregroundColor: selected ? s.onPrimary : s.onSurfaceVariant,
              child: const Icon(Icons.schedule, size: 20),
            ),
            title: Text('${two(slot.hour)}:${two(slot.minute)}'),
            trailing: selected ? Icon(Icons.check, color: s.primary) : null,
            onTap: () => Navigator.pop(context, _SlotChoice.slot(slot)),
          );
        },
      );
    }

    // Todo el selector se desplaza junto: con letra grande o poca altura, el
    // encabezado y los días no compiten por espacio con la lista.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Column(
              children: [
                Text('Elige un horario', style: t.titleLarge, textAlign: TextAlign.center),
                if (widget.clinicName.isNotEmpty)
                  Text(
                    'Horarios disponibles en ${widget.clinicName}',
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < _days.length; i++)
                  ChoiceChip(
                    label: Text(formatDayLabel(_days[i])),
                    selected: i == _day,
                    onSelected: (_) => setState(() => _day = i),
                  ),
              ],
            ),
          ),
          body,
        ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SummaryLine(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: s.primary),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Space.md),
      children: const [
        SkeletonCard(height: 150),
        SizedBox(height: Space.md),
        SkeletonCard(height: 200),
        SizedBox(height: Space.md),
        SkeletonCard(height: 180),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No pudimos cargar tu trámite',
        message: message,
        action: FilledButton.tonal(onPressed: onRetry, child: const Text('Reintentar')),
      ),
    );
  }
}
