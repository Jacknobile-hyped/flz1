import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'package:video_player/video_player.dart';
import '../providers/theme_provider.dart';
import '../services/youtube_service.dart';
import '../services/twitter_service.dart';
import '../services/facebook_service.dart';
import '../services/instagram_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'scheduled_post_details_page.dart';
import '../services/scheduled_post_service.dart';
import './settings_page.dart';
import './profile_page.dart';
import './about_page.dart';
import './calendar_view_page.dart';
import 'package:table_calendar/table_calendar.dart';
import './monthly_detail_page.dart';
import './upload_video_page.dart';
import './video_details_page.dart';

// Sort mode enum defined at top level
enum SortMode { upcoming, recent }

// View mode enum for the bottom navigation
enum ViewMode { weekView, monthView, quickView }

class ScheduledPostsPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  
  const ScheduledPostsPage({super.key, this.arguments});

  @override
  State<ScheduledPostsPage> createState() => ScheduledPostsPageState();
}

class ScheduledPostsPageState extends State<ScheduledPostsPage> with SingleTickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final ScheduledPostService _scheduledPostService = ScheduledPostService();
  final TextEditingController _searchController = TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  List<Map<String, dynamic>> _scheduledPosts = [];
  List<Map<String, dynamic>> _publishedVideos = []; // Aggiungo lista per video pubblicati
  bool _isLoading = true;
  bool _showInfo = false;
  String _searchQuery = '';
  
  // Sort mode state variable for quick view
  SortMode _currentSortMode = SortMode.upcoming;
  
  // Use TabController instead of enum for view mode
  late TabController _tabController;
  
  // ScrollController per la vista orizzontale degli orari
  final ScrollController horizontalScrollController = ScrollController();
  
  // Calendar related variables - properly initialized with defaults
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  int _selectedMonthIndex = DateTime.now().month - 1;
  int _selectedYear = DateTime.now().year;
  
  // Variabili per gestire la navigazione alla data specifica
  DateTime? _targetDate;
  bool _shouldScrollToTime = false;
  int? _highlightedHour; // Per evidenziare l'ora target
  bool _hasScrolledToCurrentHour = false; // Flag per tracciare se abbiamo già fatto lo scroll
  bool _isPageActive = false; // Flag per tracciare se la pagina è attiva

  @override
  void initState() {
    super.initState();
    
    // Inizializza la pagina come attiva per il primo caricamento
    _isPageActive = true;
    
    _loadScheduledPosts();
    _loadPublishedVideos(); // Aggiungo caricamento video pubblicati
    _scheduledPostService.startCheckingScheduledPosts();
    
    // Initialize tab controller with 3 tabs (week, month, quick view)
    _tabController = TabController(length: 3, vsync: this);
    
    // Listen to tab changes to update UI accordingly
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        
        // Quando la scheda Week View diventa attiva, scorriamo alla fascia oraria corretta
        if (_tabController.index == 0) {
          // Reset del flag quando si torna alla sezione Week
          _hasScrolledToCurrentHour = false;
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Aspetta un po' per assicurarsi che la UI sia completamente renderizzata
            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted && _isPageActive && _tabController.index == 0 && !_hasScrolledToCurrentHour) {
                if (_shouldScrollToTime && _targetDate != null) {
                  _scrollToTargetTime();
                } else {
                  _scrollToCurrentHour();
                }
                _hasScrolledToCurrentHour = true;
              }
            });
          });
        }
      }
    });
    
    // Refresh posts list every 60 seconds to keep the UI updated
    // Use a more elegant approach to prevent visual reload
    Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted) {
        _silentlyRefreshPosts();
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scheduledPostService.stopCheckingScheduledPosts();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Gestisci gli argomenti passati tramite route solo una volta
    if (_targetDate == null) {
      _handleRouteArguments();
    }
    
    _loadScheduledPosts();
    _loadPublishedVideos(); // Aggiungo caricamento video pubblicati
    
    // Se siamo nella tab Week View e non abbiamo ancora fatto lo scroll, facciamolo
    if (_tabController.index == 0 && !_isLoading && !_hasScrolledToCurrentHour && _isPageActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(Duration(milliseconds: 800), () {
          if (mounted && _isPageActive && _tabController.index == 0 && !_hasScrolledToCurrentHour) {
            if (_shouldScrollToTime && _targetDate != null) {
              _scrollToTargetTime();
            } else {
              _scrollToCurrentHour();
            }
            _hasScrolledToCurrentHour = true;
          }
        });
      });
    }
  }

  // Metodo pubblico per attivare lo scorrimento automatico quando la pagina diventa visibile
  void activateAutoScroll() {
    // Marca la pagina come attiva
    _isPageActive = true;
    
    // Reset del flag per permettere lo scroll automatico
    _hasScrolledToCurrentHour = false;
    
    // Assicurati che la tab Week View sia attiva
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
    
    // Aspetta che la UI sia completamente renderizzata e poi fai lo scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && _isPageActive && _tabController.index == 0 && !_hasScrolledToCurrentHour) {
          if (_shouldScrollToTime && _targetDate != null) {
            _scrollToTargetTime();
          } else {
            _scrollToCurrentHour();
          }
          _hasScrolledToCurrentHour = true;
        }
      });
    });
  }

  // Metodo pubblico per disattivare la pagina quando non è più visibile
  void deactivatePage() {
    _isPageActive = false;
  }

  Future<void> _loadScheduledPosts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final snapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('scheduled_posts')
            .get();

        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          final posts = data.entries.map((entry) {
            final post = entry.value as Map<dynamic, dynamic>;
            
            // Preserva la struttura originale del database
            return {
              'id': entry.key.toString(),
              'scheduledTime': post['scheduled_time'] as int?,
              'scheduled_time': post['scheduled_time'] as int?, // Aggiungo per compatibilità con sezione upcoming
              'description': post['text']?.toString() ?? '', // Campo corretto: 'text'
              'title': post['title']?.toString() ?? '',
              'thumbnail_path': post['thumbnail_path']?.toString() ?? '', // Campo locale se disponibile
              'thumbnail_url': post['thumbnail_url']?.toString() ?? '', // Campo principale per thumbnail da Firebase
              'thumbnail_cloudflare_url': post['thumbnail_cloudflare_url']?.toString() ?? '', // Campo alternativo per thumbnail
              'video_path': post['media_url']?.toString() ?? '', // Campo corretto: 'media_url'
              'accounts': post['accounts'] as Map<dynamic, dynamic>?, // Preserva la struttura accounts originale
              'status': 'scheduled',
              'timestamp': post['created_at'] ?? DateTime.now().millisecondsSinceEpoch, // Campo corretto: 'created_at'
              'media_id': post['worker_id']?.toString() ?? '', // Campo corretto: 'worker_id'
              'tweet_id': post['worker_id']?.toString() ?? '', // Usa worker_id anche per tweet_id
              'platform': post['platform']?.toString() ?? '', // Campo corretto: 'platform'
              'account_id': post['account_id']?.toString() ?? '', // Campo corretto: 'account_id'
              'media_type': post['media_type']?.toString() ?? 'text', // Campo corretto: 'media_type'
              'is_image': post['is_image'] == true, // Campo corretto: 'is_image'
              'youtube_video_id': post['youtube_video_id']?.toString() ?? '', // Per YouTube
              'is_multi_platform': post['is_multi_platform'] == true, // Campo per identificare post multi-piattaforma
              'platforms_count': post['platforms_count'] as int?, // Numero di piattaforme
              'video_duration_minutes': post['video_duration_minutes'] as int?,
              'video_duration_remaining_seconds': post['video_duration_remaining_seconds'] as int?,
              'video_duration_seconds': post['video_duration_seconds'] as int?,
              // Nuovo: includi anche media_urls, preservando la struttura originale (Map con indici numerici)
              'media_urls': post['media_urls'] is Map ? post['media_urls'] as Map<dynamic, dynamic>? : post['media_urls'],
              'cloudflare_urls': post['cloudflare_urls'] is Map ? post['cloudflare_urls'] as Map<dynamic, dynamic>? : post['cloudflare_urls'], // Aggiunto per il controllo del carosello
            };
          })
          .where((post) => post != null && post['scheduledTime'] != null)
          .cast<Map<String, dynamic>>()
          .toList();

          setState(() {
            _scheduledPosts = posts;
            // Apply the current sort mode
            _sortScheduledPosts();
            // Group events by day for calendar view
            _events = _groupEventsByDay(_scheduledPosts);
          });
          
          // Se siamo nella tab Week View, facciamo lo scroll automatico
          if (_tabController.index == 0 && !_hasScrolledToCurrentHour && _isPageActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(Duration(milliseconds: 600), () {
                if (mounted && _isPageActive && _tabController.index == 0 && !_hasScrolledToCurrentHour) {
                  if (_shouldScrollToTime && _targetDate != null) {
                    _scrollToTargetTime();
                  } else {
                    _scrollToCurrentHour();
                  }
                  _hasScrolledToCurrentHour = true;
                }
              });
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading scheduled posts: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Silently refresh posts without causing visual reload
  Future<void> _silentlyRefreshPosts() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Refresh scheduled posts
        final snapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('scheduled_posts')
            .get();

        if (snapshot.exists && mounted) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          final posts = data.entries.map((entry) {
            final post = entry.value as Map<dynamic, dynamic>;
            
            // Preserva la struttura originale del database
            return {
              'id': entry.key.toString(),
              'scheduledTime': post['scheduled_time'] as int?,
              'scheduled_time': post['scheduled_time'] as int?, // Aggiungo per compatibilità con sezione upcoming
              'description': post['text']?.toString() ?? '', // Campo corretto: 'text'
              'title': post['title']?.toString() ?? '',
              'thumbnail_path': post['thumbnail_path']?.toString() ?? '', // Campo locale se disponibile
              'thumbnail_url': post['thumbnail_url']?.toString() ?? '', // Campo principale per thumbnail da Firebase
              'thumbnail_cloudflare_url': post['thumbnail_cloudflare_url']?.toString() ?? '', // Campo alternativo per thumbnail
              'video_path': post['media_url']?.toString() ?? '', // Campo corretto: 'media_url'
              'accounts': post['accounts'] as Map<dynamic, dynamic>?, // Preserva la struttura accounts originale
              'status': 'scheduled',
              'timestamp': post['created_at'] ?? DateTime.now().millisecondsSinceEpoch, // Campo corretto: 'created_at'
              'media_id': post['worker_id']?.toString() ?? '', // Campo corretto: 'worker_id'
              'tweet_id': post['worker_id']?.toString() ?? '', // Usa worker_id anche per tweet_id
              'platform': post['platform']?.toString() ?? '', // Campo corretto: 'platform'
              'account_id': post['account_id']?.toString() ?? '', // Campo corretto: 'account_id'
              'media_type': post['media_type']?.toString() ?? 'text', // Campo corretto: 'media_type'
              'is_image': post['is_image'] == true, // Campo corretto: 'is_image'
              'youtube_video_id': post['youtube_video_id']?.toString() ?? '', // Per YouTube
              'is_multi_platform': post['is_multi_platform'] == true, // Campo per identificare post multi-piattaforma
              'platforms_count': post['platforms_count'] as int?, // Numero di piattaforme
              'video_duration_minutes': post['video_duration_minutes'] as int?,
              'video_duration_remaining_seconds': post['video_duration_remaining_seconds'] as int?,
              'video_duration_seconds': post['video_duration_seconds'] as int?,
              // Nuovo: includi anche media_urls, preservando la struttura originale (Map con indici numerici)
              'media_urls': post['media_urls'] is Map ? post['media_urls'] as Map<dynamic, dynamic>? : post['media_urls'],
              'cloudflare_urls': post['cloudflare_urls'] is Map ? post['cloudflare_urls'] as Map<dynamic, dynamic>? : post['cloudflare_urls'], // Aggiunto per il controllo del carosello
            };
          })
          .where((post) => post != null && post['scheduledTime'] != null)
          .cast<Map<String, dynamic>>()
          .toList();

          // Update the state without triggering a full UI rebuild
          if (mounted) {
            setState(() {
              _scheduledPosts = posts;
              _sortScheduledPosts();
              _events = _groupEventsByDay(_scheduledPosts);
            });
          }
        }
        
        // Refresh published videos
        await _loadPublishedVideos();
      }
    } catch (e) {
      print('Silent refresh error: $e');
      // Don't show error messages for silent refresh
    }
  }

  // Group events by day for calendar view
  Map<DateTime, List<Map<String, dynamic>>> _groupEventsByDay(List<Map<String, dynamic>> posts) {
    Map<DateTime, List<Map<String, dynamic>>> eventsByDay = {};

    for (final post in posts) {
      final scheduledTime = post['scheduledTime'] as int?;
      if (scheduledTime != null) {
        final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
        final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
        
        if (eventsByDay[dateOnly] == null) {
          eventsByDay[dateOnly] = [];
        }
        eventsByDay[dateOnly]!.add(post);
      }
    }

    return eventsByDay;
  }

  // Get events for a specific day
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    final events = _events[dateOnly] ?? [];
    final now = DateTime.now().millisecondsSinceEpoch;
    return events.where((post) {
      final scheduledTime = post['scheduledTime'] as int?;
      if (scheduledTime == null) return false;
      // Escludi tutti i post schedulati nel passato (inclusi i minuti)
      if (scheduledTime < now) return false;
      return true;
    }).toList();
  }
  
  // Get event counts per month for the year view
  Map<int, int> _getMonthlyPostCounts() {
    Map<int, int> monthCounts = {};
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (int i = 1; i <= 12; i++) {
      monthCounts[i] = 0;
    }
    
    for (var eventDay in _events.keys) {
      if (_events[eventDay] != null) {
        for (var post in _events[eventDay]!) {
          // Prendi la scheduledTime (o scheduled_time/scheduled_at)
          int? scheduledTime = post['scheduledTime'] as int? ?? post['scheduled_time'] as int? ?? post['scheduled_at'] as int?;
          if (scheduledTime != null && scheduledTime > now && eventDay.year == _selectedYear) {
            monthCounts[eventDay.month] = (monthCounts[eventDay.month] ?? 0) + 1;
          }
        }
      }
    }
    
    return monthCounts;
  }

  Future<void> _deleteScheduledPost(String postId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Ottiene i dati del post prima di eliminarlo per verificare se è un video YouTube
        final postSnapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('scheduled_posts')
            .child(postId)
            .get();
            
        if (postSnapshot.exists) {
          final postData = postSnapshot.value as Map<dynamic, dynamic>;
          final String? youtubeVideoId = postData['youtube_video_id'] as String?;
          final String? platform = postData['platform'] as String?;
          final hasYouTube = platform == 'YouTube';
          
          bool hasYouTubeError = false;
          String? youtubeErrorMessage;
          
          // Se è un video YouTube, elimina anche da YouTube
          if (hasYouTube && youtubeVideoId != null) {
            final youtubeService = YouTubeService();
            
            // Mostriamo un messaggio di caricamento
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Eliminazione in corso...'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            
            try {
              final deleted = await youtubeService.deleteYouTubeVideo(youtubeVideoId);
              
              if (!deleted) {
                hasYouTubeError = true;
                youtubeErrorMessage = 'Il post è stato eliminato ma potrebbero esserci problemi con l\'eliminazione su YouTube.';
              }
            } catch (ytError) {
              print('Errore durante l\'eliminazione del video YouTube: $ytError');
              hasYouTubeError = true;
              
              // Verifica se l'errore è dovuto a troppe richieste
              if (ytError.toString().contains('Too many attempts') || 
                  ytError.toString().contains('resource-exhausted')) {
                youtubeErrorMessage = 'Troppe richieste a YouTube. Il post verrà eliminato, ma potrebbe essere necessario eliminare manualmente il video su YouTube.';
              } else {
                youtubeErrorMessage = 'Il post è stato eliminato ma potrebbero esserci problemi con l\'eliminazione su YouTube. Verifica manualmente.';
              }
            }
          }

          // Elimina il post dal database
          await _database
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('scheduled_posts')
              .child(postId)
              .remove();

          setState(() {
            _scheduledPosts.removeWhere((post) => post['id'] == postId);
          });

          if (mounted) {
            if (hasYouTubeError && youtubeErrorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(youtubeErrorMessage),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Post eliminato con successo'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } else {
          // Il post non esiste più
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Il post non esiste più'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Errore durante l\'eliminazione: $e';
        
        // Rendi il messaggio più leggibile
        if (e.toString().contains('Too many attempts')) {
          errorMessage = 'Troppe richieste. Riprova più tardi.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permesso negato. Potresti dover riautenticare il tuo account YouTube.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation(String postId) async {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'Delete Post',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete this scheduled post?',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('Delete'),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteScheduledPost(postId);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlatformIcons(List<String> platforms) {
    final icons = {
      'TikTok': Icons.music_note,
      'YouTube': Icons.play_arrow,
      'Instagram': Icons.camera_alt,
      'Facebook': Icons.facebook,
      'Twitter': Icons.chat_bubble,
      'Snapchat': Icons.photo_camera,
      'LinkedIn': Icons.work,
      'Pinterest': Icons.push_pin,
    };

    final colors = {
      'TikTok': Colors.black87,
      'YouTube': Colors.red,
      'Instagram': Colors.purple,
      'Facebook': Colors.blue,
      'Twitter': Colors.lightBlue,
      'Snapchat': Colors.amber,
      'LinkedIn': Colors.blue.shade800,
      'Pinterest': Colors.red.shade700,
    };

    return Row(
      children: platforms.map((platform) {
        return Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (colors[platform] ?? Theme.of(context).colorScheme.primary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (colors[platform] ?? Theme.of(context).colorScheme.primary).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icons[platform] ?? Icons.public,
            size: 16,
            color: colors[platform] ?? Theme.of(context).colorScheme.primary,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About Scheduled Posts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            'Schedule Content',
            'Plan and schedule your posts in advance for multiple platforms.',
            Icons.schedule,
          ),
          _buildInfoItem(
            'View Upcoming Posts',
            'Sort by publication date to see which posts will be published soon.',
            Icons.timer,
          ),
          _buildInfoItem(
            'View Recent Schedules',
            'Sort by creation date to see which posts you\'ve scheduled recently.',
            Icons.history,
          ),
          _buildInfoItem(
            'Automatic Publishing',
            'Your content will be automatically published at the scheduled time.',
            Icons.auto_awesome,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                      Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
                        ),
                      ),
                    ],
                  ),
    );
  }

  Widget _buildVideoCard(ThemeData theme, Map<String, dynamic> post) {
    // Determina se siamo nella sezione "upcoming" o "recent"
    final isUpcomingSection = _currentSortMode == SortMode.upcoming;
    
    // Determina se è un video pubblicato o un post schedulato
    final isPublishedVideo = post.containsKey('user_id') && post['status'] == 'published';
    
    // Distinzione nuovo/vecchio formato per video pubblicati (solo per sezione recent)
    final videoId = post['id']?.toString();
    final userId = post['user_id']?.toString();
    final isNewFormat = isPublishedVideo && videoId != null && userId != null && videoId.contains(userId);
    
    // DATA: publishedAt/created_at/timestamp
    int? publishedAt = post['published_at'] as int?;
    int timestamp;
    String formattedDate;
    
    if (isUpcomingSection) {
      // Per la sezione "upcoming" (post schedulati), usa la struttura del file 1.json
      final scheduledTime = post['scheduled_time'] as int?;
      timestamp = post['created_at'] as int? ?? post['timestamp'] as int;
      formattedDate = scheduledTime != null
          ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(scheduledTime))
          : 'Date not set';
    } else {
      // Per la sezione "recent" (video pubblicati), usa la logica di history_page.dart
      if (isNewFormat) {
        // SOLO created_at, fallback a timestamp
        int? createdAt;
        if (post.containsKey('created_at')) {
          final val = post['created_at'];
          if (val is int) {
            createdAt = val;
          } else if (val is String) {
            createdAt = int.tryParse(val);
          }
        }
        timestamp = createdAt ?? (post['timestamp'] is int ? post['timestamp'] as int : int.tryParse(post['timestamp'].toString()) ?? 0);
      } else {
        timestamp = (publishedAt ?? (post['timestamp'] is int ? post['timestamp'] as int : int.tryParse(post['timestamp'].toString()) ?? 0));
      }
      
      // STATUS - dichiarato prima del suo utilizzo
      String status = post['status'] as String? ?? 'published';
      if (status == 'scheduled' && publishedAt != null) {
        status = 'published';
      }
      
      // Per i video YouTube schedulati, usa scheduled_time se disponibile
      final scheduledTime = post['scheduled_time'] as int?;
      final accounts = post['accounts'] as Map<dynamic, dynamic>? ?? {};
      final hasYouTube = accounts.containsKey('YouTube');
      
      if (status == 'scheduled' && hasYouTube && scheduledTime != null) {
        timestamp = scheduledTime;
      }
      
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      formattedDate = _formatTimestamp(dateTime);
    }
        
    final description = (post['description'] as String? ?? '').trim();
    final title = post['title'] as String? ?? '';
    
    // THUMBNAIL: Gestione diversa per upcoming vs recent
    String? videoPath;
    String? thumbnailPath;
    String? thumbnailCloudflareUrl;
    List<String> platforms;
    int accountCount;
    String accountText;
    
    if (isUpcomingSection) {
      // Per la sezione "upcoming" (post schedulati), usa la struttura del file 1.json
      videoPath = post['media_url'] as String?;
      thumbnailPath = post['thumbnail_url'] as String?;
      thumbnailCloudflareUrl = post['thumbnail_url'] as String?;
      
      // Gestione platforms per post schedulati - estrai le chiavi da accounts
      platforms = [];
      final accounts = post['accounts'] as Map<dynamic, dynamic>? ?? {};
      if (accounts.isNotEmpty) {
        platforms = accounts.keys.map((e) => e.toString()).toList();
      }
      
      // Conteggio account per post schedulati - conta tutti gli account_display_name
      accountCount = 0;
      if (accounts.isNotEmpty) {
        accounts.forEach((platform, platformData) {
          if (platformData is Map) {
            // Se è un oggetto con account_display_name, conta 1
            if (platformData.containsKey('account_display_name')) {
              accountCount += 1;
            } else {
              // Se è un oggetto con più account, conta le chiavi
              accountCount += platformData.length;
            }
          } else if (platformData is List) {
            accountCount += platformData.length;
          } else if (platformData != null) {
            accountCount += 1;
          }
        });
      }
      
      accountText = accountCount > 0 
          ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
          : 'No accounts';
    } else {
      // Per la sezione "recent" (video pubblicati), usa la logica di history_page.dart
      videoPath = isNewFormat 
          ? post['media_url'] as String?
          : post['video_path'] as String?;
      thumbnailPath = isNewFormat
          ? post['thumbnail_url'] as String?
          : post['thumbnail_path'] as String?;
      thumbnailCloudflareUrl = isNewFormat
          ? post['thumbnail_url'] as String?
          : post['thumbnail_cloudflare_url'] as String?;
      
      // SOCIAL MEDIA: platforms (copiato da history_page.dart)
      if (isNewFormat && post['accounts'] is Map) {
        platforms = (post['accounts'] as Map).keys.map((e) => e.toString()).toList();
      } else {
        platforms = List<String>.from(post['platforms'] ?? []);
      }
      
      // NUMERO ACCOUNT: conta tutti gli account (copiato da history_page.dart)
      accountCount = _countTotalAccounts(post, isNewFormat);
      
      accountText = accountCount > 0 
          ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
          : 'No accounts';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2, // Aumentata l'elevazione della card
      color: theme.brightness == Brightness.dark ? Colors.grey[850] : Colors.white,
      child: InkWell(
        onTap: () {
          // Navigazione diversa per upcoming vs recent
          if (isUpcomingSection) {
            // Per la sezione "upcoming" (post schedulati), usa ScheduledPostDetailsPage
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ScheduledPostDetailsPage(
                  post: post,
                ),
              ),
            );
          } else {
            // Per la sezione "recent" (video pubblicati), usa VideoDetailsPage
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoDetailsPage(video: post),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Thumbnail with improved styling
                    Container(
                      decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 150, // Aumentata larghezza
                    height: 110, // Aumentata altezza ulteriormente
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (videoPath?.isNotEmpty == true || thumbnailPath?.isNotEmpty == true)
                          VideoPreviewWidget(
                            videoPath: videoPath,
                            thumbnailPath: thumbnailPath,
                            thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                            width: 150,
                            height: 110,
                            isImage: isUpcomingSection ? post['media_type'] == 'image' : post['is_image'] == true,
                            videoId: isUpcomingSection ? post['unique_post_id'] as String? : post['id'] as String?,
                            userId: post['user_id'] as String?,
                            status: post['status'] as String? ?? 'published',
                            isNewFormat: isUpcomingSection ? false : isNewFormat, // Solo per recent
                          )
                        else
                          Container(
                            color: Colors.grey[200],
                      child: Center(
                        child: Icon(
                                post['is_image'] == true ? Icons.image : Icons.video_library,
                                size: 28,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        // Duration indicator - use static duration display
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: _buildStaticDurationBadge(post),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Video details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                      children: [
                    // Platform logos row
                    if (platforms.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 210, // Adjust for thumbnail and padding
                        ),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark ? Colors.transparent : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                          ),
                      ],
                    ),
                          child: Wrap(
                            spacing: 8, // Slightly reduce spacing
                            runSpacing: 6, // Vertical spacing between rows
                            alignment: WrapAlignment.start,
                            children: [
                              // Limit to maximum 5 platforms (4 icons + "+X" indicator)
                              if (platforms.length <= 5)
                                ...platforms.map((platform) => _buildPlatformLogo(platform.toString()))
                              else
                                ...[
                                  ...platforms.take(4).map((platform) => _buildPlatformLogo(platform.toString())),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: theme.colorScheme.primary.withOpacity(0.1),
                                          blurRadius: 2,
                                          offset: Offset(0, 1),
                  ),
                ],
              ),
                                    child: Text(
                                      '+${platforms.length - 4}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                            ],
                          ),
                        ),
                      ),
                    
                    // Spazio maggiore prima delle informazioni di account e data
                    const SizedBox(height: 15),
                    
                                        // Account info senza status badge
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            accountText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    
                    // Timestamp con status badge allineato a destra
                    Row(
                      children: [
                        // Timestamp a sinistra
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isUpcomingSection ? Icons.schedule : Icons.access_time,
                                  size: 14,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Status badge allineato a destra nella stessa riga della data
                        _buildScheduledStatusChip(post),
                      ],
                    ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  // Helper method to build platform logos from assets
  Widget _buildPlatformLogo(String platform) {
    String logoPath;
    double size = 24; // Slightly smaller size
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'tiktok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
      case 'instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      default:
        // Fallback to icon-based display if logo not available
        return _buildPlatformIcon(platform);
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        logoPath,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to icon if image fails to load
          print('Error loading platform logo: $error');
          return _buildPlatformIcon(platform);
        },
      ),
    );
  }
  
  // Helper method to build platform icon as fallback
  Widget _buildPlatformIcon(String platform) {
    IconData iconData;
    Color iconColor;
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        iconData = Icons.play_circle_filled;
        iconColor = Colors.red;
        break;
      case 'tiktok':
        iconData = Icons.music_note;
        iconColor = Colors.black87;
        break;
      case 'instagram':
        iconData = Icons.camera_alt;
        iconColor = Colors.purple;
        break;
      case 'facebook':
        iconData = Icons.facebook;
        iconColor = Colors.blue;
        break;
      case 'twitter':
        iconData = Icons.chat_bubble;
        iconColor = Colors.lightBlue;
        break;
      case 'threads':
        iconData = Icons.tag;
        iconColor = Colors.black87;
        break;
      case 'snapchat':
        iconData = Icons.photo_camera;
        iconColor = Colors.amber;
        break;
      case 'linkedin':
        iconData = Icons.work;
        iconColor = Colors.blue.shade800;
        break;
      case 'pinterest':
        iconData = Icons.push_pin;
        iconColor = Colors.red.shade700;
        break;
      default:
        iconData = Icons.public;
        iconColor = Colors.grey;
    }
    
    return Container(
      width: 24, // Match the logo size
      height: 24, // Match the logo size
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
        child: Icon(
        iconData,
        size: 14,
        color: iconColor,
      ),
    );
  }
  
  // Helper method to build small platform logos from assets
  Widget _buildPlatformLogoSmall(String platform) {
    String logoPath;
    double size = 16; // Smaller size for the week view cards
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'tiktok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
      case 'instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      default:
        // Fallback to icon-based display if logo not available
        return _buildPlatformIconSmall(platform);
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        logoPath,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to icon if image fails to load
          print('Error loading platform logo: $error');
          return _buildPlatformIconSmall(platform);
        },
      ),
    );
  }
  
  // Helper method to build small platform icon as fallback
  Widget _buildPlatformIconSmall(String platform) {
    IconData iconData;
    Color iconColor;
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        iconData = Icons.play_circle_filled;
        iconColor = Colors.red;
        break;
      case 'tiktok':
        iconData = Icons.music_note;
        iconColor = Colors.black87;
        break;
      case 'instagram':
        iconData = Icons.camera_alt;
        iconColor = Colors.purple;
        break;
      case 'facebook':
        iconData = Icons.facebook;
        iconColor = Colors.blue;
        break;
      case 'twitter':
        iconData = Icons.chat_bubble;
        iconColor = Colors.lightBlue;
        break;
      case 'threads':
        iconData = Icons.tag;
        iconColor = Colors.black87;
        break;
      case 'snapchat':
        iconData = Icons.photo_camera;
        iconColor = Colors.amber;
        break;
      case 'linkedin':
        iconData = Icons.work;
        iconColor = Colors.blue.shade800;
        break;
      case 'pinterest':
        iconData = Icons.push_pin;
        iconColor = Colors.red.shade700;
        break;
      default:
        iconData = Icons.public;
        iconColor = Colors.grey;
    }
    
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        size: 12,
        color: iconColor,
      ),
    );
  }
  
  // Nuovo metodo per mostrare la durata in modo statico
  Widget _buildStaticDurationBadge(Map<String, dynamic> post) {
    // Determina se siamo nella sezione "upcoming" o "recent"
    final isUpcomingSection = _currentSortMode == SortMode.upcoming;
    
    // Controlla se è un carosello (ha cloudflare_urls o media_urls con più di una voce)
    final cloudflareUrls = post['cloudflare_urls'];
    final mediaUrls = post['media_urls'];
    
    // Helper per verificare se una struttura contiene più elementi
    bool _hasMultipleItems(dynamic data) {
      if (data == null) return false;
      if (data is List && data.length > 1) return true;
      if (data is Map) {
        // Conta solo le chiavi che sono numeriche o stringhe numeriche (indici)
        int count = 0;
        for (var key in data.keys) {
          // Accetta chiavi numeriche (int) o stringhe numeriche ("0", "1", "2", ecc.)
          if (key is int || (key is String && int.tryParse(key) != null)) {
            count++;
          }
        }
        return count > 1;
      }
      return false;
    }
    
    // Verifica se è un carosello controllando entrambi i campi
    bool isCarousel = _hasMultipleItems(cloudflareUrls) || _hasMultipleItems(mediaUrls);
    
    // Se è un carosello, mostra "CAROUSEL" (ha priorità su tutto)
    if (isCarousel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'CAROUSEL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    // Se è un'immagine, mostra "IMG"
    if (isUpcomingSection ? post['media_type'] == 'image' : post['is_image'] == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'IMG',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    // Per i video, usa la vera durata dal database se disponibile
    String duration;
    final durationSeconds = post['video_duration_seconds'] as int?;
    final durationMinutes = post['video_duration_minutes'] as int?;
    final durationRemainingSeconds = post['video_duration_remaining_seconds'] as int?;
    if (durationSeconds != null && durationMinutes != null && durationRemainingSeconds != null) {
      duration = '$durationMinutes:${durationRemainingSeconds.toString().padLeft(2, '0')}';
    } else {
      // Fallback: usa una durata basata sull'ID del video (per compatibilità con video esistenti)
      final idString = isUpcomingSection ? (post['unique_post_id'] as String? ?? '') : (post['id'] as String? ?? '');
      final hashCode = idString.hashCode.abs() % 300 + 30; // tra 30 e 329 secondi
      final minutes = hashCode ~/ 60;
      final seconds = hashCode % 60;
      duration = '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        duration,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  // Widget per lo stato "Scheduled" o "Published"
  Widget _buildScheduledStatusChip(Map<String, dynamic> post) {
    // Determina se è un video pubblicato o un post schedulato
    final isPublishedVideo = post.containsKey('user_id') && post['status'] == 'published';
    
    Color backgroundColor;
    IconData icon;
    String label;
    
    if (isPublishedVideo) {
      backgroundColor = const Color(0xFF34C759);
      icon = Icons.check_circle;
      label = 'PUBLISHED';
    } else {
      backgroundColor = const Color(0xFFFF9500); // Arancione per scheduled
      icon = Icons.schedule;
      label = 'SCHEDULED';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 8,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  void _sortScheduledPosts() {
    if (_scheduledPosts.isEmpty) return;
    
    setState(() {
      switch (_currentSortMode) {
        case SortMode.upcoming:
          // Sort by scheduled time (ascending - soonest first)
          _scheduledPosts.sort((a, b) {
            final aTime = a['scheduledTime'] as int;
            final bTime = b['scheduledTime'] as int;
            return aTime.compareTo(bTime);
          });
          break;
          
        case SortMode.recent:
          // Sort by creation timestamp (descending - most recent first)
          _scheduledPosts.sort((a, b) {
            final aTime = a['timestamp'] as int;
            final bTime = b['timestamp'] as int;
            return bTime.compareTo(aTime);
          });
          break;
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredPosts() {
    if (_searchQuery.isEmpty) {
      // Applica filtro per nascondere i post solo YouTube scaduti
      return _scheduledPosts.where((post) {
        final scheduledTime = post['scheduledTime'] as int?;
        final now = DateTime.now().millisecondsSinceEpoch;
        // Controlla se è solo per YouTube
        List<String> platforms = [];
        if (post['accounts'] != null && post['accounts'] is Map) {
          platforms = (post['accounts'] as Map).keys.map((e) => e.toString().toLowerCase()).toList();
        } else if (post['platforms'] != null && post['platforms'] is List) {
          platforms = (post['platforms'] as List).map((e) => e.toString().toLowerCase()).toList();
        } else if (post['platform'] != null) {
          platforms = [post['platform'].toString().toLowerCase()];
        }
        final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
        final isPast = scheduledTime != null && scheduledTime < now;
        // Se è solo YouTube e la data è passata, escludi
        if (isOnlyYouTube && isPast) return false;
        return true;
      }).toList();
    }

    final query = _searchQuery.toLowerCase();
    return _scheduledPosts.where((post) {
      final description = (post['description'] as String? ?? '').toLowerCase();
      final title = (post['title'] as String? ?? '').toLowerCase();
      final platforms = (post['platforms'] as List<dynamic>? ?? [])
          .map((e) => e.toString().toLowerCase())
          .join(' ');
      
      // Add date search
      final scheduledTime = post['scheduledTime'] as int?;
      String formattedDate = '';
      if (scheduledTime != null) {
        final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
        // Format date in multiple ways to make search more flexible
        formattedDate = [
          DateFormat('dd/MM/yyyy').format(dateTime),  // 25/03/2024
          DateFormat('d/M/yyyy').format(dateTime),    // 25/3/2024
          DateFormat('dd/MM').format(dateTime),       // 25/03
          DateFormat('d/M').format(dateTime),         // 25/3
          DateFormat('MMMM').format(dateTime).toLowerCase(), // march
          DateFormat('MMM').format(dateTime).toLowerCase(), // mar
          DateFormat('HH:mm').format(dateTime),       // 14:30
          DateFormat('H:mm').format(dateTime),        // 14:30
          dateTime.day.toString(),                    // 25
          DateFormat('EEEE').format(dateTime).toLowerCase(), // monday
          DateFormat('EEE').format(dateTime).toLowerCase(), // mon
        ].join(' ');
      }

      return description.contains(query) ||
             title.contains(query) ||
             platforms.contains(query) ||
             formattedDate.contains(query);
    }).toList();
  }

  // Update the build method to include the filter button in the header
  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.1),
              ),
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                'assets/app_logo_nosfondo.png',
                width: 36,
                height: 36,
              ),
            ),
          ),
          Row(
            children: [
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF667eea), // Colore iniziale: blu violaceo
                      Color(0xFF764ba2), // Colore finale: viola
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                  ).createShader(bounds);
                },
                child: Text(
                  'Viral',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF667eea), // Colore iniziale: blu violaceo
                      Color(0xFF764ba2), // Colore finale: viola
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                  ).createShader(bounds);
                },
                child: Text(
                  'yst',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.settings_outlined,
                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfilePage(),
                    ),
                  );
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.primaryColor.withOpacity(0.1),
                    // Avoid network image loading error
                    image: _currentUser?.photoURL != null && !_currentUser!.photoURL!.contains('facebook')
                        ? DecorationImage(
                            image: NetworkImage(_currentUser!.photoURL!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _currentUser?.photoURL == null || _currentUser!.photoURL!.contains('facebook')
                      ? Icon(
                          Icons.person,
                          color: theme.primaryColor,
                          size: 20,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build the month view (calendar with post counts)
  Widget _buildMonthView() {
    // Note: The month detail view and expandable events panel functionality 
    // has been moved to the MonthlyDetailPage class

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final monthCounts = _getMonthlyPostCounts();
    final months = [
      'January', 'February', 'March', 'April', 
      'May', 'June', 'July', 'August', 
      'September', 'October', 'November', 'December'
    ];
    
    // Ottieni il mese e l'anno corrente per confrontare
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 0.0), // Ridotto padding superiore
      child: Column(
        children: [
          // Year selector
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              // Effetto vetro semi-trasparente opaco
              color: isDark 
                  ? Colors.white.withOpacity(0.15) 
                  : Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
              // Bordo con effetto vetro più sottile
              border: Border.all(
                color: isDark 
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.4),
                width: 1,
              ),
              // Ombre per effetto profondità e vetro
              boxShadow: [
                BoxShadow(
                  color: isDark 
                      ? Colors.black.withOpacity(0.4)
                      : Colors.black.withOpacity(0.15),
                  blurRadius: isDark ? 25 : 20,
                  spreadRadius: isDark ? 1 : 0,
                  offset: const Offset(0, 10),
                ),
                // Ombra interna per effetto vetro
                BoxShadow(
                  color: isDark 
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.6),
                  blurRadius: 2,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ],
              // Gradiente più sottile per effetto vetro
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                    ? [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.1),
                      ]
                    : [
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.2),
                      ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: () {
                    setState(() {
                      _selectedYear--;
                    });
                  },
                ),
                Text(
                  _selectedYear.toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_ios, size: 16),
                  onPressed: () {
                    setState(() {
                      _selectedYear++;
                    });
                  },
                ),
              ],
            ),
          ),
          
          // Months grid (3 per row)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final postCount = monthCounts[month] ?? 0;
                final isCurrentMonth = DateTime.now().month == month && DateTime.now().year == _selectedYear;
                
                // Verifica se il mese è passato (mese precedente dell'anno corrente o qualsiasi mese di un anno passato)
                final isPastMonth = (_selectedYear < currentYear) || 
                                   (_selectedYear == currentYear && month < currentMonth);
                
                return InkWell(
                  onTap: isPastMonth ? null : () {
                    // Instead of changing view mode, navigate to the new page
                    final focusedMonth = DateTime(_selectedYear, month, 1);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MonthlyDetailPage(
                          focusedMonth: focusedMonth,
                          selectedYear: _selectedYear,
                          events: _events,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: isCurrentMonth 
                          ? LinearGradient(
                              colors: [
                                Color(0xFF667eea).withOpacity(0.2), // Colore iniziale: blu violaceo
                                Color(0xFF764ba2).withOpacity(0.2), // Colore finale: viola
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                            )
                          : null,
                      color: isCurrentMonth 
                          ? null 
                          : isPastMonth
                              ? (isDark ? Colors.grey[850] : Colors.grey[100])
                              : theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCurrentMonth 
                            ? Color(0xFF667eea)
                            : isPastMonth
                                ? (isDark ? Colors.grey[700]! : Colors.grey[300]!)
                                : theme.colorScheme.surfaceVariant,
                        width: isCurrentMonth ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          months[index].substring(0, 3),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPastMonth
                                ? (isDark ? Colors.grey[600] : Colors.grey[400])
                                : isCurrentMonth 
                                    ? Color(0xFF667eea)
                                    : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!isPastMonth || postCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (postCount > 0 && !isPastMonth)
                                  ? Color(0xFF667eea).withOpacity(0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$postCount posts',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isPastMonth
                                    ? (isDark ? Colors.grey[600] : Colors.grey[400])
                                    : postCount > 0
                                        ? Color(0xFF667eea)
                                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                                fontWeight: (postCount > 0 && !isPastMonth) ? FontWeight.bold : FontWeight.normal,
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
        ],
      ),
    );
  }

  // Add a widget to build the week view (similar to CalendarViewPage)
  Widget _buildWeekView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    
    // Generate week days starting from Monday of current week
    List<DateTime> weekDays = [];
    DateTime startOfWeek = _focusedDay.subtract(Duration(days: _focusedDay.weekday - 1));
    for (int i = 0; i < 7; i++) {
      weekDays.add(startOfWeek.add(Duration(days: i)));
    }
    
    // Generate hours for the day view (expanded range from 0:00 to 23:00)
    List<String> hours = [];
    for (int i = 0; i <= 23; i++) {
      hours.add('${i.toString().padLeft(2, '0')}:00');
    }
    
    // Calculate event counts for each day of the week
    Map<DateTime, int> eventCountsByDay = {};
    for (DateTime day in weekDays) {
      final dateOnly = DateTime(day.year, day.month, day.day);
      // Conta solo i video con data schedulata nel futuro (inclusi i minuti)
      eventCountsByDay[dateOnly] = _getEventsForDay(day).length;
    }
    
    // Check if there are any events for the selected day
    final hasEventsForSelectedDay = _getEventsForDay(_selectedDay).isNotEmpty;
    
    return CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        // Compact month selector with week navigation - now as sliver
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            margin: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 12.0),
            decoration: BoxDecoration(
              // Effetto vetro semi-trasparente opaco
              color: isDark 
                  ? Colors.white.withOpacity(0.15) 
                  : Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(24),
              // Bordo con effetto vetro più sottile
              border: Border.all(
                color: isDark 
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.4),
                width: 1,
              ),
              // Ombre per effetto profondità e vetro
              boxShadow: [
                BoxShadow(
                  color: isDark 
                      ? Colors.black.withOpacity(0.4)
                      : Colors.black.withOpacity(0.15),
                  blurRadius: isDark ? 25 : 20,
                  spreadRadius: isDark ? 1 : 0,
                  offset: const Offset(0, 10),
                ),
                // Ombra interna per effetto vetro
                BoxShadow(
                  color: isDark 
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.6),
                  blurRadius: 2,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ],
              // Gradiente più sottile per effetto vetro
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                    ? [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.1),
                      ]
                    : [
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.2),
                      ],
              ),
            ),
            child: Column(
              children: [
                // Month with arrows
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNavigationButton(
                      icon: Icons.chevron_left,
                      onPressed: () {
                        setState(() {
                          _focusedDay = _focusedDay.subtract(const Duration(days: 7));
                        });
                      },
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_focusedDay),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    _buildNavigationButton(
                      icon: Icons.chevron_right,
                      onPressed: () {
                        setState(() {
                          _focusedDay = _focusedDay.add(const Duration(days: 7));
                        });
                      },
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Week day selector with event counts
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(weekDays.length, (index) {
                    final day = weekDays[index];
                    final isSelected = isSameDay(day, _selectedDay);
                    final isToday = isSameDay(day, DateTime.now());
                    final dateOnly = DateTime(day.year, day.month, day.day);
                    final videoCount = eventCountsByDay[dateOnly] ?? 0;
                    
                    // Verifica se è passato
                    final isPast = dateOnly.isBefore(DateTime(now.year, now.month, now.day));
                    // Verifica se è futuro
                    final isFuture = _isDateInFuture(day);
                    // Non selezionabile solo se è passato
                    final isDisabled = isPast;
                    
                    // Day names (M, T, W, etc.) - even shorter
                    String dayName = DateFormat('E').format(day).substring(0, 1);
                    
                    return GestureDetector(
                      onTap: isDisabled ? null : () {
                        setState(() {
                          _selectedDay = day;
                        });
                        
                        // Reset del flag per permettere lo scroll automatico
                        _hasScrolledToCurrentHour = false;
                        
                        // Aspetta che la UI si aggiorni e poi fai lo scroll
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          Future.delayed(Duration(milliseconds: 300), () {
                            if (mounted) {
                              _scrollToCurrentHour();
                            }
                          });
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36, // Slightly wider
                        height: 64, // Much taller to avoid overflow
                        decoration: BoxDecoration(
                          gradient: isSelected 
                              ? LinearGradient(
                                  colors: [
                                    Color(0xFF667eea), // Colore iniziale: blu violaceo
                                    Color(0xFF764ba2), // Colore finale: viola
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                                )
                              : null,
                          color: isSelected 
                              ? null 
                              : isPast
                                  ? (isDark ? Colors.grey[850] : Colors.grey[100])
                                  : theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isSelected && !isDisabled
                              ? [
                                  BoxShadow(
                                    color: Color(0xFF667eea).withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        // Remove the padding to give more space
                        child: Column(
                          // Fixed layout - no longer use mainAxisSize: min or mainAxisAlignment: center
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            SizedBox(height: 2), // Add top spacer
                            // Day letter (M, T, W...)
                            Text(
                              dayName,
                              style: TextStyle(
                                fontSize: 9, 
                                fontWeight: FontWeight.w500,
                                color: isSelected 
                                    ? Colors.white 
                                    : isDisabled
                                        ? (isDark ? Colors.grey[600] : Colors.grey[400])
                                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              ),
                            ),
                            
                            // Day number
                            Text(
                              day.day.toString(),
                              style: TextStyle(
                                fontSize: 13, 
                                fontWeight: FontWeight.bold,
                                color: isSelected 
                                    ? Colors.white 
                                    : isDisabled
                                        ? (isDark ? Colors.grey[600] : Colors.grey[400])
                                        : isToday
                                            ? Color(0xFF667eea)
                                            : theme.colorScheme.onSurface,
                              ),
                            ),
                            
                            // Video count indicator or placeholder
                            Container(
                              width: 14, 
                              height: 14,
                              decoration: videoCount > 0 && !isDisabled
                                ? BoxDecoration(
                                    color: isSelected 
                                        ? Colors.white.withOpacity(0.3) 
                                        : theme.colorScheme.primary.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  )
                                : null,
                              child: videoCount > 0 && !isDisabled
                                ? Center(
                                    child: Text(
                                      videoCount.toString(),
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected 
                                            ? Colors.white 
                                            : theme.colorScheme.primary,
                                      ),
                                    ),
                                  )
                                : null,
                            ),
                            SizedBox(height: 2), // Add bottom spacer
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        
        // Timeline container - now as sliver for better scrolling
        SliverFillRemaining(
          child: Container(
            margin: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey[50],
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Unified scrollable content view with hours headers
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: horizontalScrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hours header row - now pinned at top
                        Container(
                          height: 40,
                          child: _buildHoursHeader(hours),
                        ),
                        
                        // Divider between hours and events
                        Container(
                          width: _calculateTotalContentWidth(hours),
                          height: 1,
                          color: Colors.grey[200],
                        ),
                        
                        // Events area - integrated with the hours and scrollable
                        Expanded(
                          child: SingleChildScrollView(
                            physics: AlwaysScrollableScrollPhysics(),
                            child: Container(
                              height: math.max(MediaQuery.of(context).size.height - 200, 800), // Altezza minima per scroll verticale
                              child: _buildTimelineContent(hours),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  // Build hours header with expanded widths for hours with events
  Widget _buildHoursHeader(List<String> hours) {
    final events = _getEventsForDay(_selectedDay);
    final now = DateTime.now();
    final isToday = isSameDay(_selectedDay, now);
    final theme = Theme.of(context);
    
    // Group events by hour to know which hours have events
    Map<int, List<Map<String, dynamic>>> eventsByHour = {};
    for (var event in events) {
      final scheduledTime = event['scheduledTime'] as int?;
      if (scheduledTime == null) continue;
      
      final eventDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
      final hour = eventDateTime.hour;
      
      if (!eventsByHour.containsKey(hour)) {
        eventsByHour[hour] = [];
      }
      eventsByHour[hour]!.add(event);
    }
    
    // Mostra tutte le 24 ore senza filtrare quelle del passato
    List<int> visibleHours = [];
    for (int i = 0; i < hours.length; i++) {
      final hour = int.parse(hours[i].split(':')[0]);
      visibleHours.add(hour);
    }
    
    return Row(
      children: visibleHours.map((hour) {
        final hourString = hour.toString().padLeft(2, '0') + ':00';
        final hasEvents = eventsByHour.containsKey(hour) && eventsByHour[hour]!.isNotEmpty;
        
        // Verifica se l'ora è nel passato (solo per oggi)
        final isPastHour = isToday && hour < now.hour;
        
        // Width ridotta per ore senza eventi
        final width = hasEvents ? 160.0 : 60.0;
        
        return Container(
          width: width,
          alignment: Alignment.center,
          // Aggiungi evidenziazione se questa è l'ora target
          decoration: _highlightedHour == hour ? BoxDecoration(
            color: Color(0xFF667eea).withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Color(0xFF667eea).withOpacity(0.3),
              width: 1,
            ),
          ) : null,
          child: Text(
            hourString,
            style: TextStyle(
              fontSize: 12,
              color: isPastHour
                  ? Colors.grey[400]  // Colore più chiaro per le ore passate
                  : hasEvents ? theme.colorScheme.onSurface : Colors.grey[600],
              fontWeight: hasEvents ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
  
  // Build the timeline content
  Widget _buildTimelineContent(List<String> hours) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final events = _getEventsForDay(_selectedDay);
    final now = DateTime.now();
    final isToday = isSameDay(_selectedDay, now);
    
    // Group events by hour
    Map<int, List<Map<String, dynamic>>> eventsByHour = {};
    for (var event in events) {
      final scheduledTime = event['scheduledTime'] as int?;
      if (scheduledTime == null) continue;
      
      final eventDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
      final hour = eventDateTime.hour;
      
      if (!eventsByHour.containsKey(hour)) {
        eventsByHour[hour] = [];
      }
      eventsByHour[hour]!.add(event);
    }
    
    // Mostra tutte le ore senza filtrare
    List<int> visibleHours = [];
    for (int i = 0; i < hours.length; i++) {
      final hour = int.parse(hours[i].split(':')[0]);
      visibleHours.add(hour);
    }
    
    // Calculate total width with expanded hours (solo per le ore visibili)
    double totalWidth = 0.0;
    for (int hour in visibleHours) {
      final hasEvents = eventsByHour.containsKey(hour) && eventsByHour[hour]!.isNotEmpty;
      totalWidth += hasEvents ? 160.0 : 60.0;
    }
    
    // Ensure the content covers at least the visible area of the screen
    // This prevents empty space after the 23:00 time slot
    double contentHeight = MediaQuery.of(context).size.height - 300; // Reduced from the screen height to avoid empty space
    
    // Make sure we have enough height for the content
    contentHeight = math.max(contentHeight, 5200); // Altezza minima aumentata per scroll verticale più lungo

    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Container(
        width: totalWidth,
        height: contentHeight,
        child: Row(
          children: visibleHours.map((hour) {
            final eventsForHour = eventsByHour[hour] ?? [];
            final hasEvents = eventsForHour.isNotEmpty;
            
            // Width ridotta per ore senza eventi
            final width = hasEvents ? 160.0 : 60.0;
            
            // Verifica se l'ora è nel passato (solo per oggi)
            final isPastHour = isToday && hour < now.hour;
            
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isPastHour ? null : () {
                  _showMinuteSelector(hour);
                },
                highlightColor: isPastHour ? Colors.transparent : theme.colorScheme.primary.withOpacity(0.1),
                splashColor: isPastHour ? Colors.transparent : theme.colorScheme.primary.withOpacity(0.2),
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: (isDark ? Colors.grey[800] : Colors.grey[200])!, width: 1),
                      right: BorderSide(color: (isDark ? Colors.grey[800] : Colors.grey[200])!, width: 1),
                    ),
                    color: isPastHour 
                        ? (isDark ? Colors.grey[900] : Colors.grey[100]) // Colore più scuro per le ore passate
                        : theme.cardColor,
                    // Aggiungi evidenziazione se questa è l'ora target
                    boxShadow: _highlightedHour == hour ? [
                      BoxShadow(
                        color: Color(0xFF667eea).withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                        offset: Offset(0, 2),
                      ),
                    ] : null,
                  ),
                  child: Stack(
                    children: [
                      // Grid lines pattern (always visible)
                      CustomPaint(
                        size: Size(width, double.infinity),
                        painter: HourPatternPainter(),
                      ),
                      
                      // Events for this hour
                      if (hasEvents)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: eventsForHour.length,
                            itemBuilder: (context, eventIndex) {
                              return _buildModernEventCard(eventsForHour[eventIndex], theme, width);
                            },
                          ),
                        ),
                      
                      // Add button indicator
                      if (!hasEvents)
                        Center(),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  // Calculate total content width considering expanded hour cells
  double _calculateTotalContentWidth(List<String> hours) {
    final events = _getEventsForDay(_selectedDay);
    
    // Group events by hour
    Map<int, List<Map<String, dynamic>>> eventsByHour = {};
    for (var event in events) {
      final scheduledTime = event['scheduledTime'] as int?;
      if (scheduledTime == null) continue;
      
      final eventDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
      final hour = eventDateTime.hour;
      
      if (!eventsByHour.containsKey(hour)) {
        eventsByHour[hour] = [];
      }
      eventsByHour[hour]!.add(event);
    }
    
    // Calculate total width with expanded hours
    double totalWidth = 0.0;
    for (int i = 0; i < hours.length; i++) {
      final hour = int.parse(hours[i].split(':')[0]);
      final hasEvents = eventsByHour.containsKey(hour) && eventsByHour[hour]!.isNotEmpty;
      totalWidth += hasEvents ? 160.0 : 60.0;
    }
    
    return totalWidth;
  }
  
  // New modern event card design with adjustable width
  Widget _buildModernEventCard(Map<String, dynamic> event, ThemeData theme, double containerWidth) {
    final scheduledTime = event['scheduledTime'] as int?;
    
    // Estrai le piattaforme dalla struttura accounts del database Firebase
    List<String> platforms = [];
    
    // Prima prova a estrarre dalla struttura accounts se presente
    final accounts = event['accounts'] as Map<dynamic, dynamic>?;
    if (accounts != null) {
      // Estrai le chiavi delle piattaforme dalla struttura accounts
      platforms = accounts.keys.map((platform) => platform.toString()).toList();
    } else {
      // Fallback al vecchio formato se accounts non esiste
      platforms = (event['platforms'] as List<dynamic>? ?? []).map((p) => p.toString()).toList();
    }
    
    // Se ancora non abbiamo piattaforme, prova a estrarre dal campo platform singolo
    if (platforms.isEmpty) {
      final platform = event['platform'] as String?;
      if (platform != null && platform.isNotEmpty) {
        platforms = [platform];
      }
    }
    
    // Get thumbnail URL from Firebase - use multiple sources with correct priority
    final thumbnailPath = event['thumbnail_path'] as String?; // Campo locale se disponibile
    final thumbnailUrl = event['thumbnail_url'] as String?; // Campo principale per thumbnail da Firebase
    final thumbnailCloudflareUrl = event['thumbnail_cloudflare_url'] as String?; // Campo alternativo per thumbnail
    final isImage = event['is_image'] == true;
    
    // Determine the best thumbnail URL to use (priority: thumbnail_url > thumbnail_cloudflare_url > thumbnail_path)
    final String? bestThumbnailUrl = (thumbnailUrl != null && thumbnailUrl.isNotEmpty) 
        ? thumbnailUrl 
        : (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) 
            ? thumbnailCloudflareUrl 
            : (thumbnailPath != null && thumbnailPath.isNotEmpty && thumbnailPath.startsWith('http'))
                ? thumbnailPath 
                : null;
    
    // Format the time
    final timeString = scheduledTime != null
        ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(scheduledTime))
        : '';
    
    // Primary color for the event card
    final Color cardColor = platforms.isNotEmpty 
        ? _getPlatformColor(platforms.first)
        : theme.colorScheme.primary;
    
    // Calculate card width based on container width
    final cardWidth = containerWidth - 16; // 8px padding on each side
    
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4), // Aumentato spazio verticale di 5 pixel
      width: cardWidth,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScheduledPostDetailsPage(
                post: event,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: theme.brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade200,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnail image from Firebase with fallback logic
              if (bestThumbnailUrl != null)
                Container(
                  height: 80,
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 6),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        bestThumbnailUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: Colors.grey[200],
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          print('Error loading thumbnail: $error');
                          return Container(
                            color: Colors.grey[200],
                            child: Center(
                              child: Icon(
                                isImage ? Icons.image : Icons.video_library,
                                color: Colors.grey[400],
                                size: 24,
                              ),
                            ),
                          );
                        },
                      ),
                      // Duration indicator - use static duration display
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: _buildStaticDurationBadge(event),
                      ),
                    ],
                  ),
                )
              else
                // Fallback placeholder when no thumbnail is available
                Container(
                  height: 80,
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Icon(
                          isImage ? Icons.image : Icons.video_library,
                          color: Colors.grey[400],
                          size: 24,
                        ),
                      ),
                      // Duration indicator - use static duration display
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: _buildStaticDurationBadge(event),
                      ),
                    ],
                  ),
                ),
              
              // Platform logos and time in a row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Platform logos
                  Row(
                    children: [
                      for (int i = 0; i < platforms.length && i < 3; i++)
                        Padding(
                          padding: EdgeInsets.only(right: i < platforms.length - 1 ? 4 : 0),
                          child: _buildPlatformLogoSmall(platforms[i]),
                        ),
                      if (platforms.length > 3)
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '+${platforms.length - 3}',
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  // Time
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cardColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cardColor,
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
  }

  // Build navigation button - used in the week view
  Widget _buildNavigationButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              icon,
              size: 22,
              color: Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  // Get platform color - used in event cards
  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Colors.red;
      case 'tiktok':
        return Colors.black87;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue;
      case 'twitter':
        return Colors.lightBlue;
      case 'snapchat':
        return Colors.amber;
      case 'linkedin':
        return Colors.blue.shade800;
      case 'pinterest':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }
  
  // Build quick view (upcoming/recent toggle)
  Widget _buildQuickView() {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(top: 20), // Ridotto padding superiore
      child: Column(
        children: [
          // Filter toggle for upcoming/recent posts - glass effect
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.white.withOpacity(0.4),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.4)
                          : Colors.black.withOpacity(0.15),
                      blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                      spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.white.withOpacity(0.6),
                      blurRadius: 2,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0.1),
                          ]
                        : [
                            Colors.white.withOpacity(0.3),
                            Colors.white.withOpacity(0.2),
                          ],
                  ),
                ),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Row(

                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFilterButton(
                    isSelected: _currentSortMode == SortMode.upcoming,
                    icon: Icons.access_time,
                    label: 'Upcoming',
                    onTap: () {
                      setState(() {
                        _currentSortMode = SortMode.upcoming;
                        _sortScheduledPosts();
                      });
                    },
                    theme: theme,
                  ),
                  const SizedBox(width: 10),
                  _buildFilterButton(
                    isSelected: _currentSortMode == SortMode.recent,
                    icon: Icons.history,
                    label: 'Recent',
                    onTap: () {
                      setState(() {
                        _currentSortMode = SortMode.recent;
                        _sortScheduledPosts();
                      });
                    },
                    theme: theme,
                  ),
                ],
              ),
            ],
                ),
              ),
            ),
          ),
        
        // List of filtered posts
        Expanded(
          child: _buildFilteredPostsList(),
        ),
      ],
        ),
      );
  }
  
  // Build filtered posts list for quick view
  Widget _buildFilteredPostsList() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final filteredPosts = _currentSortMode == SortMode.upcoming
        ? _scheduledPosts.where((post) {
            final scheduledTime = post['scheduledTime'] as int?;
            if (scheduledTime == null) return false;
            final postTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
            final difference = postTime.difference(now);
            // Filtro YouTube scaduti
            List<String> platforms = [];
            if (post['accounts'] != null && post['accounts'] is Map) {
              platforms = (post['accounts'] as Map).keys.map((e) => e.toString().toLowerCase()).toList();
            } else if (post['platforms'] != null && post['platforms'] is List) {
              platforms = (post['platforms'] as List).map((e) => e.toString().toLowerCase()).toList();
            } else if (post['platform'] != null) {
              platforms = [post['platform'].toString().toLowerCase()];
            }
            final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
            final isPast = scheduledTime < now.millisecondsSinceEpoch;
            if (isOnlyYouTube && isPast) return false;
            // Posts scheduled to be published in the next 20 minutes
            return difference.inMinutes >= 0 && difference.inMinutes <= 20;
          }).toList()
        : _publishedVideos.where((video) {
            // Per la modalità "recent", usa i video pubblicati dal database videos
            final videoId = video['id']?.toString();
            final userId = video['user_id']?.toString();
            final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
            
            // Calcola il timestamp usando la stessa logica di history_page.dart
            int timestamp;
            if (isNewFormat) {
              // Per il nuovo formato: usa created_at, fallback a timestamp
              int? createdAt;
              if (video.containsKey('created_at')) {
                final val = video['created_at'];
                if (val is int) {
                  createdAt = val;
                } else if (val is String) {
                  createdAt = int.tryParse(val);
                }
              }
              timestamp = createdAt ?? (video['timestamp'] is int ? video['timestamp'] as int : int.tryParse(video['timestamp'].toString()) ?? 0);
            } else {
              // Per il vecchio formato: usa published_at, fallback a timestamp
              timestamp = video['published_at'] as int? ?? (video['timestamp'] is int ? video['timestamp'] as int : int.tryParse(video['timestamp'].toString()) ?? 0);
            }
            
            // Per i video YouTube schedulati, usa scheduled_time se disponibile
            final status = video['status'] as String? ?? '';
            final scheduledTime = video['scheduled_time'] as int?;
            final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
            final hasYouTube = accounts.containsKey('YouTube');
            
            if (status == 'scheduled' && hasYouTube && scheduledTime != null) {
              timestamp = scheduledTime;
            }
            
            final postTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final difference = now.difference(postTime);
            
            // Posts that were published in the last hour
            return difference.inMinutes >= 0 && difference.inMinutes <= 60;
          }).toList();
    
    if (filteredPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentSortMode == SortMode.upcoming ? Icons.schedule : Icons.history,
              size: _currentSortMode == SortMode.upcoming ? 64 : 70,
              color: Color(0xFF667eea).withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _currentSortMode == SortMode.upcoming
                  ? 'No posts in the next 20 minutes'
                  : 'No posts published in the last hour',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredPosts.length,
      itemBuilder: (context, index) {
        return _buildVideoCard(theme, filteredPosts[index]);
      },
    );
  }
  
  // Filter button for quick view
  Widget _buildFilterButton({
    required bool isSelected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  )
                : null,
            color: isSelected
                ? null
                : (theme.brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.white.withOpacity(0.22)),
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? null
                : Border.all(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.white.withOpacity(0.4),
                    width: 1,
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: theme.brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.08)
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              isSelected
                  ? Icon(
                      icon,
                      color: Colors.white,
                      size: 16,
                    )
                  : ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ).createShader(bounds);
                      },
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
              const SizedBox(width: 8),
              isSelected
                  ? Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  : ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ).createShader(bounds);
                      },
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: theme.brightness,
        scaffoldBackgroundColor: theme.brightness == Brightness.dark 
            ? Color(0xFF121212) 
            : Colors.white,
        cardColor: theme.brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          background: theme.brightness == Brightness.dark 
              ? Color(0xFF121212) 
              : Colors.white,
          surface: theme.brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: theme.brightness == Brightness.dark 
            ? Color(0xFF121212) 
            : Colors.white,
              body: SafeArea(
          child: Column(
            children: [
              // Padding sopra la TabBar
              SizedBox(height: MediaQuery.of(context).size.height * 0.08), // 8% dell'altezza dello schermo
              
              // Updated navigation - now using TabBar similar to history_page
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        // Effetto vetro sospeso
                        color: isDark
                            ? Colors.white.withOpacity(0.15)
                            : Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(30),
                        // Bordo con effetto vetro
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.2)
                              : Colors.white.withOpacity(0.4),
                          width: 1,
                        ),
                        // Ombre per effetto sospeso
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withOpacity(0.4)
                                : Colors.black.withOpacity(0.15),
                            blurRadius: isDark ? 25 : 20,
                            spreadRadius: isDark ? 1 : 0,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.white.withOpacity(0.6),
                            blurRadius: 2,
                            spreadRadius: -2,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        // Gradiente sottile per effetto vetro
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  Colors.white.withOpacity(0.2),
                                  Colors.white.withOpacity(0.1),
                                ]
                              : [
                                  Colors.white.withOpacity(0.3),
                                  Colors.white.withOpacity(0.2),
                                ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: Colors.white,
                          unselectedLabelColor: theme.unselectedWidgetColor,
                          indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF667eea),
                                Color(0xFF764ba2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform:
                                  GradientRotation(135 * 3.14159 / 180),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF667eea).withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.transparent, // Nasconde il testo predefinito
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 13,
                            color: Colors.transparent, // Nasconde il testo predefinito
                          ),
                          labelPadding: EdgeInsets.zero,
                          padding: EdgeInsets.zero,
                          tabs: [
                            Tab(
                              icon: AnimatedBuilder(
                                animation: _tabController,
                                builder: (context, child) {
                                  final isSelected = _tabController.index == 0;
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      isSelected
                                          ? Icon(Icons.view_week_rounded, size: 18, color: Colors.white)
                                          : ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF667eea), // blu violaceo
                                                    Color(0xFF764ba2), // viola
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
                                                ).createShader(bounds);
                                              },
                                              child: Icon(Icons.view_week_rounded, size: 18, color: Colors.white),
                                            ),
                                      const SizedBox(width: 6),
                                      isSelected
                                          ? Text('Week', style: TextStyle(color: Colors.white))
                                          : ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF667eea), // blu violaceo
                                                    Color(0xFF764ba2), // viola
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
                                                ).createShader(bounds);
                                              },
                                              child: Text('Week', style: TextStyle(color: Colors.white)),
                                            ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Tab(
                              icon: AnimatedBuilder(
                                animation: _tabController,
                                builder: (context, child) {
                                  final isSelected = _tabController.index == 1;
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      isSelected
                                          ? Icon(Icons.calendar_month_rounded, size: 18, color: Colors.white)
                                          : ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF667eea), // blu violaceo
                                                    Color(0xFF764ba2), // viola
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
                                                ).createShader(bounds);
                                              },
                                              child: Icon(Icons.calendar_month_rounded, size: 18, color: Colors.white),
                                            ),
                                      const SizedBox(width: 6),
                                      isSelected
                                          ? Text('Month', style: TextStyle(color: Colors.white))
                                          : ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF667eea), // blu violaceo
                                                    Color(0xFF764ba2), // viola
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
                                                ).createShader(bounds);
                                              },
                                              child: Text('Month', style: TextStyle(color: Colors.white)),
                                            ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Tab(
                              icon: AnimatedBuilder(
                                animation: _tabController,
                                builder: (context, child) {
                                  final isSelected = _tabController.index == 2;
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      isSelected
                                          ? Icon(Icons.timer_rounded, size: 18, color: Colors.white)
                                          : ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF667eea), // blu violaceo
                                                    Color(0xFF764ba2), // viola
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
                                                ).createShader(bounds);
                                              },
                                              child: Icon(Icons.timer_rounded, size: 18, color: Colors.white),
                                            ),
                                      const SizedBox(width: 6),
                                      isSelected
                                          ? Text('Quick', style: TextStyle(color: Colors.white))
                                          : ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF667eea), // blu violaceo
                                                    Color(0xFF764ba2), // viola
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
                                                ).createShader(bounds);
                                              },
                                              child: Text('Quick', style: TextStyle(color: Colors.white)),
                                            ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            
                          const SizedBox(height: 2),
            
            // Main content using TabBarView for smooth transitions
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildWeekView(),
                      _buildMonthView(),
                      _buildQuickView(),
                    ],
                  ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // Nuovo metodo per scorrere alla fascia oraria corrente
  void _scrollToCurrentHour() {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      
      // Assicurati che il controller sia disponibile
      if (!horizontalScrollController.hasClients) {
        // Se il controller non è ancora disponibile, riprova dopo un breve delay
        Future.delayed(Duration(milliseconds: 200), () {
          if (mounted) {
            _scrollToCurrentHour();
          }
        });
        return;
      }
      
      // Determina l'ora target in base al giorno selezionato
      int targetHour;
      final isToday = isSameDay(_selectedDay, now);
      final isPast = _isDateInPast(_selectedDay);
      final isFuture = _isDateInFuture(_selectedDay);
      
      if (isToday) {
        // Per oggi, scrolla all'ora corrente
        targetHour = currentHour;
      } else if (isPast) {
        // Per giorni passati, scrolla all'inizio (00:00)
        targetHour = 0;
      } else if (isFuture) {
        // Per giorni futuri, scrolla all'ora corrente di oggi (per riferimento)
        targetHour = currentHour;
      } else {
        // Fallback all'ora corrente
        targetHour = currentHour;
      }
      
      // Calcola la posizione di scorrimento
      double scrollPosition = 0;
      
      // Calcola la larghezza totale fino all'ora target
      for (int i = 0; i < targetHour; i++) {
        final events = _getEventsForDay(_selectedDay);
        
        Map<int, List<Map<String, dynamic>>> eventsByHour = {};
        for (var event in events) {
          final scheduledTime = event['scheduledTime'] as int?;
          if (scheduledTime == null) continue;
          
          final eventDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
          final hour = eventDateTime.hour;
          
          if (!eventsByHour.containsKey(hour)) {
            eventsByHour[hour] = [];
          }
          eventsByHour[hour]!.add(event);
        }
        
        final hasEvents = eventsByHour.containsKey(i) && eventsByHour[i]!.isNotEmpty;
        scrollPosition += hasEvents ? 160.0 : 60.0;
      }
      
      // Assicurati che la posizione sia valida
      final maxScrollExtent = horizontalScrollController.position.maxScrollExtent;
      scrollPosition = scrollPosition.clamp(0.0, maxScrollExtent);
      
      // Esegui lo scroll con un'animazione fluida
      horizontalScrollController.animateTo(
        scrollPosition,
        duration: Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      ).then((_) {
        // Aggiorna il flag quando lo scroll è completato
        if (mounted) {
          setState(() {
            _hasScrolledToCurrentHour = true;
          });
        }
      });
      
      print('Scrolled to target hour: $targetHour, position: $scrollPosition (isToday: $isToday, isPast: $isPast, isFuture: $isFuture)');
    } catch (e) {
      print('Error scrolling to current hour: $e');
      // In caso di errore, riprova dopo un breve delay
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          _scrollToCurrentHour();
        }
      });
    }
  }

  // Metodo per mostrare il selettore dei minuti
  void _showMinuteSelector(int selectedHour) {
    final theme = Theme.of(context);
    int selectedMinute = 0;
    
    // Calcola se l'ora è futura o passata
    final now = DateTime.now();
    final selectedDateTime = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      selectedHour,
      0,
    );
    
    // Verifica se l'orario selezionato è meno di 20 minuti nel futuro
    final minimumAllowedDateTime = now.add(Duration(minutes: 20));
    final bool isLessThan20MinutesInFuture = selectedDateTime.add(Duration(minutes: selectedMinute)).isBefore(minimumAllowedDateTime);
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Verifica in tempo reale se l'orario selezionato è almeno 20 minuti nel futuro
            final selectedFullDateTime = DateTime(
              _selectedDay.year,
              _selectedDay.month,
              _selectedDay.day,
              selectedHour,
              selectedMinute,
            );
            final bool isTimeValid = selectedFullDateTime.isAfter(minimumAllowedDateTime);
            
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Titolo con orario
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select minute',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isTimeValid ? theme.colorScheme.primary : Colors.grey,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (isTimeValid ? theme.colorScheme.primary : Colors.grey).withOpacity(0.3),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Data selezionata
                    SizedBox(height: 8),
                    Text(
                      'Post scheduled for ${_selectedDay.day} ${DateFormat('MMMM').format(_selectedDay)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Avviso se l'ora non è valida (meno di 20 minuti nel futuro)
                    if (!isTimeValid)
                      Container(
                        padding: EdgeInsets.all(10),
                        margin: EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Posts must be scheduled at least 20 minutes in advance',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Orologio analogico per i minuti con tema migliorato
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            spreadRadius: 1,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Numeri dei minuti intorno al bordo
                          ..._buildMinuteNumbers(),
                          
                          // Linea centrale (lancetta) con tema migliorato
                          Transform.rotate(
                            angle: selectedMinute * (2 * math.pi / 60),
                            child: Container(
                              width: 2,
                              height: 120,
                              decoration: BoxDecoration(
                                color: isTimeValid 
                                    ? theme.colorScheme.primary.withOpacity(0.15)
                                    : Colors.grey[400],
                                borderRadius: BorderRadius.circular(1),
                              ),
                              alignment: Alignment.topCenter,
                              transformAlignment: Alignment.bottomCenter,
                            ),
                          ),
                          
                          // Punto centrale dell'orologio
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isTimeValid 
                                  ? theme.colorScheme.primary.withOpacity(0.7)
                                  : Colors.grey[400],
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 2,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          
                          // Cerchio di evidenziazione per il minuto selezionato
                          Transform.rotate(
                            angle: selectedMinute * (2 * math.pi / 60),
                            child: Transform.translate(
                              offset: Offset(0, -90), // Posiziona il cerchio sulla punta della lancetta
                              child: Container(
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  color: isTimeValid 
                                      ? theme.colorScheme.primary.withOpacity(0.2)
                                      : Colors.grey[300],
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isTimeValid 
                                          ? theme.colorScheme.primary.withOpacity(0.7)
                                          : Colors.grey[400],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          // Area cliccabile per selezionare i minuti
                          GestureDetector(
                            onPanStart: (details) {
                              final minute = _calculateSelectedMinute(details.localPosition);
                              setState(() {
                                selectedMinute = minute;
                              });
                            },
                            onPanUpdate: (details) {
                              final minute = _calculateSelectedMinute(details.localPosition);
                              setState(() {
                                selectedMinute = minute;
                              });
                            },
                            child: Container(
                              width: 260,
                              height: 260,
                              color: Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Pulsanti per minuti comuni
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [0, 15, 30, 45].map((minute) {
                        final isSelected = minute == selectedMinute;
                        final fullDateTime = DateTime(
                          _selectedDay.year,
                          _selectedDay.month,
                          _selectedDay.day,
                          selectedHour,
                          minute,
                        );
                        final isMinuteValid = fullDateTime.isAfter(minimumAllowedDateTime);
                        
                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedMinute = minute;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? (isMinuteValid ? theme.colorScheme.primary.withOpacity(0.7) : Colors.grey) 
                                  : (isMinuteValid ? Colors.grey.shade100 : Colors.grey.shade50),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected 
                                    ? (isMinuteValid ? theme.colorScheme.primary.withOpacity(0.7) : Colors.grey)
                                    : (isMinuteValid ? Colors.grey.shade300 : Colors.grey.shade200),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              minute.toString().padLeft(2, '0'),
                              style: TextStyle(
                                color: isSelected 
                                    ? Colors.white 
                                    : (isMinuteValid ? Colors.black87 : Colors.grey),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Pulsanti di azione
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        // Pulsante "Create Post" con stile migliorato
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isTimeValid ? theme.colorScheme.primary.withOpacity(0.7) : Colors.grey,
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isTimeValid 
                                    ? theme.colorScheme.primary.withOpacity(0.5)
                                    : Colors.grey.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                          ),
                          icon: Icon(Icons.schedule, size: 18),
                          label: Text('Create post'),
                          onPressed: isTimeValid ? () {
                            Navigator.of(context).pop();
                            
                            // Crea il DateTime programmato
                            final scheduledDate = DateTime(
                              _selectedDay.year,
                              _selectedDay.month,
                              _selectedDay.day,
                              selectedHour,
                              selectedMinute,
                            );
                            
                            // Naviga a UploadVideoPage con il DateTime preselezionato
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UploadVideoPage(
                                  scheduledDateTime: scheduledDate,
                                ),
                              ),
                            );
                          } : null,
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
  }

  // Nuovo metodo per mostrare il selettore dei minuti per il giorno successivo
  void _showMinuteSelectorForNextDay(int selectedHour, DateTime nextDay) async {
    final theme = Theme.of(context);
    
    // Calcola se l'ora è futura o passata
    final now = DateTime.now();
    final minimumAllowedDateTime = now.add(Duration(minutes: 20));
    
    // Show time picker with custom theme like in monthly_detail_page.dart
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: selectedHour, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              dialHandColor: theme.colorScheme.primary.withOpacity(0.15),
              hourMinuteTextColor: theme.colorScheme.onSurface,
              dayPeriodTextColor: theme.colorScheme.onSurface,
              dialTextColor: theme.colorScheme.onSurface,
              dialBackgroundColor: theme.colorScheme.surfaceVariant,
              entryModeIconColor: theme.colorScheme.primary,
              hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              helpTextStyle: TextStyle(
                color: theme.colorScheme.onSurface,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            colorScheme: ColorScheme.light(
              primary: theme.colorScheme.primary.withOpacity(0.7),
              onPrimary: Colors.white,
              surface: theme.colorScheme.surface,
              onSurface: theme.colorScheme.onSurface,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null && mounted) {
      // Create a DateTime object combining the selected day and time
      final selectedDateTime = DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        time.hour,
        time.minute,
      );
      
      // Verifica se l'orario selezionato è almeno 20 minuti nel futuro
      if (selectedDateTime.isAfter(minimumAllowedDateTime)) {
        // Navigate to the upload page with the scheduled date
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UploadVideoPage(
              scheduledDateTime: selectedDateTime,
            ),
          ),
        );
      } else {
        // Mostra un avviso se l'orario non è valido
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Posts must be scheduled at least 20 minutes in advance',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // Check if a date is in the past (not including today)
  bool _isDateInPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider strictly past days (before today) as "past"
    return compareDate.isBefore(today);
  }

  // Check if a date is in the future
  bool _isDateInFuture(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider only strictly future days as "future"
    return compareDate.isAfter(today);
  }
  
  // Metodo per costruire i numeri dei minuti intorno al quadrante dell'orologio
  List<Widget> _buildMinuteNumbers() {
    final List<Widget> widgets = [];
    const double radius = 110.0; // Raggio del cerchio dei numeri
    
    for (int i = 0; i < 60; i += 5) { // Mostra solo i numeri ogni 5 minuti (0, 5, 10, 15, etc.)
      final double angle = i * (2 * math.pi / 60) - math.pi / 2; // Inizia da 12 in punto
      final double x = radius * math.cos(angle);
      final double y = radius * math.sin(angle);
      
      widgets.add(
        Positioned(
          left: 130 + x - 10, // 130 è il centro dell'orologio (260/2), -10 per centrare il testo
          top: 130 + y - 10,
          child: Container(
            width: 20,
            height: 20,
            child: Center(
              child: Text(
                i.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    return widgets;
  }
  
  // Metodo per gestire gli argomenti passati tramite route
  void _handleRouteArguments() {
    try {
      // Controlla se ci sono argomenti passati tramite route
      final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      
      if (arguments != null) {
        // Estrai la data target se presente
        if (arguments.containsKey('selectedDate')) {
          _targetDate = arguments['selectedDate'] as DateTime;
          _selectedDay = _targetDate!;
          _focusedDay = _targetDate!;
        }
        
        // Controlla se deve scrollare all'ora specifica
        if (arguments.containsKey('scrollToTime')) {
          _shouldScrollToTime = arguments['scrollToTime'] as bool;
          
          // Se deve scrollare all'ora specifica, assicurati che la tab Week View sia attiva
          if (_shouldScrollToTime && _tabController.length > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _tabController.index != 0) {
                _tabController.animateTo(0); // Attiva la tab Week View
              }
            });
          }
        }
      }
      
      // Se non ci sono argomenti di route, usa quelli del widget
      if (_targetDate == null && widget.arguments != null) {
        if (widget.arguments!.containsKey('selectedDate')) {
          _targetDate = widget.arguments!['selectedDate'] as DateTime;
          _selectedDay = _targetDate!;
          _focusedDay = _targetDate!;
        }
        
        if (widget.arguments!.containsKey('scrollToTime')) {
          _shouldScrollToTime = widget.arguments!['scrollToTime'] as bool;
          
          // Se deve scrollare all'ora specifica, assicurati che la tab Week View sia attiva
          if (_shouldScrollToTime && _tabController.length > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _tabController.index != 0) {
                _tabController.animateTo(0); // Attiva la tab Week View
              }
            });
          }
        }
      }
    } catch (e) {
      print('Error handling route arguments: $e');
      // In caso di errore, usa i valori di default
    }
  }
  
  // Metodo per scrollare all'ora target specifica
  void _scrollToTargetTime() {
    try {
      if (_targetDate != null && horizontalScrollController.hasClients) {
        final targetHour = _targetDate!.hour;
        
        // Imposta l'ora evidenziata
        setState(() {
          _highlightedHour = targetHour;
        });
        
        // Aspetta che il layout sia completamente renderizzato
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          // Calcola la posizione di scroll basandosi sui post esistenti
          double scrollPosition = 0;
          
          // Calcola la larghezza totale fino all'ora target
          for (int i = 0; i < targetHour; i++) {
            final events = _getEventsForDay(_targetDate!);
            
            Map<int, List<Map<String, dynamic>>> eventsByHour = {};
            for (var event in events) {
              final scheduledTime = event['scheduledTime'] as int?;
              if (scheduledTime == null) continue;
              
              final eventDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final hour = eventDateTime.hour;
              
              if (!eventsByHour.containsKey(hour)) {
                eventsByHour[hour] = [];
              }
              eventsByHour[hour]!.add(event);
            }
            
            final hasEvents = eventsByHour.containsKey(i) && eventsByHour[i]!.isNotEmpty;
            final hourWidth = hasEvents ? 160.0 : 60.0;
            scrollPosition += hourWidth;
          }
          
          // Sottrai metà della larghezza dell'ora target per centrarla meglio
          final targetHourEvents = _getEventsForDay(_targetDate!);
          Map<int, List<Map<String, dynamic>>> targetEventsByHour = {};
          for (var event in targetHourEvents) {
            final scheduledTime = event['scheduledTime'] as int?;
            if (scheduledTime == null) continue;
            
            final eventDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
            final hour = eventDateTime.hour;
            
            if (!targetEventsByHour.containsKey(hour)) {
              targetEventsByHour[hour] = [];
            }
            targetEventsByHour[hour]!.add(event);
          }
          
          final targetHourHasEvents = targetEventsByHour.containsKey(targetHour) && targetEventsByHour[targetHour]!.isNotEmpty;
          final targetHourWidth = targetHourHasEvents ? 160.0 : 60.0;
          
          // Centra l'ora target sottraendo metà della sua larghezza
          scrollPosition -= targetHourWidth / 2;
          
          // Assicurati che la posizione sia valida
          scrollPosition = scrollPosition.clamp(0.0, horizontalScrollController.position.maxScrollExtent);
          
          // FALLBACK: Se il calcolo sembra sbagliato, usa una posizione fissa per ora
          if (scrollPosition < 0 || scrollPosition > horizontalScrollController.position.maxScrollExtent) {
            scrollPosition = targetHour * 60.0; // 60px per ora
            scrollPosition = scrollPosition.clamp(0.0, horizontalScrollController.position.maxScrollExtent);
          }
          
          horizontalScrollController.animateTo(
            scrollPosition,
            duration: Duration(milliseconds: 800),
            curve: Curves.easeInOut,
          ).then((_) {
            // Aggiorna il flag quando lo scroll è completato
            if (mounted) {
              setState(() {
                _hasScrolledToCurrentHour = true;
              });
            }
          });
          
          // Rimuovi l'evidenziazione dopo 3 secondi
          Future.delayed(Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _highlightedHour = null;
              });
            }
          });
        });
      }
    } catch (e) {
      // In caso di errore, fallback al metodo normale
      _scrollToCurrentHour();
    }
  }

  // Metodo per caricare i video pubblicati dal database videos
  Future<void> _loadPublishedVideos() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final snapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('videos')
            .get();

        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          final videos = data.entries.map((entry) {
            final videoData = entry.value as Map<dynamic, dynamic>;
            
            try {
              // Extract video status with proper handling
              String status = videoData['status']?.toString() ?? 'published';
              
              // Check if it's a scheduled post
              final publishedAt = videoData['published_at'] as int?;
              final scheduledTime = videoData['scheduled_time'] as int?;
              final fromScheduler = videoData['from_scheduler'] == true;
              
              // Check if it's a scheduled post and handle YouTube specifically
              if (status == 'scheduled') {
                final scheduledTime = videoData['scheduled_time'] as int?;
                final accounts = videoData['accounts'] as Map<dynamic, dynamic>? ?? {};
                final hasYouTube = accounts.containsKey('YouTube');
                
                // For YouTube scheduled posts, show them if scheduled time is in the past
                if (hasYouTube && scheduledTime != null) {
                  final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
                  final now = DateTime.now();
                  
                  if (scheduledDateTime.isBefore(now)) {
                    // YouTube scheduled post with past scheduled time - show as published
                    status = 'published';
                  } else {
                    // YouTube scheduled post with future scheduled time - skip
                    return null;
                  }
                } else if (!hasYouTube) {
                  // Non-YouTube scheduled posts - skip if not published
                  if (publishedAt == null) {
                    return null;
                  } else {
                    status = 'published';
                  }
                } else {
                  // YouTube scheduled post without scheduled_time - skip
                  return null;
                }
              }
              
              // If post was scheduled and has been published, mark it as published
              if (publishedAt != null && (status == 'scheduled' || fromScheduler)) {
                status = 'published';
              }
              
              // Solo includi video pubblicati
              if (status != 'published') {
                return null;
              }
              
              return {
                'id': entry.key,
                'title': videoData['title'] ?? '',
                'description': videoData['description'] ?? '',
                'platforms': List<String>.from(videoData['platforms'] ?? []),
                'status': status,
                'timestamp': videoData['timestamp'] ?? 0,
                'created_at': videoData['created_at'],
                'video_path': videoData['video_path'] ?? '',
                'thumbnail_path': videoData['thumbnail_path'] ?? '',
                'thumbnail_url': videoData['thumbnail_url'],
                'accounts': videoData['accounts'] ?? {},
                'user_id': videoData['user_id'] ?? '',
                'scheduled_time': videoData['scheduled_time'],
                'published_at': publishedAt,
                'youtube_video_id': videoData['youtube_video_id'],
                'thumbnail_cloudflare_url': videoData['thumbnail_cloudflare_url'] ?? '',
                'is_image': videoData['is_image'] ?? false,
                'video_duration_seconds': videoData['video_duration_seconds'],
                'video_duration_minutes': videoData['video_duration_minutes'],
                'video_duration_remaining_seconds': videoData['video_duration_remaining_seconds'],
                // Aggiungo campi per compatibilità con scheduled posts
                'scheduledTime': publishedAt ?? videoData['timestamp'] ?? 0,
                'media_url': videoData['video_path'] ?? '',
                'text': videoData['description'] ?? '',
                'platform': videoData['platforms']?.isNotEmpty == true ? videoData['platforms'][0] : '',
                'media_type': videoData['is_image'] == true ? 'image' : 'video',
                'cloudflare_urls': videoData['cloudflare_urls'], // Aggiunto per il controllo del carosello
                'media_urls': videoData['media_urls'], // Aggiunto per il controllo del carosello
              };
            } catch (e) {
              print('Error processing video: $e');
              return null;
            }
          })
          .where((video) => video != null)
          .cast<Map<String, dynamic>>()
          .toList()
          ..sort((a, b) {
            // Determina se sono video del nuovo formato
            final aVideoId = a['id']?.toString();
            final aUserId = a['user_id']?.toString();
            final aIsNewFormat = aVideoId != null && aUserId != null && aVideoId.contains(aUserId);
            
            final bVideoId = b['id']?.toString();
            final bUserId = b['user_id']?.toString();
            final bIsNewFormat = bVideoId != null && bUserId != null && bVideoId.contains(bUserId);
            
            // Calcola il timestamp per il video A
            int aTime;
            if (aIsNewFormat) {
              // Per il nuovo formato: usa created_at, fallback a timestamp
              int? aCreatedAt;
              if (a.containsKey('created_at')) {
                final val = a['created_at'];
                if (val is int) {
                  aCreatedAt = val;
                } else if (val is String) {
                  aCreatedAt = int.tryParse(val);
                }
              }
              aTime = aCreatedAt ?? (a['timestamp'] is int ? a['timestamp'] as int : int.tryParse(a['timestamp'].toString()) ?? 0);
            } else {
              // Per il vecchio formato: usa published_at, fallback a timestamp
              aTime = a['published_at'] as int? ?? (a['timestamp'] is int ? a['timestamp'] as int : int.tryParse(a['timestamp'].toString()) ?? 0);
            }
            
            // Per i video YouTube schedulati, usa scheduled_time se disponibile
            final aStatus = a['status'] as String? ?? '';
            final aScheduledTime = a['scheduled_time'] as int?;
            final aAccounts = a['accounts'] as Map<dynamic, dynamic>? ?? {};
            final aHasYouTube = aAccounts.containsKey('YouTube');
            
            if (aStatus == 'scheduled' && aHasYouTube && aScheduledTime != null) {
              aTime = aScheduledTime;
            }
            
            // Calcola il timestamp per il video B
            int bTime;
            if (bIsNewFormat) {
              // Per il nuovo formato: usa created_at, fallback a timestamp
              int? bCreatedAt;
              if (b.containsKey('created_at')) {
                final val = b['created_at'];
                if (val is int) {
                  bCreatedAt = val;
                } else if (val is String) {
                  bCreatedAt = int.tryParse(val);
                }
              }
              bTime = bCreatedAt ?? (b['timestamp'] is int ? b['timestamp'] as int : int.tryParse(b['timestamp'].toString()) ?? 0);
            } else {
              // Per il vecchio formato: usa published_at, fallback a timestamp
              bTime = b['published_at'] as int? ?? (b['timestamp'] is int ? b['timestamp'] as int : int.tryParse(b['timestamp'].toString()) ?? 0);
            }
            
            // Per i video YouTube schedulati, usa scheduled_time se disponibile
            final bStatus = b['status'] as String? ?? '';
            final bScheduledTime = b['scheduled_time'] as int?;
            final bAccounts = b['accounts'] as Map<dynamic, dynamic>? ?? {};
            final bHasYouTube = bAccounts.containsKey('YouTube');
            
            if (bStatus == 'scheduled' && bHasYouTube && bScheduledTime != null) {
              bTime = bScheduledTime;
            }
            
            return bTime.compareTo(aTime); // Ordine decrescente (più recenti prima)
          });

          setState(() {
            _publishedVideos = videos;
          });
        }
      }
    } catch (e) {
      print('Error loading published videos: $e');
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} ${(difference.inDays / 365).floor() == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} ${(difference.inDays / 30).floor() == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  int _countTotalAccounts(Map<String, dynamic> video, bool isNewFormat) {
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    int totalCount = 0;
    if (accounts.isEmpty) return 0;
    if (isNewFormat) {
      accounts.forEach((platform, accountData) {
        if (accountData is Map) {
          totalCount += 1;
        } else if (accountData is List) {
          totalCount += accountData.length;
        } else if (accountData != null) {
          totalCount += 1;
        }
      });
    } else {
      accounts.forEach((platform, platformAccounts) {
        if (platformAccounts is List) {
          totalCount += platformAccounts.length;
        } else if (platformAccounts is Map) {
          totalCount += platformAccounts.length;
        } else if (platformAccounts != null) {
          totalCount += 1;
        }
      });
    }
    return totalCount;
  }
}

