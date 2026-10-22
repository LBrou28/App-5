import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/theme/app_theme.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, this.anonymousUser});
  final User? anonymousUser;
  @override State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _busy = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        if (widget.anonymousUser != null) {
          await widget.anonymousUser!.linkWithPopup(provider);
        } else {
          await FirebaseAuth.instance.signInWithPopup(provider);
        }
        return;
      }

      final google = GoogleSignIn(
        scopes: const ['email'],
      );
      final account = await google.signIn();
      if (account == null) return;
      final tokens = await account.authentication;
      final credential = GoogleAuthProvider.credential(accessToken: tokens.accessToken, idToken: tokens.idToken);
      if (widget.anonymousUser != null) {
        await widget.anonymousUser!.linkWithCredential(credential);
      } else {
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = error.message ?? 'Google sign-in failed (${error.code}).');
    } catch (error) {
      setState(() => _error = 'Google sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer.withValues(alpha: 0.6), scheme.surface, scheme.tertiaryContainer.withValues(alpha: 0.4)],
        )),
        child: SafeArea(child: Stack(children: [
          Center(child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(28)),
                    child: Icon(Icons.inventory_2_outlined, size: 44, color: scheme.onPrimaryContainer),
                  )),
                  const SizedBox(height: 24),
                  Text('Where Did I Put It?', textAlign: TextAlign.center, style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Sign in to securely access your household inventory.', textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  SizedBox(height: 52, child: FilledButton.icon(onPressed: _busy ? null : _signInWithGoogle, icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login), label: const Text('Continue with Google'))),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.error_outline, color: scheme.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                      ]),
                    ),
                  ),
                ]),
              ),
            )),
          )),
          const Positioned(top: 8, right: 8, child: ThemeToggleButton()),
        ])),
      ),
    );
  }
}
