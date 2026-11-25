# Principios de UI/UX aplicados en la app móvil

Guía corta para el equipo y para explicar las decisiones de diseño ante el jurado.

## 1. Una tarea, una acción principal por pantalla

- Cada pantalla tiene un único botón lleno (verde): *Enviar código*, *Continuar*,
  *Comenzar*, *Elige tu estudio* … *Confirma tu cita*. Todo lo demás es secundario
  (tonal, delineado o texto).
- La acción principal del trámite vive fija en la parte inferior, dentro del área
  segura, donde el pulgar llega sin esfuerzo.

## 2. El paciente siempre sabe dónde está

- Barra de progreso de 4 pasos (Estudio → Clínica → Horario → Confirmar) en la
  tarjeta del trámite y en el inicio.
- Estados escritos para personas, no para sistemas: *Recién iniciado*, *En
  progreso*, *Lista para confirmar*, *Confirmada*. El código técnico
  (`PENDIENTE_CONFIRMACION`) sigue existiendo en el contrato, no en la pantalla.
- Fechas relativas (*Mañana, 10:00*) en vez de marcas ISO.

## 3. Continuidad omnicanal visible

- Inicio, en este orden: cabecera, tarjeta del paciente, *Tus citas*,
  *Nueva cita* y *Retomar trámite de otro canal*. Los pendientes se abren desde
  *Retomar*, cada uno con la frase *Lo dejaste en WhatsApp · ayer* y un botón
  que lleva al paso exacto.
- Chips de canal (Sitio Web, WhatsApp, App móvil) y línea de tiempo con
  conectores verticales: se lee como una sola conversación.

## 4. Jerarquía y ritmo visual

- Escala de espaciado de 4/8 dp (`Space`), radios consistentes (`Radii`) y un
  solo esquema de color derivado del logotipo oficial (carpeta `Logo/`):
  verde `#008858` para acciones y estados positivos, gris `#808080` como
  secundario y amarillo `#F8B018` como acento (en texto se oscurece a
  `#B26A00` para cumplir contraste AA). Modo oscuro automático.
- El logotipo real se usa en la pantalla de acceso y como ícono de la app.
- Tipografía con pesos claros: títulos 700, secciones 600, cuerpo 400 con
  interlineado 1.4 para lectura cómoda.
- Tarjetas sin sombra y con fondo tenue: el contenido destaca, no el contenedor.

## 5. Accesibilidad y ergonomía

- Objetivos táctiles de 48 dp o más (botones de 52 dp, filas de lista completas
  tocables, no solo el texto "Elegir").
- Contraste AA: el verde de marca oscuro se usa para texto y acciones sobre
  fondos claros; el claro solo para superficies.
- Etiquetas semánticas en chips de estado y barra de progreso para lectores de
  pantalla; teclado numérico para el código y telefónico para el teléfono.
- Vibración háptica sutil al confirmar y en avisos.

## 6. Estados cuidados

- **Carga**: esqueletos con la forma de las tarjetas, sin saltos de layout.
- **Vacío**: icono, explicación y acción (*Agendar mi primera cita*).
- **Error**: banner no bloqueante con *Reintentar*; si ya había datos, se
  conservan y solo se avisa (información parcial, no pantalla en blanco).
- **Sin conexión**: el cambio queda en cola y el contador en la nube lo muestra.

## 7. Progressive disclosure

- Datos de prueba y detalles técnicos están plegados (*Datos de prueba para la
  demo*, *Información técnica*). Están a un toque, pero no compiten con la tarea.
- El paciente nunca ve el identificador técnico del trámite: solo si tiene
  algo pendiente y en qué paso va. "Retomar trámite de otro canal" (siempre
  visible) abre una ventana deslizable con sus trámites pendientes de todos
  los canales, del más reciente al más antiguo (hoja inferior en vertical,
  panel lateral en horizontal). Al abrirse los vuelve a pedir y muestra
  cargando, error de red con "Reintentar" o "No tienes trámites pendientes".
  No se pide ningún código adicional.
