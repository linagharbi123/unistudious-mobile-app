class NotificationModel {
  final String id;
  final String name; // Titre de la notification
  final String message; // Corps de la notification
  final DateTime createdAt;
  final String type; // Type de notification (Payment, New validation session, poll, etc.)
  final String idType; // ID lié (session ID, group ID, etc.)
  final bool? social; // Si c'est une notification sociale
  final bool isRead; // Statut lu/non lu (géré localement)

  NotificationModel({
    required this.id,
    required this.name,
    required this.message,
    required this.createdAt,
    required this.type,
    required this.idType,
    this.social,
    this.isRead = false,
  });

  // Getters pour compatibilité avec l'ancien code
  String get title => name;
  String get body => message;
  DateTime get receivedAt => createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
      'type': type,
      'idType': idType,
      'social': social,
      'isRead': isRead,
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    // Parser la date depuis le format "2026-01-07 13:04:04"
    DateTime parseDate(String dateString) {
      try {
        // Format: "2026-01-07 13:04:04"
        final parts = dateString.split(' ');
        final dateParts = parts[0].split('-');
        final timeParts = parts[1].split(':');
        return DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(timeParts[2]),
        );
      } catch (e) {
        return DateTime.now();
      }
    }

    return NotificationModel(
      id: json['id'].toString(), // Convertir en String
      name: json['name'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? parseDate(json['createdAt'] as String)
          : DateTime.now(),
      type: json['type'] as String? ?? '',
      idType: json['idType']?.toString() ?? '',
      social: json['social'] as bool?,
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  NotificationModel copyWith({
    String? id,
    String? name,
    String? message,
    DateTime? createdAt,
    String? type,
    String? idType,
    bool? social,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      idType: idType ?? this.idType,
      social: social ?? this.social,
      isRead: isRead ?? this.isRead,
    );
  }
}

