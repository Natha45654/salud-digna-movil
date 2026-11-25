import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../ui/layout/adaptive.dart';
import '../ui/layout/window_size.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

/// Identificación y verificación del paciente (pilar 1: Identidad).
///
/// UX: dos pasos visibles (identificador → código), un solo botón principal
/// por paso, teclado adecuado a cada campo y la información de demo plegada
/// para no competir con la tarea principal.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const logoKey = ValueKey<String>('login-logo');

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  // Botón del paso actual ("Enviar código" o "Continuar"): se mantiene
  // visible cuando el teclado reduce la altura (por ejemplo, en horizontal).
  final _actionKey = GlobalKey();
  final _value = TextEditingController();
  final _otp = TextEditingController();
  final _otpFocus = FocusNode();
  String _type = 'PATIENT_ID';
  bool _busy = false;
  bool _otpSent = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Solo en modo simulado: precarga al paciente de demostración. Con el
  /// orquestador real los campos empiezan vacíos.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    if (AppScope.of(context).config.mockMode) {
      _value.text = 'SD-123456';
      _otp.text = '123456';
    }
  }

  /// El teclado cambia las métricas de la ventana: al abrirse, desplaza el
  /// formulario para que el campo activo y el botón del paso queden visibles.
  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _actionKey.currentContext;
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      if (ctx == null || !keyboardOpen) return;
      if (FocusManager.instance.primaryFocus?.context == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _value.dispose();
    _otp.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _sendCode() {
    if (_value.text.trim().isEmpty) {
      _form.currentState!.validate();
      return;
    }
    setState(() => _otpSent = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _otpFocus.requestFocus());
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final state = AppScope.of(context);
    try {
      await state.login(
        identifiers: [PatientIdentifier(type: _type, value: _value.text.trim())],
        otp: _otp.text.trim(),
      );
    } on OrchestratorException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } on NetworkException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    final ws = context.windowSize;

    // Presentación: marca, título y para qué sirve.
    final intro = <Widget>[
      // Logotipo centrado, con más aire hacia el título.
      const Center(
        key: LoginScreen.logoKey,
        child: FittedBox(fit: BoxFit.scaleDown, child: BrandLogo(height: 56)),
      ),
      SizedBox(height: ws.isHeightCompact ? Space.xl : Space.xxl),
      Text('Identifícate', style: t.titleLarge),
      const SizedBox(height: Space.xs),
      Text(
        'Usa el mismo dato con el que te atendieron en otro canal. '
        'Recuperaremos tu trámite donde lo dejaste.',
        style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
      ),
    ];

    final privacy = Row(
      children: [
        Icon(Icons.lock_outline, size: 14, color: s.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Verificamos tu identidad antes de mostrar cualquier dato.',
            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
          ),
        ),
      ],
    );

    // Formulario: los dos pasos y su único botón principal.
    final form = <Widget>[
      _StepHeader(number: 1, label: 'Tu identificador', active: !_otpSent),
      const SizedBox(height: Space.sm),
      DropdownButtonFormField<String>(
        initialValue: _type,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tipo de identificador'),
        items: const [
          DropdownMenuItem(value: 'PATIENT_ID', child: Text('Número de paciente')),
          DropdownMenuItem(value: 'PHONE', child: Text('Teléfono')),
          DropdownMenuItem(value: 'EMAIL', child: Text('Correo electrónico')),
        ],
        onChanged: _otpSent
            ? null
            : (v) => setState(() {
                  _type = v!;
                  _value.text = switch (v) {
                    'PATIENT_ID' => 'SD-123456',
                    'PHONE' => '+525512345678',
                    _ => 'ana.garcia@example.com',
                  };
                }),
      ),
      const SizedBox(height: Space.sm + 4),
      TextFormField(
        controller: _value,
        enabled: !_otpSent,
        keyboardType: switch (_type) {
          'PHONE' => TextInputType.phone,
          'EMAIL' => TextInputType.emailAddress,
          _ => TextInputType.text,
        },
        textCapitalization: _type == 'EMAIL'
            ? TextCapitalization.none
            : TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _sendCode(),
        decoration: InputDecoration(
          labelText: switch (_type) {
            'PATIENT_ID' => 'Número de paciente',
            'PHONE' => 'Teléfono (con lada)',
            _ => 'Correo electrónico',
          },
          prefixIcon: const Icon(Icons.badge_outlined),
          suffixIcon: _otpSent
              ? IconButton(
                  tooltip: 'Cambiar identificador',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _otpSent = false),
                )
              : null,
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Escribe tu identificador' : null,
      ),
      const SizedBox(height: Space.md),
      if (!_otpSent)
        KeyedSubtree(
          key: _actionKey,
          child: FilledButton.icon(
            icon: const Icon(Icons.sms_outlined),
            label: const Text('Enviar código de verificación'),
            onPressed: _sendCode,
          ),
        )
      else ...[
        const _StepHeader(number: 2, label: 'Código de verificación', active: true),
        const SizedBox(height: Space.sm),
        TextFormField(
          controller: _otp,
          focusNode: _otpFocus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          maxLength: 6,
          style: t.titleLarge?.copyWith(letterSpacing: 6),
          decoration: const InputDecoration(
            labelText: 'Código de verificación',
            prefixIcon: Icon(Icons.lock_outline),
            helperText:
                'Código enviado por SMS. Demo: 123456 (Ana) · 654321 (Luis)',
            helperMaxLines: 2,
            counterText: '',
          ),
          validator: (v) =>
              (v == null || v.trim().length < 4) ? 'Código inválido' : null,
        ),
        const SizedBox(height: Space.md),
        KeyedSubtree(
          key: _actionKey,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Continuar'),
          ),
        ),
      ],
    ];

    // Los pacientes de demostración solo existen en el orquestador simulado.
    final showDemo = state.config.mockMode;
    final demo = Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Space.sm),
        leading: Icon(Icons.science_outlined, color: s.onSurfaceVariant),
        title: Text('Datos de prueba para la demo', style: t.labelLarge),
        children: [
          _DemoPatient(
            name: 'Ana García',
            detail: 'SD-123456 · +525512345678 · ana.garcia@example.com · código 123456',
            onTap: () => setState(() {
              _type = 'PATIENT_ID';
              _value.text = 'SD-123456';
              _otp.text = '123456';
            }),
          ),
          _DemoPatient(
            name: 'Luis Hernández',
            detail: 'SD-654321 · +523312345678 · luis.hernandez@example.com · código 654321',
            onTap: () => setState(() {
              _type = 'PATIENT_ID';
              _value.text = 'SD-654321';
              _otp.text = '654321';
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Modo: orquestador simulado en el dispositivo',
              style: t.bodySmall?.copyWith(color: s.primary),
            ),
          ),
        ],
      ),
    );

    final settingsAction = IconButton(
      tooltip: 'Conexión',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );

    // Dos paneles (alto compacto): presentación a la izquierda, formulario a
    // la derecha. Ambos se desplazan; el formulario conserva su estado al girar.
    if (ws.useTwoPane) {
      return Scaffold(
        appBar: ContentAppBar(
          compact: true,
          maxContentWidth: double.infinity,
          actions: [settingsAction],
        ),
        body: TwoPaneLayout(
          side: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.md, Space.lg),
            children: [...intro, const SizedBox(height: Space.md), privacy],
          ),
          main: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
              children: [
                ...form,
                if (showDemo) ...[const SizedBox(height: Space.lg), demo],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        maxContentWidth: LayoutTokens.formMaxWidth,
        actions: [settingsAction],
      ),
      body: SafeArea(
        // Arriba en lugar de centrado verticalmente: menos espacio muerto
        // encima del logotipo.
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: LayoutTokens.formMaxWidth),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...intro,
                    const SizedBox(height: Space.lg),
                    ...form,
                    const SizedBox(height: Space.sm),
                    privacy,
                    if (showDemo) ...[const SizedBox(height: Space.lg), demo],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int number;
  final String label;
  final bool active;
  const _StepHeader({required this.number, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active ? s.primary : s.surfaceContainerHighest,
          foregroundColor: active ? s.onPrimary : s.onSurfaceVariant,
          child: Text('$number', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(label,
              style: t.labelLarge?.copyWith(color: active ? s.onSurface : s.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _DemoPatient extends StatelessWidget {
  final String name;
  final String detail;
  final VoidCallback onTap;
  const _DemoPatient({required this.name, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.person_outline),
      title: Text(name),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
