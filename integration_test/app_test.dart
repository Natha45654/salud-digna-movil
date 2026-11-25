import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salud_digna_movil/core/config.dart';
import 'package:salud_digna_movil/main.dart';
import 'package:salud_digna_movil/state/app_state.dart';

/// Recorrido completo en dispositivo real, con el orquestador simulado.
/// Ejecutar: `flutter test integration_test -d DISPOSITIVO`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> launch(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
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

  testWidgets('Recorrido de Ana: identidad, continuidad, confirmación',
      (tester) async {
    await launch(tester);

    // 1. OTP incorrecto no da acceso.
    await login(tester, customerId: 'SD-123456', otp: '000000');
    expect(find.text('Código de verificación incorrecto'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsNothing);

    // 2. OTP correcto: identidad verificada; el pendiente se abre desde "Retomar".
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tapButton(tester, 'Continuar');
    await settle(tester, const Duration(seconds: 2));
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Continúa donde te quedaste'), findsNothing);
    await tapButton(tester, 'Retomar trámite de otro canal');
    await waitFor(tester, find.text('Ultrasonido abdominal'));
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

  testWidgets('Nuevo trámite desde la app, caída del orquestador y reenvío',
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

  testWidgets('Aislamiento entre pacientes: Luis no ve el trámite de Ana',
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
