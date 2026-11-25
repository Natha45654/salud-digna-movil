# Salud Digna · App móvil (canal MOBILE_APP)

App Flutter del canal **MOBILE_APP** para el reto *Software Inteligente* de
Salud Digna (Hackatec): un **orquestador omnicanal** que permite al paciente
iniciar un trámite en un canal (Web, WhatsApp, Call Center) y continuarlo en
otro sin repetir información.

La app identifica al paciente, le muestra sus trámites pendientes con el
contexto que dejó en otros canales, le permite retomarlos o iniciar uno nuevo
y notifica cada paso al orquestador como evento de negocio.

## Cómo se relaciona con el resto del sistema

```
App Flutter (este repositorio)
   │  contrato app ↔ backend (CONTRATO_API.md)
   │  cabeceras: X-Channel-Key, Authorization: Bearer <token de paciente>
   ▼
Backend del canal móvil (mobile_channel_backend, repositorio aparte)
   │  guarda la API key del orquestador y traduce los eventos de la app
   ▼
Orquestador omnicanal (servicio del equipo, acceso con API key privada)
```

- **La app nunca contiene la API key del orquestador.** Solo conoce la URL y la
  clave de canal de *su* backend; ese backend es quien firma las llamadas al
  orquestador.
- La app incluye además un **orquestador simulado** que implementa el mismo
  contrato dentro del dispositivo. Con él la demo funciona sin backend.
- Opcionalmente, el botón "¿Necesitas ayuda?" puede abrir el simulador de
  WhatsApp del equipo (esquema `saluddigna-wa://`) en lugar de WhatsApp real.

| Pilar del reto    | Cómo lo cubre la app                                                                 |
|-------------------|--------------------------------------------------------------------------------------|
| Identidad         | Identificadores tipados (`PATIENT_ID`, `PHONE`, `EMAIL`) + código de verificación     |
| Contexto y estado | Recupera estudio, clínica y horario elegidos en otro canal; muestra el siguiente paso |
| Trazabilidad      | Línea de tiempo unificada por canal; emite `CONTEXT_RESUMED` al retomar               |
| Seguridad         | Token de paciente, clave de canal, aislamiento entre pacientes, datos mínimos         |
| Resiliencia       | Outbox persistente con reintentos; idempotencia por `eventId`; control de versión     |

## Requisitos

- **Flutter 3.47** o superior (Dart 3.13). Comprueba con `flutter doctor`.
- **Android SDK** con un emulador o un teléfono con depuración USB.
- JDK 17 (el que incluye Android Studio sirve).
- Opcional, para el modo con backend: el backend del canal móvil en ejecución
  y `adb` para conectar un teléfono por USB.

## Instalación

```bash
git clone https://github.com/Natha45654/salud-digna-movil.git
cd salud-digna-movil
flutter pub get
cp .env.example .env        # en PowerShell: Copy-Item .env.example .env
```

## Variables de entorno

La configuración se lee al compilar desde `.env` con
`--dart-define-from-file=.env`. El archivo `.env` **no se versiona**;
`.env.example` lista todas las variables. Una variable vacía equivale a no
definida.

| Variable              | Para qué sirve                                                                       | Si se deja vacía            |
|-----------------------|--------------------------------------------------------------------------------------|-----------------------------|
| `MOCK_MODE`           | `true`: orquestador simulado en el dispositivo. `false`: usa el backend.            | `true`                      |
| `CHANNEL_BACKEND_URL` | URL base del backend del canal móvil, sin `/` final.                                | Se configura en la app      |
| `CHANNEL_KEY`         | Clave de canal (`X-Channel-Key`). Debe coincidir con `APP_CHANNEL_KEY` del backend. | Se configura en la app      |
| `WHATSAPP_SIMULATOR`  | `true`: "¿Necesitas ayuda?" abre el simulador de WhatsApp del equipo.               | `false` (WhatsApp real)     |
| `SD_WHATSAPP`         | Número de WhatsApp de contacto, solo dígitos con lada (`52` + 10 dígitos).          | Abre WhatsApp sin número    |
| `SD_CALL_CENTER`      | Número del Call Center, solo dígitos.                                                | Abre el marcador sin número |

La URL y la clave también se pueden cambiar en la app, en **Conexión y demo**
(icono de engranaje en la pantalla de identificación). Lo que se guarde ahí
tiene prioridad sobre `.env` hasta que se borren los datos de la app.

## Ejecutar y compilar

```bash
flutter run --dart-define-from-file=.env
```

**APK de depuración:**

```bash
flutter build apk --debug --dart-define-from-file=.env
```

El APK queda en `build/app/outputs/flutter-apk/app-debug.apk`. Para instalarlo
en un teléfono conectado:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**Pruebas:**

```bash
flutter analyze
flutter test                                   # reglas del orquestador simulado y diseño adaptable
flutter test integration_test/app_test.dart    # en un dispositivo; desinstala la app al terminar
```

## Apuntar la app a la API

Por omisión (`MOCK_MODE` vacío o `true`) la app no necesita ningún servidor.
Para usar el backend del canal móvil:

1. Arranca el backend del canal móvil siguiendo su README (por omisión escucha
   en el puerto `3300`).
