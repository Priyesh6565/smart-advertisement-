import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _company = TextEditingController();

  bool _isLogin = true;
  bool _busy = false;
  bool _obscurePassword = true;

  static final _emailRegex =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _company.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';

    if (v.isEmpty) return 'Email is required';

    if (!_emailRegex.hasMatch(v)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';

    if (v.isEmpty) return 'Password is required';

    if (v.length < 6) {
      return 'Password must be at least 6 characters';
    }

    return null;
  }

  String? _validateRequired(String? value, String field) {
    if ((value ?? '').trim().isEmpty) {
      return '$field is required';
    }

    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _email.text.trim();
    final pass = _password.text;

    setState(() => _busy = true);

    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: email,
          password: pass,
        );
      } else {
        final res = await supabase.auth.signUp(
          email: email,
          password: pass,
          data: {
            'full_name': _name.text.trim(),
            'company_name': _company.text.trim(),
          },
        );

        if (res.session == null && mounted) {
          toast(
            context,
            'Account created. Check your email to confirm, then log in.',
          );

          setState(() => _isLogin = true);
        }
      }
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) {
        toast(
          context,
          'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    _formKey.currentState?.reset();

    setState(() => _isLogin = !_isLogin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    const darkNavy = Color(0xFF101828);
    const accent = Color(0xFFF59E0B);
    const lightBackground = Color(0xFFF8FAFC);
    const borderColor = Color(0xFFD0D5DD);
    const fieldBackground = Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: lightBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 850;

            // ===========================================================
            // DESKTOP / TABLET
            // ===========================================================
            if (isDesktop) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // =====================================================
                    // LEFT ADVERTISING PANEL
                    // =====================================================
                    Expanded(
                      flex: 11,
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: darkNavy,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(
                            children: [
                              // Decorative circle
                              Positioned(
                                top: -80,
                                right: -70,
                                child: Container(
                                  width: 240,
                                  height: 240,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(
                                      alpha: 0.13,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),

                              // Decorative circle
                              Positioned(
                                bottom: -100,
                                left: -80,
                                child: Container(
                                  width: 280,
                                  height: 280,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(
                                      alpha: 0.10,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.all(52),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // =================================================
                                    // LOGO
                                    // =================================================
                                    Row(
                                      children: [
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: accent,
                                            borderRadius:
                                                BorderRadius.circular(15),
                                          ),
                                          child: const Icon(
                                            Icons.campaign_rounded,
                                            color: darkNavy,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Text(
                                          'Smart Ad Portal',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const Spacer(),

                                    // =================================================
                                    // MAIN HEADLINE
                                    // =================================================
                                    const Text(
                                      'Make your brand\nimpossible to ignore.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 42,
                                        height: 1.12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1,
                                      ),
                                    ),

                                    const SizedBox(height: 22),

                                    Text(
                                      'Create, manage and grow your '
                                      'advertising campaigns from one '
                                      'powerful platform.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        fontSize: 16,
                                        height: 1.6,
                                      ),
                                    ),

                                    const SizedBox(height: 38),

                                    // =================================================
                                    // FEATURE CARDS
                                    // =================================================
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding:
                                                const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.07,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              border: Border.all(
                                                color:
                                                    Colors.white.withValues(
                                                  alpha: 0.10,
                                                ),
                                              ),
                                            ),
                                            child: const Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.ads_click_rounded,
                                                  color: accent,
                                                  size: 24,
                                                ),
                                                SizedBox(height: 11),
                                                Text(
                                                  'Campaigns',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Container(
                                            padding:
                                                const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.07,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              border: Border.all(
                                                color:
                                                    Colors.white.withValues(
                                                  alpha: 0.10,
                                                ),
                                              ),
                                            ),
                                            child: const Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.analytics_rounded,
                                                  color: accent,
                                                  size: 24,
                                                ),
                                                SizedBox(height: 11),
                                                Text(
                                                  'Analytics',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Container(
                                            padding:
                                                const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.07,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              border: Border.all(
                                                color:
                                                    Colors.white.withValues(
                                                  alpha: 0.10,
                                                ),
                                              ),
                                            ),
                                            child: const Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.trending_up_rounded,
                                                  color: accent,
                                                  size: 24,
                                                ),
                                                SizedBox(height: 11),
                                                Text(
                                                  'Growth',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const Spacer(),

                                    Text(
                                      'SMART ADVERTISING  •  BETTER RESULTS',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.45,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // =====================================================
                    // RIGHT AUTHENTICATION AREA
                    // =====================================================
                    Expanded(
                      flex: 9,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 50,
                            vertical: 40,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 470,
                            ),
                            child: _buildAuthCard(
                              scheme,
                              fieldBackground,
                              borderColor,
                              darkNavy,
                              accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // ===========================================================
            // MOBILE
            // ===========================================================
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 470,
                  ),
                  child: _buildAuthCard(
                    scheme,
                    fieldBackground,
                    borderColor,
                    darkNavy,
                    accent,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAuthCard(
    ColorScheme scheme,
    Color fieldBackground,
    Color borderColor,
    Color darkNavy,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 36,
        vertical: 34,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE4E7EC),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =============================================================
            // AUTH ICON
            // =============================================================
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  _isLogin
                      ? Icons.campaign_rounded
                      : Icons.rocket_launch_rounded,
                  color: darkNavy,
                  size: 34,
                ),
              ),
            ),

            const SizedBox(height: 22),

            // =============================================================
            // TITLE
            // =============================================================
            Center(
              child: Text(
                _isLogin
                    ? 'Welcome back'
                    : 'Create your account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: darkNavy,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                _isLogin
                    ? 'Log in to manage your advertising campaigns.'
                    : 'Join Smart Ad Portal and start growing your brand.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // =============================================================
            // NAME
            // =============================================================
            if (!_isLogin) ...[
              const Text(
                'Full name',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 7),

              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    size: 21,
                  ),
                  filled: true,
                  fillColor: fieldBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: borderColor,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: borderColor,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF101828),
                      width: 1.5,
                    ),
                  ),
                ),
                validator: (v) => _validateRequired(v, 'Name'),
              ),

              const SizedBox(height: 17),

              // ===========================================================
              // COMPANY
              // ===========================================================
              const Text(
                'Company / Brand name',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 7),

              TextFormField(
                controller: _company,
                decoration: InputDecoration(
                  hintText: 'Enter your company or brand',
                  prefixIcon: const Icon(
                    Icons.business_outlined,
                    size: 21,
                  ),
                  filled: true,
                  fillColor: fieldBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: borderColor,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: borderColor,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF101828),
                      width: 1.5,
                    ),
                  ),
                ),
                validator: (v) =>
                    _validateRequired(v, 'Company name'),
              ),

              const SizedBox(height: 17),
            ],

            // =============================================================
            // EMAIL
            // =============================================================
            const Text(
              'Email address',
              style: TextStyle(
                color: Color(0xFF101828),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 7),

            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'Enter your email',
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  size: 21,
                ),
                filled: true,
                fillColor: fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: borderColor,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: borderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF101828),
                    width: 1.5,
                  ),
                ),
              ),
              validator: _validateEmail,
            ),

            const SizedBox(height: 17),

            // =============================================================
            // PASSWORD
            // =============================================================
            const Text(
              'Password',
              style: TextStyle(
                color: Color(0xFF101828),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 7),

            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  size: 21,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                ),
                helperText: _isLogin
                    ? null
                    : 'Password must contain at least 6 characters',
                helperStyle: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: fieldBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: borderColor,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: borderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF101828),
                    width: 1.5,
                  ),
                ),
              ),
              validator: _validatePassword,
            ),

            const SizedBox(height: 24),

            // =============================================================
            // LOGIN / SIGNUP BUTTON
            // =============================================================
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: darkNavy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      darkNavy.withValues(alpha: 0.45),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLogin
                                ? 'Log in to dashboard'
                                : 'Create vendor account',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 19,
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 22),

            // =============================================================
            // LOGIN / SIGNUP SWITCH
            // =============================================================
            Center(
              child: TextButton(
                onPressed: _toggleMode,
                style: TextButton.styleFrom(
                  foregroundColor: darkNavy,
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: _isLogin
                            ? "Don't have an account? "
                            : 'Already have an account? ',
                      ),
                      TextSpan(
                        text: _isLogin
                            ? 'Create one'
                            : 'Log in',
                        style: TextStyle(
                          color: darkNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 5),

            // =============================================================
            // FOOTER
            // =============================================================
            Center(
              child: Text(
                'Secure advertising management platform',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}