# Contrato entre la app móvil y la API central

Fuente: `docs/openapi.json` de la rama `main` de `jangeltr/salud-digna`
(repositorio del equipo, acceso restringido), contrastado con
`docs/api-auth.md`, `docs/api-mobile-journeys.md`, `docs/api-studies.md` y
`docs/api-clinics.md` del mismo repositorio. Si este documento y el OpenAPI no
coinciden, manda el OpenAPI.

**Estado: nada de lo descrito aquí se ha probado contra la API de
producción.** El cliente (`lib/real/`) se probó contra una API falsa construida
a partir de esa documentación (`test/support/fake_central_api.dart`).

```
App Flutter ──JWT del paciente──▶ API central ──API key del canal + permisos──▶ Orquestador
```

La app solo maneja el JWT del paciente. La API central firma la afirmación
institucional con el canal `demo-mobile`, obtiene el permiso de cada trámite y
usa su propia API key. La app **no** envía `X-Channel-Key`, `X-Journey-Grant`
ni encabezados de afirmación, y no guarda ninguna credencial de integración.

El modo simulado (`MOCK_MODE=true`) no usa este contrato: corre un orquestador
en el dispositivo (`lib/services/mock_orchestrator.dart`).

## Conexión

- URL base: `https://api.salud-digna.app/api/v1`. En la app se configura el
  origen sin `/api/v1` (`CHANNEL_BACKEND_URL`) y el cliente añade el prefijo.
- Solo HTTPS. El manifiesto de Android prohíbe el tráfico en claro.
- Cuerpos JSON con `Content-Type: application/json`. Las operaciones con
  seguridad `bearer` llevan `Authorization: Bearer <accessToken>`.

## Operaciones que usa la app

| Método | Ruta (relativa a `/api/v1`) | Autenticación | Uso en la app |
|--------|-----------------------------|---------------|---------------|
| `POST` | `/auth/login` | Pública | Inicio de sesión |
| `GET` | `/auth/me` | Bearer | Rol, cuenta activa y `patientId` |
| `GET` | `/mobile/journeys` | Bearer | Trámites activos del paciente |
| `POST` | `/mobile/journeys` | Bearer + `Idempotency-Key` | Nueva cita |
| `GET` | `/mobile/journeys/{journeyId}` | Bearer | Estado del trámite |
| `GET` | `/mobile/journeys/{journeyId}/context` | Bearer | Paso, versión y referencias |
| `GET` | `/mobile/journeys/{journeyId}/history` | Bearer | Historial entre canales |
| `POST` | `/mobile/journeys/{journeyId}/events` | Bearer | Elegir estudio o clínica, enviar a confirmación, cancelar |
| `GET` | `/studies` | Pública | Catálogo de estudios |
| `GET` | `/studies/{id}` | Pública | Estudio fuera del catálogo cargado |
| `GET` | `/clinics` | Pública | Catálogo de clínicas |
| `GET` | `/clinics/{id}` | Pública | Clínica fuera del catálogo cargado |

## Autenticación

### `POST /auth/login`

Cuerpo (`LoginDto`): `email` (correo, hasta 254) y `password` (hasta 128).

Respuesta `200` (`LoginResponseDto`):

| Campo | Tipo |
|-------|------|
| `accessToken` | string (JWT) |
| `tokenType` | `"Bearer"` |
| `expiresIn` | número, en segundos |
| `user` | `PublicUserDto`: `id` (UUID de la cuenta), `email`, `role` (`PATIENT`, `ADVISOR` o `ADMIN`) |

Errores documentados: `400`, `401` (credenciales incorrectas, cuenta ausente o
inactiva, con el mismo mensaje) y `429` con `Retry-After` en segundos.

### `GET /auth/me`

Respuesta `200` (`AccountDto`): `id`, `email`, `role`, `isActive`, `patientId`
(UUID o `null`) y `patient` (`PatientProfileDto` o `null`: `id`, `firstName`,
`lastName`, `email` o `null`, `phone` o `null`). Error documentado: `401`.

Reglas que aplica la app:

- Solo acepta `tokenType: "Bearer"`, rol `PATIENT`, `isActive: true` y
  `patientId` distinto de `null`. El identificador del paciente es `patientId`,
  no el `id` de la cuenta.
