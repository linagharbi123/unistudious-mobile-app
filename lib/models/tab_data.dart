import 'package:flutter/material.dart';

class TabData {
  const TabData(
    this.title,
    this.icon, {
    this.showIconBadge = false,
  });

  final String title;
  final IconData icon;
  final bool showIconBadge;
}
