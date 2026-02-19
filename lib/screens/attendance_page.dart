import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/sidebar.dart';
import '../widgets/notification_icon_button.dart';
import 'dart:async';

class AttendancePage extends StatefulWidget {
  @override
  _AttendancePageState createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin {
  String selectedSession = 'Tous';
  String selectedType = 'En personne';
  bool isLoading = true;
  bool isLoadingSessions = false;
  String? errorMessage;
  List<Map<String, dynamic>> inPersonAttendanceData = [];
  List<Map<String, dynamic>> onlineAttendanceData = [];
  List<Map<String, dynamic>> sessions = [];
  List<String> sessionTabs = ['Tous'];
  final List<String> typeTabs = ['En personne', 'En ligne'];
  TabController? _tabController;
  bool _inPersonDataFetched = false;
  bool _onlineDataFetched = false;

  @override
  void initState() {
    super.initState();
    developer.log('🔵 AttendancePage initState called', name: 'AttendancePage');
    _checkAuthAndFetchData();
  }

  @override
  void dispose() {
    developer.log('🔵 AttendancePage dispose called', name: 'AttendancePage');
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    developer.log('🔵 Checking authentication status', name: 'AttendancePage');

    if (!authProvider.isLoggedIn) {
      developer.log('🔴 User not logged in, redirecting to login', name: 'AttendancePage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez vous connecter pour continuer.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    developer.log('🔵 User authenticated, fetching data', name: 'AttendancePage');
    setState(() {
      _inPersonDataFetched = false;
      _onlineDataFetched = false;
      isLoading = true;
    });
    _fetchSessions();
    fetchInPersonAttendanceData();
    fetchOnlineAttendanceData();
  }

  Future<void> _fetchSessions() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    developer.log('🔵 Fetching sessions', name: 'AttendancePage');

    setState(() {
      isLoadingSessions = true;
    });

    try {
      final response =
      await authProvider.authenticatedRequest('GET', '/api/user/get-session');
      developer.log('🔵 Sessions API response: status ${response.statusCode}', name: 'AttendancePage');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> sessionData = data['sessions'] ?? [];
        setState(() {
          sessions = sessionData
              .where((session) => session != null)
              .map((session) => {
            'id': session['id'] as int,
            'name': session['name'] as String,
            'startDate': session['startDate'] as String?,
            'endDate': session['endDate'] as String?,
            'status': session['status'] as bool?,
            'imgLink': session['imgLink'] as String?,
            'accountId': session['accountId'] as int?,
            'formationId': session['formationId'] as int?,
          })
              .toList();
          sessionTabs = [
            'Tous',
            ...sessions.map((session) => session['name'] as String).toList()
          ];
          isLoadingSessions = false;
          _tabController = TabController(
            length: sessionTabs.length,
            vsync: this,
          );
          developer.log('🟢 Sessions loaded: ${sessions.length}, tabs: ${sessionTabs.length}', name: 'AttendancePage');
        });

        String? newToken =
        response.headers['authorization']?.replaceFirst('Bearer ', '');
        if (newToken != null &&
            newToken.isNotEmpty &&
            newToken != authProvider.currentToken) {
          await authProvider.updateToken(newToken);
          developer.log('🔵 Updated token', name: 'AttendancePage');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() {
          errorMessage = 'Session expirée. Veuillez vous reconnecter.';
          isLoadingSessions = false;
        });
        await authProvider.logout();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session expirée. Veuillez vous reconnecter.')),
        );
        Navigator.pushReplacementNamed(context, '/login');
        developer.log('🔴 Unauthorized, redirecting to login', name: 'AttendancePage');
      } else {
        setState(() {
          errorMessage =
          'Échec du chargement des sessions: ${response.statusCode}';
          isLoadingSessions = false;
        });
        developer.log('🔴 Failed to load sessions: ${response.statusCode}', name: 'AttendancePage');
      }
    } catch (e) {
      developer.log('🔴 Error loading sessions: $e', name: 'AttendancePage', error: e);
      setState(() {
        errorMessage = 'Erreur (sessions): $e';
        isLoadingSessions = false;
      });
    }
  }

  Future<void> fetchInPersonAttendanceData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    developer.log('🔵 Fetching in-person attendance data', name: 'AttendancePage');