// Custom painter for horizontal grid lines instead of diagonal pattern
class HourPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.1)
      ..strokeWidth = 1;
    
    // Draw horizontal lines every 15 minutes (quarter hour)
    for (int i = 1; i < 40; i++) {
      final y = (size.height / 40) * i;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
    
    // Draw vertical grid line at 30 minute mark
    final verticalPaint = Paint()
      ..color = Colors.grey.withOpacity(0.05)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
      
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      verticalPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Metodo helper per calcolare il minuto selezionato in base alla posizione del tocco
int _calculateSelectedMinute(Offset localPosition) {
  // Calcola l'angolo in base alla posizione relativa al centro dell'orologio
  final center = Offset(130, 130);
  final dx = localPosition.dx - center.dx;
  final dy = localPosition.dy - center.dy;
  
  // Calcola angolo in radianti
  double angle = math.atan2(dy, dx);
  
  // Converti l'angolo in minuti (0-59)
  double minuteDouble = ((angle / (2 * math.pi) * 60) + 15) % 60;
  if (minuteDouble < 0) minuteDouble += 60;
  
  // Arrotonda al minuto più vicino
  int minute = minuteDouble.round();
  if (minute == 60) minute = 0;
  
  return minute;
}

// Painter personalizzato per il quadrante dell'orologio
class ClockDialPainter extends CustomPainter {
  final ThemeData theme;
  
  ClockDialPainter({required this.theme});
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Disegna il cerchio esterno
    final Paint outerCirclePaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerCirclePaint);
    
    // Disegna il bordo del cerchio
    final Paint borderPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
    
    // Disegna le tacche principali (ogni 5 minuti)
    final Paint majorTickPaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2;
    
    // Disegna le tacche minori (ogni minuto)
    final Paint minorTickPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    
    for (int i = 0; i < 60; i++) {
      final angle = i * (2 * math.pi / 60);
      
      // Coordinate per le tacche
      final outerX = center.dx + math.cos(angle) * radius;
      final outerY = center.dy + math.sin(angle) * radius;
      
      if (i % 5 == 0) {
        // Tacche principali ogni 5 minuti
        final innerX = center.dx + math.cos(angle) * (radius - 15);
        final innerY = center.dy + math.sin(angle) * (radius - 15);
        
        canvas.drawLine(
          Offset(innerX, innerY),
          Offset(outerX - math.cos(angle) * 5, outerY - math.sin(angle) * 5),
          majorTickPaint,
        );
      } else {
        // Tacche minori per i minuti intermedi
        final innerX = center.dx + math.cos(angle) * (radius - 8);
        final innerY = center.dy + math.sin(angle) * (radius - 8);
        
        canvas.drawLine(
          Offset(innerX, innerY),
          Offset(outerX - math.cos(angle) * 3, outerY - math.sin(angle) * 3),
          minorTickPaint,
        );
      }
    }
    
    // Disegna cerchi colorati per i quarti d'ora (0, 15, 30, 45)
    final quarterHourPaint = Paint()
      ..color = theme.colorScheme.primary
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < 4; i++) {
      final angle = i * (math.pi / 2);
      final x = center.dx + math.cos(angle) * (radius - 30);
      final y = center.dy + math.sin(angle) * (radius - 30);
      
      // Cerchio esterno più grande
      canvas.drawCircle(Offset(x, y), 8, Paint()
        ..color = theme.colorScheme.primary.withOpacity(0.2)
        ..style = PaintingStyle.fill);
      
      // Cerchio interno più piccolo
      canvas.drawCircle(Offset(x, y), 5, quarterHourPaint);
    }
    
    // Etichette per i quarti d'ora
    final quarters = ["00", "15", "30", "45"];
    final quarterPositions = [
      Offset(center.dx, center.dy - (radius - 50)),  // 12 - 00
      Offset(center.dx + (radius - 50), center.dy),  // 3 - 15
      Offset(center.dx, center.dy + (radius - 50)),  // 6 - 30
      Offset(center.dx - (radius - 50), center.dy),  // 9 - 45
    ];
    
    final Paint dotPaint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    
    // Disegna punti per ogni 5 minuti
    for (int i = 0; i < 12; i++) {
      if (i % 3 != 0) { // Salta i quarti d'ora che hanno già i cerchi
        final angle = i * (math.pi / 6);
        final x = center.dx + math.cos(angle) * (radius - 30);
        final y = center.dy + math.sin(angle) * (radius - 30);
        
        canvas.drawCircle(Offset(x, y), 3, dotPaint);
      }
    }
  }
  
  @override
  bool shouldRepaint(ClockDialPainter oldDelegate) => false;
} 

