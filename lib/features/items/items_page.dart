import 'package:flutter/material.dart';

import 'add_item_page.dart';
import 'inventory_item.dart';

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _items = <InventoryItem>[];
  int _nextId = 0;

  Future<void> _addItem() async {
    final values = await Navigator.push<NewItemValues>(
      context,
      MaterialPageRoute(builder: (_) => const AddItemPage()),
    );
    if (!mounted || values == null) return;
    setState(() {
      _items.add(
        InventoryItem(
          id: 'local-${_nextId++}',
          name: values.name,
          category: values.category,
          notes: values.notes,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your items')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'Items are stored for this session only. Firebase is not connected yet.',
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 56),
                          SizedBox(height: 16),
                          Text('No items yet'),
                          SizedBox(height: 8),
                          Text(
                            'Tap Add item to record your first belonging.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(item.name),
                        subtitle: Text(item.category),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(item.name),
                            content: SingleChildScrollView(
                              child: Text(
                                '${item.category}\n\n${item.notes.isEmpty ? 'No notes added.' : item.notes}',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
    );
  }
}
