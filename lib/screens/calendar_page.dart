import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:developer' as developer;
import '../widgets/sidebar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<dynamic>> _events = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    initializeDateFormatting('fr_FR', null).then((_) {
      setState(() {});
    });
    _checkAuthAndFetchData();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez vous connecter pour continuer.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    await _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/calender',
      );

      developer.log('API Response (calendar): ${response.statusCode} - ${response.body}', name: 'CalendarPage');

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        List<dynamic> eventList;

        if (data is List) {
          eventList = data;
        } else if (data is Map<String, dynamic>) {
          eventList = data['calendar'] ?? [];
        } else {
          eventList = [];
        }

        Map<DateTime, List<dynamic>> events = {};
        for (var event in eventList) {
          try {
            String? dateString = event['start'];
            DateTime? eventDate;

            if (dateString != null && dateString.isNotEmpty) {
              eventDate = DateTime.tryParse(dateString)?.toLocal();
            } else if (event['date'] != null) {
              eventDate = DateTime.tryParse(event['date'])?.toLocal();
            }

            if (eventDate != null) {
              final normalizedDate = DateTime(eventDate.year, eventDate.month, eventDate.day);
              events.putIfAbsent(normalizedDate, () => []);
              events[normalizedDate]!.add(event);
            }
          } catch (_) {
            continue;
          }
        }

        setState(() {
          _events = events;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load events: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error fetching events: $e', name: 'CalendarPage');
      
      // Détecter les erreurs de connexion et ne pas afficher de snackbar
      final isNetworkError = e is SocketException || 
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection');
      
      setState(() => _isLoading = false);
      
      // Ne pas afficher de snackbar pour les erreurs de connexion
      if (!isNetworkError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement : $e')),
        );
      }
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _events[normalizedDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
    developer.log('Navigating to DateDetailsPage for day: $selectedDay', name: 'CalendarPage');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DateDetailsPage(
          selectedDay: selectedDay,
          events: _getEventsForDay(selectedDay),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentDate = DateTime.now();
    final dateFormat = DateFormat('d MMMM yyyy', 'fr_FR');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Text(
          dateFormat.format(currentDate),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ) ??
              const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? theme.iconTheme.color : Colors.white),
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
      drawer: const AppSidebar(),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
            : Padding(
          padding: const EdgeInsets.all(12.0),
          child: Card(
            color: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: TableCalendar(
              locale: 'fr_FR',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: _onDaySelected,
              eventLoader: _getEventsForDay,
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.deepPurple,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.deepPurpleAccent,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                selectedTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                defaultTextStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                weekendTextStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red[600]),
                outsideTextStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]),
                markerDecoration: BoxDecoration(
                  color: Colors.purple[700],
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 3,
                markersAlignment: Alignment.bottomCenter,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  color: Colors.deepPurple,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.deepPurple),
                rightChevronIcon: Icon(Icons.chevron_right, color: Colors.deepPurple),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                weekendStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red[600]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DateDetailsPage extends StatelessWidget {
  final DateTime selectedDay;
  final List<dynamic> events;

  const DateDetailsPage({super.key, required this.selectedDay, required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr_FR');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            developer.log('Back button pressed in DateDetailsPage', name: 'DateDetailsPage');
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              developer.log('Cannot pop, navigating to /calendar', name: 'DateDetailsPage');
              Navigator.pushReplacementNamed(context, '/calendar');
            }
          },
          tooltip: 'Retour',
        ),
        title: Text(
          dateFormat.format(selectedDay),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ) ??
              const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? theme.iconTheme.color : Colors.white),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: events.isEmpty
            ? Center(
          child: Text(
            'Aucun événement pour ce jour',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontStyle: FontStyle.italic,
              fontSize: 16,
            ),
          ),
        )
            : ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final startTime = event['start'] != null
                ? DateFormat('HH:mm').format(
              DateTime.parse(event['start']).toLocal(),
            )
                : 'Toute la journée';
            final endTime = event['end'] != null
                ? DateFormat('HH:mm').format(
              DateTime.parse(event['end']).toLocal(),
            )
                : '';

            return Card(
              color: theme.cardColor,
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 3,
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  backgroundColor: isDark ? Colors.deepPurple[300] : Colors.deepPurple[100],
                  child: const Icon(Icons.event, color: Colors.deepPurple),
                ),
                title: Text(
                  event['title'] ?? 'Sans titre',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ??
                      TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                ),
                subtitle: Text(
                  '${event['description'] ?? 'Aucune description'}\nHeure: $startTime${endTime.isNotEmpty ? ' - $endTime' : ''}',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}