import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';

class PlaceholderWidget extends StatelessWidget {
  final String title;

  PlaceholderWidget(this.title);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.purple[900],
          foregroundColor: Colors.white,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
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
      ),
    );
  }
}