// lib/services/cloud_sync.dart
import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/db_helper.dart';
import '../models/plant.dart';

class CloudSync {
  static final SupabaseClient _supa = Supabase.instance.client;

  static RealtimeChannel? _plantsChannel;
  static bool _realtimeStarted = false;
  static Timer? _pullDebounce;

  /// Pull all plants from cloud and merge into local (cloud qty wins on pull).
  static Future<void> pullAndMerge() async {
    // No generics with select() in supabase_flutter 2.x
    final rows = await _supa.from('plants').select('*');
    if (rows is! List) return;

    for (final row in rows) {
      if (row is! Map) continue;
      final r = row.cast<String, dynamic>();

      final name = (r['name'] ?? '').toString().trim();
      final type = (r['type'] ?? '').toString().trim();
      var location = (r['location'] ?? 'Default').toString().trim();
      if (location.isEmpty) location = 'Default';
      if (name.isEmpty || type.isEmpty) continue;

      final qty = _asInt(r['quantity']);
      final notesCloud = (r['notes'] ?? '').toString();
      final imagePathCloud = ((r['image_path'] ?? r['imagePath']) ?? '').toString();

      final local = await DatabaseHelper.findByNameTypeLocation(name, type, location);
      if (local == null) {
        await DatabaseHelper.insertPlant(
          name: name,
          type: type,
          location: location,
          quantity: qty,
          notes: notesCloud,
          imagePath: imagePathCloud.isEmpty ? null : imagePathCloud,
        );
      } else {
        final mergedNotes = notesCloud.trim().isNotEmpty ? notesCloud : (local.notes ?? '');
        final mergedImage = imagePathCloud.trim().isNotEmpty
            ? imagePathCloud
            : (local.imagePath ?? '');

        await DatabaseHelper.updateOrMergeOnEdit(
          id: local.id!,
          name: name,
          type: type,
          location: location,
          quantity: qty,
          notes: mergedNotes,
          imagePath: mergedImage.isEmpty ? null : mergedImage,
        );
      }
    }
  }

  /// Upsert plant and (if needed) upload local image file.
  /// Returns the uploaded image URL if we uploaded one, otherwise null.
  static Future<String?> pushPlant(Plant p) async {
    String? imgPath = p.imagePath;
    String? uploadedUrl;

    final looksLocalFile = imgPath != null &&
        imgPath.isNotEmpty &&
        !imgPath.startsWith('http');

    if (!kIsWeb && looksLocalFile && _platformSupportsFiles) {
      // No unnecessary '!' – imgPath is non-null here
      final maybeUrl = await uploadPlantImagePath(imgPath);
      if (maybeUrl != null && maybeUrl.isNotEmpty) {
        uploadedUrl = maybeUrl;
        imgPath = uploadedUrl;
      }
    }

    final payload = {
      'name': p.name.trim(),
      'type': p.type.trim(),
      'location': (p.location.trim().isEmpty) ? 'Default' : p.location.trim(),
      'quantity': p.quantity,
      'notes': p.notes ?? '',
      'image_path': imgPath ?? '',
    };

    // onConflict requires a unique index on (name,type,location) (you added this in SQL)
    await _supa
        .from('plants')
        .upsert(payload, onConflict: 'name,type,location')
        .select(); // surface errors

    return uploadedUrl;
  }

  /// Optional: delete from cloud by key
  static Future<void> pushDeleteByKey({
    required String name,
    required String type,
    required String location,
  }) async {
    await _supa.from('plants').delete().match({
      'name': name,
      'type': type,
      'location': location.isEmpty ? 'Default' : location,
    });
  }

  /// Realtime: auto-pull on changes (debounced).
  static Future<void> startRealtime() async {
    if (_realtimeStarted) return;
    _realtimeStarted = true;

    _plantsChannel = _supa
        .channel('public:plants')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'plants',
          callback: (_) {
            _pullDebounce?.cancel();
            _pullDebounce = Timer(const Duration(milliseconds: 600), () async {
              try {
                await pullAndMerge();
              } catch (_) {}
            });
          },
        )
        .subscribe();

    // supabase_flutter 2.x does not expose a realtime onReconnect API.
    // If you want a periodic safety pull, you can optionally schedule one here.
  }

  static Future<void> stopRealtime() async {
    _realtimeStarted = false;
    _pullDebounce?.cancel();
    _pullDebounce = null;
    final ch = _plantsChannel;
    if (ch != null) {
      await _supa.removeChannel(ch);
      _plantsChannel = null;
    }
  }

  /// Upload local image → Supabase Storage "plant-images" (public) with resize/compress.
  static Future<String?> uploadPlantImagePath(String localPath) async {
    if (kIsWeb || !_platformSupportsFiles) return null;
    try {
      const bucket = 'plant-images';
      final supa = Supabase.instance.client;

      final file = File(localPath);
      if (!file.existsSync()) return null;
      Uint8List bytes = await file.readAsBytes();

      // Resize/compress large images
      if (bytes.lengthInBytes > 1_500_000) {
        final optimized = await _optimizeForUpload(bytes, maxSide: 1600, jpegQuality: 80);
        if (optimized != null) bytes = optimized;
      }

      final name = localPath.split('/').last;
      final remotePath = '${DateTime.now().millisecondsSinceEpoch}_$name';

      final contentType = lookupMimeType(name) ?? 'image/jpeg';

      await supa.storage.from(bucket).uploadBinary(
        remotePath,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );

      return supa.storage.from(bucket).getPublicUrl(remotePath);
    } catch (_) {
      return null;
    }
  }

  // ------------ helpers ------------

  static bool get _platformSupportsFiles =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid || Platform.isIOS;

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.round() ?? 0;
  }

  static Future<Uint8List?> _optimizeForUpload(
    Uint8List bytes, {
    int maxSide = 1600,
    int jpegQuality = 80,
  }) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
      img.Image toEncode = decoded;
      if (longest > maxSide) {
        toEncode = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxSide : null,
          height: decoded.height > decoded.width ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
      }
      final jpg = img.encodeJpg(toEncode, quality: jpegQuality);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }
}
