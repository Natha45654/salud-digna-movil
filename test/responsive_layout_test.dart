import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/core/theme.dart';
import 'package:salud_digna_movil/widgets/common.dart';
import 'package:salud_digna_movil/widgets/patient_blocks.dart';
import 'package:salud_digna_movil/main.dart';
import 'package:salud_digna_movil/models/models.dart';
import 'package:salud_digna_movil/screens/journey_screen.dart';
import 'package:salud_digna_movil/screens/login_screen.dart';
import 'package:salud_digna_movil/ui/layout/adaptive.dart';
import 'package:salud_digna_movil/screens/new_journey_screen.dart';
import 'package:salud_digna_movil/screens/settings_screen.dart';
import 'package:salud_digna_movil/state/app_state.dart';

/// Diseño adaptable: cada pantalla en tamaños lógicos de teléfono (vertical y
/// horizontal), tableta y escritorio. Falla ante cualquier desborde.
/// En 915x412 (teléfono horizontal) verifica además que la acción principal
/// se ve completa, que no hay botón flotante y que no hay controles encimados.
void main() {
  const sizes = <(String, Size, double)>[
    ('360x800', Size(360, 800), 1.0),
    ('412x915', Size(412, 915), 1.0),
    ('800x360', Size(800, 360), 1.0),
    ('915x412', Size(915, 412), 1.0),
    ('600x960', Size(600, 960), 1.0),
    ('1280x800', Size(1280, 800), 1.0),
    ('915x412 letra 130 %', Size(915, 412), 1.3),
  ];

  Future<AppState> newState(WidgetTester tester, {bool loggedIn = true, bool confirmed = false}) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState(await AppConfig.load());
      await state.init();
      if (loggedIn) {
        await state.login(
          identifiers: const [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456')],
          otp: '123456',
        );
      }
      if (confirmed) {
        await state.sendEvent(state.buildEvent(
          eventType: EventTypes.confirmationRequested,
          journeyId: 'ATN-2026-001',
        ));
        await state.refreshJourneys();
      }
    });
    return state;
  }

  Widget wrap(AppState state, Widget home) => AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: home,
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
  }

  void setView(WidgetTester tester, Size size, double scale) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  Rect screenRect(WidgetTester tester) =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  /// La acción está completa dentro de la pantalla y de su área desplazable
  /// (es decir, se ve sin desplazarse).
  void expectFullyVisible(WidgetTester tester, Finder action) {
    final rect = tester.getRect(action);
    final screen = screenRect(tester);
    expect(screen.intersect(rect), rect, reason: 'la acción se sale de la pantalla: $rect');
    final viewport = find.ancestor(of: action, matching: find.byType(Scrollable));
    if (viewport.evaluate().isNotEmpty) {
      final area = tester.getRect(viewport.first);
      expect(area.intersect(rect), rect, reason: 'la acción queda cortada por el área desplazable');
    }
  }

  /// Ningún control interactivo visible se encima sobre otro (se ignoran los
  /// que están anidados, como el botón dentro de una tarjeta tocable).
  void expectNoInteractiveOverlap(WidgetTester tester) {
    final screen = screenRect(tester);
    final elements = find
        .byWidgetPredicate((w) =>
            w is ButtonStyleButton ||
            w is IconButton ||
            w is FloatingActionButton ||
            w is InkWell ||
            w is PopupMenuButton)
        .evaluate()
        .toList();
    final items = <(Element, Rect)>[];
    for (final e in elements) {
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final visible = (ro.localToGlobal(Offset.zero) & ro.size).intersect(screen);
      if (visible.width <= 1 || visible.height <= 1) continue;
      items.add((e, visible));
    }
    bool isAncestor(Element ancestor, Element child) {
      var found = false;
      child.visitAncestorElements((x) {
        if (identical(x, ancestor)) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final (a, ra) = items[i];
        final (b, rb) = items[j];
        if (isAncestor(a, b) || isAncestor(b, a)) continue;
        final overlap = ra.intersect(rb);
        if (overlap.width > 1 && overlap.height > 1) {
          fail('Controles encimados: ${a.widget.runtimeType} $ra y ${b.widget.runtimeType} $rb');
        }
      }
    }
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'Acceso': (tester) async {
      final state = await newState(tester, loggedIn: false);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.text('Identifícate'), findsOneWidget);
    },
    'Inicio': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.text('Tus citas'), findsOneWidget);
      expect(find.text('Continúa donde te quedaste'), findsNothing);
      // En ningún tamaño hay botón flotante ni controles encimados.
      expect(find.byType(FloatingActionButton), findsNothing);
      expectNoInteractiveOverlap(tester);
    },
    'Inicio con citas': (tester) async {
      final state = await newState(tester, confirmed: true);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.text('Tus citas'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expectNoInteractiveOverlap(tester);
    },
    'Detalle pendiente': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      expect(find.text('Confirma tu cita'), findsOneWidget);
    },
    'Detalle confirmado': (tester) async {
      final state = await newState(tester, confirmed: true);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      expect(find.text('Confirmada'), findsWidgets);
    },
    'Nueva cita': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const NewJourneyScreen()));
      await settle(tester);
      expect(find.text('Comenzar'), findsOneWidget);
    },
    'Conexión y demo': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const SettingsScreen()));
      await settle(tester);
      expect(find.text('Orquestador simulado'), findsOneWidget);
    },
  };

  for (final screen in screens.entries) {
    group(screen.key, () {
      for (final (name, size, scale) in sizes) {
        testWidgets(name, (tester) async {
          setView(tester, size, scale);
          await screen.value(tester);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  group('Panel plegable de Inicio', () {
    for (final size in const [Size(640, 360), Size(915, 412)]) {
      testWidgets('se pliega y se despliega en ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        setView(tester, size, 1.0);
        final state = await newState(tester);
        await tester.pumpWidget(SaludDignaApp(state: state));
        await settle(tester);

        final nueva = find.widgetWithText(FilledButton, 'Nueva cita').hitTestable();
        expect(nueva, findsOneWidget);
        await tester.tap(find.byTooltip('Ocultar panel'));
        await settle(tester);
        expect(find.widgetWithText(FilledButton, 'Nueva cita').hitTestable(), findsNothing);
        expect(state.homeSidePaneCollapsed, isTrue);
        // "Tus citas" sigue visible en la columna derecha, que creció.
        expect(find.text('Tus citas').hitTestable(), findsOneWidget);

        await tester.tap(find.byTooltip('Mostrar panel'));
        await settle(tester);
        expect(find.widgetWithText(FilledButton, 'Nueva cita').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no existe en vertical', (tester) async {
      setView(tester, const Size(360, 640), 1.0);
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.byTooltip('Ocultar panel'), findsNothing);
      expect(find.byTooltip('Mostrar panel'), findsNothing);
    });
  });

  group('Barra vertical y panel (Nuevo prom)', () {
    Finder inRail(Finder f) =>
        find.descendant(of: find.byKey(CollapsibleTwoPane.railKey), matching: f);
    Finder inPane(Finder f) =>
        find.descendant(of: find.byKey(CollapsibleTwoPane.paneKey), matching: f);

    Future<AppState> homeLandscape(WidgetTester tester) async {
      setView(tester, const Size(915, 412), 1.0);
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      return state;
    }

    bool isToggleFocused(String tooltip) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return false;
      var found = false;
      focused.visitAncestorElements((e) {
        final w = e.widget;
        if (w is IconButton && w.tooltip == tooltip) found = true;
        return !found;
      });
      if (!found) {
        focused.visitChildElements((e) {
          final w = e.widget;
          if (w is IconButton && w.tooltip == tooltip) found = true;
        });
      }
      return found;
    }

    testWidgets('1. Panel abierto: sin barra vertical y con control de cierre alcanzable',
        (tester) async {
      await homeLandscape(tester);
      expect(inRail(find.byType(IconButton)), findsNothing, reason: 'la barra no se muestra');
      final close = inPane(find.byTooltip('Ocultar panel')).hitTestable();
      expect(close, findsOneWidget);
      final r = tester.getRect(close);
      expect((r.center.dy - 412 / 2).abs(), lessThan(1), reason: 'centrado verticalmente');
      expect(r.right, lessThan(915 / 2), reason: 'en el borde derecho del panel');
      // En la cabecera del panel solo queda el logotipo.
      expect(inPane(find.byType(BrandLogo)), findsOneWidget);
      expect(inPane(find.byTooltip('Conexión')), findsNothing);
      expect(inPane(find.byTooltip('Cerrar sesión')), findsNothing);
    });

    testWidgets('2. Panel cerrado: la barra conserva solo la flecha, sin logo, a media altura',
        (tester) async {
      await homeLandscape(tester);
      await tester.tap(find.byTooltip('Ocultar panel'));
      await settle(tester);

      final tips = inRail(find.byType(IconButton))
          .evaluate()
          .map((e) => (e.widget as IconButton).tooltip)
          .toSet();
      expect(tips, {'Mostrar panel'});
      expect(inRail(find.byType(BrandLogo)), findsNothing);
      final open = inRail(find.byTooltip('Mostrar panel')).hitTestable();
      expect(open, findsOneWidget);
      expect((tester.getRect(open).center.dy - 412 / 2).abs(), lessThan(1));
      expect(inPane(find.byType(IconButton)).hitTestable(), findsNothing,
          reason: 'el panel cerrado no recibe toques');
    });

    /// Comprueba que toques en las esquinas de un cuadrado de `size` dp centrado
    /// en el ícono llegan al botón (zona táctil real, no tamaño visible).
    void expectTouchTarget(WidgetTester tester, String tip, double size) {
      final button = find.ancestor(of: find.byTooltip(tip), matching: find.byType(IconButton)).first;
      final inside = <RenderObject>{};
      void collect(Element e) {
        final ro = e.renderObject;
        if (ro != null) inside.add(ro);
        e.visitChildren(collect);
      }
      collect(tester.element(button));
      final c = tester.getCenter(find.byTooltip(tip));
      final h = size / 2 - 0.5;
      for (final d in [Offset(-h, -h), Offset(h, -h), Offset(-h, h), Offset(h, h)]) {
        final result = HitTestResult();
        tester.binding.hitTestInView(result, c + d, tester.view.viewId);
        expect(result.path.any((entry) => inside.contains(entry.target)), isTrue,
            reason: '$tip: el toque en ${c + d} debe llegar al botón');
      }
    }

    Finder inHeader(Finder f) =>
        find.descendant(of: find.byKey(MainPaneHeader.actionsKey), matching: f);

    testWidgets('Accesos en la esquina superior derecha del área principal, una sola vez',
        (tester) async {
      await homeLandscape(tester);
      for (final tip in ['Conexión', 'Cerrar sesión']) {
        expect(find.byTooltip(tip), findsOneWidget, reason: '$tip no se duplica');
        expect(inHeader(find.byTooltip(tip)), findsOneWidget);
        final r = tester.getRect(find.byTooltip(tip));
        expectTouchTarget(tester, tip, 44);
        expect(r.right, greaterThan(915 - 140), reason: 'pegado al borde derecho');
        expect(r.top, lessThan(Space.sm + 48), reason: 'arriba');
      }
      // Misma fila que el título de la sección.
      final title = tester.getRect(find.text('Tus citas'));
      final icon = tester.getRect(find.byTooltip('Conexión'));
      expect((title.center.dy - icon.center.dy).abs(), lessThan(Space.md));
    });

    testWidgets('Los accesos no se mueven ni cambian de tamaño al alternar el panel',
        (tester) async {
      await homeLandscape(tester);
      final settings = tester.getRect(find.byTooltip('Conexión'));
      final logout = tester.getRect(find.byTooltip('Cerrar sesión'));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Ocultar panel').hitTestable());
        await settle(tester);
        expect(tester.getRect(find.byTooltip('Conexión')), settings);
        expect(tester.getRect(find.byTooltip('Cerrar sesión')), logout);
        expect(inRail(find.byTooltip('Conexión')), findsNothing);
        await tester.tap(find.byTooltip('Mostrar panel').hitTestable());
        await settle(tester);
        expect(tester.getRect(find.byTooltip('Conexión')), settings);
        expect(tester.getRect(find.byTooltip('Cerrar sesión')), logout);
      }
    });

    testWidgets('El título de la fila superior sigue alineado con la lista, abierto y cerrado',
        (tester) async {
      setView(tester, const Size(915, 412), 1.0);
      final state = await newState(tester, confirmed: true);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      void expectAligned() {
        final title = tester.getRect(find.text('Tus citas'));
        final card = tester.getRect(
            find.descendant(of: find.byType(AppointmentsList), matching: find.byType(Card)).first);
        // Igual que antes: el título de sección está Space.xs a la derecha del
        // borde de la tarjeta.
        expect((title.left - (card.left + Space.xs)).abs(), lessThan(1));
      }

      expectAligned();
      await tester.tap(find.byTooltip('Ocultar panel').hitTestable());
      await settle(tester);
      expectAligned();
      await tester.tap(find.byTooltip('Mostrar panel').hitTestable());
      await settle(tester);
      expectAligned();
    });

    testWidgets('Área segura: con la barra del sistema a la derecha, los accesos no quedan debajo',
        (tester) async {
      setView(tester, const Size(915, 412), 1.0);
      tester.view.padding = const FakeViewPadding(right: 48);
      tester.view.viewPadding = const FakeViewPadding(right: 48);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      for (final tip in ['Conexión', 'Cerrar sesión']) {
        final r = tester.getRect(find.byTooltip(tip));
        expect(r.right, lessThanOrEqualTo(915 - 48), reason: '$tip queda fuera de la barra del sistema');
        expect(find.byTooltip(tip).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Abrir y cerrar varias veces no desplaza ni descoloca el contenido',
        (tester) async {
      final state = await homeLandscape(tester);
      final list = find.byKey(const PageStorageKey<String>('home-journeys'));
      final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
      await tester.drag(scrollable, const Offset(0, -80));
      await settle(tester);
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      final openRect = tester.getRect(list);

      Rect? closedRect;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Ocultar panel').hitTestable());
        await settle(tester);
        closedRect ??= tester.getRect(list);
        expect(tester.getRect(list), closedRect, reason: 'cerrado, siempre en el mismo lugar');
        await tester.tap(find.byTooltip('Mostrar panel').hitTestable());
        await settle(tester);
        expect(tester.getRect(list), openRect, reason: 'abierto, siempre en el mismo lugar');
        expect(tester.state<ScrollableState>(scrollable).position.pixels, offset,
            reason: 'se conserva la posición de desplazamiento');
      }
      expect(state.homeSidePaneCollapsed, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Accesibilidad: estado expandido, operable con teclado y foco visible',
        (tester) async {
      final handle = tester.ensureSemantics();
      final state = await homeLandscape(tester);
      expect(tester.getSemantics(find.bySemanticsLabel('Ocultar panel')),
          isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));

      var reached = false;
      for (var i = 0; i < 40 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached = isToggleFocused('Ocultar panel');
      }
      expect(reached, isTrue, reason: 'el control se alcanza con Tab');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(state.homeSidePaneCollapsed, isTrue, reason: 'Enter lo activa');
      expect(tester.getSemantics(find.bySemanticsLabel('Mostrar panel')),
          isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));

      final ctx = tester.element(find.byTooltip('Mostrar panel'));
      final side = Theme.of(ctx).iconButtonTheme.style!.side!.resolve({WidgetState.focused});
      expect(side, isNotNull, reason: 'anillo de foco visible');
      handle.dispose();
    });

    testWidgets('Respeta la preferencia de reducir animaciones', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await homeLandscape(tester);
      await tester.tap(find.byTooltip('Ocultar panel'));
      await tester.pump();
      await tester.pump();
      expect(inRail(find.byTooltip('Mostrar panel')).hitTestable(), findsOneWidget);
      expect(inPane(find.byType(IconButton)).hitTestable(), findsNothing);
    });

    testWidgets('4. En vertical no hay barra ni panel plegable', (tester) async {
      setView(tester, const Size(412, 915), 1.0);
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.byType(CollapsibleTwoPane), findsNothing);
      expect(find.byTooltip('Ocultar panel'), findsNothing);
      expect(find.byTooltip('Mostrar panel'), findsNothing);
      expect(find.text('Hola, Ana'), findsOneWidget);
    });

    testWidgets('5. Identificación: logo centrado y más arriba', (tester) async {
      setView(tester, const Size(412, 915), 1.0);
      final state = await newState(tester, loggedIn: false);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      final logo = tester.getRect(find.descendant(
          of: find.byKey(LoginScreen.logoKey), matching: find.byType(BrandLogo)));
      expect((logo.center.dx - 412 / 2).abs(), lessThan(1), reason: 'centrado');
      expect(logo.top, lessThan(56 + Space.md + 1), reason: 'sin espacio muerto encima');
      final title = tester.getRect(find.text('Identifícate'));
      expect(title.top - logo.bottom, greaterThanOrEqualTo(Space.xxl - 1),
          reason: 'más margen hacia el título');
    });
  });

  group('Teléfono horizontal 915x412', () {
    testWidgets('Inicio: acciones visibles, sin FAB y sin controles encimados',
        (tester) async {
      setView(tester, const Size(915, 412), 1.0);
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);

      final action = find.widgetWithText(OutlinedButton, 'Retomar trámite de otro canal');
      expect(action, findsOneWidget);
      expectFullyVisible(tester, action);
      expect(find.byType(FloatingActionButton), findsNothing);
      // "Nueva cita" sigue disponible, como botón normal del panel lateral.
      expect(find.widgetWithText(FilledButton, 'Nueva cita'), findsOneWidget);
      expectNoInteractiveOverlap(tester);
    });

    testWidgets('Detalle: la acción principal está en el panel lateral, sin barra al pie',
        (tester) async {
      setView(tester, const Size(915, 412), 1.0);
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);

      final action = find.widgetWithText(FilledButton, 'Confirma tu cita');
      expect(action, findsOneWidget);
      expectFullyVisible(tester, action);
      // Panel lateral: la acción queda en el tercio izquierdo de la pantalla.
      expect(tester.getRect(action).right, lessThan(915 / 2));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.bottomNavigationBar, isNull);
      expectNoInteractiveOverlap(tester);
    });

    testWidgets('Nueva cita: "Comenzar" visible sin desplazarse', (tester) async {
      setView(tester, const Size(915, 412), 1.0);
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const NewJourneyScreen()));
      await settle(tester);
      expectFullyVisible(tester, find.widgetWithText(FilledButton, 'Comenzar'));
      expectNoInteractiveOverlap(tester);
    });

    testWidgets('Al girar se conserva la sesión y lo escrito en el formulario',
        (tester) async {
      setView(tester, const Size(412, 915), 1.0);
      final state = await newState(tester, loggedIn: false);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).first, 'SD-654321');
      await tester.pump();

      tester.view.physicalSize = const Size(915, 412);
      await settle(tester);
      expect(find.text('SD-654321'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
