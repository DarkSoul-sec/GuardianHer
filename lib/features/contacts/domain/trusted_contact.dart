import 'dart:math';

/// Generates cryptographically random, unique contact identifiers.
///
/// IDs are opaque, high-entropy 128-bit values expressed as hex strings, so
/// they are not enumerable or guessable.
abstract final class ContactId {
  ContactId._();

  static final Random _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// An immutable trusted emergency contact.
///
/// [phoneNumber] is always stored in its canonical normalized form (digits
/// only) and [priority] is a 1-based contiguous rank within the contact
/// collection. Timestamps are UTC instants.
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a new contact with a freshly generated [id] and creation/update
  /// timestamps. [createdAt]/[updatedAt] may be supplied for testability.
  factory TrustedContact.create({
    required String name,
    required String phoneNumber,
    required int priority,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toUtc();
    return TrustedContact(
      id: ContactId.generate(),
      name: name,
      phoneNumber: phoneNumber,
      priority: priority,
      createdAt: created,
      updatedAt: updatedAt?.toUtc() ?? created,
    );
  }

  final String id;
  final String name;
  final String phoneNumber;
  final int priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  TrustedContact copyWith({
    String? name,
    String? phoneNumber,
    int? priority,
    DateTime? updatedAt,
  }) {
    return TrustedContact(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TrustedContact &&
        other.id == id &&
        other.name == name &&
        other.phoneNumber == phoneNumber &&
        other.priority == priority &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, phoneNumber, priority);
}
