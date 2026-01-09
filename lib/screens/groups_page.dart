import 'package:flutter/material.dart';
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
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      await fetchSessions();
      await fetchGroups();
      await fetchCurrentGroupForSessions();
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
      await fetchGroups();
      await fetchCurrentGroupForSessions();
    } finally {
      loadingProvider.hideLoading();
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

  Future<void> fetchGroups() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const String groupsEndpoint = '/api/get-group-management';

    try {
      final groupsResponse = await authProvider
          .authenticatedRequest('GET', groupsEndpoint)
          .timeout(const Duration(seconds: 30));

      if (groupsResponse.statusCode == 200) {
        final Map<String, dynamic> groupsData = jsonDecode(groupsResponse.body);
        final List<dynamic> rawGroups = groupsData['groups'] ?? [];
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

        for (var session in sessions) {
          final sessionId = session['id'];
          final calendarEndpoint = '/api/get-calander-group-management/$sessionId';
          final calendarResponse = await authProvider
              .authenticatedRequest('GET', calendarEndpoint)
              .timeout(const Duration(seconds: 30));

          if (calendarResponse.statusCode == 200) {
            final Map<String, dynamic> calendarData = jsonDecode(calendarResponse.body);
            final List<dynamic> calendarEvents = calendarData['calendarEvents'] ?? [];

            for (var group in tempGroups) {
              if (group['sessionId'] == sessionId) {
                final event = calendarEvents.firstWhere(
                      (event) => event['groupId'] == group['groupId'],
                  orElse: () => {},
                );
                if (event.isNotEmpty) {
                  group['teacher'] = event['teacherName'] ?? 'Unknown';
                  group['subject'] = event['subjectName'] ?? 'Unknown';
                }

                if (group['joined'] || !group['pendingJoin']) {
                  await authProvider.removePendingChange(sessionId, group['groupId']);
                  await authProvider.removePendingJoin(sessionId, group['groupId']);
                }
              }
            }
          }
        }

        setState(() {
          groups = tempGroups;
        });
      } else if (groupsResponse.statusCode == 401 || groupsResponse.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pushReplacementNamed(context, '/login');
        }
        await authProvider.logout();
      } else {
        setState(() {
          errorMessage = 'Échec du chargement des groupes : ${groupsResponse.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur lors de la récupération des groupes : $e';
      });
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

            return RefreshIndicator(
              onRefresh: refreshData,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: sessionGroups.isEmpty
                    ? SingleChildScrollView(
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
                )
                    : ListView.builder(
                  itemCount: sessionGroups.length,
                  itemBuilder: (context, index) {
                    final group = sessionGroups[index];
                    final progress = (group['members'] as int) / (group['capacity'] as int);
                    final isGroupFull = (group['members'] as int) >= (group['capacity'] as int);
                    final canLeaveGroup = group['joined'] == true &&
                        group['specialGroupStatus'] == true &&
                        group['type'] != 'Normal';

                    return FutureBuilder<bool?>(
                      future: authProvider.getPendingChange(session['id'], group['groupId']),
                      builder: (context, changeSnapshot) {
                        return FutureBuilder<bool?>(
                          future: authProvider.getPendingJoin(session['id'], group['groupId']),
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
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.calendar_month,
                                          color: isDark ? Colors.white70 : Colors.grey[600],
                                        ),
                                        onPressed: () => showGroupCalendarDialog(
                                          group['name'],
                                          group['groupId'],
                                          group['sessionId'],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}