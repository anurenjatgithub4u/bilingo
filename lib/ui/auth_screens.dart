import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'app_theme.dart';
import 'main_shell.dart';
import 'mascot.dart';

const _errorRed = Color(0xFFE5484D);

/// Shared frame: gradient, back button, mascot and a white card for the form.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.card, this.footer});

  final Widget card;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GradientBackground(
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: Mascot(size: 120)),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF151E33) : Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: kBrandBlue.withValues(
                              alpha: dark ? 0.0 : 0.10,
                            ),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                        child: card,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 16),
                      footer!,
                    ],
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

/// Outlined input used inside the auth card; turns red when [hasError].
InputDecoration _input(
  BuildContext context,
  String hint, {
  Widget? suffix,
  bool hasError = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  final idle = dark ? const Color(0x26FFFFFF) : const Color(0xFFE3E8F0);
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
    filled: true,
    fillColor: dark ? const Color(0x0FFFFFFF) : const Color(0xFFF7F9FC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    suffixIcon: suffix,
    enabledBorder: border(hasError ? _errorRed : idle),
    focusedBorder: border(hasError ? _errorRed : kBrandBlue, 1.5),
    errorBorder: border(_errorRed),
    focusedErrorBorder: border(_errorRed, 1.5),
  );
}

/// Bold label above its input, as in "Your Email" / "Password".
class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.hint,
    required this.controller,
    this.validator,
    this.hasError = false,
    this.newPassword = false,
    this.onSubmitted,
  });

  final String hint;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final bool hasError;
  final bool newPassword;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      obscureText: _hidden,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: widget.onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: _input(
        context,
        widget.hint,
        hasError: widget.hasError,
        suffix: IconButton(
          icon: Icon(
            _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

String? _validateEmail(String? v) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return 'Enter your email';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
    return 'Enter a valid email';
  }
  return null;
}

String? _validatePassword(String? v) {
  if ((v ?? '').isEmpty) return 'Enter your password';
  if (v!.length < 6) return 'At least 6 characters';
  return null;
}

void enterApp(BuildContext context) => Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute<void>(builder: (_) => const MainShell()),
  (_) => false,
);