- Sin citas, *Tus citas* muestra "Aún no tienes citas confirmadas" sin botón
  propio: "Nueva cita" está justo debajo.

## 8. Prevención de errores

- Confirmaciones con resumen antes de acciones irreversibles (confirmar cita,
  cancelar trámite, cerrar sesión).
- Mensajes de error en lenguaje claro y con causa (*Faltan datos para confirmar:
  horario*).
- El identificador se bloquea al pedir el código, con un lápiz para corregirlo.

## 9. Diseño adaptable

El layout depende del **espacio disponible**, no de la orientación ni del tipo
de dispositivo. Los puntos de quiebre viven en un solo lugar,
`lib/ui/layout/window_size.dart` (clases de tamaño de Material 3), y las
pantallas solo preguntan `context.windowSize`.

| Clase de tamaño | Regla | Ejemplo típico |
|---|---|---|
| Ancho compacto | < 600 dp | teléfono en vertical |
| Ancho medio | 600 a 839 dp | tableta chica, plegable |
| Ancho expandido | ≥ 840 dp | tableta, teléfono en horizontal |
| Alto compacto | < 480 dp | teléfono en horizontal |

### Qué cambia en cada clase

- **Ancho compacto (vertical)**: una columna a todo el ancho. "Nueva cita" y
  "Retomar trámite de otro canal" van como botones normales después de
  *Tus citas* (sin botón flotante); la acción del trámite va en una barra fija al
  pie en el detalle.
- **Sin botón flotante en ningún tamaño**: en pruebas reales el flotante
  "Nueva cita" tapaba a "Retomar" cuando la lista era larga. Como botón normal
  no tapa nada y el orden es el mismo que en el panel lateral en horizontal.
- **Alto compacto y ancho ≥ 600 dp (teléfono horizontal)**: dos paneles.
  - Inicio: a la izquierda la marca, los accesos (conexión, cerrar sesión),
    la identidad compacta, "Nueva cita" como botón normal y "Retomar trámite
    de otro canal"; a la derecha "Tus citas".
    Sin barra superior, para no gastar altura.
  - Detalle del trámite: a la izquierda el resumen (progreso, estado, cita
    confirmada) con la acción principal **fija al pie del panel**, siempre
    visible; a la derecha los datos del trámite y el historial.
  - Nueva cita: presentación y "Comenzar" a la izquierda, los pasos a la
    derecha.
  - Acceso: presentación a la izquierda y formulario a la derecha.
  - Barra superior compacta (48 dp) donde hay barra.
- **Ancho medio o expandido con alto normal (tableta)**: una columna centrada
  de 640 dp. Se descartaron los dos paneles: el contenido es corto y tiene una
  sola acción principal; dividirlo la separaría de su contexto, y una columna
  de 640 dp mantiene líneas legibles. Título y acciones de la barra superior se
  alinean a la misma columna (`ContentAppBar`).

### Por qué

En horizontal un teléfono tiene ~400 dp de alto: una sola columna apila
identidad, títulos y la tarjeta del trámite y deja la acción principal bajo el
borde. Con dos paneles la acción queda visible sin desplazarse y el ancho
sobrante se aprovecha en lugar de dejar franjas vacías.

### Reglas que se mantienen

- Una sola acción principal por pantalla, siempre visible; ningún elemento
  flotante tapa contenido ni otra acción.
- Áreas seguras en los cuatro lados (en horizontal, la barra de navegación de
  tres botones y el recorte de la cámara quedan a los lados).
- Con el teclado abierto, el formulario de acceso se desplaza para mantener a
  la vista el campo activo y el botón del paso; una barra fija al pie sube con
  el teclado o se oculta mientras se escribe si deja menos de 420 dp útiles.
- Escala de texto del sistema: sin desbordes hasta 200 % en las pantallas
  principales; títulos largos con máximo de líneas y puntos suspensivos.
- En *Tus citas* la clínica se muestra sin el prefijo "Salud Digna" (máximo
  dos líneas); el nombre completo queda en el tooltip y en accesibilidad.
