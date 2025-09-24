import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/export_service.dart';
import '../services/os_open.dart';
import '../theme/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = '${info.version} (${info.buildNumber})');
  }

  Future<void> _exportInventoryCsv() async {
    final path = await ExportService.exportInventoryCsv(alsoUpload: true);
    _afterExportSnack('CSV', path);
  }

  Future<void> _exportInventoryXlsx() async {
    final path = await ExportService.exportInventoryXlsx(alsoUpload: true);
    _afterExportSnack('XLSX', path);
  }

  Future<void> _exportHoldsCsv() async {
    final path = await ExportService.exportActiveHoldsCsv(alsoUpload: true);
    _afterExportSnack('Holds CSV', path);
  }

  Future<void> _exportHoldsXlsx() async {
    final path = await ExportService.exportActiveHoldsXlsx(alsoUpload: true);
    _afterExportSnack('Holds XLSX', path);
  }

  void _afterExportSnack(String label, String path) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await OsOpen.revealInFileManager(path);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label exported${kIsWeb ? '' : ' to $path'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = ThemeController.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Theme'),
            subtitle: const Text('System / Light / Dark'),
          ),
          ValueListenableBuilder(
            valueListenable: tc.themeMode,
            builder: (_, __, ___) => Column(
              children: [
                RadioListTile<ThemeChoice>(
                  title: const Text('System'),
                  value: ThemeChoice.system,
                  groupValue: tc.choice,
                  onChanged: (v) => tc.set(v!),
                ),
                RadioListTile<ThemeChoice>(
                  title: const Text('Light'),
                  value: ThemeChoice.light,
                  groupValue: tc.choice,
                  onChanged: (v) => tc.set(v!),
                ),
                RadioListTile<ThemeChoice>(
                  title: const Text('Dark'),
                  value: ThemeChoice.dark,
                  groupValue: tc.choice,
                  onChanged: (v) => tc.set(v!),
                ),
              ],
            ),
          ),
          const Divider(),

          ListTile(
            title: const Text('Exports'),
            subtitle: const Text('Download locally and upload to Supabase /backups'),
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Export Inventory (CSV)'),
            onTap: _exportInventoryCsv,
          ),
          ListTile(
            leading: const Icon(Icons.grid_on),
            title: const Text('Export Inventory (XLSX)'),
            onTap: _exportInventoryXlsx,
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('Export Holds (CSV)'),
            onTap: _exportHoldsCsv,
          ),
          ListTile(
            leading: const Icon(Icons.grid_on),
            title: const Text('Export Holds (XLSX)'),
            onTap: _exportHoldsXlsx,
          ),
          if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Open Exports Folder'),
              onTap: () async {
                final folder = await ExportService.getExportsFolderPath();
                await OsOpen.openFolder(folder);
              },
            ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Text('Version $_version'),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
