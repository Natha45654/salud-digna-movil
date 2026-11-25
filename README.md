# Salud Digna · App móvil (canal MOBILE_APP)

## 1. Qué es y cómo encaja en el sistema

App Flutter para Android del canal **MOBILE_APP** del reto *Software
Inteligente* de Salud Digna (Hackatec). El sistema omnicanal permite que un
paciente inicie un trámite en un canal (sitio web, WhatsApp, Call Center o app)
y lo continúe en otro sin repetir información. Esta app es el canal móvil: el
paciente se identifica, ve sus trámites pendientes con el contexto que dejó en
otros canales, los retoma o inicia uno nuevo, y cada paso queda registrado como
evento en el historial del trámite.

### Estado actual de la integración

La app tiene dos implementaciones del mismo cliente (`OrchestratorClient`):

| Modo | Qué hace | Estado |
|------|----------|--------|
| **Simulado** (`MOCK_MODE=true`, por omisión) | Un orquestador en memoria dentro de la app, con pacientes y un trámite sembrados. No necesita red. | Cubierto por 185 pruebas automáticas que pasan (`flutter test`). En dispositivo: pendiente de verificar. |
| **HTTP** (`MOCK_MODE=false`) | Llama a un backend intermedio del canal móvil con el contrato descrito en [`CONTRATO_API.md`](CONTRATO_API.md). | Ese backend no está publicado en ningún repositorio. Pendiente de verificar. |

**La app todavía no consume la API de producción.** La API desplegada usa otras
rutas y otra autenticación (ver sección 5). Las rutas que llama el cliente HTTP
de la app (`/api/v1/identity/verify`, `/api/v1/integrations/events`,
`/api/v1/me/journeys`, `/api/v1/journeys/{id}`) responden `404` en producción.

Por lo mismo, la demo de continuidad de la sección 8 ocurre completa dentro del
orquestador simulado: los pasos de los otros canales vienen sembrados, no se
ejecutan en el sitio web, WhatsApp ni el Call Center reales.

### Qué guarda la app en el dispositivo

En `SharedPreferences`: la sesión del paciente (incluido su token), la URL y la
clave de canal configuradas, el modo, los eventos pendientes de envío (outbox) y,
en modo simulado, los datos del orquestador simulado. La app **no** contiene ni
guarda la API key del orquestador, credenciales Ed25519 ni access-grants.

## 2. Requisitos previos

Versiones verificadas al compilar este repositorio desde un clon limpio:

| Herramienta | Versión verificada | Origen del requisito |
|-------------|--------------------|----------------------|
| Flutter | 3.47.5, canal stable | Versión con la que se compiló y probó |
| Dart | 3.13.4 (incluido en Flutter 3.47.5) | `pubspec.yaml` exige `>=3.13.4 <4.0.0` |
| Android SDK | Plataforma `android-36` (compileSdk y targetSdk 36) | Valores de Flutter 3.47.5 usados por `android/app/build.gradle.kts` |
| Android mínimo del dispositivo | 7.0 (API 24) | `minSdk = flutter.minSdkVersion` (24 en Flutter 3.47.5) |
| JDK | 17 o superior; se compiló con OpenJDK 21 (el que incluye Android Studio) | El proyecto compila con objetivo Java 17 |
| Gradle / Android Gradle Plugin / Kotlin | 9.3.1 / 9.1.0 / 2.4.0 | `gradle-wrapper.properties` y `settings.gradle.kts`; Gradle se descarga solo |
| Git | cualquiera reciente | Para clonar |

Dependencias de la app (`pubspec.yaml`, versiones de `pubspec.lock`): `http`
1.6.0, `shared_preferences` 2.5.6, `uuid` 4.6.0 y `cupertino_icons` 1.0.9.
Desarrollo: `flutter_test`, `integration_test` y `flutter_lints` 6.0.0.

### Preparar Flutter y el Android SDK

1. Comprueba que el `flutter` de tu terminal es el del SDK que vas a usar. Si
   `flutter --version` no imprime nada y se queda esperando, tu `PATH` apunta a
   otra copia del SDK (ver sección 9). Mientras lo corriges, ejecuta Flutter
   con la ruta completa: `<ruta del SDK>/bin/flutter`.
2. Ejecuta `flutter doctor -v` y revisa la sección *Android toolchain*: debe
   indicar la ruta del Android SDK y la plataforma `android-36`. Si Flutter no
   encuentra el SDK, indícaselo con `flutter config --android-sdk <ruta>`.