- Al girar, el estado se conserva: las listas usan la misma clave de posición
  en ambos layouts y los formularios no se recrean.

### Componentes

- `lib/ui/layout/window_size.dart`: clases de tamaño y medidas (`LayoutTokens`).
- `lib/ui/layout/adaptive.dart`: `ContentAppBar`, `TwoPaneLayout`,
  `PaneWithPinnedAction`.
- `lib/widgets/patient_blocks.dart`: `IdentityCard`, `PendingJourneyCard`,
  `AppointmentsList`, que las pantallas componen en una o dos columnas.
- `lib/widgets/common.dart`: `ResponsiveBody`, `BottomActionBar`,
  `AdaptiveHeader`, `shortClinicName`.

### Pruebas

`test/responsive_layout_test.dart` monta cada pantalla en 360x800, 412x915,
800x360, 915x412, 600x960 y 1280x800, y en 915x412 con letra al 130 %. En
915x412 verifica que la acción principal se ve completa, que no hay botón
flotante (en Inicio se verifica en todos los tamaños), que ningún control se encima con otro y que al girar no se pierde lo
escrito. `test/layout_test.dart` cubre además letra al 200 % y teclado abierto.

## 10. Ajustes de pantalla (mejoras del 24 nov)

- **Inicio en horizontal, panel plegable**:
  - Panel abierto: no hay barra vertical. La cabecera del panel lleva
    únicamente el logotipo; el control para cerrarlo está en el borde derecho
    del panel, centrado verticalmente.
  - Panel cerrado: aparece una barra vertical estrecha que contiene solo el
    control para abrirlo, a media altura.
  - Conexión y cerrar sesión van en la esquina superior derecha del área
    principal, en la misma fila que el título de la sección. Están anclados al
    borde derecho, así que no se mueven ni cambian de tamaño al abrir o cerrar
    el panel, y respetan el área segura (la barra de navegación de Android
    queda a la derecha en horizontal).
  - Los íconos conservan su tamaño de siempre; en Android su área táctil
    es de 48 dp (comportamiento estándar de Material).
  - El control (48 dp) expone su nombre ("Ocultar panel" / "Mostrar panel") y
    su estado expandido al lector de pantalla, se alcanza con Tab y se activa
    con Enter o Espacio. El foco se ve como un anillo del color primario.
  - La transición dura 180 ms y desaparece si el sistema pide reducir
    animaciones. Abrir y cerrar no recrea el contenido ni pierde la posición.
  - El estado se recuerda durante la sesión. En vertical no existe.
- **Identificación**: logotipo centrado, arriba (sin centrar la pantalla en
  vertical) y con más margen hacia el título "Identifícate".
- **Logotipo** del panel lateral con todo el ancho disponible y margen, sin
  deformarse.
- **Nueva cita**: mensaje formal "Puede quedar pendiente: tu avance se guarda y
  puedes continuar por WhatsApp, en el sitio web o en el Call Center."
- **Selectores** (estudio, clínica, horario): hoja inferior en una columna y
  diálogo centrado en dos columnas, ambos con alto máximo y desplazamiento
  propio; nunca se encima desordenado sobre el contenido.
- **Horarios**: días como chips; por día solo se listan los horarios libres.
  Si un día no tiene horarios, estado vacío con "Ver otro día" y "Cambiar
  clínica". Si el horario elegido se ocupó, la fila lo indica ("Ese horario ya
  no está disponible en esta clínica") y el siguiente paso vuelve a ser
  elegir horario.
- **Historial de atención**: tarjeta plegable, cerrada por omisión, con un
  resumen de una línea ("6 eventos, último hoy 15:49"). La acción principal y
  la cita confirmada quedan siempre por encima.
- **Filas del trámite con letra grande**: si el ancho no alcanza para la escala
  de letra, "Elegir/Cambiar" pasa a un ícono de flecha para no dejar sin
  espacio al valor; la fila completa sigue siendo tocable.
