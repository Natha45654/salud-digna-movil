import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'window_size.dart';

/// Barra superior alineada a la retícula del contenido.
///
/// En pantallas anchas el título y las acciones quedan dentro de la misma
/// columna que el contenido (no pegados al borde de la pantalla). Con alto
/// compacto usa una barra más baja para no gastar altura.
class ContentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget> actions;
  final double maxContentWidth;
  final bool compact;

  const ContentAppBar({
    super.key,
    this.title,
    this.actions = const [],
    this.maxContentWidth = LayoutTokens.contentMaxWidth,
    this.compact = false,
  });

  double get _height => compact ? LayoutTokens.compactToolbarHeight : kToolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: _height,
      titleSpacing: 0,
      title: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.only(left: canPop ? Space.xs : Space.md, right: Space.xs),
            child: Row(
              children: [
                if (canPop) ...[
                  const BackButton(),
                  const SizedBox(width: Space.xs),
                ],
                Expanded(child: title ?? const SizedBox.shrink()),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dos paneles lado a lado: lateral de ancho fijo y principal flexible.
///
/// Respeta las áreas seguras de los cuatro lados: en horizontal, la barra de
/// navegación de tres botones y el recorte de la cámara quedan a los lados.
class TwoPaneLayout extends StatelessWidget {
  final Widget side;
  final Widget main;

  /// false cuando hay AppBar (ella ya respeta el borde superior).
  final bool safeTop;

  const TwoPaneLayout({
    super.key,
    required this.side,
    required this.main,
    this.safeTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = context.windowSize.sidePaneWidth;
    return SafeArea(
      top: safeTop,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: width, child: side),
          const VerticalDivider(width: 1),
          Expanded(child: main),
        ],
      ),
    );
  }
}

/// Contenido desplazable con una acción fija al pie, dentro de un panel.
///
/// La acción siempre se ve; el contenido de arriba se desplaza si no cabe.
class PaneWithPinnedAction extends StatelessWidget {
  final List<Widget> children;
  final Widget? action;
  final Key? scrollKey;
  final EdgeInsets padding;

  const PaneWithPinnedAction({
    super.key,
    required this.children,
    this.action,
    this.scrollKey,
    this.padding = const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(key: scrollKey, padding: padding, children: children),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
            child: action,
          ),
      ],
    );
  }
}

/// Dos columnas con la izquierda plegable.
///
/// - Panel abierto: no hay barra vertical. El control para cerrarlo está en el
///   borde derecho del propio panel, centrado verticalmente.
/// - Panel cerrado: aparece una barra vertical estrecha que contiene
///   únicamente el control para abrirlo, centrado verticalmente.
/// - El control expone su estado (expandido o no) y su nombre al lector de
///   pantalla, y se opera con teclado (Tab para enfocar, Enter o Espacio).
/// - La transición respeta la preferencia del sistema de reducir animaciones.
/// - Las columnas ocupan siempre las mismas posiciones en el árbol: abrir y
///   cerrar no recrea el contenido ni pierde la posición de desplazamiento.
class CollapsibleTwoPane extends StatelessWidget {
  final Widget side;
  final Widget main;
  final bool collapsed;
  final ValueChanged<bool> onCollapsedChanged;

  const CollapsibleTwoPane({
    super.key,
    required this.side,
    required this.main,
    required this.collapsed,
    required this.onCollapsedChanged,
  });

  static const railKey = ValueKey<String>('collapsible-two-pane-rail');
  static const paneKey = ValueKey<String>('collapsible-two-pane-side');

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final contentWidth = context.windowSize.sidePaneWidth;
    // El panel abierto incluye un margen derecho del mismo ancho que la barra,
    // donde vive su control de cierre: el ancho libre de la columna derecha es
    // el mismo con el panel abierto que con la barra visible a su lado.
    final paneWidth = contentWidth + LayoutTokens.railWidth;

    final pane = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: side),
        SizedBox(
          width: LayoutTokens.railWidth,
          child: Center(
            child: _PaneToggle(collapsed: false, onPressed: () => onCollapsedChanged(true)),
          ),
        ),
      ],
    );

    final rail = DecoratedBox(
      decoration: BoxDecoration(color: s.surfaceContainerLow),
      child: Center(
        child: _PaneToggle(collapsed: true, onPressed: () => onCollapsedChanged(false)),
      ),
    );

    // Áreas seguras en los cuatro lados: en horizontal, la barra de navegación
    // de Android y el recorte de la cámara quedan a los lados; el contenido
    // (incluidos los accesos de la esquina superior derecha) nunca queda
    // debajo de ellos.
    return SafeArea(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: collapsed ? 0 : 1),
        duration: reduceMotion ? Duration.zero : LayoutTokens.paneAnimation,
        curve: Curves.easeOutCubic,
        builder: (context, open, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Reveal(
                key: paneKey,
                width: paneWidth * open,
                fullWidth: paneWidth,
                alignment: Alignment.centerRight,
                active: !collapsed,
                child: pane,
              ),
              _Reveal(
                key: railKey,
                width: LayoutTokens.railWidth * (1 - open),
                fullWidth: LayoutTokens.railWidth,
                alignment: Alignment.centerLeft,
                active: collapsed,
                child: rail,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: main),
            ],
          );
        },
      ),
    );
  }
}

