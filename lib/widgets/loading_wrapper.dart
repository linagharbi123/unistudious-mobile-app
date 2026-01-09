import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/loading_provider.dart';
import 'loading_widget.dart';

class LoadingWrapper extends StatelessWidget {
  final Widget child;

  const LoadingWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<LoadingProvider>(
      builder: (context, loadingProvider, child) {
        return Stack(
          children: [
            child!,
            if (loadingProvider.isLoading)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black.withOpacity(0.5),
                child: const LoadingWidget(),
              ),
          ],
        );
      },
      child: child,
    );
  }
}