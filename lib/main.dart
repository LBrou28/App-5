import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'features/sharing/household_home.dart';

import 'features/auth/sign_in_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App5());
}

class App5 extends StatelessWidget {
  const App5({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Where Did I Put It?',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b87)),
      useMaterial3: true,
    ),
    home: const _AuthGate(),
  );
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      return user == null || user.isAnonymous
          ? SignInPage(anonymousUser: user?.isAnonymous == true ? user : null)
          : HouseholdHome(key: ValueKey(user.uid), user: user);
    },
  );
}