/// Muestra `child` a su ancho completo recortado a `width`. Inactivo, no recibe
/// foco ni lo anuncia el lector de pantalla; con ancho cero queda fuera de
/// pantalla (ni se pinta ni recibe toques).
class _Reveal extends StatelessWidget {
  final double width;
  final double fullWidth;
  final Alignment alignment;
  final bool active;
  final Widget child;
  const _Reveal({
    super.key,
    required this.width,
    required this.fullWidth,
    required this.alignment,
    required this.active,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: width,
        child: OverflowBox(
          alignment: alignment,
          minWidth: fullWidth,
          maxWidth: fullWidth,
          child: Offstage(
            offstage: width < 0.5,
            child: ExcludeFocus(
              excluding: !active,
              child: ExcludeSemantics(excluding: !active, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Control para mostrar u ocultar el panel lateral (48 dp, nombre accesible,
/// estado expandido y foco visible por el tema).
class _PaneToggle extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onPressed;
  const _PaneToggle({required this.collapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final label = collapsed ? 'Mostrar panel' : 'Ocultar panel';
    return Semantics(
      button: true,
      expanded: !collapsed,
      label: label,
      excludeSemantics: true,
      child: IconButton.filledTonal(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
        onPressed: onPressed,
      ),
    );
  }
}

/// Abre un selector sin sobreponerlo al contenido de forma desordenada:
/// - Una columna: hoja inferior con alto máximo y desplazamiento propio.
/// - Dos columnas (alto compacto): diálogo centrado, también con alto máximo.
Future<T?> showAdaptivePicker<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final ws = context.windowSize;
  final maxHeight = ws.size.height * LayoutTokens.pickerMaxHeightFraction;
  if (ws.useTwoPane) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: LayoutTokens.narrowContentMaxWidth,
            maxHeight: maxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: builder(ctx),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: builder,
  );
}

/// Fila superior del área de contenido principal: título de la sección a la
/// izquierda (alineado a la columna de lectura) y accesos a la derecha.
///
/// Los accesos se anclan al borde derecho del área principal, que no se mueve
/// al abrir o cerrar el panel lateral: conservan posición y tamaño. El área
/// segura derecha la aplica el contenedor de dos columnas.
class MainPaneHeader extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final double maxContentWidth;
  const MainPaneHeader({
    super.key,
    required this.title,
    required this.actions,
    this.maxContentWidth = LayoutTokens.contentMaxWidth,
  });

  static const actionsKey = ValueKey<String>('main-pane-header-actions');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // El título sigue la misma columna centrada que la lista de debajo,
        // con su mismo margen lateral, esté el panel abierto o cerrado.
        final width = c.maxWidth;
        final column = math.min(width, maxContentWidth);
        final side = (width - column) / 2;
        // Si la columna llega bajo los accesos, el título se detiene antes.
        final reserved = kMinInteractiveDimension * actions.length + Space.sm;
        final overlap = math.max(0.0, side + column - (width - reserved));
        return Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: side + Space.md,
                right: side + Space.md + overlap,
              ),
              child: title,
            ),
            // Accesos anclados al borde derecho del área principal.
            Positioned(
              top: 0,
              bottom: 0,
              right: Space.sm,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Row(key: actionsKey, mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Ventana deslizable responsiva:
/// - Una columna (ancho compacto): sube desde abajo como hoja inferior.
/// - Pantallas anchas: entra desde la derecha como panel lateral.
/// Respeta la preferencia del sistema de reducir animaciones.
Future<T?> showAdaptiveSlideSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  final ws = context.windowSize;
  final maxHeight = ws.size.height * LayoutTokens.pickerMaxHeightFraction;
  Widget sheet(BuildContext ctx) => _SlideSheet(title: title, child: builder(ctx));

  if (ws.isWidthCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: maxHeight),
      builder: sheet,
    );
  }
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    transitionDuration: reduceMotion ? Duration.zero : LayoutTokens.paneAnimation,
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        left: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(LayoutTokens.formMaxWidth, ws.size.width),
          ),
          child: Material(
            color: Theme.of(ctx).colorScheme.surface,
            child: SizedBox(height: double.infinity, child: sheet(ctx)),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(animation),
      child: child,
    ),
  );
}

class _SlideSheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _SlideSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
          child: Row(
            children: [
              Expanded(child: Text(title, style: t.titleLarge)),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}
