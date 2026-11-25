import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../ui/layout/adaptive.dart';
import '../ui/layout/window_size.dart';
import '../widgets/common.dart';

/// Inicio de un trámite desde la app (JOURNEY_STARTED con origen MOBILE_APP).
///
/// UX: antes de crear nada, el paciente ve qué le vamos a pedir y la promesa
/// de continuidad. Un solo botón, dentro del área segura.
class NewJourneyScreen extends StatefulWidget {
  const NewJourneyScreen({super.key});

  @override
  State<NewJourneyScreen> createState() => _NewJourneyScreenState();
}

class _NewJourneyScreenState extends State<NewJourneyScreen> {
  bool _busy = false;

  Future<void> _start() async {
    final state = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final ack = await state.sendEvent(state.buildEvent(
        eventType: EventTypes.journeyStarted,
        data: const {'journeyType': 'APPOINTMENT_BOOKING'},
      ));
      if (!mounted) return;
      if (ack == null) {
        showSnack(context,
            'Sin conexión: el inicio del trámite quedó en cola y se reenviará',
            error: true);
        Navigator.pop(context);
        return;
      }
      // Devolver el id al inicio, que abre el detalle y refresca al volver.
      Navigator.pop(context, ack.journeyId);
    } on OrchestratorException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ws = context.windowSize;
    final intro = <Widget>[
      Text('Agenda un estudio', style: t.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: Space.sm),
      Text(
        'Te tomará menos de un minuto.',
        textAlign: TextAlign.center,
        style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
      ),
    ];
    const steps = <Widget>[
      _StepPreview(number: 1, icon: Icons.biotech_outlined, title: 'Elige tu estudio'),
      _StepPreview(number: 2, icon: Icons.local_hospital_outlined, title: 'Elige tu clínica'),
      _StepPreview(number: 3, icon: Icons.schedule, title: 'Elige un horario'),
      _StepPreview(number: 4, icon: Icons.check_circle_outline, title: 'Confirma tu cita', last: true),
    ];
    final continuity = Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: s.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_outlined, color: s.primary),
          const SizedBox(width: Space.sm + 4),
          Expanded(
            child: Text(
              'Puede quedar pendiente: tu avance se guarda y puedes continuar '
              'por WhatsApp, en el sitio web o en el Call Center.',
              style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
    final start = FilledButton.icon(
      onPressed: _busy ? null : _start,
      icon: _busy
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.play_arrow),
      label: const Text('Comenzar'),
    );

    // Dos paneles (alto compacto): presentación y "Comenzar" a la izquierda,
    // siempre visible; los pasos a la derecha.
    if (ws.useTwoPane) {
      return Scaffold(
        appBar: ContentAppBar(
          compact: true,
          maxContentWidth: double.infinity,
          title: const Text('Nueva cita'),
        ),
        body: TwoPaneLayout(
          side: PaneWithPinnedAction(
            action: start,
            children: [...intro, const SizedBox(height: Space.lg), continuity],
          ),
          main: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
            children: steps,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        maxContentWidth: LayoutTokens.narrowContentMaxWidth,
        title: const Text('Nueva cita'),
      ),
      body: ResponsiveBody(
        maxWidth: LayoutTokens.narrowContentMaxWidth,
        safeBottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
          children: [
            // Con poca altura se omite el icono grande para dar espacio a los pasos.
            if (!ws.isHeightCompact) ...[
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: s.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.event_note_outlined, size: 44, color: s.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: Space.lg),
            ],
            ...intro,
            SizedBox(height: ws.isHeightCompact ? Space.lg : Space.xl),
            ...steps,
            const SizedBox(height: Space.lg),
            continuity,
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        maxWidth: LayoutTokens.narrowContentMaxWidth,
        child: start,
      ),
    );
  }
}

class _StepPreview extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final bool last;
  const _StepPreview({required this.number, required this.icon, required this.title, this.last = false});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: s.primary.withValues(alpha: 0.12),
                foregroundColor: s.primary,
                child: Icon(icon, size: 18),
              ),
              if (!last)
                Expanded(child: Container(width: 2, color: s.outlineVariant)),
            ],
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: last ? 0 : Space.md),
              child: Text('$number. $title', style: t.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}
