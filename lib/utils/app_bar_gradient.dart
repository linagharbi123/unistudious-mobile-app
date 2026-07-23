import 'package:flutter/material.dart';

/// Couleurs de dégradé AppBar alignées sur le tableau de bord.
class AppBarGradient {
  static const List<Color> darkColors = [
    Color(0xFF1A003D),
    Color(0xFF3C0D73),
  ];

  static const List<Color> lightColors = [
    Color(0xFF8E2DE2),
    Color(0xFF4A00E0),
  ];

  static List<Color> colors(bool isDark) =>
      isDark ? darkColors : lightColors;

  static List<Color> colorsForBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? darkColors : lightColors;

  static BoxDecoration decoration(bool isDark) => BoxDecoration(
        gradient: LinearGradient(
          colors: colors(isDark),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );

  static Widget flexibleSpace(bool isDark) =>
      Container(decoration: decoration(isDark));
}