// Add VideoPreviewWidget class at the bottom of the file
class VideoPreviewWidget extends StatefulWidget {
  final String? videoPath;
  final String? thumbnailPath;
  final String? thumbnailCloudflareUrl;
  final double width;
  final double height;
  final bool isImage;
  final String? videoId;
  final String? userId;
  final String status;
  final bool isNewFormat;

  const VideoPreviewWidget({
    super.key,
    required this.videoPath,
    this.thumbnailPath,
    this.thumbnailCloudflareUrl,
    this.width = 120,
    this.height = 80,
    this.isImage = false,
    this.videoId,
    this.userId,
    required this.status,
    required this.isNewFormat,
  });

  @override
  State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _hasError = false;
  String? _firebaseThumbnailUrl;

  @override
  void initState() {
    super.initState();
    // We don't auto-initialize the video to save resources
    // Instead we show the thumbnail or a placeholder
    
    // Load thumbnail from Firebase if this is a published video and not new format
    if (widget.status == 'published' && widget.videoId != null && widget.userId != null && !widget.isNewFormat) {
      _loadThumbnailFromFirebase();
    } else if (widget.isNewFormat) {
      // For new format, thumbnail is already available in thumbnailPath
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnailFromFirebase() async {
    try {
      final database = FirebaseDatabase.instance.ref();
      final thumbnailRef = database
          .child('users')
          .child('users')
          .child(widget.userId!)
          .child('videos')
          .child(widget.videoId!)
          .child('thumbnail_cloudflare_url');
      
      final snapshot = await thumbnailRef.get();
      if (snapshot.exists && mounted) {
        final thumbnailUrl = snapshot.value as String?;
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
          setState(() {
            _firebaseThumbnailUrl = thumbnailUrl;
            _isLoading = false;
          });
          print('Loaded thumbnail from Firebase: $thumbnailUrl');
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading thumbnail from Firebase: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Widget _buildThumbnail() {
    // Se nuovo formato, mostra SOLO thumbnailPath (che è thumbnail_url)
    if (widget.isNewFormat) {
      if (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
        return _buildNetworkImage(widget.thumbnailPath!);
      } else if (widget.videoPath != null && widget.videoPath!.isNotEmpty) {
        // Fallback al video se non c'è thumbnail
        return _buildNetworkImage(widget.videoPath!, isVideo: true);
      } else {
        return _buildPlaceholder();
      }
    }
    
    // First determine if we're dealing with a URL or local path
    bool isVideoUrl = widget.videoPath != null && 
                      (widget.videoPath!.startsWith('http://') || 
                       widget.videoPath!.startsWith('https://'));
    
    bool isThumbnailUrl = widget.thumbnailPath != null && 
                          (widget.thumbnailPath!.startsWith('http://') || 
                           widget.thumbnailPath!.startsWith('https://'));
    
    bool isCloudflareUrl = widget.thumbnailCloudflareUrl != null && 
                           widget.thumbnailCloudflareUrl!.isNotEmpty &&
                           (widget.thumbnailCloudflareUrl!.startsWith('http://') || 
                            widget.thumbnailCloudflareUrl!.startsWith('https://'));
    
    // Check if we have a Firebase thumbnail URL (highest priority for published videos, only for old format)
    bool isFirebaseThumbnailUrl = _firebaseThumbnailUrl != null && 
                                 _firebaseThumbnailUrl!.isNotEmpty &&
                                 (widget.status == 'published') &&
                                 !widget.isNewFormat;
    
    // If this is an image, handle it differently
    if (widget.isImage) {
      // For new format images, use thumbnailPath directly
      if (widget.isNewFormat && widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
        return _buildNetworkImage(widget.thumbnailPath!);
      }
      
      // For old format images, check Firebase thumbnail first, then other sources
      if (isFirebaseThumbnailUrl) {
        return _buildNetworkImage(_firebaseThumbnailUrl!);
      } else if (isVideoUrl) {
        return _buildNetworkImage(widget.videoPath!);
      } else if (isThumbnailUrl) {
        return _buildNetworkImage(widget.thumbnailPath!);
      } else if (isCloudflareUrl) {
        return _buildNetworkImage(widget.thumbnailCloudflareUrl!);
      }
      
      // If not a URL, try local file (less likely in production use case)
      if (widget.videoPath != null && widget.videoPath!.isNotEmpty) {
        final file = File(widget.videoPath!);
        return FutureBuilder<bool>(
          future: file.exists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingPlaceholder();
            }
            
            final exists = snapshot.data ?? false;
            if (exists) {
              return _buildFileImage(file);
            } else {
              return _tryCloudflareImage();
            }
          },
        );
      }
      return _tryCloudflareImage();
    }
    
    // For videos, try to find the best thumbnail source
    
    // For new format videos, use thumbnailPath directly
    if (widget.isNewFormat && widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
      return _buildNetworkImage(widget.thumbnailPath!);
    }
    
    // For old format videos, check Firebase thumbnail URL first (highest priority for published videos)
    if (isFirebaseThumbnailUrl) {
      return _buildNetworkImage(_firebaseThumbnailUrl!);
    }
    
    // Then check for a dedicated thumbnail URL (Cloudflare or directly in thumbnailPath)
    if (isCloudflareUrl) {
      return _buildNetworkImage(widget.thumbnailCloudflareUrl!);
    } else if (isThumbnailUrl) {
      return _buildNetworkImage(widget.thumbnailPath!);
    }
    
    // Then check for a video that could act as its own thumbnail (especially for cloud videos)
    if (isVideoUrl) {
      // For remote videos, we can still show a preview frame, but it's best to use a dedicated thumbnail
      return _buildNetworkImage(widget.videoPath!, isVideo: true);
    }
    
    // Finally, try local files (less common in production)
    if (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
      final file = File(widget.thumbnailPath!);
      // Check if file exists first
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingPlaceholder();
          }
          
          final exists = snapshot.data ?? false;
          if (exists) {
            return _buildFileImage(file);
          } else {
            return _tryCloudflareImage();
          }
        },
      );
    }
    
    // If we still haven't found a source, try the fallback
    return _tryCloudflareImage();
  }
  
