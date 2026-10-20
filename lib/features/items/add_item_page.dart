import 'package:flutter/material.dart';

/// Returns entered values to the caller; persistence belongs to the item screen.
class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (
      name: _name.text.trim(),
      category: _category.text.trim().isEmpty
          ? 'Uncategorized'
          : _category.text.trim(),
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add item')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 100,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an item name'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                border: OutlineInputBorder(),
              ),
              maxLength: 60,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 1000,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save item')),
          ],
        ),
      ),
    );
  }
}

typedef NewItemValues = ({String name, String category, String notes});
