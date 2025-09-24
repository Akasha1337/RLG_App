// lib/screens/plant_list_screen.dart
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/db_helper.dart';
import '../models/plant.dart';
import '../services/cloud_sync.dart';

import 'add_plant_screen.dart';
import 'edit_plant_screen.dart';
import 'dashboard_screen.dart';
import 'holds_screen.dart';
import 'settings_screen.dart';

class PlantListScreen extends StatefulWidget {
  const PlantListScreen({super.key});
  @override
  State<PlantListScreen> createState() => _PlantListScreenState();
}

class _PlantListScreenState extends State<PlantListScreen> {
  List<Plant> _plants = [];
  String _query = '';
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    () async {
      await _loadPlants();                // show local instantly
      try {
        await CloudSync.pullAndMerge();   // refresh from cloud
        if (!mounted) return;
        await _loadPlants();              // reflect merged data
      } finally {
        if (mounted) {
          await CloudSync.startRealtime(); // listen for changes
        }
      }
    }();
  }

  @override
  void dispose() {
    CloudSync.stopRealtime();
    super.dispose();
  }

  Future<void> _loadPlants() async {
    final data = await DatabaseHelper.getPlants();
    if (!mounted) return;
    setState(() => _plants = data);
  }

  Future<void> _addPlant() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddPlantScreen()),
    );
    if (!mounted) return;
    if (ok == true) await _loadPlants();
  }

  Future<void> _delete(Plant p) async {
    if (p.id == null) return;
    await DatabaseHelper.deletePlant(p.id!);
    if (!mounted) return;
    await _loadPlants();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${p.name} (${p.type}) @ ${p.location.isEmpty ? 'Default' : p.location}')),
    );
  }

  Future<void> _showHoldDialog(Plant p) async {
    final nameCtrl = TextEditingController();
    final qtyCtrl  = TextEditingController(text: '1');
    final priceCtrl= TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hold: ${p.name} (${p.type})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer name')),
            const SizedBox(height: 8),
            TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Price each (e.g. 19.99)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Place Hold')),
        ],
      ),
    );

    if (ok != true) return;

    final custName = nameCtrl.text.trim();
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    final priceCents = ((double.tryParse(priceCtrl.text.trim()) ?? 0) * 100).round();

    if (custName.isEmpty || qty <= 0 || priceCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter name, qty>0, and price.')));
      return;
    }

    try {
      final customerId = await DatabaseHelper.upsertCustomerByName(name: custName);
      await DatabaseHelper.createHold(
        customerId: customerId,
        plantId: p.id!,
        quantity: qty,
        priceEachCents: priceCents,
      );
      await _loadPlants();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Held $qty × ${p.name} for $custName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hold failed: $e')));
    }
  }

  List<Plant> get _filtered {
    if (_query.trim().isEmpty) return _plants;
    final q = _query.toLowerCase();
    return _plants.where((p) =>
      p.name.toLowerCase().contains(q) ||
      p.type.toLowerCase().contains(q) ||
      (p.location.isNotEmpty && p.location.toLowerCase().contains(q))
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Group by location (case-insensitive sort)
    final byLoc = <String, List<Plant>>{};
    for (final p in _filtered) {
      final key = p.location.isEmpty ? 'Default' : p.location;
      byLoc.putIfAbsent(key, () => []).add(p);
    }
    final locKeys = byLoc.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Inventory'),
        actions: [
          IconButton(
            tooltip: 'Holds',
            icon: const Icon(Icons.assignment_turned_in_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HoldsScreen())),
          ),
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
          ),
          IconButton(
            tooltip: 'Pull from cloud',
            icon: _pulling
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download),
            onPressed: _pulling ? null : () async {
              setState(() => _pulling = true);
              try {
                await CloudSync.pullAndMerge();
                await _loadPlants();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inventory updated from cloud')));
              } finally {
                if (mounted) setState(() => _pulling = false);
              }
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search name, type, or location',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _query = ''),
                        tooltip: 'Clear',
                      ),
              ),
              onChanged: (text) => setState(() => _query = text),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await CloudSync.pullAndMerge();
          await _loadPlants();
        },
        child: locKeys.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  _EmptyState(),
                  SizedBox(height: 400),
                ],
              )
            : ListView.builder(
                itemCount: locKeys.length,
                itemBuilder: (_, i) {
                  final loc = locKeys[i];

                  // make a sorted copy (List.sort returns void)
                  final items = List<Plant>.from(byLoc[loc] ?? []);
                  items.sort((a, b) {
                    final an = a.name.toLowerCase();
                    final bn = b.name.toLowerCase();
                    final at = a.type.toLowerCase();
                    final bt = b.type.toLowerCase();
                    return an == bn ? at.compareTo(bt) : an.compareTo(bn);
                  });

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location header chip
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.place, size: 18, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                loc,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Items under this location
                      ...items.map((p) => Card(
                            child: ListTile(
                              leading: _TileThumb(path: p.imagePath),
                              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${p.type} • Qty: ${p.quantity}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'hold') {
                                    await _showHoldDialog(p);
                                  } else if (v == 'delete') {
                                    await _delete(p);
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: 'hold', child: Text('Hold for customer')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                              onTap: () async {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(builder: (_) => EditPlantScreen(plant: p)),
                                );
                                if (!mounted) return;
                                if (changed == true) await _loadPlants();
                              },
                            ),
                          )),
                    ],
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPlant,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.local_florist, size: 56, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 12),
        const Text('No plants yet'),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TileThumb extends StatelessWidget {
  final String? path;
  const _TileThumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final p = (path ?? '').trim();
    Widget thumb;

    if (p.isEmpty) {
      thumb = _placeholder(context);
    } else if (p.startsWith('http')) {
      thumb = Image.network(
        p,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        cacheWidth: 256,
        cacheHeight: 256,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    } else {
      // Windows + iOS local file
      try {
        final f = File(p);
        if (f.existsSync()) {
          thumb = Image.file(
            f,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            cacheWidth: 256,
            cacheHeight: 256,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => _placeholder(context),
          );
        } else {
          thumb = _placeholder(context);
        }
      } catch (_) {
        thumb = _placeholder(context);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: thumb,
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        width: 56,
        height: 56,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.local_florist),
      );
}
