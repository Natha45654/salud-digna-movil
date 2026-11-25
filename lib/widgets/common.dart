import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../ui/layout/window_size.dart';
import '../models/models.dart';

// ----------------------------------------------------------------- formato

String formatDateTime(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

/// "Hoy 10:00", "Mañana 10:00" o fecha completa: más natural para el paciente.
String formatRelative(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(l.year, l.month, l.day);
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(l.hour)}:${two(l.minute)}';
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Hoy, $time';
  if (diff == 1) return 'Mañana, $time';
  if (diff == -1) return 'Ayer, $time';
  return formatDateTime(d);
}

/// Forma corta para resúmenes: "hoy 15:49", "ayer 21:28", "24 nov 15:49".
String formatShortRelative(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  final diff = DateTime(l.year, l.month, l.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(l.hour)}:${two(l.minute)}';
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return switch (diff) {
    0 => 'hoy $time',
    -1 => 'ayer $time',
    1 => 'mañana $time',
    _ => '${l.day} ${months[l.month - 1]} $time',
  };
}

/// Etiqueta de día para elegir horario: "Hoy", "Mañana" o "mié 26 nov".
String formatDayLabel(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  final diff = DateTime(l.year, l.month, l.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${days[l.weekday - 1]} ${l.day} ${months[l.month - 1]}';
}

String formatMoney(num v) => v == 0 ? 'Sin costo' : '\$${v.toStringAsFixed(0)} MXN';

IconData channelIcon(String code) => switch (code) {
      Channels.web => Icons.language,
      Channels.mobileApp => Icons.phone_android,
      Channels.whatsapp => Icons.chat_bubble_outline,
      Channels.callCenter => Icons.support_agent,
      Channels.clinic => Icons.local_hospital_outlined,
      'APPOINTMENT_SYSTEM' => Icons.verified_outlined,
      _ => Icons.device_unknown,
    };

String channelLabel(String code) =>
    code == 'APPOINTMENT_SYSTEM' ? 'Sistema de citas' : Channels.label(code);

Color statusColor(BuildContext context, String status) {
  final s = Theme.of(context).colorScheme;
  return switch (status) {
    JourneyStatus.confirmado => s.primary,
    JourneyStatus.cancelado => s.error,
    JourneyStatus.pendienteConfirmacion => s.tertiary,
    _ => s.secondary,
  };
}

/// Etiqueta centrada en el paciente, no en el sistema.
String statusHuman(String status) => switch (status) {
      JourneyStatus.iniciado => 'Recién iniciado',
      JourneyStatus.enCaptura => 'En progreso',
      JourneyStatus.pendienteConfirmacion => 'Lista para confirmar',
      JourneyStatus.confirmado => 'Confirmada',
      JourneyStatus.cancelado => 'Cancelada',
      _ => JourneyStatus.label(status),
    };

// --------------------------------------------------------------- feedback

void showSnack(BuildContext context, String message, {bool error = false}) {
  final s = Theme.of(context).colorScheme;
  HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? s.onError : s.onInverseSurface, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: error ? s.error : null,
    ));
}

// ---------------------------------------------------------------- widgets

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(context, status);
    return Semantics(
      label: 'Estado: ${statusHuman(status)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          statusHuman(status),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }
}

