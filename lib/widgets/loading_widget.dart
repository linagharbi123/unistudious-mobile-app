import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

// Cache statique pour éviter de recharger l'animation Lottie
class LottieCache {
  static bool _hasLoaded = false;
  static bool _hasLogged = false;

  static void reset() {
    _hasLoaded = false;
    _hasLogged = false;
  }
}

class LoadingWidget extends StatefulWidget {
  final double? width;
  final double? height;

  const LoadingWidget({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget>
    with TickerProviderStateMixin {
  bool _hasError = false;
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animation Lottie Books stack.json
          SizedBox(
            width: widget.width ?? 200,
            height: widget.height ?? 200,
            child: Lottie.asset(
              'assets/Books stack.json',
              fit: BoxFit.contain,
              repeat: true,
              animate: true,
              onLoaded: (composition) {
                // Utiliser le cache statique pour éviter les logs multiples
                if (!LottieCache._hasLogged) {
                  print('Animation Lottie chargée avec succès - Durée: ${composition.duration}');
                  LottieCache._hasLogged = true;
                }
                LottieCache._hasLoaded = true;
              },
              errorBuilder: (context, error, stackTrace) {
                // Utiliser le cache statique pour éviter les logs multiples
                if (!LottieCache._hasLogged) {
                  print('Erreur Lottie: $error');
                  print('Stack trace: $stackTrace');
                  LottieCache._hasLogged = true;
                }
                // Ne pas appeler setState ici; retourner simplement le fallback
                return _buildOpeningBook();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningBook() {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width ?? 200,
          height: widget.height ?? 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Livre qui s'ouvre et se ferme
              Transform.scale(
                scale: _scaleAnimation.value,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Couverture arrière (fixe)
                    _buildBookCover(
                      color: Colors.orange.shade700,
                      isBack: true,
                    ),
                    // Pages qui s'ouvrent
                    Transform.rotate(
                      angle: _animation.value * 0.8, // Angle d'ouverture
                      alignment: Alignment.centerLeft,
                      child: _buildBookPages(),
                    ),
                    // Couverture avant qui s'ouvre
                    Transform.rotate(
                      angle: _animation.value * 0.6, // Angle d'ouverture
                      alignment: Alignment.centerLeft,
                      child: _buildBookCover(
                        color: Colors.purple.shade600,
                        isBack: false,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              // Barre de progression moderne
              Container(
                width: 100,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    value: _animation.value,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookCover({required Color color, required bool isBack}) {
    return Container(
      width: 80,
      height: 100,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Titre du livre
          Positioned(
            top: 15,
            left: 0,
            right: 0,
            child: Text(
              'BOOK',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Lignes décoratives
          ...List.generate(3, (index) {
            return Positioned(
              top: 35 + (index * 15),
              left: 10,
              right: 10,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBookPages() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final animationValue = _animation.value;
        final opacity = 0.8 + (animationValue * 0.2);

        return Container(
          width: 76,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: Offset(1, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Lignes de texte simulées
              ...List.generate(8, (index) {
                return Positioned(
                  top: 10 + (index * 10),
                  left: 8,
                  right: 8,
                  child: Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                );
              }),
              // Numéro de page
              Positioned(
                bottom: 8,
                right: 8,
                child: Text(
                  '1',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

