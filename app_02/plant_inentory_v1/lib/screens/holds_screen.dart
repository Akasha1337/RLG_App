// lib/screens/holds_screen.dart
import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class HoldsScreen extends StatefulWidget {
  const HoldsScreen({super.key});
  @override
  State<HoldsScreen> createState() => _HoldsScreenState();
}

class _HoldsScreenState extends State<HoldsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseHelper.listActiveHolds();
  }

  Future<void> _refresh() async {
    final next = DatabaseHelper.listActiveHolds();
    setState(() {
      _future = next;
    });
    await next; // ✅ ensures RefreshIndicator waits for data
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Optional: add to pubspec assets if you want this image
            // assets:
            //   - assets/images/empty_plant.png
            Image.asset(
              'assets/images/empty_plant.png',
              width: 140,
              height: 140,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.local_florist,
                size: 64,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text('No active holds'),
            const SizedBox(height: 400),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Holds'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) return _emptyState();

          return RefreshIndicator(
            onRefresh: _refresh, // ✅ now returns Future<void>
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rows[i];
                final id = r['id'] as int;
                final title = '${r['plant_name']} (${r['plant_type']}) @ ${r['plant_location']}';
                final qty = r['quantity'] as int;
                final price = (r['price_each_cents'] as int) / 100.0;
                final customer = r['customer_name'] as String;
                final createdAt = r['created_at'] as String?;

                return ListTile(
                  title: Text(title),
                  subtitle: Text(
                    '$customer • $qty × \$${price.toStringAsFixed(2)}'
                    '${createdAt != null ? ' • ${DateTime.tryParse(createdAt)?.toLocal().toString().split(".").first ?? ""}' : ""}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await DatabaseHelper.sellHold(id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Sold')),
                          );
                          await _refresh();
                        },
                        child: const Text('Sell'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await DatabaseHelper.cancelHold(id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cancelled')),
                          );
                          await _refresh();
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
