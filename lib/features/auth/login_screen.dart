import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';

/// Login operator (Email/Password). Akun dibuat oleh admin di Firebase
/// Console — aplikasi tidak menyediakan pendaftaran akun.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn(_email.text, _password.text);
      // Navigasi ditangani AuthGate lewat authStateChanges().
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ResponsiveBody(
              maxWidth: 420,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.recycling_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text('Masuk dengan akun operator',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Masukkan email yang valid'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Kata sandi',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Tampilkan' : 'Sembunyikan',
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Masukkan kata sandi'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Masuk'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Akun operator dibuat oleh admin di Firebase Console.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
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
