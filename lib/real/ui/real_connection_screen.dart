import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/layout/adaptive.dart';
import '../../ui/layout/window_size.dart';
import '../../widgets/common.dart';
import '../real_state.dart';
import 'real_app.dart';

/// Conexión del modo real: a qué API apunta la app (solo lectura) y los
/// cambios que todavía no tienen respuesta del servidor.
class RealConnectionScreen extends StatelessWidget {
  const RealConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = RealScope.of(context);
    final config = RealScope.configOf(context);
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pending = state.pendingOperations;

    return Scaffold(
      appBar: ContentAppBar(
        compact: context.windowSize.isHeightCompact,
        title: const Text('Conexión'),
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl),
          children: [
            const SectionTitle('API central', subtitle: 'De dónde toma la app tus trámites'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('API central de Salud Digna'),
                    subtitle: Text('${config.baseUrl}/api/v1'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.info_outline, color: s.onSurfaceVariant),
                    subtitle: const Text(
                        'El modo y la URL se fijan al compilar (MOCK_MODE y '
                        'CHANNEL_BACKEND_URL) y no se cambian desde la app. La app '
                        'solo envía tu sesión de paciente; no guarda claves.'),
                  ),
                ],
              ),
            ),
            const SectionTitle('Cambios sin enviar',
                subtitle: 'Se reintentan con el mismo contenido: nunca se duplican'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      pending.isEmpty ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                      color: pending.isEmpty ? s.primary : s.error,
                    ),
                    title: Text(pending.isEmpty
                        ? 'Todo enviado'
                        : '${pending.length} cambio(s) sin enviar'),
                    subtitle: const Text(
                        'Se guardan solo mientras la app está abierta: si la cierras, '
                        'se pierden y hay que repetirlos.'),
                  ),
                  for (final op in pending) ...[
                    const Divider(),
                    PendingOperationTile(operation: op),
                  ],
                ],
              ),
            ),
            if (!state.isLoggedIn && pending.isEmpty) ...[
              const SizedBox(height: Space.md),
              Text(
                'Si tenías cambios sin enviar y tu sesión venció, inicia sesión con la '
                'misma cuenta para reenviarlos.',
                style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila de un cambio pendiente con "Reintentar" y "Descartar". También la usa
/// la pantalla del trámite.
class PendingOperationTile extends StatefulWidget {
  final PendingOperation operation;

  /// Tras un reintento terminado (con cualquier resultado).
  final VoidCallback? onFinished;

  const PendingOperationTile({super.key, required this.operation, this.onFinished});

  @override
  State<PendingOperationTile> createState() => _PendingOperationTileState();
}

class _PendingOperationTileState extends State<PendingOperationTile> {
  bool _busy = false;

  Future<void> _retry() async {
    final state = RealScope.of(context);
    setState(() => _busy = true);
    final r = await state.retryPending(widget.operation);
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(
      context,
      switch (r.status) {
        WriteStatus.done => 'Cambio enviado',
        WriteStatus.conflict => r.message ?? 'El trámite cambió desde otro canal.',
        _ => r.message ?? 'No se pudo enviar todavía.',
      },
      error: r.status != WriteStatus.done,
    );
    widget.onFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.operation;
    final t = Theme.of(context).textTheme;
    final detail = [
      'Intentos: ${op.attempts}',
      ?op.lastError,
      if (op.notBefore != null) 'Reintentar después de ${formatRelative(op.notBefore!).toLowerCase()}',
    ].join('\n');
    return ListTile(
      leading: const Icon(Icons.schedule_send_outlined),
      title: Text(op.label),
      subtitle: Text(detail, style: t.bodySmall),
      isThreeLine: op.lastError != null,
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Descartar',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : () => RealScope.of(context).discardPending(op),
          ),
          IconButton(
            tooltip: 'Reintentar',
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _busy ? null : _retry,
          ),
        ],
      ),
    );
  }
}
