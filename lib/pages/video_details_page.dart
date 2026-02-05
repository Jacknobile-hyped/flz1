import 'package:flutter/material.dart';
import 'dart:ui'; // Import for ImageFilter
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert'; // <--- AGGIUNTO per Utf8Decoder e jsonDecode
import 'package:firebase_database/firebase_database.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'video_stats_page.dart';
import 'settings_page.dart';
import 'upload_video_page.dart';
import 'help/troubleshooting_page.dart';
import '../services/navigation_service.dart';
import 'social/social_account_details_page.dart';

class VideoDetailsPage extends StatefulWidget {
  final Map<String, dynamic> video;

  const VideoDetailsPage({
    super.key,
    required this.video,
  });

  @override
  State<VideoDetailsPage> createState() => _VideoDetailsPageState();
}

class _VideoDetailsPageState extends State<VideoDetailsPage> with SingleTickerProviderStateMixin {
  Map<String, List<Map<String, dynamic>>> _socialAccounts = {};
  Map<String, String> _postUrls = {};
  bool _isLoadingUrls = true;
  late v2.TwitterApi _twitterApi;
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  
  // Tab controller e page controller per le sezioni
  late TabController _tabController;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

  bool _isLoading = true;
  Map<String, dynamic>? _videoDetails;
  VideoPlayerController? _videoPlayerController;
  bool _isPlaying = false;
  bool _isVideoInitialized = false;
  bool _isDisposed = false; // Track disposal state
  Timer? _autoplayTimer;
  bool _showControls = false;
  bool _isFullScreen = false;
  // For video progress tracking
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;

