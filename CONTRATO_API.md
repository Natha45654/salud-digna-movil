# Contrato entre la app móvil y el backend del canal

> Actualizado el 24 nov 2026 según `CONTEXTO ACTUALIZADO.txt`.
>
> La app **no habla directo con el orquestador**. Por la decisión 4 (la API key
> del orquestador nunca va en una app móvil), la app consume este contrato
> expuesto por `mobile_channel_backend/`, y ese backend traduce al contrato real
> del orquestador (`POST /journeys`, `POST /events` con `JOURNEY_CONTEXT_UPDATED`
> y `JOURNEY_STATUS_CHANGED`, `GET /journeys/:id`, `/context`, `/history`,
> cabeceras de API key y `X-Journey-Grant`).
>
> ```
> App Flutter ──este contrato──▶ mobile_channel_backend ──contrato real──▶ Orquestador
> ```
>
> El orquestador simulado dentro de la app (`lib/services/mock_orchestrator.dart`)
> implementa este mismo contrato para demostrar sin red.

## Cabeceras en toda solicitud

| Cabecera          | Valor                        | Propósito                                  |
|-------------------|------------------------------|--------------------------------------------|
| `X-Channel-Id`    | `MOBILE_APP`                 | Identifica la aplicación (ChannelIntegration) |
| `X-Channel-Key`   | clave configurada en la app  | Autenticación de la aplicación             |
| `X-Request-Id`    | UUID por solicitud           | Identificador de solicitud para auditoría  |
| `Idempotency-Key` | igual al `eventId`           | Solo en `POST /integrations/events`        |
| `Authorization`   | `Bearer <token de paciente>` | Tras verificar identidad                   |

## 1. `POST /api/v1/identity/verify`

Verifica la identidad del paciente con identificadores tipados y un OTP.
No está en la tabla de la sección 5 del documento, pero la sección 6 exige que
"recibir un teléfono o CURP no prueba por sí solo la identidad".

Solicitud:

```json
{
  "channel": "MOBILE_APP",
  "patientIdentifiers": [{ "type": "PATIENT_ID", "value": "SD-123456" }],
  "otp": "123456"
}
```

Respuesta `200`:

```json
{
  "patientRef": "PAT-0001",
  "displayName": "Ana García",
  "token": "<jwt o token opaco>",
  "verificationLevel": "VERIFIED",
  "identifiers": [
    { "type": "PATIENT_ID", "value": "SD-123456" },
    { "type": "PHONE", "value": "+525512345678" }
  ]
}
```

Errores: `404 PATIENT_NOT_FOUND` (sin coincidencia única), `401 INVALID_OTP`.

## 2. `POST /api/v1/integrations/events`

Registra un evento canónico (sección 8). La app agrega `expectedVersion` para
el control optimista de concurrencia (sección 12).

```json
{
  "eventId": "app-5f1c…",
  "sourceSystem": "MOBILE_APP",
  "patientIdentifiers": [{ "type": "PATIENT_ID", "value": "SD-123456" }],
  "journeyId": "ATN-2026-001",
  "eventType": "CLINIC_SELECTED",
  "occurredAt": "2026-11-23T18:00:00.000",
  "data": { "clinicId": "CLI-012", "clinicName": "Salud Digna Guadalajara Centro", "city": "Guadalajara" },
  "expectedVersion": 5
}
```

Respuesta `200` / `201`:

```json
{ "accepted": true, "duplicate": false, "journeyId": "ATN-2026-001", "version": 6, "status": "PENDIENTE_CONFIRMACION" }
```

Reglas que la app asume:

- **Idempotencia**: un `eventId` repetido responde `200` con `duplicate: true`
  y la versión vigente, sin crear un segundo evento.
- **Concurrencia**: si `expectedVersion` no coincide, responder
  `409 VERSION_CONFLICT`. La app recarga el contexto y muestra el mensaje.
- **Transiciones**: `422 INVALID_TRANSITION` con mensaje legible cuando el
  evento no aplica (p. ej. confirmar sin horario, modificar un trámite cerrado).
- **Autorización**: `403 FORBIDDEN` si el paciente del token no es el dueño
  del trámite; `401` si el token no es válido.
- `JOURNEY_STARTED` sin `journeyId` crea el trámite; el orquestador asigna el
  id y lo devuelve en `journeyId`.
- Al recibir `CONFIRMATION_REQUESTED`, el sistema autorizado de citas emite
  `APPOINTMENT_CONFIRMED` (en el simulador lo hace el propio orquestador con
  `sourceSystem: APPOINTMENT_SYSTEM`). La app nunca emite
  `APPOINTMENT_CONFIRMED` por sí misma: la confirmación real pertenece al
  sistema oficial (sección 7, último párrafo).

Códigos de red (`5xx`, timeout, sin conexión) hacen que el evento quede en el
outbox local y se reintente. Los `4xx` se descartan y se informan.

## 3. `GET /api/v1/me/journeys?status=open|closed|all`

Devuelve los trámites del paciente de la **sesión verificada**. El cliente no
envía ningún identificador de paciente: el servidor lo resuelve a partir del
token de sesión y filtra por él (si el cliente pudiera pedir por id, cualquiera
leería los de otra persona). Sin sesión válida: `401` y la app regresa a la
identificación. `status=open` devuelve los pendientes de todos los canales;
`closed`, los confirmados o cancelados. Acepta arreglo plano o
`{ "journeys": [...] }`.

Reemplaza a `GET /api/v1/patients/{patientRef}/journeys`, que se eliminó.

### Reanudación

Al continuar un trámite pendiente la app envía, con la versión del contexto:

