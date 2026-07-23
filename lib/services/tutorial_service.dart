import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialKeys {
  TutorialKeys._();

  static final joinSession = GlobalKey();
}

class TutorialStepData {
  final String id;
  final String title;
  final String description;
  final GlobalKey targetKey;
  final int? tabIndexBeforeShow;
  final bool scrollIntoView;

  const TutorialStepData({
    required this.id,
    required this.title,
    required this.description,
    required this.targetKey,
    this.tabIndexBeforeShow,
    this.scrollIntoView = false,
  });
}

class TutorialService {
  static const _completedKey = 'app_tutorial_completed_v1';
  static const _pendingKey = 'app_tutorial_pending';

  static Future<bool> shouldShowAutomatically() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_completedKey) ?? false);
  }

  static Future<bool> consumePendingReplay() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_pendingKey) ?? false;
    if (pending) {
      await prefs.setBool(_pendingKey, false);
    }
    return pending;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    await prefs.setBool(_pendingKey, false);
  }

  static Future<void> requestReplay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingKey, true);
    await prefs.setBool(_completedKey, false);
  }

  static Future<void> reset() => requestReplay();
}
