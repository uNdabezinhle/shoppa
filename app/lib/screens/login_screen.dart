import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/auth_repository.dart';
import '../core/list_realtime_client.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authRepository,
    required this.listsRepository,
    required this.realtimeClient,
  });

  final AuthRepository authRepository;
  final ListsRepository listsRepository;
  final ListRealtimeClient realtimeClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.authRepository.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            authRepository: widget.authRepository,
            listsRepository: widget.listsRepository,
            realtimeClient: widget.realtimeClient,
            greetingName: user.email.split('@').first,
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'SHOPPA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShoppaColors.amber,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log in'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RegisterScreen(
                      authRepository: widget.authRepository,
                      listsRepository: widget.listsRepository,
                      realtimeClient: widget.realtimeClient,
                    ),
                  ),
                ),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
