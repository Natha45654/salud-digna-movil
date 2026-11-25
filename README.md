# Salud Digna · App móvil (canal MOBILE_APP)

## 1. Qué es y cómo encaja en el sistema

App Flutter para Android del canal **MOBILE_APP** del reto *Software
Inteligente* de Salud Digna (Hackatec). El sistema omnicanal permite que un
paciente inicie un trámite en un canal (sitio web, WhatsApp, Call Center o app)
y lo continúe en otro sin repetir información. Esta app es el canal móvil: el
paciente entra, ve los trámites que dejó en otros canales, los continúa o inicia
uno nuevo, y cada paso queda en el historial del trámite.

```
App Flutter ──JWT del paciente──▶ API central ──▶ Orquestador omnicanal
```

### Estado actual

La app tiene dos modos, que se eligen **al compilar** con `MOCK_MODE`:

| Modo | Qué hace | Estado |
|------|----------|--------|
| **Simulado** (`MOCK_MODE=true`, por omisión) | Un orquestador en memoria dentro de la app, con pacientes y un trámite sembrados. No usa red. | Cubierto por pruebas automáticas. En un teléfono: pendiente de verificar. |
| **Real** (`MOCK_MODE=false`) | Consume la API central de Salud Digna (`https://api.salud-digna.app/api/v1`) con el contrato de [`CONTRATO_API.md`](CONTRATO_API.md). | **Sin probar contra la API de producción.** Solo se probó contra una API falsa construida desde la documentación del equipo (`test/support/fake_central_api.dart`). Falta una cuenta de paciente de prueba. |

`flutter test` ejecuta 250 pruebas, todas pasan. Las del modo real cubren el
acceso, el inicio, la pantalla del trámite y los errores conocidos (401 por
sesión vencida, 404 sin trámites vinculados, 409, 429 con `Retry-After`, 502 y
503).

### Qué guarda la app en el dispositivo

- **Modo simulado**, en `SharedPreferences` con claves `mock.*`: la sesión del
  paciente de prueba, los eventos pendientes de envío (outbox), los datos del
  orquestador simulado y el interruptor de caída simulada.
- **Modo real:** nada. El JWT del paciente y los cambios pendientes viven solo
  en memoria.
- **En ambos**, la preferencia de usar el simulador de WhatsApp.

La app **no** contiene ni guarda la API key del orquestador, credenciales
Ed25519, access-grants ni encabezados de acreditación.

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
flutter test        # resultado esperado: 250 pruebas, All tests passed!
```

## 4. Configuración

La configuración se lee **al compilar** desde `.env` con
`--dart-define-from-file=.env`, o variable por variable con `--dart-define`. El
archivo `.env` no se versiona; `.env.example` contiene las mismas variables
vacías y su explicación. Una variable vacía equivale a no definida.

| Variable | Para qué sirve | Si está vacía | Ejemplo ficticio |
|----------|----------------|---------------|------------------|
| `MOCK_MODE` | `true`: orquestador simulado. `false`: API central real. | `true` | `false` |
| `CHANNEL_BACKEND_URL` | Origen de la API central, solo `https://`, **sin `/api/v1`**: la app añade `/api/v1` por su cuenta y, si se escribe, lo quita para no duplicarlo. Solo se usa con `MOCK_MODE=false`. | `https://api.salud-digna.app` | `https://api.example.com` |
| `WHATSAPP_SIMULATOR` | `true`: "¿Necesitas ayuda?" abre el simulador de WhatsApp del equipo (`saluddigna-wa://`). | `false` (abre `wa.me`) | `false` |
| `SD_WHATSAPP` | Número de WhatsApp de contacto, solo dígitos con lada. | Abre WhatsApp sin número | `525500000000` |
| `SD_CALL_CENTER` | Número del Call Center, solo dígitos. | Abre el marcador sin número | `5500000000` |

Ninguna variable lleva claves ni credenciales: la app solo usa el JWT que
obtiene al iniciar sesión.

El icono de engranaje (**Conexión**) muestra el modo y la URL, pero no los
cambia. Si `CHANNEL_BACKEND_URL` no empieza con `https://`, el APK del modo real
muestra una pantalla que lo explica en lugar de conectarse.

## 5. Cómo apuntar la app a la API y cambiar de entorno

| Entorno | Cómo se compila | Estado |
|---------|-----------------|--------|
| Simulado | `MOCK_MODE=true` o vacío | Cubierto por pruebas automáticas; en dispositivo, pendiente de verificar. |
| API central de producción | `MOCK_MODE=false`; `CHANNEL_BACKEND_URL` vacío | Sin probar contra producción. |
| Otra API central (demo o staging del equipo) | `MOCK_MODE=false` y `CHANNEL_BACKEND_URL=https://<origen>` | Sin probar. |

Para cambiar de entorno se compila e instala otro APK: la app no permite
cambiar el modo ni la URL. El modo y la URL compilados siempre mandan; versiones
anteriores guardaban estos valores en el teléfono, y la app los borra al
arrancar.

Lo que hace la app en modo real:

