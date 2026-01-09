class VersionUpdate {
  final String version;
  final bool required;
  final String message;
  final String status;

  const VersionUpdate({
    required this.version,
    required this.required,
    required this.message,
    required this.status,
  });

  factory VersionUpdate.fromJson(Map<String, dynamic> json) {
    return VersionUpdate(
      version: json['version']?.toString() ?? '',
      required: json['required'] == true || json['required'] == 1 || json['is_required'] == true,
      message: json['message']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

class VersionCheckResponse {
  final String status;
  final List<VersionUpdate> updates;

  const VersionCheckResponse({
    required this.status,
    required this.updates,
  });

  bool get hasUpdate => updates.isNotEmpty;

  VersionUpdate? get firstUpdate => updates.isNotEmpty ? updates.first : null;

  factory VersionCheckResponse.fromJson(Map<String, dynamic> json) {
    // On accepte plusieurs structures possibles selon l'API
    final status = json['status']?.toString() ?? '';

    // Chercher un tableau d'updates dans différentes clés possibles
    List<dynamic> rawUpdates = [];
    if (json['updates'] is List) {
      rawUpdates = json['updates'] as List;
    } else if (json['data'] is List) {
      rawUpdates = json['data'] as List;
    } else if (json['result'] is List) {
      rawUpdates = json['result'] as List;
    } else if (json['update'] is Map) {
      rawUpdates = [json['update']];
    }

    final updates = rawUpdates
        .whereType<Map<String, dynamic>>()
        .map((u) => VersionUpdate.fromJson(u))
        .toList();

    return VersionCheckResponse(
      status: status,
      updates: updates,
    );
  }
}



