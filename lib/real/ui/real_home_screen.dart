import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/layout/adaptive.dart';
import '../../ui/layout/window_size.dart';
import '../../widgets/common.dart';
import '../../widgets/patient_blocks.dart';
import '../api_models.dart';
import 'real_app.dart';
import 'real_connection_screen.dart';

/// Inicio del modo real: trámites activos del paciente según
/// `GET /mobile/journeys`, con su estudio y clínica cuando el contexto se
/// pudo leer.
class RealHomeScreen extends StatefulWidget {
  /// Abre un trámite. Null mientras la pantalla del trámite no existe.
  final void Function(BuildContext context, JourneySummary journey)? onOpen;

  /// Acción "Nueva cita". Null mientras la pantalla del trámite no existe.
  final Future<void> Function(BuildContext context)? onNew;

  const RealHomeScreen({super.key, this.onOpen, this.onNew});

  @override
  State<RealHomeScreen> createState() => _RealHomeScreenState();
}

class _RealHomeScreenState extends State<RealHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) RealScope.of(context).refreshJourneys();
    });
  }

  Future<void> _confirmLogout() async {
    final state = RealScope.of(context);
    final pending = state.pendingOperations.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('¿Cerrar sesión?'),
        content: Text(pending == 0
            ? 'Tu avance ya está guardado en Salud Digna. Podrás retomarlo al volver a entrar.'
            : 'Tienes $pending cambio(s) sin enviar. Si cierras sesión se descartan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true && mounted) RealScope.of(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = RealScope.of(context);
    final session = state.session;
    // Durante la transición de cierre de sesión la pantalla sigue montada un
    // instante sin sesión.
    if (session == null) return const SizedBox.shrink();
    final ws = context.windowSize;
    final account = session.account;
    final firstName = account.patient?.firstName.isNotEmpty == true
        ? account.patient!.firstName
        : session.displayName;
    final pending = state.pendingOperations.length;
    final loadingFirst = state.loadingJourneys && state.journeys.isEmpty;

    final blocks = <Widget>[
      IdentityCard.fromParts(displayName: session.displayName, detail: account.email),
      if (state.journeysError != null) ...[
        const SizedBox(height: Space.md),
        ErrorBanner(message: state.journeysError!, onRetry: state.refreshJourneys),
      ],
      const SectionTitle('Tus trámites', subtitle: 'Los que iniciaste en cualquier canal'),
      if (loadingFirst) ...[
        const SkeletonCard(height: 96),
        const SizedBox(height: Space.sm),
        const SkeletonCard(height: 96),
      ] else if (state.journeys.isNotEmpty)
        for (final j in state.journeys) ...[
          RealJourneyCard(
            journey: j,
            context: state.contexts[j.id],
            studies: state.studies,
            clinics: state.clinics,
            pending: state.pendingFor(j.id) != null,
            onTap: widget.onOpen == null ? null : () => widget.onOpen!(context, j),
          ),
          const SizedBox(height: Space.sm),
        ]
      else if (state.notLinked)
        const EmptyState(
          icon: Icons.link_off,
          title: 'Aún no tienes trámites vinculados',
          message: 'Cuando inicies un trámite en el sitio web, el Call Center o esta app '
              'con tu cuenta, aparecerá aquí para que lo continúes.',
        )
      else if (state.journeysError == null)
        const EmptyState(
          icon: Icons.task_alt,
          title: 'No tienes trámites activos',
          message: 'Los trámites que inicies en cualquier canal aparecerán aquí.',
        ),
      if (widget.onNew != null) ...[
        const SizedBox(height: Space.lg),
        FilledButton.tonalIcon(
          onPressed: () => widget.onNew!(context),
          icon: const Icon(Icons.add),
          label: const Text('Nueva cita'),
        ),
      ],
      const SizedBox(height: Space.lg),
    ];

    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        title: Text('Hola, $firstName'),
        actions: [
          if (pending > 0)
            IconButton(
              tooltip: 'Cambios sin enviar',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RealConnectionScreen()),
              ),
              icon: Badge(label: Text('$pending'), child: const Icon(Icons.cloud_upload_outlined)),
            ),
          IconButton(
            tooltip: 'Conexión',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RealConnectionScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: state.refreshJourneys,
          child: ListView(
            key: const PageStorageKey<String>('real-home'),
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.lg),
            children: blocks,
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de un trámite activo. Muestra solo lo que dio la API: estado,
/// paso, estudio y clínica (nombres del catálogo) y fecha de actualización.
class RealJourneyCard extends StatelessWidget {
  final JourneySummary journey;
  final JourneyContext? context;
  final Map<String, StudyItem> studies;
  final Map<String, ClinicItem> clinics;
  final bool pending;
  final VoidCallback? onTap;

  const RealJourneyCard({
    super.key,
    required this.journey,
    required this.context,
    required this.studies,
    required this.clinics,
    this.pending = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ctx = this.context;
    final studyId = ctx?.studyId;
    final clinicId = ctx?.clinicId;
    final study = studyId == null ? null : studies[studyId];
    final clinic = clinicId == null ? null : clinics[clinicId];
    final title = ctx == null
        ? 'Trámite de cita'
        : studyId == null
            ? 'Sin estudio elegido'
            : (study?.name ?? 'Estudio no disponible en el catálogo');

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
                title: Text(title, style: t.titleMedium),
                trailing: StatusChip(journey.status),
              ),
              const SizedBox(height: Space.xs),
              if (clinicId != null)
                Text(clinic?.name ?? 'Clínica no disponible en el catálogo',
                    style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
              if (ctx != null)
                Text('Paso: ${ApiJourneySteps.label(ctx.currentStep)}',
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
              const SizedBox(height: Space.xs),
              Text(
                'Folio ${shortJourneyId(journey.id)} · actualizado '
                '${formatRelative(journey.updatedAt).toLowerCase()}',
                style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
              ),
              if (pending) ...[
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 16, color: s.error),
                    const SizedBox(width: 4),
                    Text('Hay un cambio sin enviar',
                        style: t.bodySmall?.copyWith(color: s.error)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Primeros 8 caracteres del UUID: basta para reconocer el mismo trámite en
/// el sitio web o el Call Center.
String shortJourneyId(String id) => id.length > 8 ? id.substring(0, 8) : id;