- `REQUEST_RESUMED` con `{ "fromChannel": "WHATSAPP", "toChannel": "MOBILE_APP" }`.
- `CHANNEL_SWITCHED` con los mismos datos, si el canal de origen es otro.

Como el orquestador solo admite `JOURNEY_CONTEXT_UPDATED` y
`JOURNEY_STATUS_CHANGED`, el backend del canal los registra como
`JOURNEY_CONTEXT_UPDATED` con `{ "context": { "resume": { "type", "fromChannel",
"toChannel" } } }` hasta que el orquestador acepte los tipos nuevos.

### Contacto con Salud Digna

En el detalle del trámite, "¿Necesitas ayuda?" abre WhatsApp (`https://wa.me/...`)
o el marcador del teléfono (`tel:`, no llama solo). Antes de abrirlos, si el
trámite está abierto, la app envía con la versión del contexto:

- `CONTACT_INITIATED` con `{ "channel": "WHATSAPP" | "CALL_CENTER", "step": "<nextStep.code>" }`.

Así el asesor ve de dónde viene el paciente y en qué paso va. El backend del
canal lo registra como `JOURNEY_CONTEXT_UPDATED` con
`{ "context": { "contact": { "channel", "step" } } }`. En un trámite cerrado
(el orquestador no admite cambios) solo se abre el canal, sin evento. Si el
registro falla, el contacto se abre de todas formas. Los números de la demo son
ficticios y se fijan al compilar con `--dart-define=SD_WHATSAPP` y `SD_CALL_CENTER`.

## 4. `GET /api/v1/journeys/{journeyId}`

Proyección de contexto (Journey + JourneyContext):

```json
{
  "journeyId": "ATN-2026-001",
  "patientRef": "PAT-0001",
  "type": "APPOINTMENT_BOOKING",
  "status": "PENDIENTE_CONFIRMACION",
  "version": 5,
  "lastChannel": "WHATSAPP",
  "updatedAt": "2026-11-23T15:03:00.000",
  "channels": ["WEB", "WHATSAPP"],
  "context": {
    "study":  { "studyId": "STD-001", "studyName": "Ultrasonido abdominal", "price": 350 },
    "clinic": { "clinicId": "CLI-012", "clinicName": "Salud Digna Guadalajara Centro" },
    "slot":   { "slotStart": "2026-11-24T10:00:00.000" },
    "appointment": { "appointmentId": "CITA-1A2B3C4D" }
  },
  "pendingFields": [],
  "nextStep": { "code": "CONFIRM_APPOINTMENT", "label": "Confirma tu cita" }
}
```

Valores de `nextStep.code` que la app sabe ejecutar: `SELECT_STUDY`,
`SELECT_CLINIC`, `SELECT_SLOT`, `CONFIRM_APPOINTMENT`, `VIEW_APPOINTMENT`.

## 5. `GET /api/v1/journeys/{journeyId}/events`

Cronología inmutable, en orden ascendente. Acepta arreglo plano o
`{ "events": [...] }`. Cada elemento tiene la forma del evento canónico.
El backend del canal la construye a partir de `/history` del orquestador.

## 6. `POST /api/v1/journeys/link`

Traspaso manual de permisos entre canales (limitación conocida de la demo).
El paciente escribe el **código de acceso** que le dio otro canal; nunca ve el
identificador del trámite. El código es `base64url("journeyId:grant")` y lo
genera el canal que entrega el permiso. El backend lo decodifica, valida el
permiso contra el orquestador y vincula el trámite a la cuenta.

```json
{ "code": "NmYxYy11dWlkOmdyYW50LS4uLg" }
```

Respuesta `200`: `{ "linked": true }`. Errores: `400` si el código no se puede
decodificar, `403` si el permiso no corresponde o el trámite es de otro
paciente, `404` si no existe. En el simulador de la app, el código de demo
puede ser el propio id del trámite.

## 7. `GET /api/v1/journeys/{journeyId}/availability?clinicId=CLI-012`

Horarios **libres** para el trámite en esa clínica. Los ocupados no se
devuelven (ni siquiera deshabilitados). Un horario se identifica por
clínica + fecha + hora.

```json
{ "clinicId": "CLI-012", "slots": ["2026-11-25T08:00:00.000", "2026-11-25T10:00:00.000"] }
```

> **Comportamiento de demo.** La autoridad real de la disponibilidad es el
> sistema de citas de Salud Digna. El backend del canal (y el simulador de la
> app) llevan un registro mínimo para demostrar la regla. No cambia el
> contrato con el orquestador: sigue usando solo `JOURNEY_CONTEXT_UPDATED` y
> `JOURNEY_STATUS_CHANGED`.

Reglas, siempre del lado del servidor (compiten varios canales):

- Una cita confirmada ocupa su horario. Al **cancelarla**, el horario vuelve a
  quedar disponible para otros pacientes.
- Al **elegir** horario (`SLOT_SELECTED`) y al **confirmar**
  (`CONFIRMATION_REQUESTED`) se revalida. Si otro paciente ya lo tomó:

  ```json
  { "statusCode": 409, "code": "SLOT_UNAVAILABLE",
    "message": "Ese horario ya no está disponible en esta clínica" }
  ```

  No se aplica ningún cambio: el trámite queda como estaba, sin folio.
- La misma revalidación aplica cuando la confirmación llega tarde desde el
  outbox de la app tras una caída: no se confirma a ciegas.
- En `GET /journeys/{id}`, si el horario elegido ya no está disponible, la
  proyección trae `context.slotUnavailable: true`, estado `EN_CAPTURA` y
  `nextStep.code = SELECT_SLOT`, para que la app pida elegir otro.
