// lib/services/export_service.dart
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart' as ex;

import '../database/db_helper.dart';
import '../models/plant.dart';

class ExportService {
  /// Exports inventory to CSV → saves to app Documents → uploads to Supabase Storage (bucket: `backups`).
  /// Returns the local file path (on non-web). On web, returns a pseudo path.
  static Future<String> exportInventoryCsv({bool alsoUpload = true}) async {
    final plants = await DatabaseHelper.getPlants();

    final csv = StringBuffer();
    _writeCsvHeader(csv, const ['name','type','location','quantity','notes','imagePath']);

    for (final Plant p in plants) {
      _writeCsvRow(csv, [
        p.name,
        p.type,
        p.location.isEmpty ? 'Default' : p.location,
        p.quantity.toString(),
        p.notes ?? '',
        p.imagePath ?? '',
      ]);
    }

    final outPath = await _saveCsvToDocuments(
      filenamePrefix: 'inventory',
      content: csv.toString(),
    );

    if (alsoUpload) {
      await _uploadCsvToStorage(
        remotePrefix: 'inventory',
        localPath: outPath,
        content: csv.toString(),
      );
    }

    return outPath;
  }

  /// Exports ACTIVE holds (status='HOLD') → saves to Documents → uploads to Supabase Storage.
  static Future<String> exportActiveHoldsCsv({bool alsoUpload = true}) async {
    final rows = await DatabaseHelper.listActiveHolds();

    final csv = StringBuffer();
    _writeCsvHeader(csv, const [
      'customer','plant_name','plant_type','plant_location','quantity','price_each','created_at'
    ]);

    for (final r in rows) {
      final cents = (r['price_each_cents'] ?? 0) as int;
      final priceEach = (cents / 100.0).toStringAsFixed(2);

      _writeCsvRow(csv, [
        (r['customer_name'] ?? '').toString(),
        (r['plant_name'] ?? '').toString(),
        (r['plant_type'] ?? '').toString(),
        (r['plant_location'] ?? 'Default').toString(),
        (r['quantity'] ?? '').toString(),
        priceEach,
        (r['created_at'] ?? '').toString(),
      ]);
    }

    final outPath = await _saveCsvToDocuments(
      filenamePrefix: 'holds_active',
      content: csv.toString(),
    );

    if (alsoUpload) {
      await _uploadCsvToStorage(
        remotePrefix: 'holds_active',
        localPath: outPath,
        content: csv.toString(),
      );
    }

    return outPath;
  }

  // ------------------ CSV helpers ------------------

  // Windows/Excel friendly line endings.
  static const String _eol = '\r\n';
  // Enable if Excel needs a BOM to auto-detect UTF-8.
  static const bool _includeBom = false;

  static void _writeCsvHeader(StringBuffer sb, List<String> cols) {
    sb.write(cols.map(_escapeCsv).join(','));
    sb.write(_eol);
  }

  static void _writeCsvRow(StringBuffer sb, List<String> cols) {
    sb.write(cols.map(_escapeCsv).join(','));
    sb.write(_eol);
  }

  static String _escapeCsv(String value) {
    final s = value.replaceAll('"', '""');
    return '"$s"';
  }

