import 'package:flutter/material.dart';
import '../utils/app_bar_gradient.dart';
import '../widgets/sidebar.dart';

class PlaceholderWidget extends StatelessWidget {
  final String title;

  PlaceholderWidget(this.title);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: AppBarGradient.flexibleSpace(isDark),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      drawer: AppSidebar(),
      body: Container(
        color: Colors.white,
        child: Center(
          child: Text(
            'Page "$title" à implémenter',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}
