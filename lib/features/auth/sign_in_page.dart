import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Icons.inventory_2_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Where Did I Put It?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Sign in to securely access your household inventory.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _busy ? null : _signInWithGoogle, icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login), label: const Text('Continue with Google')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    ))),
  );
}
