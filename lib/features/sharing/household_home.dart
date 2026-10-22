import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../locations/location_repository.dart';
import '../locations/locations_page.dart';
import 'sharing_repository.dart';

class HouseholdHome extends StatefulWidget {
  const HouseholdHome({super.key, required this.user});
  final User user;
  @override State<HouseholdHome> createState() => _HouseholdHomeState();
}
class _HouseholdHomeState extends State<HouseholdHome> {
  String? _selected;
  @override Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Scaffold(body: Center(child: Text('Could not load households: ${snapshot.error}')));
      if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final ids = List<String>.from(snapshot.data!.data()?['householdIds'] ?? []);
      final selected = ids.contains(_selected) ? _selected : (ids.isEmpty ? null : ids.first);
      if (selected == null) return Scaffold(appBar: AppBar(title: const Text('Your households'), actions: [IconButton(tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))]), body: Center(child: HouseholdActions(onSelected: (id) => setState(() => _selected = id))));
      return LocationsPage(key: ValueKey(selected), repository: LocationRepository.firebase(selected), user: widget.user, onHouseholdChanged: (id) => setState(() => _selected = id));
    },
  );
}

class HouseholdActions extends StatefulWidget {
  const HouseholdActions({super.key, required this.onSelected});
  final ValueChanged<String> onSelected;
  @override State<HouseholdActions> createState() => _HouseholdActionsState();
}
class _HouseholdActionsState extends State<HouseholdActions> {
  bool _busy = false;
  String? _error;
  Future<void> _submit(bool join) async {
    final value = await showDialog<String>(context: context, builder: (context) => _TextDialog(title: join ? 'Join household' : 'Create household', label: join ? 'Invitation code' : 'Household name', max: join ? 32 : 200));
    if (value == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final id = join ? await SharingRepository.join(value) : await SharingRepository.create(value);
      if (mounted) widget.onSelected(id);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
    FilledButton.icon(onPressed: _busy ? null : () => _submit(false), icon: const Icon(Icons.add_home), label: const Text('Create household')),
    TextButton.icon(onPressed: _busy ? null : () => _submit(true), icon: const Icon(Icons.group_add), label: const Text('Join with invitation code')),
    if (_busy) const CircularProgressIndicator(),
    if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
  ]));
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.householdId, required this.user, required this.onSelected});
  final String householdId;
  final User user;
  final ValueChanged<String> onSelected;
  @override State<AccountPage> createState() => _AccountPageState();
}
class _AccountPageState extends State<AccountPage> {
  late final _repository = SharingRepository(widget.householdId);
  bool _busy = false;
  String? _code, _error;
  Future<void> _run(Future<void> Function() work) async {
    setState(() { _busy = true; _error = null; });
    try { await work(); } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _select(String id) { widget.onSelected(id); Navigator.pop(context); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Account & household')), body: ListView(padding: const EdgeInsets.all(16), children: [
    ListTile(leading: const Icon(Icons.person), title: Text(widget.user.displayName ?? 'Signed in'), subtitle: Text(widget.user.email ?? '')),
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(), builder: (context, snapshot) => Column(children: [
      for (final id in List<String>.from(snapshot.data?.data()?['householdIds'] ?? [])) StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('households').doc(id).snapshots(), builder: (context, home) => ListTile(title: Text(home.data?.data()?['name'] as String? ?? 'Household'), selected: id == widget.householdId, trailing: id == widget.householdId ? const Icon(Icons.check) : null, onTap: () => _select(id))),
    ])),
    HouseholdActions(onSelected: _select),
    const Divider(), Text('Members', style: Theme.of(context).textTheme.titleLarge),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _repository.members(), builder: (context, snapshot) {
      if (snapshot.hasError) return Text('Could not load members: ${snapshot.error}');
      final members = snapshot.data?.docs ?? [];
      final owner = members.any((m) => m.id == widget.user.uid && m.data()['role'] == 'owner');
      return Column(children: [
        for (final member in members) ListTile(leading: const Icon(Icons.person_outline), title: Text(member.data()['displayName'] as String? ?? (member.id == widget.user.uid ? 'You' : 'Household member')), subtitle: Text(member.data()['role'] as String? ?? 'member')),
        if (owner) FilledButton.tonal(onPressed: _busy ? null : () => _run(() async { final code = await _repository.invite(); if (mounted) setState(() => _code = code); }), child: const Text('Create invitation code')),
        if (owner) const Text('Codes expire after 7 days. Share only with people you want to join.'),
        if (!owner) TextButton(onPressed: _busy ? null : () async {
          final leave = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Leave household?'), content: const Text('You will lose access to its inventory and loans. You can rejoin with a valid invitation.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave'))]));
          if (leave == true) await _run(() async { await _repository.leave(); if (mounted) Navigator.pop(context); });
        }, child: const Text('Leave household')),
        if (owner) const Text('Owners keep their household membership.'),
      ]);
    }),
    if (_code != null) Padding(padding: const EdgeInsets.all(16), child: SelectableText('Invitation code (expires in 7 days):\n$_code')),
    if (_busy) const LinearProgressIndicator(),
    if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const Divider(), TextButton.icon(onPressed: _busy ? null : () async { Navigator.pop(context); await FirebaseAuth.instance.signOut(); }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
  ]));
}
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.label, required this.max});
  final String title, label;
  final int max;
  @override State<_TextDialog> createState() => _TextDialogState();
}
class _TextDialogState extends State<_TextDialog> {
  final _controller = TextEditingController();
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(widget.title), content: TextField(controller: _controller, autofocus: true, maxLength: widget.max, decoration: InputDecoration(labelText: widget.label), onChanged: (_) => setState(() {})), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _controller.text.trim().isEmpty ? null : () => Navigator.pop(context, _controller.text.trim()), child: const Text('Continue'))]);
}