- El JWT vive solo en memoria y se da por vencido 30 s antes de `expiresIn`.
  No hay *refresh token* (`docs/api-auth.md`): al vencer, se vuelve a iniciar
  sesión.

## Trámites (`/mobile/journeys`)

Todas usan Bearer. Errores documentados en el OpenAPI para estas rutas: `400`,
`401`, `403`, `404`, `429`, `502`, `503`, `504`, y además `409` en las dos
operaciones `POST`.

### `GET /mobile/journeys`

`200` (`MobileJourneyListDto`): `items`, lista de `MobileJourneySummaryDto`.
Hasta 100 trámites activos, del más reciente al más antiguo
(`docs/api-mobile-journeys.md`).

`404` cubre una identidad institucional todavía sin vínculo. La app lo muestra
como «Aún no tienes trámites vinculados» y lo registra en el log de depuración
de forma distinta a un `200` sin trámites.

### `MobileJourneySummaryDto`

Respuesta de `GET /mobile/journeys/{journeyId}` y elemento de la lista.

| Campo | Tipo |
|-------|------|
| `id` | UUID |
| `type` | string, por ejemplo `APPOINTMENT` |
| `status` | `DRAFT`, `IN_PROGRESS`, `PENDING_CONFIRMATION`, `COMPLETED` o `CANCELLED` |
| `createdAt`, `updatedAt` | fecha y hora ISO 8601 |

### `POST /mobile/journeys`

- Encabezado obligatorio `Idempotency-Key`: 32 bytes aleatorios en base64url
  sin relleno (43 caracteres). Un reintento de la misma creación reusa la
  clave; una creación nueva usa otra.
- Cuerpo (`CreateMobileJourneyDto`): `{"type":"APPOINTMENT"}`.
- `201` (`MobileJourneyCreatedDto`): `id` y `status`.
- `409`: conflicto de idempotencia.

### `GET /mobile/journeys/{journeyId}/context`

`200` (`MobileJourneyContextDto`):

| Campo | Tipo |
|-------|------|
| `journeyId` | UUID |
| `currentStep` | string; la app reconoce `SELECT_STUDY`, `SELECT_CLINIC`, `SELECT_DATETIME`, `REVIEW` y `CONFIRMED` |
| `version` | entero ≥ 1 |
| `externalRefs` | `MobileExternalRefsDto`: `studyId`, `clinicId` y `appointmentId`, todos UUID opcionales |
| `updatedAt` | fecha y hora ISO 8601 |

La app muestra los nombres y precios buscando `studyId` y `clinicId` en los
catálogos. No completa campos ausentes.

### `GET /mobile/journeys/{journeyId}/history`

Parámetros: `limit` (1 a 100, por omisión 20) y `cursor` (el `nextCursor`
anterior, hasta 200 caracteres `[A-Za-z0-9_-]`).

`200` (`MobileJourneyHistoryDto`): `items` y `nextCursor`, que solo llega si hay
otra página. Cada elemento (`MobileHistoryItemDto`):

| Campo | Tipo |
|-------|------|
| `id` | UUID |
| `type` | string, por ejemplo `JOURNEY_CREATED`, `JOURNEY_CONTEXT_UPDATED` o `JOURNEY_STATUS_CHANGED` |
| `producerCode` | canal que registró el evento, por ejemplo `demo-web`, `demo-mobile` o `demo-callcenter` |
| `occurredAt`, `receivedAt` | fecha y hora ISO 8601 |
| `schemaVersion` | entero ≥ 1 |
| `data` | `MobileHistoryDataDto`: `version`, `currentStep`, `from` y `to`, todos opcionales |

Orden ascendente por `occurredAt` (`docs/api-mobile-journeys.md`). La app
muestra el `producerCode` tal como llega, junto a un nombre legible.

### `POST /mobile/journeys/{journeyId}/events`

Cuerpo (`PublishMobileEventDto`):

