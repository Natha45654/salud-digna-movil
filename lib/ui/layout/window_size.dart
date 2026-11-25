import 'package:flutter/widgets.dart';

/// Clases de tamaño de ventana (Material 3) y medidas de layout de la app.
///
/// ÚNICO lugar donde viven los puntos de quiebre. Las pantallas preguntan
/// `context.windowSize` y deciden por el espacio disponible, nunca por la
/// orientación ni por el tipo de dispositivo.
///
/// | Clase           | Regla                     | Ejemplo                     |
/// |-----------------|---------------------------|-----------------------------|
/// | Ancho compacto  | < 600 dp                  | teléfono en vertical        |
/// | Ancho medio     | 600 a 839 dp              | tableta chica, plegable     |
/// | Ancho expandido | ≥ 840 dp                  | tableta, teléfono horizontal|
/// | Alto compacto   | < 480 dp                  | teléfono en horizontal      |
enum WindowWidthClass { compact, medium, expanded }

enum WindowHeightClass { compact, regular }

/// Medidas compartidas. Ninguna pantalla debe repetir estos números.
abstract final class LayoutTokens {
  // Puntos de quiebre (Material 3).
  static const double mediumMinWidth = 600;
  static const double expandedMinWidth = 840;
  static const double compactMaxHeight = 480;

  // Anchos máximos de columna (legibilidad).
  static const double contentMaxWidth = 640;
  static const double narrowContentMaxWidth = 520;
  static const double formMaxWidth = 440;

  // Panel lateral del layout de dos paneles.
  static const double sidePaneMinWidth = 300;
  static const double sidePaneMaxWidth = 340;
  static const double sidePaneFraction = 0.36;

  // Riel entre columnas (plegar panel, accesos) y animación del plegado.
  static const double railWidth = 56;
  static const Duration paneAnimation = Duration(milliseconds: 180);

  // Selectores (estudio, clínica, horario): alto máximo relativo a la ventana.
  static const double pickerMaxHeightFraction = 0.85;

  // Barra superior compacta cuando el alto es compacto.
  static const double compactToolbarHeight = 48;

  // Altura útil mínima (sin teclado) para mantener visible una barra fija.
  static const double keyboardMinUsefulHeight = 420;

  // Anchos mínimos, a escala de texto 1.0, para mostrar en una sola fila un
  // título con su chip de estado o con su insignia. Se multiplican por la
  // escala de texto del sistema.
  static const double inlineTrailingMinWidth = 260;
  static const double inlineBadgeMinWidth = 300;

  // Ancho de ventana mínimo, a escala 1.0, para mostrar como texto la acción
  // de una fila ("Elegir", "Cambiar"); por debajo se muestra como ícono.
  static const double inlineActionMinWidth = 360;
}

@immutable
class WindowSize {
  final Size size;
  const WindowSize(this.size);

  factory WindowSize.of(BuildContext context) => WindowSize(MediaQuery.sizeOf(context));

  WindowWidthClass get widthClass {
    if (size.width >= LayoutTokens.expandedMinWidth) return WindowWidthClass.expanded;
    if (size.width >= LayoutTokens.mediumMinWidth) return WindowWidthClass.medium;
    return WindowWidthClass.compact;
  }

  WindowHeightClass get heightClass => size.height < LayoutTokens.compactMaxHeight
      ? WindowHeightClass.compact
      : WindowHeightClass.regular;

  bool get isWidthCompact => widthClass == WindowWidthClass.compact;
  bool get isHeightCompact => heightClass == WindowHeightClass.compact;

  /// Dos paneles: hay ancho de sobra pero poca altura (teléfono horizontal).
  /// Así la acción principal queda visible sin desplazarse.
  bool get useTwoPane => isHeightCompact && !isWidthCompact;

  /// Ancho del panel lateral en el layout de dos paneles.
  double get sidePaneWidth => (size.width * LayoutTokens.sidePaneFraction)
      .clamp(LayoutTokens.sidePaneMinWidth, LayoutTokens.sidePaneMaxWidth);
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(this);
}
