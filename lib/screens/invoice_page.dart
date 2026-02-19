import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../widgets/sidebar.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key});

  @override
  _InvoicePageState createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  List<Map<String, dynamic>> invoices = [];
  List<Map<String, dynamic>> invoiceDetails = [];
  bool isLoading = true;
  bool isDetailLoading = false;
  bool isDetailView = false;
  String? errorMessage;
  final ScrollController _scrollController = ScrollController();
  double _scrollPosition = 0.0;

  @override
  void initState() {
    super.initState();
    _checkAuthAndFetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      setState(() {
        errorMessage = 'Veuillez vous connecter pour continuer.';
        isLoading = false;
      });
      return;
    }

    developer.log('Token disponible : ${authProvider.currentToken}', name: 'InvoicePage');
    fetchInvoices();
  }

  Future<void> fetchInvoices() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      isLoading = true;
      errorMessage = null; // Reset error message on refresh
    });

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-order',
      );

      developer.log('Réponse API (get-order): ${response.statusCode} - ${response.body}', name: 'InvoicePage');

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        if (decodedData['paymentData'] is List<dynamic>) {
          setState(() {
            invoices = (decodedData['paymentData'] as List)
                .where((item) => item != null)
                .map((item) => {
              'id': item['id']?.toString() ?? 'N/A',
              'type': item['type'] ?? 'N/A',
              'typeDate': item['typeDate'] ?? 'N/A',
              'datePayment': item['datePayment'] ?? 'N/A',
              'status': item['status'] ?? 'N/A',
              'amount': item['amount']?.toString() ?? 'N/A',
              'price': item['price']?.toString() ?? 'N/A',
              'sessionId': item['sessionId']?.toString() ?? 'N/A',
              'sessionName': item['sessionName'] ?? 'N/A',
              'accountId': item['accountId']?.toString() ?? 'N/A',
              'accountName': item['accountName'] ?? 'N/A',
            })
                .toList();
            isLoading = false;
            isDetailView = false; // Ensure detail view is reset on refresh
            invoiceDetails = []; // Clear details on refresh
          });
        } else {
          throw Exception('Format de réponse inattendu');
        }
      } else {
        setState(() {
          errorMessage = 'Échec du chargement : ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      developer.log('Erreur de chargement : $e', name: 'InvoicePage');
      setState(() {
        errorMessage = 'Erreur : $e';
        isLoading = false;
      });
    }
  }

  Future<void> fetchInvoiceDetails(String id) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (_scrollController.hasClients) {
      _scrollPosition = _scrollController.offset;
    }

    setState(() {
      // Passer immédiatement en vue détails pour avoir l'icône de retour
      isDetailView = true;
      isDetailLoading = true;
      errorMessage = null;
    });

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/get-invoice/$id',
        body: jsonEncode({'id': id}),
      );

      developer.log('Réponse API (get-invoice): ${response.statusCode} - ${response.body}', name: 'InvoicePage');

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        if (decodedData['invoiceData'] is List<dynamic> && (decodedData['invoiceData'] as List).isNotEmpty) {
          setState(() {
            invoiceDetails = (decodedData['invoiceData'] as List)
                .where((item) => item != null)
                .map((item) => {
              'paymentId': item['paymentId']?.toString() ?? 'N/A',
              'id': item['id']?.toString() ?? 'N/A',
              'path': item['path'] ?? 'N/A',
              'name': item['name'] ?? 'N/A',
              'type': item['type'] ?? 'N/A',
              'description': item['description'] ?? 'N/A',
              'status': item['status'] ?? false,
              'total_amount': item['total_amount']?.toString() ?? 'N/A',
              'sessionId': item['sessionId']?.toString() ?? 'N/A',
              'sessionName': item['sessionName'] ?? 'N/A',
              'accountId': item['accountId']?.toString() ?? 'N/A',
              'accountName': item['accountName'] ?? 'N/A',
            })
                .toList();
            isDetailView = true;
            isDetailLoading = false;
          });
        } else {
          // Cas normal : pas de détails disponibles, pas d'erreur à afficher
          setState(() {
            invoiceDetails = [];
            isDetailLoading = false;
            errorMessage = null; // Pas d'erreur, juste une page vide
            // Garder isDetailView = true pour rester sur la page de détails
            isDetailView = true;
          });
        }
      } else {
        // Erreur HTTP : ne pas afficher d'erreur dans la vue détails, juste une page vide
        setState(() {
          invoiceDetails = [];
          isDetailLoading = false;
          errorMessage = null; // Ne pas afficher d'erreur dans la vue détails
          // Garder isDetailView = true pour rester sur la page de détails
          isDetailView = true;
        });
      }
    } catch (e) {
      developer.log('Erreur de chargement des détails : $e', name: 'InvoicePage');
      // Ne pas afficher d'erreur dans la vue détails, juste une page vide
      setState(() {
        invoiceDetails = [];
        isDetailLoading = false;
        errorMessage = null; // Ne pas afficher d'erreur dans la vue détails
        // Garder isDetailView = true pour rester sur la page de détails
        isDetailView = true;
      });
    }
  }

  Future<void> downloadInvoice(String filename) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      setState(() {
        errorMessage = 'Token non disponible';
      });
      return;
    }

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/download-invoice/$filename',
        headers: {'Accept': 'application/pdf'},
      );

      developer.log('Réponse API (download-invoice): ${response.statusCode}', name: 'InvoicePage');

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$filename';
        final file = File(filePath);

        await file.writeAsBytes(response.bodyBytes);

        developer.log('Fichier sauvegardé : $filePath', name: 'InvoicePage');

        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          setState(() {
            errorMessage = 'Erreur lors de l\'ouverture du fichier : ${result.message}';
          });
          return;
        }

        setState(() {
          errorMessage = null;
        });
      } else {
        setState(() {
          errorMessage = 'Échec du téléchargement : ${response.statusCode}';
        });
      }
    } catch (e) {
      developer.log('Erreur de téléchargement : $e', name: 'InvoicePage');
      setState(() {
        errorMessage = 'Erreur de téléchargement : $e';
      });
    }
  }

  String getStatusLabel(Map<String, dynamic> invoice) {
    final status = invoice['status']?.toLowerCase();
    switch (status) {
      case 'pending':
        return 'En attente';
      case 'paid':
        return 'Payé';
      case 'unpaid':
        return 'Non payé';
      case 'not registered':
        return 'Non enregistré';
      case 'cancelled':
        return 'Annulé';
      default:
        return 'Inconnu';
    }
  }

  Color getStatusColor(Map<String, dynamic> invoice) {
    final status = invoice['status']?.toLowerCase();
    switch (status) {
      case 'paid':
        return Colors.green[700]!;
      case 'pending':
        return Colors.amber[700]!;
      case 'unpaid':
      case 'not registered':
        return Colors.redAccent;
      case 'cancelled':
        return Colors.grey;
      default:
        return invoice['status'] == true ? Colors.green[700]! : Colors.redAccent;
    }
  }

  IconData getStatusIcon(Map<String, dynamic> invoice) {
    final status = invoice['status']?.toLowerCase();
    switch (status) {
      case 'paid':
        return Icons.check_circle;
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'unpaid':
      case 'not registered':
        return Icons.cancel_rounded;
      case 'cancelled':
        return Icons.block;
      default:
        return invoice['status'] == true ? Icons.check_circle : Icons.cancel_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: Icon(isDetailView ? Icons.arrow_back_ios_new : Icons.menu, color: Colors.white),
              onPressed: () {
                if (isDetailView) {
                  setState(() {
                    isDetailView = false;
                    invoiceDetails = [];
                    errorMessage = null;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(_scrollPosition);
                    }
                  });
                } else {
                  Scaffold.of(context).openDrawer();
                }
              },
            );
          },
        ),
        title: Text(
          isDetailView ? 'Détails des factures' : 'Factures',
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontFamily: GoogleFonts.poppins().fontFamily,
          ) ??
              TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
        ),
        centerTitle: false, // Aligne le titre à gauche
        backgroundColor: Colors.transparent,
        elevation: 0,
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
      ),
      // En vue détails, on n'affiche pas la sidebar pour garder uniquement le bouton retour
      drawer: isDetailView ? null : const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: fetchInvoices,
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
            : isDetailView
            ? isDetailLoading
            ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
            : invoiceDetails.isNotEmpty
            ? ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invoiceDetails.length,
          itemBuilder: (context, index) {
            final detail = invoiceDetails[index];
            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: theme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt, color: theme.iconTheme.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ID : ${detail['id']}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.category, color: theme.iconTheme.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Type : ${detail['type']}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.description, color: theme.iconTheme.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Nom : ${detail['name']}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.info, color: theme.iconTheme.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Description : ${detail['description']}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.attach_money, color: Colors.teal[700]),
                        const SizedBox(width: 6),
                        Text(
                          'Montant : ${detail['total_amount']} TND',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.teal[700],
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: Colors.teal[700],
                                fontWeight: FontWeight.bold,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: detail['path'] != 'N/A'
                            ? () => downloadInvoice(detail['path'])
                            : null,
                        icon: const Icon(Icons.remove_red_eye_sharp),
                        label: Text(
                          "ouvrir la facture",
                          style: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF472072) : theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        )
            : Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Cette page est vide',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[700],
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ) ??
                      TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        )
            : errorMessage != null
            ? Center(
          child: Text(
            errorMessage!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.red[700],
              fontFamily: GoogleFonts.poppins().fontFamily,
            ) ??
                TextStyle(
                  color: Colors.red[700],
                  fontSize: 16,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
          ),
        )
            : ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          itemBuilder: (context, index) {
            final invoice = invoices[index];
            final statusLabel = getStatusLabel(invoice);
            final statusColor = getStatusColor(invoice);
            final statusIcon = getStatusIcon(invoice);

            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: theme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long, color: theme.iconTheme.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Commande : ${invoice['id']}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 18, color: theme.iconTheme.color),
                        const SizedBox(width: 6),
                        Text(
                          'Date : ${invoice['typeDate']}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.description, size: 18, color: theme.iconTheme.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Description : ${invoice['sessionName']}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          'Statut : ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                        Text(
                          statusLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.attach_money, size: 20, color: Colors.teal[700]),
                        const SizedBox(width: 6),
                        Text(
                          'Montant : ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                        Text(
                          invoice['price'] != '0' && invoice['price'] != 'N/A'
                              ? '${invoice['price']} TND'
                              : 'N/A',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.teal[700],
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: Colors.teal[700],
                                fontWeight: FontWeight.bold,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.payment_rounded, size: 20, color: theme.iconTheme.color),
                        const SizedBox(width: 6),
                        Text(
                          'Date de paiement : ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                        Text(
                          invoice['datePayment'] != 'N/A'
                              ? invoice['datePayment']
                              : 'Non disponible',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                                fontWeight: FontWeight.w500,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          fetchInvoiceDetails(invoice['id']);
                        },
                        icon: const Icon(Icons.visibility),
                        label: Text(
                          "Voir les détails",
                          style: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF472072) : theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}