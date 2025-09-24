import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/plant.dart';

class UpsertOutcome {
  final bool merged;
  final int delta;
  UpsertOutcome(this.merged, this.delta);
}

class DatabaseHelper {
  static Database? _db;

   static Future<Database> getDB() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'plants.db');
    _db = await openDatabase(
      path,
      version: 7, // keep your version
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON'); // ✅ enforce FKs
      },
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE plants (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            type TEXT,
            quantity INTEGER,
            notes TEXT,
            imagePath TEXT,
            location TEXT
          )
        ''');

        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_name_type_loc '
          'ON plants(name COLLATE NOCASE, type COLLATE NOCASE, location COLLATE NOCASE)'
        );

        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE holds (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            plant_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            price_each_cents INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'HOLD',
            created_at TEXT NOT NULL,
            closed_at TEXT,
            FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE CASCADE,
            FOREIGN KEY(plant_id) REFERENCES plants(id) ON DELETE CASCADE
          )
        ''');

        // (Optional) helpful indices
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_plants_location ON plants(location COLLATE NOCASE)'
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_plants_type ON plants(type COLLATE NOCASE)'
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_holds_status_created ON holds(status, created_at)'
        );
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 4) {
          await db.execute('ALTER TABLE plants ADD COLUMN type TEXT;').catchError((_) {});
          await db.execute('UPDATE plants SET type = COALESCE(type, category);').catchError((_) {});
        }
        if (oldV < 5) {
          await db.execute('ALTER TABLE plants ADD COLUMN imagePath TEXT;').catchError((_) {});
        }
        if (oldV < 6) {
          await db.execute('ALTER TABLE plants ADD COLUMN location TEXT;').catchError((_) {});
          await db.execute("UPDATE plants SET location = COALESCE(location, 'Default');");
          await db.execute('''
            CREATE TABLE plants_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              type TEXT,
              quantity INTEGER,
              notes TEXT,
              imagePath TEXT,
              location TEXT
            )
          ''');
          await db.execute('''
            INSERT INTO plants_new (name, type, quantity, notes, imagePath, location)
            SELECT name, type,
                  SUM(COALESCE(quantity,0)),
                  MAX(CASE WHEN TRIM(COALESCE(notes,''))<>'' THEN notes ELSE NULL END),
                  MAX(CASE WHEN TRIM(COALESCE(imagePath,''))<>'' THEN imagePath ELSE NULL END),
                  location
            FROM plants
            GROUP BY name COLLATE NOCASE, type COLLATE NOCASE, location COLLATE NOCASE
          ''');
          await db.execute('DROP TABLE plants');
          await db.execute('ALTER TABLE plants_new RENAME TO plants');
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_name_type_loc '
            'ON plants(name COLLATE NOCASE, type COLLATE NOCASE, location COLLATE NOCASE)'
          );
        }
        if (oldV < 7) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS customers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              phone TEXT,
              email TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS holds (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              customer_id INTEGER NOT NULL,
              plant_id INTEGER NOT NULL,
              quantity INTEGER NOT NULL,
              price_each_cents INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'HOLD',
              created_at TEXT NOT NULL,
              closed_at TEXT,
              FOREIGN KEY(customer_id) REFERENCES customers(id) ON DELETE CASCADE,
              FOREIGN KEY(plant_id) REFERENCES plants(id) ON DELETE CASCADE
            )
          ''');

          // (Optional) helpful indices on upgrade too
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_plants_location ON plants(location COLLATE NOCASE)'
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_plants_type ON plants(type COLLATE NOCASE)'
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_holds_status_created ON holds(status, created_at)'
          );
        }
      },
    );
    return _db!;
  }

  static Future<List<Plant>> getPlants() async {
    final db = await getDB();
    final maps = await db.query(
      'plants',
      orderBy: 'location COLLATE NOCASE, name COLLATE NOCASE, type COLLATE NOCASE',
    );
    return maps.map((m) => Plant.fromMap(m)).toList();
  }

  static Future<int> deletePlant(int id) async {
    final db = await getDB();
    return db.delete('plants', where: 'id=?', whereArgs: [id]);
  }

  static Future<int> updatePlant(Plant p) async {
    final db = await getDB();
    return db.update('plants', p.toMap(), where: 'id=?', whereArgs: [p.id]);
  }

  // Upsert by (name,type,location)
  static Future<UpsertOutcome> upsertByNameTypeLocation({
    required String name,
    required String type,
    required String location,
    required int deltaQuantity,
    String notes = '',
    String? imagePath,
  }) async {
    final db = await getDB();

    final updated = await db.rawUpdate(
      '''
      UPDATE plants
        SET quantity = quantity + ?,
            notes    = CASE
                          WHEN TRIM(?) <> '' THEN ?
                          ELSE notes
                        END,
            imagePath= CASE
                          WHEN (imagePath IS NULL OR TRIM(imagePath) = '' OR
                                LOWER(imagePath) NOT LIKE 'http%') AND TRIM(COALESCE(?, '')) <> ''
                            THEN ?
                          ELSE imagePath
                        END
      WHERE LOWER(name)=LOWER(?) AND LOWER(type)=LOWER(?) AND LOWER(location)=LOWER(?)
      ''',
      [
        deltaQuantity,
        notes, notes,
        imagePath, imagePath,
        name, type, location,
      ],
    );

    if (updated > 0) return UpsertOutcome(true, deltaQuantity);

    await db.insert('plants', {
      'name': name,
      'type': type,
      'location': location.isEmpty ? 'Default' : location,
      'quantity': deltaQuantity,
      'notes': notes,
      'imagePath': imagePath,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    return UpsertOutcome(false, deltaQuantity);
  }
  // Edit: update row; if (name,type,location) collides with another row, merge.
  static Future<void> updateOrMergeOnEdit({
    required int id,
    required String name,
    required String type,
    required String location,
    required int quantity,
    required String notes,
    String? imagePath,
    }) async {
    final db = await getDB();
    await db.transaction((txn) async {
      final dup = await txn.query(
        'plants',
        where: 'LOWER(name)=LOWER(?) AND LOWER(type)=LOWER(?) AND LOWER(location)=LOWER(?) AND id<>?',
        whereArgs: [name, type, location, id],
        limit: 1,
      );

      if (dup.isEmpty) {
        await txn.update(
          'plants',
          {
            'name': name,
            'type': type,
            'location': location,
            'quantity': quantity,
            'notes': notes,
            'imagePath': imagePath,
          },
          where: 'id=?',
          whereArgs: [id],
        );
        return;
      }

      final target = dup.first;
      final targetId = target['id'] as int;
      final mergedQty = (target['quantity'] as int? ?? 0) + quantity;
      final mergedNotes = notes.trim().isNotEmpty
          ? notes
          : (target['notes'] as String? ?? '');

      final targetImage = (target['imagePath'] as String?)?.trim() ?? '';
      final incoming = (imagePath ?? '').trim();

      final mergedImage = (targetImage.isNotEmpty && targetImage.toLowerCase().startsWith('http'))
          ? targetImage
          : (incoming.isNotEmpty ? incoming : (targetImage.isNotEmpty ? targetImage : null));

      await txn.update('plants', {
        'quantity': mergedQty,
        'notes': mergedNotes,
        'imagePath': mergedImage,
      }, where: 'id=?', whereArgs: [targetId]);

      await txn.delete('plants', where: 'id=?', whereArgs: [id]);
    });
  }

  // Distinct list of locations (sorted)
  static Future<List<String>> getDistinctLocations() async {
    final db = await getDB();
    final rows = await db.rawQuery('''
      SELECT DISTINCT location
      FROM plants
      WHERE TRIM(COALESCE(location, '')) <> ''
      ORDER BY location COLLATE NOCASE
    ''');
    return rows
        .map((r) => (r['location'] as String?) ?? '')
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  // --- DASHBOARD QUERIES ---

  /// Totals for header cards.
  /// - distinctEntries: number of rows (unique (name,type,location))
  /// - totalQuantity: sum of quantity across all rows
  /// - distinctLocations: count of unique locations
  /// - distinctTypes: count of unique types
  static Future<Map<String, int>> getTotals() async {
    final db = await getDB();
    // Use COALESCE to avoid nulls
    final rows = await db.rawQuery('''
      SELECT 
        COUNT(*) AS distinctEntries,
        COALESCE(SUM(quantity), 0) AS totalQuantity,
        (SELECT COUNT(DISTINCT LOWER(TRIM(COALESCE(location,'')))) FROM plants) AS distinctLocations,
        (SELECT COUNT(DISTINCT LOWER(TRIM(COALESCE(type,'')))) FROM plants) AS distinctTypes
      FROM plants
    ''');
    final r = rows.first;
    return {
      'distinctEntries': (r['distinctEntries'] as int?) ?? 0,
      'totalQuantity': (r['totalQuantity'] as int?) ?? 0,
      'distinctLocations': (r['distinctLocations'] as int?) ?? 0,
      'distinctTypes': (r['distinctTypes'] as int?) ?? 0,
    };
  }

  /// Sum of quantity grouped by location (descending)
  static Future<List<Map<String, dynamic>>> getQuantityByLocation() async {
    final db = await getDB();
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(COALESCE(location,'')), ''), 'Default') AS location,
            COALESCE(SUM(quantity), 0) AS qty
      FROM plants
      GROUP BY location COLLATE NOCASE
      ORDER BY qty DESC, location COLLATE NOCASE ASC
    ''');
    return rows;
  }

  /// Sum of quantity grouped by type (descending)
  static Future<List<Map<String, dynamic>>> getQuantityByType() async {
    final db = await getDB();
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(COALESCE(type,'')), ''), 'Unknown') AS type,
            COALESCE(SUM(quantity), 0) AS qty
      FROM plants
      GROUP BY type COLLATE NOCASE
      ORDER BY qty DESC, type COLLATE NOCASE ASC
    ''');
    return rows;
  }

  static String _nowIso() => DateTime.now().toIso8601String();

  static Future<int> upsertCustomerByName({required String name, String? phone, String? email}) async {
    final db = await getDB();
    // find by case-insensitive name
    final existing = await db.query(
      'customers',
      where: "LOWER(name) LIKE ? OR LOWER(COALESCE(phone, '')) LIKE ? OR LOWER(COALESCE(email, '')) LIKE ?",
      whereArgs: [name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('customers', {
        'phone': phone,
        'email': email,
      }, where: 'id=?', whereArgs: [id]);
      return id;
    }
    return await db.insert('customers', {
      'name': name,
      'phone': phone,
      'email': email,
    });
  }

  static Future<List<Map<String, dynamic>>> listCustomers({String q = ''}) async {
    final db = await getDB();
    if (q.trim().isEmpty) {
      return db.query('customers', orderBy: 'name COLLATE NOCASE');
    }
    final like = '%${q.toLowerCase()}%';
    return db.query('customers',
        orderBy: 'name COLLATE NOCASE',
        where: 'LOWER(name) LIKE ? OR LOWER(COALESCE(phone,"")) LIKE ? OR LOWER(COALESCE(email,"")) LIKE ?',
        whereArgs: [like, like, like]);
  }

  /// Place a HOLD for a customer on a plant (decrements available quantity immediately).
  /// If you prefer to NOT decrement stock on hold, remove the update to plants below.
  static Future<void> createHold({
    required int customerId,
    required int plantId,
    required int quantity,
    required int priceEachCents,
  }) async {
    final db = await getDB();
    await db.transaction((txn) async {
      // Check current qty
      final p = await txn.query('plants', where: 'id=?', whereArgs: [plantId], limit: 1);
      if (p.isEmpty) throw Exception('Plant not found');
      final cur = (p.first['quantity'] ?? 0) as int;
      if (quantity <= 0) throw Exception('Quantity must be > 0');
      if (cur < quantity) throw Exception('Not enough stock');

      // reduce on-hand immediately (reserve)
      await txn.update('plants', {'quantity': cur - quantity}, where: 'id=?', whereArgs: [plantId]);

      // create hold row
      await txn.insert('holds', {
        'customer_id': customerId,
        'plant_id': plantId,
        'quantity': quantity,
        'price_each_cents': priceEachCents,
        'status': 'HOLD',
        'created_at': _nowIso(),
      });
    });
  }

  /// Convert an existing HOLD to SOLD (does NOT change stock because it was reserved already).
  static Future<void> sellHold(int holdId) async {
    final db = await getDB();
    await db.update('holds', {
      'status': 'SOLD',
      'closed_at': _nowIso(),
    }, where: 'id=?', whereArgs: [holdId]);
  }

  /// Cancel a HOLD and return quantity to stock.
  static Future<void> cancelHold(int holdId) async {
    final db = await getDB();
    await db.transaction((txn) async {
      final h = await txn.query('holds', where: 'id=?', whereArgs: [holdId], limit: 1);
      if (h.isEmpty) return;
      if ((h.first['status'] as String) != 'HOLD') return; // ignore already sold/cancelled

      final qty = (h.first['quantity'] ?? 0) as int;
      final plantId = (h.first['plant_id'] as int);
      // return to stock
      final p = await txn.query('plants', where: 'id=?', whereArgs: [plantId], limit: 1);
      if (p.isNotEmpty) {
        final cur = (p.first['quantity'] ?? 0) as int;
        await txn.update('plants', {'quantity': cur + qty}, where: 'id=?', whereArgs: [plantId]);
      }

      await txn.update('holds', {
        'status': 'CANCELLED',
        'closed_at': _nowIso(),
      }, where: 'id=?', whereArgs: [holdId]);
    });
  }

  /// List active holds
  static Future<List<Map<String, dynamic>>> listActiveHolds() async {
    final db = await getDB();
    return db.rawQuery('''
      SELECT h.id, h.quantity, h.price_each_cents, h.created_at,
            c.name AS customer_name,
            p.name AS plant_name, p.type AS plant_type, p.location AS plant_location
      FROM holds h
      JOIN customers c ON c.id = h.customer_id
      JOIN plants p    ON p.id = h.plant_id
      WHERE h.status = 'HOLD'
      ORDER BY h.created_at DESC
    ''');
  }
  /// Sales summary between dates (inclusive), grouped by plant.
  static Future<List<Map<String, dynamic>>> salesSummaryByPlant({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await getDB();
    final fromIso = from.toIso8601String();
    final toIso = to.add(const Duration(days: 1)).toIso8601String(); // inclusive
    return db.rawQuery('''
      SELECT p.name, p.type, p.location,
            SUM(h.quantity) AS qty_sold,
            SUM(h.quantity * h.price_each_cents)/100.0 AS revenue
      FROM holds h
      JOIN plants p ON p.id = h.plant_id
      WHERE h.status='SOLD'
        AND h.closed_at >= ? AND h.closed_at < ?
      GROUP BY p.name, p.type, p.location
      ORDER BY revenue DESC
    ''', [fromIso, toIso]);
  }

  /// Sales summary by customer in date range
  static Future<List<Map<String, dynamic>>> salesSummaryByCustomer({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await getDB();
    final fromIso = from.toIso8601String();
    final toIso = to.add(const Duration(days: 1)).toIso8601String();
    return db.rawQuery('''
      SELECT c.name AS customer,
            SUM(h.quantity) AS qty_sold,
            SUM(h.quantity * h.price_each_cents)/100.0 AS revenue
      FROM holds h
      JOIN customers c ON c.id = h.customer_id
      WHERE h.status='SOLD'
        AND h.closed_at >= ? AND h.closed_at < ?
      GROUP BY c.name
      ORDER BY revenue DESC, customer COLLATE NOCASE
    ''', [fromIso, toIso]);
  }
  static Future<Plant?> findByNameTypeLocation(String name, String type, String location) async {
    final db = await getDB();
    final rows = await db.query(
      'plants',
      where: 'LOWER(name)=LOWER(?) AND LOWER(type)=LOWER(?) AND LOWER(location)=LOWER(?)',
      whereArgs: [name.trim(), type.trim(), (location.isEmpty ? 'Default' : location).trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Plant.fromMap(rows.first);
  }
  static Future<int> insertPlant({
    required String name,
    required String type,
    required String location,
    required int quantity,
    String notes = '',
    String? imagePath,
  }) async {
    final db = await getDB();
    return await db.insert('plants', {
      'name': name,
      'type': type,
      'location': location.isEmpty ? 'Default' : location,
      'quantity': quantity,
      'notes': notes,
      'imagePath': imagePath, // store hosted URL here if provided
    });
  }
}