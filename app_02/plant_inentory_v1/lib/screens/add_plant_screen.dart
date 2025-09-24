// lib/screens/add_plant_screen.dart
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;

import '../database/db_helper.dart';
import '../models/plant.dart';
import '../services/cloud_sync.dart';

class AddPlantScreen extends StatefulWidget {
  const AddPlantScreen({super.key});

  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _nameCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();
  final _newLocationCtrl = TextEditingController(); // 👈 for "Add new location..."

  // Locations state
  List<String> _locations = [];
  String? _locationValue;
  bool _addingLocation = false;

  // Image + save state
  String? _imagePath; // local path or remote URL after upload
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final locs = await DatabaseHelper.getDistinctLocations();
    final set = {
      ...locs.map((e) => e.trim()).where((e) => e.isNotEmpty),
      'Default',
    };
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() {
      _locations = list;
      _locationValue = 'Default';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _typeCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _newLocationCtrl.dispose();
    super.dispose();
  }

  // -------- Image picking (image_picker only) --------
  Future<void> _pickImage() async {
    try {
      final picker = ip.ImagePicker();

      final ip.ImageSource? src = (Platform.isAndroid || Platform.isIOS)
          ? await showModalBottomSheet<ip.ImageSource>(
              context: context,
              builder: (ctx) => SafeArea(
                child: Wrap(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_camera),
                      title: const Text('Take photo'),
                      onTap: () => Navigator.pop(ctx, ip.ImageSource.camera),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library),
                      title: const Text('Choose from gallery'),
                      onTap: () => Navigator.pop(ctx, ip.ImageSource.gallery),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            )
          : ip.ImageSource.gallery; // desktop/web: open picker

      if (src == null) return;

      final picked = await picker.pickImage(
        source: src,
        imageQuality: 75, // compress immediately
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;

      setState(() => _imagePath = picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Image error: $e')));
    }
  }

  void _removeImage() => setState(() => _imagePath = null);

  // -------- Save --------
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final type = _typeCtrl.text.trim();

    // 👇 If user chose "Add new location…" but didn't press Enter,
    // read the typed value here so we don't fall back to "Default".
    String location;
    if (_addingLocation || (_locationValue ?? '') == '__ADD__') {
      final raw = _newLocationCtrl.text.trim();
      location = raw.isEmpty ? 'Default' : raw;
    } else {
      location = (_locationValue == null || _locationValue!.trim().isEmpty)
          ? 'Default'
          : _locationValue!.trim();
    }

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final notes = _notesCtrl.text.trim();

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be ≥ 1')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // 1) Merge locally first (fast UI)
      await DatabaseHelper.upsertByNameTypeLocation(
        name: name,
        type: type,
        location: location,
        deltaQuantity: qty,
        notes: notes,
        imagePath: _imagePath,
      );

      // 2) Get merged row
      final merged =
          await DatabaseHelper.findByNameTypeLocation(name, type, location);

      // 3) Push to cloud; if local file, upload & get URL back
      if (merged != null) {
        final uploadedUrl = await CloudSync.pushPlant(merged);

        // 4) If we got a URL, write it back locally so the list shows it immediately
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          await DatabaseHelper.updateOrMergeOnEdit(
            id: merged.id!,
            name: merged.name,
            type: merged.type,
            location: merged.location,
            quantity: merged.quantity,
            notes: merged.notes ?? '',
            imagePath: uploadedUrl,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved: $name')));
      Navigator.pop(context, true); // pop last so nothing after runs
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Plant'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Image preview
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImagePreview(theme),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo),
                    label: Text((Platform.isAndroid || Platform.isIOS)
                        ? 'Add photo'
                        : 'Choose image'),
                    onPressed: _pickImage,
                  ),
                  const SizedBox(width: 8),
                  if (_imagePath != null && _imagePath!.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                      onPressed: _removeImage,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _typeCtrl,
                decoration:
                    const InputDecoration(labelText: 'Type (e.g., Perennial)'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      items: [
                        ..._locations.map((loc) =>
                            DropdownMenuItem(value: loc, child: Text(loc))),
                        const DropdownMenuItem(
                          value: '__ADD__',
                          child: Text('➕ Add new location…'),
                        ),
                      ],
                      value: _locationValue, // current choice
                      decoration:
                          const InputDecoration(labelText: 'Location'),
                      onChanged: (val) {
                        if (val == '__ADD__') {
                          setState(() {
                            _addingLocation = true;
                            _locationValue = null; // clear sentinel
                            _newLocationCtrl.clear();
                          });
                        } else {
                          setState(() {
                            _locationValue = val;
                            _addingLocation = false;
                            _newLocationCtrl.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: _qtyCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null) return 'Number';
                        if (n <= 0) return '≥ 1';
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              if (_addingLocation) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newLocationCtrl,
                  decoration:
                      const InputDecoration(labelText: 'New location name'),
                  onFieldSubmitted: (val) {
                    final newLoc =
                        val.trim().isEmpty ? 'Default' : val.trim();
                    if (!_locations.contains(newLoc)) {
                      setState(() {
                        _locations = [..._locations, newLoc]
                          ..sort((a, b) =>
                              a.toLowerCase().compareTo(b.toLowerCase()));
                      });
                    }
                    setState(() {
                      _locationValue = newLoc;
                      _addingLocation = false;
                    });
                  },
                ),
              ],

              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Save plant'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(ThemeData theme) {
    final path = _imagePath;
    if (path == null || path.isEmpty) {
      return Container(
        width: 160,
        height: 160,
        color: theme.colorScheme.surfaceVariant,
        child: const Icon(Icons.local_florist, size: 48),
      );
    }
    if (path.startsWith('http')) {
      return Image.network(
        path,
        width: 160,
        height: 160,
        fit: BoxFit.cover,
        cacheWidth: 512,
        cacheHeight: 512,
        filterQuality: FilterQuality.low,
      );
    }
    final f = File(path);
    if (f.existsSync()) {
      return Image.file(
        f,
        width: 160,
        height: 160,
        fit: BoxFit.cover,
        cacheWidth: 512,
        cacheHeight: 512,
        filterQuality: FilterQuality.low,
      );
    }
    return Container(
      width: 160,
      height: 160,
      color: theme.colorScheme.surfaceVariant,
      child: const Icon(Icons.local_florist, size: 48),
    );
  }
}