| Campo | Valor |
|-------|-------|
| `externalEventId` | Opaco, hasta 128 caracteres, `^(?!system:)[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$`. La app usa `app-<UUID v4>` |
| `type` | `JOURNEY_CONTEXT_UPDATED` o `JOURNEY_STATUS_CHANGED` |
| `schemaVersion` | `1` |
| `occurredAt` | UTC con milisegundos, por ejemplo `2026-11-25T15:30:00.000Z` |
| `payload` | `MobileEventPayloadDto`: `expectedVersion` (obligatorio, la `version` vigente del contexto) y además `studyId`, `clinicId` o `to` (`PENDING_CONFIRMATION` o `CANCELLED`) |

Usos en la app:

| Acción | `type` | `payload` |
|--------|--------|-----------|
| Elegir estudio | `JOURNEY_CONTEXT_UPDATED` | `expectedVersion`, `studyId` |
| Elegir clínica | `JOURNEY_CONTEXT_UPDATED` | `expectedVersion`, `clinicId` |
| Enviar a confirmación | `JOURNEY_STATUS_CHANGED` | `expectedVersion`, `to: "PENDING_CONFIRMATION"` |
| Cancelar | `JOURNEY_STATUS_CHANGED` | `expectedVersion`, `to: "CANCELLED"` |

`201` (`MobileEventReceiptDto`): `id` (UUID del evento) y `journeyId`. Después de
publicar, la app vuelve a leer el contexto.

Reglas del orquestador (`apps/orchestrator/docs/journey-writes.md`): la
clínica requiere un estudio previo, y cambiar de estudio borra la clínica.
`PENDING_CONFIRMATION` requiere `IN_PROGRESS` con estudio y clínica.
`CANCELLED` se admite desde un estado abierto. `409` indica versión obsoleta,
transición inválida o un `externalEventId` reutilizado con otro contenido.

## Catálogos

`GET /studies` y `GET /clinics` aceptan `page` (1 a 10 000), `limit` (1 a 100)
y `q`. La app pide `limit=100` y recorre las páginas mientras `hasMore` sea
`true`.

| Esquema | Campos |
|---------|--------|
| `StudyPageDto` / `ClinicPageDto` | `page`, `limit`, `hasMore`, `items` |
| `StudyDto` | `id`, `name`, `description` (puede ser `null`), `price` (cadena `^[0-9]+\.[0-9]{2}$`), `isActive` |
| `ClinicDto` | `id`, `name`, `address`, `city`, `state`, `isActive` |

El precio se conserva como cadena y se muestra sin convertirlo a número
(«$120.00 MXN»). `GET /studies/{id}` y `GET /clinics/{id}` responden `404` si el
registro no existe o está inactivo; la app lo recuerda y muestra «no
disponible en el catálogo».

## Cómo responde la app a cada código

| Código | Lectura | Escritura (evento o creación) |
|--------|---------|-------------------------------|
| `400` | Mensaje del servidor | Se descarta, sin reintento |
| `401` | Regresa al acceso con «Tu sesión venció» | Igual; el cambio se conserva para la misma cuenta |
| `403` | «Tu cuenta no tiene autorización…» | Se descarta |
| `404` | Al listar: «Aún no tienes trámites vinculados». En otras lecturas: no disponible | Se descarta |
| `409` | — | Se descarta, se relee el contexto y se avisa que cambió en otro canal |
| `429` | Aviso con los segundos de `Retry-After` | Si `Retry-After` ≤ 10 s, espera y reintenta. Si es mayor, queda pendiente hasta esa hora |
| `502`, `503`, `504` | Aviso con «Reintentar» | Hasta 3 intentos (esperas de 1 s y 2 s). Después queda pendiente |
| Sin red o tiempo de espera | Aviso con «Reintentar» | Igual que `5xx` |

Un reintento envía exactamente el mismo cuerpo (mismo `externalEventId`,
`occurredAt` y `expectedVersion`) o la misma `Idempotency-Key`. Los cambios
pendientes viven solo en memoria, separados por cuenta y URL. Se pierden al
cerrar la app y se descartan al cerrar sesión.

## Fuera del alcance de la API para el canal móvil

No hay operaciones móviles para horarios disponibles, confirmación de cita ni
registro de contactos. La app los muestra deshabilitados y explicados. El
trámite llega hasta `PENDING_CONFIRMATION`.