/// Runs [action] with a busy flag; any [AuthException] lands in [error] and
/// is shown inline in the card.
mixin _AuthActions<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<bool> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget submitButton(String label, VoidCallback onPressed) => FilledButton(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    onPressed: busy ? null : onPressed,
    child: busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : Text(label),
  );

  Widget errorText() => Text(
    error ?? '',
    style: const TextStyle(
      color: _errorRed,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Log in / Sign up in one card with tabs, plus Google sign-in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.startOnSignUp = false});

  final bool startOnSignUp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin, _AuthActions<LoginScreen> {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.startOnSignUp ? 1 : 0,
  )..addListener(_onTab);

  final _loginForm = GlobalKey<FormState>();
  final _signUpForm = GlobalKey<FormState>();
  // Email and password carry over when switching tabs.
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool get _signUp => _tabs.index == 1;

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    setState(() => error = null);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final form = _signUp ? _signUpForm : _loginForm;
    if (!form.currentState!.validate()) return;
    final ok = await run(
      () => _signUp
          ? AuthService.instance.register(
              _name.text,
              _email.text,
              _password.text,
            )
          : AuthService.instance.signIn(_email.text, _password.text),
    );
    if (ok && mounted) enterApp(context);
  }

  Future<void> _google() async {
    if (await run(AuthService.instance.signInWithGoogle) && mounted) {
      enterApp(context);
    }
  }

  Widget _emailField() => _Labeled(
    'Your Email',
    TextFormField(
      controller: _email,
      validator: _validateEmail,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      decoration: _input(context, 'you@example.com'),
    ),
  );

  Widget _loginFields() => Form(
    key: _loginForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _emailField(),
        const SizedBox(height: 16),
        _Labeled(
          'Password',
          _PasswordField(
            hint: 'Enter your password',
            controller: _password,
            validator: _validatePassword,
            hasError: error != null,
            onSubmitted: _submit,
          ),
        ),
        Row(
          children: [
            Expanded(child: errorText()),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ForgotPasswordScreen(email: _email.text),
                ),
              ),
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _signUpFields() => Form(
    key: _signUpForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Labeled(
          'Full name',
          TextFormField(
            controller: _name,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter your name' : null,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: _input(context, 'Your name'),
          ),
        ),
        const SizedBox(height: 16),
        _emailField(),
        const SizedBox(height: 16),
        _Labeled(
          'Password',
          _PasswordField(
            hint: 'At least 6 characters',
            controller: _password,
            validator: _validatePassword,
            newPassword: true,
          ),
        ),
        const SizedBox(height: 16),
        _Labeled(
          'Confirm password',
          _PasswordField(
            hint: 'Re-enter your password',
            controller: _confirm,
            newPassword: true,
            validator: (v) =>
                v != _password.text ? 'Passwords do not match' : null,
            onSubmitted: _submit,
          ),
        ),
        if (error != null) ...[const SizedBox(height: 10), errorText()],
        const SizedBox(height: 10),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _AuthScaffold(
      card: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabs,
              dividerColor: Colors.transparent,
              indicatorColor: scheme.onSurface,
              indicatorWeight: 2.5,
              labelColor: scheme.onSurface,
              unselectedLabelColor: scheme.onSurfaceVariant.withValues(
                alpha: 0.45,
              ),
              labelStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
              splashBorderRadius: BorderRadius.circular(12),
              tabs: const [
                Tab(text: 'Log in'),
                Tab(text: 'Sign up'),
              ],
            ),
            const SizedBox(height: 22),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_signUp),
                  child: _signUp ? _signUpFields() : _loginFields(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            submitButton(_signUp ? 'Create account' : 'Continue', _submit),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'Or',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 22),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: scheme.onSurface,
                side: BorderSide(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0x33FFFFFF)
                      : const Color(0xFFE3E8F0),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: busy ? null : _google,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleLogo(size: 20),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Continue with Google',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _signUp ? 'Already have an account?' : "Don't have an account?",
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          TextButton(
            onPressed: () => _tabs.animateTo(_signUp ? 0 : 1),
            child: Text(_signUp ? 'Log in' : 'Sign up'),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with _AuthActions<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email.trim());
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final ok = await run(
      () => AuthService.instance.sendPasswordReset(_email.text),
    );
    if (ok && mounted) setState(() => _sent = true);
  }

  Widget _heading(String title, String subtitle) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _requestView() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Forgot password?',
          "No worries. Enter the email you signed up with and we'll send "
              'you a link to reset it.',
        ),
        const SizedBox(height: 24),
        _Labeled(
          'Your Email',
          TextFormField(
            controller: _email,
            validator: _validateEmail,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: _input(
              context,
              'you@example.com',
              hasError: error != null,
            ),
          ),
        ),
        if (error != null) ...[const SizedBox(height: 8), errorText()],
        const SizedBox(height: 20),
        submitButton('Send reset link', _submit),
      ],
    ),
  );

  Widget _sentView() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kBrandBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: kBrandBlue,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _heading(
          'Check your inbox',
          'If an account exists for ${_email.text.trim()}, a reset link is '
              'on its way.',
        ),
        const SizedBox(height: 24),
        submitButton('Back to log in', () => Navigator.of(context).pop()),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : _submit,
          child: Text.rich(
            TextSpan(
              text: "Didn't get it? ",
              style: TextStyle(color: scheme.onSurfaceVariant),
              children: const [
                TextSpan(
                  text: 'Resend',
                  style: TextStyle(
                    color: kBrandBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      card: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey(_sent),
            child: _sent ? _sentView() : _requestView(),
          ),
        ),
      ),
      footer: _sent
          ? null
          : TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to log in'),
            ),
    );
  }
}

/// The four-colour Google "G", drawn so no image asset is needed.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GoogleLogoPainter());
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double deg(double d) => d * math.pi / 180;
    // Angles run clockwise from 3 o'clock; the gap sits at the upper right.
    void arc(Color color, double start, double sweep) => canvas.drawArc(
      rect,
      deg(start),
      deg(sweep),
      false,
      paint..color = color,
    );
    arc(const Color(0xFFEA4335), -150, 105); // red, top
    arc(const Color(0xFFFBBC05), 150, 60); // yellow, left
    arc(const Color(0xFF34A853), 45, 105); // green, bottom
    arc(const Color(0xFF4285F4), 0, 45); // blue, right
    // Blue crossbar.
    canvas.drawRect(
      Rect.fromLTWH(
        size.width / 2,
        size.height / 2 - stroke / 2,
        size.width / 2 - stroke * 0.05,
        stroke,
      ),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;
}
