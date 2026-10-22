import 'dart:async';

import 'package:flutter/material.dart';

import '../locations/location.dart';
import '../locations/location_repository.dart';
import 'sharing_repository.dart';
import 'return_reminders.dart';

class BorrowedItemsPage extends StatefulWidget {
  const BorrowedItemsPage({super.key, required this.repository});
  final LocationRepository repository;
  @override
  State<BorrowedItemsPage> createState() => _BorrowedItemsPageState();
}

class _BorrowedItemsPageState extends State<BorrowedItemsPage> {
  late final _sharing = SharingRepository(widget.repository.householdId!);
  late final _loans = _sharing.loans();
  late final _items = widget.repository.watchItems();
  bool _history = false, _busy = false;
  String? _message;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _date(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
  Future<void> _borrow(List<StoredItem> items) async {
    final available = items.where((item) => !item.isOnLoan).toList();
    if (available.isEmpty) {
      setState(
        () => _message =
            'No available items. Add an item or return an existing loan first.',
      );
      return;
    }
    final draft = await showDialog<_LoanDraft>(
      context: context,
      builder: (_) => _LoanDialog(items: available),
    );
    if (draft == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final loanId = await _sharing.borrow(
        draft.item.id,
        draft.borrower,
        draft.due,
      );
      var reminded = false;
      try {
        reminded = await ReturnReminders.instance.schedule(
          _sharing.householdId,
          loanId,
          draft.item.name,
          draft.due,
        );
      } catch (_) {
        /* The successful loan must not be retried when notification setup fails. */
      }
      if (mounted) {
        setState(
          () => _message = reminded
              ? 'Loan recorded. This phone will remind you at the return time.'
              : 'Loan recorded. No phone reminder was scheduled. Check notification permissions or use an Android/iOS phone.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not record loan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _return(Loan loan) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _sharing.returnItem(loan.itemId);
      if (mounted) {
        setState(() => _message = 'Item returned. Loan history retained.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not return item: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<StoredItem>>(
    stream: _items,
    builder: (context, itemsSnapshot) => StreamBuilder<List<Loan>>(
      stream: _loans,
      builder: (context, loansSnapshot) {
        final items = itemsSnapshot.data ?? [];
        final loans =
            (loansSnapshot.data ?? [])
                .where((loan) => _history ? !loan.active : loan.active)
                .toList()
              ..sort(
                (a, b) => _history
                    ? b.borrowedAt.compareTo(a.borrowedAt)
                    : a.dueDate.compareTo(b.dueDate),
              );
        return Scaffold(
          appBar: AppBar(title: const Text('Borrowed items')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy || !itemsSnapshot.hasData
                ? null
                : () => _borrow(items),
            icon: const Icon(Icons.handshake_outlined),
            label: const Text('Record loan'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Active & overdue')),
                  ButtonSegment(value: true, label: Text('History')),
                ],
                selected: {_history},
                onSelectionChanged: (values) =>
                    setState(() => _history = values.first),
              ),
              if (_busy || !itemsSnapshot.hasData || !loansSnapshot.hasData)
                const LinearProgressIndicator(),
              if (itemsSnapshot.hasError || loansSnapshot.hasError)
                Text(
                  'Could not load borrowing records: ${itemsSnapshot.error ?? loansSnapshot.error}',
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              if (loansSnapshot.hasData && loans.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _history ? 'No returned loans yet.' : 'No active loans.',
                  ),
                ),
              for (final loan in loans)
                Card(
                  child: ListTile(
                    leading: Icon(
                      loan.overdueAt(DateTime.now())
                          ? Icons.warning_amber
                          : Icons.handshake_outlined,
                      color: loan.overdueAt(DateTime.now())
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(
                      items
                              .where((item) => item.id == loan.itemId)
                              .firstOrNull
                              ?.name ??
                          'Removed item',
                    ),
                    subtitle: Text(
                      '${loan.borrower}\nLoaned ${_date(loan.borrowedAt)} · Due ${_date(loan.dueDate)} ${TimeOfDay.fromDateTime(loan.dueDate.toLocal()).format(context)}${loan.overdueAt(DateTime.now()) ? '\nOverdue' : ''}${loan.returnedAt == null ? '' : '\nReturned ${_date(loan.returnedAt!)}'}',
                    ),
                    isThreeLine: true,
                    trailing: loan.active
                        ? TextButton(
                            onPressed: _busy ? null : () => _return(loan),
                            child: const Text('Return'),
                          )
                        : const Icon(Icons.check_circle_outline),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _LoanDraft {
  _LoanDraft(this.item, this.borrower, this.due);
  final StoredItem item;
  final String borrower;
  final DateTime due;
}

class _LoanDialog extends StatefulWidget {
  const _LoanDialog({required this.items});
  final List<StoredItem> items;
  @override
  State<_LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<_LoanDialog> {
  final _borrower = TextEditingController();
  late StoredItem _item = widget.items.first;
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  @override
  void dispose() {
    _borrower.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
    );
    if (time != null && mounted) {
      setState(
        () => _due = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record loan'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _item.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Item'),
              items: widget.items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(
                () => _item = widget.items.firstWhere((item) => item.id == id),
              ),
            ),
            TextField(
              controller: _borrower,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Borrower name'),
              onChanged: (_) => setState(() {}),
            ),
            const Text('Loan date is recorded automatically when saved.'),
            TextButton(
              onPressed: _pickDue,
              child: Text(
                'Return: ${MaterialLocalizations.of(context).formatMediumDate(_due)} ${TimeOfDay.fromDateTime(_due).format(context)}',
              ),
            ),
            if (!_due.isAfter(DateTime.now()))
              const Text('Choose a future return date and time.'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _borrower.text.trim().isEmpty ||
                _borrower.text.contains('/') ||
                !_due.isAfter(DateTime.now())
            ? null
            : () => Navigator.pop(
                context,
                _LoanDraft(_item, _borrower.text.trim(), _due),
              ),
        child: const Text('Record'),
      ),
    ],
  );
}
