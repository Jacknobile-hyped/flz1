import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import '../../pages/settings_page.dart';
import '../../pages/profile_page.dart';
import '../../pages/scheduled_post_details_page.dart';
import '../../pages/video_details_page.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SocialAccountDetailsPage extends StatefulWidget {
  final Map<String, dynamic> account;
  final String platform;

  const SocialAccountDetailsPage({
    super.key,
    required this.account,
    required this.platform,
  });

  @override
  State<SocialAccountDetailsPage> createState() => _SocialAccountDetailsPageState();
}

class _SocialAccountDetailsPageState extends State<SocialAccountDetailsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _videosSubscription;
  StreamSubscription<DatabaseEvent>? _scheduledPostsSubscription;
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showInfo = false;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  Map<String, String?> _postUrls = {};
  bool _isLoadingUrls = true;
  final PageController _fullscreenPageController = PageController();
  
  // Variabili per la paginazione
  int _currentPage = 1;
  static const int _postsPerPage = 30;
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;
  bool _showLoadMoreButton = false;

  // Define platform logo paths
  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Listener per il cambio di tab per resettare la paginazione
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          // Reset pagination when changing tabs
          _currentPage = 1;
          _hasMorePosts = true;
        });
      }
    });
    
    _initializeVideosListener();
  }

  @override
  void dispose() {
    _videosSubscription?.cancel();
    _scheduledPostsSubscription?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    _fullscreenPageController.dispose();
    super.dispose();
  }

  void _initializeVideosListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    print('Initializing videos listener for user: ${currentUser.uid}');

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
              // Verifica se il video è associato all'account corrente
              bool isAssociatedWithAccount = false;
              
              // Prima prova la struttura con 'accounts' (struttura più recente)
              final accounts = videoData['accounts'] as Map<dynamic, dynamic>?;
              if (accounts != null) {
                // Cerca la piattaforma con la prima lettera maiuscola (come nel database)
                String platformKey = widget.platform;
                // Capitalizza la prima lettera per matchare il database
                platformKey = platformKey[0].toUpperCase() + platformKey.substring(1).toLowerCase();
                
                // Per YouTube, prova entrambe le varianti
                List<dynamic>? platformAccounts;
                if (widget.platform.toLowerCase() == 'youtube') {
                  // Prova prima con "YouTube" (maiuscolo)
                  platformAccounts = accounts['YouTube'] as List<dynamic>?;
                  // Se non trova nulla, prova con "youtube" (minuscolo)
                  if (platformAccounts == null) {
                    platformAccounts = accounts['youtube'] as List<dynamic>?;
                  }
                } else {
                  platformAccounts = accounts[platformKey] as List<dynamic>?;
                }
                
                if (platformAccounts != null) {
                  // Verifica se il video è associato all'account corrente
                  isAssociatedWithAccount = platformAccounts.any((acc) => 
                    acc['username'] == widget.account['username']
                  );
                }
              }
              
              // Se non trova nulla nella struttura 'accounts', prova la struttura alternativa
              if (!isAssociatedWithAccount) {
                final accountId = videoData['account_id']?.toString();
                final accountUsername = videoData['account_username']?.toString();
                
                if (accountId != null) {
                  final currentUsername = widget.account['username']?.toString();
                  final currentChannelId = widget.account['channel_id']?.toString();
                  final currentId = widget.account['id']?.toString();
                  
                  isAssociatedWithAccount = (currentUsername != null && accountUsername == currentUsername) ||
                                           (currentChannelId != null && currentChannelId == accountId) ||
                                           (currentId != null && currentId == accountId);
                }
              }
              
              if (!isAssociatedWithAccount) {
                return null;
              }

            String status = videoData['status']?.toString() ?? 'published';
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

              // Ottieni la descrizione dal campo corretto per la piattaforma corrente (video pubblicati)
              String description = '';
              final videoAccounts = videoData['accounts'] as Map<dynamic, dynamic>?;
              if (videoAccounts != null) {
                String platformKey = widget.platform;
                platformKey = platformKey[0].toUpperCase() + platformKey.substring(1).toLowerCase();
                
                // Per YouTube, prova entrambe le varianti
                List<dynamic>? platformAccounts;
                if (widget.platform.toLowerCase() == 'youtube') {
                  platformAccounts = videoAccounts['YouTube'] as List<dynamic>?;
                  if (platformAccounts == null) {
                    platformAccounts = videoAccounts['youtube'] as List<dynamic>?;
                  }
                } else {
                  platformAccounts = videoAccounts[platformKey] as List<dynamic>?;
                }
                
                if (platformAccounts != null && platformAccounts.isNotEmpty) {
                  // Cerca l'account che corrisponde all'account corrente
                  for (var account in platformAccounts) {
                    if (account is Map) {
                      final accountUsername = account['username']?.toString();
                      final currentUsername = widget.account['username']?.toString();
                      if (accountUsername == currentUsername) {
                        description = account['description']?.toString() ?? '';
                        break;
                      }
                    }
                  }
                }
              }
              
              // Fallback al campo 'description' se non trova la descrizione specifica per piattaforma
              if (description.isEmpty) {
                description = videoData['description']?.toString() ?? '';
              }

              return {
                'id': entry.key,
                'title': videoData['title'] ?? '',
                'description': description,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading videos: $error')),
        );
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
        // Found scheduled posts in database
        scheduledList = data.entries.map((entry) {
                  final postData = entry.value as Map<dynamic, dynamic>;
        try {
          // Processing post
          // Verifica se il post è associato all'account corrente
          bool isAssociatedWithAccount = false;
            
            // Prima prova la struttura con 'accounts' (struttura più recente)
            final accounts = postData['accounts'] as Map<dynamic, dynamic>?;
            if (accounts != null) {
              // Cerca la piattaforma con la prima lettera maiuscola (come nel database)
              String platformKey = widget.platform;
              // Capitalizza la prima lettera per matchare il database
              platformKey = platformKey[0].toUpperCase() + platformKey.substring(1).toLowerCase();
              
              // Platform key
              // Available platforms
              
              // Per YouTube, prova entrambe le varianti
              Map<dynamic, dynamic>? platformAccounts;
              if (widget.platform.toLowerCase() == 'youtube') {
                // Prova prima con "YouTube" (maiuscolo)
                platformAccounts = accounts['YouTube'] as Map<dynamic, dynamic>?;
                // Se non trova nulla, prova con "youtube" (minuscolo)
                if (platformAccounts == null) {
                  platformAccounts = accounts['youtube'] as Map<dynamic, dynamic>?;
                }
              } else {
                platformAccounts = accounts[platformKey] as Map<dynamic, dynamic>?;
              }
              
              // Platform accounts found
              
              if (platformAccounts != null) {
                // Itera su tutte le chiavi uniche per trovare l'account corrente
                for (String uniqueKey in platformAccounts.keys) {
                  final accountData = platformAccounts[uniqueKey] as Map<dynamic, dynamic>?;
                  if (accountData != null) {
                    final accUsername = accountData['account_username']?.toString();
                    final accId = accountData['account_id']?.toString();
                    final currentUsername = widget.account['username']?.toString();
                    final currentId = widget.account['id']?.toString();
                    final currentChannelId = widget.account['channel_id']?.toString();
                    
                    // Comparing account
                    
                    if ((currentUsername != null && accUsername == currentUsername) ||
                        (currentId != null && accId == currentId) ||
                        (currentChannelId != null && accId == currentChannelId)) {
                      isAssociatedWithAccount = true;
                      break;
                    }
                  }
                }
              }
            }
            
            // Se non trova nulla nella struttura 'accounts', prova la struttura alternativa
            if (!isAssociatedWithAccount) {
                      final accountId = postData['account_id']?.toString();
                      final accountUsername = postData['account_username']?.toString();
                      
              // Trying alternative structure
              
              if (accountId != null) {
                        final currentUsername = widget.account['username']?.toString();
                        final currentChannelId = widget.account['channel_id']?.toString();
                        final currentId = widget.account['id']?.toString();
                        final currentUserId = widget.account['user_id']?.toString();
                        
                        isAssociatedWithAccount = (currentUsername != null && accountUsername == currentUsername) ||
                                                 (currentChannelId != null && currentChannelId == accountId) ||
                                                 (currentId != null && currentId == accountId) ||
                                                 (currentUserId != null && currentUserId == accountId);
              }
            }
            
            // Is associated with account
            
            // Filtra solo i post associati all'account corrente
            if (!isAssociatedWithAccount) {
              // Post filtered out - not associated with current account
              return null;
            }

            String status = postData['status']?.toString() ?? 'scheduled';
            final scheduledTime = postData['scheduled_time'] as int?;
            final postAccounts = postData['accounts'] as Map<dynamic, dynamic>? ?? {};
            final platforms = postAccounts.keys.map((e) => e.toString().toLowerCase()).toList();
            
            // Gestione speciale per YouTube schedulato
            final hasYouTube = postAccounts.containsKey('YouTube') || postAccounts.containsKey('youtube');
            if (status == 'scheduled' && hasYouTube && scheduledTime != null) {
              final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (scheduledDateTime.isBefore(now)) {
                status = 'published';
              }
              // Se è ancora nel futuro, mantieni come scheduled
            }
            
            // Per tutte le altre piattaforme, mantieni il status originale
            // Non restituire null per i post schedulati di altre piattaforme
            
            // Verifica che il post abbia una data schedulata valida
            if (scheduledTime == null) {
              return null;
            }
            // Ottieni la descrizione dal campo corretto per la piattaforma corrente
            String description = '';
            final accountsForDescription = postData['accounts'] as Map<dynamic, dynamic>?;
            if (accountsForDescription != null) {
              String platformKey = widget.platform;
              platformKey = platformKey[0].toUpperCase() + platformKey.substring(1).toLowerCase();
              
              // Per YouTube, prova entrambe le varianti
              Map<dynamic, dynamic>? platformAccounts;
              if (widget.platform.toLowerCase() == 'youtube') {
                platformAccounts = accountsForDescription['YouTube'] as Map<dynamic, dynamic>?;
                if (platformAccounts == null) {
                  platformAccounts = accountsForDescription['youtube'] as Map<dynamic, dynamic>?;
                }
              } else {
                platformAccounts = accountsForDescription[platformKey] as Map<dynamic, dynamic>?;
              }
              
              if (platformAccounts != null) {
                // Itera su tutte le chiavi uniche per trovare l'account corrente
                for (String uniqueKey in platformAccounts.keys) {
                  final accountData = platformAccounts[uniqueKey] as Map<dynamic, dynamic>?;
                  if (accountData != null) {
                    final accUsername = accountData['account_username']?.toString();
                    final accId = accountData['account_id']?.toString();
                    final currentUsername = widget.account['username']?.toString();
                    final currentId = widget.account['id']?.toString();
                    final currentChannelId = widget.account['channel_id']?.toString();
                    
                    if ((currentUsername != null && accUsername == currentUsername) ||
                        (currentId != null && accId == currentId) ||
                        (currentChannelId != null && accId == currentChannelId)) {
                      description = accountData['description']?.toString() ?? '';
                      break;
                    }
                  }
                }
              }
            }
            
            // Fallback al campo 'text' se non trova la descrizione specifica per piattaforma
            if (description.isEmpty) {
              description = postData['text']?.toString() ?? '';
            }
            
            return {
              'id': entry.key,
              'title': postData['title'] ?? '',
              'description': description,
              'platforms': platforms,
              'status': status,
              'timestamp': postData['created_at'] ?? DateTime.now().millisecondsSinceEpoch, // Campo corretto: 'created_at'
              'created_at': postData['created_at'],
              'video_path': postData['media_url'] ?? '', // Campo corretto: 'media_url'
              'media_url': postData['media_url'],
              'thumbnail_path': postData['thumbnail_url'] ?? '', // Campo principale per thumbnail da Firebase
              'thumbnail_url': postData['thumbnail_url'],
              'thumbnail_cloudflare_url': postData['thumbnail_cloudflare_url'] ?? '',
              'accounts': postData['accounts'] ?? {},
              'user_id': postData['user_id'] ?? '',
              'scheduled_time': postData['scheduled_time'],
              'scheduledTime': postData['scheduled_time'], // Aggiungo per compatibilità con scheduled_posts_page
              'published_at': null,
              'youtube_video_id': postData['youtube_video_id'],
              'is_image': postData['is_image'] == true, // Campo corretto: 'is_image'
              'media_type': postData['media_type']?.toString() ?? 'text', // Campo corretto: 'media_type'
              'video_duration_seconds': postData['video_duration_seconds'],
              'video_duration_minutes': postData['video_duration_minutes'],
              'video_duration_remaining_seconds': postData['video_duration_remaining_seconds'],
            };
          } catch (e) {
            print('Error processing scheduled_post: $e');
            return null;
          }
        }).where((post) => post != null).cast<Map<String, dynamic>>().toList();
        // After filtering scheduled posts remain
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
      });
    });
  }

  int _getPublishedVideosCount() {
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    return _videos.where((video) {
      final status = video['status'] as String? ?? '';
      final publishedAt = video['published_at'] as int?;
      return status == 'published' || (status == 'scheduled' && publishedAt != null);
    }).length;
  }

  int _getScheduledVideosCount() {
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    return _videos.where((video) {
      final status = video['status'] as String? ?? '';
      final publishedAt = video['published_at'] as int?;
      final scheduledTime = video['scheduled_time'] as int?;
      
      // Conta i video che sono ancora schedulati (status = 'scheduled' e non ancora pubblicati)
      return status == 'scheduled' && 
             publishedAt == null && 
             scheduledTime != null && 
             scheduledTime > currentTimestamp;
    }).length;
  }

  void _updatePostUrl(Map<dynamic, dynamic>? accounts, String videoId) {
    if (accounts == null) return;

    accounts.forEach((platform, platformAccounts) {
      if (platformAccounts is List) {
        for (var account in platformAccounts) {
          if (account is Map) {
            final username = account['username']?.toString();
            final postId = account['post_id']?.toString();
            final mediaId = account['media_id']?.toString();

            if (username != null) {
              String? url;
              if (platform.toString() == 'Twitter' && postId != null) {
                url = 'https://twitter.com/i/status/$postId';
              } else if ((platform.toString() == 'YouTube' || platform.toString() == 'youtube') && (postId != null || mediaId != null)) {
                final videoId = postId ?? mediaId;
                url = 'https://www.youtube.com/watch?v=$videoId';
              } else if (platform.toString() == 'Instagram' && mediaId != null) {
                url = 'https://www.instagram.com/reel/$mediaId/';
              } else if (platform.toString() == 'Tiktok' && mediaId != null) {
                url = 'https://tiktok.com/@$username/video/$mediaId';
              } else if (platform.toString() == 'Threads' && postId != null && postId.isNotEmpty) {
                url = 'https://www.threads.com/@$username/post/$postId';
              }

              if (url != null) {
                setState(() {
                  _postUrls['${platform.toString().toLowerCase()}_${username}_$videoId'] = url;
                });
              }
            }
          }
        }
      }
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
      await _videosSubscription?.cancel();
      await _scheduledPostsSubscription?.cancel();
      _initializeVideosListener();
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
          // Nascondi il bottone dopo aver caricato più post
          _showLoadMoreButton = false;
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

  Widget _buildLoadMoreFAB(ThemeData theme) {
    return Material(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.2),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: FloatingActionButton(
          onPressed: _isLoadingMore ? null : _loadMorePosts,
          heroTag: 'load_more_fab',
          backgroundColor: Colors.transparent,
            elevation: 0,
          mini: true,
            shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            ),
          foregroundColor: Colors.white,
          child: _isLoadingMore
              ? SizedBox(
                  width: 14,
                  height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.refresh, size: 16),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  size: 22,
                ),
                onPressed: () => Navigator.pop(context),
              ),
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
                      'Fluzar',
                  style: TextStyle(
                        fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                        fontFamily: 'Ethnocentric',
                  ),
                ),
              ),
            ],
          ),
              IconButton(
                icon: Icon(
                  Icons.settings_outlined,
              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  size: 22,
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
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final account = widget.account;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        // Ombra per effetto profondità e vetro
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Upper section with profile image and info
                Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                                         // Profile image with glass effect border
                 Container(
                   width: 70,
                   height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                          color: isDark 
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.5),
                          width: 3,
                    ),
                    boxShadow: [
                        BoxShadow(
                            color: isDark 
                                ? Colors.black.withOpacity(0.3)
                                : Colors.black.withOpacity(0.15),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: const Offset(0, 5),
                          ),
                          BoxShadow(
                            color: isDark 
                                ? Colors.white.withOpacity(0.1)
                                : Colors.white.withOpacity(0.4),
                            blurRadius: 2,
                            spreadRadius: -2,
                            offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: ClipOval(
                    child: (account['profileImageUrl']?.isNotEmpty ?? false)
                      ? Image.network(
                          account['profileImageUrl'],
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                                  decoration: BoxDecoration(
                                    color: isDark 
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                              child: Center(
                                child: Text(
                                  ((account['displayName']?.toString() ?? '?').isNotEmpty ? (account['displayName']?.toString() ?? '?')[0] : '?').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                        color: isDark 
                                            ? Colors.white.withOpacity(0.8)
                                            : Colors.grey[600],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                              decoration: BoxDecoration(
                                color: isDark 
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                          child: Center(
                                                      child: Text(
                            ((account['displayName']?.toString() ?? '?').isNotEmpty ? (account['displayName']?.toString() ?? '?')[0] : '?').toUpperCase(),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.8)
                                      : Colors.grey[600],
                            ),
                          ),
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 20),
                // Name and username with improved styling
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        account['displayName'] ?? '',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : theme.colorScheme.onBackground,
                        ),
                      ),
                      if (account['username']?.isNotEmpty ?? false)
                        Text(
                          '@${account['username']}',
                          style: TextStyle(
                            fontSize: 16,
                                color: isDark ? Colors.white.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (account['location']?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                    color: isDark ? Colors.white.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                account['location'] ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                      color: isDark ? Colors.white.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                    // Open profile button with glass effect styling
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: _openProfileUrl,
                    child: Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                            color: isDark 
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.5),
                              width: 1,
                            ),
                        boxShadow: [
                            BoxShadow(
                                color: isDark 
                                    ? Colors.black.withOpacity(0.2)
                                    : Colors.black.withOpacity(0.1),
                              blurRadius: 5,
                                offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Icon(
                        Icons.open_in_new,
                            color: isDark ? Colors.white : theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
          ),
          
          // Bio section - only if present
          if (account['bio']?.isNotEmpty ?? false)
            Padding(
                    padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                        color: isDark 
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark 
                                ? Colors.black.withOpacity(0.2)
                                : Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Text(
                  account['bio'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                          color: isDark ? Colors.white : theme.colorScheme.onBackground,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          
                // Stats section with glass effect
          Padding(
                  padding: const EdgeInsets.only(top: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withOpacity(0.2)
                          : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark 
                            ? Colors.white.withOpacity(0.3)
                            : Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                boxShadow: [
                    BoxShadow(
                          color: isDark 
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 1),
                    ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Videos count
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 6),
                            Text(
                              '${_getPublishedVideosCount()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                      color: isDark ? Colors.white : theme.colorScheme.onBackground,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Published',
                          style: TextStyle(
                                  color: isDark ? Colors.white.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Divider
                  Container(
                    height: 40,
                    width: 1,
                          color: isDark 
                              ? Colors.white.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                  ),
                  
                  // Scheduled count
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${_getScheduledVideosCount()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                                  color: isDark ? Colors.white : theme.colorScheme.onBackground,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scheduled',
                          style: TextStyle(
                                  color: isDark ? Colors.white.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Divider
                  Container(
                    height: 40,
                    width: 1,
                          color: isDark 
                              ? Colors.white.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                  ),
                  
                  // Followers count
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          NumberFormat.compact().format(int.tryParse(account['followersCount']?.toString() ?? '0') ?? 0),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                                  color: isDark ? Colors.white : theme.colorScheme.onBackground,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Followers',
                          style: TextStyle(
                                  color: isDark ? Colors.white.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
      ),
    );
  }

  Widget _buildVideoList(bool isPublished) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 3,
        ),
      );
    }

    var filteredVideos = List<Map<String, dynamic>>.from(_videos);
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        final title = (video['title'] as String? ?? '').toLowerCase();
        final description = (video['description'] as String? ?? '').toLowerCase();
        final status = (video['status'] as String? ?? '').toLowerCase();
        return title.contains(query) ||
               description.contains(query) || 
               status.contains(query);
      }).toList();
    }

    // Filter by status
    filteredVideos = filteredVideos.where((video) {
      final status = video['status'] as String? ?? '';
      final publishedAt = video['published_at'] as int?;
      final scheduledTime = video['scheduled_time'] as int?;
      final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      if (isPublished) {
        // Show in Published tab if:
        // 1. Status is 'published', OR
        // 2. Status is 'scheduled' but has 'published_at' timestamp (was a scheduled post that's been published)
        return status == 'published' || (status == 'scheduled' && publishedAt != null);
      } else {
        // Show in Scheduled tab only if:
        // 1. Status is 'scheduled' AND
        // 2. No 'published_at' timestamp exists (not yet published) AND
        // 3. Scheduled time is in the future
        return status == 'scheduled' && 
               publishedAt == null && 
               scheduledTime != null && 
               scheduledTime > currentTimestamp;
      }
    }).toList();

    // Sort videos
    if (isPublished) {
      // Published videos: most recent first (descending)
      filteredVideos.sort((a, b) {
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
    } else {
      // Scheduled videos: nearest scheduled time first (ascending)
      filteredVideos.sort((a, b) {
        final aTime = a['scheduledTime'] as int? ?? a['scheduled_time'] as int? ?? a['timestamp'] as int;
        final bTime = b['scheduledTime'] as int? ?? b['scheduled_time'] as int? ?? b['timestamp'] as int;
        return aTime.compareTo(bTime);
      });
    }

    // Applica la paginazione solo per il tab "Published" (isPublished = true)
    List<Map<String, dynamic>> paginatedVideos = filteredVideos;
    bool showLoadMoreButton = false;
    
    if (isPublished) {
      // Per il tab "Published", applica la paginazione
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showInfo) _buildInfoDropdown(),
        
        Expanded(
          child: paginatedVideos.isEmpty
              ? _buildEmptyState(isPublished)
              : RefreshIndicator(
                  onRefresh: _refreshVideos,
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.background,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate item size based on available width for TikTok-style vertical grid
                        final availableWidth = constraints.maxWidth;
                        // Use 3 columns with equal spacing
                        final itemWidth = (availableWidth - 16) / 3;
                        // Make items more vertical (aspect ratio 9:16 like TikTok)
                        final itemHeight = itemWidth * 1.8;
                        
                        return NotificationListener<ScrollNotification>(
                          onNotification: (ScrollNotification scrollInfo) {
                            if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                              // Mostra il bottone quando l'utente è vicino alla fine
                              if (_hasMorePosts && !_showLoadMoreButton) {
                                setState(() {
                                  _showLoadMoreButton = true;
                                });
                              }
                            } else {
                              // Nascondi il bottone quando l'utente non è alla fine
                              if (_showLoadMoreButton) {
                                setState(() {
                                  _showLoadMoreButton = false;
                                });
                              }
                            }
                            return false;
                          },
                          child: GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, 
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                              childAspectRatio: 1 / 1.2, // More vertical for 3cm height
                            ),
                            itemCount: paginatedVideos.length,
                            itemBuilder: (context, index) {
                        return _buildGridThumbnail(
                          theme, 
                          paginatedVideos[index], 
                                false, // No large items anymore
                          () => _openFullscreenPostView(paginatedVideos, index, isPublished)
                        );
                      },
                          ),
                        );
                      }
                    ),
                  ),
                ),
        ),
        
      ],
    );
  }

  // Updated thumbnail builder for TikTok-style vertical grid
  Widget _buildGridThumbnail(
    ThemeData theme, 
    Map<String, dynamic> video, 
    bool isLargeItem, // Kept for compatibility but not used
    VoidCallback onTap
  ) {
    final isDark = theme.brightness == Brightness.dark;
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    final status = video['status'] as String? ?? '';
    final publishedAt = video['published_at'] as int?;
    final scheduledTime = video['scheduled_time'] as int?;
    final isScheduled = (status == 'scheduled' && publishedAt == null) || 
                       (scheduledTime != null && scheduledTime > DateTime.now().millisecondsSinceEpoch);
    
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
    
    final mediaType = (video['media_type']?.toString().toLowerCase() ?? '');
    final isImage = video['is_image'] == true || mediaType == 'image' || mediaType == 'photo';
    
    // Determine which platform this video is for based on the current account
    final platform = widget.platform.toLowerCase();
    final logoPath = _platformLogos[platform] ?? '';
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white,
          width: 0.5,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: Material(
        color: isDark ? theme.colorScheme.surface : theme.colorScheme.background,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Se è un'immagine pubblicata, mostra l'immagine
              if (isImage)
                _buildImageThumbnail(videoPath, thumbnailPath, thumbnailCloudflareUrl, theme)
              else
                // Thumbnail con stato di caricamento
                _buildThumbnailImage(thumbnailCloudflareUrl, thumbnailPath, videoPath, theme),
              
              // Dark gradient overlay for better text visibility
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.black.withOpacity(0.3),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              
              // Platform and date info
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Row(
                  children: [
                    // Logo from assets with white background - smaller for vertical format
                    Container(
                      width: 14, 
                      height: 14,
                      padding: EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: isDark ? theme.colorScheme.surface : theme.colorScheme.background,
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: theme.colorScheme.shadow.withOpacity(0.1),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                        ],
                      ),
                      child: logoPath.isNotEmpty
                        ? Image.asset(
                            logoPath,
                            fit: BoxFit.contain,
                          )
                        : Icon(
                            Icons.public,
                            color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.primary,
                            size: 7,
                          ),
                    ),
                        SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            _formatPostDate(video),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
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
  }

  // Helper method to build thumbnail image prioritizing Cloudflare URLs - simplified like history_page.dart
  Widget _buildThumbnailImage(String? thumbnailCloudflareUrl, String? thumbnailPath, String? cloudflareUrl, ThemeData theme) {
    // First try thumbnail from Cloudflare
    if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              thumbnailCloudflareUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // Try cloudflare video URL as thumbnail
                if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
                  return Image.network(
                    cloudflareUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildLocalThumbnail(thumbnailPath, theme),
                  );
                }
                return _buildLocalThumbnail(thumbnailPath, theme);
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    
    // Then try cloudflare video URL as thumbnail
    if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              cloudflareUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildLocalThumbnail(thumbnailPath, theme),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    
    // Fallback to local thumbnail
    return _buildLocalThumbnail(thumbnailPath, theme);
  }
  
  // Helper to build local thumbnail with fallback
  Widget _buildLocalThumbnail(String? thumbnailPath, ThemeData theme) {
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(thumbnailPath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: theme.colorScheme.surface.withOpacity(0.8),
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    
    return Container(
      color: theme.colorScheme.surface.withOpacity(0.8),
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 32,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
  
  // Helper per formattare la data del post
  String _formatPostDate(Map<String, dynamic> video) {
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    // Calcolo timestamp per visualizzazione usando la stessa logica dell'ordinamento
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
    
    final publishedAt = video['published_at'] as int?;
    final scheduledTime = video['scheduled_time'] as int?;
    final scheduledTimeAlt = video['scheduledTime'] as int?; // Per compatibilità con scheduled_posts_page
    
    DateTime dateTime;
    if (publishedAt != null) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(publishedAt);
    } else if (scheduledTime != null) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    } else if (scheduledTimeAlt != null) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTimeAlt);
    } else {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    
    // Formato breve: "25 May" o "Today, 14:30"
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final postDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (postDate == today) {
      // Oggi, mostra solo l'ora
      return "Today, ${DateFormat('HH:mm').format(dateTime)}";
    } else {
      // Altro giorno, mostra giorno e mese
      return DateFormat('dd MMM').format(dateTime);
    }
  }
  
  String _formatTimestamp(DateTime timestamp, bool isScheduled) {
    if (isScheduled) {
      return DateFormat('dd/MM').format(timestamp);
    }
    
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 1) {
      // Se è maggiore di un giorno, mostra la data nel formato gg/mm/anno
      return DateFormat('dd/MM/yyyy').format(timestamp);
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
  
  // Helper per ottenere l'icona della piattaforma
  Widget _getPlatformIcon() {
    IconData iconData;
    Color iconColor;
    
    switch (widget.platform.toLowerCase()) {
      case 'twitter':
        iconData = Icons.chat;
        iconColor = Colors.blue;
        break;
      case 'instagram':
        iconData = Icons.camera_alt;
        iconColor = Colors.purple;
        break;
      case 'facebook':
        iconData = Icons.facebook;
        iconColor = Colors.blue;
        break;
      case 'youtube':
        iconData = Icons.play_circle_outline;
        iconColor = Colors.red;
        break;
      case 'tiktok':
        iconData = Icons.music_note;
        iconColor = Colors.black;
        break;
      case 'threads':
        iconData = Icons.chat_bubble_outline;
        iconColor = Colors.black;
        break;
      default:
        iconData = Icons.public;
        iconColor = Colors.grey;
        break;
    }
    
    return Icon(
      iconData,
      size: 12,
      color: iconColor,
    );
  }
  
  // Wrapper method to handle post opening with platform-specific logic
  Future<void> _openPostWithPlatformLogic(String url, Map<String, dynamic> video) async {
    // Ora che apriamo sempre la pagina profilo per Threads, Facebook e Instagram,
    // possiamo usare direttamente il metodo generico
    await _openSocialMedia(url);
  }
  
  // Nuovo metodo per aprire la visualizzazione a schermo intero
  void _openFullscreenPostView(List<Map<String, dynamic>> videos, int initialIndex, bool isPublished) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullscreenPostView(
          videos: videos,
          initialIndex: initialIndex,
          platform: widget.platform,
          onOpenPost: (url, video) async => await _openPostWithPlatformLogic(url, video),
          getPostUrl: _getPostUrl,
          formatTimestamp: _formatTimestamp,
          formatPostDate: _formatPostDate,
          getPlatformIcon: _getPlatformIcon,

        ),
      ),
    );
  }

  // Nuovo metodo per mostrare immagini nella griglia - simplified like history_page.dart
  Widget _buildImageThumbnail(String? mediaUrl, String? thumbnailPath, String? thumbnailCloudflareUrl, ThemeData theme) {
    // Priorità: thumbnailCloudflareUrl > mediaUrl > thumbnailPath
    if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              thumbnailCloudflareUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildLocalImage(mediaUrl, thumbnailPath, theme),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      // Se è un url http mostro come network, altrimenti come file
      if (mediaUrl.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                mediaUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildLocalImage(null, thumbnailPath, theme),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: null,
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      } else {
        return _buildLocalImage(mediaUrl, thumbnailPath, theme);
      }
    }
    // Fallback su thumbnailPath
    return _buildLocalImage(null, thumbnailPath, theme);
  }

  Widget _buildLocalImage(String? mediaUrl, String? thumbnailPath, ThemeData theme) {
    final path = mediaUrl ?? thumbnailPath;
    if (path != null && path.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surface.withOpacity(0.8),
                child: Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      color: theme.colorScheme.surface.withOpacity(0.8),
      child: Center(
        child: Icon(
          Icons.image,
          size: 32,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isPublished) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surfaceVariant : theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 48,
                color: isDark ? theme.colorScheme.onSurface.withOpacity(0.5) : theme.colorScheme.primary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? theme.colorScheme.onSurface.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                  // Reset pagination when clearing search
                  _currentPage = 1;
                  _hasMorePosts = true;
                });
              },
              icon: Icon(Icons.refresh_rounded, size: 18, color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.primary),
              label: Text('Clear search', style: TextStyle(color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.primary)),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surfaceVariant : theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPublished ? Icons.video_library : Icons.schedule,
              size: 50,
              color: isDark ? theme.colorScheme.onSurface.withOpacity(0.5) : theme.colorScheme.primary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isPublished ? 'No published videos' : 'No scheduled videos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              isPublished 
                ? 'Videos you publish will appear here'
                : 'Videos scheduled will appear here',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? theme.colorScheme.onSurface.withOpacity(0.7) : theme.colorScheme.onBackground.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'About Account Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            'Content Overview',
            'View all published and scheduled content for this social account.',
            Icons.visibility,
            isDark,
          ),
          _buildInfoItem(
            'Real-time Updates',
            'Track your content status and engagement metrics in real-time.',
            Icons.update,
            isDark,
          ),
          _buildInfoItem(
            'Content Management',
            'Easily manage and monitor your social media content from one place.',
            Icons.manage_accounts,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isDark ? Colors.grey[400] : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSocialMedia(String url) async {
    print('Attempting to open URL: $url');
    

    
    // Gestione normale per tutte le altre piattaforme
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('Could not launch URL: $url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open the link. URL: $url')),
          );
        }
      }
    } catch (e) {
      print('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening the link: $e')),
        );
      }
    }
  }

  Future<String?> _getPostUrl(Map<String, dynamic> video) async {
    // Check either if it's a published post or a scheduled post that has been published
    final status = video['status'] as String? ?? '';
    final publishedAt = video['published_at'] as int?;
    
    if (!(status == 'published' || (status == 'scheduled' && publishedAt != null))) {
      return null;
    }

    // Prima prova la struttura con 'accounts' (struttura più recente)
    final accounts = video['accounts'] as Map<dynamic, dynamic>?;
    if (accounts != null) {
      // Cerca la piattaforma con la prima lettera maiuscola (come nel database)
      String platformKey = widget.platform;
      // Capitalizza la prima lettera per matchare il database
      platformKey = platformKey[0].toUpperCase() + platformKey.substring(1).toLowerCase();
      
      // Per YouTube, prova entrambe le varianti
      List<dynamic>? platformAccounts;
      if (widget.platform.toLowerCase() == 'youtube') {
        // Prova prima con "YouTube" (maiuscolo)
        platformAccounts = accounts['YouTube'] as List<dynamic>?;
        // Se non trova nulla, prova con "youtube" (minuscolo)
        if (platformAccounts == null) {
          platformAccounts = accounts['youtube'] as List<dynamic>?;
        }
      } else {
        platformAccounts = accounts[platformKey] as List<dynamic>?;
      }
      
      if (platformAccounts != null && platformAccounts.isNotEmpty) {
        // Find the matching account entry for the current account
        final currentUsername = widget.account['username']?.toString();
        if (currentUsername != null) {
          // Find the account data in the video's accounts list that matches the current account
          Map<dynamic, dynamic>? accountData;
          for (var account in platformAccounts) {
            if (account is Map && account['username']?.toString() == currentUsername) {
              accountData = account;
              break;
            }
          }
          
          if (accountData != null) {
            final username = accountData['username']?.toString();
            final postId = accountData['post_id']?.toString();
            final mediaId = accountData['media_id']?.toString();
            final scheduledTweetId = accountData['scheduled_tweet_id']?.toString();
            final platformKeyLower = platformKey.toLowerCase();

            if (username != null) {
              // Utilizza la stessa logica di video_details_page.dart
              if (platformKeyLower == 'twitter' && (postId != null && postId.isNotEmpty || scheduledTweetId != null && scheduledTweetId.isNotEmpty)) {
                final tweetId = (postId != null && postId.isNotEmpty) ? postId : scheduledTweetId;
                return 'https://twitter.com/i/status/$tweetId';
              } else if (platformKeyLower == 'youtube' && (postId != null && postId.isNotEmpty || mediaId != null && mediaId.isNotEmpty)) {
                final videoId = (postId != null && postId.isNotEmpty) ? postId : mediaId;
                return 'https://www.youtube.com/watch?v=$videoId';
              } else if (platformKeyLower == 'facebook') {
                // Per Facebook, usa direttamente il username
                return 'https://m.facebook.com/profile.php?id=$username';
              } else if (platformKeyLower == 'instagram') {
                // Per Instagram, usa direttamente il profilo dell'utente
                return 'https://www.instagram.com/$username/';
              } else if (platformKeyLower == 'tiktok' && (postId != null && postId.isNotEmpty || mediaId != null && mediaId.isNotEmpty)) {
                final videoId = (postId != null && postId.isNotEmpty) ? postId : mediaId;
                return 'https://www.tiktok.com/@$username/video/$videoId';
              } else if (platformKeyLower == 'threads' && (postId != null && postId.isNotEmpty || mediaId != null && mediaId.isNotEmpty)) {
                final threadPostId = (postId != null && postId.isNotEmpty) ? postId : mediaId;
                return 'https://www.threads.net/@$username/post/$threadPostId';
              }
            }
          }
        }
      }
    }

    // Fallback if no specific post URL is found (e.g., for general profile links or other platforms)
    final videoIdLegacy = video['id'] as String?;
    final platformKeyLower = widget.platform.toLowerCase();
    
    // Check if the video ID contains a user ID (new format for some platforms)
    // This assumes the user ID is part of the video ID, e.g., "userId_videoId"
    if (videoIdLegacy != null && videoIdLegacy.contains('_')) {
      final parts = videoIdLegacy.split('_');
      if (parts.length == 2) {
        final userIdInVideoId = parts[0];
        final actualVideoId = parts[1];
        
        // Attempt to find the username associated with this userId
        try {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            final userSnapshot = await FirebaseDatabase.instance.ref()
                .child('users')
                .child('users')
                .child(currentUser.uid)
                .child('social_accounts')
                .child(platformKeyLower)
                .orderByKey()
                .equalTo(userIdInVideoId) // Assuming userIdInVideoId is the account ID
                .get();

            if (userSnapshot.exists && userSnapshot.value is Map) {
              final accountEntry = (userSnapshot.value as Map).values.first as Map<dynamic, dynamic>;
              final associatedUsername = accountEntry['username']?.toString();

              if (associatedUsername != null && associatedUsername.isNotEmpty) {
                if (platformKeyLower == 'tiktok') {
                  return 'https://www.tiktok.com/@$associatedUsername/video/$actualVideoId';
                } else if (platformKeyLower == 'instagram') {
                  // If we have a mediaId and an access token, this block should not be reached
                  // as the direct API call for permalink should be prioritized.
                  // This is a fallback to profile if the permalink fetching failed.
                  return 'https://www.instagram.com/$associatedUsername/';
                } else if (platformKeyLower == 'threads') {
                  return 'https://www.threads.net/@$associatedUsername/post/$actualVideoId';
                }
              }
            }
          }
        } catch (e) {
          print('Error processing legacy video ID with user ID: $e');
        }
      }
    }
    
    // Fallback for older formats or if no specific post link is found
    if (videoIdLegacy != null && videoIdLegacy.isNotEmpty) {
      if (platformKeyLower == 'twitter') {
        return 'https://twitter.com/i/status/$videoIdLegacy';
      } else if (platformKeyLower == 'youtube') {
        return 'https://www.youtube.com/watch?v=$videoIdLegacy';
      } else if (platformKeyLower == 'tiktok') {
        // This case would usually be covered by the above logic if username is available
        return 'https://www.tiktok.com/video/$videoIdLegacy';
      } else if (platformKeyLower == 'instagram') {
        // This is the problematic line that needs to be removed as it bypasses API call
        // Removed: return 'https://www.instagram.com/$username/';
        return null; // Ensure it explicitly returns null if permalink couldn't be fetched
      } else if (platformKeyLower == 'facebook' && widget.account['username'] != null) {
        // This might be for profile link if no post link is available
        return 'https://m.facebook.com/profile.php?id=${widget.account['username']}';
      } else if (platformKeyLower == 'threads' && widget.account['username'] != null) {
        return 'https://www.threads.net/@${widget.account['username']}/';
      }
    }

    return null; // Default to null if no valid URL can be constructed
  }



  Future<void> _openProfileUrl() async {
    final account = widget.account;
    String? profileUrl;

    switch (widget.platform.toLowerCase()) {
      case 'twitter':
        profileUrl = 'https://twitter.com/${account['username']}';
        break;
      case 'instagram':
        profileUrl = 'https://www.instagram.com/${account['username']}';
        break;
      case 'facebook':
        // Per Facebook, usa direttamente l'username o l'ID
        final facebookId = account['id']?.toString() ?? account['username']?.toString() ?? '';
        profileUrl = 'https://m.facebook.com/profile.php?id=$facebookId';
        break;
      case 'youtube':
        profileUrl = 'https://youtube.com/channel/${account['id']}';
        break;
      case 'tiktok':
        profileUrl = 'https://tiktok.com/@${account['username']}';
        break;
      case 'threads':
        profileUrl = 'https://www.threads.com/@${account['username']}';
        break;
    }

    if (profileUrl != null) {
      final uri = Uri.parse(profileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _openInstagramPostOrProfile(Map<String, dynamic> account) async {
    final username = account['username']?.toString();
    if (username != null && username.isNotEmpty) {
      _openInstagramProfile(username);
    }
  }



  // Method to open Instagram profile
  void _openInstagramProfile(String username) async {
    // Try opening Instagram app with username first
    final instagramUserUri = Uri.parse('instagram://user?username=$username');
    try {
      if (await canLaunchUrl(instagramUserUri)) {
        await launchUrl(instagramUserUri);
        return;
      }
    } catch (e) {
      debugPrint('Error launching Instagram app with username: $e');
    }
    
    // Fallback to web URL if app launch fails
    final webUri = Uri.parse('https://www.instagram.com/$username/');
    try {
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $webUri');
        // Show a snackbar to inform the user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open Instagram. Please make sure you have Instagram installed.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching web URL: $e');
    }
  }



  // Method to open Facebook profile
  void _openFacebookProfile(String username) async {
    // Try opening Facebook app with username first (not always possible, fallback to web)
    final webUri = Uri.parse('https://www.facebook.com/$username');
    try {
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $webUri');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open Facebook. Please make sure you have Facebook installed.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching Facebook web URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? theme.colorScheme.background : theme.colorScheme.background,
      floatingActionButton: _showLoadMoreButton ? _buildLoadMoreFAB(theme) : null,
      body: Stack(
        children: [
          // Main content area - no padding, content can scroll behind floating header
          SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshVideos,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.background,
          child: CustomScrollView(
            slivers: [
                                SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80), // Ridotto il padding per avvicinare alla top bar
                      child: _buildProfileSection(),
                    ),
                  ),
              SliverPersistentHeader(
                delegate: _SliverTabBarDelegate(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 12,
                              ),
                              labelPadding: EdgeInsets.zero,
                              padding: EdgeInsets.zero,
                              tabs: [
                                Tab(
                                  icon: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.video_library, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Published'),
                                    ],
                                  ),
                                ),
                                Tab(
                                  icon: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.schedule, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Scheduled'),
                                    ],
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
                pinned: true,
              ),
              SliverFillRemaining(
                child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildVideoList(true),
                        _buildVideoList(false),
                      ],
                    ),
              ),
            ],
          ),
        ),
          ),
          
          // Floating header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildHeader(context),
            ),
          ),
        ],
      ),
    );
  }
}