  static Future<String> _saveCsvToDocuments({
    required String filenamePrefix,
    required String content,
  }) async {
    final ts = _timestamp();
    final filename = '$filenamePrefix-$ts.csv';

    if (kIsWeb) {
      // No local FS on web.
      return '/web/$filename';
    }

    final dir = await getApplicationDocumentsDirectory();
    final outPath = p.join(dir.path, filename);
    final file = File(outPath);

    final bytes = _includeBom
        ? Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)])
        : Uint8List.fromList(utf8.encode(content));

    await file.writeAsBytes(bytes, flush: true);
    return outPath;
  }

  static Future<void> _uploadCsvToStorage({
    required String localPath,
    required String remotePrefix,
    required String content,
  }) async {
    final supa = Supabase.instance.client;
    final ts = _timestamp();
    final remotePath = 'backups/$remotePrefix-$ts.csv';

    Future<void> doUpload(Uint8List bytes) async {
      await supa.storage.from('backups').uploadBinary(
            remotePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'text/csv'),
          );
    }

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        if (kIsWeb) {
          await doUpload(Uint8List.fromList(utf8.encode(content)));
        } else {
          final f = File(localPath);
          if (await f.exists()) {
            await doUpload(await f.readAsBytes());
          } else {
            await doUpload(Uint8List.fromList(utf8.encode(content)));
          }
        }
        return;
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// Returns the folder path where CSV exports are saved (desktop/mobile).
  /// On web, there is no local filesystem, so we return a pseudo path.
  static Future<String> getExportsFolderPath() async {
    if (kIsWeb) return '/web';
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  // ---------------- XLSX EXPORTS (excel v4, no column width calls) ----------------

  /// Exports inventory to a native Excel workbook (.xlsx).
  static Future<String> exportInventoryXlsx({bool alsoUpload = true}) async {
    final plants = await DatabaseHelper.getPlants();

    final wb = ex.Excel.createExcel();
    final sh = wb['Inventory'];

    // headers
    const headers = ['name','type','location','quantity','notes','imagePath'];
    sh.appendRow(_cells(headers));

    // rows
    for (final p in plants) {
      sh.appendRow(_cells(<Object?>[
        p.name,
        p.type,
        p.location.isEmpty ? 'Default' : p.location,
        p.quantity,                 // numeric
        p.notes ?? '',
        p.imagePath ?? '',
      ]));
    }

    final bytes = Uint8List.fromList(wb.encode()!);
    final outPath = await _saveBytesToDocuments(
      filenamePrefix: 'inventory',
      extension: 'xlsx',
      bytes: bytes,
    );

    if (alsoUpload) {
      await _uploadBytesToStorage(
        remotePrefix: 'inventory',
        extension: 'xlsx',
        bytes: bytes,
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }
    return outPath;
  }

  /// Exports ACTIVE holds to Excel (.xlsx).
  static Future<String> exportActiveHoldsXlsx({bool alsoUpload = true}) async {
    final rows = await DatabaseHelper.listActiveHolds();

    final wb = ex.Excel.createExcel();
    final sh = wb['Active Holds'];

    const headers = [
      'customer','plant_name','plant_type','plant_location','quantity','price_each','created_at'
    ];
    sh.appendRow(_cells(headers));

    for (final r in rows) {
      final cents = (r['price_each_cents'] ?? 0) as int;
      final priceEach = cents / 100.0; // numeric

      sh.appendRow(_cells(<Object?>[
        (r['customer_name'] ?? '').toString(),
        (r['plant_name'] ?? '').toString(),
        (r['plant_type'] ?? '').toString(),
        (r['plant_location'] ?? 'Default').toString(),
        (r['quantity'] ?? 0) as int,  // numeric
        priceEach,                    // numeric
        (r['created_at'] ?? '').toString(),
      ]));
    }

    final bytes = Uint8List.fromList(wb.encode()!);
    final outPath = await _saveBytesToDocuments(
      filenamePrefix: 'holds_active',
      extension: 'xlsx',
      bytes: bytes,
    );

    if (alsoUpload) {
      await _uploadBytesToStorage(
        remotePrefix: 'holds_active',
        extension: 'xlsx',
        bytes: bytes,
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }
    return outPath;
  }

  // Map a dynamic row to excel v4 cells
  static List<ex.CellValue?> _cells(List<Object?> values) {
    return values.map<ex.CellValue?>((v) {
      if (v == null) return null;
      if (v is int) return ex.IntCellValue(v);
      if (v is double) return ex.DoubleCellValue(v);
      if (v is num) return ex.DoubleCellValue(v.toDouble());
      if (v is bool) return ex.BoolCellValue(v);
      if (v is DateTime) {
        // excel v4: only date parts available here
        return ex.DateCellValue(
          year: v.year,
          month: v.month,
          day: v.day,
        );
      }
      return ex.TextCellValue(v.toString());
    }).toList();
  }
  // ---------------- shared XLSX helpers ----------------

  static Future<String> _saveBytesToDocuments({
    required String filenamePrefix,
    required String extension, // 'xlsx'
    required Uint8List bytes,
  }) async {
    final ts = _timestamp();
    final filename = '$filenamePrefix-$ts.$extension';

    if (kIsWeb) {
      return '/web/$filename';
    }

    final dir = await getApplicationDocumentsDirectory();
    final outPath = p.join(dir.path, filename);
    final file = File(outPath);
    await file.writeAsBytes(bytes, flush: true);
    return outPath;
  }

  static Future<void> _uploadBytesToStorage({
    required String remotePrefix,
    required String extension, // 'xlsx'
    required Uint8List bytes,
    required String contentType,
  }) async {
    final supa = Supabase.instance.client;
    final ts = _timestamp();
    final remotePath = 'backups/$remotePrefix-$ts.$extension';

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        await supa.storage.from('backups').uploadBinary(
          remotePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType), // ✅ Supabase FileOptions
        );
        return;
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
  }
}