- **Acceso** con correo y contraseña (`POST /auth/login` y `GET /auth/me`).
  Solo admite cuentas `PATIENT` activas con perfil de paciente.
- **Inicio** con los trámites activos de `GET /mobile/journeys`: estado, paso,
  estudio, clínica y los primeros caracteres del folio (UUID).
- **Trámite:** recorrido estudio → clínica → revisión → *pendiente de
  confirmación* (`PENDING_CONFIRMATION`), con los catálogos de `/studies` y
  `/clinics`. También permite cancelar. Muestra el folio completo para
  compararlo con el sitio web y el Call Center, y el historial con el canal tal
  como lo devuelve la API (`demo-web`, `demo-mobile`, `demo-callcenter`...).
  Se vuelve a leer al regresar a la app, para ver el avance de otros canales.
- **Nueva cita** crea un trámite con `POST /mobile/journeys` y abre el
  selector de estudio.
- **No disponible todavía**, y así se muestra en la app: elegir fecha y hora,
  confirmar la cita y avisar por WhatsApp o Call Center desde la app. La API
  central no lo ofrece al canal móvil.

### Sesión, vencimiento y cambios pendientes (modo real)

- La sesión dura lo que indique `expiresIn` al iniciar sesión. `docs/api-auth.md`
  muestra 30 minutos como ejemplo; el valor de producción está pendiente de
  confirmar con el equipo de backend. **No hay renovación automática**: la
  app da la sesión por vencida 30 segundos antes y pide iniciar sesión de nuevo.
  Antes de una demostración, inicia sesión justo antes de empezar.
- Si un cambio no llega al servidor (sin red, `5xx` o `429`), la app lo
  reintenta hasta 3 veces con el mismo contenido. Si sigue sin llegar, queda
  **pendiente**: el trámite lo avisa, con *Reintentar* y *Descartar*, y no
  admite otro cambio hasta resolverlo.
- Los cambios pendientes **viven solo en memoria. Se pierden si se cierra la
  app** y se descartan al cerrar sesión. Si la sesión vence, se conservan
  mientras la app siga abierta y se pueden reenviar al volver a entrar con la
  misma cuenta; otra cuenta nunca los ve. No hay que prometer frente al jurado
  una persistencia que no existe.

## 6. Compilar e instalar los APK

Compilación de depuración (verificada desde un clon limpio):

```bash
flutter build apk --debug --dart-define-from-file=.env
```

El APK queda en `build/app/outputs/flutter-apk/app-debug.apk`.

### Los dos APK de la demostración

Para no recompilar en el escenario, se preparan dos APK: uno simulado y uno
real. Ambos usan el mismo identificador de aplicación, así que en un mismo
teléfono solo puede haber uno instalado a la vez: para cambiar, se instala el
otro encima. Los dos comandos compilan; la ruta de salida es la misma, así que
hay que copiar el primero antes de compilar el segundo:

```bash
flutter build apk --release --dart-define=MOCK_MODE=true
cp build/app/outputs/flutter-apk/app-release.apk salud-digna-simulado.apk

flutter build apk --release --dart-define=MOCK_MODE=false
cp build/app/outputs/flutter-apk/app-release.apk salud-digna-real.apk
```

El APK de release se firma con las claves de depuración
(`android/app/build.gradle.kts`): sirve para instalarlo directamente, no para
publicarlo en una tienda. Los APK no se versionan (`*.apk` está en
`.gitignore`).

### Instalar en un teléfono (pendiente de verificar)

1. En el teléfono, activa las *Opciones de desarrollador* y la *Depuración
   USB*, y conéctalo por USB.
2. Comprueba que aparece con `adb devices` (o `flutter devices`). Usa el `adb`
   del Android SDK que configuraste en Flutter (ver sección 9).
3. Instala, por ejemplo, `adb install -r salud-digna-real.apk`. Con más de un
   dispositivo, añade `-s <serie>`. Después abre *Salud Digna* desde el lanzador.

`flutter run --dart-define-from-file=.env` y `integration_test/app_test.dart`
(recorrido del modo simulado en un dispositivo) están pendientes de verificar.

## 7. Credenciales de prueba

Este README no incluye valores de credenciales.

| Entorno | Qué se necesita | Cómo obtenerlo |
|---------|-----------------|----------------|
| Simulado | Identificador del paciente ficticio y código de verificación | La pantalla de identificación los muestra en *Datos de prueba para la demo*; al tocar un paciente se rellenan. No hay que solicitarlos. |
| Real | Una cuenta de paciente (correo y contraseña), rol `PATIENT`, con perfil de paciente vinculado | Al equipo de backend, por un canal privado. Pendiente de recibir. |

La API key del orquestador nunca va en la app.

## 8. Demo de continuidad omnicanal

### Modo simulado

Los pasos de los canales sitio web y WhatsApp vienen sembrados en el
orquestador simulado; no se ejecutan en esos canales. Todo lo que sigue se
hace en la app (APK simulado).

Estado de verificación: los pasos están cubiertos por las pruebas de widgets
`test/ui_flow_test.dart` y `test/resume_flow_test.dart`, que pasan. La
ejecución en un teléfono está pendiente de verificar.