3. Si `flutter doctor` avisa de licencias de Android sin aceptar, ejecuta
   `flutter doctor --android-licenses`. Este paso no se probó en una máquina
   nueva: pendiente de verificar.
4. Si Flutter no usa un JDK 17 o superior, indícaselo con
   `flutter config --jdk-dir <ruta del JDK>`.

## 3. Instalación

Probado desde un clon limpio:

```bash
git clone https://github.com/Natha45654/salud-digna-movil.git
cd salud-digna-movil
flutter pub get
cp .env.example .env        # en PowerShell: Copy-Item .env.example .env
```

En Windows, `flutter pub get` puede terminar con el aviso *"Building with
plugins requires symlink support"* y código de salida 1 aunque las dependencias
sí se resolvieron (ver sección 9).

Para comprobar la instalación:

```bash
flutter analyze     # resultado esperado: No issues found!
flutter test        # resultado esperado: 185 pruebas, All tests passed!
```

## 4. Configuración

La configuración se lee **al compilar** desde `.env` con
`--dart-define-from-file=.env`. El archivo `.env` no se versiona;
`.env.example` contiene las mismas variables vacías. Una variable vacía equivale
a no definida. Con `.env` sin completar la app compila y arranca en modo
simulado.

| Variable | Para qué sirve | Si está vacía | Ejemplo ficticio |
|----------|----------------|---------------|------------------|
| `MOCK_MODE` | `true`: orquestador simulado. `false`: cliente HTTP. | `true` | `true` |
| `CHANNEL_BACKEND_URL` | URL base del backend del canal móvil, sin `/` final. La app le añade `/api/v1/...`. | Se configura en la app | `https://backend-canal.example.com` |
| `CHANNEL_KEY` | Valor de la cabecera `X-Channel-Key` hacia ese backend. | Se configura en la app | `clave-de-ejemplo` |
| `WHATSAPP_SIMULATOR` | `true`: "¿Necesitas ayuda?" abre el simulador de WhatsApp del equipo (`saluddigna-wa://`). | `false` (abre `wa.me`) | `false` |
| `SD_WHATSAPP` | Número de WhatsApp de contacto, solo dígitos con lada. | Abre WhatsApp sin número | `525500000000` |
| `SD_CALL_CENTER` | Número del Call Center, solo dígitos. | Abre el marcador sin número | `5500000000` |

Dentro de la app, el icono de engranaje (**Conexión y demo**) permite cambiar el
modo, la URL y la clave. Lo guardado ahí tiene prioridad sobre `.env` y se
conserva al reinstalar con `adb install -r`; para volver a los valores de `.env`
hay que borrar los datos de la app.

## 5. Cómo apuntar la app a la API y cambiar de entorno

### Entornos

| Entorno | Cómo se activa | Estado |
|---------|----------------|--------|
| Simulado en el dispositivo | `MOCK_MODE=true` o vacío, o el interruptor *Orquestador simulado* en Conexión y demo | Es el entorno de la demo. Cubierto por pruebas automáticas; en dispositivo, pendiente de verificar. |
| Backend del canal móvil | `MOCK_MODE=false`, `CHANNEL_BACKEND_URL` y `CHANNEL_KEY`; recompilar | Pendiente de verificar: el backend no está publicado. |
| API de producción | No disponible | La app no es compatible todavía con esta API. |

Para cambiar de entorno, edita `.env` y vuelve a compilar, o cambia el modo y la
URL en **Conexión y demo** y pulsa *Guardar*.

Si usas el backend del canal móvil en tu PC, la URL depende de dónde corre la
app: en el emulador de Android tu PC es `10.0.2.2`; en un teléfono por USB usa
`127.0.0.1` después de `adb reverse tcp:<puerto> tcp:<puerto>`.

### API de producción (referencia)

Fuente: `docs/openapi.json` de la rama `main` del repositorio del orquestador
del equipo (acceso restringido). La app no llama a estas rutas todavía.

- URL base: `https://api.salud-digna.app/api/v1`
- Autenticación: `POST /auth/login` con `email` y `password`. Responde
  `accessToken` (JWT), `tokenType: "Bearer"`, `expiresIn` (segundos) y `user`.
  Las demás rutas usan `Authorization: Bearer <accessToken>`. No hay cabecera
  `X-Channel-Key`. El cliente solo maneja el JWT del paciente: la API central
  conserva las credenciales del canal y obtiene los permisos de cada trámite.

