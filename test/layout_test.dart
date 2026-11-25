import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/core/theme.dart';
import 'package:salud_digna_movil/main.dart';
import 'package:salud_digna_movil/models/models.dart';
import 'package:salud_digna_movil/screens/journey_screen.dart';
import 'package:salud_digna_movil/screens/new_journey_screen.dart';
import 'package:salud_digna_movil/screens/settings_screen.dart';
import 'package:salud_digna_movil/state/app_state.dart';

/// Regresión de layout: cada pantalla principal en tres tamaños
/// (vertical, horizontal de teléfono y tableta) y con letra al 100 % y 200 %.
/// Cualquier desborde (RenderFlex overflow) o excepción de layout hace fallar
/// la prueba. Usa el orquestador simulado.
void main() {
  const sizes = <String, Size>{
    'vertical 360x640': Size(360, 640),
    'horizontal 640x360': Size(640, 360),
    'tableta 900x600': Size(900, 600),
  };
  const scales = [1.0, 2.0];

  Future<AppState> newState(WidgetTester tester, {bool loggedIn = true}) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final config = await AppConfig.load();
      state = AppState(config);
      await state.init();
      if (loggedIn) {
        await state.login(
          identifiers: const [PatientIdentifier(type: 'PATIENT_ID', value: 'SD-123456')],
          otp: '123456',
        );
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

  /// Cada caso construye la pantalla y, si aplica, abre un diálogo.
  final cases = <String, Future<void> Function(WidgetTester)>{
    'Acceso': (tester) async {
      final state = await newState(tester, loggedIn: false);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      final send = find.text('Enviar código de verificación');
      await tester.ensureVisible(send);
      await tester.pumpAndSettle();
      await tester.tap(send);
      await settle(tester);
      expect(find.text('Código de verificación'), findsWidgets);
    },
    'Inicio': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.text('Tus citas'), findsWidgets);
    },
    'Inicio con citas cerradas': (tester) async {
      final state = await newState(tester);
      await tester.runAsync(() async {
        await state.sendEvent(state.buildEvent(
          eventType: EventTypes.confirmationRequested,
          journeyId: 'ATN-2026-001',
        ));
        await state.refreshJourneys();
      });
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      expect(find.text('Tus citas'), findsOneWidget);
    },
    'Retomar trámite (ventana de pendientes)': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(SaludDignaApp(state: state));
      await settle(tester);
      final link = find.text('Retomar trámite de otro canal');
      await tester.scrollUntilVisible(link, 200, scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await settle(tester);
      await tester.tap(link);
      await settle(tester);
      expect(find.text('Trámites pendientes'), findsOneWidget);
    },
    'Detalle pendiente': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      expect(find.text('Confirma tu cita'), findsWidgets);
    },
    'Ayuda (contacto)': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      final detail = find.descendant(
        of: find.byKey(const PageStorageKey<String>('journey-detail')),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(find.text('Llamar al Call Center'), 200, scrollable: detail);
      await settle(tester);
      expect(find.text('Escribir por WhatsApp'), findsOneWidget);
    },
    'Confirmar cita (diálogo)': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirma tu cita'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
    'Detalle confirmado': (tester) async {
      final state = await newState(tester);
      await tester.runAsync(() => state.sendEvent(state.buildEvent(
            eventType: EventTypes.confirmationRequested,
            journeyId: 'ATN-2026-001',
          )));
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      expect(find.text('Confirmada'), findsWidgets);
      // La tarjeta de cita y "Cancelar cita" quedan más abajo: se desplaza
      // hasta ellas para verificar que también se dibujan sin desborde.
      await tester.scrollUntilVisible(find.text('Cancelar cita'), 200,
          scrollable: find.byType(Scrollable).first);
      await settle(tester);
    },
    'Selector de horarios': (tester) async {
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      // "Horario" también es una etiqueta de la barra de pasos: se toca la fila.
      final row = find.widgetWithText(ListTile, 'Horario');
      final detail = find.descendant(
        of: find.byKey(const PageStorageKey<String>('journey-detail')),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(row, 120, scrollable: detail);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await settle(tester);
      expect(find.text('Elige un horario'), findsWidgets);
    },
    'Horarios sin disponibilidad': (tester) async {
      final state = await newState(tester);
      await tester.runAsync(() => state.sendEvent(state.buildEvent(
            eventType: EventTypes.clinicSelected,
            journeyId: 'ATN-2026-001',
            data: const {'clinicId': 'CLI-015', 'clinicName': 'Salud Digna Tlajomulco'},
          )));
      await tester.pumpWidget(wrap(state, const JourneyScreen(journeyId: 'ATN-2026-001')));
      await settle(tester);
      // "Horario" también es una etiqueta de la barra de pasos: se toca la fila.
      final row = find.widgetWithText(ListTile, 'Horario');
      final detail = find.descendant(
        of: find.byKey(const PageStorageKey<String>('journey-detail')),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(row, 120, scrollable: detail);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await settle(tester);
      expect(find.text('No hay horarios disponibles'), findsOneWidget);
      expect(find.text('Cambiar clínica'), findsOneWidget);
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

  for (final c in cases.entries) {
    group(c.key, () {
      for (final size in sizes.entries) {
        for (final scale in scales) {
          testWidgets('${size.key} · letra ${(scale * 100).round()} %', (tester) async {
            setView(tester, size.value, scale);
            await c.value(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    });
  }

  group('Teclado abierto', () {
    testWidgets('una columna con teclado grande: la barra fija se oculta',
        (tester) async {
      // 412x915 con un teclado de 600 dp deja 315 dp útiles: la barra se
      // oculta mientras se escribe para no tapar los campos.
      setView(tester, const Size(412, 915), 1.0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(tester.view.resetViewInsets);
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const NewJourneyScreen()));
      await settle(tester);
      expect(find.text('Comenzar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('horizontal con teclado: el acceso no se desborda', (tester) async {
      setView(tester, const Size(640, 360), 2.0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.resetViewInsets);
      final login = await newState(tester, loggedIn: false);
      await tester.pumpWidget(SaludDignaApp(state: login));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con altura suficiente la acción fija sube sobre el teclado',
        (tester) async {
      setView(tester, const Size(900, 900), 1.0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      final state = await newState(tester);
      await tester.pumpWidget(wrap(state, const NewJourneyScreen()));
      await settle(tester);
      final button = find.text('Comenzar');
      expect(button, findsOneWidget);
      // El botón queda por encima del borde superior del teclado.
      expect(tester.getBottomLeft(button).dy, lessThan(900 - 300));
      expect(tester.takeException(), isNull);
    });
  });
}
