import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../database/db_helper.dart';
import '../services/export_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashData> _load() async {
    final totals = await DatabaseHelper.getTotals();
    final byLoc  = await DatabaseHelper.getQuantityByLocation();
    final byType = await DatabaseHelper.getQuantityByType();
    return _DashData(totals: totals, byLocation: byLoc, byType: byType);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard & Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _future = _load();
              });
            },
          ),
          IconButton(
            tooltip: 'Export XLSX',
            icon: const Icon(Icons.file_download),
            onPressed: () async {
              final path = await ExportService.exportInventoryXlsx();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Saved spreadsheet:\n$path')),
              );
              // Optional: reveal on Windows/macOS
              // await OsOpen.revealInFileManager(path);
            },
          ),
        ],
        
      ),
      body: FutureBuilder<_DashData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data ?? _DashData(
          totals: const {
            'distinctEntries': 0,
            'totalQuantity': 0,
            'distinctLocations': 0,
            'distinctTypes': 0,
          },
          byLocation: const [],
          byType: const [],
          );
          final totals = data.totals;
          final byLoc = data.byLocation;    
          final byType = data.byType;

          final totalEntries   = totals['distinctEntries'] ?? 0;
          final totalQuantity  = totals['totalQuantity'] ?? 0;
          final totalLocations = totals['distinctLocations'] ?? 0;
          final totalTypes     = totals['distinctTypes'] ?? 0;

          if (totalEntries == 0) {
            return _emptyState(context);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              // Top KPIs
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpiCard(context, 'Total Quantity', totalQuantity.toString(), Icons.inventory_2),
                  _kpiCard(context, 'Unique Entries', totalEntries.toString(), Icons.dataset),
                  _kpiCard(context, 'Locations', totalLocations.toString(), Icons.place),
                  _kpiCard(context, 'Types', totalTypes.toString(), Icons.category),
                ],
              ),
              const SizedBox(height: 20),

              // Bar: Quantity by Location
              _sectionTitle(context, 'Quantity by Location'),
              const SizedBox(height: 8),
              _BarByLocation(data: byLoc),

              const SizedBox(height: 24),

              // Pie: Quantity by Type
              _sectionTitle(context, 'Quantity by Type'),
              const SizedBox(height: 8),
              _PieByType(data: byType),

              const SizedBox(height: 24),

              // Small table summaries (optional, helpful)
              _sectionTitle(context, 'Top Locations'),
              _miniList(byLoc, labelKey: 'location'),
              const SizedBox(height: 16),
              _sectionTitle(context, 'Top Types'),
              _miniList(byType, labelKey: 'type'),
            ],
          );
        },
      ),
    );
  }

  Widget _kpiCard(BuildContext context, String title, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }

  Widget _miniList(List<Map<String, dynamic>> rows, {required String labelKey}) {
    final max = rows.take(5).toList();
    return Card(
      child: Column(
        children: [
          for (final r in max)
            ListTile(
              dense: true,
              title: Text('${r[labelKey]}'),
              trailing: Text('${r['qty']}'),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insights, size: 56, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 12),
          const Text('No data yet'),
          const SizedBox(height: 6),
          const Text('Add plants to see analytics.'),
        ],
      ),
    );
  }
}

class _DashData {
  final Map<String, int> totals;
  final List<Map<String, dynamic>> byLocation;
  final List<Map<String, dynamic>> byType;
  _DashData({required this.totals, required this.byLocation, required this.byType});
}

/// BAR CHART: Quantity by Location
class _BarByLocation extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _BarByLocation({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _placeholder(context, 'No locations yet');

    // Show up to 8 bars (most significant)
    final top = data.take(8).toList();
    final maxQty = top.fold<double>(0, (m, r) => (r['qty'] as num).toDouble() > m ? (r['qty'] as num).toDouble() : m);
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < top.length; i++) {
      final qty = (top[i]['qty'] as num).toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: qty, width: 18, borderRadius: BorderRadius.circular(6))],
        ),
      );
    }
    return SizedBox(
      height: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 24, 12),
          child: BarChart(
            BarChartData(
              maxY: (maxQty == 0) ? 1 : maxQty * 1.15,
              barGroups: groups,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= top.length) return const SizedBox();
                      final label = '${top[idx]['location']}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_short(label), textAlign: TextAlign.center),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ),
    );
  }

  static String _short(String s) => s.length <= 8 ? s : '${s.substring(0, 7)}…';

  Widget _placeholder(BuildContext ctx, String msg) => SizedBox(
        height: 140,
        child: Card(
          child: Center(child: Text(msg)),
        ),
      );
}

/// PIE CHART: Quantity by Type
class _PieByType extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _PieByType({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _placeholder(context, 'No types yet');

    final top = data.take(6).toList();
    final total = top.fold<double>(0, (m, r) => m + (r['qty'] as num).toDouble());
    if (total == 0) return _placeholder(context, 'No quantities yet');

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < top.length; i++) {
      final qty = (top[i]['qty'] as num).toDouble();
      final pct = (qty / total * 100).toStringAsFixed(0);
      sections.add(
        PieChartSectionData(
          value: qty,
          title: '${top[i]['type']}\n$pct%',
          radius: 60,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }

    return SizedBox(
      height: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: sections,
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext ctx, String msg) => SizedBox(
        height: 140,
        child: Card(
          child: Center(child: Text(msg)),
        ),
      );
}
