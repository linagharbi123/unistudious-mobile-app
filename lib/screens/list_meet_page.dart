import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:provider/provider.dart';
import '../widgets/sidebar.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/auth_guard.dart';

class ListMeetPage extends StatefulWidget {
  const ListMeetPage({super.key});

  @override
  _ListMeetPageState createState() => _ListMeetPageState();
}

class _ListMeetPageState extends State<ListMeetPage> {
  final _jitsiMeet = JitsiMeet();

  List<Map<String, dynamic>> meetsData = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchMeetings();
  }

  Future<void> fetchMeetings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    developer.log('AuthProvider isLoggedIn: ${authProvider.isLoggedIn}', name: 'ListMeetPage');
    developer.log('AuthProvider currentToken: ${authProvider.currentToken}', name: 'ListMeetPage');

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/list-course-online',
      );

      developer.log('Réponse API (list-course-online): ${response.statusCode} - ${response.body}', name: 'ListMeetPage');

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        if (decodedData['meetsData'] is List<dynamic>) {
          setState(() {
            meetsData = (decodedData['meetsData'] as List)
                .where((item) => item != null)
                .map((item) => {
              'id': item['id']?.toString() ?? 'N/A',
              'name': item['name'] ?? 'N/A',
              'sessionId': item['sessionId']?.toString() ?? 'N/A',
              'sessionName': item['sessionName'] ?? 'N/A',
              'groupId': item['groupId']?.toString() ?? 'N/A',
              'groupName': item['groupName'] ?? 'N/A',
              'meetingId': item['meetingId'] ?? 'N/A',
              'roomName': item['roomName'] ?? 'N/A',
              'meetingUrl': item['meetingUrl'] ?? 'N/A',
              'startDate': item['startDate'] ?? 'N/A',
              'endDate': item['endDate'] ?? 'N/A',
              'speakerId': item['speakerId']?.toString() ?? 'N/A',
              'speakerName': item['speakerName'] ?? 'N/A',
            })
                .toList();
            isLoading = false;
            errorMessage = null; // Reset error message on successful fetch
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
      developer.log('Erreur de chargement : $e', name: 'ListMeetPage');

      if (e.toString().contains('Session expired')) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        return;
      }

      setState(() {
        errorMessage = 'Erreur : $e';
        isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> startMeeting(String id) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String apiUrl = 'https://www.unistudious.com';

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/start-course-online/$id',
      );

      developer.log('Réponse API (start-course-online): ${response.statusCode} - ${response.body}', name: 'ListMeetPage');

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        if (decodedData['meetData'] != null && decodedData['token'] != null && decodedData['meetData']['roomName'] != null) {
          return {
            'token': decodedData['token'],
            'roomName': decodedData['meetData']['roomName'],
            'meetingUrl': decodedData['meetData']['meetingUrl'],
          };
        } else {
          throw Exception('Données de réunion incomplètes dans la réponse');
        }
      } else {
        setState(() {
          errorMessage = 'Échec du démarrage de la réunion : ${response.statusCode}';
        });
        return null;
      }
    } catch (e) {
      developer.log('Erreur lors du démarrage de la réunion : $e', name: 'ListMeetPage');
      setState(() {
        errorMessage = 'Erreur : $e';
      });
      return null;
    }
  }

  Future<bool> updateAttendance(String jwt, String roomName) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String apiUrl = 'https://www.unistudious.com';

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/update-attendance-course-online',
        body: jsonEncode({
          'jwt': jwt,
          'roomName': roomName,
        }),
      );

      developer.log('Réponse API (update-attendance-course-online): ${response.statusCode} - ${response.body}', name: 'ListMeetPage');

      if (response.statusCode == 200) {
        developer.log('Mise à jour de l\'assiduité réussie pour roomName: $roomName', name: 'ListMeetPage');
        return true;
      } else {
        setState(() {
          errorMessage = 'Échec de la mise à jour de l\'assiduité : ${response.statusCode}';
        });
        developer.log('Échec de la mise à jour de l\'assiduité : ${response.statusCode}', name: 'ListMeetPage');
        return false;
      }
    } catch (e) {
      developer.log('Erreur lors de la mise à jour de l\'assiduité : $e', name: 'ListMeetPage');
      setState(() {
        errorMessage = 'Erreur lors de la mise à jour de l\'assiduité : $e';
      });
      return false;
    }
  }

  Future<void> _launchJitsiMeeting(String id) async {
    final meetingData = await startMeeting(id);

    if (meetingData != null) {
      final String roomName = meetingData['roomName'];
      final String? jwt = meetingData['token'];
      final String domain = 'https://meet.unistudious.com';

      if (jwt != null) {
        final success = await updateAttendance(jwt, roomName);
        if (!success) {
          developer.log('Échec de la mise à jour de l\'assiduité avant de rejoindre la réunion', name: 'ListMeetPage');
        }
      } else {
        setState(() {
          errorMessage = 'JWT manquant pour la mise à jour de l\'assiduité.';
        });
        developer.log('JWT manquant pour la mise à jour de l\'assiduité', name: 'ListMeetPage');
      }

      final options = JitsiMeetConferenceOptions(
        serverURL: domain,
        room: roomName,
        token: jwt,
        configOverrides: {
          "startWithAudioMuted": false,
          "startWithVideoMuted": false,
        },
        featureFlags: {
          "welcomepage.enabled": false,
          "chat.enabled": true,
          "invite.enabled": false,
          "live-streaming.enabled": false,
          "recording.enabled": false,
          "add-people.enabled": false,
          "kick-out.enabled": false,
          "raise-hand.enabled": true,
          "tile-view.enabled": true,
          "video-share.enabled": false,
          "settings.enabled": false,
        },
        userInfo: JitsiMeetUserInfo(
          displayName: "Utilisateur",
          email: "utilisateur@example.com",
        ),
      );

      await _jitsiMeet.join(options);
    } else {
      setState(() {
        errorMessage = 'Impossible de récupérer les données de réunion.';
      });
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      // Format attendu: "26-01-05 14:57:30" (YY-MM-DD HH:mm:ss)
      // Convertir en format ISO: "2026-01-05 14:57:30"
      String normalizedDate = dateTime;
      
      // Extraire l'année à 2 chiffres et la convertir en 4 chiffres
      final yearMatch = RegExp(r'^(\d{2})-').firstMatch(dateTime);
      if (yearMatch != null) {
        final year2Digits = int.parse(yearMatch.group(1)!);
        // Si l'année est >= 50, c'est 19XX, sinon c'est 20XX
        final year4Digits = year2Digits >= 50 ? 1900 + year2Digits : 2000 + year2Digits;
        normalizedDate = dateTime.replaceFirst(RegExp(r'^\d{2}-'), '${year4Digits}-');
      }
      
      final parsedDate = DateTime.parse(normalizedDate);
      return '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year} ${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      developer.log('Erreur de formatage de la date : $dateTime, Erreur : $e', name: 'DateFormat');
      return dateTime;
    }
  }

  String _calculateDuration(String startDate, String endDate) {
    try {
      // Normaliser les dates (convertir YY en YYYY)
      String normalizeDate(String date) {
        final yearMatch = RegExp(r'^(\d{2})-').firstMatch(date);
        if (yearMatch != null) {
          final year2Digits = int.parse(yearMatch.group(1)!);
          final year4Digits = year2Digits >= 50 ? 1900 + year2Digits : 2000 + year2Digits;
          return date.replaceFirst(RegExp(r'^\d{2}-'), '${year4Digits}-');
        }
        return date;
      }
      
      final start = DateTime.parse(normalizeDate(startDate));
      final end = DateTime.parse(normalizeDate(endDate));
      final duration = end.difference(start);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } catch (e) {
      developer.log('Erreur de calcul de la durée : Start=$startDate, End=$endDate, Erreur : $e', name: 'Duration');
      return 'N/A';
    }
  }

  Map<String, dynamic> _getButtonState(String startDate, String endDate) {
    try {
      // Normaliser les dates (convertir YY en YYYY)
      String normalizeDate(String date) {
        final yearMatch = RegExp(r'^(\d{2})-').firstMatch(date);
        if (yearMatch != null) {
          final year2Digits = int.parse(yearMatch.group(1)!);
          final year4Digits = year2Digits >= 50 ? 1900 + year2Digits : 2000 + year2Digits;
          return date.replaceFirst(RegExp(r'^\d{2}-'), '${year4Digits}-');
        }
        return date;
      }
      
      final now = DateTime.now().toUtc();
      final start = DateTime.parse(normalizeDate(startDate));
      final end = DateTime.parse(normalizeDate(endDate));

      developer.log('Dates - Start: $start, End: $end, Now: $now', name: 'ButtonState');

      if (now.isBefore(start)) {
        return {
          'text': 'Séance pas encore commencée',
          'isEnabled': false,
          'color': Colors.purple[600]!,
        };
      } else if (now.isAfter(start) && now.isBefore(end)) {
        return {
          'text': 'Cliquer pour rejoindre',
          'isEnabled': true,
          'color': Colors.green[600]!,
        };
      } else {
        return {
          'text': 'Séance terminée',
          'isEnabled': false,
          'color': Colors.red[600]!,
        };
      }
    } catch (e) {
      developer.log('Erreur dans _getButtonState : Start=$startDate, End=$endDate, Erreur : $e', name: 'ButtonState');
      return {
        'text': 'Erreur de date',
        'isEnabled': false,
        'color': Colors.red[600]!,
      };
    }
  }

  Widget _buildMeetingsList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: meetsData.length,
      itemBuilder: (context, index) {
        final meeting = meetsData[index];
        final buttonState = _getButtonState(meeting['startDate'], meeting['endDate']);
        return Card(
          color: theme.cardColor,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/meeting_image.png',
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_today, color: theme.iconTheme.color, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              _formatDateTime(meeting['startDate']),
                              style: GoogleFonts.poppins(
                                color: theme.textTheme.bodyMedium?.color,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.access_time, color: theme.iconTheme.color, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              _calculateDuration(meeting['startDate'], meeting['endDate']),
                              style: GoogleFonts.poppins(
                                color: theme.textTheme.bodyMedium?.color,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      meeting['groupName'],
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.deepPurple[900],
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Heure de début :',
                          style: GoogleFonts.poppins(
                            color: theme.textTheme.bodyMedium?.color,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatDateTime(meeting['startDate']).split(' ')[1],
                          style: GoogleFonts.poppins(
                            color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Heure de fin : ',
                          style: GoogleFonts.poppins(
                            color: theme.textTheme.bodyMedium?.color,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatDateTime(meeting['endDate']).split(' ')[1],
                          style: GoogleFonts.poppins(
                            color: isDark ? Colors.pink[300] : Colors.pink,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: meeting['id'] != 'N/A' && buttonState['isEnabled']
                            ? () => _launchJitsiMeeting(meeting['id'])
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonState['color'],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          buttonState['text'],
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Divider(color: isDark ? Colors.white24 : Colors.black26),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: isDark ? Colors.grey[700] : Colors.grey,
                          child: Icon(Icons.person, color: theme.iconTheme.color),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Intervenant :',
                              style: GoogleFonts.poppins(
                                color: theme.textTheme.bodyMedium?.color,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              meeting['speakerName'],
                              style: GoogleFonts.poppins(
                                color: theme.textTheme.bodyLarge?.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AuthGuard(
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
            'Cours en ligne',
            style: GoogleFonts.poppins(
              fontSize: 20,
              color: Colors.white,
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
          iconTheme: theme.iconTheme,
        ),
        drawer: const AppSidebar(),
        body: RefreshIndicator(
          onRefresh: fetchMeetings,
          child: isLoading
              ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
              : errorMessage != null
              ? Center(
            child: Text(
              errorMessage!,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.red[400] : Colors.red[700],
                fontSize: 16,
              ),
            ),
          )
              : meetsData.isEmpty
              ? Center(
            child: Text(
              'Aucune réunion disponible',
              style: GoogleFonts.poppins(
                color: theme.textTheme.bodyMedium?.color,
                fontSize: 16,
              ),
            ),
          )
              : _buildMeetingsList(),
        ),
      ),
    );
  }
}