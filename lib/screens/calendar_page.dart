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
import '../widgets/notification_icon_button.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _isLoadingMore = false;
  Set<String> _loadedMonths = {}; // Track les mois déjà chargés (format: "YYYY-MM")

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
    // Charger les autres mois en arrière-plan après le chargement initial
    _loadOtherMonths();
  }

  // Charger les autres mois (précédents et suivants) en arrière-plan
  Future<void> _loadOtherMonths() async {
    // Attendre un peu pour ne pas surcharger
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Charger seulement les 2 mois précédents et les 2 mois suivants (au lieu de 3)
    // pour éviter de surcharger et de recharger inutilement
    for (int i = -2; i <= 2; i++) {
      if (i == 0) continue; // Le mois actuel est déjà chargé ou en cours de chargement
      
      final targetMonth = DateTime(_focusedDay.year, _focusedDay.month + i, 1);
      
      // Vérifier si le mois n'est pas déjà chargé
      if (!_isMonthLoaded(targetMonth)) {
        // Charger en arrière-plan sans bloquer l'UI
        _fetchEvents(loadMore: true, targetMonth: targetMonth).catchError((e) {
          developer.log('Error loading month ${_getMonthKey(targetMonth)}: $e', name: 'CalendarPage');
        });
        
        // Petit délai entre chaque requête pour ne pas surcharger
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        developer.log('Month ${_getMonthKey(targetMonth)} already loaded, skipping', name: 'CalendarPage');
      }
    }
  }

  // Calculer les dates de début et fin pour le mois visible
  Map<String, DateTime> _getMonthRange(DateTime focusedDay) {
    final firstDay = DateTime(focusedDay.year, focusedDay.month, 1);
    final lastDay = DateTime(focusedDay.year, focusedDay.month + 1, 0);
    return {
      'start': firstDay,
      'end': lastDay,
    };
  }

  // Obtenir la clé du mois (format: "YYYY-MM")
  String _getMonthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  // Formater la date pour l'API (format ISO 8601)
  String _formatDateForAPI(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Vérifier si un mois a déjà été chargé
  bool _isMonthLoaded(DateTime date) {
    return _loadedMonths.contains(_getMonthKey(date));
  }

  // Marquer un mois comme chargé
  void _markMonthAsLoaded(DateTime date) {
    _loadedMonths.add(_getMonthKey(date));
  }

  Future<void> _fetchEvents({bool loadMore = false, DateTime? targetMonth}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Utiliser le mois cible ou le mois focalisé
    final monthToLoad = targetMonth ?? _focusedDay;
    
    // Vérifier si le mois est déjà chargé - ne jamais recharger un mois déjà chargé
    if (_isMonthLoaded(monthToLoad)) {
      developer.log('Month ${_getMonthKey(monthToLoad)} already loaded, skipping fetch', name: 'CalendarPage');
      // Si c'est le chargement principal, s'assurer que l'UI n'est pas en état de chargement
      if (!loadMore) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (!loadMore) {
      setState(() {
        _isLoading = true;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      // Calculer startDate et endDate pour le mois à charger
      final monthRange = _getMonthRange(monthToLoad);
      final startDate = _formatDateForAPI(monthRange['start']!);
      final endDate = _formatDateForAPI(monthRange['end']!);

      developer.log('Fetching calendar events from $startDate to $endDate', name: 'CalendarPage');

      // Créer une requête multipart avec form-data
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      final baseUrl = 'https://www.unistudious.com';
      final request = http.MultipartRequest(
        'GET',
        Uri.parse('$baseUrl/api/calender'),
      );

      // Ajouter les champs form-data
      request.fields['startDate'] = startDate;
      request.fields['endDate'] = endDate;

      // Ajouter le token d'authentification
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });

      // Envoyer la requête
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

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

        // Séparer les événements : ceux avec start/end en premier, puis les autres
        List<dynamic> priorityEvents = [];
        List<dynamic> otherEvents = [];

        final monthStart = monthRange['start']!;
        final monthEnd = monthRange['end']!;

        for (var event in eventList) {
          try {
            String? startString = event['start'];
            String? endString = event['end'];
            
            // Prioriser les événements qui ont start ET end
            if (startString != null && startString.isNotEmpty && 
                endString != null && endString.isNotEmpty) {
              DateTime? eventStart = DateTime.tryParse(startString)?.toLocal();
              DateTime? eventEnd = DateTime.tryParse(endString)?.toLocal();
              
              if (eventStart != null && eventEnd != null) {
                // Vérifier si les dates sont dans la plage du mois visible
                if ((eventStart.isAfter(monthStart.subtract(const Duration(days: 1))) && 
                     eventStart.isBefore(monthEnd.add(const Duration(days: 1)))) ||
                    (eventEnd.isAfter(monthStart.subtract(const Duration(days: 1))) && 
                     eventEnd.isBefore(monthEnd.add(const Duration(days: 1))))) {
                  priorityEvents.add(event);
                } else {
                  otherEvents.add(event);
                }
              } else {
                otherEvents.add(event);
              }
            } else {
              otherEvents.add(event);
            }
          } catch (_) {
            otherEvents.add(event);
          }
        }

        // Traiter d'abord les événements prioritaires (avec start/end dans la plage)
        Map<DateTime, List<dynamic>> newEvents = Map.from(_events);
        
        for (var event in priorityEvents) {
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
              newEvents.putIfAbsent(normalizedDate, () => []);
              // Éviter les doublons pour une même journée (même id ou même couple start/end)
              final eventId = event['id']?.toString();
              final eventStart = event['start']?.toString();
              final eventEnd = event['end']?.toString();
              final alreadyExists = newEvents[normalizedDate]!.any((existing) {
                final existingId = existing['id']?.toString();
                final existingStart = existing['start']?.toString();
                final existingEnd = existing['end']?.toString();
                return (eventId != null && existingId == eventId) ||
                    (eventStart != null &&
                        eventEnd != null &&
                        existingStart == eventStart &&
                        existingEnd == eventEnd);
              });
              if (!alreadyExists) {
                newEvents[normalizedDate]!.add(event);
              }
            }
          } catch (_) {
            continue;
          }
        }

        // Marquer le mois comme chargé
        _markMonthAsLoaded(monthToLoad);

        // Mettre à jour l'UI immédiatement avec les événements prioritaires
        if (!loadMore) {
          setState(() {
            _events = newEvents;
            _isLoading = false;
          });
        } else {
          setState(() {
            _events = newEvents;
            _isLoadingMore = false;
          });
        }

        // Ensuite traiter les autres événements de manière asynchrone
        if (otherEvents.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              for (var event in otherEvents) {
                try {
                  String? dateString = event['start'] ?? event['date'];
                  DateTime? eventDate;

                  if (dateString != null && dateString.isNotEmpty) {
                    eventDate = DateTime.tryParse(dateString)?.toLocal();
                  }

                  if (eventDate != null) {
                    final normalizedDate = DateTime(eventDate.year, eventDate.month, eventDate.day);
                    setState(() {
                      _events.putIfAbsent(normalizedDate, () => []);
                      // Éviter les doublons pour une même journée (même id ou même couple start/end)
                      final eventId = event['id']?.toString();
                      final eventStart = event['start']?.toString();
                      final eventEnd = event['end']?.toString();
                      final alreadyExists = _events[normalizedDate]!.any((existing) {
                        final existingId = existing['id']?.toString();
                        final existingStart = existing['start']?.toString();
                        final existingEnd = existing['end']?.toString();
                        return (eventId != null && existingId == eventId) ||
                            (eventStart != null &&
                                eventEnd != null &&
                                existingStart == eventStart &&
                                existingEnd == eventEnd);
                      });
                      if (!alreadyExists) {
                        _events[normalizedDate]!.add(event);
                      }
                    });
                  }
                } catch (_) {
                  continue;
                }
              }
            }
          });
        }
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
      
      if (!loadMore) {
        setState(() => _isLoading = false);
      } else {
        setState(() => _isLoadingMore = false);
      }
      
      // Erreur silencieuse
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
        actions: [
          const NotificationIconButton(),
        ],
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
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
                // Charger le mois seulement s'il n'est pas déjà chargé
                if (!_isMonthLoaded(focusedDay)) {
                  _fetchEvents();
                  // Charger les autres mois en arrière-plan (seulement ceux non chargés)
                  _loadOtherMonths();
                } else {
                  developer.log('Month ${_getMonthKey(focusedDay)} already loaded, no fetch needed', name: 'CalendarPage');
                  // Ne pas recharger, juste charger les mois adjacents non chargés en arrière-plan
                  _loadOtherMonths();
                }
              },
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