  // Helper to build a network image with proper error handling
  Widget _buildNetworkImage(String url, {bool isVideo = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading network image: $error');
              return _buildPlaceholder(isVideo: isVideo);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildLoadingPlaceholder();
            },
          ),
          _buildGradientOverlay(),
          if (isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // Helper to build a file image with proper error handling
  Widget _buildFileImage(File file) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading file image: $error');
              return _tryCloudflareImage();
            },
          ),
          _buildGradientOverlay(),
        ],
      ),
    );
  }
  
  Widget _tryCloudflareImage() {
    // For new format, thumbnail is already in thumbnailPath
    if (widget.isNewFormat && widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
      return _buildNetworkImage(widget.thumbnailPath!);
    }
    
    // First check if we have a Firebase thumbnail URL (old format only)
    if (_firebaseThumbnailUrl != null && _firebaseThumbnailUrl!.isNotEmpty && !widget.isNewFormat) {
      return _buildNetworkImage(_firebaseThumbnailUrl!);
    }
    
    // Then check if we have any Cloudflare URL
    if (widget.thumbnailCloudflareUrl != null && widget.thumbnailCloudflareUrl!.isNotEmpty) {
      return _buildNetworkImage(widget.thumbnailCloudflareUrl!);
    }
    
    // If we have a videoPath that's a URL and no better thumbnail, use it
    if (widget.videoPath != null && 
        (widget.videoPath!.startsWith('http://') || widget.videoPath!.startsWith('https://'))) {
      return _buildNetworkImage(widget.videoPath!, isVideo: !widget.isImage);
    }
    
    // If nothing works, show placeholder
    return _buildPlaceholder();
  }
  
  Widget _tryCloudflareThumbnail() {
    // Try regular cloudflare URL if thumbnailCloudflareUrl is not available
    if (widget.videoPath != null && widget.videoPath!.contains('cloudflarestorage.com')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              widget.videoPath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading Cloudflare video: $error');
                return _buildPlaceholder();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildLoadingPlaceholder();
              },
            ),
            _buildGradientOverlay(),
          ],
        ),
      );
    }
    
    return _tryLocalThumbnail();
  }
  
  Widget _tryLocalThumbnail() {
    // Try local thumbnail first as it's more reliable based on logs
    if (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty && !widget.thumbnailPath!.startsWith('http')) {
      final file = File(widget.thumbnailPath!);
      // Check if file exists first
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingPlaceholder();
          }
          
          final exists = snapshot.data ?? false;
          if (exists) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      print('Error loading local thumbnail: $error');
                      // If local fails, try Cloudflare as fallback
                      return _tryCloudflareThumbnail();
                    },
                  ),
                  _buildGradientOverlay(),
                ],
              ),
            );
          } else {
            return _tryCloudflareThumbnail();
          }
        },
      );
    }
    
    // If no local path, try Cloudflare
    return _tryCloudflareThumbnail();
  }
  
  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.5),
            ],
            stops: const [0.6, 1.0],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLoadingPlaceholder() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceVariant,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPlaceholder({bool isVideo = false}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            width: widget.width,
            height: widget.height,
            color: theme.colorScheme.surfaceVariant,
            child: Center(
              child: Icon(
                widget.isImage ? Icons.image : (isVideo ? Icons.play_circle_outline : Icons.video_library),
                color: theme.iconTheme.color?.withOpacity(0.5),
                size: 32,
              ),
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                  ],
                  stops: const [0.7, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator if we're loading from Firebase (only for old format)
    if (_isLoading && widget.status == 'published' && widget.videoId != null && widget.userId != null && !widget.isNewFormat) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: _buildLoadingPlaceholder(),
      );
    }
    
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _buildThumbnail(),
    );
  }
}