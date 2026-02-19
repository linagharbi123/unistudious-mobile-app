import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../widgets/sidebar.dart';
import '../widgets/notification_icon_button.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  /// Active / désactive les logs de debug pour le QR code.
  /// Passe à `false` quand tu n'en as plus besoin.
  static const bool _qrDebug = true;

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  String? _lastScannedCode;

  @override
  void dispose() {
    if (_qrDebug) {
      developer.log('📷 QRScannerPage dispose() – arrêt du contrôleur',
          name: 'QRScanner');
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture barcodeCapture) async {
    if (_isProcessing) {
      if (_qrDebug) {
        developer.log(
          'Détection ignorée car un QR est déjà en cours de traitement',
          name: 'QRScanner',
        );
      }
      return;
    }

    final List<Barcode> barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) {
      if (_qrDebug) {
        developer.log(
          'Aucun barcode détecté dans BarcodeCapture',
          name: 'QRScanner',
        );
      }
      return;
    }

    final String? code = barcodes.first.rawValue;
    if (code == null) {
      if (_qrDebug) {
        developer.log(
          'Barcode détecté mais rawValue est null',
          name: 'QRScanner',
        );
      }
      return;
    }

    if (code == _lastScannedCode) {
      if (_qrDebug) {
        developer.log(
          'Même code que le dernier scanné, on ignore pour éviter les doublons: $code',
          name: 'QRScanner',
        );
      }
      return;
    }

    if (_qrDebug) {
      developer.log(
        'QR détecté: $code',
        name: 'QRScanner',
      );
    }

    setState(() {
      _isProcessing = true;
      _lastScannedCode = code;
    });

    // Arrêter temporairement le scanner
    if (_qrDebug) {
      developer.log(
        'Arrêt temporaire du scanner pour traitement du QR',
        name: 'QRScanner',
      );
    }
    await _controller.stop();

    // Traiter le QR (essayer d'abord l'API d'attendance, sinon afficher juste le contenu)
    await _processScannedCode(code);
  }

  Future<void> _processScannedCode(String code) async {
    if (_qrDebug) {
      developer.log(
        'Début du traitement du code scanné',
        name: 'QRScanner',
      );
    }

    final parsed = _parseSlcAndCalendarFromCode(code);

    if (parsed == null) {
      if (_qrDebug) {
        developer.log(
          'Impossible d\'extraire slc_id / calander_id du code: $code',
          name: 'QRScanner',
        );
      }
      // Si on ne trouve pas slc_id / calander_id, on affiche juste un message d'erreur
      // sans montrer la carte de contenu du QR.
      _showPopupDialog(
        title: 'QR Code invalide',
        message: 'QR code invalide ou non pris en charge',
        icon: Icons.error_outline,
        iconColor: Colors.red.shade600,
      );
      return;
    }

    await _scanQrAttendance(
      slcId: parsed['slc_id']!,
      calendarId: parsed['calander_id']!,
      rawCode: code,
    );
  }

  Map<String, String>? _parseSlcAndCalendarFromCode(String code) {
    if (_qrDebug) {
      developer.log(
        'Tentative de parsing du code QR',
        name: 'QRScanner',
      );
    }

    // 1) Essayer comme URL avec IDs dans le chemin (format: https://www.unistudious.com/{slc_id}/{calendar_id})
    // Supporte aussi: https://www.unistudious.com/.../{slc_id}/{calendar_id} (avec segments supplémentaires)
    try {
      final uri = Uri.parse(code);
      // Vérifier si c'est un domaine unistudious.com
      if (uri.host.contains('unistudious.com')) {
        final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        // Chercher un pattern comme /{slc_id}/{calendar_id} (les deux derniers segments numériques)
        if (pathSegments.length >= 2) {
          final slcId = pathSegments[pathSegments.length - 2];
          final calendarId = pathSegments[pathSegments.length - 1];
          // Vérifier que ce sont des nombres valides (peut être n'importe quel nombre)
          if (slcId.isNotEmpty && calendarId.isNotEmpty &&
              int.tryParse(slcId) != null && int.tryParse(calendarId) != null) {
            if (_qrDebug) {
              developer.log(
                'QR parsé comme URL avec chemin: slc_id=$slcId, calander_id=$calendarId',
                name: 'QRScanner',
              );
            }
            return {
              'slc_id': slcId,
              'calander_id': calendarId,
            };
          }
        }
      }
    } catch (e) {
      if (_qrDebug) {
        developer.log(
          'Erreur lors du parsing URL avec chemin: $e',
          name: 'QRScanner',
        );
      }
      // Ignorer et essayer d'autres formats
    }

    // 2) Essayer comme URL avec paramètres de requête
    try {
      final uri = Uri.parse(code);
      final slcId = uri.queryParameters['slc_id'];
      final calendarId = uri.queryParameters['calander_id'];
      if (slcId != null && calendarId != null) {
        if (_qrDebug) {
          developer.log(
            'QR parsé comme URL avec paramètres: slc_id=$slcId, calander_id=$calendarId',
            name: 'QRScanner',
          );
        }
        return {
          'slc_id': slcId,
          'calander_id': calendarId,
        };
      }
    } catch (_) {
      // Ignorer et essayer d'autres formats
    }

    // 3) Essayer comme JSON
    try {
      final decoded = json.decode(code);
      if (decoded is Map<String, dynamic>) {
        final slcId = decoded['slc_id']?.toString();
        final calendarId = decoded['calander_id']?.toString();
        if (slcId != null && calendarId != null) {
          if (_qrDebug) {
            developer.log(
              'QR parsé comme JSON: slc_id=$slcId, calander_id=$calendarId',
              name: 'QRScanner',
            );
          }
          return {
            'slc_id': slcId,
            'calander_id': calendarId,
          };
        }
      }
    } catch (_) {
      // Pas du JSON valide
    }

    return null;
  }

  Future<void> _scanQrAttendance({
    required String slcId,
    required String calendarId,
    required String rawCode,
  }) async {
    if (_qrDebug) {
      developer.log(
        'Appel _scanQrAttendance avec slc_id=$slcId, calander_id=$calendarId',
        name: 'QRScanner',
      );
    }

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.currentToken;

      if (token == null) {
        _showPopupDialog(
          title: 'Erreur d\'authentification',
          message: 'Erreur d\'authentification. Veuillez vous reconnecter',
          icon: Icons.error_outline,
          iconColor: Colors.red.shade600,
        );
        return;
      }

      if (_qrDebug) {
        developer.log(
          'Token présent, préparation de la requête HTTP pour l\'attendance',
          name: 'QRScanner',
        );
      }

      // On envoie les données en body "form-data" (multipart/form-data)
      final uri = Uri.parse(
        'https://www.unistudious.com/api/scan-qr-attendance-slc',
      );

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        // Ces champs sont envoyés en form-data (multipart/form-data)
        ..fields['slc_id'] = slcId
        ..fields['calander_id'] = calendarId;

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

       if (_qrDebug) {
        developer.log(
          'Réponse HTTP reçue pour scan-qr-attendance-slc: '
          'statusCode=${response.statusCode}, body=${response.body}',
          name: 'QRScanner',
        );
      }

      Map<String, dynamic>? responseData;
      try {
        if (response.body.isNotEmpty) {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic>) {
            responseData = decoded;
          }
        }
      } catch (_) {
        // Réponse non JSON, on gérera juste avec le status code
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Quel que soit le cas (auto_join_group ou autre), message fixe
        if (_qrDebug) {
          developer.log(
            'Attendance marquée avec succès pour le QR (status ${response.statusCode})',
            name: 'QRScanner',
          );
        }
        _showPopupDialog(
          title: 'Succès',
          message: 'Étudiant marqué comme présent',
          icon: Icons.check_circle,
          iconColor: Colors.green.shade600,
          isSuccess: true,
        );
      } else {
        String errorMessage = 'Erreur lors du traitement du QR d\'attendance';

        // On ne renvoie au client QUE des messages en français.
        // Les messages bruts de l’API (souvent en anglais) restent
        // uniquement dans les logs de debug.
        final apiMessage = responseData?['message']?.toString();
        if (response.statusCode == 400) {
          // Message fixe demandé par le client en cas de 400
          errorMessage = 'Cet étudiant ne peut pas marquer la présence';
        } else if (response.statusCode == 404) {
          errorMessage = 'Ressource introuvable pour ce QR';
        } else if (response.statusCode == 500) {
          errorMessage = 'Erreur serveur. Veuillez réessayer plus tard';
        } else {
          errorMessage =
              'Erreur ${response.statusCode} lors du traitement du QR';
        }

        if (_qrDebug) {
          developer.log(
            'Erreur côté API lors du traitement du QR: '
            'status=${response.statusCode}, message="$errorMessage"',
            name: 'QRScanner',
          );
        }

        _showPopupDialog(
          title: 'Erreur',
          message: errorMessage,
          icon: Icons.error_outline,
          iconColor: Colors.red.shade600,
        );
      }
    } catch (e) {
      if (_qrDebug) {
        developer.log(
          'Exception attrapée dans _scanQrAttendance: $e',
          name: 'QRScanner',
          error: e,
        );
      }

      String errorMessage =
          'Une erreur est survenue lors du traitement du QR d\'attendance';
      final errorText = e.toString().toLowerCase();

      if (errorText.contains('network') || errorText.contains('connection')) {
        errorMessage = 'Erreur de connexion. Vérifiez votre connexion internet';
      } else if (errorText.contains('timeout')) {
        errorMessage = 'La requête a expiré. Veuillez réessayer';
      } else {
        errorMessage =
            'Erreur lors du traitement du QR d\'attendance: ${e.toString()}';
      }

      _showPopupDialog(
        title: 'Erreur',
        message: errorMessage,
        icon: Icons.error_outline,
        iconColor: Colors.red.shade600,
      );
    }
  }

  void _showPopupDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    bool isSuccess = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.grey[700],
            fontSize: 16,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resumeScanning();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuccess 
                  ? Colors.green.shade600 
                  : (isDark ? const Color(0xFF1A003D) : theme.primaryColor),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resumeScanning() {
    setState(() {
      _isProcessing = false;
      _lastScannedCode = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scanner QR Code',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                  : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: const [
          NotificationIconButton(),
        ],
      ),
      drawer: const AppSidebar(),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: Stack(
          children: [
            // Scanner view
            MobileScanner(
              controller: _controller,
              onDetect: _handleBarcode,
            ),
            // Overlay avec instructions
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Positionnez le QR code dans le cadre',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Cadre de scan au centre
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.primaryColor,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    // Coins décoratifs
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.primaryColor, width: 4),
                            left: BorderSide(color: theme.primaryColor, width: 4),
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.primaryColor, width: 4),
                            right: BorderSide(color: theme.primaryColor, width: 4),
                          ),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: theme.primaryColor, width: 4),
                            left: BorderSide(color: theme.primaryColor, width: 4),
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: theme.primaryColor, width: 4),
                            right: BorderSide(color: theme.primaryColor, width: 4),
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Instructions en bas
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Le QR code sera automatiquement détecté',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        shadows: [
                          Shadow(
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