// Delegate per rendere persistente la TabBar quando si scrolla
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  
  _SliverTabBarDelegate(this.child);
  
  @override
  double get minExtent => 48;
  
  @override
  double get maxExtent => 48;
  
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }
  
  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}

// Nuova classe per la visualizzazione a schermo intero in stile social media
class _FullscreenPostView extends StatefulWidget {
  final List<Map<String, dynamic>> videos;
  final int initialIndex;
  final String platform;
  final Future<void> Function(String, Map<String, dynamic>) onOpenPost;
  final Future<String?> Function(Map<String, dynamic>) getPostUrl;
  final String Function(DateTime, bool) formatTimestamp;
  final String Function(Map<String, dynamic>) formatPostDate;
  final Widget Function() getPlatformIcon;


  const _FullscreenPostView({
    required this.videos,
    required this.initialIndex,
    required this.platform,
    required this.onOpenPost,
    required this.getPostUrl,
    required this.formatTimestamp,
    required this.formatPostDate,
    required this.getPlatformIcon,

  });

  @override
  _FullscreenPostViewState createState() => _FullscreenPostViewState();
}

class _FullscreenPostViewState extends State<_FullscreenPostView> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  Map<int, bool> _expandedDescriptions = {};
  Map<int, VideoPlayerController?> _videoControllers = {};
  bool _isVideoLoading = false;
  Map<int, bool> _isVideoPlaying = {};
  // Added variables for progress bar
  Map<int, Duration> _currentPositions = {};
  Map<int, Duration> _durations = {};
  bool _isDraggingProgressBar = false;
  
  // Animation for description expansion
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  // Variables for play/pause controls visibility
  Map<int, bool> _showPlayPauseControls = {};
  Map<int, Timer?> _controlsHideTimers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeVideoController(widget.initialIndex);
    
    // Initialize animation controller with faster duration
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllVideoControllers();
    _animationController.dispose();
    
    // Cancel all control hide timers
    for (var timer in _controlsHideTimers.values) {
      timer?.cancel();
    }
    _controlsHideTimers.clear();
    
    super.dispose();
  }

  void _disposeAllVideoControllers() {
    for (var controller in _videoControllers.values) {
      controller?.dispose();
    }
    _videoControllers.clear();
  }

  Future<void> _initializeVideoController(int index) async {
    // Dispose any controller that's not the current one or adjacent to conserve memory
    _disposeNonVisibleControllers(index);
    
    if (_videoControllers.containsKey(index) && _videoControllers[index] != null) {
      // Controller already exists, just play it
      try {
        await _videoControllers[index]!.play();
        setState(() {
          _isVideoPlaying[index] = true;
          _showPlayPauseControls[index] = false; // Non mostrare controlli quando si riprende la riproduzione
        });
      } catch (e) {
        print('Error playing existing video: $e');
      }
      return;
    }

    final video = widget.videos[index];
    
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    // THUMBNAIL: Gestione corretta per nuovo formato
    final videoPath = isNewFormat 
        ? video['media_url'] as String?
        : video['video_path'] as String?;
    
      if (videoPath == null || videoPath.isEmpty) {
        _videoControllers[index] = null;
        return;
      }
      
    // Check if local file exists before trying to use it (only for old format)
    if (!isNewFormat && !videoPath.startsWith('http')) {
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        _videoControllers[index] = null;
        return;
      }
    }

    setState(() {
      _isVideoLoading = true;
    });

    try {
      VideoPlayerController controller;
      
      // Prioritize network URL (new format) over local file
      if (videoPath.startsWith('http')) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(videoPath),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      } else {
        controller = VideoPlayerController.file(
          File(videoPath),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      }
      
      _videoControllers[index] = controller;
      
      // Add listener for position updates
      controller.addListener(() {
        if (mounted && !_isDraggingProgressBar) {
          setState(() {
            _currentPositions[index] = controller.value.position;
            _durations[index] = controller.value.duration;
          });
        }
      });
      
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _isVideoPlaying[index] = true;
          _currentPositions[index] = controller.value.position;
          _durations[index] = controller.value.duration;
          _showPlayPauseControls[index] = false; // Non mostrare controlli quando il video inizia automaticamente
        });
        
        // Non serve timer quando i controlli sono nascosti
        _startControlsHideTimer(index, false);
      }
    } catch (e) {
      print('Error initializing video controller: $e');
      _videoControllers[index] = null;
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _isVideoPlaying[index] = false;
        });
      }
    }
  }

  // Dispose controllers that are not needed anymore to free memory
  void _disposeNonVisibleControllers(int currentIndex) {
    // Keep only the current controller and adjacent ones
    final keysToKeep = [currentIndex - 1, currentIndex, currentIndex + 1];
    
    for (var entry in _videoControllers.entries) {
      if (!keysToKeep.contains(entry.key)) {
        try {
          entry.value?.pause();
          entry.value?.dispose();
          _videoControllers.remove(entry.key);
          
          // Also clean up related state
          _isVideoPlaying.remove(entry.key);
          _showPlayPauseControls.remove(entry.key);
          _controlsHideTimers[entry.key]?.cancel();
          _controlsHideTimers.remove(entry.key);
        } catch (e) {
          print('Error disposing controller: $e');
        }
      }
    }
  }

  void _toggleDescription(int index) {
    setState(() {
      _expandedDescriptions[index] = !(_expandedDescriptions[index] ?? false);
      
      // Animate the fade in/out
      if (_expandedDescriptions[index] ?? false) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  // Toggle video play/pause when tapping screen
  void _togglePlayPause(int index) {
    final controller = _videoControllers[index];
    if (controller != null) {
      setState(() {
        if (controller.value.isPlaying) {
          // Quando il video è in play, metti in pausa e mostra sempre l'icona di pausa
          controller.pause();
          _isVideoPlaying[index] = false;
          _showPlayPauseControls[index] = true; // Mostra sempre i controlli quando in pausa
          _startControlsHideTimer(index, false); // Non nascondere automaticamente quando in pausa
        } else {
          // Quando il video è in pausa, rimetti in play e nascondi i controlli
          controller.play();
          _isVideoPlaying[index] = true;
          _showPlayPauseControls[index] = false; // Nascondi i controlli quando in play
          _startControlsHideTimer(index, false); // Non serve timer quando i controlli sono nascosti
        }
      });
    }
  }
  
  // Show/hide play/pause controls - ora gestito solo tramite tap sul video
  void _toggleControlsVisibility(int index) {
    // Non fare nulla - i controlli sono gestiti solo tramite _togglePlayPause
    // Questa funzione è mantenuta per compatibilità ma non viene più utilizzata
  }
  
  // Start timer to hide controls automatically - ora non utilizzato
  void _startControlsHideTimer(int index, bool autoHide) {
    // Cancella eventuali timer esistenti
    _controlsHideTimers[index]?.cancel();
    // Non avviare nuovi timer - i controlli non si nascondono più automaticamente
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Helper method to get video timestamp based on format
  int _getVideoTimestamp(Map<String, dynamic> video) {
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    // Per i video schedulati, usa sempre scheduled_time
    final status = video['status'] as String? ?? '';
    final publishedAt = video['published_at'] as int?;
    final scheduledTime = video['scheduled_time'] as int?;
    final isScheduled = (status == 'scheduled' && publishedAt == null) || 
                       (scheduledTime != null && scheduledTime > DateTime.now().millisecondsSinceEpoch);
    
    if (isScheduled) {
      return video['scheduled_time'] as int? ?? 0;
    }

    // Calcolo timestamp per visualizzazione usando la stessa logica dell'ordinamento
    if (isNewFormat) {
      // Per il nuovo formato: usa scheduled_time, fallback a created_at, poi timestamp
      return video['scheduled_time'] as int? ?? 
             (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
             (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
    } else {
      // Per il vecchio formato: usa timestamp
      return video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.videos.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
            
            // Pause all videos
            for (var controller in _videoControllers.values) {
              if (controller != null && controller.value.isPlaying) {
                controller.pause();
              }
            }
            
            // Initialize and play the new video
            _initializeVideoController(index);
          },
          scrollDirection: Axis.vertical,
          itemBuilder: (context, index) {
            final video = widget.videos[index];
            final title = video['title'] as String? ?? '';
            final description = video['description'] as String? ?? '';
            final status = video['status'] as String? ?? '';
            final publishedAt = video['published_at'] as int?;
            final scheduledTime = video['scheduled_time'] as int?;
        final isScheduled = (status == 'scheduled' && publishedAt == null) || 
                           (scheduledTime != null && scheduledTime > DateTime.now().millisecondsSinceEpoch);
            final isExpanded = _expandedDescriptions[index] ?? false;
            final videoController = _videoControllers[index];
            final hasVideo = videoController != null && videoController.value.isInitialized;
            final isPlaying = _isVideoPlaying[index] ?? false;
            
            // Get current position and duration for progress bar
            final currentPosition = _currentPositions[index] ?? Duration.zero;
            final duration = _durations[index] ?? Duration.zero;
            
            return FutureBuilder<String?>(
              future: widget.getPostUrl(video),
              builder: (context, snapshot) {
                final postUrl = snapshot.data;
                
                return GestureDetector(
                  onTapDown: (TapDownDetails details) {
                    // Check if tap is in the video area (almost entire screen)
                    final RenderBox renderBox = context.findRenderObject() as RenderBox;
                    final size = renderBox.size;
                    final tapX = details.localPosition.dx;
                    final tapY = details.localPosition.dy;
                    
                    // Define video area (90% of screen width and height, excluding edges)
                    final videoAreaWidth = size.width * 0.9;
                    final videoAreaHeight = size.height * 0.9;
                    final startX = size.width * 0.05; // 5% margin from left
                    final startY = size.height * 0.05; // 5% margin from top
                    
                    final isInVideoArea = (tapX >= startX &&
                                          tapX <= startX + videoAreaWidth &&
                                          tapY >= startY &&
                                          tapY <= startY + videoAreaHeight);
                    
                    if (hasVideo && isInVideoArea) {
                      // Toggle video playback if tap is in video area
                      _togglePlayPause(index);
                    }
                  },
                  child: Stack(
              fit: StackFit.expand,
              children: [
                // Video or Thumbnail with GestureDetector for play/pause
                  Container(
                    color: Colors.black,
                    child: hasVideo
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: videoController.value.aspectRatio,
                            child: VideoPlayer(videoController),
                          ),
                        )
                      : _buildMediaPreview(video)
                ),
                
                // Loading indicator for video
                if (_isVideoLoading && index == _currentIndex)
                  Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                
                // Play indicator when video is paused
                if (hasVideo && (_showPlayPauseControls[index] ?? false) && !(_isVideoPlaying[index] ?? false))
                  AnimatedOpacity(
                    opacity: (_showPlayPauseControls[index] ?? false) ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 300),
                    child: Center(
                      child: Container(
                        width: 67,
                        height: 67,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 37,
                        ),
                      ),
                    ),
                  ),
                
                // Overlay gradient for better text visibility
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: [0.0, 0.2, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
                

                
                // Content overlay - directly on video in social media style
                Positioned(
                  left: 16,
                  right: 16,
                    bottom: 95, // Increased to make more space for the button below
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title with shadow for better readability - only for YouTube
                      if (title.isNotEmpty && widget.platform.toLowerCase() == 'youtube')
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 3,
                                color: Colors.black.withOpacity(0.5),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      
                      SizedBox(height: 10),
                      
                      // Platform and date info for scheduled videos - above description
                      if (isScheduled && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              _buildPlatformLogo(widget.platform),
                              SizedBox(width: 10),
                              Text(
                                widget.formatTimestamp(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    video['scheduled_time'] as int? ?? 0
                                  ),
                                  true
                                ),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 3,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // Platform and date info for published videos - above description
                      if (!isScheduled && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              _buildPlatformLogo(widget.platform),
                              SizedBox(width: 10),
                              Text(
                                widget.formatTimestamp(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    publishedAt ?? _getVideoTimestamp(video)
                                  ),
                                  false
                                ),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1, 1),
                                          blurRadius: 3,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                              Spacer(),
                            ],
                          ),
                        ),
                      
                      // Description with shadow and animated fade
                      if (description.isNotEmpty)
                        GestureDetector(
                          onTap: () => _toggleDescription(index),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                AnimatedCrossFade(
                                  firstChild: Text(
                                description,
                                    style: TextStyle(
                                          color: Colors.white,
                                      fontSize: 14,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1, 1),
                                          blurRadius: 3,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  secondChild: Text(
                                    description,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 3,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                                  crossFadeState: isExpanded 
                                      ? CrossFadeState.showSecond 
                                      : CrossFadeState.showFirst,
                                  duration: Duration(milliseconds: 200),
                              ),
                            ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      

                      

                      
                  // Video controls at bottom - fixed position
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (description.isEmpty)
                              Expanded(
                                child: Row(
                                  children: [
                                    _buildPlatformLogo(widget.platform),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.formatTimestamp(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            isScheduled
                                                ? (video['scheduled_time'] as int? ?? 0)
                                                : (publishedAt ?? _getVideoTimestamp(video)),
                                          ),
                                          isScheduled,
                                        ),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          shadows: [
                                            Shadow(
                                              offset: Offset(1, 1),
                                              blurRadius: 3,
                                              color: Colors.black.withOpacity(0.5),
                                            ),
                                          ],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (hasVideo)
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      "${_formatDuration(currentPosition)} / ${_formatDuration(duration)}",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Spacer(),
                            if (!isScheduled)
                              GestureDetector(
                                onTap: () {
                                  _pauseCurrentVideo();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VideoDetailsPage(
                                        video: video,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  height: 28,
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 3,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.black,
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'View Details',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (isScheduled)
                              GestureDetector(
                                onTap: () {
                                  _pauseCurrentVideo();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ScheduledPostDetailsPage(
                                        post: video,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  height: 28,
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 3,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        color: Colors.black,
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'View Details',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (hasVideo) ...[
                          SizedBox(height: 8),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withOpacity(0.3),
                              thumbColor: Colors.white,
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                            ),
                            child: Slider(
                              value: currentPosition.inMilliseconds.toDouble(),
                              min: 0.0,
                              max: duration.inMilliseconds > 0 
                                  ? duration.inMilliseconds.toDouble() 
                                  : 1.0,
                              onChanged: (value) {
                                if (videoController != null) {
                                  setState(() {
                                    _isDraggingProgressBar = true;
                                    _currentPositions[index] = Duration(milliseconds: value.round());
                                  });
                                }
                              },
                              onChangeEnd: (value) {
                                if (videoController != null) {
                                  videoController.seekTo(Duration(milliseconds: value.round()));
                                  setState(() {
                                    _isDraggingProgressBar = false;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                
                // Close button
                Positioned(
                  top: 16,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                ],
              ),
            );
          },
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildPlatformLogo(String platform) {
    String logoPath;
    
    switch (platform.toLowerCase()) {
      case 'twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'youtube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'tiktok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
      case 'threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      default:
        logoPath = '';
        break;
    }
    
    if (logoPath.isNotEmpty) {
      return Container(
        width: 24,
        height: 24,
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          logoPath,
          fit: BoxFit.contain,
        ),
      );
    } else {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.public,
          color: Theme.of(context).colorScheme.primary,
          size: 14,
        ),
      );
    }
  }

  // Helper method to load media from Cloudflare or local file
  Widget _buildMediaPreview(Map<String, dynamic> video) {
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

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
    
    final mediaType = (video['media_type']?.toString().toLowerCase() ?? '');
    final isImage = video['is_image'] == true || mediaType == 'image' || mediaType == 'photo';
    
    // Se è un'immagine, mostra solo l'immagine senza overlay play
    if (isImage) {
      // Priorità: thumbnailCloudflareUrl > videoPath > thumbnailPath
      if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
        return Image.network(
          thumbnailCloudflareUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _buildDefaultMediaPlaceholder(),
        );
      }
      if (videoPath != null && videoPath.isNotEmpty) {
        if (videoPath.startsWith('http')) {
          return Image.network(
            videoPath,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => _buildDefaultMediaPlaceholder(),
          );
        } else {
          final file = File(videoPath);
          if (file.existsSync()) {
            return Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => _buildDefaultMediaPlaceholder(),
            );
          }
        }
      }
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        final file = File(thumbnailPath);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildDefaultMediaPlaceholder(),
          );
        }
      }
      return _buildDefaultMediaPlaceholder();
    }
    // Per i video, mostra solo il thumbnail senza overlay play
    if (videoPath != null && videoPath.isNotEmpty && videoPath.startsWith('http')) {
      return Image.network(
        thumbnailCloudflareUrl ?? videoPath,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.black,
          child: Center(
            child: Icon(
              Icons.video_library,
              color: Colors.white.withOpacity(0.5),
              size: 64,
            ),
          ),
        ),
      );
    }
    // Se nessun ramo precedente ha fatto return, restituisci sempre un widget di fallback
    return _buildDefaultMediaPlaceholder();
  }
  
  Widget _buildDefaultMediaPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.image,
          color: Colors.white.withOpacity(0.5),
          size: 64,
        ),
      ),
    );
  }

  // Function to handle video play/pause on tap
  void _toggleVideoPlayback() {
    if (_videoControllers[_currentIndex] != null &&
        _videoControllers[_currentIndex]!.value.isInitialized) {
      setState(() {
        if (_videoControllers[_currentIndex]!.value.isPlaying) {
          _videoControllers[_currentIndex]!.pause();
          _isVideoPlaying[_currentIndex] = false;
        } else {
          _videoControllers[_currentIndex]!.play();
          _isVideoPlaying[_currentIndex] = true;
        }
      });
    }
  }


// ... existing code ...

  // Add this method inside _FullscreenPostViewState
  void _pauseCurrentVideo() {
    final controller = _videoControllers[_currentIndex];
    if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
      controller.pause();
      setState(() {
        _isVideoPlaying[_currentIndex] = false;
      });
    }
  }
} 