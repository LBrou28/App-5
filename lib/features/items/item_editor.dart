import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';

import '../locations/location.dart';
import '../locations/location_repository.dart';

class ItemEditor extends StatefulWidget {
  const ItemEditor({
    super.key,
    required this.repository,
    required this.locations,
    this.existing,
    this.initialLocationId,
    this.imagePicker,
  });
  final LocationRepository repository;
  final List<StorageLocation> locations;
  final StoredItem? existing;
  final ImagePicker? imagePicker;
  final String? initialLocationId;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();
  late final String _draftId = widget.repository.newItemId();
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _category = TextEditingController(text: widget.existing?.category);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String? _locationId =
      widget.existing?.locationId ?? widget.initialLocationId;
  Uint8List? _photo;
  String? _photoType;
  bool _removePhoto = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _recoverPhoto();
    }
  }

  Future<void> _readPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length >= 5 * 1024 * 1024) {
      throw StateError('Choose a photo smaller than 5 MB.');
    }
    if (mounted) {
      setState(() {
        _photo = bytes;
        _photoType =
            file.mimeType ??
            (file.name.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg');
        _removePhoto = false;
      });
    }
  }

  Future<void> _recoverPhoto() async {
    setState(() => _busy = true);
    try {
      final result = await _picker.retrieveLostData();
      if (result.files?.isNotEmpty == true) {
        await _readPhoto(result.files!.first);
      }
      if (result.exception != null) throw result.exception!;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not recover the previous photo. Please select it again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file != null) await _readPhoto(file);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not select the photo. Check camera or photo access and choose an image smaller than 5 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveItem(
        draftId: _draftId,
        existing: widget.existing,
        name: _name.text.trim(),
        category: _category.text.trim(),
        notes: _notes.text.trim(),
        locationId: _locationId,
        photo: _photo,
        photoType: _photoType,
        removePhoto: _removePhoto,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message ?? 'Could not save item. Please try again.'
              : 'Could not save item. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _path(StorageLocation location) {
    final parents = widget.locations.where((l) => l.id == location.parentId);
    return parents.isEmpty
        ? location.name
        : '${parents.first.name} → ${location.name}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.existing == null ? 'New item' : 'Edit item'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter an item name.'
                      : v.contains('/')
                      ? 'Use a name without a slash.'
                      : null,
                ),
                TextFormField(
                  controller: _category,
                  enabled: !_busy,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: widget.locations.any((l) => l.id == _locationId)
                      ? _locationId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...widget.locations.map(
                      (l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(_path(l), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) => setState(() => _locationId = id),
                ),
                TextFormField(
                  controller: _notes,
                  enabled: !_busy,
                  maxLength: 2000,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                if (_photo != null)
                  Image.memory(
                    _photo!,
                    height: 160,
                    errorBuilder: (_, _, _) =>
                        const Text('Photo preview unavailable.'),
                  )
                else if (!_removePhoto && widget.existing?.photoPath != null)
                  ItemPhoto(
                    repository: widget.repository,
                    path: widget.existing!.photoPath!,
                    height: 160,
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                    if (_photo != null ||
                        (!_removePhoto && widget.existing?.photoPath != null))
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _photo = null;
                                _removePhoto = true;
                              }),
                        child: const Text('Remove photo'),
                      ),
                  ],
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class ItemPhoto extends StatefulWidget {
  const ItemPhoto({
    super.key,
    required this.repository,
    required this.path,
    this.height = 200,
  });
  final LocationRepository repository;
  final String path;
  final double height;
  @override
  State<ItemPhoto> createState() => _ItemPhotoState();
}

class _ItemPhotoState extends State<ItemPhoto> {
  late Future<Uint8List?> _bytes = widget.repository.loadPhoto(widget.path);
  @override
  void didUpdateWidget(ItemPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = widget.repository.loadPhoto(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Photo unavailable.');
      if (snapshot.connectionState == ConnectionState.done && !snapshot.hasData) {
        return const Text('Photo unavailable.');
      }
      if (!snapshot.hasData) {
        return SizedBox(
          height: widget.height,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return Image.memory(
        snapshot.data!,
        height: widget.height,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Text('Photo unavailable.'),
      );
    },
  );
}