class ChannelChip extends StatelessWidget {
  final String channel;
  const ChannelChip(this.channel, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(channelIcon(channel), size: 14, color: s.onSecondaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(channelLabel(channel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: s.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final String? subtitle;
  final Widget? trailing;

  /// Límite de líneas del título (null: sin límite, como siempre). Con límite,
  /// el sobrante se corta con puntos suspensivos; el estilo no cambia.
  final int? maxLines;
  const SectionTitle(this.text, {super.key, this.subtitle, this.trailing, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: t.titleMedium,
                  maxLines: maxLines,
                  overflow: maxLines == null ? null : TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Indicador de progreso del trámite: el paciente siempre sabe en qué paso va.
class StepProgress extends StatelessWidget {
  final List<String> steps;
  final int completed; // pasos completados (0..steps.length)
  final bool done; // trámite cerrado con éxito
  const StepProgress({
    super.key,
    required this.steps,
    required this.completed,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: done
          ? 'Trámite completado'
          : 'Paso ${(completed + 1).clamp(1, steps.length)} de ${steps.length}',
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: (done || i < completed)
                          ? s.primary
                          : i == completed
                              ? s.primary.withValues(alpha: 0.35)
                              : s.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      steps[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: t.labelSmall?.copyWith(
                        color: (done || i <= completed)
                            ? s.onSurface
                            : s.onSurfaceVariant,
                        fontWeight:
                            (!done && i == completed) ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < steps.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Estado vacío con icono, título, texto y acción.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xl),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: s.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: s.onPrimaryContainer),
          ),
          const SizedBox(height: Space.md),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(message,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
          if (action != null) ...[
            const SizedBox(height: Space.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Banner de error no bloqueante con acción de reintento.
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorBanner({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
      decoration: BoxDecoration(
        color: s.errorContainer,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_outlined, color: s.onErrorContainer),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: s.onErrorContainer)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Placeholder de carga con forma de tarjeta (evita saltos de layout).
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: s.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    );
  }
}

/// Columna de contenido centrada, con ancho máximo y áreas seguras.
///
/// Es el layout de una columna (ancho compacto, o tableta con alto normal).
/// `safeBottom` en false cuando la pantalla tiene barra fija al pie, que ya
/// respeta el borde inferior.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool safeBottom;
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = LayoutTokens.contentMaxWidth,
    this.safeBottom = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: safeBottom,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          // Expandir al hijo: las listas y pilas necesitan alto acotado.
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }
}

/// Factor de escala de texto del sistema (1.0 = 100 %).
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1);

/// Título con un elemento a la derecha (chip de estado, insignia).
///
/// En fila cuando cabe; si el ancho disponible es poco para la escala de texto
/// actual (teléfono angosto o letra grande), el elemento baja debajo del
/// título. El elemento lateral nunca ocupa más del 45 % del ancho en fila.
class AdaptiveHeader extends StatelessWidget {
  final Widget title;
  final Widget trailing;

  /// Ancho mínimo, a escala 1.0, para mostrar título y elemento en una fila.
  final double minRowWidth;
  const AdaptiveHeader({
    super.key,
    required this.title,
    required this.trailing,
    this.minRowWidth = LayoutTokens.inlineTrailingMinWidth,
  });

  @override
  Widget build(BuildContext context) {
    final scale = textScaleOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < minRowWidth * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              const SizedBox(height: Space.sm),
              trailing,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: Space.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
              child: trailing,
            ),
          ],
        );
      },
    );
  }
}

/// Barra con la acción principal fija al pie.
///
/// - Respeta la barra de navegación del sistema (SafeArea inferior).
/// - Sube junto con el teclado para no quedar debajo de él.
/// - Si el teclado deja poca altura útil (típico en horizontal), se oculta
///   mientras se escribe para no tapar los campos; reaparece al cerrarlo.
/// - En pantallas anchas se centra con el mismo ancho máximo del contenido.
class BottomActionBar extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const BottomActionBar({
    super.key,
    required this.child,
    this.maxWidth = LayoutTokens.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    if (keyboard > 0 && mq.size.height - keyboard < LayoutTokens.keyboardMinUsefulHeight) {
      return const SizedBox.shrink();
    }
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: s.surface,
          border: Border(top: BorderSide(color: s.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.sm + 4, Space.md, Space.sm + 4),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nombre corto de clínica para listas: quita el prefijo "Salud Digna".
/// Solo presentación; el dato original no cambia.
String shortClinicName(String name) {
  final short = name.replaceFirst(RegExp(r'^\s*Salud\s+Digna\s+', caseSensitive: false), '');
  return short.isEmpty ? name : short;
}

/// Logotipo oficial (assets/logo/salud_digna.png). En modo oscuro se coloca
/// sobre una placa clara para conservar el gris de "Digna" legible.
class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 40});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final img = Image.asset(
      'assets/logo/salud_digna.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'Salud Digna. La salud es para todos',
    );
    if (!dark) return img;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: img,
    );
  }
}