| Método | Ruta | Uso |
|--------|------|-----|
| `GET` | `/mobile/journeys` | Trámites activos del paciente autenticado (`items`) |
| `POST` | `/mobile/journeys` | Crear un trámite. Cuerpo `{ "type": "APPOINTMENT" }`; cabecera obligatoria `Idempotency-Key` |
| `GET` | `/mobile/journeys/{journeyId}` | Estado: `id`, `status`, `type`, `createdAt`, `updatedAt` |
| `GET` | `/mobile/journeys/{journeyId}/context` | Contexto: `journeyId`, `currentStep`, `version`, `externalRefs`, `updatedAt` |
| `GET` | `/mobile/journeys/{journeyId}/history` | Historial: `items` y `nextCursor`; parámetros `limit` y `cursor` |
| `POST` | `/mobile/journeys/{journeyId}/events` | Registrar un avance: `externalEventId`, `type` (`JOURNEY_CONTEXT_UPDATED` o `JOURNEY_STATUS_CHANGED`), `schemaVersion: 1`, `occurredAt`, `payload` |

`GET /api/v1/health` responde `{"status":"ok"}` sin autenticación. Sin token,
las rutas `/mobile/journeys` responden `401`.

## 6. Compilar y ejecutar el APK de depuración

Compilar (verificado desde un clon limpio):

```bash
flutter build apk --debug --dart-define-from-file=.env
```

El APK queda en `build/app/outputs/flutter-apk/app-debug.apk`.

Instalar en un teléfono (pendiente de verificar en este repositorio):

1. En el teléfono, activa las *Opciones de desarrollador* y la *Depuración
   USB*, y conéctalo por USB.
2. Comprueba que aparece con `adb devices` (o `flutter devices`). Usa el `adb`
   del Android SDK que configuraste en Flutter (ver sección 9).