Preparación: abre **Conexión y demo** (engranaje), comprueba que muestre
*Orquestador simulado* y pulsa *Restablecer escenario de Ana*. Si hay una
sesión abierta, ciérrala con *Cerrar sesión*.

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

### Modo real: sitio web → app → Call Center

**Pendiente de verificar.** Requiere la cuenta de paciente de prueba, que la
integración móvil esté configurada en la API central y un trámite de Web
vinculado a ese paciente. Las pruebas contra la API falsa cubren lo que la app
muestra en los pasos 2 a 4 y el estado *Pendiente de confirmación*. No cubren
que el historial reciba los eventos de `demo-mobile` y `demo-callcenter`: eso
lo hace el servidor. El recorrido con los tres canales reales no se ha
ejecutado.

| Paso | Canal | Qué se hace | Qué debe verse |
|------|-------|-------------|----------------|
| 1 | Sitio web | El paciente inicia un trámite y elige un estudio. Se anota el folio (UUID). | El portal pide la clínica. |
| 2 | App | Entra con la misma cuenta (APK real). | En el inicio, el trámite con el estudio, *Paso: Elegir clínica* y los primeros caracteres del folio. |
| 3 | App | Abre el trámite. | El folio completo coincide con el del sitio web; *Historial entre canales* muestra eventos de `demo-web`. |
| 4 | App | Pulsa *Elige tu clínica* y elige una. | *Paso actual: Revisión*; en el historial, un evento de `demo-mobile`. |
| 5 | Sitio web | Recarga el trámite. | La clínica elegida en la app. |
| 6 | Call Center | Con la autorización del paciente, el asesor abre el mismo trámite y lo deja pendiente de confirmación. | — |
| 7 | App | Vuelve a la app o pulsa *Actualizar*. | Estado *Pendiente de confirmación*; en el historial, un evento de `demo-callcenter`. |

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

**La app simulada no arranca en el estado esperado tras reinstalar.**
`adb install -r` conserva los datos: la sesión y el escenario guardados siguen
vigentes. Cierra sesión y usa *Restablecer escenario de Ana*, o borra los datos
de la app.

**Con la caída simulada no cargan los horarios.** Es lo esperado: también
fallan las lecturas. Para la prueba de resiliencia cambia el estudio o la
clínica.

**Modo real: qué significa cada aviso.** Según `docs/api-mobile-journeys.md`:

| Lo que muestra la app | Código | Qué revisar |
|-----------------------|--------|-------------|
| *Aún no tienes trámites vinculados* | `404` al listar | La identidad institucional del paciente no tiene trámites vinculados. Si debería tenerlos, el equipo de backend debe revisar el vínculo. En una compilación de depuración, el log `[modo real] GET /mobile/journeys → 404` lo distingue de un `200` sin trámites. |
| *Falló la comunicación con el orquestador* o *La integración no está disponible por ahora* | `502` / `503` | Problema de servicio o configuración de la integración móvil en la API central. Es del backend. |
| *El orquestador tardó demasiado* | `504` | Tiempo de espera del orquestador. |
| *Demasiadas solicitudes. Intenta en N s.* | `429` | Límite temporal; esperar los segundos indicados. El acceso comparte hasta 10 intentos por IP cada 15 minutos (`docs/api-auth.md`). |
| *Tu sesión venció* | `401` | Volver a iniciar sesión. |
| *Esta app es solo para cuentas de paciente* | — | La cuenta no es `PATIENT`, no está activa o no tiene perfil de paciente. |
| *La app no está bien configurada* | — | `CHANNEL_BACKEND_URL` no empieza con `https://`. Recompilar. |

## Estructura del proyecto

```
lib/
  main.dart                          arranque: elige el modo según MOCK_MODE
  core/config.dart                   MOCK_MODE y CHANNEL_BACKEND_URL (del compilado)
  core/theme.dart                    sistema visual y modo oscuro
  real/api_models.dart               modelos del contrato de la API central
  real/central_api.dart              cliente HTTP de la API central (solo JWT)
  real/real_state.dart               sesión en memoria, trámites, catálogos y escrituras
  real/ui/                           acceso, inicio, trámite y conexión del modo real
  models/models.dart                 modelos del modo simulado
  data/catalog.dart                  estudios, clínicas y horarios ficticios (simulado)
  services/orchestrator_client.dart  interfaz del orquestador simulado
  services/mock_orchestrator.dart    orquestador simulado
  services/outbox.dart               cola persistente de eventos (simulado)
  services/contact_launcher.dart     WhatsApp y Call Center
  state/app_state.dart               estado del modo simulado
  screens/                           pantallas del modo simulado
  ui/layout/                         diseño adaptable
  widgets/                           componentes compartidos
test/                                pruebas unitarias y de widgets
test/support/fake_central_api.dart   API central falsa para las pruebas
integration_test/                    recorrido del modo simulado en dispositivo
```

Contrato con la API central: [`CONTRATO_API.md`](CONTRATO_API.md). Principios
de diseño de la interfaz: [`UX.md`](UX.md).