    try {
      final response = await authProvider
          .authenticatedRequest('GET', '/api/attendance?type=in-person');

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        if (decodedData['attendanceData'] is List<dynamic>) {
          setState(() {
            inPersonAttendanceData = (decodedData['attendanceData'] as List)
                .where((item) => item != null)
                .map((item) => {
              'groupName': item['groupName'] ?? 'N/A',
              'startTime': item['startTime'] ?? 'N/A',
              'endTime': item['endTime'] ?? 'N/A',
              'status': _convertStatus(item['status']),
              'note': item['note'] ?? '',
              'sessionId': item['sessionId'] ?? -1,
              'sessionName': item['sessionName'] ?? 'N/A',
            })
                .toList();
            _inPersonDataFetched = true;
            if (_inPersonDataFetched && _onlineDataFetched) {
              isLoading = false;
            }
            developer.log('🟢 In-person attendance loaded: ${inPersonAttendanceData.length}', name: 'AttendancePage');
          });
        } else {
          setState(() {
            _inPersonDataFetched = true;
            if (_inPersonDataFetched && _onlineDataFetched) {
              isLoading = false;
            }
          });
        }
      } else {
        setState(() {
          _inPersonDataFetched = true;
          if (_inPersonDataFetched && _onlineDataFetched) {
            isLoading = false;
          }
        });
      }
    } catch (e) {
      developer.log('🔴 Error loading in-person attendance: $e', name: 'AttendancePage', error: e);
      setState(() {
        _inPersonDataFetched = true;
        if (_inPersonDataFetched && _onlineDataFetched) {
          isLoading = false;
        }
      });
    }
  }

  Future<void> fetchOnlineAttendanceData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    developer.log('🔵 Fetching online attendance data', name: 'AttendancePage');

    try {
      final response =
      await authProvider.authenticatedRequest('GET', '/api/attendance-online');

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        if (decodedData['attendanceData'] is List<dynamic>) {
          setState(() {
            onlineAttendanceData = (decodedData['attendanceData'] as List)
                .where((item) => item != null)
                .map((item) => {
              'groupName': item['groupName'] ?? 'N/A',
              'startTime': item['startTime'] ?? 'N/A',
              'endTime': item['endTime'] ?? 'N/A',
              'status': _convertStatus(item['status']),
              'note': item['note'] ?? '',
              'sessionId': item['sessionId'] ?? -1,
              'sessionName': item['sessionName'] ?? 'N/A',
            })
                .toList();
            _onlineDataFetched = true;
            if (_inPersonDataFetched && _onlineDataFetched) {
              isLoading = false;
            }
            developer.log('🟢 Online attendance loaded: ${onlineAttendanceData.length}', name: 'AttendancePage');
          });
        } else {
          setState(() {
            _onlineDataFetched = true;
            if (_inPersonDataFetched && _onlineDataFetched) {
              isLoading = false;
            }
          });
        }
      } else {
        setState(() {
          _onlineDataFetched = true;
          if (_inPersonDataFetched && _onlineDataFetched) {
            isLoading = false;
          }
        });
      }
    } catch (e) {
      developer.log('🔴 Error loading online attendance: $e', name: 'AttendancePage', error: e);
      setState(() {
        _onlineDataFetched = true;
        if (_inPersonDataFetched && _onlineDataFetched) {
          isLoading = false;
        }
      });
    }
  }

  String _convertStatus(dynamic status) {
    if (status is bool) {
      return status ? 'Présent' : 'Absent';
    } else if (status is String) {
      return status == 'true'
          ? 'Présent'
          : status == 'false'
          ? 'Absent'
          : status;
    }
    return 'N/A';
  }

  String _formatDateTime(String? startTime, String? endTime) {
    if (startTime == null || endTime == null) return 'N/A - N/A';

    try {
      DateTime startDateTime;
      DateTime endDateTime;

      try {
        final dateTimeFormat = DateFormat('yy-MM-dd HH:mm');
        startDateTime = dateTimeFormat.parse(startTime);
        endDateTime = dateTimeFormat.parse(endTime);
      } catch (e) {
        startDateTime = DateTime.parse(startTime).toLocal();
        endDateTime = DateTime.parse(endTime).toLocal();
      }

      final dateFormat = DateFormat('yy-MM-dd');
      final timeFormat = DateFormat('HH:mm');

      final startDate = dateFormat.format(startDateTime);
      final startTimeFormatted = timeFormat.format(startDateTime);
      final endTimeFormatted = timeFormat.format(endDateTime);

      return '$startDate $startTimeFormatted - $endTimeFormatted';
    } catch (e) {
      developer.log('🔴 Error formatting date: $e', name: 'AttendancePage', error: e);
      return 'N/A - N/A';
    }
  }

  List<Map<String, dynamic>> get filteredAttendanceData {
    List<Map<String, dynamic>> filtered =
    selectedType == 'En personne' ? inPersonAttendanceData : onlineAttendanceData;
    if (selectedSession != 'Tous') {
      final selectedSessionId = sessions.firstWhere(
            (session) => session['name'] == selectedSession,
        orElse: () => {'id': -1, 'name': 'N/A'},
      )['id'];
      filtered = filtered.where((item) => item['sessionId'] == selectedSessionId).toList();
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    developer.log('🔵 Building AttendancePage, isLoading: $isLoading, isLoadingSessions: $isLoadingSessions', name: 'AttendancePage');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
                developer.log('🔵 Drawer opened', name: 'AttendancePage');
              },
            );
          },
        ),
        title: Text(
          'Journal de présence',
          style: GoogleFonts.poppins(
            color: Colors.white,
          ),
        ),
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
        actions: [
          const NotificationIconButton(),
        ],
        bottom: isLoadingSessions || sessions.isEmpty
            ? null
            : TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: sessionTabs.map((tab) => Tab(text: tab)).toList(),
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(),
          onTap: (index) {
            setState(() {
              selectedSession = sessionTabs[index];
              developer.log('🔵 Selected session: $selectedSession', name: 'AttendancePage');
            });
          },
        ),
      ),
      drawer: AppSidebar(),
      body: isLoading || isLoadingSessions
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
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
          : RefreshIndicator(
        onRefresh: () async {
          developer.log('🔵 RefreshIndicator triggered', name: 'AttendancePage');
          setState(() {
            _inPersonDataFetched = false;
            _onlineDataFetched = false;
            isLoading = true;
          });
          await fetchInPersonAttendanceData();
          await fetchOnlineAttendanceData();
        },
        color: theme.primaryColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: typeTabs.map((tab) {
                    final isSelected = tab == selectedType;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedType = tab;
                          developer.log('🔵 Selected type: $selectedType', name: 'AttendancePage');
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                            color: isSelected ? (isDark ? const Color(0xFF472072) : theme.primaryColor) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tab,
                          style: GoogleFonts.poppins(
                            color: isSelected
                                ? Colors.white
                                : theme.textTheme.bodyMedium?.color ?? Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: filteredAttendanceData.isEmpty
                    ? Center(
                  child: Text(
                    'Aucune présence disponible',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFamily: GoogleFonts.poppins().fontFamily,
                      color: theme.textTheme.bodyLarge?.color ?? Colors.grey[600],
                    ) ??
                        TextStyle(
                          fontSize: 16,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: Colors.grey[600],
                        ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: filteredAttendanceData.length,
                  itemBuilder: (context, index) {
                    final item = filteredAttendanceData[index];
                    final isPresent = item['status'] == 'Présent';
                    final statusColor = isPresent ? Colors.green : Colors.red;
                    developer.log('🔵 Building attendance item $index: ${item['groupName']}', name: 'AttendancePage');

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: statusColor.withOpacity(0.15),
                          child: Icon(
                            isPresent ? Icons.check_circle : Icons.cancel,
                            color: statusColor,
                            size: 28,
                          ),
                        ),
                        title: Text(
                          item['groupName'],
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.titleMedium?.color ?? Colors.deepPurple[900],
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.schedule,
                                      size: 16,
                                      color: theme.iconTheme.color ?? Colors.black54),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _formatDateTime(
                                          item['startTime'], item['endTime']),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontFamily: GoogleFonts.poppins().fontFamily,
                                        color: theme.textTheme.bodyMedium?.color ?? Colors.black54,
                                      ) ??
                                          TextStyle(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                            color: Colors.black54,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.circle,
                                      size: 14,
                                      color: statusColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item['status'],
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: statusColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (item['note'] != null &&
                                  item['note'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.sticky_note_2_outlined,
                                        size: 16,
                                        color: theme.iconTheme.color ?? Colors.black54,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          item['note'],
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                            color: theme.textTheme.bodyMedium?.color ?? Colors.black54,
                                          ) ??
                                              TextStyle(
                                                fontFamily: GoogleFonts.poppins().fontFamily,
                                                color: Colors.black54,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}