import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _company = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.length < 6) {
      toast(context, 'Enter a valid email and a password of 6+ characters');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(email: email, password: pass);
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
          toast(context,
              'Account created. Check your email to confirm, then log in.');
          setState(() => _isLogin = true);
        }
      }
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                const Icon(Icons.campaign, size: 64, color: Colors.indigo),
                const SizedBox(height: 8),
                Text('Smart Ad Portal',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                if (!_isLogin) ...[
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'Your name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _company,
                    decoration: const InputDecoration(
                        labelText: 'Company / Brand name',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? 'Log in' : 'Create vendor account'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin
                      ? 'New vendor? Create an account'
                      : 'Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
