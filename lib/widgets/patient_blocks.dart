import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/catalog.dart';
import '../models/models.dart';
import '../ui/layout/window_size.dart';
import 'common.dart';

/// Bloques de la pantalla de Inicio. Las pantallas los componen en una o dos
/// columnas según el espacio; nunca se duplican por orientación.

/// Tarjeta de identidad del paciente. `compact` reduce relleno y avatar para
/// el panel lateral.
class IdentityCard extends StatelessWidget {
  final PatientSession session;
  final bool compact;
  const IdentityCard({super.key, required this.session, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final initials = session.displayName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join();
    final badge = Tooltip(
      message: 'Identidad verificada en este canal',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: s.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user, size: 16, color: s.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text('Verificada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: s.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    final scale = textScaleOf(context);
    return Container(
      padding: EdgeInsets.all(compact ? Space.sm + 4 : Space.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [s.primaryContainer, s.primaryContainer.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final stacked = c.maxWidth < LayoutTokens.inlineBadgeMinWidth * scale;
          return Row(
            children: [
              CircleAvatar(
                radius: compact ? 20 : 24,
                backgroundColor: s.primary,
                foregroundColor: s.onPrimary,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: compact ? Space.sm + 4 : Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(color: s.onPrimaryContainer)),
                    const SizedBox(height: 2),
                    Text(
                      session.identifiers.map((e) => e.value).join(' · '),
                      maxLines: compact ? 2 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: t.bodySmall?.copyWith(color: s.onPrimaryContainer),
                    ),
                    if (stacked) ...[
                      const SizedBox(height: Space.sm),
                      badge,
                    ],
                  ],
                ),
              ),
              if (!stacked) ...[
                const SizedBox(width: Space.sm),
                badge,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Trámite abierto con su progreso y la acción principal para continuarlo.
class PendingJourneyCard extends StatelessWidget {
  final Journey journey;
  final VoidCallback onTap;
  const PendingJourneyCard({super.key, required this.journey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final study = journey.study?['studyName'] as String?;
    final clinic = journey.clinic?['clinicName'] as String?;
    final completed = [journey.study, journey.clinic, journey.slot].where((x) => x != null).length;
    final missing = journey.pendingFields;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdaptiveHeader(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Agendar cita',
                        style: t.labelMedium?.copyWith(color: s.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(study ?? 'Estudio por elegir',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(fontSize: 18)),
                    if (clinic != null)
                      Text(clinic,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
                  ],
                ),
                trailing: StatusChip(journey.status),
              ),
              const SizedBox(height: Space.md),
              StepProgress(
                steps: const ['Estudio', 'Clínica', 'Horario', 'Confirmar'],
                completed: completed,
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Text(
                  'Falta: ${missing.join(', ')}',
                  style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                ),
              ],
              ...[
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Icon(channelIcon(journey.lastChannel), size: 16, color: s.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Lo dejaste en ${Channels.label(journey.lastChannel)} · '
                        '${formatRelative(journey.updatedAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: s.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Space.md),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward),
                label: Text(journey.nextStep?.label ?? 'Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista compacta de citas cerradas (confirmadas o canceladas).
class AppointmentsList extends StatelessWidget {
  final List<Journey> journeys;
  final ValueChanged<Journey> onOpen;
  const AppointmentsList({super.key, required this.journeys, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < journeys.length; i++) ...[
            _ClosedJourneyTile(journey: journeys[i], onTap: () => onOpen(journeys[i])),
            if (i < journeys.length - 1) const Divider(indent: 64),
          ],
        ],
      ),
    );
  }
}

class _ClosedJourneyTile extends StatelessWidget {
  final Journey journey;
  final VoidCallback onTap;
  const _ClosedJourneyTile({required this.journey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final study = journey.study?['studyName'] as String? ?? 'Trámite';
    final clinic = clinicById(journey.clinic?['clinicId'] as String?)?.name ??
        journey.clinic?['clinicName'] as String?;
    final slotRaw = journey.slot?['slotStart'] as String?;
    final slot = slotRaw == null ? null : DateTime.tryParse(slotRaw);
    final confirmed = journey.status == JourneyStatus.confirmado;
    final scale = textScaleOf(context);
    final muted = t.bodyMedium?.copyWith(color: s.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm + 4),
          child: LayoutBuilder(
            builder: (context, c) {
              final stacked = c.maxWidth < LayoutTokens.inlineBadgeMinWidth * scale;
              final chip = StatusChip(journey.status);
              return Row(
                children: [
                  CircleAvatar(
                    backgroundColor: (confirmed ? s.primary : s.error).withValues(alpha: 0.12),
                    foregroundColor: confirmed ? s.primary : s.error,
                    child: Icon(confirmed ? Icons.event_available : Icons.event_busy),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(study, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyLarge),
                        if (slot != null) Text(formatRelative(slot), style: muted),
                        if (clinic != null)
                          Tooltip(
                            message: clinic,
                            child: Semantics(
                              label: clinic,
                              excludeSemantics: true,
                              child: Text(
                                shortClinicName(clinic),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: muted,
                              ),
                            ),
                          ),
                        if (stacked) ...[
                          const SizedBox(height: Space.xs + 2),
                          chip,
                        ],
                      ],
                    ),
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: Space.sm),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: c.maxWidth * 0.4),
                      child: chip,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
