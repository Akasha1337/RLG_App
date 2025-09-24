class Plant {
  final int? id;
  final String name;
  final String type;        // e.g., Tree / Shrub / Perennial
  final int quantity;
  final String notes;
  final String? imagePath;
  final String location;    // NEW

  Plant({
    this.id,
    required this.name,
    required this.type,
    required this.quantity,
    required this.notes,
    this.imagePath,
    required this.location,  // NEW
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'quantity': quantity,
        'notes': notes,
        'imagePath': imagePath,
        'location': location,
      };

  factory Plant.fromMap(Map<String, dynamic> m) => Plant(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        type: (m['type'] as String?) ?? (m['category'] as String? ?? ''),
        quantity: (m['quantity'] ?? 0) as int,
        notes: (m['notes'] as String?) ?? '',
        imagePath: m['imagePath'] as String?,
        location: (m['location'] as String?) ?? '', // NEW
      );
}
