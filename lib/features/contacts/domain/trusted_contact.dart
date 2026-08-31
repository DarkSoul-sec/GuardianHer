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
/// collection. [email] is optional (normalized to null when blank) and is
/// used only as a fallback delivery channel when no SMS app can handle a
/// message (Phase 3G). [isEmergencyContact] determines if this contact
/// receives SOS alerts. Timestamps are UTC instants.
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.isEmergencyContact = true,
  });

  /// Creates a new contact with a freshly generated [id] and creation/update
  /// timestamps. [createdAt]/[updatedAt] may be supplied for testability.
  factory TrustedContact.create({
    required String name,
    required String phoneNumber,
    required int priority,
    String? email,
    bool isEmergencyContact = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toUtc();
    return TrustedContact(
      id: ContactId.generate(),
      name: name,
      phoneNumber: phoneNumber,
      priority: priority,
      email: TrustedContact.normalizeEmail(email),
      isEmergencyContact: isEmergencyContact,
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
  final String? email;
  final bool isEmergencyContact;

  /// Canonicalizes an email input: trimmed, lower-cased, blank → null.
  static String? normalizeEmail(String? value) {
    if (value == null) return null;
    final trimmed = value.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  TrustedContact copyWith({
    String? name,
    String? phoneNumber,
    String? Function()? email,
    int? priority,
    bool? isEmergencyContact,
    DateTime? updatedAt,
  }) {
    return TrustedContact(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email != null ? email() : this.email,
      priority: priority ?? this.priority,
      isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
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
        other.email == email &&
        other.priority == priority &&
        other.isEmergencyContact == isEmergencyContact &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, phoneNumber, email, priority, isEmergencyContact);
}