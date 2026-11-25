import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/main.dart';
import 'package:salud_digna_movil/state/app_state.dart';

/// Los mismos recorridos que integration_test/app_test.dart, pero como pruebas
/// de widgets en la PC (sin dispositivo), contra el orquestador simulado.
/// Ejecutar: `flutter test test/ui_flow_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> launch(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final config = await AppConfig.load();
    final state = AppState(config);
    await state.init();
    await tester.pumpWidget(SaludDignaApp(state: state));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester,
      [Duration d = const Duration(milliseconds: 600)]) async {
    await tester.pump(d);
    await tester.pumpAndSettle();
  }

  /// Oculta cualquier aviso flotante que pudiera tapar un botón.
  Future<void> dismissSnack(WidgetTester tester) async {
    final scaffold = find.byType(Scaffold);
    if (scaffold.evaluate().isNotEmpty) {
      ScaffoldMessenger.of(tester.element(scaffold.first)).clearSnackBars();
      await settle(tester);
    }
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await dismissSnack(tester);
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
  }

  Future<void> login(WidgetTester tester,
      {required String customerId, required String otp}) async {
    await tester.enterText(find.byType(TextFormField).first, customerId);
    await tapButton(tester, 'Enviar código de verificación');
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).last, otp);
    await tapButton(tester, 'Continuar');
    await settle(tester, const Duration(seconds: 2));
  }

  /// Espera hasta que el buscador encuentre algo (máx. 10 s).
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }
    final texts = find.byType(Text).evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    tester.printToConsole('PANTALLA al fallar la espera de $finder: $texts');
    for (final e in find.byType(ListView, skipOffstage: false).evaluate()) {
      tester.printToConsole('LISTVIEW size=${e.size} offstage=${!find.byType(ListView).evaluate().contains(e)}');
    }
    for (final e in find.byType(Scaffold, skipOffstage: false).evaluate()) {
      tester.printToConsole('SCAFFOLD size=${e.size}');
    }
    expect(finder, findsWidgets);
  }

  /// Desplaza la lista principal hasta el final (para ver el historial).
  Future<void> scrollToEnd(WidgetTester tester) async {
    await dismissSnack(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
  }

  /// El historial está plegado por omisión: se baja hasta él y se despliega.
  Future<void> openHistory(WidgetTester tester) async {
    await scrollToEnd(tester);
    await tester.tap(find.text('Historial de atención'));
    await settle(tester);
    await scrollToEnd(tester);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await dismissSnack(tester);
    await tester.tap(find.byTooltip('Conexión'));
    await settle(tester);
  }

  Future<void> goBack(WidgetTester tester) async {
    await dismissSnack(tester);
    await tester.tap(find.byType(BackButton).first);
    await settle(tester);
  }

  testWidgets('1. Identidad: OTP incorrecto se rechaza y el correcto da acceso',
      (tester) async {
    await launch(tester);
    await login(tester, customerId: 'SD-123456', otp: '000000');
    expect(find.text('Código de verificación incorrecto'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsNothing);
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tapButton(tester, 'Continuar');
    await settle(tester, const Duration(seconds: 2));
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Verificada'), findsOneWidget);
  });

  testWidgets('2. Continuidad Web → WhatsApp → App y confirmación de la cita',
      (tester) async {
    await launch(tester);
    await login(tester, customerId: 'SD-123456', otp: '123456');
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Continúa donde te quedaste'), findsNothing);
    // Los pendientes se abren desde "Retomar", sin código.
    await tapButton(tester, 'Retomar trámite de otro canal');
    await waitFor(tester, find.text('Ultrasonido abdominal'));
    expect(find.text('Trámites pendientes'), findsOneWidget);
    expect(find.textContaining('Lo dejaste en WhatsApp'), findsOneWidget);

    // 3. Abrir el trámite: contexto de Web y WhatsApp, y cambio de canal registrado.
    await tapButton(tester, 'Ultrasonido abdominal');
    await waitFor(tester, find.text('Canales:'));
    expect(find.text('Lista para confirmar'), findsOneWidget);
    expect(find.text('Sitio Web'), findsWidgets);
    expect(find.text('WhatsApp'), findsWidgets);
    // El evento CONTEXT_RESUMED se registra tras cargar: esperar a verlo.
    await waitFor(tester, find.text('App móvil'));
    expect(find.textContaining('Salud Digna Guadalajara Centro'), findsWidgets);
    await openHistory(tester);
    expect(find.text('Trámite retomado en otro canal'), findsWidgets);

    // 4. Confirmar la cita desde la app.
    await tapButton(tester, 'Confirma tu cita');
    await settle(tester);
    await tapButton(tester, 'Confirmar');
    await waitFor(tester, find.textContaining('Folio CITA-'));
    expect(find.text('Cita confirmada'), findsWidgets);
    // Trámite cerrado: ya no hay botón de próximo paso ni acciones de cambio.
    expect(find.text('Confirma tu cita'), findsNothing);
    expect(find.text('Cambiar'), findsNothing);

    // 5. En inicio aparece en "Tus citas".
    await goBack(tester);
    expect(find.text('Tus citas'), findsOneWidget);
    await waitFor(tester, find.text('Ultrasonido abdominal'));
  });

  testWidgets('3. Nuevo trámite desde la app con progreso por pasos',
      (tester) async {
    await launch(tester);
    await login(tester, customerId: 'SD-123456', otp: '123456');
    expect(find.text('Hola, Ana'), findsOneWidget);

    // Iniciar trámite.
    await tapButton(tester, 'Nueva cita');
    await settle(tester);
    await tapButton(tester, 'Comenzar');
    await waitFor(tester, find.text('Recién iniciado'));

    // Elegir estudio con el orquestador disponible.
    await waitFor(tester, find.text('Elige tu estudio'));
    await tapButton(tester, 'Elige tu estudio');
    await settle(tester);
    await tapButton(tester, 'Rayos X de tórax');
    await waitFor(tester, find.text('En progreso'));
    expect(find.textContaining('Rayos X de tórax'), findsWidgets);
    // El inicio refleja el trámite nuevo con su progreso.
    await goBack(tester);
    await tapButton(tester, 'Retomar trámite de otro canal');
    await waitFor(tester, find.text('Rayos X de tórax'));
    expect(find.text('Elige tu clínica'), findsWidgets);
  });

  testWidgets('4. Caída del orquestador: el cambio queda en cola y se reenvía sin duplicar',
      (tester) async {
    await launch(tester);
    await login(tester, customerId: 'SD-123456', otp: '123456');
    await tapButton(tester, 'Nueva cita');
    await settle(tester);
    await tapButton(tester, 'Comenzar');
    await waitFor(tester, find.text('Recién iniciado'));
    await waitFor(tester, find.text('Elige tu estudio'));
    await tapButton(tester, 'Elige tu estudio');
    await settle(tester);
    await tapButton(tester, 'Rayos X de tórax');
    await waitFor(tester, find.text('En progreso'));

    // Simular caída del orquestador desde el propio trámite.
    await openSettings(tester);
    await tapButton(tester, 'Simular caída del orquestador');
    await goBack(tester);

    // Elegir clínica con el orquestador caído: debe quedar en el outbox.
    await waitFor(tester, find.text('Elige tu clínica'));
    await tapButton(tester, 'Elige tu clínica');
    await settle(tester);
    await tapButton(tester, 'Salud Digna Tlajomulco');
    await waitFor(tester, find.textContaining('quedó en cola'));

    // Outbox muestra el evento con su error; restaurar y reenviar.
    await openSettings(tester);
    expect(find.text('1 evento(s) sin entregar'), findsOneWidget);
    expect(find.text('Clínica seleccionada'), findsOneWidget);
    expect(find.textContaining('Fallo simulado'), findsOneWidget);
    await tapButton(tester, 'Simular caída del orquestador');
    await tapButton(tester, 'Reenviar');
    await waitFor(tester, find.text('Todo entregado'));

    // De vuelta en el trámite, actualizar: la clínica aparece una sola vez.
    await goBack(tester);
    await dismissSnack(tester);
    await tester.tap(find.byTooltip('Actualizar'));
    await waitFor(tester, find.textContaining('Salud Digna Tlajomulco'));
    await openHistory(tester);
    expect(find.text('Clínica seleccionada'), findsOneWidget);
  });

  testWidgets('5. Aislamiento entre pacientes y cierre de sesión con confirmación',
      (tester) async {
    await launch(tester);
    await login(tester, customerId: 'SD-654321', otp: '654321');
    expect(find.text('Hola, Luis'), findsOneWidget);
    expect(find.text('Aún no tienes citas confirmadas'), findsOneWidget);
    expect(find.text('Ultrasonido abdominal'), findsNothing);

    // Cerrar sesión y volver como Ana: el trámite sigue ahí.
    await dismissSnack(tester);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await settle(tester);
    await tapButton(tester, 'Cerrar sesión');
    await settle(tester);
    await login(tester, customerId: 'SD-123456', otp: '123456');
    expect(find.text('Hola, Ana'), findsOneWidget);
    await tapButton(tester, 'Retomar trámite de otro canal');
    await waitFor(tester, find.text('Ultrasonido abdominal'));
  });
}
