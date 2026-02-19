import 'package:flutter/foundation.dart';

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

  /// Retourne la mise à jour à afficher en priorisant :
  /// 1. Les mises à jour obligatoires (required: true)
  /// 2. La version la plus récente parmi les mises à jour obligatoires
  /// 3. Sinon, la première mise à jour optionnelle
  VersionUpdate? get firstUpdate {
    if (updates.isEmpty) return null;
    
    // Séparer les mises à jour obligatoires et optionnelles
    final requiredUpdates = updates.where((u) => u.required).toList();
    final optionalUpdates = updates.where((u) => !u.required).toList();
    
    // Debug: Afficher les mises à jour séparées
    if (kDebugMode) {
      print('🔍 Analyse des mises à jour:');
      print('  📌 Mises à jour obligatoires: ${requiredUpdates.length}');
      for (var u in requiredUpdates) {
        print('    - Version ${u.version}, Required=${u.required}');
      }
      print('  📌 Mises à jour optionnelles: ${optionalUpdates.length}');
      for (var u in optionalUpdates) {
        print('    - Version ${u.version}, Required=${u.required}');
      }
    }
    
    // Si des mises à jour obligatoires existent, prendre la plus récente
    if (requiredUpdates.isNotEmpty) {
      // Trier par version (numérique si possible, sinon alphabétique)
      requiredUpdates.sort((a, b) {
        try {
          final aVersion = int.tryParse(a.version) ?? 0;
          final bVersion = int.tryParse(b.version) ?? 0;
          final comparison = bVersion.compareTo(aVersion); // Plus récente en premier
          if (kDebugMode) {
            print('  🔄 Tri: Version ${a.version} (${aVersion}) vs ${b.version} (${bVersion}) = $comparison');
          }
          return comparison;
        } catch (e) {
          final comparison = b.version.compareTo(a.version); // Tri alphabétique inverse
          if (kDebugMode) {
            print('  🔄 Tri alphabétique: Version ${a.version} vs ${b.version} = $comparison');
          }
          return comparison;
        }
      });
      final selected = requiredUpdates.first;
      if (kDebugMode) {
        print('  ✅ Mise à jour obligatoire sélectionnée: Version ${selected.version}');
      }
      return selected;
    }
    
    // Sinon, retourner la première mise à jour optionnelle
    if (optionalUpdates.isNotEmpty) {
      final selected = optionalUpdates.first;
      if (kDebugMode) {
        print('  ✅ Mise à jour optionnelle sélectionnée: Version ${selected.version}');
      }
      return selected;
    }
    
    return null;
  }

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



