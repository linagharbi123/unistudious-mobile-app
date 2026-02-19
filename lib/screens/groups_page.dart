import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/loading_wrapper.dart';
import '../utils/snackbar_helper.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../widgets/sidebar.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> sessions = [];
  DateTime selectedDate = DateTime.now();
  TabController? _tabController;
  bool isLoading = true;
  String? errorMessage;
  String? selectedNewGroupId;
  final TextEditingController _reasonController = TextEditingController();
  final Map<int, List<Map<String, dynamic>>> currentGroups = {};
  final String apiBaseUrl = 'https://www.unistudious.com';
  
  // Pagination data
  Map<String, dynamic>? pagination;
  List<Map<String, dynamic>> uniqueSessionsData = [];
  
  // Pagination par session
  final Map<int, int> _currentPage = {}; // sessionId -> page actuelle
  final Map<int, bool> _isLoadingMore = {}; // sessionId -> chargement en cours
  final Map<int, bool> _hasMorePages = {}; // sessionId -> il y a encore des pages
  final Map<int, ScrollController> _scrollControllers = {}; // sessionId -> ScrollController
  
  // Pour les calendriers par session
  final Map<int, DateTime> _focusedDays = {}; // sessionId -> focusedDay
  final Map<int, DateTime?> _selectedDays = {}; // sessionId -> selectedDay
  final Map<int, Map<DateTime, List<Map<String, dynamic>>>> _sessionEvents = {}; // sessionId -> events
  final Map<int, bool> _isLoadingCalendar = {}; // sessionId -> isLoading
  final Map<int, Set<String>> _loadedMonths = {}; // sessionId -> loadedMonths

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);
    _tabController = TabController(length: 1, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndFetchData();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _reasonController.dispose();
    // Nettoyer les ScrollControllers
    for (var controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    loadingProvider.showLoading();

    try {
      await fetchSessions();
      
      // Charger les groupes pour toutes les sessions en parallèle (sans calendriers pour être rapide)
      if (sessions.isNotEmpty) {
        final futures = sessions.map((session) async {
          final sessionId = session['id'];
          _currentPage[sessionId] = 1;
          _hasMorePages[sessionId] = true;
          // Charger les groupes sans calendriers pour être rapide
          await fetchGroups(sessionId: sessionId, page: 1, perPage: 8, append: false, skipCalendar: true);
        }).toList();
        
        // Attendre que tous les groupes soient chargés en parallèle
        await Future.wait(futures);
        
        // Masquer le loading après que le frame soit rendu pour s'assurer que les groupes sont affichés
        if (mounted) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              loadingProvider.hideLoading();
            }
          });
        }
        
        // Charger les calendriers en arrière-plan après l'affichage
        Future.microtask(() async {
          for (var session in sessions) {
            final sessionId = session['id'];
            await _loadCalendarForGroups(sessionId);
          }
        });
      }
      
      await fetchCurrentGroupForSessions();
      
      // Charger immédiatement le calendrier de la première session avec startDate et endDate
      if (sessions.isNotEmpty) {
        final firstSessionId = sessions.first['id'];
        // Initialiser les structures pour la première session
        if (!_focusedDays.containsKey(firstSessionId)) {
          _focusedDays[firstSessionId] = DateTime.now();
          _selectedDays[firstSessionId] = null;
          _sessionEvents[firstSessionId] = {};
          _isLoadingCalendar[firstSessionId] = false;
          _loadedMonths[firstSessionId] = {};
        }
        // Charger le mois actuel immédiatement
        _fetchSessionCalendarEvents(firstSessionId, isPriority: true);
        // Charger les autres mois en arrière-plan
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadOtherMonthsInBackground(firstSessionId);
          }
        });
        // Charger les autres sessions en arrière-plan
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && sessions.length > 1) {
            for (int i = 1; i < sessions.length; i++) {
              final sessionId = sessions[i]['id'];
              if (!_focusedDays.containsKey(sessionId)) {
                _focusedDays[sessionId] = DateTime.now();
                _selectedDays[sessionId] = null;
                _sessionEvents[sessionId] = {};
                _isLoadingCalendar[sessionId] = false;
                _loadedMonths[sessionId] = {};
              }
              _fetchSessionCalendarEvents(sessionId, isPriority: false);
              Future.delayed(Duration(milliseconds: 200 * i), () {
                if (mounted) {
                  _loadOtherMonthsInBackground(sessionId);
                }
              });
            }
          }
        });
      }
    } catch (e) {
      developer.log('🔴 Erreur dans _checkAuthAndFetchData: $e', name: 'GroupsPage', error: e);
      setState(() {
        errorMessage = 'Erreur lors du chargement: $e';
      });
    } finally {
      loadingProvider.hideLoading();
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> refreshData() async {
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
    loadingProvider.showLoading();
    
    try {
      await fetchSessions();
      // Réinitialiser la pagination pour toutes les sessions et charger en parallèle
      if (sessions.isNotEmpty) {
        final futures = sessions.map((session) async {
          final sessionId = session['id'];
          _currentPage[sessionId] = 1;
          _hasMorePages[sessionId] = true;
          await fetchGroups(sessionId: sessionId, page: 1, perPage: 8, append: false, skipCalendar: true);
        }).toList();
        
        await Future.wait(futures);
        
        // Masquer le loading après que le frame soit rendu pour s'assurer que les groupes sont affichés
        if (mounted) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              loadingProvider.hideLoading();
            }
          });
        }
        
        // Charger les calendriers en arrière-plan
        Future.microtask(() async {
          for (var session in sessions) {
            final sessionId = session['id'];
            await _loadCalendarForGroups(sessionId);
          }
        });
      }
      
      await fetchCurrentGroupForSessions();
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur lors du rafraîchissement: $e';
      });
    } finally {
      loadingProvider.hideLoading();
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchSessions() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const String endpoint = '/api/management/get-sessions';

    try {
      final response = await authProvider
          .authenticatedRequest('GET', endpoint)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is! List) {
          throw const FormatException('Expected a list of sessions');
        }
        setState(() {
          sessions = data
              .where((item) => item['id'] != null && item['name'] != null)
              .map((item) => {
            'id': item['id'],
            'name': item['name'] as String,
          })
              .toList();
          _tabController?.dispose();
          _tabController = TabController(
            length: sessions.isNotEmpty ? sessions.length : 1,
            vsync: this,
          );
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pushReplacementNamed(context, '/login');
        }
        await authProvider.logout();
      } else {
        setState(() {
          errorMessage = 'Échec du chargement des sessions : ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur lors de la récupération des sessions : $e';
      });
    }
  }

  // Fonction pour charger les calendriers pour les groupes d'une session
  Future<void> _loadCalendarForGroups(int sessionId) async {
    if (!mounted) return;
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Vérifier qu'il y a des groupes pour cette session
      final sessionGroups = groups.where((g) => g['sessionId'] == sessionId).toList();
      if (sessionGroups.isEmpty) return;
      
      developer.log('📅 Chargement du calendrier pour sessionId: $sessionId', name: 'GroupsPage');
      
      final calendarEndpoint = '/api/get-calander-group-management/$sessionId';
      final calendarResponse = await authProvider
          .authenticatedRequest('GET', calendarEndpoint);

      if (calendarResponse.statusCode == 200 && mounted) {
        final Map<String, dynamic> calendarData = jsonDecode(calendarResponse.body);
        final List<dynamic> calendarEvents = calendarData['calendarEvents'] ?? [];

        setState(() {
          for (var group in groups) {
            if (group['sessionId'] == sessionId) {
              final event = calendarEvents.firstWhere(
                    (event) => event['groupId'] == group['groupId'],
                orElse: () => {},
              );
              if (event.isNotEmpty) {
                group['teacher'] = event['teacherName'] ?? 'Unknown';
                group['subject'] = event['subjectName'] ?? 'Unknown';
              }
            }
          }
        });
        
        developer.log('📅 ✅ Calendrier chargé pour sessionId: $sessionId', name: 'GroupsPage');
      }
    } catch (e) {
      developer.log('🔴 Erreur lors du chargement du calendrier pour sessionId $sessionId: $e', name: 'GroupsPage');
    }
  }

  Future<void> fetchGroups({int? sessionId, int page = 1, int perPage = 8, bool append = false, bool skipCalendar = false}) async {
    developer.log('🔵 fetchGroups appelé - sessionId: $sessionId, page: $page, perPage: $perPage, append: $append', name: 'GroupsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const String groupsEndpoint = '/api/get-group-management';

    try {
      // Construire l'URI avec les paramètres de requête
      final uri = Uri.parse('$apiBaseUrl$groupsEndpoint').replace(
        queryParameters: {
          if (sessionId != null) 'sessionId': sessionId.toString(),
          'page': page.toString(),
          'perPage': perPage.toString(),
        },
      );

      developer.log('🔵 URI construite: ${uri.toString()}', name: 'GroupsPage');
      developer.log('🔵 Envoi de la requête API...', name: 'GroupsPage');

      final groupsResponse = await authProvider
          .authenticatedRequest('GET', uri.toString());

      developer.log('🔵 Réponse reçue - Status: ${groupsResponse.statusCode}', name: 'GroupsPage');

      if (groupsResponse.statusCode == 200) {
        final Map<String, dynamic> groupsData = jsonDecode(groupsResponse.body);
        final List<dynamic> rawGroups = groupsData['groups'] ?? [];
        
        developer.log('🔵 Nombre de groupes reçus: ${rawGroups.length}', name: 'GroupsPage');
        
        // Gérer la pagination
        if (groupsData['pagination'] != null) {
          final paginationData = Map<String, dynamic>.from(groupsData['pagination']);
          final currentPageNum = paginationData['currentPage'] as int? ?? page;
          final totalPages = paginationData['totalPages'] as int? ?? 1;
          
          developer.log('🔵 Pagination - currentPage: $currentPageNum, totalPages: $totalPages', name: 'GroupsPage');
          
          if (sessionId != null) {
            setState(() {
              _currentPage[sessionId] = currentPageNum;
              _hasMorePages[sessionId] = currentPageNum < totalPages;
            });
            developer.log('🔵 État pagination mis à jour pour sessionId $sessionId - hasMorePages: ${_hasMorePages[sessionId]}', name: 'GroupsPage');
          }
          
          setState(() {
            pagination = paginationData;
          });
        }
        
        // Gérer uniqueSessionsData
        if (groupsData['uniqueSessionsData'] != null) {
          setState(() {
            uniqueSessionsData = List<Map<String, dynamic>>.from(
              groupsData['uniqueSessionsData'].map((session) => Map<String, dynamic>.from(session))
            );
          });
        }
        
        List<Map<String, dynamic>> tempGroups = rawGroups.map((group) {
          final capacityStr = group['capacity']?.toString() ?? '0';
          int capacity;
          try {
            capacity = int.parse(capacityStr);
          } catch (e) {
            capacity = 0;
          }
          return {
            'groupId': group['groupId'],
            'name': group['groupName'] ?? 'Groupe sans nom',
            'capacity': capacity,
            'members': group['userCount'] ?? 0,
            'joined': group['isUserInGroup'] ?? false,
            'pendingJoin': group['pendingJoin'] ?? false,
            'hasEmptyRelation': group['hasEmptyRelation'] ?? false,
            'userOneRelation': group['userOneRelation'] ?? false,
            'specialGroupStatus': group['specialGroupStatus'] ?? false,
            'sessionId': group['sessionId'],
            'teacher': 'Unknown',
            'subject': 'Unknown',
            'type': group['type'] ?? 'Normal',
          };
        }).toList();

        developer.log('🔵 Groupes transformés: ${tempGroups.length} groupes', name: 'GroupsPage');
        developer.log('🔵 Groupes pour sessionId $sessionId: ${tempGroups.where((g) => g['sessionId'] == sessionId).length}', name: 'GroupsPage');

        // Charger les calendriers seulement si skipCalendar est false
        if (!skipCalendar) {
          // Charger les calendriers seulement pour la session concernée ou pour toutes les sessions si sessionId est null
          final sessionsToProcess = sessionId != null 
              ? sessions.where((s) => s['id'] == sessionId).toList()
              : sessions;

          for (var session in sessionsToProcess) {
            final currentSessionId = session['id'];
            // Ne charger le calendrier que pour les groupes de cette session
            final groupsForThisSession = tempGroups.where((g) => g['sessionId'] == currentSessionId).toList();
            
            if (groupsForThisSession.isNotEmpty) {
              try {
                final calendarEndpoint = '/api/get-calander-group-management/$currentSessionId';
                final calendarResponse = await authProvider
                    .authenticatedRequest('GET', calendarEndpoint);

                if (calendarResponse.statusCode == 200) {
                  final Map<String, dynamic> calendarData = jsonDecode(calendarResponse.body);
                  final List<dynamic> calendarEvents = calendarData['calendarEvents'] ?? [];

                  for (var group in groupsForThisSession) {
                    final event = calendarEvents.firstWhere(
                          (event) => event['groupId'] == group['groupId'],
                      orElse: () => {},
                    );
                    if (event.isNotEmpty) {
                      group['teacher'] = event['teacherName'] ?? 'Unknown';
                      group['subject'] = event['subjectName'] ?? 'Unknown';
                    }

                    if (group['joined'] || !group['pendingJoin']) {
                      await authProvider.removePendingChange(currentSessionId, group['groupId']);
                      await authProvider.removePendingJoin(currentSessionId, group['groupId']);
                    }
                  }
                }
              } catch (e) {
                // En cas d'erreur sur le calendrier, continuer avec les groupes sans les infos de calendrier
                // Les groupes seront quand même ajoutés avec 'Unknown' pour teacher et subject
              }
            }
          }
        }

        developer.log('🔵 Avant setState - Nombre total de groupes actuels: ${groups.length}', name: 'GroupsPage');
        developer.log('🔵 append: $append, sessionId: $sessionId', name: 'GroupsPage');
        
        setState(() {
          if (append && sessionId != null) {
            // Ajouter les nouveaux groupes à la liste existante pour cette session
            // Garder les groupes des autres sessions
            final otherSessionsGroups = groups.where((g) => g['sessionId'] != sessionId).toList();
            // Garder les groupes existants de cette session
            final existingSessionGroups = groups.where((g) => g['sessionId'] == sessionId).toList();
            // Ajouter les nouveaux groupes de cette session
            final newGroupsForSession = tempGroups.where((g) => g['sessionId'] == sessionId).toList();
            developer.log('🔵 Mode APPEND - otherSessionsGroups: ${otherSessionsGroups.length}, existingSessionGroups: ${existingSessionGroups.length}, newGroupsForSession: ${newGroupsForSession.length}', name: 'GroupsPage');
            // Combiner : autres sessions + groupes existants de cette session + nouveaux groupes de cette session
            groups = [...otherSessionsGroups, ...existingSessionGroups, ...newGroupsForSession];
            developer.log('🔵 Après APPEND - Nombre total de groupes: ${groups.length}', name: 'GroupsPage');
            developer.log('🔵 Groupes pour sessionId $sessionId: ${groups.where((g) => g['sessionId'] == sessionId).length}', name: 'GroupsPage');
          } else {
            // Remplacer tous les groupes ou seulement ceux de la session spécifiée
            if (sessionId != null) {
              final otherSessionsGroups = groups.where((g) => g['sessionId'] != sessionId).toList();
              final thisSessionGroups = tempGroups.where((g) => g['sessionId'] == sessionId).toList();
              developer.log('🔵 Mode REPLACE pour sessionId $sessionId - otherSessionsGroups: ${otherSessionsGroups.length}, thisSessionGroups: ${thisSessionGroups.length}', name: 'GroupsPage');
              groups = [...otherSessionsGroups, ...thisSessionGroups];
            } else {
              developer.log('🔵 Mode REPLACE tous les groupes - tempGroups: ${tempGroups.length}', name: 'GroupsPage');
              groups = tempGroups;
            }
            developer.log('🔵 Après REPLACE - Nombre total de groupes: ${groups.length}', name: 'GroupsPage');
          }
        });
        
        developer.log('🔵 ✅ setState terminé - Nombre final de groupes: ${groups.length}', name: 'GroupsPage');
      } else if (groupsResponse.statusCode == 401 || groupsResponse.statusCode == 403) {
        developer.log('🔴 Erreur d\'authentification: ${groupsResponse.statusCode}', name: 'GroupsPage');
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pushReplacementNamed(context, '/login');
        }
        await authProvider.logout();
      } else {
        developer.log('🔴 Erreur HTTP: ${groupsResponse.statusCode}', name: 'GroupsPage');
        developer.log('🔴 Body de la réponse: ${groupsResponse.body}', name: 'GroupsPage');
        setState(() {
          errorMessage = 'Échec du chargement des groupes : ${groupsResponse.statusCode}';
        });
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Exception dans fetchGroups: $e', name: 'GroupsPage', error: e, stackTrace: stackTrace);
      setState(() {
        errorMessage = 'Erreur lors de la récupération des groupes : $e';
      });
    }
  }

  Future<void> loadMoreGroups(int sessionId, {int perPage = 8}) async {
    developer.log('🟢 loadMoreGroups appelé pour sessionId: $sessionId', name: 'GroupsPage');
    developer.log('🟢 _isLoadingMore[$sessionId]: ${_isLoadingMore[sessionId]}', name: 'GroupsPage');
    developer.log('🟢 _hasMorePages[$sessionId]: ${_hasMorePages[sessionId]}', name: 'GroupsPage');
    
    if (_isLoadingMore[sessionId] == true || _hasMorePages[sessionId] == false) {
      developer.log('🟡 loadMoreGroups annulé - isLoadingMore: ${_isLoadingMore[sessionId]}, hasMorePages: ${_hasMorePages[sessionId]}', name: 'GroupsPage');
      return;
    }

    developer.log('🟢 Démarrage du chargement de plus de groupes...', name: 'GroupsPage');
    setState(() {
      _isLoadingMore[sessionId] = true;
    });

    final currentPage = _currentPage[sessionId] ?? 1;
    final nextPage = currentPage + 1;
    developer.log('🟢 Page actuelle: $currentPage, Page suivante: $nextPage', name: 'GroupsPage');
    
    try {
      await fetchGroups(sessionId: sessionId, page: nextPage, perPage: perPage, append: true);
      developer.log('🟢 fetchGroups terminé avec succès', name: 'GroupsPage');
    } catch (e) {
      developer.log('🔴 Erreur dans loadMoreGroups: $e', name: 'GroupsPage', error: e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore[sessionId] = false;
        });
        developer.log('🟢 _isLoadingMore[$sessionId] mis à false', name: 'GroupsPage');
      }
    }
  }

  Future<void> fetchCurrentGroupForSessions() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    for (var session in sessions) {
      final sessionId = session['id'];
      final String endpoint = '/api/management/get-current-group/$sessionId';
      try {
        final response = await authProvider
            .authenticatedRequest('GET', endpoint)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          List<Map<String, dynamic>> sessionCurrentGroups = [];
          if (data['groups'] != null && data['groups'].isNotEmpty) {
            for (var group in data['groups']) {
              final matchingGroup = groups.firstWhere(
                    (g) => g['sessionId'] == sessionId && g['groupId'] == group['id'] && g['joined'] == true,
                orElse: () => {},
              );
              if (matchingGroup.isNotEmpty) {
                sessionCurrentGroups.add({
                  'sessionId': sessionId,
                  'groupId': group['id'],
                  'name': group['name'] ?? 'Groupe sans nom',
                });
              }
            }
          }
          setState(() {
            currentGroups[sessionId] = sessionCurrentGroups;
          });
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          if (mounted) {
            SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
            Navigator.pushReplacementNamed(context, '/login');
          }
          await authProvider.logout();
        } else {
          setState(() {
            currentGroups[sessionId] = [];
          });
        }
      } catch (e) {
        setState(() {
          currentGroups[sessionId] = [];
          errorMessage = 'Erreur inattendue pour la session $sessionId : $e';
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupCalendarEvents(int sessionId, int groupId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String endpoint = '/api/get-calander-group-management/$sessionId';

    try {
      final response = await authProvider
          .authenticatedRequest('GET', endpoint)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> rawEvents = data['calendarEvents'] ?? [];
        final List<Map<String, dynamic>> calendarEvents = rawEvents
            .where((event) => event['groupId'] == groupId && event['start'] != null && event['end'] != null)
            .map((event) {
          DateTime? start, end, date;
          try {
            start = DateTime.parse(event['start']);
            end = DateTime.parse(event['end']);
            date = DateTime.parse(event['date'] ?? event['start']);
          } catch (e) {
            return null;
          }
          return {
            'id': event['id'],
            'ref': event['ref'],
            'title': event['title'] ?? 'Sans titre',
            'start': start,
            'end': end,
            'backgroundColor': event['backgroundColor'],
            'description': event['description'] ?? '',
            'date': date,
            'sessionId': event['sessionId'],
            'groupId': event['groupId'],
            'userCount': event['userCount'] ?? 0,
            'isUserInGroup': event['isUserInGroup'] ?? false,
            'hasEmptyRelation': event['hasEmptyRelation'] ?? false,
            'capacity': int.tryParse(event['capacity']?.toString() ?? '0') ?? 0,
            'userOneRelation': event['userOneRelation'] ?? false,
            'specialGroupStatus': event['specialGroupStatus'] ?? false,
            'accessType': event['accessType'],
            'teacherName': event['teacherName'] ?? 'Unknown',
            'subjectName': event['subjectName'] ?? 'Unknown',
          };
        })
            .whereType<Map<String, dynamic>>()
            .toList();

        return calendarEvents;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pushReplacementNamed(context, '/login');
        }
        await authProvider.logout();
        return [];
      } else {
        setState(() {
          errorMessage = 'Échec du chargement des événements : ${response.statusCode}';
        });
        return [];
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur lors de la récupération des événements : $e';
      });
      return [];
    }
  }

  String _getMonthKey(DateTime date) {
    return '${date.year}-${date.month}';
  }

  Future<void> _fetchSessionCalendarEvents(int sessionId, {DateTime? monthDate, bool isPriority = false}) async {
    // Initialiser les structures pour cette session si nécessaire
    if (!_focusedDays.containsKey(sessionId)) {
      _focusedDays[sessionId] = DateTime.now();
      _selectedDays[sessionId] = null;
      _sessionEvents[sessionId] = {};
      _isLoadingCalendar[sessionId] = false;
      _loadedMonths[sessionId] = {};
    }
    
    final targetMonth = monthDate ?? _focusedDays[sessionId]!;
    final monthKey = _getMonthKey(targetMonth);
    
    if (_loadedMonths[sessionId]!.contains(monthKey) && !isPriority) {
      return;
    }

    // Calculer startDate et endDate pour le mois ciblé
    final firstDayOfMonth = DateTime(targetMonth.year, targetMonth.month, 1);
    final lastDayOfMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0);
    
    // Formater les dates au format ISO 8601
    final startDate = firstDayOfMonth.toUtc().toIso8601String();
    final endDate = lastDayOfMonth.toUtc().toIso8601String();

    // Ne jamais afficher le loader dans le calendrier
    // Le chargement se fait en arrière-plan

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      Map<DateTime, List<Map<String, dynamic>>> newEvents = {};

      // Construire l'URL
      final uri = Uri.parse('$apiBaseUrl/api/get-calander-group-management/$sessionId');

      // Récupérer le token d'authentification
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      // Créer une requête MultipartRequest pour GET avec form-data (comme dans calendar_page.dart)
      final request = http.MultipartRequest('GET', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['startDate'] = startDate
        ..fields['endDate'] = endDate
        ..fields['sessionId'] = sessionId.toString();

      // Envoyer la requête avec un timeout plus court pour le mois actuel
      final timeoutDuration = isPriority ? const Duration(seconds: 15) : const Duration(seconds: 30);
      final streamedResponse = await request.send().timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> rawEvents = data['calendarEvents'] ?? [];

        // Créer un cache temporaire des noms de groupes pour éviter les recherches répétées
        final groupNameCache = <int, String>{};
        
        for (var event in rawEvents) {
          if (event['start'] != null && event['end'] != null) {
            DateTime? start, end;
            try {
              start = DateTime.parse(event['start']).toLocal();
              end = DateTime.parse(event['end']).toLocal();
            } catch (e) {
              continue;
            }

            // Utiliser la date de début (start) pour déterminer le jour d'affichage
            final normalizedDate = DateTime(start.year, start.month, start.day);
            
            // Utiliser le cache pour le nom du groupe
            final groupId = event['groupId'] as int;
            String groupName = groupNameCache[groupId] ?? '';
            if (groupName.isEmpty) {
              final group = groups.firstWhere(
                (g) => g['groupId'] == groupId && g['sessionId'] == sessionId,
                orElse: () => {'name': 'Groupe inconnu'},
              );
              groupName = group['name'] ?? 'Groupe inconnu';
              groupNameCache[groupId] = groupName;
            }
            
            final eventData = {
              'id': event['id'],
              'ref': event['ref'],
              'title': event['title'] ?? 'Sans titre',
              'start': start,
              'end': end,
              'backgroundColor': event['backgroundColor'],
              'description': event['description'] ?? '',
              'date': start, // Utiliser start comme date d'affichage
              'sessionId': event['sessionId'],
              'groupId': groupId,
              'groupName': groupName,
              'teacherName': event['teacherName'] ?? 'Unknown',
              'subjectName': event['subjectName'] ?? 'Unknown',
            };

            newEvents.putIfAbsent(normalizedDate, () => []);
            newEvents[normalizedDate]!.add(eventData);
          }
        }
      }

      _loadedMonths[sessionId]!.add(monthKey);

      if (mounted) {
        setState(() {
          _sessionEvents[sessionId] = {..._sessionEvents[sessionId]!, ...newEvents};
          // Désactiver le loader immédiatement après avoir reçu les données
          _isLoadingCalendar[sessionId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCalendar[sessionId] = false;
        });
      }
    }
  }

  Future<void> _loadOtherMonthsInBackground(int sessionId) async {
    // Charger les mois précédents et suivants en arrière-plan sans loader
    final currentMonth = _focusedDays[sessionId] ?? DateTime.now();
    
    // Charger 2 mois précédents et 2 mois suivants
    for (int i = -2; i <= 2; i++) {
      if (i == 0) continue; // Le mois actuel est déjà chargé
      
      final monthToLoad = DateTime(currentMonth.year, currentMonth.month + i, 1);
      final monthKey = _getMonthKey(monthToLoad);
      
      if (!(_loadedMonths[sessionId]?.contains(monthKey) ?? false)) {
        _fetchSessionCalendarEvents(sessionId, monthDate: monthToLoad, isPriority: false);
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(int sessionId, DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _sessionEvents[sessionId]?[normalizedDay] ?? [];
  }

  void _onDaySelected(int sessionId, DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDays[sessionId] = selectedDay;
      _focusedDays[sessionId] = focusedDay;
    });
    _showDayEventsDialog(sessionId, selectedDay);
  }

  void _showDayEventsDialog(int sessionId, DateTime day) {
    final events = _getEventsForDay(sessionId, day);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr_FR');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: theme.dialogBackgroundColor,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                        : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        dateFormat.format(day),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: events.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Aucune séance prévue ce jour',
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final startTime = DateFormat('HH:mm').format(event['start'] as DateTime);
                          final endTime = DateFormat('HH:mm').format(event['end'] as DateTime);
                          final groupName = event['groupName'] ?? 'Groupe inconnu';
                          final teacherName = event['teacherName'] ?? 'Enseignant non spécifié';
                          final subjectName = event['subjectName'] ?? 'Matière non spécifiée';
                          final description = event['description']?.toString().trim() ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 3,
                            color: theme.cardColor,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Barre verticale et nom du groupe
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: theme.primaryColor,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Nom du groupe en grand
                                            Text(
                                              groupName,
                                              style: theme.textTheme.titleLarge?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 20,
                                              ) ?? const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 20,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            // Titre de la séance
                                            if (event['title'] != null && event['title'].toString().isNotEmpty)
                                              Text(
                                                event['title'],
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                                  fontSize: 14,
                                                ) ?? TextStyle(
                                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                                  fontSize: 14,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Heure avec icône
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 18,
                                        color: theme.primaryColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$startTime - $endTime',
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ) ?? TextStyle(
                                          color: theme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Enseignant
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 18,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Enseignant : $teacherName',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                                          ) ?? TextStyle(
                                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Matière
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.book,
                                        size: 18,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Matière : $subjectName',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                                          ) ?? TextStyle(
                                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Description si elle existe et n'est pas technique
                                  if (description.isNotEmpty && 
                                      !description.toLowerCase().contains('group') &&
                                      !description.toLowerCase().contains('has learning') &&
                                      !description.toLowerCase().contains('with teacher') &&
                                      !description.toLowerCase().contains('on subject')) ...[
                                    const SizedBox(height: 12),
                                    const Divider(height: 1),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Description',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                                      ) ?? TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        height: 1.4,
                                      ) ?? TextStyle(
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCalendar(int sessionId) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Palette de couleurs pour le calendrier (assortie au violet de l'app)
    final Color todayColor = isDark
        ? const Color(0xFF2962FF) // bleu un peu plus vif en mode sombre
        : const Color(0xFF1E88E5); // bleu moyen en mode clair
    final Color selectedDayColor = theme.primaryColor; // violet principal
    final Color markerColor = isDark
        ? const Color(0xFFB388FF) // violet clair en mode sombre
        : const Color(0xFFD1C4E9); // violet très clair en mode clair
    // Couleur pour le titre \"Calendrier - session\" (pas en violet)
    final Color calendarTitleColor = isDark
        ? const Color(0xFFBBDEFB) // bleu très clair en mode sombre
        : const Color(0xFF1976D2); // bleu soutenu en mode clair
    // Couleur pour le mois et les chevrons de navigation (en violet)
    final Color headerAccentColor = theme.primaryColor;
    
    // Initialiser si nécessaire
    if (!_focusedDays.containsKey(sessionId)) {
      _focusedDays[sessionId] = DateTime.now();
      _selectedDays[sessionId] = null;
      _sessionEvents[sessionId] = {};
      _isLoadingCalendar[sessionId] = false;
      _loadedMonths[sessionId] = {};
    }

    final focusedDay = _focusedDays[sessionId]!;
    final selectedDay = _selectedDays[sessionId];
    final sessionName = sessions.firstWhere(
      (s) => s['id'] == sessionId,
      orElse: () => {'name': 'Session'},
    )['name'];

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: headerAccentColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Calendrier - $sessionName',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: calendarTitleColor,
                    ) ?? TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: calendarTitleColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Toutes les séances de tous les groupes de cette session',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ) ?? TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            TableCalendar(
              locale: 'fr_FR',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: focusedDay,
              calendarFormat: CalendarFormat.month,
              selectedDayPredicate: (day) =>
                  selectedDay != null && isSameDay(selectedDay, day),
              onDaySelected: (selected, focused) =>
                  _onDaySelected(sessionId, selected, focused),
              onPageChanged: (focused) {
                setState(() {
                  _focusedDays[sessionId] = focused;
                });
                final monthKey = _getMonthKey(focused);
                if (!(_loadedMonths[sessionId]?.contains(monthKey) ?? false)) {
                  _fetchSessionCalendarEvents(
                    sessionId,
                    monthDate: focused,
                    isPriority: true,
                  );
                }
              },
              eventLoader: (day) {
                final events = _getEventsForDay(sessionId, day);
                return events.map((e) => e['title'] as String).toList();
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: todayColor,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: selectedDayColor,
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
                defaultTextStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                weekendTextStyle: TextStyle(
                  color: isDark ? Colors.red[300] : Colors.red[600],
                ),
                outsideTextStyle: TextStyle(
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                markerDecoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 3,
                markersAlignment: Alignment.bottomCenter,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  color: headerAccentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: headerAccentColor,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: headerAccentColor,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                weekendStyle: TextStyle(
                  color: isDark ? Colors.red[300] : Colors.red[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> leaveGroup(int groupId, int sessionId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final response = await authProvider
          .authenticatedRequest(
        'POST',
        '$apiBaseUrl/api/management/exit/special/group',
        body: jsonEncode({
          'sessionId': sessionId.toString(),
          'groupId': groupId.toString(),
        }),
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        if (mounted) {
          SnackBarHelper.showSuccess(context, 'Vous avez quitté le groupe avec succès');
        }
        setState(() {
          final group = groups.firstWhere(
                (g) => g['groupId'] == groupId && g['sessionId'] == sessionId,
            orElse: () => {},
          );
          if (group.isNotEmpty) {
            group['joined'] = false;
            group['members'] = (group['members'] as int) - 1;
            group['pendingJoin'] = false;
            currentGroups[sessionId]?.removeWhere((g) => g['groupId'] == groupId);
          }
        });
        await authProvider.removePendingChange(sessionId, groupId);
        await authProvider.removePendingJoin(sessionId, groupId);
      } else {
        String errorDetail = 'Échec de la sortie du groupe : ${response.statusCode}';
        if (response.body.isNotEmpty) {
          try {
            final errorData = jsonDecode(response.body);
            if (errorData['message'] == 'You have already exited this group') {
              if (mounted) {
                SnackBarHelper.showWarning(context, 'Vous avez déjà quitté ce groupe');
              }
              setState(() {
                final group = groups.firstWhere(
                      (g) => g['groupId'] == groupId && g['sessionId'] == sessionId,
                  orElse: () => {},
                );
                if (group.isNotEmpty) {
                  group['joined'] = false;
                  group['members'] = (group['members'] as int) - 1;
                  group['pendingJoin'] = false;
                  currentGroups[sessionId]?.removeWhere((g) => g['groupId'] == groupId);
                }
              });
              await authProvider.removePendingChange(sessionId, groupId);
              await authProvider.removePendingJoin(sessionId, groupId);
            } else {
              errorDetail += ' - ${errorData['message'] ?? response.body}';
              if (mounted) {
                SnackBarHelper.showError(context, errorDetail);
              }
            }
          } catch (_) {
            errorDetail += ' - ${response.body}';
            if (mounted) {
              SnackBarHelper.showError(context, errorDetail);
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la sortie du groupe : $e');
      }
    }
  }

  void showGroupCalendarDialog(String groupName, int groupId, int sessionId) {
    DateTime currentMonth = DateTime.now();
    List<Map<String, dynamic>> calendarEvents = [];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchGroupCalendarEvents(sessionId, groupId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    backgroundColor: theme.dialogBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
                    ),
                  );
                } else if (snapshot.hasError || !snapshot.hasData) {
                  return Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    backgroundColor: theme.dialogBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Erreur lors du chargement des événements.',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  );
                }

                calendarEvents = snapshot.data!;
                final eventsOnSelectedDate = calendarEvents.where((event) {
                  final eventDate = event['date'] as DateTime;
                  return eventDate.year == selectedDate.year &&
                      eventDate.month == selectedDate.month &&
                      eventDate.day == selectedDate.day;
                }).toList();

                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                  backgroundColor: theme.dialogBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: Icon(Icons.close, color: theme.iconTheme.color),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(height: 8.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left, color: theme.iconTheme.color),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(maxWidth: 40.0, maxHeight: 40.0),
                                onPressed: () {
                                  setState(() {
                                    currentMonth = DateTime(currentMonth.year, currentMonth.month - 1);
                                    selectedDate = DateTime(currentMonth.year, currentMonth.month, 1);
                                  });
                                },
                              ),
                              Expanded(
                                child: Text(
                                  DateFormat.yMMMM('fr_FR').format(currentMonth),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ) ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right, color: theme.iconTheme.color),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(maxWidth: 40.0, maxHeight: 40.0),
                                onPressed: () {
                                  setState(() {
                                    currentMonth = DateTime(currentMonth.year, currentMonth.month + 1);
                                    selectedDate = DateTime(currentMonth.year, currentMonth.month, 1);
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'].map((e) {
                              return Expanded(
                                child: Center(
                                  child: Text(
                                    e,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ) ?? const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10.0),
                          SizedBox(
                            height: 250.0,
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 42,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 4.0,
                                crossAxisSpacing: 4.0,
                                childAspectRatio: 1.0,
                              ),
                              itemBuilder: (context, index) {
                                final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
                                final weekdayOffset = (firstDay.weekday + 6) % 7;
                                final dayOffset = index - weekdayOffset;
                                final currentDay = firstDay.add(Duration(days: dayOffset));

                                bool isInMonth = currentDay.month == currentMonth.month;
                                bool isSelected = selectedDate.year == currentDay.year &&
                                    selectedDate.month == currentDay.month &&
                                    selectedDate.day == currentDay.day;
                                bool isToday = currentDay.year == DateTime.now().year &&
                                    currentDay.month == DateTime.now().month &&
                                    currentDay.day == DateTime.now().day;
                                bool hasEvent = calendarEvents.any((event) {
                                  final eventDate = event['date'] as DateTime;
                                  return eventDate.year == currentDay.year &&
                                      eventDate.month == currentDay.month &&
                                      eventDate.day == currentDay.day;
                                });

                                return GestureDetector(
                                  onTap: isInMonth
                                      ? () {
                                    setState(() {
                                      selectedDate = currentDay;
                                    });
                                  }
                                      : null,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? theme.primaryColor
                                          : isToday
                                          ? Colors.green
                                          : hasEvent
                                          ? theme.primaryColor.withOpacity(0.3)
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${currentDay.day}',
                                      style: TextStyle(
                                        color: isInMonth
                                            ? isSelected
                                            ? Colors.white
                                            : theme.textTheme.bodyMedium?.color ?? Colors.black
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12.0),
                          const Divider(),
                          if (eventsOnSelectedDate.isEmpty)
                            Text(
                              'Aucun événement pour ce jour',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ) ?? const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          if (eventsOnSelectedDate.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: eventsOnSelectedDate.map((event) {
                                final startTime = DateFormat.Hm('fr_FR').format(event['start'] as DateTime);
                                final endTime = DateFormat.Hm('fr_FR').format(event['end'] as DateTime);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event['title'],
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ) ?? const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '$startTime - $endTime',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: Colors.grey[600],
                                        ) ?? TextStyle(color: Colors.grey[600]),
                                      ),
                                      Text(
                                        event['description'],
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 8.0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showGroupDialog({
    required String title,
    required String groupName,
    required int groupId,
    required int sessionId,
    required String endpoint,
    required String successMessage,
    bool isJoin = false,
    bool isSpecial = false,
    bool isRequest = false,
  }) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final prefs = await authProvider.getPendingJoin(sessionId, groupId);
    final isPendingJoin = prefs ?? false;

    if (isPendingJoin) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Une demande est déjà en attente pour ce groupe.');
      }
      return;
    }

    final selectedGroup = groups.firstWhere(
          (g) => g['groupId'] == groupId && g['sessionId'] == sessionId,
      orElse: () => {'name': groupName, 'members': 0, 'capacity': 0},
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          backgroundColor: theme.dialogBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.deepPurple[800],
                    ) ?? TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.deepPurple[800],
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    'Groupe sélectionné : ${selectedGroup['name']}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ) ?? TextStyle(
                      fontSize: 16.0,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: Text(
                          'Annuler',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ) ?? const TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          elevation: 2.0,
                        ),
                        onPressed: () async {
                          try {
                            if (selectedGroup['members'] >= selectedGroup['capacity']) {
                              if (mounted) {
                                SnackBarHelper.showError(context, 'Le groupe est complet.');
                              }
                              return;
                            }

                            final response = await authProvider.authenticatedRequest(
                              'POST',
                              '$apiBaseUrl$endpoint',
                              body: jsonEncode({
                                'sessionId': sessionId.toString(),
                                'groupId': groupId.toString(),
                              }),
                            ).timeout(const Duration(seconds: 30));

                            if (response.statusCode == 200) {
                              Navigator.pop(context);
                              if (mounted) {
                                SnackBarHelper.showSuccess(context, successMessage);
                              }
                              setState(() {
                                final group = groups.firstWhere(
                                      (g) => g['groupId'] == groupId,
                                  orElse: () => {},
                                );
                                if (group.isNotEmpty) {
                                  if (isJoin || isSpecial) {
                                    group['joined'] = true;
                                    group['pendingJoin'] = false;
                                  } else if (isRequest) {
                                    group['pendingJoin'] = true;
                                  }
                                  group['members'] = (group['members'] as int) + 1;
                                  if (!currentGroups.containsKey(sessionId)) {
                                    currentGroups[sessionId] = [];
                                  }
                                  if (!currentGroups[sessionId]!.any((g) => g['groupId'] == groupId)) {
                                    currentGroups[sessionId]!.add({
                                      'sessionId': sessionId,
                                      'groupId': groupId,
                                      'name': selectedGroup['name'],
                                    });
                                  }
                                }
                              });
                              if (isJoin || isSpecial) {
                                await authProvider.removePendingJoin(sessionId, groupId);
                              } else if (isRequest) {
                                await authProvider.setPendingJoin(sessionId, groupId, true);
                              }
                            } else {
                              Navigator.pop(context);
                              String errorDetail = 'Échec de l\'opération : ${response.statusCode}';
                              if (response.body.isNotEmpty) {
                                try {
                                  final errorData = jsonDecode(response.body);
                                  errorDetail += ' - ${errorData['message'] ?? response.body}';
                                } catch (_) {
                                  errorDetail += ' - ${response.body}';
                                }
                              }
                              if (mounted) {
                                SnackBarHelper.showError(context, errorDetail);
                              }
                            }
                          } catch (e) {
                            Navigator.pop(context);
                            if (mounted) {
                              SnackBarHelper.showError(context, 'Erreur : $e');
                            }
                          }
                        },
                        child: Text(
                          'Confirmer',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ) ?? const TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void showJoinGroupDialog(String groupName, int groupId, int sessionId) {
    _showGroupDialog(
      title: 'Rejoindre nouveau groupe',
      groupName: groupName,
      groupId: groupId,
      sessionId: sessionId,
      endpoint: '/api/management/join/new/group',
      successMessage: 'Demande d\'adhésion envoyée avec succès',
      isJoin: true,
    );
  }

  void showJoinSpecialGroupDialog(String groupName, int groupId, int sessionId) {
    _showGroupDialog(
      title: 'Rejoindre groupe spécial',
      groupName: groupName,
      groupId: groupId,
      sessionId: sessionId,
      endpoint: '/api/management/join/special/group',
      successMessage: 'Vous avez rejoint le groupe spécial avec succès',
      isSpecial: true,
    );
  }

  void showRequestSpecialGroupDialog(String groupName, int groupId, int sessionId) {
    _showGroupDialog(
      title: 'Demande pour rejoindre groupe spécial',
      groupName: groupName,
      groupId: groupId,
      sessionId: sessionId,
      endpoint: '/api/management/send/request/special/group',
      successMessage: 'Demande envoyée avec succès, en attente de l\'acceptation de l\'admin',
      isRequest: true,
    );
  }

  void showChangeGroupRequestDialog(String preferredGroupName, int preferredGroupId, int sessionId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final prefs = await authProvider.getPendingChange(sessionId, preferredGroupId);
    final isPendingChange = prefs ?? false;

    if (isPendingChange) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Une demande de changement est déjà en attente.');
      }
      return;
    }

    final selectedGroup = groups.firstWhere(
          (g) => g['groupId'] == preferredGroupId && g['sessionId'] == sessionId,
      orElse: () => {'name': preferredGroupName, 'members': 0, 'capacity': 0},
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
              backgroundColor: theme.dialogBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Changement de groupe',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.deepPurple[800],
                        ) ?? TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.deepPurple[800],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        'Groupe préféré : ${selectedGroup['name']}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ) ?? TextStyle(
                          fontSize: 16.0,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20.0),
                      DropdownButtonFormField<int>(
                        value: (currentGroups[sessionId] ?? []).isNotEmpty ? currentGroups[sessionId]![0]['groupId'] : null,
                        decoration: InputDecoration(
                          labelText: 'Groupe actuel',
                          labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.deepPurple[600]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: theme.primaryColor, width: 2.0),
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        ),
                        items: (currentGroups[sessionId] ?? []).map((group) {
                          return DropdownMenuItem<int>(
                            value: group['groupId'],
                            child: Text(
                              '${group['name']} (${groups.firstWhere((g) => g['groupId'] == group['groupId'], orElse: () => {'members': 0, 'capacity': 0})['members']}/${groups.firstWhere((g) => g['groupId'] == group['groupId'], orElse: () => {'members': 0, 'capacity': 0})['capacity']})',
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (int? newValue) {
                          setState(() {
                            selectedNewGroupId = newValue?.toString();
                          });
                        },
                        dropdownColor: theme.cardColor,
                        icon: Icon(Icons.arrow_drop_down, color: theme.primaryColor),
                        isExpanded: true,
                      ),
                      const SizedBox(height: 20.0),
                      TextField(
                        controller: _reasonController,
                        decoration: InputDecoration(
                          labelText: 'Raison du changement',
                          labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.deepPurple[600]),
                          hintText: 'Entrez la raison de votre demande...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: theme.primaryColor, width: 2.0),
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        ),
                        maxLines: 4,
                        maxLength: 200,
                        style: theme.textTheme.bodyMedium,
                        textAlignVertical: TextAlignVertical.top,
                      ),
                      const SizedBox(height: 24.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              _reasonController.clear();
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: Text(
                              'Annuler',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ) ?? const TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                              elevation: 2.0,
                            ),
                            onPressed: selectedNewGroupId == null || _reasonController.text.trim().isEmpty
                                ? null
                                : () async {
                              try {
                                final currentGroupId = int.tryParse(selectedNewGroupId!);
                                if (currentGroupId == null || currentGroupId <= 0) {
                                  if (mounted) {
                                    SnackBarHelper.showError(context, 'ID du groupe actuel invalide');
                                  }
                                  return;
                                }
                                if (preferredGroupId <= 0) {
                                  if (mounted) {
                                    SnackBarHelper.showError(context, 'ID du groupe préféré invalide');
                                  }
                                  return;
                                }
                                final reason = _reasonController.text.trim();
                                if (reason.length > 200) {
                                  if (mounted) {
                                    SnackBarHelper.showError(context, 'La raison dépasse la limite de 200 caractères');
                                  }
                                  return;
                                }

                                final response = await authProvider.authenticatedRequest(
                                  'POST',
                                  '$apiBaseUrl/api/management/send-request-change',
                                  body: jsonEncode({
                                    'currentGroupId': currentGroupId,
                                    'preferredGroupId': preferredGroupId,
                                    'reasonForChange': reason,
                                    'sessionId': sessionId,
                                  }),
                                ).timeout(const Duration(seconds: 30));

                                if (response.statusCode == 200) {
                                  Navigator.pop(context);
                                  if (mounted) {
                                    SnackBarHelper.showSuccess(context, 'Demande envoyée avec succès');
                                  }
                                  setState(() {
                                    final group = groups.firstWhere(
                                          (g) => g['groupId'] == preferredGroupId,
                                      orElse: () => {},
                                    );
                                    if (group.isNotEmpty) {
                                      group['pendingJoin'] = true;
                                      group['members'] = (group['members'] as int) + 1;
                                      if (!currentGroups.containsKey(sessionId)) {
                                        currentGroups[sessionId] = [];
                                      }
                                      if (!currentGroups[sessionId]!.any((g) => g['groupId'] == preferredGroupId)) {
                                        currentGroups[sessionId]!.add({
                                          'sessionId': sessionId,
                                          'groupId': preferredGroupId,
                                          'name': selectedGroup['name'],
                                        });
                                      }
                                    }
                                    selectedNewGroupId = null;
                                    _reasonController.clear();
                                  });
                                  await authProvider.setPendingChange(sessionId, preferredGroupId, true);
                                } else {
                                  Navigator.pop(context);
                                  String errorDetail = 'Échec de la demande : ${response.statusCode}';
                                  if (response.body.isNotEmpty) {
                                    try {
                                      final errorData = jsonDecode(response.body);
                                      errorDetail += ' - ${errorData['message'] ?? response.body}';
                                    } catch (_) {
                                      errorDetail += ' - ${response.body}';
                                    }
                                  }
                                  if (mounted) {
                                    SnackBarHelper.showError(context, errorDetail);
                                  }
                                }
                              } catch (e) {
                                Navigator.pop(context);
                                if (mounted) {
                                  SnackBarHelper.showError(context, 'Erreur : $e');
                                }
                              }
                            },
                            child: Text(
                              'Envoyer',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ) ?? const TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = theme.brightness == Brightness.dark;

    return LoadingWrapper(
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (BuildContext context) {
              return IconButton(
                icon: Icon(Icons.menu, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
              );
            },
          ),
          title: Text(
            'Groupes de révision',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
            ) ?? const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: false, // Aligne le titre à gauche
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: theme.iconTheme,
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
          bottom: isLoading || sessions.isEmpty
              ? null
              : TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: sessions.map((session) => Tab(text: session['name'])).toList(),
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        drawer: const AppSidebar(),
        body: isLoading
            ? const SizedBox.shrink()
            : sessions.isEmpty
            ? RefreshIndicator(
          onRefresh: refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Center(
                child: Text(
                  'Aucune session disponible',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        )
            : groups.isEmpty
            ? RefreshIndicator(
          onRefresh: refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Center(
                child: Text(
                  'Aucun groupe disponible',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        )
            : errorMessage != null && groups.isNotEmpty
            ? RefreshIndicator(
          onRefresh: refreshData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Center(
                child: Text(
                  errorMessage!,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        )
            : TabBarView(
          controller: _tabController,
          children: sessions.map((session) {
            final sessionGroups = groups.where((group) => group['sessionId'] == session['id']).toList();
            final currentGroupsForSession = currentGroups[session['id']] ?? [];
            final sessionId = session['id'];
            
            developer.log('📊 Affichage sessionId: $sessionId - Nombre de groupes à afficher: ${sessionGroups.length}', name: 'GroupsPage');
            developer.log('📊 État pagination - currentPage: ${_currentPage[sessionId]}, hasMorePages: ${_hasMorePages[sessionId]}, isLoadingMore: ${_isLoadingMore[sessionId]}', name: 'GroupsPage');

            // Initialiser les structures pour cette session si nécessaire
            if (!_focusedDays.containsKey(sessionId)) {
              _focusedDays[sessionId] = DateTime.now();
              _selectedDays[sessionId] = null;
              _sessionEvents[sessionId] = {};
              _isLoadingCalendar[sessionId] = false;
              _loadedMonths[sessionId] = {};
            }
            
            // Initialiser le ScrollController pour cette session si nécessaire
            if (!_scrollControllers.containsKey(sessionId)) {
              _scrollControllers[sessionId] = ScrollController();
              if (!_currentPage.containsKey(sessionId)) {
                _currentPage[sessionId] = 1;
              }
              if (!_hasMorePages.containsKey(sessionId)) {
                _hasMorePages[sessionId] = true;
              }
              if (!_isLoadingMore.containsKey(sessionId)) {
                _isLoadingMore[sessionId] = false;
              }
            }
            
            // Charger les événements du calendrier pour cette session si nécessaire
            // Le premier calendrier est déjà chargé dans _checkAuthAndFetchData
            // Pour les autres sessions, charger en arrière-plan sans loader
            if (!_loadedMonths.containsKey(sessionId) || _loadedMonths[sessionId]!.isEmpty) {
              // Charger le mois actuel sans priorité (en arrière-plan)
              _fetchSessionCalendarEvents(sessionId, isPriority: false);
              // Charger les autres mois en arrière-plan après un court délai
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  _loadOtherMonthsInBackground(sessionId);
                }
              });
            }

            return RefreshIndicator(
              onRefresh: () async {
                // Réinitialiser la pagination lors du refresh
                if (_currentPage.containsKey(sessionId)) {
                  _currentPage[sessionId] = 1;
                  _hasMorePages[sessionId] = true;
                }
                await refreshData();
                // Recharger le calendrier après le refresh
                if (_loadedMonths.containsKey(sessionId)) {
                  _loadedMonths[sessionId]!.clear();
                }
                _fetchSessionCalendarEvents(sessionId, isPriority: true);
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification scrollInfo) {
                  // Détecter quand on atteint la fin du scroll
                  final pixels = scrollInfo.metrics.pixels;
                  final maxScrollExtent = scrollInfo.metrics.maxScrollExtent;
                  final threshold = maxScrollExtent - 200;
                  
                  developer.log('📜 Scroll détecté - pixels: $pixels, maxScrollExtent: $maxScrollExtent, threshold: $threshold', name: 'GroupsPage');
                  developer.log('📜 hasMorePages: ${_hasMorePages[sessionId]}, isLoadingMore: ${_isLoadingMore[sessionId]}', name: 'GroupsPage');
                  
                  if (pixels >= threshold) {
                    developer.log('📜 Seuil atteint! Vérification des conditions...', name: 'GroupsPage');
                    if (_hasMorePages[sessionId] == true && 
                        _isLoadingMore[sessionId] != true) {
                      developer.log('📜 ✅ Conditions remplies, appel de loadMoreGroups pour sessionId: $sessionId', name: 'GroupsPage');
                      loadMoreGroups(sessionId);
                    } else {
                      developer.log('📜 ❌ Conditions non remplies - hasMorePages: ${_hasMorePages[sessionId]}, isLoadingMore: ${_isLoadingMore[sessionId]}', name: 'GroupsPage');
                    }
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scrollControllers[sessionId],
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Calendrier pour cette session
                        _buildSessionCalendar(sessionId),
                        // Liste des groupes
                        if (sessionGroups.isEmpty)
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Center(
                              child: Text(
                                'Aucun groupe disponible',
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                          )
                        else
                          ...sessionGroups.map((group) {
                          final progress = (group['members'] as int) / (group['capacity'] as int);
                          final isGroupFull = (group['members'] as int) >= (group['capacity'] as int);
                          final canLeaveGroup = group['joined'] == true &&
                              group['specialGroupStatus'] == true &&
                              group['type'] != 'Normal';

                          return FutureBuilder<bool?>(
                            future: authProvider.getPendingChange(sessionId, group['groupId']),
                            builder: (context, changeSnapshot) {
                              return FutureBuilder<bool?>(
                                future: authProvider.getPendingJoin(sessionId, group['groupId']),
                                builder: (context, joinSnapshot) {
                                  final isPendingChange = changeSnapshot.data ?? false;
                                  final isPendingJoin = joinSnapshot.data ?? false;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 16.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16.0),
                                    ),
                                    color: theme.cardColor,
                                    elevation: 3,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Stack(
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                group['name'],
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ) ?? const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18.0,
                                                ),
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '${group['teacher']} • ${group['subject']}',
                                                style: theme.textTheme.bodyMedium,
                                              ),
                                              const SizedBox(height: 12.0),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(8.0),
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                  backgroundColor: isDark ? Colors.grey[700] : Colors.deepPurple.shade100,
                                                  color: theme.primaryColor,
                                                  minHeight: 6.0,
                                                ),
                                              ),
                                              const SizedBox(height: 4.0),
                                              Align(
                                                alignment: Alignment.centerRight,
                                                child: Text(
                                                  'Capacité: ${group['capacity']} - ${group['members']} membres',
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                        ),
                                        const SizedBox(height: 12.0),
                                        if (isGroupFull && !group['joined'])
                                          Container(
                                            padding: const EdgeInsets.all(8.0),
                                            margin: const EdgeInsets.only(bottom: 8.0),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8.0),
                                            ),
                                            child: Text(
                                              'Ce groupe est complet',
                                              style: TextStyle(
                                                color: isDark ? Colors.red[300] : Colors.red[800],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                        if (isPendingChange)
                                          Container(
                                            padding: const EdgeInsets.all(8.0),
                                            margin: const EdgeInsets.only(bottom: 8.0),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8.0),
                                            ),
                                            child: Text(
                                              'Tu as déjà demandé de changer de groupe, il faut attendre la validation de ta demande',
                                              style: TextStyle(
                                                color: isDark ? Colors.orange[300] : Colors.orange[800],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                        if (isPendingJoin && !group['joined'] && group['specialGroupStatus'] && group['type'] == 'Request')
                                          Container(
                                            padding: const EdgeInsets.all(8.0),
                                            margin: const EdgeInsets.only(bottom: 8.0),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8.0),
                                            ),
                                            child: Text(
                                              'Une demande pour rejoindre ce groupe spécial est en attente de l\'acceptation de l\'admin',
                                              style: TextStyle(
                                                color: isDark ? Colors.orange[300] : Colors.orange[800],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                        if (isPendingJoin && !group['joined'] && !(group['specialGroupStatus'] && group['type'] == 'Request'))
                                          Container(
                                            padding: const EdgeInsets.all(8.0),
                                            margin: const EdgeInsets.only(bottom: 8.0),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8.0),
                                            ),
                                            child: Text(
                                              'Une demande d\'adhésion pour ce groupe est déjà en attente',
                                              style: TextStyle(
                                                color: isDark ? Colors.orange[300] : Colors.orange[800],
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                        if (!group['specialGroupStatus'] && !group['joined'] && !isGroupFull && group['hasEmptyRelation'] && !isPendingChange && !isPendingJoin)
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: () => showJoinGroupDialog(
                                                group['name'],
                                                group['groupId'],
                                                group['sessionId'],
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isDark ? Colors.deepPurple[700] : Colors.deepPurple.shade50,
                                                foregroundColor: isDark ? Colors.white : Colors.deepPurple,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10.0),
                                                ),
                                              ),
                                              child: Text(
                                                'Rejoindre nouveau groupe',
                                                style: TextStyle(
                                                  fontSize: 16.0,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? Colors.white : Colors.deepPurple[800],
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (!group['specialGroupStatus'] && !group['joined'] && !isGroupFull && group['userOneRelation'] && !isPendingChange && !isPendingJoin)
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: () => showChangeGroupRequestDialog(
                                                group['name'],
                                                group['groupId'],
                                                group['sessionId'],
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: theme.primaryColor,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10.0),
                                                ),
                                              ),
                                              child: Text(
                                                'Demande de changement de groupe',
                                                style: theme.textTheme.labelLarge?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ) ?? const TextStyle(
                                                  fontSize: 16.0,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (group['specialGroupStatus'] && group['hasEmptyRelation'] && group['type'] == 'Direct' && !group['joined'] && !isGroupFull && !isPendingChange && !isPendingJoin)
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: () => showJoinSpecialGroupDialog(
                                                group['name'],
                                                group['groupId'],
                                                group['sessionId'],
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isDark ? Colors.blue[700] : Colors.blue.shade50,
                                                foregroundColor: isDark ? Colors.white : Colors.blue,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10.0),
                                                ),
                                              ),
                                              child: Text(
                                                'Rejoindre groupe spécial',
                                                style: TextStyle(
                                                  fontSize: 16.0,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? Colors.white : Colors.blue[800],
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (group['specialGroupStatus'] && group['hasEmptyRelation'] && group['type'] == 'Request' && !group['joined'] && !isGroupFull && !isPendingChange && !isPendingJoin)
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: () => showRequestSpecialGroupDialog(
                                                group['name'],
                                                group['groupId'],
                                                group['sessionId'],
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10.0),
                                                ),
                                              ),
                                              child: Text(
                                                'Demande pour rejoindre groupe spécial',
                                                style: theme.textTheme.labelLarge?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ) ?? const TextStyle(
                                                  fontSize: 16.0,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (group['joined'])
                                          Text(
                                            'Vous êtes membre',
                                            style: TextStyle(color: Colors.green),
                                          ),
                                        if (canLeaveGroup) const SizedBox(height: 8.0),
                                        if (canLeaveGroup)
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: () => leaveGroup(
                                                group['groupId'],
                                                group['sessionId'],
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isDark ? Colors.red[700] : Colors.red.shade50,
                                                foregroundColor: isDark ? Colors.white : Colors.red,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10.0),
                                                ),
                                              ),
                                              child: Text(
                                                'Quitter ce groupe',
                                                style: TextStyle(
                                                  fontSize: 16.0,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? Colors.white : Colors.red[800],
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (group['specialGroupStatus']) const SizedBox(height: 8.0),
                                        if (group['specialGroupStatus'])
                                          Text(
                                            'Groupe Spécial',
                                            style: TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  }).toList(),
                      // Indicateur de chargement pour la pagination
                      if (_isLoadingMore[sessionId] == true)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}