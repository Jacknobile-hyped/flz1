import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../providers/theme_provider.dart';
import './video_details_page.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import './draft_details_page.dart';
import './scheduled_posts_page.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  final int? initialTabIndex;
  
  const HistoryPage({super.key, this.initialTabIndex});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _videosSubscription;
  StreamSubscription<DatabaseEvent>? _scheduledPostsSubscription;
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showInfo = false;
  bool _isSearchFocused = false;
  late TabController _tabController;
  
  // Add calendar related variables
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _publishedVideosByDay = {};
  
  // Variabile per il controllo della visibilità del selettore settimanale
  bool _isWeekSelectorVisible = true;
  
  // Variabili per la paginazione
  int _currentPage = 1;
  static const int _postsPerPage = 15;
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;
  
  // Variabili per il controllo dello scroll
  final ScrollController _scrollController = ScrollController();
  double _searchBarOpacity = 1.0; // 0.0 = completamente nascosta, 1.0 = completamente visibile
  double _lastScrollOffset = 0;
  
  // Variabili per il filtro account espandibile
  Map<String, bool> _platformExpanded = {}; // Track expanded/collapsed state for platforms
  List<String> _selectedPlatforms = []; // Track selected platform names (can have multiple now)
  List<String> _selectedAccounts = []; // Track selected account IDs
  bool _accountsFilterActive = false; // Track if any account filter is active
  
  // Variabili per il filtro per intervallo di date
  DateTime? _startDate;
  DateTime? _endDate;
  bool _dateFilterActive = false; // Track if date filter is active
  bool _dateFilterExpanded = false; // Track if date filter section is expanded

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Listener per il cambio di tab per resettare la paginazione
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          // Reset pagination when changing tabs
          _currentPage = 1;
          _hasMorePosts = true;
          // Optionally reset filters when changing tabs
          // _selectedPlatform = null;
          // _selectedAccounts.clear();
          // _accountsFilterActive = false;
        });
      }
    });
    
    // Se è specificato un tab iniziale, impostalo dopo un breve delay per assicurarsi che il widget sia completamente costruito
    if (widget.initialTabIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.initialTabIndex! >= 0 && widget.initialTabIndex! < 3) {
          _tabController.animateTo(widget.initialTabIndex!);
        }
      });
    }
    
    // Listener per il controllo dello scroll
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final offset = _scrollController.offset;
        
        // Calcola l'opacità basandosi sull'offset dello scroll
        // La barra inizia a nascondersi dopo 50px e si nasconde completamente dopo 150px
        const startHideOffset = 50.0;
        const endHideOffset = 150.0;
        
        double newOpacity;
        if (offset <= startHideOffset) {
          newOpacity = 1.0;
        } else if (offset >= endHideOffset) {
          newOpacity = 0.0;
        } else {
          // Interpolazione lineare tra 1.0 e 0.0
          newOpacity = 1.0 - (offset - startHideOffset) / (endHideOffset - startHideOffset);
        }
        
        // Aggiorna solo se c'è un cambiamento significativo (per performance)
        if ((_searchBarOpacity - newOpacity).abs() > 0.01) {
          setState(() {
            _searchBarOpacity = newOpacity;
          });
        }
        
        _lastScrollOffset = offset;
      }
    });
    
    // Listener per il focus della search bar
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
    
    _initializeVideosListener();
  }

  @override
  void dispose() {
    _videosSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _initializeVideosListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    print('Initializing videos listener for user: [33m${currentUser.uid}[0m');
    
    final videosRef = _database
        .child('users')
        .child('users')
        .child(currentUser.uid)
        .child('videos');
    final scheduledPostsRef = _database
        .child('users')
        .child('users')
        .child(currentUser.uid)
        .child('scheduled_posts');

    // Prima cancello eventuali subscription precedenti
    _videosSubscription?.cancel();
    _scheduledPostsSubscription?.cancel();

    // Listener per videos
    _videosSubscription = videosRef.onValue.listen((event) {
      if (!mounted) return;
      final List<Map<String, dynamic>> videosList = [];
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        videosList.addAll(data.entries.map((entry) {
          final videoData = entry.value as Map<dynamic, dynamic>;
                      try {
              String status = videoData['status']?.toString() ?? 'published';
              
              // Non escludere più i draft dal database - verranno filtrati nei tab
            
            final publishedAt = videoData['published_at'] as int?;
            final scheduledTime = videoData['scheduled_time'] as int?;
            final fromScheduler = videoData['from_scheduler'] == true;
            final videoId = entry.key?.toString();
            final userId = videoData['user_id']?.toString();
            final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
            // --- LOGICA RICHIESTA ---
            if (isNewFormat) {
              // Se non ci sono errori negli account, status = published
              final accounts = videoData['accounts'] as Map<dynamic, dynamic>? ?? {};
              bool hasError = false;
              accounts.forEach((platform, accountData) {
                if (accountData is Map && accountData['error'] != null && accountData['error'].toString().isNotEmpty) {
                  hasError = true;
                }
              });
              if (!hasError) {
                status = 'published';
              }
            }
            // --- FINE LOGICA RICHIESTA ---
            if (status == 'scheduled') {
              final accounts = videoData['accounts'] as Map<dynamic, dynamic>? ?? {};
              final hasYouTube = accounts.containsKey('YouTube');
              if (hasYouTube && scheduledTime != null) {
                final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
                final now = DateTime.now();
                if (scheduledDateTime.isBefore(now)) {
                  status = 'published';
                } else {
                  return null;
                }
              } else if (!hasYouTube) {
                if (publishedAt == null) {
                  return null;
                } else {
                  status = 'published';
                }
              } else {
                return null;
              }
            }
            if (publishedAt != null && (status == 'scheduled' || fromScheduler)) {
              status = 'published';
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
              'cloudflare_urls': videoData['cloudflare_urls'],
            };
          } catch (e) {
            print('Error processing video: $e');
            return null;
          }
        }).where((video) => video != null).cast<Map<String, dynamic>>());
      }
      // Aggiorno lo stato solo dopo aver letto anche i scheduled_posts
      _fetchAndMergeScheduledPosts(videosList);
    }, onError: (error) {
      print('Error loading videos: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _fetchAndMergeScheduledPosts(List<Map<String, dynamic>> videosList) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final scheduledPostsRef = _database
        .child('users')
        .child('users')
        .child(currentUser.uid)
        .child('scheduled_posts');
    _scheduledPostsSubscription = scheduledPostsRef.onValue.listen((event) {
      if (!mounted) return;
      List<Map<String, dynamic>> scheduledList = [];
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        scheduledList = data.entries.map((entry) {
          final postData = entry.value as Map<dynamic, dynamic>;
          try {
            String status = postData['status']?.toString() ?? 'scheduled';
            final scheduledTime = postData['scheduled_time'] as int?;
            final accounts = postData['accounts'] as Map<dynamic, dynamic>? ?? {};
            final platforms = accounts.keys.map((e) => e.toString().toLowerCase()).toList();
            final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
            final hasYouTube = accounts.containsKey('YouTube');
            if (status == 'scheduled' && isOnlyYouTube && hasYouTube && scheduledTime != null) {
              final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (scheduledDateTime.isBefore(now)) {
                status = 'published';
              } else {
                return null;
              }
            } else {
              // Non mostrare altri scheduled_posts qui
              return null;
            }
            return {
              'id': entry.key,
              'title': postData['title'] ?? '',
              'description': postData['description'] ?? '',
              'platforms': platforms,
              'status': status,
              'timestamp': postData['timestamp'] ?? 0,
              'created_at': postData['created_at'],
              'video_path': postData['video_path'] ?? '',
              'media_url': postData['media_url'],
              'thumbnail_path': postData['thumbnail_path'] ?? '',
              'thumbnail_url': postData['thumbnail_url'],
              'accounts': postData['accounts'] ?? {},
              'user_id': postData['user_id'] ?? '',
              'scheduled_time': postData['scheduled_time'],
              'published_at': null,
              'youtube_video_id': postData['youtube_video_id'],
              'thumbnail_cloudflare_url': postData['thumbnail_cloudflare_url'] ?? '',
              'is_image': postData['is_image'] ?? false,
              'video_duration_seconds': postData['video_duration_seconds'],
              'video_duration_minutes': postData['video_duration_minutes'],
              'video_duration_remaining_seconds': postData['video_duration_remaining_seconds'],
              'cloudflare_urls': postData['cloudflare_urls'],
            };
          } catch (e) {
            print('Error processing scheduled_post: $e');
            return null;
          }
        }).where((post) => post != null).cast<Map<String, dynamic>>().toList();
      }
      // Merge videosList + scheduledList
      final merged = [...videosList, ...scheduledList];
      setState(() {
        _videos = merged
          ..sort((a, b) {
            // Determina se è un video del nuovo formato
            final aVideoId = a['id']?.toString();
            final aUserId = a['user_id']?.toString();
            final aIsNewFormat = aVideoId != null && aUserId != null && aVideoId.contains(aUserId);
            
            final bVideoId = b['id']?.toString();
            final bUserId = b['user_id']?.toString();
            final bIsNewFormat = bVideoId != null && bUserId != null && bVideoId.contains(bUserId);
            
            // Calcola il timestamp per l'ordinamento
            int aTime;
            if (aIsNewFormat) {
              // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
              aTime = a['scheduled_time'] as int? ?? 
                     (a['created_at'] is int ? a['created_at'] : int.tryParse(a['created_at']?.toString() ?? '') ?? 0) ??
                     (a['timestamp'] is int ? a['timestamp'] : int.tryParse(a['timestamp'].toString()) ?? 0);
            } else {
              // Per il vecchio formato: usa timestamp
              aTime = a['timestamp'] is int ? a['timestamp'] : int.tryParse(a['timestamp'].toString()) ?? 0;
            }
            
            int bTime;
            if (bIsNewFormat) {
              // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
              bTime = b['scheduled_time'] as int? ?? 
                     (b['created_at'] is int ? b['created_at'] : int.tryParse(b['created_at']?.toString() ?? '') ?? 0) ??
                     (b['timestamp'] is int ? b['timestamp'] : int.tryParse(b['timestamp'].toString()) ?? 0);
            } else {
              // Per il vecchio formato: usa timestamp
              bTime = b['timestamp'] is int ? b['timestamp'] : int.tryParse(b['timestamp'].toString()) ?? 0;
            }
            
            return bTime.compareTo(aTime); // Ordine decrescente (più recenti prima)
          });
        _isLoading = false;
        // Aggiorna anche la mappa per il calendario (escludi le draft)
        final publishedVideos = _videos.where((video) {
          final status = video['status'] as String? ?? '';
          final publishedAt = video['published_at'] as int?;
          final scheduledTime = video['scheduled_time'] as int?;
          final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
          final platforms = accounts.keys.map((e) => e.toString().toLowerCase()).toList();
          final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
          final hasYouTube = accounts.containsKey('YouTube');
          
          // Escludi le draft dal calendario
          if (status.toLowerCase() == 'draft') return false;
          
          if (status == 'scheduled') {
            if (hasYouTube && scheduledTime != null) {
              final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (isOnlyYouTube) {
                return scheduledDateTime.isBefore(now);
              }
              return publishedAt != null;
            }
            return publishedAt != null;
          }
          return true;
        }).toList();
        _publishedVideosByDay = _groupVideosByDay(publishedVideos);
      });
    });
  }

  Future<void> _refreshVideos() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      // Reset pagination when refreshing
      _currentPage = 1;
      _hasMorePosts = true;
    });

    try {
      // Cancel existing subscription
      await _videosSubscription?.cancel();
      
      // Reinitialize the listener
      _initializeVideosListener();
      
      // Add a small delay to ensure the listener has time to fetch data
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('Error refreshing videos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing videos: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (!mounted || _isLoadingMore || !_hasMorePosts) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    try {
      // Simula un breve delay per mostrare l'animazione di caricamento
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        setState(() {
          _currentPage++;
        });
      }
    } catch (e) {
      print('Error loading more posts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading more posts: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Widget _buildLoadMoreButton(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: ElevatedButton(
          onPressed: _isLoadingMore ? null : _loadMorePosts,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            foregroundColor: theme.colorScheme.primary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          child: _isLoadingMore
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Load More Posts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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
        body: Stack(
          children: [
            // Main content area - no padding, videos can scroll behind floating elements
            SafeArea(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildVideoList(theme),
                  _buildPublishedWithCalendar(theme),  // Now using calendar view for published tab
                  _buildVideoList(theme, onlyDrafts: true),
                ],
              ),
            ),
            
            // Floating header with search and tabs
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              top: -100 + (MediaQuery.of(context).size.height * 0.08 + 100) * _searchBarOpacity,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row with Search bar and Filter button
                    Row(
                      children: [
                        // Search bar with glass effect
                        Expanded(
                          flex: _isSearchFocused ? 1 : 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                  // Effetto vetro sospeso
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.15) 
                                      : Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(25),
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
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onChanged: (value) {
                                    setState(() {
                                      _searchQuery = value;
                                      // Reset pagination when searching
                                      _currentPage = 1;
                                      _hasMorePosts = true;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search videos by text...',
                                    hintStyle: TextStyle(
                                      color: theme.hintColor,
                                      fontSize: 13,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search,
                                      color: theme.colorScheme.primary,
                                      size: 18,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 0,
                                    ),
                                    suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          iconSize: 16,
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              // Reset pagination when clearing search
                                              _currentPage = 1;
                                              _hasMorePosts = true;
                                            });
                                          },
                                          color: theme.hintColor,
                                        )
                                      : null,
                                    isDense: true,
                                    isCollapsed: false,
                                    alignLabelWithHint: true,
                                  ),
                                  textAlignVertical: TextAlignVertical.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Spacing between search and filter (animated)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: _isSearchFocused ? 0 : 12,
                        ),
                        
                        // Filter button (animated)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                          width: _isSearchFocused ? 0 : 42,
                          height: _isSearchFocused ? 0 : 42,
                          child: _isSearchFocused
                              ? const SizedBox.shrink()
                              : GestureDetector(
                          onTap: () {
                            _showPlatformFilterMenu(context);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.15) 
                                      : Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.4),
                                    width: 1,
                                  ),
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
                                child: Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(
                                        Icons.filter_list,
                                        color: (_selectedPlatforms.isNotEmpty || _accountsFilterActive || _dateFilterActive)
                                            ? theme.colorScheme.primary 
                                            : theme.iconTheme.color,
                                        size: 20,
                                      ),
                                      if (_selectedPlatforms.isNotEmpty || _accountsFilterActive || _dateFilterActive)
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Color(0xFF667eea),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isDark ? Color(0xFF121212) : Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                                ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Tab bar with glass effect
                    ClipRRect(
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
                                  transform: GradientRotation(135 * 3.14159 / 180),
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
                                fontSize: 12,
                                color: Colors.transparent, // Nasconde il testo predefinito
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 12,
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
                                              ? Icon(
                                                  Icons.video_library,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
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
                                                  child: Icon(
                                                    Icons.video_library,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? Text('All', style: TextStyle(color: Colors.white))
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
                                                  child: Text('All', style: TextStyle(color: Colors.white)),
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
                                              ? Icon(
                                                  Icons.public,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
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
                                                  child: Icon(
                                                    Icons.public,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? Text('Published', style: TextStyle(color: Colors.white))
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
                                                  child: Text('Published', style: TextStyle(color: Colors.white)),
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
                                              ? Icon(
                                                  Icons.drafts,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
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
                                                  child: Icon(
                                                    Icons.drafts,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? Text('Draft', style: TextStyle(color: Colors.white))
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
                                                  child: Text('Draft', style: TextStyle(color: Colors.white)),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoList(ThemeData theme, {bool onlyPublished = false, bool onlyDrafts = false}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    var filteredVideos = List<Map<String, dynamic>>.from(_videos);
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        final title = (video['title'] as String? ?? '').toLowerCase();
        final description = (video['description'] as String? ?? '').toLowerCase();
        final status = (video['status'] as String? ?? '').toLowerCase();
        final platforms = (video['platforms'] as List<dynamic>? ?? [])
            .map((e) => e.toString().toLowerCase())
            .join(' ');
        return title.contains(query) ||
               description.contains(query) || 
               status.contains(query) || 
               platforms.contains(query);
      }).toList();
    }

    // Apply date range filter
    if (_dateFilterActive && _startDate != null && _endDate != null) {
      filteredVideos = filteredVideos.where((video) {
        // Get video timestamp
        final videoId = video['id']?.toString();
        final userId = video['user_id']?.toString();
        final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
        
        int timestamp;
        if (isNewFormat) {
          // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
          timestamp = video['scheduled_time'] as int? ?? 
                     (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                     (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
        } else {
          // Per il vecchio formato: usa timestamp
          timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
        }
        
        if (timestamp == 0) return false;
        
        final videoDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final dateOnly = DateTime(videoDate.year, videoDate.month, videoDate.day);
        final startDateOnly = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final endDateOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
        
        // Check if video date is within range (inclusive)
        return dateOnly.isAtSameMomentAs(startDateOnly) || 
               dateOnly.isAtSameMomentAs(endDateOnly) ||
               (dateOnly.isAfter(startDateOnly) && dateOnly.isBefore(endDateOnly));
      }).toList();
    }

    // Apply platform or account filter
    if (_selectedPlatforms.isNotEmpty) {
      filteredVideos = filteredVideos.where((video) {
        // Distinzione nuovo/vecchio formato
        final videoId = video['id']?.toString();
        final userId = video['user_id']?.toString();
        final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
        
        List<String> platforms;
        Map<String, dynamic>? accounts;
        
        if (isNewFormat && video['accounts'] is Map) {
          // Nuovo formato: usa le chiavi di accounts
          accounts = Map<String, dynamic>.from(video['accounts'] as Map);
          platforms = accounts.keys.map((e) => e.toString()).toList();
        } else {
          // Vecchio formato: usa platforms
          platforms = List<String>.from(video['platforms'] ?? []);
          // Convert safely from dynamic Map
          final rawAccounts = video['accounts'];
          if (rawAccounts is Map) {
            accounts = Map<String, dynamic>.from(rawAccounts.map((key, value) => MapEntry(key.toString(), value)));
          } else {
            accounts = null;
          }
        }
        
        // Check if any of the selected platforms is in the video's platforms
        bool hasPlatform = platforms.any((platform) => 
          _selectedPlatforms.any((selectedPlatform) => 
            platform.toLowerCase() == selectedPlatform.toLowerCase()
          )
        );
        
        // If account filtering is active, also check for specific accounts
        if (_accountsFilterActive && _selectedAccounts.isNotEmpty && accounts != null) {
          bool hasSelectedAccount = false;
          
          // Check accounts for all selected platforms
          for (final selectedPlatform in _selectedPlatforms) {
            final platformAccounts = accounts[selectedPlatform];
            
            if (platformAccounts != null) {
              if (platformAccounts is Map) {
                // Single account
                final accountId = platformAccounts['account_id']?.toString() ?? 
                                 platformAccounts['id']?.toString() ?? 
                                 platformAccounts['username']?.toString() ?? '';
                if (_selectedAccounts.contains(accountId)) {
                  hasSelectedAccount = true;
                  break;
                }
              } else if (platformAccounts is List) {
                // Multiple accounts
                for (var account in platformAccounts) {
                  if (account is Map) {
                    final accountId = account['account_id']?.toString() ?? 
                                     account['id']?.toString() ?? 
                                     account['username']?.toString() ?? '';
                    if (_selectedAccounts.contains(accountId)) {
                      hasSelectedAccount = true;
                      break;
                    }
                  }
                }
              }
            }
            if (hasSelectedAccount) break;
          }
          
          // Video must have one of the platforms AND at least one selected account
          return hasPlatform && hasSelectedAccount;
        }
        
        // If no account filtering, just check platform
        return hasPlatform;
      }).toList();
    }

    // Apply tab filter
    filteredVideos = filteredVideos.where((video) {
      final status = video['status'] as String? ?? '';
      
      // Se onlyDrafts è true, mostra solo i draft
      if (onlyDrafts) {
        return status.toLowerCase() == 'draft';
      }
      
      // Se onlyPublished è true, mostra solo i pubblicati
      if (onlyPublished) {
        // Escludi esplicitamente i draft
        if (status.toLowerCase() == 'draft') {
          return false;
        }
        
        final publishedAt = video['published_at'] as int?;
        final scheduledTime = video['scheduled_time'] as int?;
        final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
        final hasYouTube = accounts.containsKey('YouTube');
        final platforms = (video['platforms'] as List<dynamic>? ?? [])
            .map((e) => e.toString().toLowerCase())
            .toList();
        final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
        
        if (status == 'scheduled') {
          if (hasYouTube && scheduledTime != null) {
            final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
            final now = DateTime.now();
            if (isOnlyYouTube) {
              return scheduledDateTime.isBefore(now);
            }
            // Se non è solo YouTube, mostra solo se pubblicato
            return publishedAt != null;
          }
          // Per altri casi, mostra solo se pubblicato
          return publishedAt != null;
        }
        return status == 'published';
      }
      
      // Per il tab "All", mostra tutti inclusi i draft
      if (status == 'scheduled') {
        final publishedAt = video['published_at'] as int?;
        final scheduledTime = video['scheduled_time'] as int?;
        final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
        final hasYouTube = accounts.containsKey('YouTube');
        final platforms = (video['platforms'] as List<dynamic>? ?? [])
            .map((e) => e.toString().toLowerCase())
            .toList();
        final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
        if (hasYouTube && scheduledTime != null) {
          final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
          final now = DateTime.now();
          if (isOnlyYouTube) {
            return scheduledDateTime.isBefore(now);
          }
          // Se non è solo YouTube, mostra solo se pubblicato
          return publishedAt != null;
        }
        // Per altri casi, mostra solo se pubblicato
        return publishedAt != null;
      }
      return true;
    }).toList();

    // Filtered videos for display

    if (filteredVideos.isEmpty) {
      // Check if there are any active filters (search, platforms, accounts, dates)
      bool hasActiveFilters = _searchQuery.isNotEmpty || 
                              _selectedPlatforms.isNotEmpty || 
                              _accountsFilterActive || 
                              _dateFilterActive;
      
      if (hasActiveFilters) {
        return Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              ShaderMask(
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
                  'No results found',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try different keywords or filters',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        );
      }
      return _buildEmptyState(theme, isDraft: onlyDrafts);
    }

    // Applica la paginazione solo per il tab "All" (quando non è onlyPublished e non è onlyDrafts)
    List<Map<String, dynamic>> paginatedVideos = filteredVideos;
    bool showLoadMoreButton = false;
    
    if (!onlyPublished && !onlyDrafts) {
      // Per il tab "All", applica la paginazione
      final startIndex = 0;
      final endIndex = _currentPage * _postsPerPage;
      paginatedVideos = filteredVideos.take(endIndex).toList();
      showLoadMoreButton = endIndex < filteredVideos.length;
      
      // Aggiorna lo stato per il bottone "Load More"
      if (mounted) {
        setState(() {
          _hasMorePosts = showLoadMoreButton;
        });
      }
    }

    return RefreshIndicator(
      onRefresh: _refreshVideos,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: 140 + MediaQuery.of(context).size.height * 0.06, // 140px + 3% dell'altezza dello schermo
          left: 20, 
          right: 20, 
          bottom: 90 // Aumentato a 90px (circa 2 cm) per dare più spazio in basso
        ), // Add top padding for floating elements
        itemCount: paginatedVideos.length + (showLoadMoreButton ? 1 : 0),
        itemBuilder: (context, index) {
          // Se è l'ultimo elemento e c'è il bottone "Load More"
          if (showLoadMoreButton && index == paginatedVideos.length) {
            return _buildLoadMoreButton(theme);
          }
          
          final video = paginatedVideos[index];
          return _buildVideoCard(theme, video);
        },
      ),
    );
  }

  Widget _buildVideoCard(ThemeData theme, Map<String, dynamic> video) {
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    // DATA: Calcolo timestamp per visualizzazione usando la stessa logica dell'ordinamento
    int timestamp;
    if (isNewFormat) {
      // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
      timestamp = video['scheduled_time'] as int? ?? 
                 (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                 (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
      // Debug info per formato video
    } else {
      // Per il vecchio formato: usa timestamp
      timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
    }
    
    // STATUS - dichiarato prima del suo utilizzo
    String status = video['status'] as String? ?? 'published';
    final publishedAt = video['published_at'] as int?;
    if (status == 'scheduled' && publishedAt != null) {
      status = 'published';
    }
    
    // Per i video YouTube schedulati, usa scheduled_time se disponibile
    final scheduledTime = video['scheduled_time'] as int?;
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    final hasYouTube = accounts.containsKey('YouTube');
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final timeAgo = _formatTimestamp(dateTime);

    // SOCIAL MEDIA: platforms
    List<String> platforms;
    if (isNewFormat && video['accounts'] is Map) {
      platforms = (video['accounts'] as Map).keys.map((e) => e.toString()).toList();
    } else {
      platforms = List<String>.from(video['platforms'] ?? []);
    }

    // NUMERO ACCOUNT: conta tutti gli account_display_name
    int accountCount = _countTotalAccounts(video, isNewFormat);
    
    // Debug per il conteggio account
    
    final accountText = accountCount > 0 
        ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
        : 'No accounts';

    // Determina se il video è stato schedulato
    final wasScheduled = (publishedAt != null && video['scheduled_time'] != null) || 
                        (status == 'scheduled' && hasYouTube && scheduledTime != null);

    // THUMBNAIL: Gestione corretta per nuovo formato
    final videoPath = isNewFormat 
        ? video['media_url'] as String?
        : video['video_path'] as String?;
    final thumbnailPath = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_path'] as String?;
    final thumbnailCloudflareUrl = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_cloudflare_url'] as String?;
    
    // Debug per thumbnail

    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.28),
            borderRadius: BorderRadius.circular(12),
            // Bordo con effetto vetro più sottile
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.4),
              width: 1,
            ),
            // Ombre per effetto profondità e vetro
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.12),
                blurRadius: isDark ? 22 : 18,
                spreadRadius: isDark ? 0.5 : 0,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.55),
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
                      Colors.white.withOpacity(0.16),
                      Colors.white.withOpacity(0.08),
                    ]
                  : [
                      Colors.white.withOpacity(0.34),
                      Colors.white.withOpacity(0.24),
                    ],
            ),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => (video['status'] as String? ?? 'published') == 'draft'
                      ? DraftDetailsPage(video: video)
                      : VideoDetailsPage(video: video),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Thumbnail
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
                    width: 150,
                    height: 110,
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
                            isImage: video['is_image'] == true,
                            videoId: video['id'] as String?,
                            userId: video['user_id'] as String?,
                            status: video['status'] as String? ?? 'published',
                            isNewFormat: isNewFormat, // Passa flag
                          )
                        else
                          Container(
                            color: theme.colorScheme.surfaceVariant,
                            child: Center(
                              child: Icon(
                                video['is_image'] == true ? Icons.image : Icons.video_library,
                                size: 28,
                                color: theme.iconTheme.color?.withOpacity(0.5),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: _buildStaticDurationBadge(video),
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
                          maxWidth: MediaQuery.of(context).size.width - 210,
                        ),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              if (platforms.length <= 4)
                                ...platforms.map((platform) => Padding(
                                  padding: const EdgeInsets.only(right: 7),
                                  child: _buildPlatformLogo(platform.toString()),
                                ))
                              else
                                ...[
                                  ...platforms.take(4).map((platform) => Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: _buildPlatformLogo(platform.toString()),
                                  )),
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
                    const SizedBox(height: 15),
                    // Account info
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
                    const SizedBox(height: 5),
                    // Timestamp con status badge
                    Row(
                      children: [
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
                            child: Text(
                              wasScheduled ? 'Scheduled · $timeAgo' : timeAgo,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: video['status'] as String? ?? 'published', wasScheduled: wasScheduled),
                      ],
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to build platform logos from assets
  Widget _buildPlatformLogo(String platform) {
    if (platform == 'All') {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            transform: GradientRotation(135 * 3.14159 / 180),
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.apps,
          color: Colors.white,
          size: 16,
        ),
      );
    }
    
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
  
  // Nuovo metodo per mostrare la durata in modo statico
  Widget _buildStaticDurationBadge(Map<String, dynamic> video) {
    // Controlla se è un carosello (ha cloudflare_urls con più di una voce)
    final cloudflareUrls = video['cloudflare_urls'];
    final bool isCarousel = cloudflareUrls != null && 
                           (cloudflareUrls is List && (cloudflareUrls as List).length > 1 ||
                            cloudflareUrls is Map && (cloudflareUrls as Map).length > 1);
    
    // Se è un carosello, mostra "CAROUSEL"
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
    if (video['is_image'] == true) {
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
    
    // Controlla se abbiamo i dati della durata dal database
    final durationSeconds = video['video_duration_seconds'] as int?;
    final durationMinutes = video['video_duration_minutes'] as int?;
    final durationRemainingSeconds = video['video_duration_remaining_seconds'] as int?;
    
    if (durationSeconds != null && durationMinutes != null && durationRemainingSeconds != null) {
      // Usa i dati reali dal database
      duration = '$durationMinutes:${durationRemainingSeconds.toString().padLeft(2, '0')}';
    } else {
      // Fallback: usa una durata basata sull'ID del video (per compatibilità con video esistenti)
      final idString = video['id'] as String? ?? '';
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

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    
    // Se è passato più di un giorno, mostra la data in formato gg/mm/anno
    if (difference.inDays > 1) {
      return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}';
    } else if (difference.inDays == 1) {
      return '1 day ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildStat(ThemeData theme, String value, String label) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? Colors.grey[800] : theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, {bool isDraft = false}) {
    return Center(
      child: Transform.translate(
        offset: const Offset(0, 40), // Sposta 2 cm più in basso (circa 80px totali)
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea), // Colore iniziale: blu violaceo
                  Color(0xFF764ba2), // Colore finale: viola
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF667eea).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isDraft ? Icons.drafts_rounded : Icons.video_library_rounded,
              size: 70,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
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
              isDraft ? 'No Draft Videos' : 'No Videos Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 280,
            child: Text(
              isDraft 
                ? 'Save your videos as drafts to edit and publish them later.' 
                : 'When you upload content, it will appear here for easy management.',
              style: TextStyle(
                fontSize: 14,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea), // Colore iniziale: blu violaceo
                  Color(0xFF764ba2), // Colore finale: viola
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF667eea).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/upload');
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(isDraft ? 'Create Draft' : 'Upload Content'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                )
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildInfoDropdown() {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'About Content History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            'Published Content',
            'View all your published videos across different platforms.',
            Icons.public,
          ),
          _buildInfoItem(
            'Drafts',
            'Access and manage your saved draft videos.',
            Icons.drafts,
          ),
          _buildInfoItem(
            'Content Details',
            'View detailed information about each video, including platforms and engagement.',
            Icons.info,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description, IconData icon) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Add this new method to build the published content with calendar view
  Widget _buildPublishedWithCalendar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    var filteredVideos = _videos.where((video) {
      final status = video['status'] as String? ?? '';
      final publishedAt = video['published_at'] as int?;
      final scheduledTime = video['scheduled_time'] as int?;
      final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
      final hasYouTube = accounts.containsKey('YouTube');
      
      // Exclude draft videos from published tab
      if (status.toLowerCase() == 'draft') return false;
      
      // Show regular published posts
      if (status == 'published') return true;
      
      // Show YouTube scheduled posts with past scheduled time
      if (status == 'scheduled' && hasYouTube && scheduledTime != null) {
        final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
        final now = DateTime.now();
        return scheduledDateTime.isBefore(now);
      }
      
      // Show other scheduled posts that have been published
      if (status == 'scheduled' && publishedAt != null) return true;
      
      return false;
    }).toList();
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        final title = (video['title'] as String? ?? '').toLowerCase();
        final description = (video['description'] as String? ?? '').toLowerCase();
        final platforms = (video['platforms'] as List<dynamic>? ?? [])
            .map((e) => e.toString().toLowerCase())
            .join(' ');
        return title.contains(query) ||
               description.contains(query) || 
               platforms.contains(query);
      }).toList();
    }

    // Apply date range filter
    if (_dateFilterActive && _startDate != null && _endDate != null) {
      filteredVideos = filteredVideos.where((video) {
        // Get video timestamp
        final videoId = video['id']?.toString();
        final userId = video['user_id']?.toString();
        final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
        
        int timestamp;
        if (isNewFormat) {
          // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
          timestamp = video['scheduled_time'] as int? ?? 
                     (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                     (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
        } else {
          // Per il vecchio formato: usa timestamp
          timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
        }
        
        if (timestamp == 0) return false;
        
        final videoDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final dateOnly = DateTime(videoDate.year, videoDate.month, videoDate.day);
        final startDateOnly = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final endDateOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
        
        // Check if video date is within range (inclusive)
        return dateOnly.isAtSameMomentAs(startDateOnly) || 
               dateOnly.isAtSameMomentAs(endDateOnly) ||
               (dateOnly.isAfter(startDateOnly) && dateOnly.isBefore(endDateOnly));
      }).toList();
    }

    // Apply platform or account filter
    if (_selectedPlatforms.isNotEmpty) {
      filteredVideos = filteredVideos.where((video) {
        // Distinzione nuovo/vecchio formato
        final videoId = video['id']?.toString();
        final userId = video['user_id']?.toString();
        final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
        
        List<String> platforms;
        Map<String, dynamic>? accounts;
        
        if (isNewFormat && video['accounts'] is Map) {
          // Nuovo formato: usa le chiavi di accounts
          accounts = Map<String, dynamic>.from(video['accounts'] as Map);
          platforms = accounts.keys.map((e) => e.toString()).toList();
        } else {
          // Vecchio formato: usa platforms
          platforms = List<String>.from(video['platforms'] ?? []);
          // Convert safely from dynamic Map
          final rawAccounts = video['accounts'];
          if (rawAccounts is Map) {
            accounts = Map<String, dynamic>.from(rawAccounts.map((key, value) => MapEntry(key.toString(), value)));
          } else {
            accounts = null;
          }
        }
        
        // Check if any of the selected platforms is in the video's platforms
        bool hasPlatform = platforms.any((platform) => 
          _selectedPlatforms.any((selectedPlatform) => 
            platform.toLowerCase() == selectedPlatform.toLowerCase()
          )
        );
        
        // If account filtering is active, also check for specific accounts
        if (_accountsFilterActive && _selectedAccounts.isNotEmpty && accounts != null) {
          bool hasSelectedAccount = false;
          
          // Check accounts for all selected platforms
          for (final selectedPlatform in _selectedPlatforms) {
            final platformAccounts = accounts[selectedPlatform];
            
            if (platformAccounts != null) {
              if (platformAccounts is Map) {
                // Single account
                final accountId = platformAccounts['account_id']?.toString() ?? 
                                 platformAccounts['id']?.toString() ?? 
                                 platformAccounts['username']?.toString() ?? '';
                if (_selectedAccounts.contains(accountId)) {
                  hasSelectedAccount = true;
                  break;
                }
              } else if (platformAccounts is List) {
                // Multiple accounts
                for (var account in platformAccounts) {
                  if (account is Map) {
                    final accountId = account['account_id']?.toString() ?? 
                                     account['id']?.toString() ?? 
                                     account['username']?.toString() ?? '';
                    if (_selectedAccounts.contains(accountId)) {
                      hasSelectedAccount = true;
                      break;
                    }
                  }
                }
              }
            }
            if (hasSelectedAccount) break;
          }
          
          // Video must have one of the platforms AND at least one selected account
          return hasPlatform && hasSelectedAccount;
        }
        
        // If no account filtering, just check platform
        return hasPlatform;
      }).toList();
    }
    
    if (filteredVideos.isEmpty) {
      // Check if there are any active filters (search, platforms, accounts, dates)
      bool hasActiveFilters = _searchQuery.isNotEmpty || 
                              _selectedPlatforms.isNotEmpty || 
                              _accountsFilterActive || 
                              _dateFilterActive;
      
      if (hasActiveFilters) {
        return Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              ShaderMask(
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
                  'No results found',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try different keywords or filters',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        );
      }
      return _buildEmptyState(theme, isDraft: false);
    }
    
    // Generate week days starting from Monday of current week
    List<DateTime> weekDays = [];
    DateTime startOfWeek = _focusedDay.subtract(Duration(days: _focusedDay.weekday - 1));
    for (int i = 0; i < 7; i++) {
      weekDays.add(startOfWeek.add(Duration(days: i)));
    }
    
    // Calculate video counts for each day of the week
    Map<DateTime, int> videoCountsByDay = {};
    for (DateTime day in weekDays) {
      final dateOnly = DateTime(day.year, day.month, day.day);
      videoCountsByDay[dateOnly] = _publishedVideosByDay[dateOnly]?.length ?? 0;
    }
    
    // Get today's date for navigation restriction
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    
    return RefreshIndicator(
      onRefresh: _refreshVideos,
      child: Column(
        children: [
          // Container per il selettore settimanale o vista compatta
          AnimatedContainer(
            duration: Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            margin: EdgeInsets.only(
              top: (MediaQuery.of(context).size.height * 0.06 + 20) + 
                   ((100 + MediaQuery.of(context).size.height * 0.11) - (MediaQuery.of(context).size.height * 0.06 + 20)) * _searchBarOpacity,
              left: 16, 
              right: 16, 
              bottom: 4
            ),
            height: _isWeekSelectorVisible ? null : 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 12), // Added bottom padding
                  decoration: BoxDecoration(
                    // Effetto vetro sospeso
                    color: isDark 
                        ? Colors.white.withOpacity(0.15) 
                        : Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
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
                  child: _isWeekSelectorVisible 
                      ? _buildExpandedWeekSelector(theme, weekDays, videoCountsByDay, today)
                      : _buildCollapsedWeekSelector(theme),
                ),
              ),
            ),
          ),
          
          // Animazione per lo spazio dopo il selettore
          AnimatedContainer(
            duration: Duration(milliseconds: 300),
            height: 4,
          ),
          
          // List of videos for the selected day
          Expanded(
            child: _buildSelectedDayVideos(theme),
          ),
        ],
      ),
    );
  }
  
  // Widget per il selettore settimanale espanso
  Widget _buildExpandedWeekSelector(ThemeData theme, List<DateTime> weekDays, 
      Map<DateTime, int> videoCountsByDay, DateTime today) {
    final isDark = theme.brightness == Brightness.dark;
    
    return AnimatedOpacity(
      opacity: 1.0,
      duration: Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Column(
        children: [
          // Header row con mese e pulsanti
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Left arrow
              IconButton(
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.chevron_left, size: 18),
                onPressed: () {
                  setState(() {
                    _focusedDay = _focusedDay.subtract(const Duration(days: 7));
                    // If the selected day is no longer visible or is in the future, adjust it
                    final endOfDisplayedWeek = _focusedDay.add(Duration(days: 6));
                    if (_selectedDay.isAfter(endOfDisplayedWeek) || 
                        _selectedDay.isBefore(_focusedDay) ||
                        _isDateInFuture(_selectedDay)) {
                      // Find the most recent non-future day in the visible week
                      for (int i = 6; i >= 0; i--) {
                        final day = _focusedDay.add(Duration(days: i));
                        if (!_isDateInFuture(day)) {
                          _selectedDay = day;
                          break;
                        }
                      }
                    }
                  });
                },
              ),
            
              // Month indicator - clickable with integrated calendar icon
              InkWell(
                onTap: () {
                  // Open the full month calendar view
                  _showMonthCalendarDialog(context, theme);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.1),
                        Color(0xFF764ba2).withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ShaderMask(
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
                          DateFormat('MMM yyyy').format(_focusedDay),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 4),
                      ShaderMask(
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
                          Icons.calendar_month_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Right arrow
              IconButton(
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.chevron_right, 
                  size: 18,
                  // Gray out the icon if we're already showing the current week
                  color: _weekContainsCurrentOrFutureDays(_focusedDay)
                      ? theme.disabledColor
                      : theme.iconTheme.color,
                ),
                onPressed: _weekContainsCurrentOrFutureDays(_focusedDay)
                    ? null // Disable if we're showing a week that includes today
                    : () {
                        setState(() {
                          _focusedDay = _focusedDay.add(const Duration(days: 7));
                          // If the selected day is no longer visible or is in the future, adjust it
                          if (_selectedDay.isBefore(_focusedDay) || 
                              _selectedDay.isAfter(_focusedDay.add(Duration(days: 6))) ||
                              _isDateInFuture(_selectedDay)) {
                            // Find the most recent non-future day in the visible week
                            for (int i = 6; i >= 0; i--) {
                              final day = _focusedDay.add(Duration(days: i));
                              if (!_isDateInFuture(day)) {
                                _selectedDay = day;
                                break;
                              }
                            }
                          }
                        });
                      },
              ),
              
              // Spaziatore
              Spacer(),
              
              // Pulsante per collassare
              IconButton(
                icon: Icon(
                  Icons.expand_less_rounded,
                  color: Color(0xFF667eea),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _isWeekSelectorVisible = false;
                  });
                },
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          
          // Week day selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(weekDays.length, (index) {
              final day = weekDays[index];
              final isSelected = isSameDay(day, _selectedDay);
              final isToday = isSameDay(day, today);
              final isFuture = _isDateInFuture(day);
              final dateOnly = DateTime(day.year, day.month, day.day);
              final videoCount = videoCountsByDay[dateOnly] ?? 0;
              
              // Day names (M, T, W, etc.) - even shorter
              String dayName = DateFormat('E').format(day).substring(0, 1);
              
              return GestureDetector(
                onTap: isFuture ? null : () {
                  setState(() {
                    _selectedDay = day;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36, // Slightly wider
                  height: 64, // Much taller to avoid overflow
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? null
                        : isFuture
                            ? theme.disabledColor.withOpacity(0.1)
                            : theme.cardColor,
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
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isSelected && !isFuture
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
                              : isFuture
                                  ? theme.disabledColor
                                  : theme.textTheme.bodySmall?.color,
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
                              : isFuture
                                  ? theme.disabledColor
                                  : isToday
                                      ? Color(0xFF667eea)
                                      : theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      
                      // Video count indicator or placeholder
                      Container(
                        width: 14, 
                        height: 14,
                        decoration: videoCount > 0 && !isFuture
                          ? BoxDecoration(
                              color: isSelected 
                                  ? Colors.white.withOpacity(0.3) 
                                  : Color(0xFF667eea).withOpacity(0.1),
                              shape: BoxShape.circle,
                            )
                          : null,
                        child: videoCount > 0 && !isFuture
                          ? Center(
                              child: Text(
                                videoCount.toString(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected 
                                      ? Colors.white 
                                      : Color(0xFF667eea),
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
    );
  }
  
  // Widget per il selettore compatto (quando è chiuso)
  Widget _buildCollapsedWeekSelector(ThemeData theme) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: Duration(milliseconds: 250),
      curve: Curves.easeInOut,
              child: Padding(
          padding: const EdgeInsets.only(top: 6, right: 16), // Ridotto il padding destro
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end, // Allinea tutto a destra
            crossAxisAlignment: CrossAxisAlignment.center, // Centra verticalmente
            children: [
              // Data attualmente selezionata
              Text(
                'Published on ${DateFormat('d MMMM yyyy').format(_selectedDay)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667eea),
                ),
              ),
              
              const SizedBox(width: 16), // Spazio tra testo e icona
              
              // Pulsante per espandere - ora posizionato a destra e centrato verticalmente
              IconButton(
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: Color(0xFF667eea),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _isWeekSelectorVisible = true;
                  });
                },
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildSelectedDayVideos(ThemeData theme) {
    final videosForSelectedDay = _getVideosForDay(_selectedDay);
    final dateString = DateFormat('yyyy-MM-dd').format(_selectedDay);
    
    // Debug info about all available days with videos
    
    if (videosForSelectedDay.isEmpty) {
      return Center(
        child: Transform.translate(
          offset: const Offset(0, 0), // Move up by 4 cm (approximately 160px)
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.calendar_today_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No content published on',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 4),
              ShaderMask(
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
                  DateFormat('EEE, MMM d, yyyy').format(_selectedDay),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: 10 + 10 * _searchBarOpacity, // Riduce il padding quando la search bar è nascosta (10 quando nascosta, 20 quando visibile)
        left: 16, 
        right: 16, 
        bottom: 88
      ),
      itemCount: videosForSelectedDay.length,
      itemBuilder: (context, index) {
        final video = videosForSelectedDay[index];
        return _buildVideoCard(theme, video);
      },
    );
  }

  // Helper method to group videos by day for calendar view
  Map<DateTime, List<Map<String, dynamic>>> _groupVideosByDay(List<Map<String, dynamic>> videos) {
    Map<DateTime, List<Map<String, dynamic>>> videosByDay = {};
    // Grouping videos by day
    
    for (final video in videos) {
      try {
        // Determina se è un video del nuovo formato
        final videoId = video['id']?.toString();
        final userId = video['user_id']?.toString();
        final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
        
        // Calcola il timestamp usando la stessa logica dell'ordinamento
        int timestamp;
        if (isNewFormat) {
          // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
          timestamp = video['scheduled_time'] as int? ?? 
                     (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                     (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
        } else {
          // Per il vecchio formato: usa timestamp
          timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
        }
        

            
        if (timestamp <= 0) {
          print('Invalid timestamp for video: ${video['id']}, title: ${video['title']}');
          continue;
        }
        
        final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
        
        if (videosByDay[dateOnly] == null) {
          videosByDay[dateOnly] = [];
        }
        videosByDay[dateOnly]!.add(video);
      } catch (e) {
        print('Error processing video for calendar: $e');
      }
    }
    
    print('Grouped videos into ${videosByDay.length} days');
    return videosByDay;
  }
  
  // Get videos for a specific day
  List<Map<String, dynamic>> _getVideosForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    final videos = _publishedVideosByDay[dateOnly] ?? [];
    return videos;
  }
  
  // Check if a date is in the future
  bool _isDateInFuture(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider only strictly future days as "future"
    return compareDate.isAfter(today);
  }
  
  // Check if a date is in the past (not including today)
  bool _isDateInPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider strictly past days (before today) as "past"
    return compareDate.isBefore(today);
  }
  
  // Check if a week contains today or future dates
  bool _weekContainsCurrentOrFutureDays(DateTime weekStart) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = weekStart.add(Duration(days: 6));
    
    // If the end of the week is on or after today, the week contains today or future days
    return !weekEnd.isBefore(today);
  }

  void _showMonthCalendarDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) {
        return PublishedMonthCalendarPage(
          focusedMonth: _focusedDay,
          events: _publishedVideosByDay,
        );
      },
    ).then((selectedDay) {
      // Se l'utente ha selezionato un giorno, aggiorniamo la vista settimanale
      if (selectedDay != null && selectedDay is DateTime) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = selectedDay;
        });
      }
    });
  }
  
  /// Conta il numero totale di account in un video
  int _countTotalAccounts(Map<String, dynamic> video, bool isNewFormat) {
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    int totalCount = 0;
    
    if (accounts.isEmpty) return 0;
    
    // Counting accounts for format
    
    if (isNewFormat) {
      // Nel nuovo formato, ogni piattaforma ha un account
      // Ma potrebbero esserci più account per piattaforma in futuro
      accounts.forEach((platform, accountData) {
        if (accountData is Map) {
          // Se accountData è un Map, conta 1 account per piattaforma
          totalCount += 1;
        } else if (accountData is List) {
          // Se accountData è una List, conta ogni elemento
          totalCount += accountData.length;
        } else if (accountData != null) {
          // Se accountData non è null, conta 1
          totalCount += 1;
        }
      });
    } else {
      // Vecchio formato: conta tutti gli account in tutte le piattaforme
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
    
    // Total account count
    return totalCount;
  }
  
  /// Shows platform filter menu with expandable accounts
  void _showPlatformFilterMenu(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final List<String> platforms = [
      'All',
      'YouTube',
      'TikTok',
      'Instagram',
      'Facebook',
      'Twitter',
      'Threads',
    ];
    
    // Filter out TikTok and Twitter from display
    final List<String> visiblePlatforms = platforms.where((platform) => 
      platform != 'TikTok' && platform != 'Twitter'
    ).toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
        return ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: isDark 
                    ? Color(0xFF1E1E1E) 
                    : Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      margin: EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    
                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Center(
                        child: Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                        
                        // Date range filter
                        _buildDateRangeFilter(context, theme, isDark, setModalState),
                        
                        const SizedBox(height: 12),
                    
                    // Platform list - with flexible height
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: visiblePlatforms.length,
                        itemBuilder: (context, index) {
                          final platform = visiblePlatforms[index];
                          final isSelected = _selectedPlatforms.contains(platform) || 
                                            (_selectedPlatforms.isEmpty && platform == 'All');
                              
                              return _buildPlatformFilterItem(
                                context, 
                                theme, 
                                platform, 
                                isSelected, 
                                isDark,
                                setModalState, // Pass the setModalState function
                              );
                            },
                          ),
                        ),
                        
                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  // New method to build platform filter item with expandable accounts
  Widget _buildPlatformFilterItem(
    BuildContext context,
    ThemeData theme,
    String platform,
    bool isSelectedOriginal,
    bool isDark,
    StateSetter setModalState,
  ) {
    final isAllPlatform = platform == 'All';
    final isExpanded = _platformExpanded[platform] ?? false;
    
    // Recalculate if this platform is actually selected
    final isSelected = isSelectedOriginal || (!isAllPlatform && _selectedPlatforms.contains(platform));
    
    return Column(
      children: [
        InkWell(
                            onTap: () {
                              setState(() {
                                if (platform == 'All') {
                _selectedPlatforms.clear();
                _selectedAccounts.clear();
                _accountsFilterActive = false;
                Navigator.pop(context);
              } else if (isExpanded) {
                // If already expanded, close it
                _platformExpanded[platform] = false;
                                } else {
                // If not expanded, close all others first, then expand it
                // Close all platforms first
                _platformExpanded.forEach((key, value) {
                  if (value == true) {
                    _platformExpanded[key] = false;
                  }
                });
                // Now expand this one
                _platformExpanded[platform] = true;
                                }
                                // Reset pagination when filtering
                                _currentPage = 1;
                                _hasMorePosts = true;
                              });
            setModalState(() {}); // Update the modal state
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? (isDark ? Color(0xFF667eea).withOpacity(0.1) : Color(0xFF667eea).withOpacity(0.05))
                                    : Colors.transparent,
                              ),
                              child: Row(
                                children: [
                                  // Platform logo
                                  _buildPlatformLogo(platform),
                                  SizedBox(width: 16),
                                  
                                  // Platform name
                                  Expanded(
                                    child: Text(
                                      platform,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        color: isSelected 
                                            ? theme.colorScheme.primary 
                                            : theme.textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ),
                                  
                // Platform selection icon or Expand/Collapse icon
                if (!isAllPlatform)
                  Row(
                    children: [
                      // Platform selection button
                      InkWell(
                        onTap: () {
                          setState(() {
                            // Toggle platform selection (multiple platforms allowed)
                            if (_selectedPlatforms.contains(platform)) {
                              _selectedPlatforms.remove(platform);
                            } else {
                              _selectedPlatforms.add(platform);
                            }
                            _selectedAccounts.clear(); // Clear specific account selection
                            _accountsFilterActive = false;
                            
                            // Reset pagination when filtering
                            _currentPage = 1;
                            _hasMorePosts = true;
                          });
                          setModalState(() {}); // Update the modal state
                        },
                        child: Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
                              width: 1.5,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : Icon(
                                  Icons.circle_outlined,
                                  color: theme.iconTheme.color?.withOpacity(0.5),
                                  size: 14,
                                ),
                        ),
                      ),
                      SizedBox(width: 8),
                      // Expand/Collapse button
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              // If already expanded, close it
                              _platformExpanded[platform] = false;
                            } else {
                              // If not expanded, close all others first, then expand it
                              // Close all platforms first
                              _platformExpanded.forEach((key, value) {
                                if (value == true) {
                                  _platformExpanded[key] = false;
                                }
                              });
                              // Now expand this one
                              _platformExpanded[platform] = true;
                            }
                          });
                          setModalState(() {}); // Update the modal state
                        },
                        child: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: theme.iconTheme.color,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                
                // Check icon for All (only shown when selected)
                if (isAllPlatform && isSelected)
                                    ShaderMask(
                                      shaderCallback: (Rect bounds) {
                                        return LinearGradient(
                                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          transform: GradientRotation(135 * 3.14159 / 180),
                                        ).createShader(bounds);
                                      },
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                ],
                              ),
                            ),
        ),
        
        // Expanded accounts list with animation
        if (!isAllPlatform)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: isExpanded
                ? AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: isExpanded ? 1.0 : 0.0,
                    child: _buildPlatformAccounts(context, theme, platform, isDark, setModalState),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
  
  // New method to build date range filter
  Widget _buildDateRangeFilter(BuildContext context, ThemeData theme, bool isDark, StateSetter setModalState) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: _dateFilterActive
            ? LinearGradient(
                colors: isDark
                    ? [
                        Color(0xFF667eea).withOpacity(0.25),
                        Color(0xFF764ba2).withOpacity(0.25),
                      ]
                    : [
                        Color(0xFF667eea).withOpacity(0.12),
                        Color(0xFF764ba2).withOpacity(0.12),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _dateFilterActive
            ? null
            : (isDark ? Color(0xFF1E1E1E) : Color(0xFFF9F9F9)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _dateFilterActive
              ? Color(0xFF667eea).withOpacity(0.4)
              : theme.dividerColor.withOpacity(0.5),
          width: _dateFilterActive ? 2 : 1.5,
        ),
        boxShadow: _dateFilterActive
            ? [
                BoxShadow(
                  color: Color(0xFF667eea).withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: Container(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _dateFilterExpanded = !_dateFilterExpanded;
                    });
                    setModalState(() {});
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: _dateFilterActive
                              ? LinearGradient(
                                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: _dateFilterActive
                              ? null
                              : (isDark ? Color(0xFF2A2A2A) : Color(0xFFEAEAEA)),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _dateFilterActive
                              ? [
                                  BoxShadow(
                                    color: Color(0xFF667eea).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Icon(
                          Icons.calendar_today_rounded,
                          size: 20,
                          color: _dateFilterActive 
                              ? Colors.white
                              : theme.iconTheme.color?.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date Range',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _dateFilterActive
                                    ? theme.colorScheme.primary
                                    : theme.textTheme.bodyLarge?.color?.withOpacity(0.9),
                              ),
                            ),
                            if (_dateFilterActive && _startDate != null && _endDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Expand/Collapse icon
                      Icon(
                        _dateFilterExpanded ? Icons.expand_less : Icons.expand_more,
                        color: theme.iconTheme.color,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      // Clear button (only show when active)
                      if (_dateFilterActive)
                        InkWell(
                          onTap: () {
                            setState(() {
                              _startDate = null;
                              _endDate = null;
                              _dateFilterActive = false;
                              _currentPage = 1;
                              _hasMorePosts = true;
                            });
                            setModalState(() {});
                          },
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Expandable content with animation
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  child: _dateFilterExpanded
                      ? AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: 1.0,
                          child: Column(
                            children: [
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark ? Color(0xFF151515) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.dividerColor.withOpacity(0.3),
                                  ),
                                ),
                                padding: EdgeInsets.all(4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildDateSelector(
                                        context, theme, isDark, setModalState,
                                        'From',
                                        _startDate,
                                        (date) {
                                          setState(() {
                                            _startDate = date;
                                            if (_startDate != null && _endDate != null) {
                                              _dateFilterActive = true;
                                            }
                                          });
                                          setModalState(() {});
                                        },
                                        maxDate: _endDate,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 60,
                                      color: theme.dividerColor.withOpacity(0.2),
                                    ),
                                    Expanded(
                                      child: _buildDateSelector(
                                        context, theme, isDark, setModalState,
                                        'To',
                                        _endDate,
                                        (date) {
                                          setState(() {
                                            _endDate = date;
                                            if (_startDate != null && _endDate != null) {
                                              _dateFilterActive = true;
                                            }
                                          });
                                          setModalState(() {});
                                        },
                                        minDate: _startDate,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildDateSelector(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    StateSetter setModalState,
    String label,
    DateTime? selectedDate,
    Function(DateTime) onDateSelected,
    {DateTime? minDate, DateTime? maxDate}
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? (minDate ?? DateTime.now().subtract(Duration(days: 7))),
          firstDate: minDate ?? DateTime(2020),
          lastDate: maxDate ?? DateTime.now(),
        );
        if (picked != null) {
          onDateSelected(picked);
          setModalState(() {});
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selectedDate != null
                  ? DateFormat('MMM dd, yyyy').format(selectedDate!)
                  : 'Select date',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selectedDate != null
                    ? theme.textTheme.bodyLarge?.color
                    : theme.hintColor.withOpacity(0.6),
              ),
            ),
          ],
            ),
          ),
        );
  }
  
  // New method to build accounts list for a platform
  Widget _buildPlatformAccounts(BuildContext context, ThemeData theme, String platform, bool isDark, StateSetter setModalState) {
    // Get all unique accounts for this platform from all videos
    Set<String> accountSet = {};
    Map<String, Map<String, dynamic>> accountDetails = {};
    
    for (var video in _videos) {
      final videoId = video['id']?.toString();
      final userId = video['user_id']?.toString();
      final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
      
      List<String> platforms;
      Map<String, dynamic>? accounts;
      
      if (isNewFormat && video['accounts'] is Map) {
        accounts = Map<String, dynamic>.from(video['accounts'] as Map);
        platforms = accounts.keys.map((e) => e.toString()).toList();
      } else {
        platforms = List<String>.from(video['platforms'] ?? []);
        // Convert safely from dynamic Map
        final rawAccounts = video['accounts'];
        if (rawAccounts is Map) {
          accounts = Map<String, dynamic>.from(rawAccounts.map((key, value) => MapEntry(key.toString(), value)));
        } else {
          accounts = null;
        }
      }
      
      // Check if this video has the platform
      if (platforms.any((p) => p.toLowerCase() == platform.toLowerCase()) && accounts != null) {
        // Get accounts for this platform
        final rawPlatformAccounts = accounts[platform];
        
        if (rawPlatformAccounts != null) {
          if (rawPlatformAccounts is Map) {
            // Single account or Map structure - convert to Map<String, dynamic>
            final platformAccounts = Map<String, dynamic>.from(rawPlatformAccounts.map((key, value) => MapEntry(key.toString(), value)));
            
            final accountId = platformAccounts['account_id']?.toString() ?? 
                             platformAccounts['id']?.toString() ?? 
                             platformAccounts['username']?.toString() ?? '';
            
            if (accountId.isNotEmpty) {
              accountSet.add(accountId);
              if (!accountDetails.containsKey(accountId)) {
                accountDetails[accountId] = {
                  'display_name': platformAccounts['account_display_name'] ?? 
                                  platformAccounts['display_name'] ?? 
                                  platformAccounts['username'] ?? accountId,
                  'username': platformAccounts['username'] ?? accountId,
                  'profile_image_url': platformAccounts['account_profile_image_url'] ??
                                      platformAccounts['profile_image_url'] ??
                                      platformAccounts['thumbnail_url'],
                };
              }
            }
          } else if (rawPlatformAccounts is List) {
            // Multiple accounts
            for (var account in rawPlatformAccounts) {
              if (account is Map) {
                // Convert to Map<String, dynamic>
                final accountMap = Map<String, dynamic>.from(account.map((key, value) => MapEntry(key.toString(), value)));
                
                final accountId = accountMap['account_id']?.toString() ?? 
                                 accountMap['id']?.toString() ?? 
                                 accountMap['username']?.toString() ?? '';
                
                if (accountId.isNotEmpty) {
                  accountSet.add(accountId);
                  if (!accountDetails.containsKey(accountId)) {
                    accountDetails[accountId] = {
                      'display_name': accountMap['account_display_name'] ?? 
                                      accountMap['display_name'] ?? 
                                      accountMap['username'] ?? accountId,
                      'username': accountMap['username'] ?? accountId,
                      'profile_image_url': accountMap['account_profile_image_url'] ??
                                          accountMap['profile_image_url'] ??
                                          accountMap['thumbnail_url'],
                    };
                  }
                }
              }
            }
          }
        }
      }
    }
    
    final accountList = accountSet.toList();
    
    if (accountList.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          'No accounts found for $platform',
          style: TextStyle(
            fontSize: 13,
            color: theme.textTheme.bodySmall?.color,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    return Container(
      color: isDark ? Color(0xFF151515) : Colors.grey[50],
      child: ListView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: accountList.length,
        itemBuilder: (context, index) {
          final accountId = accountList[index];
          final details = accountDetails[accountId] ?? {};
          final displayName = details['display_name'] ?? accountId;
          final isAccountSelected = _selectedAccounts.contains(accountId);
          
          final profileImageUrl = details['profile_image_url']?.toString();
          
          return InkWell(
            onTap: () {
              setState(() {
                if (isAccountSelected) {
                  _selectedAccounts.remove(accountId);
                } else {
                  _selectedAccounts.add(accountId);
                }
                
                // Update filter active state
                _accountsFilterActive = _selectedAccounts.isNotEmpty;
                
                // If no accounts selected, clear platform filter
                if (_selectedAccounts.isEmpty) {
                  _selectedPlatforms.clear();
                  _accountsFilterActive = false;
                } else {
                  // Set platform filter when accounts are selected
                  if (!_selectedPlatforms.contains(platform)) {
                    _selectedPlatforms.add(platform);
                  }
                }
                
                // Reset pagination when filtering
                _currentPage = 1;
                _hasMorePosts = true;
              });
              setModalState(() {}); // Update the modal state
            },
            child: Container(
              padding: const EdgeInsets.only(left: 60, right: 20, top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: isAccountSelected
                    ? (isDark ? Color(0xFF667eea).withOpacity(0.15) : Color(0xFF667eea).withOpacity(0.08))
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  // Profile image
                  if (profileImageUrl != null && profileImageUrl.isNotEmpty)
                    Container(
                      width: 32,
                      height: 32,
                      margin: EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isAccountSelected
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                          width: isAccountSelected ? 2 : 1,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.network(
                          profileImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: theme.colorScheme.surfaceVariant,
                              child: Icon(
                                Icons.person,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  
                  Expanded(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isAccountSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isAccountSelected
                            ? theme.colorScheme.primary
                            : theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  
                  // Check icon
                  if (isAccountSelected)
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ).createShader(bounds);
                      },
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool wasScheduled;

  const _StatusChip({required this.status, this.wasScheduled = false});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'published':
        backgroundColor = wasScheduled ? const Color(0xFF34C759).withOpacity(0.9) : const Color(0xFF34C759);
        textColor = Colors.white;
        icon = wasScheduled ? Icons.schedule_send : Icons.check_circle;
        label = wasScheduled ? 'SCHEDULED' : 'PUBLISHED';
        break;
      case 'scheduled':
        backgroundColor = const Color(0xFF34C759).withOpacity(0.9);
        textColor = Colors.white;
        icon = Icons.schedule_send;
        label = 'SCHEDULED';
        break;
      case 'processing':
        backgroundColor = const Color(0xFFFF9500);
        textColor = Colors.white;
        icon = Icons.pending;
        label = 'PROCESSING';
        break;
      case 'draft':
        backgroundColor = const Color(0xFF007AFF);
        textColor = Colors.white;
        icon = Icons.edit;
        label = 'DRAFT';
        break;
      case 'failed':
        backgroundColor = const Color(0xFFFF3B30);
        textColor = Colors.white;
        icon = Icons.error;
        label = 'FAILED';
        break;
      default:
        backgroundColor = Colors.grey;
        textColor = Colors.white;
        icon = Icons.help;
        label = status.toUpperCase();
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
            color: textColor,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

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
    return Container(
      color: Colors.grey[200],
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

// Helper function to check if two dates are the same day
bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// Add this new class for the full month calendar view
class PublishedMonthCalendarPage extends StatefulWidget {
  final DateTime focusedMonth;
  final Map<DateTime, List<Map<String, dynamic>>> events;

  const PublishedMonthCalendarPage({
    Key? key,
    required this.focusedMonth,
    required this.events,
  }) : super(key: key);

  @override
  State<PublishedMonthCalendarPage> createState() => _PublishedMonthCalendarPageState();
}

class _PublishedMonthCalendarPageState extends State<PublishedMonthCalendarPage> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.focusedMonth;
    _selectedDay = widget.focusedMonth;
  }

  // Get videos for a specific day
  List<Map<String, dynamic>> _getVideosForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return widget.events[dateOnly] ?? [];
  }
  
  // Check if a date is in the future
  bool _isDateInFuture(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider only strictly future days as "future"
    return compareDate.isAfter(today);
  }
  
  // Check if a date is in the past (not including today)
  bool _isDateInPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compareDate = DateTime(date.year, date.month, date.day);
    // Consider strictly past days (before today) as "past"
    return compareDate.isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthName = DateFormat('MMMM').format(_focusedDay);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,  // Ombra aumentata per il dialog
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with month name and navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(
                        _focusedDay.year,
                        _focusedDay.month - 1,
                        1,
                      );
                    });
                  },
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.1),
                        Color(0xFF764ba2).withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF667eea).withOpacity(0.2),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ShaderMask(
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
                      '$monthName ${_focusedDay.year}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_ios, size: 16),
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(
                        _focusedDay.year,
                        _focusedDay.month + 1,
                        1,
                      );
                    });
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Calendar
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              eventLoader: (day) {
                final videos = _getVideosForDay(day);
                return videos.isEmpty ? [] : [videos.first];
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: 0, // Hide the default title
                ),
                leftChevronVisible: false,
                rightChevronVisible: false,
                headerMargin: EdgeInsets.zero,
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
                weekendStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              calendarStyle: CalendarStyle(
                markersMaxCount: 1,
                markerDecoration: BoxDecoration(
                  color: Colors.green, // Green dot for videos
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                weekendTextStyle: TextStyle(
                  color: theme.colorScheme.primary.withOpacity(0.8),
                ),
                outsideTextStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                // Style for disabled days (future only)
                disabledTextStyle: TextStyle(
                  color: Colors.grey.withOpacity(0.3),
                ),
                defaultDecoration: const BoxDecoration(shape: BoxShape.circle),
                cellMargin: const EdgeInsets.all(4),
              ),
              // Disable only future days, allow past days
              enabledDayPredicate: (day) => !_isDateInFuture(day),
              onDaySelected: (selectedDay, focusedDay) {
                // Permetti la selezione di tutti i giorni che non sono nel futuro
                if (!_isDateInFuture(selectedDay)) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  
                  // Close the dialog and return the selected day
                  Navigator.of(context).pop(_selectedDay);
                }
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
              // Aggiungo animazioni di pagina più fluide
              pageAnimationEnabled: true,
              pageAnimationCurve: Curves.easeInOut,
              pageAnimationDuration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }
} 