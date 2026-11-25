import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../ui/layout/adaptive.dart';
import '../ui/layout/window_size.dart';
import '../widgets/common.dart';
import '../widgets/patient_blocks.dart';
import 'journey_screen.dart';
import 'new_journey_screen.dart';
import 'settings_screen.dart';

/// Inicio: trámites del paciente de la sesión verificada (GET /me/journeys).
///
/// UX: tarjeta del paciente, "Tus citas", "Nueva cita" y "Retomar trámite de
/// otro canal", en ese orden. Los trámites pendientes no se listan aquí: se
/// abren desde "Retomar"; los errores no bloquean la pantalla.
///
/// Layout: una columna cuando hay altura; dos paneles cuando la altura es
/// compacta (teléfono horizontal): identidad y acciones secundarias a la
/// izquierda, trámites a la derecha. En ningún tamaño hay botón flotante:
/// "Nueva cita" es un botón normal junto a "Retomar", para que nada tape
/// contenido ni otra acción.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppScope.of(context).refreshJourneys();
    });
  }

  Future<void> _open(Journey j) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JourneyScreen(journeyId: j.journeyId)),
    );
    if (mounted) AppScope.of(context).refreshJourneys();
  }

  /// Continuar un trámite pendiente: abre el paso exacto donde quedó, con sus
  /// datos cargados, y registra la reanudación (y el cambio de canal).
  Future<void> _resume(Journey j) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JourneyScreen(journeyId: j.journeyId, resume: true),
      ),
    );
    if (mounted) AppScope.of(context).refreshJourneys();
  }

  Future<void> _startNew() async {
    final journeyId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const NewJourneyScreen()),
    );
    if (!mounted) return;
    if (journeyId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => JourneyScreen(journeyId: journeyId)),
      );
    }
    if (mounted) AppScope.of(context).refreshJourneys();
  }

  /// "Retomar trámite de otro canal": ventana deslizable con todos los
  /// trámites pendientes del paciente, del más reciente al más antiguo. No
  /// pide código: la identidad está verificada en esta sesión y el servidor
  /// filtra por el paciente de la sesión.
  Future<void> _showPending() async {
    final chosen = await showAdaptiveSlideSheet<Journey>(
      context: context,
      title: 'Trámites pendientes',
      builder: (ctx) => _PendingJourneysView(
        onChoose: (j) => Navigator.of(ctx).pop(j),
      ),
    );
    if (chosen != null && mounted) await _resume(chosen);
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tu avance queda guardado. Podrás retomarlo al volver a identificarte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true && mounted) await AppScope.of(context).logout();
  }

  Widget _outboxButton(AppState state) => AnimatedBuilder(
        animation: state.outbox,
        builder: (_, _) => state.outbox.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Eventos pendientes de envío',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: Badge(
                  label: Text('${state.outbox.length}'),
                  child: const Icon(Icons.cloud_upload_outlined),
                ),
              ),
      );

  Widget _settingsButton() => IconButton(
        tooltip: 'Conexión',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      );

  Widget _logoutButton() => IconButton(
        tooltip: 'Cerrar sesión',
        icon: const Icon(Icons.logout),
        onPressed: _confirmLogout,
      );

  List<Widget> _barActions(AppState state) =>
      [_outboxButton(state), _settingsButton(), _logoutButton()];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = Theme.of(context).colorScheme;
    // Durante la transición de cierre de sesión la pantalla sigue montada un
    // instante sin sesión: no dibujar nada en ese caso.
    final session = state.session;
    if (session == null) return const SizedBox.shrink();
    final ws = context.windowSize;
    final closed = state.journeys.where((j) => !JourneyStatus.isOpen(j.status)).toList();
    final firstName = session.displayName.split(' ').first;
    final loadingFirst = state.loadingJourneys && state.journeys.isEmpty;

    // Bloques de citas: los mismos en ambos layouts. En dos columnas el
    // título "Tus citas" va en la fila superior fija, junto a los accesos;
    // aquí se omite para no repetirlo.
    final twoPane = ws.useTwoPane;
    final journeyBlocks = <Widget>[
      if (state.lastError != null) ...[
        const SizedBox(height: Space.md),
        ErrorBanner(message: state.lastError!, onRetry: state.refreshJourneys),
      ],
      if (!twoPane) const SectionTitle('Tus citas'),
      if (loadingFirst) ...[
        const SkeletonCard(height: 84),
        const SizedBox(height: Space.sm),
        const SkeletonCard(height: 84),
      ] else if (closed.isNotEmpty)
        AppointmentsList(journeys: closed, onOpen: _open)
      else if (state.lastError == null)
        // "Nueva cita" va justo debajo: el estado vacío no repite la acción.
        const EmptyState(
          icon: Icons.event_available_outlined,
          title: 'Aún no tienes citas confirmadas',
          message: 'Cuando confirmes una cita, la verás aquí.',
        ),
    ];
    final tagline = Center(
      child: Text(
        'Un paciente, una sola conversación.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
      ),
    );
    // Misma clave en ambos layouts: al girar se conserva la posición de scroll.
    const listKey = PageStorageKey<String>('home-journeys');

    if (ws.useTwoPane) {
      return Scaffold(
        body: CollapsibleTwoPane(
          collapsed: state.homeSidePaneCollapsed,
          onCollapsedChanged: state.setHomeSidePaneCollapsed,
          side: _HomeSidePane(
            session: session,
            onNew: _startNew,
            onShowPending: _showPending,
          ),
          // Área principal: fila superior fija (título y accesos en la esquina
          // superior derecha) y, debajo, la lista con ancho máximo de lectura.
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MainPaneHeader(
                // Una línea: la fila no cambia de alto al abrir o cerrar el
                // panel, así que los accesos y la lista no se mueven.
                title: const SectionTitle('Tus citas', maxLines: 1),
                actions: _barActions(state),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: LayoutTokens.contentMaxWidth),
                    child: RefreshIndicator(
                      onRefresh: state.refreshJourneys,
                      child: ListView(
                        key: listKey,
                        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
                        children: [
                          ...journeyBlocks,
                          const SizedBox(height: Space.lg),
                          tagline,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        title: Text('Hola, $firstName'),
        actions: _barActions(state),
      ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: state.refreshJourneys,
          child: ListView(
            key: listKey,
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.lg),
            children: [
              IdentityCard(session: session),
              ...journeyBlocks,
              const SizedBox(height: Space.lg),
              _SecondaryActions(onNew: _startNew, onShowPending: _showPending),
              const SizedBox(height: Space.md),
              tagline,
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel lateral de Inicio en dos columnas: cabecera solo con el logotipo,
/// identidad compacta y acciones secundarias. Los accesos (conexión, cerrar
/// sesión) viven en la esquina superior derecha del área principal.
class _HomeSidePane extends StatelessWidget {
  final PatientSession session;
  final VoidCallback onNew;
  final VoidCallback onShowPending;
  const _HomeSidePane({
    required this.session,
    required this.onNew,
    required this.onShowPending,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('home-side'),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.md),
      children: [
        // Cabecera: únicamente el logotipo, sin deformarse.
        const Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(fit: BoxFit.scaleDown, child: BrandLogo(height: 48)),
        ),
        const SizedBox(height: Space.md),
        IdentityCard(session: session, compact: true),
        const SizedBox(height: Space.md),
        _SecondaryActions(onNew: onNew, onShowPending: onShowPending),
      ],
    );
  }
}

/// Acciones de Inicio: "Nueva cita" (tonal) y "Retomar trámite de otro
/// canal" (delineado), siempre visibles. "Retomar" abre la lista de trámites
/// pendientes, que lo explica cuando no hay ninguno.
class _SecondaryActions extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onShowPending;
  const _SecondaryActions({required this.onNew, required this.onShowPending});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: onNew,
          icon: const Icon(Icons.add),
          label: const Text('Nueva cita'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: onShowPending,
          icon: const Icon(Icons.link),
          label: const Text('Retomar trámite de otro canal'),
        ),
      ],
    );
  }
}

/// Lista de trámites pendientes de "Retomar". Al abrirse vuelve a pedirlos
/// (GET /me/journeys, por la sesión) y muestra cargando, error de red con
/// reintento o "sin trámites pendientes". Mismas tarjetas que antes.
class _PendingJourneysView extends StatefulWidget {
  final ValueChanged<Journey> onChoose;
  const _PendingJourneysView({required this.onChoose});

  @override
  State<_PendingJourneysView> createState() => _PendingJourneysViewState();
}

class _PendingJourneysViewState extends State<_PendingJourneysView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).refreshJourneys();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pending = state.pendingJourneys;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
      children: [
        if (state.loadingJourneys) ...[
          const SkeletonCard(height: 160),
          const SizedBox(height: Space.sm + 4),
          const SkeletonCard(height: 160),
        ] else ...[
          if (state.lastError != null) ...[
            ErrorBanner(message: state.lastError!, onRetry: state.refreshJourneys),
            const SizedBox(height: Space.sm + 4),
          ],
          if (pending.isEmpty && state.lastError == null)
            const EmptyState(
              icon: Icons.task_alt,
              title: 'No tienes trámites pendientes',
              message: 'Si inicias una cita por WhatsApp, en el sitio web o en el '
                  'Call Center, aparecerá aquí para que la continúes.',
            ),
          for (final j in pending) ...[
            PendingJourneyCard(journey: j, onTap: () => widget.onChoose(j)),
            const SizedBox(height: Space.sm + 4),
          ],
        ],
      ],
    );
  }
}
