import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/layout/adaptive.dart';
import '../../ui/layout/window_size.dart';
import '../../widgets/common.dart';
import '../api_models.dart';
import '../real_state.dart';
import 'real_app.dart';
import 'real_connection_screen.dart';

/// Acceso del modo real: correo y contraseña de la cuenta de paciente
/// (`POST /auth/login`). La contraseña no se guarda; el JWT vive en memoria.
class RealLoginScreen extends StatefulWidget {
  const RealLoginScreen({super.key});

  static const emailKey = ValueKey<String>('real-login-email');
  static const passwordKey = ValueKey<String>('real-login-password');

  @override
  State<RealLoginScreen> createState() => _RealLoginScreenState();
}

class _RealLoginScreenState extends State<RealLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = RealScope.of(context);
    String? error;
    try {
      await state.login(_email.text, _password.text);
    } on RealAuthException catch (e) {
      error = e.message;
    } on ApiException catch (e) {
      error = humanApiError(e);
    } on ApiNetworkException catch (e) {
      error = 'No se pudo conectar con Salud Digna. Revisa tu conexión e intenta de nuevo. '
          '(${e.message})';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final state = RealScope.of(context);
    final ws = context.windowSize;
    final notice = state.notice;

    return Scaffold(
      appBar: ContentAppBar(
        compact: ws.isHeightCompact,
        maxContentWidth: LayoutTokens.formMaxWidth,
        actions: [
          IconButton(
            tooltip: 'Conexión',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RealConnectionScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
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
                    const Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: BrandLogo(height: 56)),
                    ),
                    SizedBox(height: ws.isHeightCompact ? Space.xl : Space.xxl),
                    Text('Inicia sesión', style: t.titleLarge),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Usa la misma cuenta del sitio web. Recuperaremos tus trámites '
                      'donde los dejaste.',
                      style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                    ),
                    if (notice != null) ...[
                      const SizedBox(height: Space.md),
                      _Notice(message: notice, icon: Icons.timer_off_outlined),
                    ],
                    const SizedBox(height: Space.lg),
                    TextFormField(
                      key: RealLoginScreen.emailKey,
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Escribe tu correo';
                        if (!value.contains('@')) return 'Revisa el correo';
                        return null;
                      },
                    ),
                    const SizedBox(height: Space.sm + 4),
                    TextFormField(
                      key: RealLoginScreen.passwordKey,
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.md),
                      _Notice(message: _error!, icon: Icons.error_outline, error: true),
                    ],
                    const SizedBox(height: Space.md),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: s.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tu sesión dura un tiempo limitado y no se guarda en el teléfono.',
                            style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
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

class _Notice extends StatelessWidget {
  final String message;
  final IconData icon;
  final bool error;
  const _Notice({required this.message, required this.icon, this.error = false});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final bg = error ? s.errorContainer : s.secondaryContainer;
    final fg = error ? s.onErrorContainer : s.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(Space.sm + 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(message, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}