  // Carousel related variables for multi-media (caroselli)
  List<String> _mediaUrls = [];
  List<bool> _isImageList = [];
  PageController? _carouselController;
  int _currentCarouselIndex = 0;
  String? _currentVideoUrl; // Track current video URL to avoid re-initializing unnecessarily

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentPage = _tabController.index;
        });
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
        );
        // Pausa il video quando si passa alla tab 'Accounts'
        if (_tabController.index == 1) {
          _pauseVideoIfPlaying();
        }
      }
    });
    
    _initializeTwitterApi();
    _loadPostUrls();
    
    // Carica i dettagli del video
    _loadVideoDetails().then((_) {
      // Se abbiamo un carosello (cloudflare_urls), il player viene gestito da _initializeNetworkVideoPlayer
      final hasMultipleMedia = _mediaUrls.length > 1;
      
      // Inizializza il player solo per i video singoli (non carosello)
      if (!hasMultipleMedia && !_isImage) {
        _initializePlayer();
      }
      
      // Avvia il timer di aggiornamento posizione solo per i contenuti non carosello
      if (!hasMultipleMedia) {
      _startPositionUpdateTimer();
      setState(() {
        _showControls = true;
      });
      }
    });
  }

  // Build carousel media preview (carosello multi-media) - stessa logica di DraftDetailsPage
  Widget _buildCarouselMediaPreview(ThemeData theme) {
    // Get media URLs directly from _videoDetails or widget if _mediaUrls is empty (async loading)
    final videoDataToCheck = _videoDetails ?? widget.video;
    final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
    final mediaUrlsToUse = _mediaUrls.isNotEmpty
        ? _mediaUrls
        : (cloudflareUrls != null ? cloudflareUrls.cast<String>() : <String>[]);
    
    print('_buildCarouselMediaPreview (video_details_page) - mediaUrlsToUse.length: ${mediaUrlsToUse.length}');
    print('_buildCarouselMediaPreview (video_details_page) - _carouselController: ${_carouselController != null}');
    
    // Get image list directly or compute it
    List<bool> isImageListToUse;
    if (_isImageList.length == mediaUrlsToUse.length && _isImageList.isNotEmpty) {
      isImageListToUse = _isImageList;
    } else {
      isImageListToUse = List.generate(mediaUrlsToUse.length, (index) {
        final url = mediaUrlsToUse[index].toLowerCase();
        return url.contains('.jpg') ||
            url.contains('.jpeg') ||
            url.contains('.png') ||
            url.contains('.gif') ||
            url.contains('.webp') ||
            url.contains('.bmp') ||
            url.contains('.heic') ||
            url.contains('.heif');
      });
    }
    
    // Ensure carousel controller exists
    if (_carouselController == null && mediaUrlsToUse.isNotEmpty) {
      _carouselController = PageController(initialPage: 0);
      print('Created carousel controller on-the-fly (video_details_page)');
    }
    
    return Stack(
      children: [
        // Carousel with PageView
        PageView.builder(
          controller: _carouselController,
          onPageChanged: mediaUrlsToUse.length > 1 ? _onCarouselPageChanged : null,
          itemCount: mediaUrlsToUse.length,
          itemBuilder: (context, index) {
            final isImage = index < isImageListToUse.length ? isImageListToUse[index] : false;
            final mediaUrl = mediaUrlsToUse[index];
            
            if (isImage) {
              // Display image directly
              return Center(
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, url, error) => Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.grey[400],
                      size: 48,
                    ),
                  ),
                ),
              );
            } else {
              // Video: usa player di rete, inizializzato solo per elemento corrente
              if (index == _currentCarouselIndex) {
                return _buildVideoPlayerWidget(mediaUrl, theme, index == 0);
              } else {
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.video_library,
                          color: Colors.grey[400],
                          size: 48,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Video ${index + 1}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
          },
        ),
        
        // Carousel dot indicators (only show if more than 1 item)
        if (mediaUrlsToUse.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                mediaUrlsToUse.length,
                (index) => Container(
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentCarouselIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
        
        // Badge conteggio media in alto a sinistra
        if (mediaUrlsToUse.length > 1)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentCarouselIndex + 1}/${mediaUrlsToUse.length}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoplayTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _tabController.dispose();
    _pageController.dispose();
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    super.dispose();
  }

  // Check if the content is an image
  bool get _isImage => widget.video['is_image'] == true;

  String? _getVideoTitle() {
    // Prima prova a prendere il titolo dal campo title
    final title = widget.video['title'] as String?;
    if (title != null && !title.endsWith('.mp4')) {
      return title;
    }
    
    // Se il titolo non è presente o è il nome del file, usa la descrizione
    final description = widget.video['description'] as String?;
    if (description != null) {
      final titleFromDesc = description.split('#').first.trim();
      if (titleFromDesc.isNotEmpty) {
        return titleFromDesc;
      }
    }
    
    // Se non c'è né titolo né descrizione, usa il nome del file
    return title;
  }

  void _initializeTwitterApi() {
    _twitterApi = v2.TwitterApi(
      bearerToken: 'AAAAAAAAAAAAAAAAAAAAABSU0QEAAAAAo4YuWM0KL95fvPVsVk0EuIp%2B8tM%3DMh7GqySbNJX4qoTC3lpEycVl3x9cqQaRvbt1mwckSXszlBLmzM',
      oauthTokens: v2.OAuthTokens(
        consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
        consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
        accessToken: '1854892180193624064-DTblJdRTeYVNLpgAZPDomab286q7VB',
        accessTokenSecret: 'NxhkhdQifTYU7J5ek1i962RRqECPCs9CyaNDzr8YjLCMw',
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAccountsFromSubfolders(DatabaseReference platformRef) async {
    final snapshot = await platformRef.get();
    List<Map<String, dynamic>> accounts = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      // Caso 1: nodo diretto dell'account (mappa con campi account_*)
      final bool looksLikeSingleAccount = data.containsKey('account_username') ||
          data.containsKey('account_display_name') ||
          data.containsKey('account_id') ||
          data.containsKey('youtube_video_id') ||
          data.containsKey('media_id') ||
          data.containsKey('post_id');
      if (looksLikeSingleAccount) {
        final account = Map<String, dynamic>.from(data);
        // Normalizza YouTube: youtube_video_id -> post_id se mancante
        if ((account['post_id'] == null || account['post_id'].toString().isEmpty) &&
            account['youtube_video_id'] != null &&
            account['youtube_video_id'].toString().isNotEmpty) {
          account['post_id'] = account['youtube_video_id'].toString();
        }
        accounts.add(account);
      } else {
        // Caso 2: mappa di sotto-nodi account
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is Map && value.isNotEmpty) {
            final account = Map<String, dynamic>.from(value);
            if ((account['post_id'] == null || account['post_id'].toString().isEmpty) &&
                account['youtube_video_id'] != null &&
                account['youtube_video_id'].toString().isNotEmpty) {
              account['post_id'] = account['youtube_video_id'].toString();
            }
            accounts.add(account);
          }
        }
      }
    } else if (snapshot.exists && snapshot.value is List) {
      // Se la struttura è una lista
      final data = snapshot.value as List<dynamic>;
      for (final value in data) {
        if (value is Map && value.isNotEmpty) {
          final account = Map<String, dynamic>.from(value);
          if ((account['post_id'] == null || account['post_id'].toString().isEmpty) &&
              account['youtube_video_id'] != null &&
              account['youtube_video_id'].toString().isNotEmpty) {
            account['post_id'] = account['youtube_video_id'].toString();
          }
          accounts.add(account);
        }
      }
    }
    return accounts;
  }

  Future<void> _loadPostUrls() async {
    setState(() => _isLoadingUrls = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      final videoId = widget.video['id']?.toString();
      final userId = widget.video['user_id']?.toString();
      final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
      Map<String, String> urlsMap = {};
      if (isNewFormat) {
        // --- NUOVO FORMATO: accounts in sottocartelle ---
        final db = FirebaseDatabase.instance.ref();
        final platforms = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
        for (final platform in platforms) {
          final baseUserRef = db.child('users').child('users').child(userId!);
          // Prova prima scheduled_posts, poi fallback a videos
          final scheduledRef = baseUserRef.child('scheduled_posts').child(videoId!).child('accounts').child(platform);
          final videosRef = baseUserRef.child('videos').child(videoId!).child('accounts').child(platform);
          List<Map<String, dynamic>> accounts = await _fetchAccountsFromSubfolders(scheduledRef);
          if (accounts.isEmpty) {
            accounts = await _fetchAccountsFromSubfolders(videosRef);
          }
          for (final account in accounts) {
            final username = account['account_username']?.toString() ?? account['username']?.toString();
            final postId = account['post_id']?.toString();
            final mediaId = account['media_id']?.toString();
            if (username != null) {
              final platformKey = platform.toLowerCase();
              if (platformKey == 'twitter' && postId != null) {
                urlsMap['twitter_$username'] = 'https://twitter.com/i/status/$postId';
              } else if (platformKey == 'youtube' && (postId != null || mediaId != null || account['youtube_video_id'] != null)) {
                final videoId = postId ?? mediaId ?? account['youtube_video_id']?.toString();
                urlsMap['youtube_$username'] = 'https://www.youtube.com/watch?v=$videoId';
              } else if (platformKey == 'facebook') {
                final displayName = account['account_display_name']?.toString() ?? username;
                final pageId = await _getFacebookPageIdRobust(displayName);
                final finalPageId = pageId ?? username;
                final facebookUrl = 'https://m.facebook.com/profile.php?id=$finalPageId';
                urlsMap['facebook_$username'] = facebookUrl;
              } else if (platformKey == 'instagram') {
                urlsMap['instagram_$username'] = 'https://www.instagram.com/$username/';
              } else if (platformKey == 'tiktok' && mediaId != null) {
                urlsMap['tiktok_$username'] = 'https://www.tiktok.com/@$username/video/$mediaId';
              } else if (platformKey == 'tiktok') {
                urlsMap['tiktok_$username'] = 'https://www.tiktok.com/@$username';
              } else if (platformKey == 'threads') {
                urlsMap['threads_$username'] = 'https://threads.net/@$username';
              }
            }
          }
        }
      } else {
        // --- FORMATO VECCHIO: logica attuale ---
        final accounts = widget.video['accounts'];
        if (accounts != null && accounts is Map) {
          for (final platform in accounts.keys) {
            final platformAccounts = accounts[platform];
            if (platformAccounts is List) {
              for (var account in platformAccounts) {
                if (account is Map) {
                  final username = account['username']?.toString();
                  final postId = account['post_id']?.toString();
                  final mediaId = account['media_id']?.toString();
                  if (username != null) {
                    if (platform.toString().toLowerCase() == 'twitter' && postId != null) {
                      urlsMap['twitter_$username'] = 'https://twitter.com/i/status/$postId';
                    } else if (platform.toString().toLowerCase() == 'youtube' && (postId != null || mediaId != null)) {
                      final videoId = postId ?? mediaId;
                      urlsMap['youtube_$username'] = 'https://www.youtube.com/watch?v=$videoId';
                    } else if (platform.toString().toLowerCase() == 'facebook') {
                      final displayName = account['display_name']?.toString() ?? username;
                      final pageId = await _getFacebookPageIdRobust(displayName);
                      final finalPageId = pageId ?? username;
                      final facebookUrl = 'https://m.facebook.com/profile.php?id=$finalPageId';
                      urlsMap['facebook_$username'] = facebookUrl;
                    } else if (platform.toString().toLowerCase() == 'instagram') {
                      urlsMap['instagram_$username'] = 'https://www.instagram.com/$username/';
                      if (mediaId != null) {
                        account['has_media_id'] = true;
                      }
                    } else if (platform.toString().toLowerCase() == 'tiktok' && mediaId != null) {
                      urlsMap['tiktok_$username'] = 'https://www.tiktok.com/@$username/video/$mediaId';
                    } else if (platform.toString().toLowerCase() == 'tiktok') {
                      urlsMap['tiktok_$username'] = 'https://www.tiktok.com/@$username';
                    } else if (platform.toString().toLowerCase() == 'threads') {
                      urlsMap['threads_$username'] = 'https://threads.net/@$username';
                    }
                  }
                }
              }
            }
          }
        }
      }
      debugPrint('Final URL map: $urlsMap');
      setState(() {
        _postUrls = urlsMap;
      });
    } catch (e) {
      debugPrint('Error loading post URLs: $e');
    } finally {
      setState(() => _isLoadingUrls = false);
    }
  }

  Future<void> _loadVideoDetails() async {
    print("Load video details called");
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get current user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      final videoId = widget.video['id'] as String?;
      final userId = widget.video['user_id']?.toString();
      
      if (videoId == null || userId == null) {
        print("Video ID or User ID is null, using widget data");
        // Fallback to widget data if IDs are missing
        setState(() {
          _videoDetails = widget.video;
          _isLoading = false;
        });
        return;
      }
      
      // Load video details from Firebase
      final database = FirebaseDatabase.instance.ref();
      final videoRef = database
          .child('users')
          .child('users')
          .child(userId)
          .child('videos')
          .child(videoId);
      
      print("Loading video from Firebase path: users/users/$userId/videos/$videoId");
      
      final snapshot = await videoRef.get();
      if (snapshot.exists) {
        final firebaseVideoData = snapshot.value as Map<dynamic, dynamic>;
        
        // Merge Firebase data with widget data, prioritizing Firebase data
        final mergedVideoData = Map<String, dynamic>.from(widget.video);
        firebaseVideoData.forEach((key, value) {
          if (value != null) {
            mergedVideoData[key.toString()] = value;
          }
        });
        
        setState(() {
          _videoDetails = mergedVideoData;
          _isLoading = false;
        });
        
        print("Video details loaded from Firebase: ${mergedVideoData['id']}");
        print("Cloudflare URL from Firebase: ${mergedVideoData['cloudflare_url']}");
        print("Video path from Firebase: ${mergedVideoData['video_path']}");
        print("Thumbnail URL from Firebase: ${mergedVideoData['thumbnail_url']}");
        print("All Firebase keys: ${mergedVideoData.keys.toList()}");
      } else {
        print("Video not found in Firebase, using widget data");
        print("Widget video keys: ${widget.video.keys.toList()}");
        print("Widget thumbnail_url: ${widget.video['thumbnail_url']}");
        setState(() {
          _videoDetails = widget.video;
          _isLoading = false;
        });
      }
      
      // Gestione carosello: controlla se abbiamo cloudflare_urls (lista media) - PRIORITÀ su cloudflare_url
      final videoDataToCheck = _videoDetails ?? widget.video;
      final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
      
      print('Checking cloudflare_urls in video_details_page - keys: ${videoDataToCheck.keys.toList()}');
      print('cloudflare_urls type: ${cloudflareUrls.runtimeType}, value: $cloudflareUrls');
      
      if (cloudflareUrls != null && cloudflareUrls.isNotEmpty) {
        print('Found cloudflare_urls with ${cloudflareUrls.length} items (video_details_page)');
        
        // Popola le liste media/immagini
        _mediaUrls = cloudflareUrls.cast<String>();
        
        // Heuristica per capire se è immagine o video da estensione URL
        _isImageList = List.generate(_mediaUrls.length, (index) {
          final url = _mediaUrls[index].toLowerCase();
          return url.contains('.jpg') || 
                 url.contains('.jpeg') || 
                 url.contains('.png') || 
                 url.contains('.gif') ||
                 url.contains('.webp') ||
                 url.contains('.bmp') ||
                 url.contains('.heic') ||
                 url.contains('.heif');
        });
        
        print('Populated _mediaUrls with ${_mediaUrls.length} items, isImageList: $_isImageList (video_details_page)');
        
        // Inizializza il controller del carosello se abbiamo almeno un media
        if (_mediaUrls.isNotEmpty) {
          _carouselController = PageController(initialPage: 0);
          print('Initialized carousel controller for ${_mediaUrls.length} media (video_details_page)');
        }
        
        // Inizializza player per il primo media se è un video
        if (_mediaUrls.isNotEmpty && !_isImageList[0]) {
          final firstVideoUrl = _mediaUrls[0];
          _currentVideoUrl = firstVideoUrl;
          await _initializeNetworkVideoPlayer(firstVideoUrl);
        } else if (_mediaUrls.isNotEmpty && _isImageList[0]) {
          _currentVideoUrl = null;
        }
      } else {
        // Nessun carosello: reset liste
        _mediaUrls = [];
        _isImageList = [];
      }
      
      // Per le immagini singole, non è necessario inizializzare il player qui
      if (_isImage && _mediaUrls.isEmpty) {
        print("Content is a single image, skipping video player initialization");
      }
      
      // Non inizializziamo qui il player per i video: lo faremo in initState in base al numero di media
    } catch (e) {
      print('Error loading content details: $e');
      // Fallback to widget data on error
      setState(() {
        _videoDetails = widget.video;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;
    
    // Colore di sfondo più vivace ma velato per il video
    final videoBackgroundColor = Color(0xFF2C3E50).withOpacity(0.9); // Blu petrolio scuro e velato
    
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
        appBar: null,
        body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _isFullScreen
                // Layout semplificato per la modalità fullscreen
                ? GestureDetector(
                    onTap: () {
                      print("Tap on fullscreen container");
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    child: Container(
                      width: mediaWidth,
                      height: mediaHeight,
                      color: videoBackgroundColor,
                      child: Stack(
                        children: [
                          // Se il video è inizializzato, mostralo
                          if (_isVideoInitialized && _videoPlayerController != null)
                            Center(
                              child: _buildVideoPlayer(_videoPlayerController!),
                            ),
                          
                          // Controlli video in modalità fullscreen
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: Duration(milliseconds: 300),
                            child: Stack(
                              children: [
                                // Overlay semi-trasparente
                                Container(
                                  width: mediaWidth,
                                  height: mediaHeight,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.5),
                                        Colors.transparent,
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.5),
                                      ],
                                      stops: [0.0, 0.2, 0.8, 1.0],
                                    ),
                                  ),
                                ),
                                
                                // Pulsante per uscire dalla modalità fullscreen
                                Positioned(
                                  top: 60,
                                  left: 20,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.fullscreen_exit, color: Colors.white),
                                      onPressed: _toggleFullScreen,
                                    ),
                                  ),
                                ),
                                
                                // Pulsante Play/Pause al centro
                                Center(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        _videoPlayerController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                      padding: EdgeInsets.all(12),
                                      onPressed: _toggleVideoPlayback,
                                    ),
                                  ),
                                ),
                                
                                // Progress bar
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.7),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatDuration(_currentPosition),
                                              style: TextStyle(color: Colors.white, fontSize: 14),
                                            ),
                                            Text(
                                              _formatDuration(_videoDuration),
                                              style: TextStyle(color: Colors.white, fontSize: 14),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        SliderTheme(
                                          data: SliderThemeData(
                                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                            trackHeight: 4,
                                            activeTrackColor: Colors.white, // Colore bianco per la progress bar
                                            inactiveTrackColor: Colors.white.withOpacity(0.3),
                                            thumbColor: Colors.white,
                                          ),
                                          child: Slider(
                                            value: _currentPosition.inSeconds.toDouble(),
                                            min: 0.0,
                                            max: _videoDuration.inSeconds.toDouble() > 0 
                                                ? _videoDuration.inSeconds.toDouble() 
                                                : 1.0,
                                            onChanged: (value) {
                                              _videoPlayerController?.seekTo(Duration(seconds: value.toInt()));
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                                // Layout con Stack per permettere al contenuto di scorrere dietro i selettori
                : Stack(
                    children: [
                      // Main content area - no padding, content can scroll behind floating elements
                      SafeArea(
                        child: PageView(
                          controller: _pageController,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index;
                            });
                            _tabController.animateTo(index);
                          },
                          children: [
                            // Prima sezione: Video
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    )),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildVideoSection(theme, mediaWidth, videoBackgroundColor),
                            ),
                            // Seconda sezione: Accounts
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    )),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildAccountsSection(theme),
                            ),
                          ],
                        ),
                      ),
                      
                      // Floating header and tab bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            // Header
                            _buildHeader(),
                            
                            // Tab bar with glass effect
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      // Effetto vetro sospeso
                                      color: theme.brightness == Brightness.dark 
                                          ? Colors.white.withOpacity(0.15) 
                                          : Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(30),
                                      // Bordo con effetto vetro
                                      border: Border.all(
                                        color: theme.brightness == Brightness.dark 
                                            ? Colors.white.withOpacity(0.2)
                                            : Colors.white.withOpacity(0.4),
                                        width: 1,
                                      ),
                                      // Ombre per effetto sospeso
                                      boxShadow: [
                                        BoxShadow(
                                          color: theme.brightness == Brightness.dark 
                                              ? Colors.black.withOpacity(0.4)
                                              : Colors.black.withOpacity(0.15),
                                          blurRadius: theme.brightness == Brightness.dark ? 25 : 20,
                                          spreadRadius: theme.brightness == Brightness.dark ? 1 : 0,
                                          offset: const Offset(0, 10),
                                        ),
                                        BoxShadow(
                                          color: theme.brightness == Brightness.dark 
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
                                        colors: theme.brightness == Brightness.dark 
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
                                                Icon(_isImage ? Icons.image : Icons.video_library, size: 16),
                                                const SizedBox(width: 4),
                                                Text(_isImage ? 'Image' : 'Video'),
                                              ],
                                            ),
                                          ),
                                          Tab(
                                            icon: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.account_circle, size: 16),
                                                const SizedBox(width: 4),
                                                Text('Accounts'),
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
                          ],
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountsList(dynamic accounts, ThemeData theme) {
    try {
      final videoId = widget.video['id']?.toString();
      final userId = widget.video['user_id']?.toString() ?? _currentUserId;
      final isNewFormat = _isNewVideoFormat(videoId, userId);
      if (isNewFormat) {
        // --- FORMATO NUOVO: accounts in sottocartelle, fetch async e UI dinamica ---
        final platforms = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
        return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
          future: _fetchAllAccountsForNewFormat(userId!, videoId!),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 40),
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading accounts...'),
                  ],
                ),
              );
            }
            final platformsMap = snapshot.data!;
            if (platformsMap.isEmpty) {
              return Center(child: Text('No accounts found.'));
            }
            // --- UI simile al vecchio formato ---
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...platforms.where((p) => platformsMap[p]?.isNotEmpty == true).map((platform) {
                  final platformAccounts = platformsMap[platform]!;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      // Effetto vetro semi-trasparente opaco
                      color: theme.brightness == Brightness.dark 
                          ? Colors.white.withOpacity(0.15) 
                          : Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(16),
                      // Bordo con effetto vetro più sottile
                      border: Border.all(
                        color: theme.brightness == Brightness.dark 
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.4),
                        width: 1,
                      ),
                      // Ombra per effetto profondità e vetro
                      boxShadow: [
                        BoxShadow(
                          color: theme.brightness == Brightness.dark 
                              ? Colors.black.withOpacity(0.4)
                              : Colors.black.withOpacity(0.15),
                          blurRadius: theme.brightness == Brightness.dark ? 25 : 20,
                          spreadRadius: theme.brightness == Brightness.dark ? 1 : 0,
                          offset: const Offset(0, 10),
                        ),
                        // Ombra interna per effetto vetro
                        BoxShadow(
                          color: theme.brightness == Brightness.dark 
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
                        colors: theme.brightness == Brightness.dark 
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
                        // Platform header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            // Effetto vetro semi-trasparente per l'header
                            color: theme.brightness == Brightness.dark 
                                ? Colors.white.withOpacity(0.1) 
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                            // Bordo con effetto vetro
                            border: Border.all(
                              color: theme.brightness == Brightness.dark 
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                            // Ombra per effetto vetro
                            boxShadow: [
                              BoxShadow(
                                color: theme.brightness == Brightness.dark 
                                    ? Colors.black.withOpacity(0.2)
                                    : Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  // Icona con effetto vetro semi-trasparente
                                  color: theme.brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.brightness == Brightness.dark 
                                        ? Colors.white.withOpacity(0.3)
                                        : Colors.white.withOpacity(0.5),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.brightness == Brightness.dark 
                                          ? Colors.black.withOpacity(0.3)
                                          : Colors.black.withOpacity(0.15),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                    BoxShadow(
                                      color: theme.brightness == Brightness.dark 
                                          ? Colors.white.withOpacity(0.1)
                                          : Colors.white.withOpacity(0.4),
                                      blurRadius: 2,
                                      spreadRadius: -1,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  _platformLogos[platform.toLowerCase()] ?? '',
                                  width: 20,
                                  height: 20,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                platform.toUpperCase(),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
                                      ? Colors.white
                                      : _getPlatformColor(platform),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant),
                        ...platformAccounts.map((account) {
                          final username = account['account_username']?.toString() ?? account['username']?.toString() ?? '';
                          final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? username;
                          final profileImageUrl = account['account_profile_image_url']?.toString() ?? account['profile_image_url']?.toString() ?? '';
                          final followersCount = account['followers_count']?.toString() ?? '0';
                          final mediaId = account['media_id']?.toString();
                          final postId = account['post_id']?.toString();
                          final description = account['description']?.toString() ?? widget.video['description']?.toString() ?? '';
                          final title = account['title']?.toString() ?? widget.video['title']?.toString() ?? '';
                          String? postUrl;
                          bool hasMediaId = false;
                          final platformKey = platform.toLowerCase();
                          if (platformKey == 'twitter' && postId != null) {
                            postUrl = 'https://twitter.com/i/status/$postId';
                          } else if (platformKey == 'youtube' && (postId != null || mediaId != null || account['youtube_video_id'] != null)) {
                            final videoId = postId ?? mediaId ?? account['youtube_video_id']?.toString();
                            postUrl = 'https://www.youtube.com/watch?v=$videoId';
                          } else if (platformKey == 'facebook') {
                            postUrl = 'https://m.facebook.com/profile.php?id=$username';
                          } else if (platformKey == 'instagram') {
                            postUrl = 'https://www.instagram.com/$username/';
                            hasMediaId = mediaId != null;
                          } else if (platformKey == 'tiktok' && mediaId != null) {
                            postUrl = 'https://www.tiktok.com/@$username/video/$mediaId';
                            hasMediaId = true;
                          } else if (platformKey == 'tiktok') {
                            postUrl = 'https://www.tiktok.com/@$username';
                          } else if (platformKey == 'threads') {
                            postUrl = 'https://threads.net/@$username';
                          }
                          return Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Profile image
                                GestureDetector(
                                  onTap: () => _navigateToSocialAccountDetails(account, platform),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 5,
                                          spreadRadius: 1,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: theme.colorScheme.surface,
                                      backgroundImage: profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
                                      child: profileImageUrl.isEmpty
                                          ? Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: _getPlatformColor(platform).withOpacity(0.3),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  (username.isNotEmpty ? username[0] : '?').toUpperCase(),
                                                  style: TextStyle(
                                                    color: _getPlatformColor(platform),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Account details
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _navigateToSocialAccountDetails(account, platform),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          platformKey == 'tiktok' ? username : '@$username',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Action buttons
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => _showPostDetailsBottomSheet(context, account, platform),
                                      icon: Icon(Icons.info_outline, size: 20),
                                      style: IconButton.styleFrom(
                                        foregroundColor: (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
                                            ? Colors.white
                                            : _getPlatformColor(platform),
                                        backgroundColor: _getPlatformLightColor(platform),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      tooltip: 'View post details',
                                    ),
                                    SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () async {
                                        if (platformKey == 'instagram') {
                                          await _openInstagramPostOrProfile(account);
                                        } else if (platformKey == 'threads') {
                                          await _openThreadsPostOrProfile(account);
                                        } else if (platformKey == 'facebook') {
                                          await _openFacebookPostOrProfile(account);
                                        } else if (platformKey == 'tiktok' && hasMediaId) {
                                          _openTikTokWithMediaId(username, mediaId!);
                                        } else if (postUrl != null && postUrl.isNotEmpty) {
                                          _openSocialMedia(postUrl);
                                        }
                                      },
                                      icon: const Icon(Icons.open_in_new, size: 20),
                                      style: IconButton.styleFrom(
                                        foregroundColor: (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
                                            ? Colors.white
                                            : _getPlatformColor(platform),
                                        backgroundColor: _getPlatformLightColor(platform),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      tooltip: 'View post',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        );
      } else {
        // --- FORMATO VECCHIO: logica attuale ---
        (accounts as Map).forEach((platform, platformAccounts) {
          if (platform is String) {
            final processedAccounts = <Map<String, dynamic>>[];
            
            // Handle two possible data formats: array of maps (new format) or array of strings (old format)
            if (platformAccounts is List) {
              // New format - platformAccounts is a list of maps with full account details
              for (var account in platformAccounts) {
                if (account is Map) {
                  final username = account['username']?.toString() ?? '';
                  final platformKey = platform.toLowerCase();
                  final mediaId = account['media_id']?.toString();
                  final postId = account['post_id']?.toString();
                  final displayName = account['display_name']?.toString() ?? username;
                  final profileImageUrl = account['profile_image_url']?.toString() ?? '';
                  final followersCount = account['followers_count']?.toString() ?? '0';
                  // Per il formato vecchio, prendi la descrizione dall'account specifico se disponibile
                  final description = account['description']?.toString() ?? widget.video['description']?.toString() ?? '';
                  final title = account['title']?.toString() ?? widget.video['title']?.toString() ?? '';
                  String? postUrl;
                  bool hasMediaId = false;
                  if (platformKey == 'twitter' && postId != null) {
                    postUrl = 'https://twitter.com/i/status/$postId';
                  } else if (platformKey == 'youtube' && (postId != null || mediaId != null || account['youtube_video_id'] != null)) {
                    final videoId = postId ?? mediaId ?? account['youtube_video_id']?.toString();
                    postUrl = 'https://www.youtube.com/watch?v=$videoId';
                  } else if (platformKey == 'facebook') {
                    // Per Facebook, apri direttamente la pagina profilo
                    // Per ora usa il username, il page_id verrà gestito quando si clicca il bottone
                    final facebookUrl = 'https://m.facebook.com/profile.php?id=$username';
                    postUrl = facebookUrl;
                  } else if (platformKey == 'instagram') {
                    // Per Instagram, apri direttamente la pagina profilo
                    postUrl = 'https://www.instagram.com/$username/';
                    hasMediaId = mediaId != null;
                  } else if (platformKey == 'tiktok' && mediaId != null) {
                    postUrl = 'https://www.tiktok.com/@$username/video/$mediaId';
                    hasMediaId = true;
                  } else if (platformKey == 'tiktok') {
                    postUrl = 'https://www.tiktok.com/@$username';
                  } else if (platformKey == 'threads') {
                    // Per Threads, apri direttamente la pagina profilo
                    postUrl = 'https://threads.net/@$username';
                  }
                  processedAccounts.add({
                    'username': username,
                    'display_name': displayName,
                    'profile_image_url': profileImageUrl,
                    'followers_count': followersCount,
                    'post_url': postUrl,
                    'media_id': mediaId,  // Store the media ID for Instagram and Threads
                    'has_media_id': hasMediaId,
                    'title': title,  // Add title for bottom sheet
                    'description': description,  // Add description for bottom sheet
                  });
                }
              }
            } else if (platformAccounts is Map) {
              // Old format - may be a map of account IDs
              platformAccounts.forEach((accountId, accountValue) {
                final username = accountId.toString();
                final platformKey = platform.toLowerCase();
                // Per il formato molto vecchio, usa la descrizione globale
                final description = widget.video['description']?.toString() ?? '';
                final title = widget.video['title']?.toString() ?? '';
                String? postUrl;
                if (platformKey == 'twitter') {
                  postUrl = 'https://twitter.com/$username';
                } else if (platformKey == 'youtube') {
                  postUrl = 'https://www.youtube.com/channel/$username';
                } else if (platformKey == 'facebook') {
                  postUrl = 'https://facebook.com/$username';
                } else if (platformKey == 'instagram') {
                  postUrl = 'https://www.instagram.com/$username/';
                } else if (platformKey == 'tiktok') {
                  postUrl = 'https://www.tiktok.com/@$username';
                } else if (platformKey == 'threads') {
                  postUrl = 'https://threads.net/@$username';
                }
                processedAccounts.add({
                  'username': username,
                  'display_name': username, // Fallback to username
                  'profile_image_url': '', // No profile image available
                  'post_url': postUrl,
                  'title': title,
                  'description': description,
                });
              });
            }
            if (processedAccounts.isNotEmpty) {
              _socialAccounts[platform] = processedAccounts;
            }
          }
        });
      }

      if (_socialAccounts.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo 
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0),
                    borderRadius: BorderRadius.circular(0),
                  ),
                ),
              ],
            ),
          ),
          
          // Platforms
          ..._socialAccounts.entries.map((entry) {
          final platform = entry.key;
          final platformAccounts = entry.value;
          
          return Container(
              width: double.infinity, // Assicura che prenda tutta la larghezza disponibile
              margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
                border: Border.all(
              color: theme.colorScheme.surfaceVariant,
                  width: 1,
                ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Platform header
                  Container(
                  padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getPlatformLightColor(platform),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                    ),
                  child: Row(
                    children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: _getPlatformColor(platform).withOpacity(0.2),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Image.asset(
                        _platformLogos[platform.toLowerCase()] ?? '',
                            width: 20,
                            height: 20,
                        fit: BoxFit.contain,
                      ),
                        ),
                        const SizedBox(width: 14),
                      Text(
                        platform.toUpperCase(),
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
                                ? Colors.white
                                : _getPlatformColor(platform),
                        ),
                      ),
                    ],
                  ),
                ),
                  
                  // Divider
                  Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant),
                
                // List of accounts for this platform
                ...platformAccounts.map((account) {
                  final isInstagram = platform.toLowerCase() == 'instagram';
                  final isThreads = platform.toLowerCase() == 'threads';
                  final hasMediaId = account['has_media_id'] == true;
                  final mediaId = account['media_id']?.toString();
                  final username = account['username']?.toString() ?? '';
                  final postUrl = account['post_url']?.toString();
                  
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Profile image with shadow and border
                        GestureDetector(
                          onTap: () => _navigateToSocialAccountDetails(account, platform),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 5,
                                  spreadRadius: 1,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: theme.colorScheme.surface,
                            backgroundImage: account['profile_image_url']?.isNotEmpty == true
                                ? NetworkImage(account['profile_image_url'] as String)
                                : null,
                            child: account['profile_image_url']?.isNotEmpty != true
                                  ? Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _getPlatformColor(platform).withOpacity(0.3),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                    (username.isNotEmpty ? username[0] : '?').toUpperCase(),
                                    style: TextStyle(
                                            color: _getPlatformColor(platform),
                                      fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                    ),
                                  )
                                : null,
                          ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Account details
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _navigateToSocialAccountDetails(account, platform),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account['display_name'] as String? ?? username,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  platform.toLowerCase() == 'tiktok' ? username : '@$username',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Action buttons - logica unificata per tutte le piattaforme
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Info button sempre presente
                            IconButton(
                              onPressed: () => _showPostDetailsBottomSheet(context, account, platform),
                              icon: Icon(Icons.info_outline, size: 20),
                              style: IconButton.styleFrom(
                              foregroundColor: (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
                                  ? Colors.white
                                  : _getPlatformColor(platform),
                                backgroundColor: _getPlatformLightColor(platform),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                              tooltip: 'View post details',
                            ),
                            SizedBox(width: 8),
                            
                            // View button con logica differenziata per tipo di piattaforma
                            if (_isLoadingUrls)
                              // Loading indicator
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(_getPlatformColor(platform)),
                                ),
                              )
                            else
                          IconButton(
                                onPressed: () async {
                                  if (platform.toLowerCase() == 'instagram') {
                                    await _openInstagramPostOrProfile(account);
                                  } else if (platform.toLowerCase() == 'threads') {
                                    await _openThreadsPostOrProfile(account);
                                  } else if (platform.toLowerCase() == 'facebook') {
                                    await _openFacebookPostOrProfile(account);
                                  } else if (platform.toLowerCase() == 'tiktok' && hasMediaId) {
                                    _openTikTokWithMediaId(username, mediaId!);
                                  } else if (postUrl != null && postUrl.isNotEmpty) {
                                    _openSocialMedia(postUrl);
                                  }
                                },
                          icon: const Icon(Icons.open_in_new, size: 20),
                          style: IconButton.styleFrom(
                                foregroundColor: (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
                                    ? Colors.white
                                    : _getPlatformColor(platform),
                              backgroundColor: _getPlatformLightColor(platform),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          tooltip: 'View post',
                              ),
                          ],
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }).toList(),
        ],
      );
    } catch (e) {
      debugPrint('Error building accounts list: $e');
      return const SizedBox.shrink();
    }
  }

  void _openSocialMedia(String url) async {
    // Gestione speciale per Facebook
    if (url.contains('m.facebook.com/profile.php')) {
      // Estrai il page_id dall'URL
      final uri = Uri.parse(url);
      final pageIdOrName = uri.queryParameters['id'];
      if (pageIdOrName != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          // Prova a cercare il page_id corretto usando il display_name (anche se è già un id numerico, la funzione restituirà comunque quello)
          final correctPageId = await _getFacebookPageIdRobust(pageIdOrName);
          final finalPageId = correctPageId ?? pageIdOrName;
          final facebookUrl = 'https://m.facebook.com/profile.php?id=$finalPageId';
          print('[FACEBOOK URL - CLICK] Original: $pageIdOrName, Correct: $correctPageId, Final: $finalPageId, URL: $facebookUrl');
          final uri = Uri.parse(facebookUrl);
          if (await canLaunchUrl(uri)) {
            // FORZA apertura nel browser di sistema
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        }
      }
    }
    // Gestione normale per tutte le altre piattaforme
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch $url');
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
        if (!_isDisposed) {
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

  // Method to open Threads profile
  void _openThreadsProfile(String username) async {
    // Try opening Threads app with username first
    final threadsUserUri = Uri.parse('threads://user/$username');
    try {
      if (await canLaunchUrl(threadsUserUri)) {
        await launchUrl(threadsUserUri);
        return;
      }
    } catch (e) {
      debugPrint('Error launching Threads app with username: $e');
    }
    
    // Fallback to web URL if app launch fails
    final webProfileUri = Uri.parse('https://threads.net/@$username');
    try {
      if (await canLaunchUrl(webProfileUri)) {
        await launchUrl(webProfileUri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch Threads web URL');
        // Show a snackbar to inform the user
        if (!_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open Threads. Please check your internet connection.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching Threads web URL: $e');
    }
  }

  // Method to open TikTok with a specific username and media ID
  void _openTikTokWithMediaId(String username, String mediaId) async {
    // First try to open TikTok app with the video URL
    final tiktokVideoUri = Uri.parse('tiktok://video/$mediaId');
    
    // Try to launch TikTok app with direct video ID first
    try {
      if (await canLaunchUrl(tiktokVideoUri)) {
        await launchUrl(tiktokVideoUri);
        return;
      }
    } catch (e) {
      debugPrint('Error launching TikTok app with video ID: $e');
    }
    
    // If direct video access fails, try opening TikTok app with username
    final tiktokUserUri = Uri.parse('tiktok://user/$username');
    try {
      if (await canLaunchUrl(tiktokUserUri)) {
        await launchUrl(tiktokUserUri);
        // Show message that we couldn't open the specific video
        if (!_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opened TikTok profile. The specific video could not be accessed directly.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error launching TikTok app with username: $e');
    }
    
    // Fallback to web URL if app launch fails
    final webVideoUri = Uri.parse('https://www.tiktok.com/@$username/video/$mediaId');
    try {
      if (await canLaunchUrl(webVideoUri)) {
        await launchUrl(webVideoUri, mode: LaunchMode.externalApplication);
      } else {
        // If direct video URL fails, try profile URL
        final webProfileUri = Uri.parse('https://www.tiktok.com/@$username');
        if (await canLaunchUrl(webProfileUri)) {
          await launchUrl(webProfileUri, mode: LaunchMode.externalApplication);
          // Inform user that direct video access failed
          if (!_isDisposed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open specific TikTok video. Opening profile instead.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          debugPrint('Could not launch TikTok web URL');
          // Show a snackbar to inform the user
          if (!_isDisposed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open TikTok. Please check your internet connection.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error launching TikTok web URL: $e');
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Colors.black;
      case 'youtube':
        return Colors.red;
      case 'tiktok':
        return Colors.black;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue;
      case 'threads':
        return Colors.black;
      default:
        return Colors.grey;
    }
  }

  LinearGradient _getPlatformGradient(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'instagram':
        return LinearGradient(
          colors: [
            Color(0xFFC13584), // Instagram gradient start
            Color(0xFFE1306C), // Instagram gradient middle
            Color(0xFFF56040), // Instagram gradient end
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'tiktok':
        return LinearGradient(
          colors: [
            Color(0xFF00F2EA), // TikTok turchese
            Color(0xFFFF0050), // TikTok rosa
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'twitter':
        return LinearGradient(
          colors: [
            Colors.black,
            Colors.black87,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return LinearGradient(
          colors: [
            _getPlatformColor(platform),
            _getPlatformColor(platform),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  void _toggleVideoPlayback() {
    print("Toggle video playback called");
    
    if (_videoPlayerController == null) {
      print("Controller is null, initializing");
      _initializePlayer();
      return;
    }
    
    if (!_videoPlayerController!.value.isInitialized) {
      print("Controller not initialized");
      return;
    }
    
    if (_videoPlayerController!.value.isPlaying) {
      print("Pausing video");
      _videoPlayerController!.pause();
      _autoplayTimer?.cancel();
      setState(() {
        _isPlaying = false;
        _showControls = true; // Show controls when paused
      });
    } else {
      print("Playing video");
      // Retry play if there's an error or player is at end
      if (_videoPlayerController!.value.position >= _videoPlayerController!.value.duration) {
        // Se il video è finito, riavvialo dall'inizio
        _videoPlayerController!.seekTo(Duration.zero);
      }
      
      _videoPlayerController!.play().then((_) {
        // Aggiorna lo stato solo se il play è riuscito
        if (mounted && !_isDisposed) {
          print("Play succeeded");
      setState(() {
        _isPlaying = true;
          });
        }
      }).catchError((error) {
        print('Error playing video: $error');
        // Mostra messaggio d'errore
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore nella riproduzione del video. Riprova.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
      
      setState(() {
        _isPlaying = true; // Aggiorniamo immediatamente per feedback UI
        // Hide controls after a delay
        Future.delayed(Duration(seconds: 3), () {
          if (mounted && !_isDisposed && _isPlaying) {
            setState(() {
              _showControls = false;
            });
          }
        });
      });
      
      // Auto-stop after 30 seconds to save resources
      _autoplayTimer?.cancel();
      _autoplayTimer = Timer(const Duration(seconds: 30), () {
        if (_videoPlayerController != null && !_isDisposed) {
          _videoPlayerController!.pause();
          setState(() {
            _isPlaying = false;
            _showControls = true; // Show controls when auto-paused
          });
        }
      });
    }
  }
  
  // Handle video player events
  void _onVideoPositionChanged() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        mounted && 
        !_isDisposed) {
      final isPlayingNow = _videoPlayerController!.value.isPlaying;
      final isAtEnd = _videoPlayerController!.value.position >= _videoPlayerController!.value.duration - Duration(milliseconds: 300);
      
      setState(() {
        _currentPosition = _videoPlayerController!.value.position;
        
        // Update isPlaying based on actual player state
        if (_isPlaying != isPlayingNow) {
          _isPlaying = isPlayingNow;
        }
      });
      
      // Show controls and update playing state when video ends
      if (isAtEnd && _isPlaying) {
        setState(() {
          _isPlaying = false;
          _showControls = true;
        });
      }
    }
  }

  void _initializePlayer() {
    print("Initialize player called");
    
    if (_videoDetails == null) {
      print("Video details is null");
      return;
    }
    
    // Skip video initialization for images
    if (_isImage) {
      print('Content is an image, skipping video player initialization');
      return;
    }
    
    // Clean up any existing controller first
    if (_videoPlayerController != null) {
      print("Disposing existing controller");
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    
    setState(() {
      _isVideoInitialized = false;
      _showControls = true; // Show controls when initializing
      _isPlaying = false; // Reset playing state
    });
    
    try {
      print("Creating new video controller");
      
      // Priority order for video sources:
      // 1. cloudflare_url from Firebase (highest priority)
      // 2. video_path from Firebase (if it's a URL)
      // 3. local video_path file
      // 4. fallback to widget data
      
      String? videoUrl;
      String? videoSource;
      
      // Riconosci se è formato nuovo
      final videoId = _videoDetails!['id']?.toString();
      final userId = _videoDetails!['user_id']?.toString() ?? _currentUserId;
      final isNewFormat = _isNewVideoFormat(videoId, userId);
      
      if (isNewFormat) {
        // --- FORMATO NUOVO: usa SOLO _videoDetails['media_url'] come sorgente video ---
        final mediaUrl = _videoDetails!['media_url'] as String?;
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          videoUrl = mediaUrl;
          videoSource = 'firebase_media_url';
          print('Using media_url from _videoDetails (new format): $mediaUrl');
        }
      } else {
        // --- FORMATO VECCHIO: logica attuale ---
        // First, try cloudflare_url from Firebase data
        final cloudflareUrl = _videoDetails!['cloudflare_url'] as String?;
        if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
          videoUrl = cloudflareUrl;
          videoSource = 'cloudflare_url';
          print('Using cloudflare_url from Firebase: $cloudflareUrl');
        } else {
          // Try video_path from Firebase data
          final videoPath = _videoDetails!['video_path'] as String?;
          if (videoPath != null && videoPath.isNotEmpty) {
            // Check if video_path is a URL
            if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
              videoUrl = videoPath;
              videoSource = 'video_path_url';
              print('Using video_path URL from Firebase: $videoPath');
            } else {
              // Check if local file exists
              final videoFile = File(videoPath);
              if (videoFile.existsSync()) {
                videoUrl = videoPath;
                videoSource = 'local_file';
                print('Using local video file: $videoPath');
              } else {
                print('Local video file not found: $videoPath');
              }
            }
          }
        }
        // If no video source found in Firebase data, try widget data as fallback
        if (videoUrl == null) {
          final widgetCloudflareUrl = widget.video['cloudflare_url'] as String?;
          if (widgetCloudflareUrl != null && widgetCloudflareUrl.isNotEmpty) {
            videoUrl = widgetCloudflareUrl;
            videoSource = 'widget_cloudflare_url';
            print('Using cloudflare_url from widget data: $widgetCloudflareUrl');
          } else {
            final widgetVideoPath = widget.video['video_path'] as String?;
            if (widgetVideoPath != null && widgetVideoPath.isNotEmpty) {
              if (widgetVideoPath.startsWith('http://') || widgetVideoPath.startsWith('https://')) {
                videoUrl = widgetVideoPath;
                videoSource = 'widget_video_path_url';
                print('Using video_path URL from widget data: $widgetVideoPath');
              } else {
                final videoFile = File(widgetVideoPath);
                if (videoFile.existsSync()) {
                  videoUrl = widgetVideoPath;
                  videoSource = 'widget_local_file';
                  print('Using local video file from widget data: $widgetVideoPath');
                }
              }
            }
          }
        }
      }
      
      if (videoUrl == null) {
        print('No video resource available');
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No video source found'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      // Create video controller based on source type
      if (videoSource == 'local_file' || videoSource == 'widget_local_file') {
        _videoPlayerController = VideoPlayerController.file(File(videoUrl));
        print('Created file video controller');
      } else {
        _videoPlayerController = VideoPlayerController.network(videoUrl);
        print('Created network video controller');
      }
      
      // Add listener for player events
      _videoPlayerController!.addListener(_onVideoPositionChanged);
      
      _videoPlayerController!.initialize().then((_) {
        print("Video controller initialized successfully");
        if (!mounted || _isDisposed) return;
        
        // Determine if video is horizontal (aspect ratio > 1)
        final bool isHorizontalVideo = _videoPlayerController!.value.aspectRatio > 1.0;
        
        print("Video aspect ratio: \\${_videoPlayerController!.value.aspectRatio}");
        print("Is horizontal video: \\${isHorizontalVideo}");
        
        setState(() {
          _isVideoInitialized = true;
          _videoDuration = _videoPlayerController!.value.duration;
          _currentPosition = Duration.zero;
          _showControls = true; // Keep controls visible
        });
        
      }).catchError((error) {
        print('Error initializing video player: $error');
        
        // Handle errors properly
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to play video: \\${error.toString().substring(0, min(error.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      });
    } catch (e) {
      print('Exception during video controller creation: $e');
      
      setState(() {
        _isVideoInitialized = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating video player: \\${e.toString().substring(0, min(e.toString().length, 50))}...'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildImagePreview(String imagePath) {
    final imageFile = File(imagePath);
    
    // Check if local file exists
    if (imageFile.existsSync()) {
      return Image.file(
        imageFile,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading local image: $error, trying Cloudflare URL');
          // If local file fails, try Cloudflare URL
          return _loadCloudflareImage();
        },
      );
    } 
    
    // Try Cloudflare URL if local file doesn't exist
    return _loadCloudflareImage();
  }

  // Helper method to load image from Cloudflare
  Widget _loadCloudflareImage() {
    // Riconosci se è formato nuovo
    final videoId = _videoDetails?['id']?.toString();
    final userId = _videoDetails?['user_id']?.toString() ?? _currentUserId;
    final isNewFormat = _isNewVideoFormat(videoId, userId);
    if (isNewFormat) {
      // --- FORMATO NUOVO: usa SOLO _videoDetails['thumbnail_url'], fallback widget.video['thumbnail_url'] ---
      final thumbUrl = _videoDetails?['thumbnail_url'] as String?;
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        print('Using thumbnail_url from _videoDetails (new format): $thumbUrl');
        return Image.network(
          thumbUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, url, error) => _buildFallbackImage(),
        );
      }
      // Fallback: widget.video['thumbnail_url']
      final widgetThumbUrl = widget.video['thumbnail_url'] as String?;
      if (widgetThumbUrl != null && widgetThumbUrl.isNotEmpty) {
        print('Using thumbnail_url from widget.video (new format fallback): $widgetThumbUrl');
        return Image.network(
          widgetThumbUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, url, error) => _buildFallbackImage(),
        );
      }
      // Se non c'è nulla, mostra fallback
      return _buildFallbackImage();
    }
    // --- FORMATO VECCHIO: logica attuale ---
    final cloudflareUrl = _videoDetails?['cloudflare_url'] as String?;
    if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
      print('Using Cloudflare URL from Firebase for image: $cloudflareUrl');
      return Image.network(
        cloudflareUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) {
          // If cloudflare_url fails, try thumbnail_cloudflare_url from Firebase
          final thumbnailUrl = _videoDetails?['thumbnail_cloudflare_url'] as String?;
          if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
            return Image.network(
              thumbnailUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / 
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, url, error) => _buildFallbackImage(),
            );
          }
          
          // If everything fails, show error icon
          return _buildFallbackImage();
        },
      );
    }
    
    // If no cloudflare_url from Firebase, try thumbnail_cloudflare_url from Firebase
    final thumbnailUrl = _videoDetails?['thumbnail_cloudflare_url'] as String?;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      print('Using thumbnail Cloudflare URL from Firebase for image: $thumbnailUrl');
      return Image.network(
        thumbnailUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) => _buildFallbackImage(),
      );
    }
    
    // Fallback to widget data
    final widgetCloudflareUrl = widget.video['cloudflare_url'] as String?;
    if (widgetCloudflareUrl != null && widgetCloudflareUrl.isNotEmpty) {
      print('Using Cloudflare URL from widget data for image: $widgetCloudflareUrl');
      return Image.network(
        widgetCloudflareUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) {
          // If widget cloudflare_url fails, try widget thumbnail_cloudflare_url
          final widgetThumbnailUrl = widget.video['thumbnail_cloudflare_url'] as String?;
          if (widgetThumbnailUrl != null && widgetThumbnailUrl.isNotEmpty) {
            return Image.network(
              widgetThumbnailUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / 
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, url, error) => _buildFallbackImage(),
            );
          }
          
          return _buildFallbackImage();
        },
      );
    }
    
    // If no widget cloudflare_url, try widget thumbnail_cloudflare_url
    final widgetThumbnailUrl = widget.video['thumbnail_cloudflare_url'] as String?;
    if (widgetThumbnailUrl != null && widgetThumbnailUrl.isNotEmpty) {
      print('Using thumbnail Cloudflare URL from widget data for image: $widgetThumbnailUrl');
      return Image.network(
        widgetThumbnailUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) => _buildFallbackImage(),
      );
    }
    
    // Default fallback
    return _buildFallbackImage();
  }
  
  // Helper function to get fallback thumbnail
  Widget _getFallbackThumbnail() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.video_library,
          color: Colors.grey[400],
          size: 48,
        ),
      ),
    );
  }
  
  Widget _buildFallbackImage() {
    return Icon(
      Icons.image_not_supported,
      color: Colors.grey[400],
      size: 48,
    );
  }

  // Start a timer to update the video position periodically
  void _startPositionUpdateTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_videoPlayerController != null && 
          _videoPlayerController!.value.isInitialized && 
          mounted && 
          !_isDisposed) {
        setState(() {
          _currentPosition = _videoPlayerController!.value.position;
          _videoDuration = _videoPlayerController!.value.duration;
        });
      }
    });
  }

  // Helper functions for formatting time - formato più compatto
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds'; // Non aggiungo padding per i minuti per risparmiare spazio
  }

  // Function to toggle fullscreen mode
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      // Always show controls when toggling fullscreen
      _showControls = true;
      
      // Hide controls after a delay
      if (_isFullScreen && _isPlaying) {
        Future.delayed(Duration(seconds: 3), () {
          if (mounted && !_isDisposed && _isPlaying) {
            setState(() {
              _showControls = false;
            });
          }
        });
      }
    });
  }

  // Function to show controls temporarily
  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });
    
    // Auto-hide controls after 3 seconds if video is playing
    Future.delayed(Duration(seconds: 3), () {
      if (mounted && !_isDisposed && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  // Aggiunta della funzione per ottenere il colore chiaro di una piattaforma
  Color _getPlatformLightColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Colors.blue.withOpacity(0.08);
      case 'youtube':
        return Colors.red.withOpacity(0.08);
      case 'tiktok':
        return Colors.black.withOpacity(0.05);
      case 'instagram':
        return Colors.purple.withOpacity(0.08);
      case 'facebook':
        return Colors.blue.withOpacity(0.08);
      case 'threads':
        return Colors.black.withOpacity(0.05);
      default:
        return Colors.grey.withOpacity(0.08);
    }
  }

  // Funzione per mostrare la tendina con i dettagli del post
  void _showPostDetailsBottomSheet(BuildContext context, Map<String, dynamic> account, String platform) {
    final theme = Theme.of(context);
    final platformColor = (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
        ? Colors.white
        : _getPlatformColor(platform);
    // Estrai i dati del post, compatibile con nuovo formato
    final username = account['account_username']?.toString() ?? account['username']?.toString() ?? '';
    final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? username;
    final profileImageUrl = account['account_profile_image_url']?.toString() ?? account['profile_image_url']?.toString();
    final title = account['title']?.toString() ?? '';
    final description = account['description']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 0,
              offset: Offset(0, -2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Linea in alto per indicare che è trascinabile
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // Intestazione con piattaforma
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getPlatformLightColor(platform),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      _platformLogos[platform.toLowerCase()] ?? '',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '$platform Post Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: platformColor,
                    ),
                  ),
                ],
              ),
            ),
            // Informazioni profilo
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _getPlatformLightColor(platform),
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Profile image
                  GestureDetector(
                    onTap: () => _navigateToSocialAccountDetails(account, platform),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(
                          color: theme.cardColor,
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: theme.cardColor,
                        backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                            ? NetworkImage(profileImageUrl)
                            : null,
                        child: profileImageUrl == null || profileImageUrl.isEmpty
                            ? Text(
                                username.isNotEmpty ? username[0].toUpperCase() : '',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: platformColor,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _navigateToSocialAccountDetails(account, platform),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            platform.toLowerCase() == 'tiktok' ? username : '@$username',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: _getPlatformGradient(platform),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _getPlatformColor(platform).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                    onPressed: () {
                      if (platform.toLowerCase() == 'instagram') {
                        _openInstagramProfile(username);
                      } else if (platform.toLowerCase() == 'threads') {
                        _openThreadsProfile(username);
                      } else if (account['post_url'] != null && account['post_url'].toString().isNotEmpty) {
                        _openSocialMedia(account['post_url']);
                      }
                    },
                    icon: Icon(Icons.open_in_new, size: 16),
                    label: Text('View'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Contenuto del post
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty && platform.toLowerCase() == 'youtube') ...[
                      Text(
                        'Title',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                    Text(
                      'Description',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Text(
                        description.isNotEmpty 
                            ? description 
                            : 'No description available',
                        style: theme.textTheme.bodyMedium,
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

  Widget _buildVideoPlayer(VideoPlayerController controller) {
    // Verify if video is horizontal (aspect ratio > 1)
    final bool isHorizontalVideo = controller.value.aspectRatio > 1.0;
    
    if (isHorizontalVideo) {
      // For horizontal videos, show them full screen with FittedBox
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Black background to avoid empty spaces
        child: FittedBox(
          fit: BoxFit.contain, // Scale to preserve aspect ratio
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      // For vertical videos, maintain standard AspectRatio
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
  }

  // Metodo per costruire la sezione video
  Widget _buildVideoSection(ThemeData theme, double mediaWidth, Color videoBackgroundColor) {
    // Check if we have cloudflare_urls - prioritize cloudflare_urls over cloudflare_url
    // Use carousel even if there's only 1 item in cloudflare_urls to avoid conflicts with cloudflare_url
    // Use _videoDetails if available, otherwise widget.video
    final videoDataToCheck = _videoDetails ?? widget.video;
    final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
    final bool hasCloudflareUrls = cloudflareUrls != null && cloudflareUrls.isNotEmpty;
    final bool hasMultipleMedia = hasCloudflareUrls && cloudflareUrls!.length > 1;
    
    print('_buildVideoSection (video_details_page) - videoDataToCheck keys: ${videoDataToCheck.keys.toList()}');
    print('_buildVideoSection (video_details_page) - cloudflareUrls: $cloudflareUrls');
    print('_buildVideoSection (video_details_page) - hasCloudflareUrls: $hasCloudflareUrls, hasMultipleMedia: $hasMultipleMedia');
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 129.4, 16, 16), // Aggiunto 113.4px (3cm) di padding superiore
      child: Column(
        children: [
          // Video container a schermo intero
          Expanded(
            child: GestureDetector(
              onTap: () {
                print("Tap on video section container");
                // Per i caroselli, i tap sono gestiti internamente al widget del carosello
                if (!hasCloudflareUrls) {
                if (!_isImage && (_videoPlayerController == null || !_isVideoInitialized)) {
                  _toggleVideoPlayback();
                } else if (!_isImage && _isVideoInitialized) {
                  setState(() {
                    _showControls = !_showControls;
                  });
                  }
                }
              },
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: hasCloudflareUrls
                    ? _buildCarouselMediaPreview(theme)
                    : Stack(
                  children: [
                    // If it's an image, display it directly
                    if (_isImage)
                      Center(
                        child: _videoDetails?['video_path'] != null && 
                             _videoDetails!['video_path'].toString().isNotEmpty
                             ? _buildImagePreview(_videoDetails!['video_path'])
                             : _loadCloudflareImage(),
                      )
                    // Show video player if initialized and it's not an image
                    else if (!_isImage && _isVideoInitialized && _videoPlayerController != null)
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video Player
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _showControls = !_showControls;
                              });
                            },
                            child: _buildVideoPlayer(_videoPlayerController!),
                          ),
                          
                          // Video Controls
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: Duration(milliseconds: 300),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isSmallScreen = constraints.maxHeight < 300;
                                
                                return Stack(
                                  children: [
                                    // Overlay semi-trasparente
                                    Container(
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withOpacity(0.3),
                                            Colors.transparent,
                                            Colors.transparent,
                                            Colors.black.withOpacity(0.4),
                                          ],
                                          stops: [0.0, 0.2, 0.8, 1.0],
                                        ),
                                      ),
                                    ),
                                    
                                    // Pulsante Play/Pause al centro
                                    Center(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.2),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.4),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: IconButton(
                                          icon: Icon(
                                            _videoPlayerController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Colors.white,
                                            size: isSmallScreen ? 32 : 40,
                                          ),
                                          padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                                          onPressed: () {
                                            _toggleVideoPlayback();
                                          },
                                        ),
                                      ),
                                    ),
                                    
                                    // Controlli in alto (fullscreen)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(15),
                                        ),
                                        child: IconButton(
                                          icon: Icon(
                                            _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          padding: EdgeInsets.all(isSmallScreen ? 2 : 4),
                                          constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                          onPressed: _toggleFullScreen,
                                        ),
                                      ),
                                    ),
                                    
                                    // Controlli in basso (slider e tempo)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: EdgeInsets.only(top: 20),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              Colors.black.withOpacity(0.6),
                                              Colors.black.withOpacity(0.2),
                                              Colors.transparent,
                                            ],
                                            stops: [0.0, 0.5, 1.0],
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Time indicators
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    _formatDuration(_currentPosition),
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    _formatDuration(_videoDuration),
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            
                                            // Progress bar
                                            SliderTheme(
                                              data: SliderThemeData(
                                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: isSmallScreen ? 3 : 5),
                                                trackHeight: isSmallScreen ? 2 : 3,
                                                trackShape: RoundedRectSliderTrackShape(),
                                                activeTrackColor: Colors.white,
                                                inactiveTrackColor: Colors.white.withOpacity(0.3),
                                                thumbColor: Colors.white,
                                                overlayColor: theme.colorScheme.primary.withOpacity(0.3),
                                              ),
                                              child: Slider(
                                                value: _currentPosition.inSeconds.toDouble(),
                                                min: 0.0,
                                                max: _videoDuration.inSeconds.toDouble() > 0 
                                                    ? _videoDuration.inSeconds.toDouble() 
                                                    : 1.0,
                                                onChanged: (value) {
                                                  _videoPlayerController?.seekTo(Duration(seconds: value.toInt()));
                                                  setState(() {
                                                    _showControls = true;
                                                  });
                                                },
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      )

                    // Show thumbnail with loading spinner while video is loading
                    else if (!_isImage && !_isVideoInitialized)
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          // Thumbnail as background
                          _getLoadingThumbnail(),
                          
                          // Loading overlay with spinner
                          Container(
                            color: Colors.black.withOpacity(0.3),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Loading video...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                          // Otherwise show thumbnail from Cloudflare if available (new format)
                    else if (_videoDetails?['thumbnail_url'] != null &&
                            _videoDetails!['thumbnail_url'].toString().isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: Center(
                          child: Image.network(
                            _videoDetails!['thumbnail_url'],
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (context, url, error) => _buildFallbackImage(),
                          ),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Handle carousel page change (carosello multi-media)
  void _onCarouselPageChanged(int index) {
    setState(() {
      _currentCarouselIndex = index;
    });
    
    // Dispose previous video player if exists
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.pause();
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
      _isVideoInitialized = false;
      _currentVideoUrl = null;
    }
    
    // Reset controls
    setState(() {
      _showControls = true;
      _isPlaying = false;
    });
    
    // Initialize video player for current media if it's a video
    final videoDataToCheck = _videoDetails ?? widget.video;
    final cloudflareUrls = videoDataToCheck['cloudflare_urls'] as List<dynamic>?;
    if (cloudflareUrls != null && index < cloudflareUrls.length) {
      final mediaUrl = cloudflareUrls[index] as String?;
      if (mediaUrl != null) {
        final lower = mediaUrl.toLowerCase();
        final isImage = lower.contains('.jpg') ||
            lower.contains('.jpeg') ||
            lower.contains('.png') ||
            lower.contains('.gif') ||
            lower.contains('.webp') ||
            lower.contains('.bmp') ||
            lower.contains('.heic') ||
            lower.contains('.heif');
        if (!isImage) {
          _currentVideoUrl = mediaUrl;
          _initializeNetworkVideoPlayer(mediaUrl);
        } else {
          _currentVideoUrl = null;
        }
      }
    }
  }

  // Build video player widget for network URL (per singolo elemento del carosello)
  Widget _buildVideoPlayerWidget(String videoUrl, ThemeData theme, bool isFirstVideo) {
    // Show loading state while video is initializing or if URL doesn't match
    if (!_isVideoInitialized ||
        _videoPlayerController == null ||
        _currentVideoUrl != videoUrl) {
      // Show thumbnail while loading only for first video (se disponibile)
      final thumbnailUrl = isFirstVideo
          ? (_videoDetails?['thumbnail_cloudflare_url'] as String?)
          : null;
      
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
            Center(
              child: Image.network(
                thumbnailUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, url, error) => Container(
                  color: Colors.black,
                ),
              ),
            )
          else
            Container(color: Colors.black),
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading video...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    
    // Show video player
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Player
        GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
          },
          child: _buildVideoPlayer(_videoPlayerController!),
        ),
        
        // Video Controls (same style as singolo video)
        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: Duration(milliseconds: 300),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxHeight < 300;
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.4),
                        ],
                        stops: [0.0, 0.2, 0.8, 1.0],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _videoPlayerController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: isSmallScreen ? 32 : 40,
                        ),
                        padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                        onPressed: _toggleVideoPlayback,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.only(top: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.black.withOpacity(0.2),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_currentPosition),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _formatDuration(_videoDuration),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SliderTheme(
                            data: SliderThemeData(
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: isSmallScreen ? 3 : 5),
                              trackHeight: isSmallScreen ? 2 : 3,
                              trackShape: RoundedRectSliderTrackShape(),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withOpacity(0.3),
                              thumbColor: Colors.white,
                              overlayColor: theme.colorScheme.primary.withOpacity(0.3),
                            ),
                            child: Slider(
                              value: _currentPosition.inSeconds.toDouble(),
                              min: 0.0,
                              max: _videoDuration.inSeconds.toDouble() > 0
                                  ? _videoDuration.inSeconds.toDouble()
                                  : 1.0,
                              onChanged: (value) {
                                _videoPlayerController?.seekTo(Duration(seconds: value.toInt()));
                                setState(() {
                                  _showControls = true;
                                });
                              },
                            ),
                          ),
                          SizedBox(height: 2),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // Initialize network video player for carosello
  Future<void> _initializeNetworkVideoPlayer(String videoUrl) async {
    // Dispose previous controller if exists
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.pause();
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }
    
    setState(() {
      _isVideoInitialized = false;
      _showControls = true;
      _isPlaying = false;
    });
    
    try {
      print('Initializing network video player for URL (video_details_page): $videoUrl');
      
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      
      _videoPlayerController!.addListener(_onVideoPositionChanged);
      
      await _videoPlayerController!.initialize();
      
      if (!mounted || _isDisposed) return;
      
      setState(() {
        _isVideoInitialized = true;
        _videoDuration = _videoPlayerController!.value.duration;
        _currentPosition = Duration.zero;
        _showControls = true;
        _currentVideoUrl = videoUrl;
      });
      
      print('Network video player initialized successfully (video_details_page) for URL: $videoUrl');
    } catch (e) {
      print('Error initializing network video player (video_details_page): $e');
      
      if (mounted && !_isDisposed) {
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to load video: ${e.toString().substring(0, min(e.toString().length, 50))}...',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Metodo per costruire la sezione accounts
  Widget _buildAccountsSection(ThemeData theme) {
    final status = (_videoDetails?['status'] ?? widget.video['status'])?.toString().toLowerCase();
    final errorMsg = _videoDetails?['error']?.toString() ?? widget.video['error']?.toString();
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor, // Usa il colore del tema per la dark mode
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Social Media Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 137.4, 24, 24), // Aggiunto 113.4px (3cm) di padding superiore
                    child: _buildAccountsList(widget.video['accounts'], theme),
                  ),
                  if (status == 'failed') ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.error.withOpacity(0.18),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'Upload Failed',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              errorMsg?.isNotEmpty == true ? _translateErrorMessage(_truncateErrorMessage(errorMsg!)) : 'An unknown error occurred during upload.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  // Usa la stessa logica del player per ottenere il path/url corretto
                                  final bestVideoUrl = _getBestVideoUrl();
                                  if (bestVideoUrl != null) {
                                    print('=== TRY AGAIN CLICKED ===');
                                    print('Video URL/Path: ' + bestVideoUrl);
                                    print('Video ID: \\${widget.video['id']}');
                                    print('Video Title: \\${widget.video['title']}');
                                    print('Video Status: \\${widget.video['status']}');
                                    print('Is URL: \\${bestVideoUrl.startsWith('http://') || bestVideoUrl.startsWith('https://')}');
                                    print('========================');
                                  }
                                  NavigationService.navigateToUploadWithDraft(
                                    context,
                                    widget.video,
                                    widget.video['id'],
                                  );
                                },
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Try Again'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TroubleshootingPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.help_outline, size: 18),
                                label: const Text('Troubleshooting Help'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.primary,
                                  side: BorderSide(color: theme.colorScheme.primary, width: 1.2),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Analytics button fixed at bottom
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                  colors: [
                    Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                    Color(0xFF764ba2), // Colore finale: viola al 100%
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667eea).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoStatsPage(video: widget.video),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.analytics_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                label: const Text(
                  'View Analytics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Utility: ritorna true se l'id del video contiene l'uid dell'utente corrente (formato nuovo)
  bool _isNewVideoFormat(String? videoId, String? userId) {
    if (videoId == null || userId == null) return false;
    return videoId.contains(userId);
  }

  /// Utility: ritorna l'uid dell'utente corrente (se autenticato)
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// Ritorna true se il contenuto proviene dai scheduled_posts
  bool _isScheduledPost() {
    final status = (_videoDetails?['status'] ?? widget.video['status'])?.toString().toLowerCase();
    return status == 'scheduled';
  }

  /// Estrae solo la parte del messaggio tra 'message' e 'type', senza parentesi graffe, doppi punti, virgole e virgolette
  /// Mostra solo il contenuto del messaggio di errore senza dettagli tecnici
  String _truncateErrorMessage(String errorMessage) {
    final lower = errorMessage.toLowerCase();
    final messageIndex = lower.indexOf('message');
    if (messageIndex == -1) {
      // Se non trova 'message', ritorna il messaggio originale senza caratteri speciali
      return errorMessage.replaceAll(RegExp(r'[{}:,\"]'), '');
    }
    final typeIndex = lower.indexOf('type', messageIndex);
    if (typeIndex == -1) {
      // Se non trova 'type', ritorna tutto quello che c'è dopo 'message'
      return errorMessage.substring(messageIndex + 7).replaceAll(RegExp(r'[{}:,\"]'), '').trim();
    }
    // Estrae la parte tra 'message' e 'type'
    final startIndex = messageIndex + 7; // 7 è la lunghezza di 'message'
    final endIndex = typeIndex;
    if (startIndex >= endIndex) {
      return errorMessage.replaceAll(RegExp(r'[{}:,\"]'), '');
    }
    return errorMessage.substring(startIndex, endIndex).replaceAll(RegExp(r'[{}:,\"]'), '').trim();
  }

  /// Traduce i principali messaggi di errore italiani in inglese
  String _translateErrorMessage(String errorMsg) {
    // Mappa di frasi/parole chiave italiane -> inglese
    final translations = <String, String>{
      // Frasi intere
      'Errore nel recupero delle informazioni del creator': 'Error retrieving creator information',
      'Token di autenticazione non valido o scaduto': 'Authentication token invalid or expired',
      'Riconnetti il tuo account': 'Reconnect your account',
      'URL del file non accessibile': 'File URL not accessible',
      'TikTok richiede URL accessibili': 'TikTok requires accessible URLs',
      'Timeout durante la pubblicazione su TikTok': 'Timeout during TikTok publishing',
      'Opzioni di privacy non valide per questo account TikTok': 'Invalid privacy options for this TikTok account',
      'Client non verificato da TikTok': 'Unverified TikTok client',
      'Il contenuto sarà pubblicato come privato': 'Content will be published as private',
      'Errore di autenticazione TikTok': 'TikTok authentication error',
      'Errore di autenticazione Threads': 'Threads authentication error',
      'Timeout durante il caricamento su Threads': 'Timeout during Threads upload',
      'Errore nell\'elaborazione del media': 'Error processing media',
      'Prova un file o formato diverso': 'Try a different file or format',
      'Troppe richieste. Riprova più tardi.': 'Too many requests. Please try again later.',
      'Permesso negato. Potresti dover riautenticare il tuo account': 'Permission denied. You may need to re-authenticate your account',
      'Account non trovato': 'Account not found',
      'Impossibile creare il contenitore media su Instagram': 'Unable to create media container on Instagram',
      'Verifica di avere accesso corretto o che il media sia supportato': 'Check you have correct access or that the media is supported',
      'Errore nella creazione del contenitore media': 'Error creating media container',
      'Potrebbe essere un problema di formato o permessi': 'It may be a format or permission issue',
      'Instagram API richiede Firebase Storage configurato correttamente': 'Instagram API requires properly configured Firebase Storage',
      'Il video è stato caricato su Cloudflare e può essere usato manualmente': 'The video was uploaded to Cloudflare and can be used manually',
      'Timeout durante il caricamento. Controlla la connessione internet.': 'Timeout during upload. Check your internet connection.',
      'Errore durante l\'eliminazione': 'Error during deletion',
      'Il post non esiste più': 'The post no longer exists',
      'Upload completato con successo': 'Upload completed successfully',
      'Upload Failed': 'Upload Failed',
      'An unknown error occurred during upload.': 'An unknown error occurred during upload.',
      // Parole chiave
      'errore': 'error',
      'token': 'token',
      'timeout': 'timeout',
      'autenticazione': 'authentication',
      'pubblicazione': 'publishing',
      'account': 'account',
      'contenitore': 'container',
      'media': 'media',
      'formato': 'format',
      'permessi': 'permissions',
      'connessione': 'connection',
      'file': 'file',
      'non trovato': 'not found',
      'accessibile': 'accessible',
      'richiede': 'requires',
      'privato': 'private',
      'pubblicato': 'published',
      'completato': 'completed',
      'riprovare': 'try again',
      'riprova': 'try again',
      'elaborazione': 'processing',
      'caricamento': 'upload',
      'creazione': 'creation',
      'verifica': 'check',
      'accesso': 'access',
      'video': 'video',
      'url': 'url',
      'cloudflare': 'cloudflare',
      'instagram': 'instagram',
      'tiktok': 'tiktok',
      'threads': 'threads',
      'facebook': 'facebook',
      'youtube': 'youtube',
    };

    // Prima cerca una frase intera
    for (final entry in translations.entries) {
      if (errorMsg.toLowerCase().contains(entry.key.toLowerCase())) {
        // Se la chiave è una frase intera, sostituisci solo quella parte
        errorMsg = errorMsg.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
      }
    }
    return errorMsg;
  }

  /// Restituisce il miglior URL/path video disponibile, con la stessa logica del player
  String? _getBestVideoUrl() {
    // Usa _videoDetails se disponibile, altrimenti widget.video
    final data = _videoDetails ?? widget.video;
    String? videoUrl;
    String? videoSource;
    final videoId = data['id']?.toString();
    final userId = data['user_id']?.toString() ?? _currentUserId;
    final isNewFormat = _isNewVideoFormat(videoId, userId);
    if (isNewFormat) {
      final mediaUrl = data['media_url'] as String?;
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        videoUrl = mediaUrl;
        videoSource = 'firebase_media_url';
      }
    } else {
      final cloudflareUrl = data['cloudflare_url'] as String?;
      if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
        videoUrl = cloudflareUrl;
        videoSource = 'cloudflare_url';
      } else {
        final videoPath = data['video_path'] as String?;
        if (videoPath != null && videoPath.isNotEmpty) {
          if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
            videoUrl = videoPath;
            videoSource = 'video_path_url';
          } else {
            final videoFile = File(videoPath);
            if (videoFile.existsSync()) {
              videoUrl = videoPath;
              videoSource = 'local_file';
            }
          }
        }
      }
      if (videoUrl == null) {
        final widgetCloudflareUrl = widget.video['cloudflare_url'] as String?;
        if (widgetCloudflareUrl != null && widgetCloudflareUrl.isNotEmpty) {
          videoUrl = widgetCloudflareUrl;
          videoSource = 'widget_cloudflare_url';
        } else {
          final widgetVideoPath = widget.video['video_path'] as String?;
          if (widgetVideoPath != null && widgetVideoPath.isNotEmpty) {
            if (widgetVideoPath.startsWith('http://') || widgetVideoPath.startsWith('https://')) {
              videoUrl = widgetVideoPath;
              videoSource = 'widget_video_path_url';
            } else {
              final videoFile = File(widgetVideoPath);
              if (videoFile.existsSync()) {
                videoUrl = widgetVideoPath;
                videoSource = 'widget_local_file';
              }
            }
          }
        }
      }
    }
    return videoUrl;
  }

  /// Restituisce la thumbnail corretta per il caricamento del video
  Widget _getLoadingThumbnail() {
    print('Getting loading thumbnail for video details');
    
    // Usa _videoDetails se disponibile, altrimenti widget.video
    final data = _videoDetails ?? widget.video;
    
    // First try thumbnail_url (new format)
    final thumbnailUrl = data['thumbnail_url'] as String?;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      print('Using thumbnail_url for loading: $thumbnailUrl');
      return Image.network(
        thumbnailUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) {
          print('Failed to load thumbnail from URL: $error');
          return _getFallbackThumbnail();
        },
      );
    }
    
    // Fallback to old format: thumbnail_cloudflare_url
    final thumbnailCloudflareUrl = data['thumbnail_cloudflare_url'] as String?;
    if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
      print('Using thumbnail_cloudflare_url for loading: $thumbnailCloudflareUrl');
      return Image.network(
        thumbnailCloudflareUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) {
          print('Failed to load thumbnail from cloudflare URL: $error');
          return _getFallbackThumbnail();
        },
      );
    }
    
    // Fallback to default
    return _getFallbackThumbnail();
  }

  // Funzione per ottenere il page_id di Facebook dal database (case-insensitive e trim)
  Future<String?> _getFacebookPageIdRobust(String displayName) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      print('[FACEBOOK PAGE_ID SEARCH] Looking for display_name: "${displayName.trim().toLowerCase()}"');
      
      // Prova tutti i possibili percorsi dove l'account Facebook potrebbe essere memorizzato
      final paths = [
        'users/${currentUser.uid}/facebook',
        'users/users/${currentUser.uid}/facebook',
        'users/${currentUser.uid}/social_accounts/Facebook',
        'users/users/${currentUser.uid}/social_accounts/Facebook',
      ];
      
      for (final path in paths) {
        print('[FACEBOOK PAGE_ID SEARCH] Checking path: $path');
        final snapshot = await _databaseRef.child(path).get();
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          print('[FACEBOOK PAGE_ID SEARCH] Found data in path: $path, entries: \\${data.length}');
          // Cerca l'account con il display_name corrispondente
          for (final entry in data.entries) {
            final accountData = entry.value as Map<dynamic, dynamic>;
            final accountDisplayName = accountData['display_name']?.toString().trim().toLowerCase();
            final accountPageId = accountData['page_id']?.toString();
            final accountId = accountData['id']?.toString();
            print('[FACEBOOK PAGE_ID SEARCH] Account: "$accountDisplayName", Page ID: $accountPageId, ID: $accountId');
            if (accountDisplayName == displayName.trim().toLowerCase()) {
              final result = accountPageId ?? accountId;
              print('[FACEBOOK PAGE_ID SEARCH] MATCH FOUND! Page ID: $result');
              return result;
            }
          }
        } else {
          print('[FACEBOOK PAGE_ID SEARCH] No data found in path: $path');
        }
      }
      
      print('[FACEBOOK PAGE_ID SEARCH] No match found for display_name: $displayName');
      return null;
    } catch (e) {
      print('Error getting Facebook page_id: $e');
      return null;
    }
  }

  // --- INIZIO: Funzioni asincrone per URL pubblico post/video ---
  Future<void> _openFacebookPostOrProfile(Map<String, dynamic> account) async {
    final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? '';
    String? url;
    print('[FACEBOOK] Richiesta link per displayName=$displayName');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final db = FirebaseDatabase.instance.ref();
        
        // Prima ottieni il video ID dal widget
        final videoId = widget.video['id']?.toString();
        final userId = widget.video['user_id']?.toString();
        
        if (videoId != null && userId != null) {
          // Controlla se è formato nuovo
          final isNewFormat = _isNewVideoFormat(videoId, userId);
          
          String? postId;
          String? accountId;
          
          if (isNewFormat) {
            // --- FORMATO NUOVO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(videoId)
                .child('accounts')
                .child('Facebook');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db
                  .child('users')
                  .child('users')
                  .child(userId)
                  .child('videos')
                  .child(videoId)
                  .child('accounts')
                  .child('Facebook');
            }
            
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, potrebbe essere:
              // - un oggetto diretto
              // - una lista di oggetti
              // - una mappa di oggetti indicizzati (scheduled_posts)
              if (videoAccounts is Map) {
                if (videoAccounts.containsKey('account_display_name')) {
                  // Oggetto diretto
                  final accountDisplayName = videoAccounts['account_display_name']?.toString();
                  if (accountDisplayName == displayName) {
                    postId = videoAccounts['post_id']?.toString();
                    accountId = videoAccounts['account_id']?.toString();
                    print('[FACEBOOK] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - singolo account)');
                  }
                } else {
                  // Mappa indicizzata -> itera i valori
                  for (final entry in videoAccounts.entries) {
                    final accountData = entry.value;
                    if (accountData is Map) {
                      final accountDisplayName = accountData['account_display_name']?.toString();
                      if (accountDisplayName == displayName) {
                        postId = accountData['post_id']?.toString();
                        accountId = accountData['account_id']?.toString();
                        print('[FACEBOOK] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - mappa indicizzata)');
                        break;
                      }
                    }
                  }
                }
              } else if (videoAccounts is List) {
                // Lista di oggetti
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['account_display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString();
                      accountId = accountData['account_id']?.toString();
                      print('[FACEBOOK] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - multipli account)');
                      break;
                    }
                  }
                }
              }
            }
          } else {
            // --- FORMATO VECCHIO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(videoId)
                .child('accounts')
                .child('Facebook');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db
                  .child('users')
                  .child('users')
                  .child(userId)
                  .child('videos')
                  .child(videoId)
                  .child('accounts')
                  .child('Facebook');
            }
            
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              if (videoAccounts is List) {
                // Lista classica
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString();
                      accountId = accountData['id']?.toString();
                      print('[FACEBOOK] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato vecchio)');
                      break;
                    }
                  }
                }
              } else if (videoAccounts is Map) {
                // Mappa indicizzata per formati legacy/scheduled
                for (final entry in videoAccounts.entries) {
                  final accountData = entry.value;
                  if (accountData is Map) {
                    final accountDisplayName = (accountData['display_name'] ?? accountData['account_display_name'])?.toString();
                    if (accountDisplayName == displayName) {
                      postId = (accountData['post_id'] ?? accountData['media_id'])?.toString();
                      accountId = (accountData['id'] ?? accountData['account_id'])?.toString();
                      print('[FACEBOOK] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (mappa indicizzata)');
                      break;
                    }
                  }
                }
              }
            }
          }
          
          if (postId != null && postId.isNotEmpty) {
            // Ora ottieni l'access token usando laccountId trovato
            final snap = await db.child('users').child(currentUser.uid).child('facebook').get();
            if (snap.exists) {
              final data = snap.value as Map<dynamic, dynamic>;
              String? accessToken;
              if (accountId != null && data[accountId] != null && data[accountId]['access_token'] != null) {
                accessToken = data[accountId]['access_token'].toString();
                print('[FACEBOOK] Access token trovato per accountId $accountId');
              } else {
                for (final entry in data.entries) {
                  final acc = entry.value as Map<dynamic, dynamic>;
                  if (acc['access_token'] != null && acc['access_token'].toString().isNotEmpty) {
                    accessToken = acc['access_token'].toString();
                    print('[FACEBOOK] Access token trovato generico');
                    break;
                  }
                }
              }
              
              if (accessToken != null) {
                final apiUrl = 'https://graph.facebook.com/$postId?fields=permalink_url&access_token=$accessToken';
                print('[FACEBOOK] Chiamata API: $apiUrl');
                final response = await HttpClient().getUrl(Uri.parse(apiUrl)).then((req) => req.close());
                final respBody = await response.transform(Utf8Decoder()).join();
                print('[FACEBOOK] Risposta API: $respBody');
                final data = respBody.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(respBody)) : null;
                if (data != null && data['permalink_url'] != null) {
                  final permalink = data['permalink_url'].toString();
                  // Costruisci lURL completo aggiungendo il dominio Facebook se è un permalink relativo
                  if (permalink.startsWith('/')) {
                    url = 'https://www.facebook.com$permalink';
                  } else {
                    url = permalink;
                  }
                  print('[FACEBOOK] Permalink ottenuto: $url');
                } else {
                  print('[FACEBOOK] Nessun permalink_url nella risposta');
                }
              } else {
                print('[FACEBOOK] Nessun access token trovato');
              }
            } else {
              print('[FACEBOOK] Nessun dato facebook trovato in Firebase');
            }
          } else {
            print('[FACEBOOK] Nessun post_id trovato per display_name=$displayName');
          }
        } else {
          print('[FACEBOOK] Video ID o User ID mancanti');
        }
      } else {
        print('[FACEBOOK] Nessun utente autenticato');
      }
    } catch (e) {
      debugPrint('[FACEBOOK API] Errore durante il fetch del permalink: $e');
    }
    if (url != null) {
      _openSocialMedia(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible to get the public link for Facebook.')),
      );
    }
  }

  Future<void> _openInstagramPostOrProfile(Map<String, dynamic> account) async {
    final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? '';
    final username = account['username']?.toString();
    String? url;
    print('[INSTAGRAM] Richiesta link per displayName=$displayName');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final db = FirebaseDatabase.instance.ref();
        // Prima ottieni il video ID dal widget
        final videoId = widget.video['id']?.toString();
        final userId = widget.video['user_id']?.toString();
        if (videoId != null && userId != null) {
          // Controlla se è formato nuovo
          final isNewFormat = _isNewVideoFormat(videoId, userId);
          
          String? mediaId;
          String? accountId;
          
          if (isNewFormat) {
            // --- FORMATO NUOVO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(videoId)
                .child('accounts')
                .child('Instagram');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db
                  .child('users')
                  .child('users')
                  .child(userId)
                  .child('videos')
                  .child(videoId)
                  .child('accounts')
                  .child('Instagram');
            }
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, può essere oggetto diretto, lista o mappa indicizzata
              if (videoAccounts is Map) {
                if (videoAccounts.containsKey('account_display_name')) {
                  // Oggetto diretto
                  final accountDisplayName = videoAccounts['account_display_name']?.toString();
                  if (accountDisplayName == displayName) {
                    mediaId = videoAccounts['media_id']?.toString();
                    accountId = videoAccounts['account_id']?.toString();
                    print('[INSTAGRAM] Trovato media_id=$mediaId, accountId=$accountId per display_name=$displayName (formato nuovo - singolo account)');
                  }
                } else {
                  // Mappa indicizzata -> itera valori
                  for (final entry in videoAccounts.entries) {
                    final accountData = entry.value;
                    if (accountData is Map) {
                      final accountDisplayName = accountData['account_display_name']?.toString();
                      if (accountDisplayName == displayName) {
                        mediaId = accountData['media_id']?.toString();
                        accountId = accountData['account_id']?.toString();
                        print('[INSTAGRAM] Trovato media_id=$mediaId, accountId=$accountId per display_name=$displayName (formato nuovo - mappa indicizzata)');
                        break;
                      }
                    }
                  }
                }
              } else if (videoAccounts is List) {
                // Lista di oggetti
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['account_display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      mediaId = accountData['media_id']?.toString();
                      accountId = accountData['account_id']?.toString();
                      print('[INSTAGRAM] Trovato media_id=$mediaId, accountId=$accountId per display_name=$displayName (formato nuovo - multipli account)');
                      break;
                    }
                  }
                }
              }
            }
          } else {
            // --- FORMATO VECCHIO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(videoId)
                .child('accounts')
                .child('Instagram');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db
                  .child('users')
                  .child('users')
                  .child(userId)
                  .child('videos')
                  .child(videoId)
                  .child('accounts')
                  .child('Instagram');
            }
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              if (videoAccounts is List) {
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      mediaId = accountData['media_id']?.toString();
                      accountId = accountData['id']?.toString();
                      print('[INSTAGRAM] Trovato media_id=$mediaId, accountId=$accountId per display_name=$displayName (formato vecchio)');
                      break;
                    }
                  }
                }
              } else if (videoAccounts is Map) {
                for (final entry in videoAccounts.entries) {
                  final accountData = entry.value;
                  if (accountData is Map) {
                    final accountDisplayName = (accountData['display_name'] ?? accountData['account_display_name'])?.toString();
                    if (accountDisplayName == displayName) {
                      mediaId = accountData['media_id']?.toString();
                      accountId = (accountData['id'] ?? accountData['account_id'])?.toString();
                      print('[INSTAGRAM] Trovato media_id=$mediaId, accountId=$accountId per display_name=$displayName (mappa indicizzata)');
                      break;
                    }
                  }
                }
              }
            }
          }
          
          if (accountId != null) {
            // --- CONTROLLO facebook_access_token PRIMA DI PROCEDERE ---
            final instagramAccountSnap = await db.child('users').child(currentUser.uid).child('instagram').child(accountId).get();
            bool hasFacebookAccessToken = false;
            if (instagramAccountSnap.exists) {
              final instagramAccountData = instagramAccountSnap.value as Map<dynamic, dynamic>;
              hasFacebookAccessToken = instagramAccountData['facebook_access_token'] != null && instagramAccountData['facebook_access_token'].toString().isNotEmpty;
            }
            if (!hasFacebookAccessToken) {
              // Mostra popup professionale/minimal (step 2)
              if (username != null && username.isNotEmpty) {
                _showInstagramNotLinkedDialog(username);
              } else {
                _showInstagramNotLinkedDialog(null);
              }
              return;
            }
          }
          
          if (mediaId != null && mediaId.isNotEmpty) {
            // Ora ottieni l'access token usando laccountId trovato
            final snap = await db.child('users').child(currentUser.uid).child('instagram').get();
            if (snap.exists) {
              final data = snap.value as Map<dynamic, dynamic>;
              String? accessToken;
              if (accountId != null && data[accountId] != null && data[accountId]['facebook_access_token'] != null) {
                accessToken = data[accountId]['facebook_access_token'].toString();
                print('[INSTAGRAM] Facebook access token trovato per accountId $accountId');
              } else {
                for (final entry in data.entries) {
                  final acc = entry.value as Map<dynamic, dynamic>;
                  if (acc['facebook_access_token'] != null && acc['facebook_access_token'].toString().isNotEmpty) {
                    accessToken = acc['facebook_access_token'].toString();
                    print('[INSTAGRAM] Facebook access token trovato generico');
                    break;
                  }
                }
              }
              if (accessToken != null) {
                final apiUrl = 'https://graph.facebook.com/v18.0/$mediaId?fields=id,media_type,media_url,permalink&access_token=$accessToken';
                print('[INSTAGRAM] Chiamata API: $apiUrl');
                final response = await HttpClient().getUrl(Uri.parse(apiUrl)).then((req) => req.close());
                final respBody = await response.transform(Utf8Decoder()).join();
                print('[INSTAGRAM] Risposta API: $respBody');
                final data = respBody.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(respBody)) : null;
                if (data != null && data['permalink'] != null) {
                  url = data['permalink'];
                  print('[INSTAGRAM] Permalink ottenuto: $url');
                } else {
                  print('[INSTAGRAM] Nessun permalink nella risposta');
                }
              } else {
                print('[INSTAGRAM] Nessun access token valido');
              }
            } else {
              print('[INSTAGRAM] Nessun media_id trovato per display_name=$displayName');
            }
          } else {
            print('[INSTAGRAM] Nessun account Instagram trovato per il video $videoId');
          }
        } else {
          print('[INSTAGRAM] Video ID o User ID mancanti');
        }
      } else {
        print('[INSTAGRAM] Nessun utente autenticato');
      }
    } catch (e) {
      debugPrint('[INSTAGRAM API] Errore durante il fetch del permalink: $e');
    }
    if (url != null) {
      _openSocialMedia(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible to get the public link for Instagram.')),
      );
    }
  }

  Future<void> _openThreadsPostOrProfile(Map<String, dynamic> account) async {
    final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? '';
    String? url;
    print('[THREADS] Richiesta link per displayName=$displayName');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final db = FirebaseDatabase.instance.ref();
        // Ottieni videoId e userId
        final videoId = widget.video['id']?.toString();
        final userId = widget.video['user_id']?.toString();
        if (videoId != null && userId != null) {
          // Controlla se è formato nuovo
          final isNewFormat = _isNewVideoFormat(videoId, userId);
          
          String? postId;
          String? accountId;
          
          if (isNewFormat) {
            // --- FORMATO NUOVO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(videoId)
                .child('accounts')
                .child('Threads');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db
                  .child('users')
                  .child('users')
                  .child(userId)
                  .child('videos')
                  .child(videoId)
                  .child('accounts')
                  .child('Threads');
            }
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, può essere oggetto diretto, lista o mappa indicizzata
              if (videoAccounts is Map) {
                if (videoAccounts.containsKey('account_display_name')) {
                  // Oggetto diretto
                  final accountDisplayName = videoAccounts['account_display_name']?.toString();
                  if (accountDisplayName == displayName) {
                    postId = videoAccounts['post_id']?.toString(); // <-- uso post_id
                    accountId = videoAccounts['account_id']?.toString();
                    print('[THREADS] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - singolo account)');
                  }
                } else {
                  // Mappa indicizzata -> itera i valori
                  for (final entry in videoAccounts.entries) {
                    final accountData = entry.value;
                    if (accountData is Map) {
                      final accountDisplayName = accountData['account_display_name']?.toString();
                      if (accountDisplayName == displayName) {
                        postId = accountData['post_id']?.toString(); // <-- uso post_id
                        accountId = accountData['account_id']?.toString();
                        print('[THREADS] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - mappa indicizzata)');
                        break;
                      }
                    }
                  }
                }
              } else if (videoAccounts is List) {
                // Lista di oggetti
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['account_display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString(); // <-- uso post_id
                      accountId = accountData['account_id']?.toString();
                      print('[THREADS] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - multipli account)');
                      break;
                    }
                  }
                }
              }
            }
          } else {
            // --- FORMATO VECCHIO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(videoId)
                .child('accounts')
                .child('Threads');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db
                  .child('users')
                  .child('users')
                  .child(userId)
                  .child('videos')
                  .child(videoId)
                  .child('accounts')
                  .child('Threads');
            }
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              if (videoAccounts is List) {
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString(); // <-- uso post_id
                      accountId = accountData['id']?.toString();
                      print('[THREADS] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato vecchio)');
                      break;
                    }
                  }
                }
              } else if (videoAccounts is Map) {
                for (final entry in videoAccounts.entries) {
                  final accountData = entry.value;
                  if (accountData is Map) {
                    final accountDisplayName = (accountData['display_name'] ?? accountData['account_display_name'])?.toString();
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString();
                      accountId = (accountData['id'] ?? accountData['account_id'])?.toString();
                      print('[THREADS] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (mappa indicizzata)');
                      break;
                    }
                  }
                }
              }
            }
          }
          
          if (postId != null && postId.isNotEmpty && accountId != null && accountId.isNotEmpty) {
            // Prendi l'access token dal path users/users/[uid]/social_accounts/threads/[accountId]/access_token
            final accessTokenSnap = await db.child('users').child('users').child(currentUser.uid).child('social_accounts').child('threads').child(accountId).child('access_token').get();
            String? accessToken;
            if (accessTokenSnap.exists) {
              accessToken = accessTokenSnap.value?.toString();
              print('[THREADS] Access token trovato per accountId $accountId');
            } else {
              print('[THREADS] Nessun access token trovato per accountId $accountId');
            }
            if (accessToken != null && accessToken.isNotEmpty) {
              // Chiamata corretta secondo la doc: GET https://graph.threads.net/v1.0/{media_id}?fields=permalink&access_token=...
              final apiUrl = 'https://graph.threads.net/v1.0/$postId?fields=permalink&access_token=$accessToken';
              print('[THREADS] Chiamata API: $apiUrl');
              final response = await HttpClient().getUrl(Uri.parse(apiUrl)).then((req) => req.close());
              final respBody = await response.transform(Utf8Decoder()).join();
              print('[THREADS] Risposta API: $respBody');
              final data = respBody.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(respBody)) : null;
              if (data != null && data['permalink'] != null) {
                url = data['permalink'].toString();
                print('[THREADS] Permalink ottenuto: $url');
              } else {
                print('[THREADS] Nessun permalink nella risposta');
              }
            } else {
              print('[THREADS] Nessun access token valido');
            }
          } else {
            print('[THREADS] Nessun post_id o accountId trovato per display_name=$displayName');
          }
        } else {
          print('[THREADS] Video ID o User ID mancanti');
        }
      } else {
        print('[THREADS] Nessun utente autenticato');
      }
    } catch (e) {
      debugPrint('[THREADS API] Errore durante il fetch del permalink: $e');
    }
    if (url != null) {
      _openSocialMedia(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible to get the public link for Threads.')),
      );
    }
  }
  // --- FINE: Funzioni asincrone per URL pubblico post/video ---

  // Popup professionale/minimal per Instagram non collegato a Facebook
  void _showInstagramNotLinkedDialog(String? username) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.info_outline, size: 38, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 18),
                Text(
                  'Instagram Limitation',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  "Instagram does not allow access to public post links unless your Instagram account is linked to a Facebook Page.\n\nTo enable this feature, please connect your Instagram account to a Facebook Page in your account settings.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (username != null && username.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _openInstagramProfile(username);
                      },
                      icon: Icon(Icons.open_in_new, size: 18),
                      label: Text('Open Instagram Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(color: theme.colorScheme.primary, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _pauseVideoIfPlaying() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized && _videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
      setState(() {
        _isPlaying = false;
      });
    }
  }

  // Navigate to social account details page
  void _navigateToSocialAccountDetails(Map<String, dynamic> account, String platform) {
    // Create account data structure expected by SocialAccountDetailsPage
    final accountData = {
      'username': account['account_username']?.toString() ?? account['username']?.toString() ?? '',
      'displayName': account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? '',
      'profileImageUrl': account['account_profile_image_url']?.toString() ?? account['profile_image_url']?.toString() ?? '',
      'id': account['account_id']?.toString() ?? account['id']?.toString() ?? account['username']?.toString() ?? '',
      'platform': platform.toLowerCase(),
      'followersCount': int.tryParse(account['followers_count']?.toString() ?? '0')?.toString() ?? '0',
      'bio': account['bio']?.toString() ?? '',
      'location': account['location']?.toString() ?? '',
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SocialAccountDetailsPage(
          account: accountData,
          platform: platform.toLowerCase(),
        ),
      ),
    );
  }

  // Helper per fetch async di tutti gli account per tutte le piattaforme (nuovo formato)
  Future<Map<String, List<Map<String, dynamic>>>> _fetchAllAccountsForNewFormat(String userId, String videoId) async {
    final db = FirebaseDatabase.instance.ref();
    final platforms = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
    Map<String, List<Map<String, dynamic>>> result = {};
    for (final platform in platforms) {
      final baseUserRef = db.child('users').child('users').child(userId);
      // Tenta scheduled_posts; se vuoto, fallback a videos
      final scheduledPlatformRef = baseUserRef.child('scheduled_posts').child(videoId).child('accounts').child(platform);
      final videosPlatformRef = baseUserRef.child('videos').child(videoId).child('accounts').child(platform);
      List<Map<String, dynamic>> accounts = await _fetchAccountsFromSubfolders(scheduledPlatformRef);
      if (accounts.isEmpty) {
        accounts = await _fetchAccountsFromSubfolders(videosPlatformRef);
      }
      if (accounts.isNotEmpty) {
        result[platform] = accounts;
      }
    }
    return result;
  }
}

class _SocialAccount {
  final String username;
  final String followers;
  final String? imageUrl;
  final String? displayName;
  final String? postId;  // Aggiunto campo per l'ID del post

  const _SocialAccount({
    required this.username,
    required this.followers,
    this.imageUrl,
    this.displayName,
    this.postId,  // Aggiunto al costruttore
  });
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
} 