2. En `.env`, define `MOCK_MODE=false`, `CHANNEL_BACKEND_URL` y `CHANNEL_KEY`.
3. Elige la URL según dónde corre la app:

   | La app corre en…               | `CHANNEL_BACKEND_URL`                                                     |
   |--------------------------------|---------------------------------------------------------------------------|
   | Emulador Android               | `http://10.0.2.2:<puerto>` (así ve el emulador a tu PC)                   |
   | Teléfono por USB               | `http://127.0.0.1:<puerto>` tras `adb reverse tcp:<puerto> tcp:<puerto>`  |
   | Teléfono en la misma red Wi-Fi | `http://<IP de tu PC>:<puerto>`                                           |
   | Backend desplegado             | `https://<dominio del backend>`                                           |

   Con `adb reverse` usa `127.0.0.1`, no `localhost`: en Android, `localhost`
   puede resolver a IPv6 y el túnel es IPv4.
4. Vuelve a compilar con `--dart-define-from-file=.env`.

El contrato que la app espera del backend está en
[`CONTRATO_API.md`](CONTRATO_API.md).

## Credenciales de prueba

Los pacientes son **ficticios**; la app no contiene datos reales. Este README
no incluye valores de credenciales. Hacen falta:

| Credencial                                   | Dónde se usa                        | Dónde obtenerla                                       |
|----------------------------------------------|-------------------------------------|-------------------------------------------------------|
| Identificador de un paciente de prueba (número de paciente, teléfono o correo) | Identificación, paso 1 | Ver abajo                                   |
| Código de verificación (OTP) de ese paciente | Identificación, paso 2              | Ver abajo                                             |
| Clave de canal (`CHANNEL_KEY`)               | Solo en modo backend                | La misma que `APP_CHANNEL_KEY` del backend del canal  |
| API key del orquestador                      | **Nunca en la app**; solo en el backend del canal | Responsable del orquestador en el equipo |

- **Modo simulado:** la pantalla de identificación muestra la sección
  *Datos de prueba para la demo* con los dos pacientes ficticios. Al tocar uno
  se rellenan su identificador y su código.
- **Modo backend:** los pacientes de prueba son los que tenga sembrados el
  backend del canal móvil (consulta su README).
- **Jurado:** pendiente de definir cómo se entregan las credenciales.
  <!-- TODO: indicar el medio de entrega (p. ej. formulario de entrega del reto). No escribir los valores aquí. -->

| Paciente ficticio | Escenario                                                            |
|-------------------|----------------------------------------------------------------------|
| Ana García        | Tiene un trámite pendiente iniciado en Web y continuado en WhatsApp  |
| Luis Hernández    | No tiene trámites; inicia uno nuevo desde la app                     |

## Reproducir la demo

Funciona en modo simulado, sin backend.

1. Compila e instala el APK de depuración (ver arriba) con `MOCK_MODE` vacío
   o en `true`.
2. **Identidad.** En *Datos de prueba para la demo*, toca a Ana, pulsa
   *Enviar código* y luego *Continuar*. Un código incorrecto se rechaza.
3. **Contexto.** En Inicio, pulsa *Retomar trámite de otro canal*: aparecen el
   estudio, la clínica y el canal donde lo dejó.
4. **Trazabilidad.** Abre el trámite: se ven el contexto completo y el
   historial con los eventos de Web y WhatsApp. La app registra
   `CONTEXT_RESUMED`.
5. **Continuidad.** Pulsa *Confirma tu cita*: el trámite pasa a cita
   confirmada con su folio.
6. **Resiliencia.** En *Conexión y demo* activa *Simular caída del
   orquestador* y haz un cambio en un trámite abierto: el evento queda en la
   cola con su error. Desactiva la caída y pulsa *Reenviar*: se entrega una
   sola vez.
7. **Autorización.** Cierra sesión e identifícate como Luis: no ve el trámite
   de Ana. Puede iniciar uno nuevo desde *Agenda un estudio*.
8. Para repetir la demo: *Conexión y demo* → *Restablecer escenario de Ana*.

## Estructura

```
lib/
  main.dart                          arranque, tema, inyección de estado
  core/config.dart                   URL, clave de canal y modo (variables de entorno + ajustes)
  core/theme.dart                    sistema visual: color, forma, espaciado, modo oscuro
  models/models.dart                 contrato: evento canónico, trámite, estados, errores
  data/catalog.dart                  estudios, clínicas y horarios ficticios
  services/orchestrator_client.dart  interfaz común de los dos orquestadores
  services/http_orchestrator.dart    cliente HTTP hacia el backend del canal
  services/mock_orchestrator.dart    orquestador simulado con las reglas de negocio
  services/outbox.dart               cola persistente de eventos con reintentos
  services/contact_launcher.dart     WhatsApp / Call Center
  state/app_state.dart               sesión, trámites, construcción y envío de eventos
  screens/                           identificación, inicio, trámite, nueva cita, conexión
  ui/layout/                         clases de tamaño de ventana y diseño adaptable
  widgets/                           bloques de paciente y componentes comunes
test/                                pruebas unitarias y de widgets
integration_test/                    recorrido completo en dispositivo
```

Los principios de UI/UX aplicados están en [`UX.md`](UX.md).