3. Instala y abre:

   ```bash
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

   Con más de un dispositivo conectado, indica cuál con
   `adb -s <serie> install -r ...`. Después abre la app *Salud Digna* desde el
   lanzador del teléfono.

`flutter run --dart-define-from-file=.env` compila e instala en un paso; está
pendiente de verificar. `integration_test/app_test.dart` contiene el recorrido
completo para ejecutarse en un dispositivo; también está pendiente de verificar.

## 7. Credenciales de prueba

Los pacientes de prueba son ficticios. Este README no incluye sus valores.

| Entorno | Qué se necesita | Cómo obtenerlo |
|---------|-----------------|----------------|
| Simulado | Identificador del paciente y código de verificación | La pantalla de identificación los muestra en *Datos de prueba para la demo*; al tocar un paciente se rellenan. No hay que solicitarlos. |
| Backend del canal móvil | `CHANNEL_KEY` y los pacientes sembrados en ese backend | Al equipo que opera el backend. Medio de solicitud pendiente de definir. |
| API de producción | Cuenta de paciente (correo y contraseña) | Al equipo que opera el orquestador. Medio de solicitud pendiente de definir. La app aún no usa esta API. |

La API key del orquestador nunca va en la app.

## 8. Demo de continuidad omnicanal

Entorno: simulado. Los pasos de los canales sitio web y WhatsApp vienen
sembrados en el orquestador simulado; no se ejecutan en esos canales. Todo lo
que sigue se hace en la app.

Estado de verificación: los pasos están cubiertos por las pruebas de widgets
`test/ui_flow_test.dart` y `test/resume_flow_test.dart`, que pasan. La
ejecución en un teléfono está pendiente de verificar.

Preparación: abre **Conexión y demo** (engranaje), comprueba que
*Orquestador simulado* esté activado y pulsa *Restablecer escenario de Ana*.
Si hay una sesión abierta, ciérrala con *Cerrar sesión*.

| Paso | Canal | Qué haces | Qué debes ver |
|------|-------|-----------|---------------|
| 0 | Sitio web, luego WhatsApp (sembrado) | Nada: el escenario ya contiene que Ana eligió estudio y clínica en el sitio web y el horario en WhatsApp. | — |
| 1 | App | En *Datos de prueba para la demo* toca a Ana García, pulsa *Enviar código de verificación*, cambia el código por uno incorrecto y pulsa *Continuar*. | El aviso *Código de verificación incorrecto*. |
| 2 | App | Escribe el código correcto de Ana y pulsa *Continuar*. | *Hola, Ana* y su ficha marcada como *Verificada*. |
| 3 | App | Pulsa *Retomar trámite de otro canal*. | El trámite *Ultrasonido abdominal*, clínica, estado *Lista para confirmar* y *Lo dejaste en WhatsApp*. |
| 4 | App | Toca el trámite y despliega *Historial de atención*. | Estudio, clínica y horario ya elegidos, con la barra de progreso en el último paso (*Confirmar*). En el historial, eventos de *Sitio Web*, *WhatsApp* y *App móvil*, incluidos *Trámite retomado* y *Cambio de canal (De WhatsApp a App móvil)*. |
| 5 | App | Pulsa *Confirma tu cita* y luego *Confirmar* en el diálogo. | En el historial: *Confirmación solicitada* (App móvil) y *Cita confirmada* con un folio (Sistema de citas). |
| 6 | App | Restablece el escenario, abre de nuevo el trámite de Ana, activa *Simular caída del orquestador* en Conexión y demo, vuelve y cambia el **estudio**. En Conexión y demo, desactiva la caída y pulsa *Reenviar*. | Primero *1 evento(s) sin entregar* con el error simulado; después *Todo entregado*. Al actualizar el trámite, un solo evento *Estudio seleccionado*. |
| 7 | App | Cierra sesión y entra como Luis Hernández. Pulsa *Retomar trámite de otro canal*. | *No tienes trámites pendientes*: Luis no ve el trámite de Ana. *Nueva cita* abre *Agenda un estudio*. |
| 8 | App | Conexión y demo → *Restablecer escenario de Ana*. | El escenario queda listo para repetir la demo. |

Al retomar un trámite, la app registra los eventos `REQUEST_RESUMED` y
`CHANNEL_SWITCHED`.

## 9. Resolución de problemas

**`flutter` no responde.** Al probar desde un clon limpio, el `flutter` del
`PATH` apuntaba a una segunda copia del SDK y se quedaba bloqueado sin imprimir
nada. Ejecutar `flutter doctor` con esa misma copia también se bloquea. Ejecuta
el del SDK que usas, con ruta completa (`<ruta del SDK>/bin/flutter doctor`):
avisa con *"`flutter` on your path resolves to ..., which is not inside your
current Flutter SDK checkout"*. Corrige el `PATH` poniendo primero
`<ruta del SDK>/bin`.

**`flutter pub get` termina con error de symlinks.** En Windows aparece
*"Building with plugins requires symlink support. Please enable Developer Mode"*
y el código de salida es 1, pero las dependencias se resuelven (existe
`.dart_tool/package_config.json`), `flutter analyze` y `flutter test` funcionan
y el APK de Android compila. Para quitar el aviso, activa el Modo de
desarrollador de Windows.

**`flutter doctor` avisa de varios `adb`.** Si hay más de un Android SDK
instalado, el `adb` del `PATH` puede no ser el del SDK que usa Flutter.
`flutter doctor -v` muestra la ruta del SDK configurado; usa el `adb` de su
carpeta `platform-tools` y, con varios dispositivos, añade `-s <serie>`.

**La app no arranca en el estado esperado tras reinstalar.** `adb install -r`
conserva los datos: la sesión, el modo y la URL guardados en Conexión y demo
siguen vigentes. Cierra sesión y usa *Restablecer escenario de Ana*, o borra
los datos de la app.

**Con la caída simulada no cargan los horarios.** Es lo esperado: también
fallan las lecturas. Para la prueba de resiliencia cambia el estudio o la
clínica.

**La identificación falla con `404` al usar la API de producción.** La app no es
compatible todavía con `https://api.salud-digna.app/api/v1` (ver sección 1).
Usa el modo simulado.

## Estructura del proyecto

```
lib/
  main.dart                          arranque, tema, inyección de estado
  core/config.dart                   modo, URL y clave (variables de entorno + ajustes)
  core/theme.dart                    sistema visual y modo oscuro
  models/models.dart                 evento, trámite, estados, errores
  data/catalog.dart                  estudios, clínicas y horarios ficticios
  services/orchestrator_client.dart  interfaz común de los dos modos
  services/http_orchestrator.dart    cliente HTTP (contrato de CONTRATO_API.md)
  services/mock_orchestrator.dart    orquestador simulado
  services/outbox.dart               cola persistente de eventos con reintentos
  services/contact_launcher.dart     WhatsApp y Call Center
  state/app_state.dart               sesión, trámites y envío de eventos
  screens/                           identificación, inicio, trámite, nueva cita, conexión
  ui/layout/                         diseño adaptable
  widgets/                           componentes
test/                                pruebas unitarias y de widgets
integration_test/                    recorrido en dispositivo
```

Principios de diseño de la interfaz: [`UX.md`](UX.md).
