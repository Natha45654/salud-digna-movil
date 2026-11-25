import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../ui/layout/adaptive.dart';
import '../ui/layout/window_size.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

/// Conexión con el orquestador y herramientas de demostración.
///
/// UX: lo que el jurado necesita tocar (simular caída, reenviar, restablecer)
/// está arriba y con texto claro; lo técnico queda plegado al final.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cfg = state.config;
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: ContentAppBar(
        compact: context.windowSize.isHeightCompact,
        title: const Text('Conexión y demo'),
      ),
      body: ResponsiveBody(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl),
        children: [
          const SectionTitle('Conexión', subtitle: 'De dónde toma la app tus trámites'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(cfg.mockMode ? Icons.memory_outlined : Icons.cloud_outlined),
                  title: Text(cfg.mockMode ? 'Orquestador simulado' : 'API central de Salud Digna'),
                  subtitle: Text(cfg.mockMode
                      ? 'Corre dentro de la app, sin red, con pacientes y trámites de prueba.'
                      : cfg.baseUrl),
                ),
                if (!cfg.mockMode && cfg.baseUrlError != null) ...[
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.error_outline, color: s.error),
                    title: Text(cfg.baseUrlError!, style: TextStyle(color: s.error)),
                  ),
                ],
                const Divider(),
                ListTile(
                  leading: Icon(Icons.info_outline, color: s.onSurfaceVariant),
                  subtitle: const Text(
                      'El modo y la URL se fijan al compilar (MOCK_MODE y '
                      'CHANNEL_BACKEND_URL en .env) y no se cambian desde la app. '
                      'Para cambiar de entorno, instala el APK compilado para ese entorno.'),
                ),
              ],
            ),
          ),

          const SectionTitle('Contacto', subtitle: 'Adónde lleva "¿Necesitas ayuda?" por WhatsApp'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: const Icon(Icons.chat_outlined),
              title: const Text('Ayuda por WhatsApp en el simulador'),
              subtitle: const Text(
                  'Para la demo: abre WhatsApp Sim con el mensaje listo en lugar del '
                  'WhatsApp real. Requiere tener instalado WhatsApp Sim.'),
              value: cfg.whatsappSimulator,
              onChanged: (v) => cfg.update(whatsappSimulator: v),
            ),
          ),

          if (cfg.mockMode) ...[
          const SectionTitle('Pruebas de resiliencia',
              subtitle: 'Para demostrar que nada se pierde si el orquestador falla'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (cfg.mockMode)
                  SwitchListTile(
                    secondary: Icon(Icons.cloud_off_outlined,
                        color: cfg.mockFailures ? s.error : null),
                    title: const Text('Simular caída del orquestador'),
                    subtitle: const Text(
                        'Las llamadas fallan; los eventos se guardan en el outbox.'),
                    value: cfg.mockFailures,
                    onChanged: (v) => cfg.update(mockFailures: v),
                  ),
                if (cfg.mockMode) const Divider(),
                AnimatedBuilder(
                  animation: state.outbox,
                  builder: (_, _) {
                    final entries = state.outbox.entries;
                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            entries.isEmpty ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                            color: entries.isEmpty ? s.primary : s.error,
                          ),
                          title: Text(entries.isEmpty
                              ? 'Todo entregado'
                              : '${entries.length} evento(s) sin entregar'),
                          subtitle: const Text(
                              'Los eventos se guardan en el dispositivo antes de enviarse. '
                              'Reintentar nunca duplica.'),
                        ),
                        if (entries.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm + 4),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                icon: const Icon(Icons.send_outlined),
                                onPressed: state.outbox.flushing
                                    ? null
                                    : () async {
                                        final n = await state.retryOutbox();
                                        if (!context.mounted) return;
                                        final rejected = state.outbox.lastRejections;
                                        if (rejected.any((e) => e.isSlotUnavailable)) {
                                          // El horario se ocupó mientras no había conexión:
                                          // no se confirmó. El paciente debe elegir otro.
                                          showSnack(context,
                                              '${OrchestratorException.slotUnavailableMessage}. '
                                              'Abre tu trámite y elige otro horario.',
                                              error: true);
                                        } else if (rejected.isNotEmpty) {
                                          showSnack(context, rejected.first.message, error: true);
                                        } else {
                                          showSnack(context,
                                              n == 0 ? 'Sigue sin conexión' : '$n evento(s) entregado(s)',
                                              error: n == 0);
                                        }
                                      },
                                label: const Text('Reenviar'),
                              ),
                            ),
                          ),
                        for (final e in entries) ...[
                          const Divider(),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.schedule_send_outlined),
                            title: Text(EventTypes.label(e.event.eventType)),
                            subtitle: Text(
                              'Intentos: ${e.attempts}${e.lastError != null ? '\n${e.lastError}' : ''}',
                              style: t.bodySmall,
                            ),
                            isThreeLine: e.lastError != null,
                            trailing: IconButton(
                              tooltip: 'Descartar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => state.outbox.discard(e),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          ],

          if (cfg.mockMode) ...[
            const SectionTitle('Escenario de demostración'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Restablecer escenario de Ana'),
                subtitle: const Text(
                    'Vuelve a dejar el trámite de Ana como lo dejó en WhatsApp, '
                    'pendiente de confirmar, y vacía el outbox.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await state.resetDemo();
                  if (context.mounted) showSnack(context, 'Escenario restablecido');
                },
              ),
            ),
          ],

          const SizedBox(height: Space.lg),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: Space.xs),
              leading: Icon(Icons.code, color: s.onSurfaceVariant),
              title: Text('Información técnica', style: t.labelLarge),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.sm),
                  child: Text(
                    cfg.mockMode
                        ? 'Canal: ${Channels.mobileApp}. Modo simulado: el orquestador corre '
                            'en el dispositivo y no se conecta a ningún servidor.'
                        : 'Canal: demo-mobile. API central: ${cfg.baseUrl}/api/v1 '
                            '(POST /auth/login, GET /auth/me, /mobile/journeys, /studies, '
                            '/clinics). La app solo envía el JWT del paciente.',
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (!state.isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                ),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver a identificarme'),
              ),
            ),
        ],
        ),
      ),
    );
  }
}
