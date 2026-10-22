import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'features/locations/location_repository.dart';
import 'features/locations/locations_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/locations/demo_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('DEMO_MODE')) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
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
    home: const bool.fromEnvironment('DEMO_MODE')
        ? LocationsPage(repository: DemoLocationRepository())
        : const _AuthGate(),
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
          : _FirebaseHome(key: ValueKey(user.uid), uid: user.uid);
    },
  );
}

class _FirebaseHome extends StatefulWidget {
  const _FirebaseHome({super.key, required this.uid});
  final String uid;
  @override
  State<_FirebaseHome> createState() => _FirebaseHomeState();
}

class _FirebaseHomeState extends State<_FirebaseHome> {
  late Future<LocationRepository> _repository = LocationRepository.forUser(
    widget.uid,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<LocationRepository>(
    future: _repository,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'We could not open your household. Check your connection and try again.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(
                      () =>
                          _repository = LocationRepository.forUser(widget.uid),
                    ),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return LocationsPage(
        key: ValueKey(snapshot.data!.householdId),
        repository: snapshot.data!,
        user: FirebaseAuth.instance.currentUser!,
        onHouseholdChanged: (id) => setState(
          () => _repository = Future.value(LocationRepository.firebase(id)),
        ),
      );
    },
  );
}
