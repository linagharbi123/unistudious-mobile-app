import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'resources_page.dart';
import 'calendar_page.dart';
import 'invoice_page.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  _StatisticsPageState createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool isLoading = true;
  String? errorMessage;

  // Variables pour les statistiques
  double inPersonAttendance = 0.0;
  double onlineAttendance = 0.0;
  int inPersonPresent = 0;
  int inPersonAbsent = 0;
  int onlinePresent = 0;
  int onlineAbsent = 0;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez vous connecter pour continuer.')),
        );
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }
    await _fetchStatistics();
  }

  Future<void> _fetchStatistics() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Fetch in-person attendance
      final inPersonResponse = await http.get(
        Uri.parse('https://www.unistudious.com/api/attendance'),
        headers: {
          'Authorization': 'Bearer ${authProvider.token}',
          'Content-Type': 'application/json',
        },
      );

      // Fetch online attendance
      final onlineResponse = await http.get(
        Uri.parse('https://www.unistudious.com/api/attendance-online'),
        headers: {
          'Authorization': 'Bearer ${authProvider.token}',
          'Content-Type': 'application/json',
        },
      );

      if (inPersonResponse.statusCode == 200 && onlineResponse.statusCode == 200) {
        final inPersonData = jsonDecode(inPersonResponse.body);
        final onlineData = jsonDecode(onlineResponse.body);

        setState(() {
          // In-person attendance data
          inPersonAttendance = (inPersonData['attendancePercentage'] ?? 0.0).toDouble();
          inPersonPresent = inPersonData['presentAttendances'] ?? 0;
          inPersonAbsent = inPersonData['absentAttendances'] ?? 0;

          // Online attendance data
          onlineAttendance = (onlineData['attendancePercentage'] ?? 0.0).toDouble();
          onlinePresent = onlineData['presentAttendances'] ?? 0;
          onlineAbsent = onlineData['absentAttendances'] ?? 0;

          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Erreur lors de la récupération des données : '
              'Présentiel(${inPersonResponse.statusCode}), En ligne(${onlineResponse.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur réseau : $e';
        isLoading = false;
      });
    }
  }

  // Section Pages Populaires
  Widget _buildPopularPages(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Pages Populaires",
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color ?? Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _pageCard(
          context,
          "Ressources",
          "Consultez et gérez vos ressources.",
          Icons.folder,
          Colors.indigo,
          const ResourcesPage(),
        ),
        const SizedBox(height: 12),
        _pageCard(
          context,
          "Calendrier",
          "Consultez et gérez votre calendrier.",
          Icons.calendar_month,
          Colors.deepPurple,
          CalendarPage(),
        ),
        const SizedBox(height: 12),
        _pageCard(
          context,
          "Factures",
          "Consultez et gérez vos factures ici.",
          Icons.receipt_long,
          Colors.orange,
          const InvoicePage(),
        ),
      ],
    );
  }

  Widget _pageCard(BuildContext context, String title, String desc, IconData icon, Color color, Widget page) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          elevation: 4,
          shadowColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: theme.cardColor,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: theme.textTheme.bodyMedium?.color ?? Colors.grey[700],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => page),
                    );
                  },
                  child: Text(
                    "Ouvrir",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Section Présence
  Widget _buildAttendanceStats(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Présence",
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color ?? Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                "En Présentiel",
                "${inPersonAttendance.toStringAsFixed(2)}%",
                Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                "En Ligne",
                "${onlineAttendance.toStringAsFixed(2)}%",
                Colors.pink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          "Aperçu de la présence",
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.textTheme.titleMedium?.color ?? Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: theme.cardColor,
          child: SizedBox(
            height: 320,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.dividerColor.withOpacity(0.2),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 10,
                        getTitlesWidget: (value, meta) {
                          if (value % 10 == 0 && value >= 0 && value <= 100) {
                            return Text(
                              value.toInt().toString(),
                              style: theme.textTheme.bodySmall,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return Text(
                                "Présent\nPrésentiel",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              );
                            case 1:
                              return Text(
                                "Absent\nPrésentiel",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              );
                            case 2:
                              return Text(
                                "Présent\nEn ligne",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              );
                            case 3:
                              return Text(
                                "Absent\nEn ligne",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              );
                            default:
                              return const Text("");
                          }
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: isDark ? Colors.black87 : Colors.grey[800],
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          "${rod.toY.toInt()}",
                          theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ) ?? const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  minY: 0,
                  maxY: 100,
                  barGroups: [
                    _makeBarGroup(0, inPersonPresent.toDouble(), [Colors.teal.shade400, Colors.teal.shade800]),
                    _makeBarGroup(1, inPersonAbsent.toDouble(), [Colors.red.shade400, Colors.red.shade700]),
                    _makeBarGroup(2, onlinePresent.toDouble(), [Colors.pink.shade400, Colors.pink.shade700]),
                    _makeBarGroup(3, onlineAbsent.toDouble(), [Colors.amber.shade400, Colors.amber.shade700]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  BarChartGroupData _makeBarGroup(int x, double value, List<Color> gradient) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: value,
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
          borderRadius: BorderRadius.circular(8),
          width: 28,
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, Color color) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      shadowColor: color.withOpacity(0.4),
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyMedium?.color ?? Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Statistiques',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ) ?? const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
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
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : errorMessage != null
          ? Center(
        child: Text(
          errorMessage!,
          style: theme.textTheme.bodyLarge,
        ),
      )
          : RefreshIndicator(
        onRefresh: _fetchStatistics,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopularPages(context),
              const SizedBox(height: 24),
              _buildAttendanceStats(context),
            ],
          ),
        ),
      ),
    );
  }
}