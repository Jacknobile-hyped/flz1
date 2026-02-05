import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math show Random, pi, cos, sin, max;
import 'profile_edit_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import 'about_page.dart';
import 'refeeral_code_page.dart';

// Classe per le particelle dei confetti
class ConfettiParticle {
  final String emoji;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final double size;
  final double speed;
  final double rotation;
  final double rotationSpeed;
  
  ConfettiParticle({
    required this.emoji,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  // TabController per le tre sezioni
  late TabController _tabController;
  
  // PageController per lo scroll verticale a scatti (stile TikTok)
  late PageController _verticalPageController;
  int _currentVerticalPage = 0;
  
  // Controllo per nascondere/mostrare la sezione superiore
  bool _isTopSectionVisible = true;
  late AnimationController _topSectionAnimationController;
  late Animation<double> _topSectionAnimation;
  
  // Animazione per la stella
  Map<String, AnimationController> _starAnimationControllers = {};
  Map<String, Animation<double>> _starScaleAnimations = {};
  Map<String, Animation<double>> _starRotationAnimations = {};
  
  // Animazione per la stella dei commenti
  Map<String, AnimationController> _commentStarAnimationControllers = {};
  Map<String, Animation<double>> _commentStarScaleAnimations = {};
  Map<String, Animation<double>> _commentStarRotationAnimations = {};
  
        // Stati
  bool _isSearching = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _feedPosts = [];
  Map<String, bool> _friendshipStatus = {}; // Traccia lo stato di amicizia per ogni utente
  Map<String, bool> _pendingRequests = {}; // Traccia le richieste pendenti per ogni utente
  Map<String, bool> _receivedRequests = {}; // Traccia le richieste ricevute da ogni utente
  
  // Nuove variabili per il feed degli amici
  List<String> _friendIds = [];
  List<Map<String, dynamic>> _friendsVideos = [];
  List<Map<String, dynamic>> _topLikedVideos = [];
  List<Map<String, dynamic>> _recentVideos = [];
  bool _isLoadingFriendsVideos = false;
  
  // Variabili per header come in main.dart
  int _unreadNotifications = 0;
  Stream<DatabaseEvent>? _notificationsStream;
  String? _profileImageUrl;
  
  // Variabili per la classifica degli amici
  List<Map<String, dynamic>> _friendsRanking = [];
  bool _isLoadingRanking = false;
  
  // Variabili per lo stato online/offline
  Map<String, bool> _onlineStatus = {};
  Stream<DatabaseEvent>? _connectionStatusStream;
  // Keep track of friend status subscriptions to cancel them on dispose
  final List<StreamSubscription<DatabaseEvent>> _friendStatusSubscriptions = [];
  
  // Variabili per il referral code
  String? _referralCode;
  
  // Variabile per tracciare l'ultimo caricamento del feed
  DateTime? _lastLoadTime;
  
  // Variabile per tracciare se siamo tornati da una navigazione
  bool _hasNavigatedAway = false;
  
  // Variabile per tracciare se abbiamo appena aperto un URL esterno
  bool _justOpenedExternalUrl = false;
  
  // Cache per i conteggi dei commenti
  Map<String, int> _commentsCountCache = {};
  
  // Debounce per prevenire doppi tap (fix iOS)
  Map<String, DateTime> _lastStarTapTime = {};
  static const Duration _starDebounceTime = Duration(milliseconds: 500);
  
  // Emoji per commenti rapidi
  final List<String> _quickEmojis = ['❤️', '🔥', '👏', '🎉', '💯', '🚀'];
  
  // Stream per aggiornamenti in tempo reale dei commenti
  Map<String, Stream<DatabaseEvent>> _commentsStreams = {};
  
  // Animazioni per i confetti delle emoji
  Map<String, List<ConfettiParticle>> _confettiParticles = {};
  Map<String, AnimationController> _confettiControllers = {};
  Map<String, String> _currentConfettiId = {}; // ID unico per ogni animazione
  Map<String, AnimationController> _activeConfettiControllers = {}; // Controller attivi per ogni animazione
  
  // VideoPlayer controllers per l'autoplay
  Map<String, VideoPlayerController> _videoControllers = {};
  Map<String, bool> _videoInitialized = {};
  Map<String, bool> _videoPlaying = {};
  Map<String, bool> _showVideoControls = {};
  Map<String, Timer?> _controlsHideTimers = {};
  
  // Tracciamento visualizzazioni video
  Map<String, Set<String>> _videoViews = {}; // videoId -> Set di userId che l'hanno visto
  Map<String, bool> _hasUserViewedVideo = {}; // videoId -> se l'utente corrente l'ha visto
  
  // Interazione con la barra di progresso
  Map<String, bool> _isProgressBarInteracting = {}; // videoId -> se l'utente sta interagendo con la barra
  
  // Mappa dei loghi delle piattaforme social
  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };
  
  // Animazioni
  late AnimationController _fadeAnimationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Inizializza TabController con 3 tab
    _tabController = TabController(length: 3, vsync: this);
    
    // Inizializza PageController per lo scroll verticale
    _verticalPageController = PageController();
    
    // Aggiungi listener per il cambio di tab
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _onTabChanged(_tabController.index);
      }
    });
    

    
    _initializeAnimations();
    _initializeTopSectionAnimation();
    _loadFeedPosts();
    _setupNotificationsListener();
    _loadProfileImage();
    _loadFriendsRanking();
    _setupOnlineStatus();
    _loadFriendsOnlineStatus();
    _loadReferralCode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ricarica i dati SOLO quando l'utente torna da una navigazione, non quando si aprono tendine
    if (_hasNavigatedAway && !_isLoading && !_isLoadingFriendsVideos && ModalRoute.of(context)?.isCurrent == true) {
      // Verifica se è passato del tempo dall'ultimo caricamento per evitare ricaricamenti continui
      final now = DateTime.now();
      if (_lastLoadTime == null || now.difference(_lastLoadTime!).inSeconds > 5) {
        _loadFeedPosts();
        _lastLoadTime = now;
      }
      // Reset del flag dopo aver ricaricato
      _hasNavigatedAway = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Ricarica i dati quando l'app torna in primo piano
    if (state == AppLifecycleState.resumed) {
      // Se abbiamo appena aperto un URL esterno, non ricaricare il feed
      if (_justOpenedExternalUrl) {
        _justOpenedExternalUrl = false;
        print('[LIFECYCLE] Tornato da URL esterno, skip refresh del feed');
        return;
      }
      
      final now = DateTime.now();
      if (_lastLoadTime == null || now.difference(_lastLoadTime!).inSeconds > 10) {
        _loadFeedPosts();
        _lastLoadTime = now;
      }
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Se la tastiera viene chiusa, togli il focus dalla search bar
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    if (bottomInset == 0.0 && _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      // Se vuoi anche svuotare la barra di ricerca, decommenta la riga sotto:
      // _searchController.clear();
    }
  }

  Future<void> _refreshFeed() async {
    setState(() {
      _isLoading = true;
    });
    
    await Future.wait([
      _loadFriendsIds(),
      _loadFriendsVideos(),
      _loadFriendsRanking(),
    ]);
    
    // Carica le visualizzazioni dei video
    await _loadVideoViews();
    
    // Ricarica lo stato online degli amici
    _loadFriendsOnlineStatus();
    
    // Reinizializza i video controllers
    await _initializeVideoControllers();
    
    setState(() {
      _isLoading = false;
    });
  }

  void _initializeAnimations() {
    _fadeAnimationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimationController.forward();
  }
  
  void _initializeTopSectionAnimation() {
    _topSectionAnimationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    
    _topSectionAnimation = Tween<double>(
      begin: 0.0, // Inizia visibile (0 = visibile)
      end: 1.0,   // Finisce nascosta (1 = nascosta)
    ).animate(CurvedAnimation(
      parent: _topSectionAnimationController,
      curve: Curves.easeInOut,
    ));
    
    // Assicurati che la sezione superiore sia visibile all'inizio
    _topSectionAnimationController.value = 0.0;
  }
  
  void _initializeStarAnimation(String videoId) {
    if (!_starAnimationControllers.containsKey(videoId)) {
      _starAnimationControllers[videoId] = AnimationController(
        duration: Duration(milliseconds: 600), // Animazione più equilibrata
        vsync: this,
      );
      
      _starScaleAnimations[videoId] = Tween<double>(
        begin: 1.0,
        end: 1.6, // Scala più equilibrata
      ).animate(CurvedAnimation(
        parent: _starAnimationControllers[videoId]!,
        curve: Curves.elasticOut, // Curva elastica per effetto bounce
      ));
      
      _starRotationAnimations[videoId] = Tween<double>(
        begin: 0.0,
        end: 1.0, // Rotazione completa
      ).animate(CurvedAnimation(
        parent: _starAnimationControllers[videoId]!,
        curve: Curves.easeInOutBack, // Curva con back per effetto più dinamico
      ));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeAnimationController.dispose();
    _topSectionAnimationController.dispose();
    
    // Pulisci le animazioni delle stelle
    _starAnimationControllers.values.forEach((controller) => controller.dispose());
    
    // Pulisci le animazioni delle stelle dei commenti
    _commentStarAnimationControllers.values.forEach((controller) => controller.dispose());
    
    // Pulisci i controller dei confetti
    _confettiControllers.values.forEach((controller) => controller.dispose());
    _activeConfettiControllers.values.forEach((controller) => controller.dispose());
    
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    _verticalPageController.dispose();
    
    // Dispose di tutti i VideoPlayer controllers
    _videoControllers.values.forEach((controller) {
      controller.dispose();
    });
    _videoControllers.clear();
    
    // Cancel all control hide timers
    for (var timer in _controlsHideTimers.values) {
      timer?.cancel();
    }
    _controlsHideTimers.clear();

    // Cancel friend status subscriptions
    for (final sub in _friendStatusSubscriptions) {
      sub.cancel();
    }
    _friendStatusSubscriptions.clear();
    
    // Imposta lo stato offline quando la pagina viene chiusa
    if (_currentUser != null) {
      final userStatusRef = _database.child('status').child(_currentUser!.uid);
      userStatusRef.set({
        'online': false,
        'last_active': ServerValue.timestamp,
      });
    }
    
    // Pulisci la cache del debounce (fix iOS)
    _lastStarTapTime.clear();
    
    super.dispose();
  }

    Future<void> _loadFeedPosts() async {
        setState(() {
      _isLoading = true;
    });

    try {
      print('Current user: ${_currentUser?.uid ?? 'Not authenticated'}');
      
      // Carica gli ID degli amici dell'utente corrente
      await _loadFriendsIds();
      
      // Carica i video degli amici
      await _loadFriendsVideos();
      
      // Carica conteggi e visualizzazioni SOLO per i video mostrati
      await _loadCountsAndViewsForDisplayedVideos();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading feed posts: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFriendsIds() async {
    if (_currentUser == null) return;

    try {
      print('Loading friends for user: ${_currentUser!.uid}');
      
      // Carica gli ID degli amici dal database
      final friendsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('alreadyfriends')
          .get();

      if (friendsSnapshot.exists) {
        final friends = friendsSnapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _friendIds = friends.keys.cast<String>().toList();
        });
        print('Loaded ${_friendIds.length} friends: $_friendIds');
      } else {
        print('No friends found at path: users/users/${_currentUser!.uid}/profile/alreadyfriends');
        
        // Prova a verificare se esiste il path del profilo
        final profileSnapshot = await _database
            .child('users')
            .child('users')
            .child(_currentUser!.uid)
            .child('profile')
            .get();
            
        if (profileSnapshot.exists) {
          final profile = profileSnapshot.value as Map<dynamic, dynamic>;
          print('Profile exists, keys: ${profile.keys.toList()}');
        } else {
          print('Profile path does not exist');
        }
        
        setState(() {
          _friendIds = [];
        });
      }
    } catch (e) {
      print('Error loading friends IDs: $e');
      setState(() {
        _friendIds = [];
      });
    }
  }

  Future<void> _loadFriendsVideos() async {
    if (_friendIds.isEmpty) {
      print('No friends to load videos from');
      setState(() {
        _friendsVideos = [];
        _topLikedVideos = [];
        _recentVideos = [];
        _isLoadingFriendsVideos = false;
      });
      return;
    }

    setState(() {
      _isLoadingFriendsVideos = true;
    });

    try {
      List<Map<String, dynamic>> allVideos = [];
      print('Loading videos for ${_friendIds.length} friends');

      // Carica i video in parallelo per ogni amico
      List<Future<void>> loadFutures = [];
      
      for (String friendId in _friendIds) {
        loadFutures.add(_loadVideosForFriend(friendId, allVideos));
      }

      // Non aspettare tutti i video - lascia che si carichino progressivamente
      // I video verranno mostrati appena disponibili tramite _updateVideosProgressively
      Future.wait(loadFutures).then((_) {
        // Quando tutti i video sono caricati, finalizza il caricamento
        setState(() {
          _isLoadingFriendsVideos = false;
        });
        
        // Inizializza i controller per i video del TAB corrente (pochi elementi)
        _initializeVideoControllers();
        // E carica conteggi e visualizzazioni solo per i video mostrati
        _loadCountsAndViewsForDisplayedVideos();
      });
      
      // Esci subito per permettere l'aggiornamento progressivo
      return;
    } catch (e) {
      print('Error loading friends videos: $e');
      setState(() {
        _friendsVideos = [];
        _isLoadingFriendsVideos = false;
      });
    }
  }

  // Nuovo metodo per caricare i video di un singolo amico e aggiornare l'UI progressivamente
  Future<void> _loadVideosForFriend(String friendId, List<Map<String, dynamic>> allVideos) async {
    try {
      print('Loading videos for friend: $friendId');
      
      // Carica i dati del profilo dell'amico
      final profileSnapshot = await _database
          .child('users')
          .child('users')
          .child(friendId)
          .child('profile')
          .get();

      String displayName = 'Unknown User';
      String username = 'unknown';
      String profileImageUrl = 'https://via.placeholder.com/100';

      if (profileSnapshot.exists) {
        final profile = profileSnapshot.value as Map<dynamic, dynamic>;
        displayName = profile['displayName']?.toString() ?? 'Unknown User';
        username = profile['username']?.toString() ?? 'unknown';
        profileImageUrl = profile['profileImageUrl']?.toString() ?? 'https://via.placeholder.com/100';
        print('Friend profile: $displayName (@$username)');
      } else {
        print('No profile found for friend: $friendId');
      }

      // Carica SOLO gli ultimi video dell'amico per ridurre memoria/traffico
      final Query videosQuery = _database
          .child('users')
          .child('users')
          .child(friendId)
          .child('videos')
          .orderByChild('timestamp')
          .limitToLast(10);
      final videosSnapshot = await videosQuery.get();

      if (videosSnapshot.exists) {
        print('Found ${videosSnapshot.children.length} recent videos for friend: $friendId');
        List<Map<String, dynamic>> friendVideos = [];
        for (final child in videosSnapshot.children) {
          final videoId = child.key;
          final videoData = child.value;
          if (videoId != null && videoData is Map) {
            final video = Map<String, dynamic>.from(videoData as Map);
            video['id'] = videoId;
            video['userId'] = friendId;
            video['displayName'] = displayName;
            video['username'] = username;
            video['profileImageUrl'] = profileImageUrl;
            // Assicurati che total_likes sia un numero
            int totalLikes = 0;
            if (video['total_likes'] != null) {
              totalLikes = video['total_likes'] is int 
                  ? video['total_likes'] 
                  : int.tryParse(video['total_likes'].toString()) ?? 0;
            }
            video['total_likes'] = totalLikes;
            video['likes'] = totalLikes; // Per compatibilità con il feed esistente
            // Aggiungi timestamp se non presente
            if (video['timestamp'] == null) {
              video['timestamp'] = DateTime.now().millisecondsSinceEpoch;
            }
            // Converti timestamp in DateTime se è un numero
            if (video['timestamp'] is int) {
              video['timestamp'] = DateTime.fromMillisecondsSinceEpoch(video['timestamp']);
            }
            // Inizializza i campi mancanti
            if (!video.containsKey('star_users') || video['star_users'] == null) {
              video['star_users'] = <String, dynamic>{};
            }
            if (!video.containsKey('star_count')) {
              video['star_count'] = 0;
            }
            
            // Fix iOS: aggiungi controlli aggiuntivi per l'URL del video
            final String videoUserId = video['userId'] as String;
            final bool videoIsNewFormat = videoId.contains(videoUserId);
            if (videoIsNewFormat && video['media_url'] == null) {
              print('Warning: New format video $videoId missing media_url');
            } else if (!videoIsNewFormat && video['video_path'] == null && video['cloudflare_url'] == null) {
              print('Warning: Old format video $videoId missing video_path and cloudflare_url');
            }
            friendVideos.add(video);
          }
        }

        // Aggiungi i video dell'amico alla lista principale
        allVideos.addAll(friendVideos);

        // Aggiorna immediatamente l'UI con i video disponibili
        _updateVideosProgressively(allVideos);
      } else {
        print('No videos found for friend: $friendId');
      }
    } catch (e) {
      print('Error loading videos for friend $friendId: $e');
    }
  }

  // Metodo per aggiornare progressivamente i video nell'UI
  void _updateVideosProgressively(List<Map<String, dynamic>> allVideos) {
    if (allVideos.isEmpty) return;

    // Crea una copia ordinata per likes
    List<Map<String, dynamic>> sortedByLikes = List.from(allVideos);
    sortedByLikes.sort((a, b) => (b['total_likes'] as int).compareTo(a['total_likes'] as int));

    // Crea una copia ordinata per timestamp con priorità ai video non visti
    List<Map<String, dynamic>> sortedByTime = List.from(allVideos);
    sortedByTime.sort((a, b) {
      // Prima ordina per visualizzazione (non visti prima)
      bool aViewed = _hasUserViewedVideo[a['id']] ?? false;
      bool bViewed = _hasUserViewedVideo[b['id']] ?? false;
      
      if (aViewed != bViewed) {
        return aViewed ? 1 : -1; // Non visti prima
      }
      
      // Poi per timestamp (più recenti prima)
      DateTime aTime = a['timestamp'] is DateTime ? a['timestamp'] : DateTime.fromMillisecondsSinceEpoch(a['timestamp']);
      DateTime bTime = b['timestamp'] is DateTime ? b['timestamp'] : DateTime.fromMillisecondsSinceEpoch(b['timestamp']);
      return bTime.compareTo(aTime);
    });

    setState(() {
      // Aggiorna i top liked videos (massimo 3)
      _topLikedVideos = sortedByLikes.where((video) => (video['total_likes'] as int) > 0).take(3).toList();
      
      // Aggiorna i video recenti (massimo 3) con priorità ai non visti
      _recentVideos = sortedByTime.take(3).toList();
      
      // Aggiorna la lista completa (cap a 100 per sicurezza memoria)
      _friendsVideos = allVideos.length > 100 ? allVideos.take(100).toList() : allVideos;
    });

    // Inizializza i video controllers per i video del tab corrente
    _initializeVideoControllersForNewVideos();
    // Carica conteggi e visualizzazioni SOLO per i video mostrati
    _loadCountsAndViewsForDisplayedVideos();
  }

  // Metodo per inizializzare i video controllers solo per i nuovi video
  Future<void> _initializeVideoControllersForNewVideos() async {
    // Scegli la lista in base al tab corrente
    List<Map<String, dynamic>> target = [];
    if (_tabController.index == 0) {
      target = _topLikedVideos;
    } else {
      target = _recentVideos;
    }
    final toInit = target.take(3).toList();
    for (final video in toInit) {
      final videoId = video['id'] as String;
      if (!_videoControllers.containsKey(videoId)) {
        await _initializeVideoController(video);
      }
    }
  }

  // Metodo per inizializzare un singolo video controller
  Future<void> _initializeVideoController(Map<String, dynamic> video) async {
    final videoId = video['id'] as String;
    final userId = video['userId'] as String;
    final bool isNewFormat = videoId.contains(userId);
    
    // Usa la stessa logica di profile_edit_page.dart
    String videoUrl = '';
    if (isNewFormat) {
      // Per il nuovo formato: usa media_url
      videoUrl = video['media_url'] ?? '';
      print('Using media_url (new format) for video $videoId: $videoUrl');
    } else {
      // Per il vecchio formato: usa video_path o cloudflare_url
      videoUrl = video['video_path'] ?? video['cloudflare_url'] ?? '';
      print('Using video_path/cloudflare_url (old format) for video $videoId: $videoUrl');
    }
    
    if (videoUrl.isNotEmpty) {
      try {
        print('Initializing video controller for $videoId with URL: $videoUrl');
        
        // Fix per iOS: usa configurazione più robusta per il video controller
        final controller = VideoPlayerController.network(
          videoUrl,
          httpHeaders: {
            'User-Agent': 'Viralyst/1.0 (iOS; iPhone)',
          },
        );
        
        _videoControllers[videoId] = controller;
        _videoInitialized[videoId] = false;
        
        // Fix iOS: aggiungi timeout per l'inizializzazione
        await controller.initialize().timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Video initialization timeout', Duration(seconds: 10));
          },
        );
        
        // Fix iOS: verifica che il controller sia ancora valido dopo l'inizializzazione
        if (controller.value.hasError) {
          throw Exception('Video controller has error: ${controller.value.errorDescription}');
        }
        
        controller.setLooping(true);
        controller.setVolume(1.0);
        
        // Fix iOS: controlla se il widget è ancora montato prima di aggiornare lo stato
        if (mounted) {
        setState(() {
          _videoInitialized[videoId] = true;
          _videoPlaying[videoId] = false;
          _showVideoControls[videoId] = false;
        });
        }
        
        // Start auto-hide timer for controls
        _startControlsHideTimer(videoId, true);
        print('Video controller initialized successfully for $videoId');
      } catch (e) {
        print('Error initializing video controller for $videoId: $e');
        // Se fallisce, rimuovi il controller e marca come non inizializzato
        _videoControllers.remove(videoId);
        _videoInitialized[videoId] = false;
        _videoPlaying[videoId] = false;
        _showVideoControls[videoId] = false;
        
        if (mounted) {
        setState(() {});
        }
      }
    } else {
      print('No valid video URL found for video $videoId');
    }
  }

  Future<void> _handleVideoLike(Map<String, dynamic> video) async {
    if (_currentUser == null) return;

    try {
      final videoId = video['id'] as String;
      final userId = video['userId'] as String;
      
      // TODO: Implementare la logica per il like del video
      // Per ora mostriamo solo un messaggio
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.favorite, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text('Like aggiunto al video!', style: TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      print('Error handling video like: $e');
    }
  }
  
  bool _isVideoStarredByCurrentUser(Map<String, dynamic> video) {
    if (_currentUser == null) return false;
    
    final starUsers = video['star_users'];
    if (starUsers == null) return false;
    
    // iOS robust: può essere Map o List
    if (starUsers is Map) {
      return starUsers.containsKey(_currentUser!.uid);
    } else if (starUsers is List) {
      return starUsers.contains(_currentUser!.uid);
    }
    return false;
  }
  
  bool _isCommentStarredByCurrentUser(Map<String, dynamic> comment) {
    if (_currentUser == null) return false;
    
    final starUsers = comment['star_users'];
    if (starUsers == null) return false;
    
    // Gestisci diversi tipi di dati per star_users (fix iOS)
    if (starUsers is Map) {
    return starUsers.containsKey(_currentUser!.uid);
    } else if (starUsers is List) {
      // Caso in cui star_users è una lista invece di una mappa
      return starUsers.contains(_currentUser!.uid);
    }
    
    return false;
  }
  
  void _triggerStarAnimation(String videoId) {
    _initializeStarAnimation(videoId);
    final controller = _starAnimationControllers[videoId];
    if (controller != null) {
      controller.forward().then((_) {
        controller.reverse();
      });
    }
  }
  
  void _initializeCommentStarAnimation(String commentId) {
    if (!_commentStarAnimationControllers.containsKey(commentId)) {
      _commentStarAnimationControllers[commentId] = AnimationController(
        duration: Duration(milliseconds: 600), // Animazione più lunga
        vsync: this,
      );
      
      _commentStarScaleAnimations[commentId] = Tween<double>(
        begin: 1.0,
        end: 1.6, // Scala più drammatica
      ).animate(CurvedAnimation(
        parent: _commentStarAnimationControllers[commentId]!,
        curve: Curves.elasticOut, // Curva elastica per effetto bounce
      ));
      
      _commentStarRotationAnimations[commentId] = Tween<double>(
        begin: 0.0,
        end: 1.0, // Rotazione completa
      ).animate(CurvedAnimation(
        parent: _commentStarAnimationControllers[commentId]!,
        curve: Curves.easeInOutBack, // Curva con back per effetto più dinamico
      ));
    }
  }
  
  void _triggerCommentStarAnimation(String commentId) {
    _initializeCommentStarAnimation(commentId);
    final controller = _commentStarAnimationControllers[commentId];
    if (controller != null) {
      controller.forward().then((_) {
        controller.reverse();
      });
    }
  }

  Future<void> _handleVideoStar(Map<String, dynamic> video) async {
    if (_currentUser == null) return;
    
    final videoId = video['id'] as String;
    
    try {
      final videoUserId = video['userId'] as String;
      final currentUserId = _currentUser!.uid;
      
      // Percorso per il campo stelle del video
      final videoRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId);
      
      // Percorso per gli utenti che hanno messo stella
      final starUsersRef = videoRef.child('star_users');
      
      // Controlla se l'utente corrente ha già messo stella
      final userStarSnapshot = await starUsersRef.child(currentUserId).get();
      final hasUserStarred = userStarSnapshot.exists;
      
      // Recupera il numero totale di stelle
      final starCountSnapshot = await videoRef.child('star_count').get();
      int currentStarCount = 0;
      
      if (starCountSnapshot.exists) {
        final value = starCountSnapshot.value;
        if (value is int) {
          currentStarCount = value;
        } else if (value != null) {
          currentStarCount = int.tryParse(value.toString()) ?? 0;
        }
      }
      
      int newStarCount;
      String message;
      
      if (hasUserStarred) {
        // Rimuovi la stella
        await starUsersRef.child(currentUserId).remove();
        newStarCount = currentStarCount - 1;
        message = ''; // Nessun messaggio quando si rimuove la stella
      } else {
        // Aggiungi la stella - attiva l'animazione solo quando si aggiunge
        _triggerStarAnimation(videoId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;
        // Ottieni il nome dell'utente proprietario del video
        final videoOwnerName = video['username'] ?? 'User';
        message = '$videoOwnerName thanks you for your support';
        
        // Salva la stella nella cartella notificationstars del proprietario del video
        if (currentUserId != videoUserId) {
          final notificationStarRef = _database
              .child('users')
              .child('users')
              .child(videoUserId)
              .child('notificationstars')
              .child('${videoId}_${currentUserId}');
          
          // Dati della stella per le notifiche
          final notificationStarData = {
            'id': '${videoId}_${currentUserId}',
            'videoId': videoId,
            'videoTitle': video['title'] ?? 'Untitled Video',
            'videoOwnerId': videoUserId,
            'starUserId': currentUserId,
            'starUserDisplayName': _currentUser!.displayName ?? 'Anonymous',
            'starUserProfileImage': _currentUser!.photoURL ?? '',
            'timestamp': ServerValue.timestamp,
            'type': 'video_star',
            'read': false, // Marca come non letto
          };
          
          await notificationStarRef.set(notificationStarData);
          print('Stella salvata in notificationstars per l\'utente $videoUserId');
        }
      }
      
      // Aggiorna il conteggio totale delle stelle
      await videoRef.child('star_count').set(newStarCount);
      
      // Aggiorna lo stato locale
      setState(() {
        // Aggiorna il conteggio stelle nel video locale
        if (video.containsKey('star_count')) {
          video['star_count'] = newStarCount;
        }
        // Aggiorna lo stato della stella per l'utente corrente
        if (!video.containsKey('star_users') || video['star_users'] == null) {
          video['star_users'] = <String, dynamic>{};
        }
        
        // Assicurati che star_users sia una Map
        if (video['star_users'] is! Map) {
          video['star_users'] = <String, dynamic>{};
        }
        
          if (hasUserStarred) {
            video['star_users'].remove(currentUserId);
          } else {
            video['star_users'][currentUserId] = true;
        }
      });
      
      print('Stelle aggiornate per il video $videoId: $newStarCount (utente ${hasUserStarred ? 'rimosso' : 'aggiunto'})');
      
      // Mostra feedback visivo solo se c'è un messaggio
      if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          duration: Duration(seconds: 2),
        ),
      );
      }
      
    } catch (e) {
      print('Errore nell\'aggiornamento delle stelle: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nell\'aggiornamento delle stelle'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleReplyStar(Map<String, dynamic> reply, String videoUserId) async {
    if (_currentUser == null) return;
    
    final replyId = reply['id'] as String;
    final parentCommentId = reply['parentCommentId'] as String;
    final videoId = reply['videoId'] as String;
    
    // Debounce per prevenire doppi tap (fix iOS)
    final now = DateTime.now();
    final lastTapTime = _lastStarTapTime[replyId];
    if (lastTapTime != null && now.difference(lastTapTime) < _starDebounceTime) {
      return; // Ignora il tap se troppo vicino al precedente
    }
    _lastStarTapTime[replyId] = now;
    
    try {
      final currentUserId = _currentUser!.uid;
      
      // Percorso per il campo stelle della risposta
      final replyRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId)
          .child('replies')
          .child(replyId);
      
      // Percorso per gli utenti che hanno messo stella
      final starUsersRef = replyRef.child('star_users');
      
      // SEMPRE controlla Firebase per lo stato attuale (fix per iOS)
      final userStarSnapshot = await starUsersRef.child(currentUserId).get();
      final hasUserStarred = userStarSnapshot.exists;
      
      // Recupera il numero totale di stelle
      final starCountSnapshot = await replyRef.child('star_count').get();
      int currentStarCount = 0;
      
      if (starCountSnapshot.exists) {
        final value = starCountSnapshot.value;
        if (value is int) {
          currentStarCount = value;
        } else if (value != null) {
          currentStarCount = int.tryParse(value.toString()) ?? 0;
        }
      }
      
      int newStarCount;
      String message;
      
      if (hasUserStarred) {
        // Rimuovi la stella
        await starUsersRef.child(currentUserId).remove();
        newStarCount = math.max(0, currentStarCount - 1); // Previeni valori negativi
        message = 'Star removed from reply';
      } else {
        // Aggiungi la stella - attiva l'animazione solo quando si aggiunge
        _triggerCommentStarAnimation(replyId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;
        // Ottieni il nome dell'utente proprietario della risposta
        final replyOwnerName = reply['userDisplayName'] ?? 'User';
        message = '$replyOwnerName thanks you for your support';
        
        // Salva la stella nella cartella notificationstars del proprietario della risposta
        final replyOwnerId = reply['userId'] as String?;
        if (replyOwnerId != null && currentUserId != replyOwnerId) {
          final notificationStarRef = _database
              .child('users')
              .child('users')
              .child(replyOwnerId)
              .child('notificationstars')
              .child('${replyId}_${currentUserId}');
          
          // Dati della stella per le notifiche
          final notificationStarData = {
            'id': '${replyId}_${currentUserId}',
            'replyId': replyId,
            'commentId': parentCommentId,
            'videoId': videoId,
            'videoOwnerId': videoUserId,
            'videoTitle': reply['videoTitle'] ?? 'Untitled Video',
            'replyOwnerId': replyOwnerId,
            'starUserId': currentUserId,
            'starUserDisplayName': _currentUser!.displayName ?? 'Anonymous',
            'starUserProfileImage': _currentUser!.photoURL ?? '',
            'timestamp': ServerValue.timestamp,
            'type': 'reply_star',
            'read': false, // Marca come non letto
          };
          
          await notificationStarRef.set(notificationStarData);
          print('Stella della risposta salvata in notificationstars per l\'utente $replyOwnerId');
        }
      }
      
      // Aggiorna il conteggio totale delle stelle usando transazione atomica
      await replyRef.child('star_count').set(newStarCount);
      
      // Verifica finale dello stato su Firebase per sicurezza (fix iOS)
      final finalStarSnapshot = await starUsersRef.child(currentUserId).get();
      final finalStarState = finalStarSnapshot.exists;
      
      // Aggiorna lo stato locale DOPO aver verificato Firebase
      if (mounted) {
      setState(() {
        // Aggiorna il conteggio stelle nella risposta locale
          reply['star_count'] = newStarCount;
          
          // Aggiorna lo stato della stella basato sulla verifica finale di Firebase
          if (reply['star_users'] == null) {
            reply['star_users'] = <String, dynamic>{};
          }
          
          // Usa lo stato finale verificato da Firebase
          if (finalStarState) {
            reply['star_users'][currentUserId] = true;
          } else {
            reply['star_users'].remove(currentUserId);
        }
      });
      }
      
      print('Stelle aggiornate per la risposta $replyId: $newStarCount (utente ${hasUserStarred ? 'rimosso' : 'aggiunto'})');
      
    } catch (e) {
      print('Errore nell\'aggiornamento delle stelle della risposta: $e');
      // In caso di errore, ricarica i dati dal database per sincronizzare
      if (mounted) {
        try {
          // Ricarica lo stato attuale da Firebase per sincronizzare
          final replyRef = _database
              .child('users')
              .child('users')
              .child(videoUserId)
              .child('videos')
              .child(videoId)
              .child('comments')
              .child(parentCommentId)
              .child('replies')
              .child(replyId);
          
          final refreshSnapshot = await replyRef.get();
          if (refreshSnapshot.exists) {
            final refreshedReply = Map<String, dynamic>.from(refreshSnapshot.value as Map);
            setState(() {
              reply['star_count'] = refreshedReply['star_count'] ?? 0;
              reply['star_users'] = refreshedReply['star_users'] ?? {};
            });
          }
        } catch (refreshError) {
          print('Errore nel refresh della risposta: $refreshError');
        }
      }
    }
  }

  Future<void> _handleCommentStar(Map<String, dynamic> comment, String videoUserId) async {
    if (_currentUser == null) return;
    
    final commentId = comment['id'] as String;
    final videoId = comment['videoId'] as String;
    
    // Debounce per prevenire doppi tap (fix iOS)
    final now = DateTime.now();
    final lastTapTime = _lastStarTapTime[commentId];
    if (lastTapTime != null && now.difference(lastTapTime) < _starDebounceTime) {
      return; // Ignora il tap se troppo vicino al precedente
    }
    _lastStarTapTime[commentId] = now;
    
    try {
      final currentUserId = _currentUser!.uid;
      
      // Percorso per il campo stelle del commento
      final commentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);
      
      // Percorso per gli utenti che hanno messo stella
      final starUsersRef = commentRef.child('star_users');
      
      // SEMPRE controlla Firebase per lo stato attuale (fix per iOS)
      final userStarSnapshot = await starUsersRef.child(currentUserId).get();
      final hasUserStarred = userStarSnapshot.exists;
      
      // Recupera il numero totale di stelle
      final starCountSnapshot = await commentRef.child('star_count').get();
      int currentStarCount = 0;
      
      if (starCountSnapshot.exists) {
        final value = starCountSnapshot.value;
        if (value is int) {
          currentStarCount = value;
        } else if (value != null) {
          currentStarCount = int.tryParse(value.toString()) ?? 0;
        }
      }
      
      int newStarCount;
      String message;
      
      if (hasUserStarred) {
        // Rimuovi la stella
        await starUsersRef.child(currentUserId).remove();
        newStarCount = math.max(0, currentStarCount - 1); // Previeni valori negativi
        message = 'Star removed from comment';
      } else {
        // Aggiungi la stella - attiva l'animazione solo quando si aggiunge
        _triggerCommentStarAnimation(commentId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;
        // Ottieni il nome dell'utente proprietario del commento
        final commentOwnerName = comment['userDisplayName'] ?? 'User';
        message = '$commentOwnerName thanks you for your support';
        
        // Salva la stella nella cartella notificationstars del proprietario del commento
        final commentOwnerId = comment['userId'] as String?;
        if (commentOwnerId != null && currentUserId != commentOwnerId) {
          final notificationStarRef = _database
              .child('users')
              .child('users')
              .child(commentOwnerId)
              .child('notificationstars')
              .child('${commentId}_${currentUserId}');
          
          // Dati della stella per le notifiche
          final notificationStarData = {
            'id': '${commentId}_${currentUserId}',
            'commentId': commentId,
            'videoId': videoId,
            'videoTitle': comment['videoTitle'] ?? 'Untitled Video',
            'commentOwnerId': commentOwnerId,
            'starUserId': currentUserId,
            'starUserDisplayName': _currentUser!.displayName ?? 'Anonymous',
            'starUserProfileImage': _currentUser!.photoURL ?? '',
            'timestamp': ServerValue.timestamp,
            'type': 'comment_star',
            'read': false, // Marca come non letto
          };
          
          await notificationStarRef.set(notificationStarData);
          print('Stella del commento salvata in notificationstars per l\'utente $commentOwnerId');
        }
      }
      
      // Aggiorna il conteggio totale delle stelle usando transazione atomica
      await commentRef.child('star_count').set(newStarCount);
      
      // Verifica finale dello stato su Firebase per sicurezza (fix iOS)
      final finalStarSnapshot = await starUsersRef.child(currentUserId).get();
      final finalStarState = finalStarSnapshot.exists;
      
      // Aggiorna lo stato locale DOPO aver verificato Firebase
      if (mounted) {
      setState(() {
        // Aggiorna il conteggio stelle nel commento locale
          comment['star_count'] = newStarCount;
          
          // Aggiorna lo stato della stella basato sulla verifica finale di Firebase
          if (comment['star_users'] == null) {
            comment['star_users'] = <String, dynamic>{};
          }
          
          // Usa lo stato finale verificato da Firebase
          if (finalStarState) {
            comment['star_users'][currentUserId] = true;
          } else {
            comment['star_users'].remove(currentUserId);
        }
      });
      }
      
      print('Stelle aggiornate per il commento $commentId: $newStarCount (utente ${hasUserStarred ? 'rimosso' : 'aggiunto'})');
      
    } catch (e) {
      print('Errore nell\'aggiornamento delle stelle del commento: $e');
      // In caso di errore, ricarica i dati dal database per sincronizzare
      if (mounted) {
        try {
          // Ricarica lo stato attuale da Firebase per sincronizzare
          final commentRef = _database
              .child('users')
              .child('users')
              .child(videoUserId)
              .child('videos')
              .child(videoId)
              .child('comments')
              .child(commentId);
          
          final refreshSnapshot = await commentRef.get();
          if (refreshSnapshot.exists) {
            final refreshedComment = Map<String, dynamic>.from(refreshSnapshot.value as Map);
            setState(() {
              comment['star_count'] = refreshedComment['star_count'] ?? 0;
              comment['star_users'] = refreshedComment['star_users'] ?? {};
            });
          }
        } catch (refreshError) {
          print('Errore nel refresh del commento: $refreshError');
        }
      }
    }
  }

  Future<void> _handleVideoShare(Map<String, dynamic> video) async {
    try {
      final videoTitle = video['title'] ?? 'Video';
      final userName = video['displayName'] ?? 'Unknown User';
      
      // TODO: Implementare la condivisione effettiva
      // Per ora mostriamo solo un messaggio
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.share, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text('Condividi: $videoTitle di $userName', style: TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      print('Error handling video share: $e');
    }
  }

  void _triggerConfettiAnimation(String videoId, String emoji, double tapX, double tapY) {
    // Crea un ID unico per questa animazione
    final animationId = '${videoId}_${DateTime.now().millisecondsSinceEpoch}';
    _currentConfettiId[videoId] = animationId;
    
    // Crea un controller separato per questa animazione
    final controller = AnimationController(
      duration: Duration(milliseconds: 1800), // Durata più breve e professionale
      vsync: this,
    );
    
    // Salva il controller attivo per questa animazione
    _activeConfettiControllers[animationId] = controller;
    
    // Crea le particelle dei confetti con pattern più strutturato
    List<ConfettiParticle> particles = [];
     final random = math.Random();
    
    // Crea un numero fisso di particelle per consistenza
    final particleCount = 6; // Numero fisso invece di casuale
    
    for (int i = 0; i < particleCount; i++) {
      // Calcola angoli distribuiti uniformemente
       final angle = (i * 2 * math.pi / particleCount) + (random.nextDouble() - 0.5) * 0.5; // Piccola variazione
      
      // Distanza di partenza e arrivo più controllata
      final startDistance = 20.0 + random.nextDouble() * 10; // Dispersione iniziale più piccola
      final endDistance = 80.0 + random.nextDouble() * 40; // Dispersione finale controllata
      
      // Calcola posizioni basate su angoli
       final startX = tapX + math.cos(angle) * startDistance;
       final startY = tapY + math.sin(angle) * startDistance;
       final endX = tapX + math.cos(angle) * endDistance;
      final endY = tapY - 120 - random.nextDouble() * 60; // Movimento verso l'alto più controllato
      
      final particle = ConfettiParticle(
        emoji: emoji,
        startX: startX,
        startY: startY,
        endX: endX,
        endY: endY,
         size: 18.0 + random.nextDouble() * 8, // Dimensioni più uniformi
        speed: 1.0 + random.nextDouble() * 0.2, // Velocità più consistente
        rotation: angle, // Rotazione iniziale basata sull'angolo
        rotationSpeed: (random.nextDouble() - 0.5) * 2, // Rotazione più sottile
      );
      particles.add(particle);
    }
    
    // Salva le particelle con l'ID dell'animazione
    _confettiParticles[animationId] = particles;
    
    // Forza la ricostruzione del widget per mostrare le nuove particelle
    setState(() {});
    
    // Avvia l'animazione
    controller.forward().then((_) {
      // Pulisci tutto dopo l'animazione
      _confettiParticles.remove(animationId);
      _activeConfettiControllers.remove(animationId);
      if (_currentConfettiId[videoId] == animationId) {
        _currentConfettiId.remove(videoId);
      }
      setState(() {});
      
      // Dispose del controller
      controller.dispose();
    });
  }

  Future<void> _handleQuickEmojiComment(Map<String, dynamic> video, String emoji, double tapX, double tapY) async {
    if (_currentUser == null) return;
    
    // Avvia l'animazione dei confetti
    _triggerConfettiAnimation(video['id'], emoji, tapX, tapY);
    
    try {
      final currentUserId = _currentUser!.uid;
      
      // Carica i dati aggiornati dell'utente dal profilo
      final userProfileSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUserId)
          .child('profile')
          .get();
      
      String currentUserDisplayName = 'Anonymous';
      String? currentUserProfileImage;
      
      if (userProfileSnapshot.exists) {
        final profileData = userProfileSnapshot.value as Map<dynamic, dynamic>?;
        if (profileData != null) {
          currentUserDisplayName = profileData['username'] as String? ?? 
                                  profileData['displayName'] as String? ?? 
                                  _currentUser!.displayName ?? 
                                  'Anonymous';
          currentUserProfileImage = profileData['profileImageUrl'] as String? ?? 
                                   _currentUser!.photoURL;
        }
      } else {
        // Fallback ai dati dell'utente corrente
        currentUserDisplayName = _currentUser!.displayName ?? 'Anonymous';
        currentUserProfileImage = _currentUser!.photoURL;
      }
      
      final videoId = video['id'] as String;
      final videoUserId = video['userId'] as String;
      
      // Crea un ID unico per il commento
      final commentId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Percorso per salvare il commento
      final commentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);
      
      // Dati del commento con emoji ripetuta 3 volte
      final commentData = {
        'id': commentId,
        'text': '$emoji$emoji$emoji',
        'userId': currentUserId,
        'userDisplayName': currentUserDisplayName,
        'userProfileImage': currentUserProfileImage,
        'timestamp': ServerValue.timestamp,
        'videoId': videoId,
        'replies_count': 0,
        'star_count': 0,
        'star_users': {},
        'isQuickEmoji': true, // Flag per identificare commenti rapidi
      };
      
      // Salva il commento nel database
      await commentRef.set(commentData);
      
      // Salva il commento nella cartella notificationcomment del proprietario del video
      if (currentUserId != videoUserId) {
        final notificationCommentRef = _database
            .child('users')
            .child('users')
            .child(videoUserId)
            .child('notificationcomment')
            .child(commentId);
        
        final notificationCommentData = {
          'id': commentId,
          'text': '$emoji$emoji$emoji',
          'userId': currentUserId,
          'userDisplayName': currentUserDisplayName,
          'userProfileImage': currentUserProfileImage,
          'timestamp': ServerValue.timestamp,
          'videoId': videoId,
          'videoTitle': video['title'] ?? 'Untitled Video',
          'videoOwnerId': videoUserId,
          'type': 'comment',
          'read': false,
          'replies_count': 0,
          'star_count': 0,
          'star_users': {},
          'isQuickEmoji': true,
        };
        
        await notificationCommentRef.set(notificationCommentData);
      }
      
      // Aggiorna la cache del conteggio commenti
      final cacheKey = '${videoUserId}_$videoId';
      final currentCount = _commentsCountCache[cacheKey] ?? 0;
      _commentsCountCache[cacheKey] = currentCount + 1;
      
      // Forza la ricostruzione del widget per aggiornare il conteggio
      setState(() {});
      
    } catch (e) {
      print('Errore nel salvataggio del commento rapido: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding comment'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleVideoComment(Map<String, dynamic> video) async {
    if (_currentUser == null) return;
    
    final videoId = video['id'] as String;
    final videoUserId = video['userId'] as String;
    final videoOwnerName = video['username'] ?? 'User';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _buildCommentsSheet(videoId, videoUserId, videoOwnerName, video),
      ),
    );
  }
  
  Widget _buildCommentsSheet(String videoId, String videoUserId, String videoOwnerName, Map<String, dynamic> video) {
    final TextEditingController commentController = TextEditingController();
    final FocusNode commentFocusNode = FocusNode();
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.6, // Altezza fissa al 60% dello schermo
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
            children: [
          // Handle della tendina
          Container(
            margin: EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header con titolo e conteggio commenti (minimal)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white70 
                          : Colors.black54,
                    ),
                  ),
                  SizedBox(width: 6),
                  FutureBuilder<int>(
                    future: _getCommentsCount(videoId, videoUserId),
                    builder: (context, snapshot) {
                      final commentCount = snapshot.data ?? 0;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(0xFF6C63FF).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          commentCount.toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Lista commenti con StreamBuilder per aggiornamenti in tempo reale
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _database
                  .child('users')
                  .child('users')
                  .child(videoUserId)
                  .child('videos')
                  .child(videoId)
                  .child('comments')
                  .onValue,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading comments',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }
                
                if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 40),
                          Icon(
                            Icons.comment_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Be the first to comment!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          SizedBox(height: 40),
                        ],
                      ),
                    ),
                  );
                }
                
                // iOS: i commenti possono arrivare come Map o List
                final dynamic rawComments = snapshot.data!.snapshot.value;
                Map<dynamic, dynamic>? commentsData;
                if (rawComments is Map) {
                  commentsData = rawComments;
                } else if (rawComments is List) {
                  commentsData = {
                    for (int i = 0; i < rawComments.length; i++)
                      if (rawComments[i] != null) i.toString(): rawComments[i]
                  };
                } else {
                  commentsData = null;
                }
                if (commentsData == null || commentsData.isEmpty) {
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 40),
                          Icon(
                            Icons.comment_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Be the first to comment!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          SizedBox(height: 40),
                        ],
                      ),
                    ),
                  );
                }
                
                // Converti i commenti in lista e ordina per timestamp
                List<Map<String, dynamic>> comments = [];
                commentsData.forEach((commentId, commentData) {
                  if (commentData is Map) {
                    final comment = Map<String, dynamic>.from(commentData);
                    comment['id'] = commentId;
                    comments.add(comment);
                  }
                });
                
                // Ordina per timestamp (più recenti prima)
                comments.sort((a, b) {
                  final aTimestamp = a['timestamp'] ?? 0;
                  final bTimestamp = b['timestamp'] ?? 0;
                  return bTimestamp.compareTo(aTimestamp);
                });
                
                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return _buildCommentItem(comment, videoUserId);
                  },
                );
              },
            ),
          ),
          
          // Campo input commento
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Color(0xFF2A2A2A) 
                  : Colors.grey[50],
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Immagine profilo utente
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF6C63FF),
                        Color(0xFFFF6B6B),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: _profileImageUrl != null
                      ? ClipOval(
                          child: Image.network(
                            _profileImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.person, color: Colors.white, size: 16);
                            },
                          ),
                        )
                      : Icon(Icons.person, color: Colors.white, size: 16),
                ),
                
                SizedBox(width: 12),
                
                // Campo di input
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[800] 
                          : Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: commentFocusNode.hasFocus 
                            ? Color(0xFF6C63FF) 
                            : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                                            child: TextField(
                          controller: commentController,
                          focusNode: commentFocusNode,
                          maxLines: null, // Permette infinite righe
                          textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                          keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          maxLength: 120,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(120),
                          ],
                          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        ),
                  ),
                ),
                
                SizedBox(width: 12),
                
                // Pulsante invia
                GestureDetector(
                  onTap: () async {
                    if (commentController.text.trim().isNotEmpty) {
                      await _submitComment(
                        videoId, 
                        videoUserId, 
                        commentController.text.trim(),
                        video,
                      );
                      commentController.clear();
                      commentFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(10),
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
                    ),
                    child: Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCommentItem(Map<String, dynamic> comment, String videoUserId) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Converti timestamp in DateTime
    DateTime commentTime;
    if (comment['timestamp'] is int) {
      commentTime = DateTime.fromMillisecondsSinceEpoch(comment['timestamp']);
    } else {
      commentTime = DateTime.now();
    }
    
    // Check if current user is the comment owner or the video owner
    final isCommentOwner = _currentUser?.uid == comment['userId'];
    final isVideoOwner = _currentUser?.uid == videoUserId;
    final canDeleteComment = isCommentOwner || isVideoOwner;
    
    // Load profile image and username dynamically for this comment
    final userId = comment['userId']?.toString() ?? '';
    final profileImageUrl = comment['userProfileImage']?.toString() ?? '';
    
    return FutureBuilder<Map<String, String?>>(
      future: userId.isNotEmpty 
          ? Future.wait([
              _loadUserProfileImage(userId),
              _loadUserName(userId),
            ]).then((results) => {
              'profileImage': results[0],
              'username': results[1],
            })
          : Future.value({'profileImage': null, 'username': null}),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data?['profileImage'] ?? profileImageUrl;
        final currentUsername = snapshot.data?['username'] ?? comment['userDisplayName'] ?? 'Anonymous';
    
    return GestureDetector(
      onLongPress: canDeleteComment ? () => _showCommentDeleteDialog(comment, videoUserId) : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Immagine profilo utente (cliccabile)
            GestureDetector(
              onTap: () => _navigateToUserProfile(comment['userId']),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color(0xFF6C63FF).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: ClipOval(
                  child: currentProfileImageUrl.isNotEmpty
                      ? Image.network(
                          currentProfileImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF6C63FF),
                                    Color(0xFF8B7CF6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 16,
                              ),
                            );
                          },
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFF8B7CF6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                ),
              ),
            ),
            
            SizedBox(width: 12),
            
            // Contenuto del commento
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome utente e timestamp
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _navigateToUserProfile(comment['userId']),
                        child: Text(
                          currentUsername,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        _formatTimestamp(commentTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 4),
                  
                  // Testo del commento
                  Text(
                    comment['text'] ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  
                  SizedBox(height: 8),
                  
                  // Pulsanti azioni (Reply, Star e View Replies)
                  Row(
                    children: [
                      // Pulsante Reply
                      GestureDetector(
                        onTap: () => _showReplyInput(comment, videoUserId),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.reply,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Reply',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(width: 16),
                      
                      // Pulsante Star
                      GestureDetector(
                        onTap: () => _handleCommentStar(comment, videoUserId),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _commentStarAnimationControllers[comment['id']] ?? 
                                          AnimationController(duration: Duration.zero, vsync: this),
                                builder: (context, child) {
                                  final scaleAnimation = _commentStarScaleAnimations[comment['id']];
                                  final rotationAnimation = _commentStarRotationAnimations[comment['id']];
                                  final isStarred = _isCommentStarredByCurrentUser(comment);
                                  
                                  return Transform.scale(
                                    scale: scaleAnimation?.value ?? 1.0,
                                    child: Transform.rotate(
                                      angle: rotationAnimation?.value ?? 0.0,
                                      child: isStarred
                                          ? ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  colors: [
                                                    Color(0xFF6C63FF),
                                                    Color(0xFFFF6B6B),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ).createShader(bounds);
                                              },
                                              child: Icon(
                                                Icons.star,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            )
                                          : Icon(
                                              Icons.star_border,
                                              color: Colors.grey[600],
                                              size: 18,
                                            ),
                                    ),
                                  );
                                },
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${comment['star_count'] ?? 0}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      SizedBox(width: 16),
                      
                      // Pulsante View Replies (se ci sono risposte)
                      if (comment['replies_count'] != null && (comment['replies_count'] as int) > 0)
                        GestureDetector(
                          onTap: () => _showRepliesSheet(comment, videoUserId),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.expand_more,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${comment['replies_count']} replies',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Future<void> _submitComment(String videoId, String videoUserId, String commentText, Map<String, dynamic> video) async {
    try {
      final currentUserId = _currentUser!.uid;
      
      // Carica i dati aggiornati dell'utente dal profilo
      final userProfileSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUserId)
          .child('profile')
          .get();
      
      String currentUserDisplayName = 'Anonymous';
      String? currentUserProfileImage;
      
      if (userProfileSnapshot.exists) {
        final profileData = userProfileSnapshot.value as Map<dynamic, dynamic>?;
        if (profileData != null) {
          currentUserDisplayName = profileData['username'] as String? ?? 
                                  profileData['displayName'] as String? ?? 
                                  _currentUser!.displayName ?? 
                                  'Anonymous';
          currentUserProfileImage = profileData['profileImageUrl'] as String? ?? 
                                   _currentUser!.photoURL;
        }
      } else {
        // Fallback ai dati dell'utente corrente
        currentUserDisplayName = _currentUser!.displayName ?? 'Anonymous';
        currentUserProfileImage = _currentUser!.photoURL;
      }
      
      // Crea un ID unico per il commento
      final commentId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Percorso per salvare il commento
      final commentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);
      
      // Dati del commento
      final commentData = {
        'id': commentId,
        'text': commentText,
        'userId': currentUserId,
        'userDisplayName': currentUserDisplayName,
        'userProfileImage': currentUserProfileImage,
        'timestamp': ServerValue.timestamp,
        'videoId': videoId,
        'replies_count': 0, // Inizializza il conteggio delle risposte
        'star_count': 0, // Inizializza il conteggio delle stelle
        'star_users': {}, // Inizializza la lista degli utenti che hanno messo stella
      };
      
      // Salva il commento nel database
      await commentRef.set(commentData);
      
      // Salva il commento nella cartella notificationcomment del proprietario del video
      if (currentUserId != videoUserId) {
        final notificationCommentRef = _database
            .child('users')
            .child('users')
            .child(videoUserId)
            .child('notificationcomment')
            .child(commentId);
        
        // Dati del commento per le notifiche (con informazioni aggiuntive)
        final notificationCommentData = {
          'id': commentId,
          'text': commentText,
          'userId': currentUserId,
          'userDisplayName': currentUserDisplayName,
          'userProfileImage': currentUserProfileImage,
          'timestamp': ServerValue.timestamp,
          'videoId': videoId,
          'videoTitle': video['title'] ?? 'Untitled Video',
          'videoOwnerId': videoUserId,
          'type': 'comment',
          'read': false, // Marca come non letto
          'replies_count': 0,
          'star_count': 0,
          'star_users': {},
        };
        
        await notificationCommentRef.set(notificationCommentData);
        print('Commento salvato in notificationcomment per l\'utente $videoUserId');
      }
      
      // Aggiorna la cache del conteggio commenti
      final cacheKey = '${videoUserId}_$videoId';
      final currentCount = _commentsCountCache[cacheKey] ?? 0;
      _commentsCountCache[cacheKey] = currentCount + 1;
      
      // Forza la ricostruzione del widget per aggiornare il conteggio
      setState(() {});
      
      print('Commento salvato per il video $videoId');
      
      // Invia notifica push al proprietario del video (se non è lo stesso utente)
      if (currentUserId != videoUserId) {
        await _sendCommentNotification(videoUserId, currentUserDisplayName, video);
      }
      
      // Mostra feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Comment posted!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Color(0xFF6C63FF),
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      print('Errore nel salvataggio del commento: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting comment'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showCommentDeleteDialog(Map<String, dynamic> comment, String videoUserId) {
    // Check if current user is the comment owner or video owner
    final isCommentOwner = _currentUser?.uid == comment['userId'];
    final isVideoOwner = _currentUser?.uid == videoUserId;
    final canDeleteComment = isCommentOwner || isVideoOwner;
    
    String deleteText = 'Delete comment';
    if (isVideoOwner && !isCommentOwner) {
      deleteText = 'Delete comment (as video owner)';
    }
    
    // Check if comment is starred by current user
    final isStarred = _isCommentStarredByCurrentUser(comment);
    final starCount = comment['star_count'] ?? 0;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle della tendina
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Opzione star
            ListTile(
              leading: AnimatedBuilder(
                animation: _commentStarAnimationControllers[comment['id']] ?? 
                          AnimationController(duration: Duration.zero, vsync: this),
                builder: (context, child) {
                  final scaleAnimation = _commentStarScaleAnimations[comment['id']];
                  final rotationAnimation = _commentStarRotationAnimations[comment['id']];
                  
                  return Transform.scale(
                    scale: scaleAnimation?.value ?? 1.0,
                    child: Transform.rotate(
                      angle: rotationAnimation?.value ?? 0.0,
                      child: isStarred
                          ? ShaderMask(
                              shaderCallback: (Rect bounds) {
                                return LinearGradient(
                                  colors: [
                                    Color(0xFF6C63FF),
                                    Color(0xFFFF6B6B),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds);
                              },
                              child: Icon(
                                Icons.star,
                                color: Colors.white,
                                size: 24,
                              ),
                            )
                          : Icon(
                              Icons.star_border,
                              color: Colors.grey[600],
                              size: 24,
                            ),
                    ),
                  );
                },
              ),
              title: Text(
                isStarred ? 'Remove star' : 'Add star',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isStarred ? Colors.amber : Colors.grey[600],
                ),
              ),
              subtitle: starCount > 0 ? Text(
                '$starCount star${starCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ) : null,
              onTap: () {
                Navigator.pop(context);
                _handleCommentStar(comment, videoUserId);
              },
            ),
            
            // Opzione delete (solo se l'utente può eliminare il commento)
            if (canDeleteComment)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 24,
                ),
                title: Text(
                  deleteText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.red[400],
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteComment(comment, videoUserId);
                },
              ),
            
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteComment(Map<String, dynamic> comment, String videoUserId) async {
    try {
      final commentId = comment['id'] as String;
      final videoId = comment['videoId'] as String;
      
      // Percorso per eliminare il commento
      final commentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId);
      
      // Elimina il commento dal database
      await commentRef.remove();
      
      // Aggiorna la cache del conteggio commenti
      final cacheKey = '${videoUserId}_$videoId';
      final currentCount = _commentsCountCache[cacheKey] ?? 0;
      if (currentCount > 0) {
        _commentsCountCache[cacheKey] = currentCount - 1;
      }
      
      // Forza la ricostruzione del widget per aggiornare il conteggio
      setState(() {});
      
      print('Commento eliminato: $commentId');
      
      // Mostra feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Comment deleted',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      print('Errore nell\'eliminazione del commento: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting comment'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showReplyInput(Map<String, dynamic> parentComment, String videoUserId) {
    final TextEditingController replyController = TextEditingController();
    final FocusNode replyFocusNode = FocusNode();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle della tendina
              Container(
                margin: EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header (minimal)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Center(
                  child: Text(
                    'Reply to ${parentComment['userDisplayName'] ?? 'comment'}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white70 
                          : Colors.black54,
                    ),
                  ),
                ),
              ),
              
              // Campo input risposta
              Container(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    // Immagine profilo utente
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF6C63FF),
                            Color(0xFFFF6B6B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: _profileImageUrl != null
                          ? ClipOval(
                              child: Image.network(
                                _profileImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(Icons.person, color: Colors.white, size: 16);
                                },
                              ),
                            )
                          : Icon(Icons.person, color: Colors.white, size: 16),
                    ),
                    
                    SizedBox(width: 12),
                    
                    // Campo di input
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[800] 
                              : Colors.white,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextField(
                          controller: replyController,
                          focusNode: replyFocusNode,
                          maxLines: null, // Permette infinite righe
                          textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                          keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                          decoration: InputDecoration(
                            hintText: 'Write a reply...',
                            hintStyle: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          maxLength: 120,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(120),
                          ],
                          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        ),
                      ),
                    ),
                    
                    SizedBox(width: 12),
                    
                    // Pulsante invia
                    GestureDetector(
                      onTap: () async {
                        if (replyController.text.trim().isNotEmpty) {
                          await _submitReply(parentComment, videoUserId, replyController.text.trim());
                          replyController.clear();
                          replyFocusNode.unfocus();
                          FocusScope.of(context).unfocus();
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.all(10),
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
                        ),
                        child: Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 18,
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

  Future<void> _submitReply(Map<String, dynamic> parentComment, String videoUserId, String replyText) async {
    try {
      final currentUserId = _currentUser!.uid;
      
      // Carica i dati aggiornati dell'utente dal profilo
      final userProfileSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUserId)
          .child('profile')
          .get();
      
      String currentUserDisplayName = 'Anonymous';
      String? currentUserProfileImage;
      
      if (userProfileSnapshot.exists) {
        final profileData = userProfileSnapshot.value as Map<dynamic, dynamic>?;
        if (profileData != null) {
          currentUserDisplayName = profileData['username'] as String? ?? 
                                  profileData['displayName'] as String? ?? 
                                  _currentUser!.displayName ?? 
                                  'Anonymous';
          currentUserProfileImage = profileData['profileImageUrl'] as String? ?? 
                                   _currentUser!.photoURL;
        }
      } else {
        // Fallback ai dati dell'utente corrente
        currentUserDisplayName = _currentUser!.displayName ?? 'Anonymous';
        currentUserProfileImage = _currentUser!.photoURL;
      }
      
      final parentCommentId = parentComment['id'] as String;
      final videoId = parentComment['videoId'] as String;
      
      // Crea un ID unico per la risposta
      final replyId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Percorso per salvare la risposta
      final replyRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId)
          .child('replies')
          .child(replyId);
      
      // Dati della risposta
      final replyData = {
        'id': replyId,
        'text': replyText,
        'userId': currentUserId,
        'userDisplayName': currentUserDisplayName,
        'userProfileImage': currentUserProfileImage,
        'timestamp': ServerValue.timestamp,
        'parentCommentId': parentCommentId,
        'videoId': videoId,
        'star_count': 0, // Inizializza il conteggio delle stelle
        'star_users': {}, // Inizializza la lista degli utenti che hanno messo stella
      };
      
      // Salva la risposta nel database
      await replyRef.set(replyData);
      
      // Aggiorna il conteggio delle risposte nel commento padre
      final parentCommentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId);
      
      // Ottieni il conteggio attuale delle risposte
      final repliesCountSnapshot = await parentCommentRef.child('replies_count').get();
      int currentRepliesCount = 0;
      if (repliesCountSnapshot.exists) {
        currentRepliesCount = repliesCountSnapshot.value as int? ?? 0;
      }
      
      // Incrementa il conteggio
      await parentCommentRef.child('replies_count').set(currentRepliesCount + 1);
      
      print('Risposta salvata per il commento $parentCommentId');
      
      // Mostra feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reply posted!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Color(0xFF6C63FF),
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      print('Errore nel salvataggio della risposta: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting reply'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showRepliesSheet(Map<String, dynamic> parentComment, String videoUserId) {
    final TextEditingController replyController = TextEditingController();
    final FocusNode replyFocusNode = FocusNode();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle della tendina
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header con commento originale
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  // Titolo
                  Center(
                    child: Text(
                      'Replies',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white70 
                            : Colors.black54,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Commento originale con caricamento dinamico dei dati
                  FutureBuilder<Map<String, String?>>(
                    future: Future.wait([
                      _loadUserProfileImage(parentComment['userId']),
                      _loadUserName(parentComment['userId']),
                    ]).then((results) => {
                      'profileImage': results[0],
                      'username': results[1],
                    }),
                    builder: (context, snapshot) {
                      final currentProfileImageUrl = snapshot.data?['profileImage'] ?? parentComment['userProfileImage']?.toString() ?? '';
                      final currentUsername = snapshot.data?['username'] ?? parentComment['userDisplayName'] ?? 'Anonymous';
                      
                      return Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[800] 
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Immagine profilo del commento originale
                            GestureDetector(
                              onTap: () => _navigateToUserProfile(parentComment['userId']),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Color(0xFF6C63FF).withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: ClipOval(
                                  child: currentProfileImageUrl.isNotEmpty
                                      ? Image.network(
                                          currentProfileImageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Color(0xFF6C63FF),
                                                    Color(0xFF8B7CF6),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF6C63FF),
                                                Color(0xFF8B7CF6),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            
                            SizedBox(width: 12),
                            
                            // Contenuto del commento originale
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Nome utente e timestamp
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _navigateToUserProfile(parentComment['userId']),
                                        child: Text(
                                          currentUsername,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).brightness == Brightness.dark 
                                                ? Colors.white 
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(parentComment['timestamp'] ?? DateTime.now().millisecondsSinceEpoch)),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  SizedBox(height: 4),
                                  
                                  // Testo del commento originale
                                  Text(
                                    parentComment['text'] ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.white70 
                                          : Colors.black87,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // Lista risposte con StreamBuilder
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: _database
                    .child('users')
                    .child('users')
                    .child(videoUserId)
                    .child('videos')
                    .child(parentComment['videoId'])
                    .child('comments')
                    .child(parentComment['id'])
                    .child('replies')
                    .onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading replies',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  
                  if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 40),
                            Icon(
                              Icons.reply_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No replies yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Be the first to reply!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                            SizedBox(height: 40),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  final repliesData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>?;
                  if (repliesData == null || repliesData.isEmpty) {
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 40),
                            Icon(
                              Icons.reply_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No replies yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Be the first to reply!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                            SizedBox(height: 40),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  // Converti le risposte in lista e ordina per timestamp
                  List<Map<String, dynamic>> replies = [];
                  repliesData.forEach((replyId, replyData) {
                    if (replyData is Map) {
                      final reply = Map<String, dynamic>.from(replyData);
                      reply['id'] = replyId;
                      replies.add(reply);
                    }
                  });
                  
                  // Ordina per timestamp (più recenti prima)
                  replies.sort((a, b) {
                    final aTimestamp = a['timestamp'] ?? 0;
                    final bTimestamp = b['timestamp'] ?? 0;
                    return bTimestamp.compareTo(aTimestamp);
                  });
                  
                  return ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    itemCount: replies.length,
                    itemBuilder: (context, index) {
                      final reply = replies[index];
                      return _buildReplyItem(reply, videoUserId);
                    },
                  );
                },
              ),
            ),
            
            // Campo input per nuova risposta
            Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Color(0xFF2A2A2A) 
                    : Colors.grey[50],
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Immagine profilo utente
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF6C63FF),
                          Color(0xFFFF6B6B),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: _profileImageUrl != null
                        ? ClipOval(
                            child: Image.network(
                              _profileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(Icons.person, color: Colors.white, size: 16);
                              },
                            ),
                          )
                        : Icon(Icons.person, color: Colors.white, size: 16),
                  ),
                  
                  SizedBox(width: 12),
                  
                  // Campo di input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[800] 
                            : Colors.white,
                        borderRadius: BorderRadius.circular(25),
                      ),
                                             child: TextField(
                         controller: replyController,
                         focusNode: replyFocusNode,
                         maxLines: null, // Permette infinite righe
                         textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                         keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                         decoration: InputDecoration(
                           hintText: 'Add a reply...',
                           hintStyle: TextStyle(
                             color: Colors.grey[500],
                             fontSize: 14,
                           ),
                           border: InputBorder.none,
                           contentPadding: EdgeInsets.symmetric(
                             horizontal: 16,
                             vertical: 10,
                           ),
                         ),
                         maxLength: 120,
                         inputFormatters: [
                           LengthLimitingTextInputFormatter(120),
                         ],
                         buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                         onSubmitted: (text) async {
                           if (text.trim().isNotEmpty) {
                             await _submitReply(parentComment, videoUserId, text.trim());
                             replyController.clear();
                             replyFocusNode.unfocus();
                             FocusScope.of(context).unfocus();
                           }
                         },
                       ),
                    ),
                  ),
                  
                  SizedBox(width: 12),
                  
                                     // Pulsante invia
                   GestureDetector(
                     onTap: () async {
                       if (replyController.text.trim().isNotEmpty) {
                         await _submitReply(parentComment, videoUserId, replyController.text.trim());
                         replyController.clear();
                         replyFocusNode.unfocus();
                         FocusScope.of(context).unfocus();
                       }
                     },
                    child: Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF6C63FF),
                            Color(0xFFFF6B6B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyItem(Map<String, dynamic> reply, String videoUserId) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Converti timestamp in DateTime
    DateTime replyTime;
    if (reply['timestamp'] is int) {
      replyTime = DateTime.fromMillisecondsSinceEpoch(reply['timestamp']);
    } else {
      replyTime = DateTime.now();
    }
    
    // Check if current user is the reply owner or the video owner
    final isReplyOwner = _currentUser?.uid == reply['userId'];
    final isVideoOwner = _currentUser?.uid == videoUserId;
    final canDeleteReply = isReplyOwner || isVideoOwner;
    
    // Load profile image and username dynamically for this reply
    final userId = reply['userId']?.toString() ?? '';
    final profileImageUrl = reply['userProfileImage']?.toString() ?? '';
    
    return FutureBuilder<Map<String, String?>>(
      future: userId.isNotEmpty 
          ? Future.wait([
              _loadUserProfileImage(userId),
              _loadUserName(userId),
            ]).then((results) => {
              'profileImage': results[0],
              'username': results[1],
            })
          : Future.value({'profileImage': null, 'username': null}),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data?['profileImage'] ?? profileImageUrl;
        final currentUsername = snapshot.data?['username'] ?? reply['userDisplayName'] ?? 'Anonymous';
    
    return GestureDetector(
      onLongPress: canDeleteReply ? () => _showReplyDeleteDialog(reply, videoUserId) : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indentazione per mostrare che è una risposta
            Container(
              width: 20,
              height: 20,
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey[400]!, width: 2),
                  bottom: BorderSide(color: Colors.grey[400]!, width: 2),
                ),
              ),
            ),
            
            // Immagine profilo utente (cliccabile)
            GestureDetector(
              onTap: () => _navigateToUserProfile(reply['userId']),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color(0xFF6C63FF).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: ClipOval(
                  child: currentProfileImageUrl.isNotEmpty
                      ? Image.network(
                          currentProfileImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF6C63FF),
                                    Color(0xFF8B7CF6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 14,
                              ),
                            );
                          },
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFF8B7CF6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                ),
              ),
            ),
            
            SizedBox(width: 12),
            
            // Contenuto della risposta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome utente e timestamp
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _navigateToUserProfile(reply['userId']),
                        child: Text(
                          currentUsername,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        _formatTimestamp(replyTime),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 4),
                  
                  // Testo della risposta
                  Text(
                    reply['text'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  
                  SizedBox(height: 8),
                  
                  // Pulsante Star
                  GestureDetector(
                    onTap: () => _handleReplyStar(reply, videoUserId),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _commentStarAnimationControllers[reply['id']] ?? 
                                      AnimationController(duration: Duration.zero, vsync: this),
                            builder: (context, child) {
                              final scaleAnimation = _commentStarScaleAnimations[reply['id']];
                              final rotationAnimation = _commentStarRotationAnimations[reply['id']];
                              final isStarred = _isCommentStarredByCurrentUser(reply);
                              
                              return Transform.scale(
                                scale: scaleAnimation?.value ?? 1.0,
                                child: Transform.rotate(
                                  angle: rotationAnimation?.value ?? 0.0,
                                  child: isStarred
                                      ? ShaderMask(
                                          shaderCallback: (Rect bounds) {
                                            return LinearGradient(
                                              colors: [
                                                Color(0xFF6C63FF),
                                                Color(0xFFFF6B6B),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ).createShader(bounds);
                                          },
                                          child: Icon(
                                            Icons.star,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        )
                                      : Icon(
                                          Icons.star_border,
                                          color: Colors.grey[600],
                                          size: 16,
                                        ),
                                ),
                              );
                            },
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${reply['star_count'] ?? 0}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
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
    );
      },
    );
  }

  void _showReplyDeleteDialog(Map<String, dynamic> reply, String videoUserId) {
    // Check if current user is the reply owner or video owner
    final isReplyOwner = _currentUser?.uid == reply['userId'];
    final isVideoOwner = _currentUser?.uid == videoUserId;
    final canDeleteReply = isReplyOwner || isVideoOwner;
    
    String deleteText = 'Delete reply';
    if (isVideoOwner && !isReplyOwner) {
      deleteText = 'Delete reply (as video owner)';
    }
    
    // Check if reply is starred by current user
    final isStarred = _isCommentStarredByCurrentUser(reply);
    final starCount = reply['star_count'] ?? 0;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle della tendina
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Opzione star
            ListTile(
              leading: AnimatedBuilder(
                animation: _commentStarAnimationControllers[reply['id']] ?? 
                          AnimationController(duration: Duration.zero, vsync: this),
                builder: (context, child) {
                  final scaleAnimation = _commentStarScaleAnimations[reply['id']];
                  final rotationAnimation = _commentStarRotationAnimations[reply['id']];
                  
                  return Transform.scale(
                    scale: scaleAnimation?.value ?? 1.0,
                    child: Transform.rotate(
                      angle: rotationAnimation?.value ?? 0.0,
                      child: isStarred
                          ? ShaderMask(
                              shaderCallback: (Rect bounds) {
                                return LinearGradient(
                                  colors: [
                                    Color(0xFF6C63FF),
                                    Color(0xFFFF6B6B),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds);
                              },
                              child: Icon(
                                Icons.star,
                                color: Colors.white,
                                size: 24,
                              ),
                            )
                          : Icon(
                              Icons.star_border,
                              color: Colors.grey[600],
                              size: 24,
                            ),
                    ),
                  );
                },
              ),
              title: Text(
                isStarred ? 'Remove star' : 'Add star',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isStarred ? Colors.amber : Colors.grey[600],
                ),
              ),
              subtitle: starCount > 0 ? Text(
                '$starCount star${starCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ) : null,
              onTap: () {
                Navigator.pop(context);
                _handleReplyStar(reply, videoUserId);
              },
            ),
            
            // Opzione delete (solo se l'utente può eliminare la risposta)
            if (canDeleteReply)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 24,
                ),
                title: Text(
                  deleteText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.red[400],
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteReply(reply, videoUserId);
                },
              ),
            
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReply(Map<String, dynamic> reply, String videoUserId) async {
    try {
      final replyId = reply['id'] as String;
      final parentCommentId = reply['parentCommentId'] as String;
      final videoId = reply['videoId'] as String;
      
      // Percorso per eliminare la risposta
      final replyRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId)
          .child('replies')
          .child(replyId);
      
      // Elimina la risposta dal database
      await replyRef.remove();
      
      // Decrementa il conteggio delle risposte nel commento padre
      final parentCommentRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId);
      
      final repliesCountSnapshot = await parentCommentRef.child('replies_count').get();
      int currentRepliesCount = 0;
      if (repliesCountSnapshot.exists) {
        currentRepliesCount = repliesCountSnapshot.value as int? ?? 0;
      }
      
      if (currentRepliesCount > 0) {
        await parentCommentRef.child('replies_count').set(currentRepliesCount - 1);
      }
      
      print('Risposta eliminata: $replyId');
      
      // Mostra feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reply deleted',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      print('Errore nell\'eliminazione della risposta: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting reply'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleVideoSave(Map<String, dynamic> video) async {
    try {
      final videoTitle = video['title'] ?? 'Video';
      final userName = video['displayName'] ?? 'Unknown User';
      
      // TODO: Implementare il salvataggio effettivo
      // Per ora mostriamo solo un messaggio
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.bookmark, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text('Salvato: $videoTitle di $userName', style: TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      print('Error handling video save: $e');
    }
  }

  Future<void> _initializeVideoControllers() async {
    // Dispose dei controller esistenti con controllo per iOS
    for (final controller in _videoControllers.values) {
      try {
        if (controller.value.isInitialized) {
          await controller.pause();
        }
      controller.dispose();
      } catch (e) {
        print('Error disposing video controller: $e');
      }
    }
    _videoControllers.clear();
    _videoInitialized.clear();
    
    // Inizializza solo i controller per i video VISIBILI nel tab corrente per risparmiare memoria
    List<Map<String, dynamic>> currentTabVideos;
    if (_tabController.index == 0) {
      currentTabVideos = _topLikedVideos;
    } else {
      currentTabVideos = _recentVideos;
    }
    final videosToInitialize = currentTabVideos.take(3).toList();
    
    // Fix iOS: inizializza i video uno alla volta con delay per evitare sovraccarico
    for (int i = 0; i < videosToInitialize.length; i++) {
      final video = videosToInitialize[i];
      await _initializeVideoController(video);
      
      // Fix iOS: piccolo delay tra inizializzazioni per evitare problemi di memoria
      if (i < videosToInitialize.length - 1) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }
  
      void _toggleVideoPlayback(VideoPlayerController controller, String videoId) {
      // Fix iOS: verifica che il controller sia ancora valido
      if (controller.value.hasError) {
        print('Cannot toggle playback - controller has error: ${controller.value.errorDescription}');
        return;
      }
      
      try {
      if (controller.value.isPlaying) {
        // Metti in pausa e mostra sempre l'icona di pausa
        controller.pause();
          if (mounted) {
        setState(() {
          _videoPlaying[videoId] = false;
          _showVideoControls[videoId] = true; // Mostra sempre i controlli quando in pausa
        });
          }
        // Cancella il timer di auto-hide quando in pausa
        _controlsHideTimers[videoId]?.cancel();
      } else {
          // Fix iOS: verifica che il video sia ancora inizializzato prima di riprodurre
          if (!controller.value.isInitialized) {
            print('Cannot play video - controller not initialized');
            return;
          }
          
        // Metti in play e nascondi i controlli
        controller.play();
          if (mounted) {
        setState(() {
          _videoPlaying[videoId] = true;
          _showVideoControls[videoId] = false; // Nascondi i controlli quando in play
        });
          }
        // Cancella il timer di auto-hide quando in play
        _controlsHideTimers[videoId]?.cancel();
        }
      } catch (e) {
        print('Error toggling video playback for $videoId: $e');
      }
    }
  
      // Start timer to hide controls automatically
    void _startControlsHideTimer(String videoId, bool autoHide) {
      _controlsHideTimers[videoId]?.cancel();
      if (autoHide) {
        _controlsHideTimers[videoId] = Timer(Duration(seconds: 3), () {
          if (mounted && (_videoPlaying[videoId] ?? false)) {
            setState(() {
              _showVideoControls[videoId] = false;
            });
          }
        });
      }
    }
    
        // Toggle controls visibility - ora gestito direttamente in _toggleVideoPlayback
      void _toggleControlsVisibility(String videoId) {
        // Questa funzione non è più necessaria con il nuovo comportamento
        // I controlli vengono gestiti direttamente in _toggleVideoPlayback
      }
    
    void _onVideoVisibilityChanged(String videoId, bool isVisible) {
      final controller = _videoControllers[videoId];
      if (controller != null && _videoInitialized[videoId] == true) {
        try {
          // Fix iOS: verifica che il controller sia ancora valido
          if (controller.value.hasError) {
            print('Video controller has error for $videoId: ${controller.value.errorDescription}');
            return;
          }
          
        if (isVisible) {
            // Avvia il video quando diventa visibile (solo se inizializzato correttamente)
            if (controller.value.isInitialized) {
          controller.play();
          // Precarica conteggio e stato visto per il video corrente
          final List<Map<String, dynamic>> merged = [
            ..._topLikedVideos,
            ..._recentVideos,
          ];
          final Map<String, dynamic>? video = merged.cast<Map<String, dynamic>?>().firstWhere(
            (v) => v != null && v['id'] == videoId,
            orElse: () => null,
          );
          if (video != null) {
            _loadCommentCount(video['id'], video['userId']);
            _checkVideoView(video);
              }
          }
        } else {
          // Pausa il video quando non è più visibile
            if (controller.value.isInitialized) {
          controller.pause();
          controller.seekTo(Duration.zero); // Torna all'inizio
            }
          }
        } catch (e) {
          print('Error in video visibility change for $videoId: $e');
        }
      }
    }
  
  // Gestione dell'interazione con la barra di progresso
  void _handleProgressBarTap(VideoPlayerController controller, TapDownDetails details) {
    // Usa la larghezza dello schermo per calcolare la percentuale
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.localPosition.dx;
    
    // Calcola la percentuale di progresso basata sulla posizione del tap
    final progress = (tapX / screenWidth).clamp(0.0, 1.0);
    
    print('Tap at $tapX / $screenWidth = $progress');
    
    // Calcola la nuova posizione del video
    final duration = controller.value.duration;
    if (duration.inMilliseconds > 0) {
      final newPosition = Duration(milliseconds: (duration.inMilliseconds * progress).round());
      print('Seeking to: ${newPosition.inMilliseconds}ms / ${duration.inMilliseconds}ms');
      controller.seekTo(newPosition);
    }
  }
  
  void _handleProgressBarDrag(VideoPlayerController controller, DragUpdateDetails details) {
    // Usa la larghezza dello schermo per calcolare la percentuale
    final screenWidth = MediaQuery.of(context).size.width;
    final dragX = details.localPosition.dx;
    
    // Calcola la percentuale di progresso basata sulla posizione del drag
    final progress = (dragX / screenWidth).clamp(0.0, 1.0);
    
    // Calcola la nuova posizione del video
    final duration = controller.value.duration;
    if (duration.inMilliseconds > 0) {
      final newPosition = Duration(milliseconds: (duration.inMilliseconds * progress).round());
      controller.seekTo(newPosition);
    }
  }
  
  void _startProgressBarInteraction(String videoId) {
    setState(() {
      _isProgressBarInteracting[videoId] = true;
    });
  }
  
  void _endProgressBarInteraction(String videoId) {
    setState(() {
      _isProgressBarInteracting[videoId] = false;
    });
  }
  
  void _onVerticalPageChanged(int newPageIndex) {
    setState(() {
      _currentVerticalPage = newPageIndex;
    });
    
    // Nascondi la sezione superiore quando si scorre verso il basso (se non è già nascosta)
    if (_isTopSectionVisible && newPageIndex > 0) {
      _hideTopSection();
    }
    
    // Mostra la sezione superiore quando si torna alla prima pagina
    if (!_isTopSectionVisible && newPageIndex == 0) {
      _showTopSection();
    }
    
    // Pausa tutti i video quando cambia pagina (fix iOS)
    _videoControllers.forEach((videoId, controller) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        controller.seekTo(Duration.zero);
        }
      } catch (e) {
        print('Error pausing video $videoId during page change: $e');
      }
    });
    
    // Avvia il video della pagina corrente dopo un breve delay
    Future.delayed(Duration(milliseconds: 300), () async {
      if (mounted && _currentVerticalPage == newPageIndex) {
        // Determina quale lista di video usare in base al tab corrente
        List<Map<String, dynamic>> currentVideos = [];
        if (_tabController.index == 0) {
          currentVideos = _topLikedVideos;
        } else if (_tabController.index == 1) {
          currentVideos = _recentVideos;
        }
        
        if (newPageIndex < currentVideos.length) {
          final currentVideo = currentVideos[newPageIndex];
          final videoId = currentVideo['id'] as String;
          final videoUserId = currentVideo['userId'] as String;
          final controller = _videoControllers[videoId];
          
          // Controlla se l'utente ha già visto il video controllando direttamente la cartella viewers
          final viewerSnapshot = await _database
              .child('users')
              .child('users')
              .child(videoUserId)
              .child('videos')
              .child(videoId)
              .child('viewers')
              .child(_currentUser!.uid)
              .get();
          
          // Salva la visualizzazione se l'utente non l'ha ancora vista
          if (!viewerSnapshot.exists) {
            _saveVideoView(videoId, videoUserId);
          }
          
                      if (controller != null && _videoInitialized[videoId] == true) {
              // Fix iOS: verifica che il controller sia ancora valido prima di riprodurre
              try {
                if (!controller.value.hasError && controller.value.isInitialized) {
                  await controller.play();
                  if (mounted) {
              setState(() {
                _videoPlaying[videoId] = true;
                _showVideoControls[videoId] = false; // Assicurati che i controlli siano nascosti quando in play
              });
            }
                } else {
                  print('Cannot play video $videoId - controller error or not initialized');
                }
              } catch (e) {
                print('Error playing video $videoId: $e');
              }
            }
        }
      }
    });
  }
  
  void _onTabChanged(int index) {
    // Disattiva la search bar se è attiva
    if (_searchController.text.isNotEmpty || _searchFocusNode.hasFocus) {
      _searchController.clear();
      _searchFocusNode.unfocus();
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
    
    // Resetta la pagina corrente quando cambia tab
    setState(() {
      _currentVerticalPage = 0;
    });
    
    // Pausa tutti i video (fix iOS)
    _videoControllers.forEach((videoId, controller) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        controller.seekTo(Duration.zero);
        }
      } catch (e) {
        print('Error pausing video $videoId during tab change: $e');
      }
    });
    
    // Vai alla prima pagina del nuovo tab
    _verticalPageController.animateToPage(
      0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    
    // Se passiamo al tab "Recent", aggiorna l'ordinamento per mostrare i non visti prima
    if (index == 1) {
      _updateVideosProgressively(_friendsVideos);
    }
  }
  
  void _hideTopSection() {
    if (_isTopSectionVisible) {
      setState(() {
        _isTopSectionVisible = false;
      });
      _topSectionAnimationController.forward(); // Va da 0.0 a 1.0 (nasconde)
    }
  }
  
  void _showTopSection() {
    if (!_isTopSectionVisible) {
      setState(() {
        _isTopSectionVisible = true;
      });
      _topSectionAnimationController.reverse(); // Va da 1.0 a 0.0 (mostra)
    }
  }
  
  void _toggleTopSection() {
    if (_isTopSectionVisible) {
      _hideTopSection();
    } else {
      _showTopSection();
    }
  }

  void _showVideoOptions(Map<String, dynamic> video) {
    final videoId = video['id'] as String;
    final userId = video['userId'] as String;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _getVideoTotals(videoId, userId),
          _loadVideoSocialAccounts(videoId, userId),
        ]).then((results) => {
          'totals': results[0] as Map<String, int>,
          'socialAccounts': results[1] as Map<String, List<Map<String, dynamic>>>,
        }),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Color(0xFF1E1E1E) 
                    : Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }
          
          final totals = snapshot.data!['totals'] as Map<String, int>;
          final socialAccounts = snapshot.data!['socialAccounts'] as Map<String, List<Map<String, dynamic>>>;
          
          return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
                Expanded(
                  child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Statistiche del video
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Totale Like
                          Column(
                            children: [
                                                             ShaderMask(
                                 shaderCallback: (Rect bounds) {
                                   return LinearGradient(
                                     colors: [
                                       Color(0xFF6C63FF),
                                       Color(0xFFFF6B6B),
                                     ],
                                     begin: Alignment.topLeft,
                                     end: Alignment.bottomRight,
                                   ).createShader(bounds);
                                 },
                                 child: Icon(
                                   Icons.favorite,
                                   color: Colors.white,
                                   size: 32,
                                 ),
                               ),
                              SizedBox(height: 8),
                              Text(
                                _formatNumber(totals['likes'] ?? 0),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white 
                                      : Colors.black87,
                                ),
                              ),
                              Text(
                                'Likes',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          
                          // Separatore verticale
                          Container(
                            width: 1,
                            height: 60,
                            color: Colors.grey[300],
                          ),
                          
                          // Totale Commenti
                          Column(
                            children: [
                              Icon(
                                Icons.comment,
                                color: Color(0xFF6C63FF),
                                size: 32,
                              ),
                              SizedBox(height: 8),
                              Text(
                                _formatNumber(totals['comments'] ?? 0),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white 
                                      : Colors.black87,
                                ),
                              ),
                              Text(
                                'Comments',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 20),
                      
                        // Sezione Social Media
                        if (socialAccounts.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.grey[850] 
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Open on Social',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white 
                                        : Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 12),
                                ...socialAccounts.entries.map((entry) {
                                  final platform = entry.key;
                                  final accounts = entry.value;
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header piattaforma
                                      Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: _getPlatformLightColor(platform),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Image.asset(
                                              _platformLogos[platform.toLowerCase()] ?? '',
                                              width: 16,
                                              height: 16,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            platform.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: _getPlatformColor(platform),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      // Lista account per questa piattaforma
                                      ...accounts.map((account) {
                                        final username = account['account_username']?.toString() ?? 
                                                       account['username']?.toString() ?? '';
                                        final displayName = account['account_display_name']?.toString() ?? 
                                                          account['display_name']?.toString() ?? username;
                                        final mediaId = account['media_id']?.toString();
                                        final postId = account['post_id']?.toString();
                                        final accountId = account['account_id']?.toString() ?? account['id']?.toString();
                                        
                                        return FutureBuilder<String?>(
                                          future: accountId != null ? _getSocialProfileImage(userId, platform, accountId) : Future.value(null),
                                          builder: (context, snapshot) {
                                            final profileImageUrl = snapshot.data;
                                            
                                            return Container(
                                          margin: EdgeInsets.only(bottom: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).brightness == Brightness.dark 
                                                ? Colors.grey[800] 
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.grey[300]!,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              // Immagine profilo dell'account social
                                              Container(
                                                width: 40,
                                                height: 40,
                                                margin: EdgeInsets.only(right: 12),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.grey[300]!,
                                                    width: 1,
                                                  ),
                                                ),
                                                child: ClipOval(
                                                  child: profileImageUrl != null && profileImageUrl.isNotEmpty
                                                      ? Image.network(
                                                          profileImageUrl,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return Container(
                                                              color: Colors.grey[200],
                                                              child: Icon(
                                                                Icons.person,
                                                                color: Colors.grey[600],
                                                                size: 20,
                                                              ),
                                                            );
                                                          },
                                                          loadingBuilder: (context, child, loadingProgress) {
                                                            if (loadingProgress == null) return child;
                                                            return Container(
                                                              color: Colors.grey[200],
                                                              child: Center(
                                                                child: CircularProgressIndicator(
                                                                  strokeWidth: 2,
                                                                  value: loadingProgress.expectedTotalBytes != null
                                                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                                      : null,
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : snapshot.connectionState == ConnectionState.waiting
                                                          ? Container(
                                                              color: Colors.grey[200],
                                                              child: Center(
                                                                child: CircularProgressIndicator(
                                                                  strokeWidth: 2,
                                                                ),
                                                              ),
                                                            )
                                                          : Container(
                                                              color: Colors.grey[200],
                                                              child: Icon(
                                                                Icons.person,
                                                                color: Colors.grey[600],
                                                                size: 20,
                                                              ),
                                                            ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      displayName,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w500,
                                                        color: Theme.of(context).brightness == Brightness.dark 
                                                            ? Colors.white 
                                                            : Colors.black87,
                                                      ),
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      platform.toLowerCase() == 'tiktok' ? username : '@$username',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              ElevatedButton.icon(
                                                                                              onPressed: () async {
                                                Navigator.pop(context);
                                                
                                                // Aggiungi i dati del video all'account
                                                final accountWithVideoData = Map<String, dynamic>.from(account);
                                                accountWithVideoData['video_id'] = videoId;
                                                accountWithVideoData['video_user_id'] = userId;
                                                
                                                if (platform.toLowerCase() == 'instagram') {
                                                  await _openInstagramPostOrProfile(accountWithVideoData);
                                                } else if (platform.toLowerCase() == 'threads') {
                                                  await _openThreadsPostOrProfile(accountWithVideoData);
                                                } else if (platform.toLowerCase() == 'facebook') {
                                                  await _openFacebookPostOrProfile(accountWithVideoData);
                                                } else if (platform.toLowerCase() == 'tiktok' && mediaId != null) {
                                                  _openTikTokWithMediaId(username, mediaId);
                                                } else {
                                                  // Per altre piattaforme, usa URL generici
                                                  String? postUrl;
                                                  if (platform.toLowerCase() == 'twitter' && postId != null) {
                                                    postUrl = 'https://twitter.com/i/status/$postId';
                                                  } else if (platform.toLowerCase() == 'youtube' && (postId != null || mediaId != null)) {
                                                    final videoId = postId ?? mediaId;
                                                    postUrl = 'https://www.youtube.com/watch?v=$videoId';
                                                  } else if (platform.toLowerCase() == 'facebook') {
                                                    postUrl = 'https://m.facebook.com/profile.php?id=$username';
                                                  } else if (platform.toLowerCase() == 'instagram') {
                                                    postUrl = 'https://www.instagram.com/$username/';
                                                  } else if (platform.toLowerCase() == 'tiktok') {
                                                    postUrl = 'https://www.tiktok.com/@$username';
                                                  } else if (platform.toLowerCase() == 'threads') {
                                                    postUrl = 'https://threads.net/@$username';
                                                  }
                                                  
                                                  if (postUrl != null) {
                                                    _openSocialMedia(postUrl);
                                                  }
                                                }
                                              },
                                                icon: Icon(Icons.open_in_new, size: 16),
                                                label: Text('Open'),
                                                style: ElevatedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  backgroundColor: _getPlatformColor(platform),
                                                  elevation: 0,
                                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                          },
                                        );
                                      }).toList(),
                                      SizedBox(height: 12),
                                    ],
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Pulsante chiudi (fisso in basso)
                Padding(
                  padding: EdgeInsets.all(20),
                  child: SizedBox(
                        width: double.infinity,
                        child: Container(
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Close'),
                          ),
                        ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, int>> _getVideoTotals(String videoId, String userId) async {
    try {
      // Percorso per recuperare i totali del video
      final videoSnapshot = await _database
          .child('users')
          .child('users')
          .child(userId)
          .child('videos')
          .child(videoId)
          .get();

      if (videoSnapshot.exists) {
        final videoData = videoSnapshot.value as Map<dynamic, dynamic>;
        final video = Map<String, dynamic>.from(videoData);
        
        // Estrai i totali, con fallback a 0 se non presenti
        final totalLikes = video['total_likes'] ?? 0;
        final totalComments = video['total_comments'] ?? 0;
        
        return {
          'likes': totalLikes is int ? totalLikes : int.tryParse(totalLikes.toString()) ?? 0,
          'comments': totalComments is int ? totalComments : int.tryParse(totalComments.toString()) ?? 0,
        };
      }
      
      return {'likes': 0, 'comments': 0};
    } catch (e) {
      print('Errore nel recupero dei totali del video: $e');
      return {'likes': 0, 'comments': 0};
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Cerca tutti gli utenti nel database
      final usersSnapshot = await _database
          .child('users')
          .child('users')
          .get();

      if (usersSnapshot.exists) {
        final users = usersSnapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> results = [];

        // Itera su tutti gli utenti
        users.forEach((userId, userData) async {
          if (userData is Map) {
            final user = Map<String, dynamic>.from(userData);
            
            // Cerca il displayName nella cartella profile
            String? displayName;
            String? username;
            String? profileImageUrl;
            
            if (user['profile'] != null) {
              final profile = user['profile'] as Map<dynamic, dynamic>;
              displayName = profile['displayName']?.toString();
              username = profile['username']?.toString();
              profileImageUrl = profile['profileImageUrl']?.toString();
            }
            
            // Fallback ai dati principali se non trovato in profile
            displayName ??= user['displayName']?.toString();
            username ??= user['username']?.toString();
            profileImageUrl ??= user['profileImageUrl']?.toString();
            
            // Controlla se il displayName contiene la query (case insensitive) e non è l'utente corrente
            if (displayName != null && 
                displayName.toLowerCase().contains(query.toLowerCase()) &&
                userId != _currentUser?.uid) {
              results.add({
                'userId': userId,
                'displayName': displayName,
                'username': username ?? '',
                'profileImageUrl': profileImageUrl ?? 'https://via.placeholder.com/100',
              });
              
              // Controlla se sono già amici
              _checkFriendshipStatus(userId);
            }
          }
        });
      
      setState(() {
          _searchResults = results;
        _isSearching = false;
      });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Error searching users: $e');
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  void _navigateToUserProfile(String userId) {
    _hasNavigatedAway = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileEditPage(userId: userId),
      ),
    );
  }

  Future<void> _checkFriendshipStatus(String targetUserId) async {
    if (_currentUser == null) return;

    try {
      print('Checking friendship status for user: $targetUserId');
      
      // Controlla se sono già amici
      final alreadyFriendsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('alreadyfriends')
          .child(targetUserId)
          .get();

      final isFriend = alreadyFriendsSnapshot.exists == true;
      print('Friendship status for $targetUserId: $isFriend');

      // Controlla se c'è una richiesta pendente dal punto di vista dell'utente nel container
      final pendingRequestSnapshot = await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .child('friends')
          .child(_currentUser!.uid)
          .get();

      bool hasPendingRequest = false;
      if (pendingRequestSnapshot.exists) {
        final requestData = pendingRequestSnapshot.value as Map<dynamic, dynamic>;
        final status = requestData['status']?.toString();
        hasPendingRequest = status == 'pending';
      }

      // Controlla se l'utente nel container ha inviato una richiesta all'utente corrente
      final receivedRequestSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('friends')
          .child(targetUserId)
          .get();

      bool hasReceivedRequest = false;
      if (receivedRequestSnapshot.exists) {
        final requestData = receivedRequestSnapshot.value as Map<dynamic, dynamic>;
        final status = requestData['status']?.toString();
        hasReceivedRequest = status == 'pending';
      }

      print('Pending request status for $targetUserId: $hasPendingRequest');
      print('Received request status from $targetUserId: $hasReceivedRequest');

      if (mounted) {
        setState(() {
          _friendshipStatus[targetUserId] = isFriend;
          _pendingRequests[targetUserId] = hasPendingRequest;
          _receivedRequests[targetUserId] = hasReceivedRequest;
        });
      }
    } catch (e) {
      print('Error checking friendship status: $e');
      if (mounted) {
        setState(() {
          _friendshipStatus[targetUserId] = false;
          _pendingRequests[targetUserId] = false;
        });
      }
    }
  }

  Future<void> _sendOneSignalNotification(String targetUserId, String fromDisplayName) async {
    try {
      // Configurazione OneSignal
      const String oneSignalAppId = '8ad10111-3d90-4ec2-a96d-28f6220ab3a0';
      const String oneSignalApiUrl = 'https://api.onesignal.com/notifications';
      
      // Ottieni il OneSignal Player ID dell'utente target
      final targetUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('onesignal_player_id')
          .get();

      if (!targetUserSnapshot.exists) {
        print('OneSignal Player ID not found for user: $targetUserId');
        return;
      }

      final String playerId = targetUserSnapshot.value.toString();
      
      // Prepara il contenuto della notifica
      const String title = '👋 New Friend Request!';
      final String content = '$fromDisplayName wants to be your friend';
      const String clickUrl = 'https://fluzar.com/deep-redirect';
      const String largeIcon = 'https://img.onesignal.com/tmp/a74d2f7f-f359-4df4-b7ed-811437987e91/oxcPer7LSBS4aCGcVMi3_120x120%20app%20logo%20grande%20con%20sfondo%20bianco.png?_gl=1*1x2tx4r*_gcl_au*NjI1OTE1MTUyLjE3NTI0Mzk0Nzc.*_ga*MTYzNjE2MzA0MC4xNzUyNDM5NDc4*_ga_Z6LSTXWLPN*czE3NTI0NTEwMDkkbzMkZzAkdDE3NTI0NTEwMDkkajYwJGwwJGgyOTMzMzMxODk';

      // Prepara il payload per OneSignal
      final Map<String, dynamic> payload = {
        'app_id': oneSignalAppId,
        'include_player_ids': [playerId],
        'channel_for_external_user_ids': "push",
        'headings': {
          'en': title
        },
        'contents': {
          'en': content
        },
        'url': clickUrl,
        'chrome_web_icon': largeIcon,
        'data': {
          'type': 'friend_request',
          'from_user_id': _currentUser!.uid,
          'from_display_name': fromDisplayName,
          'target_user_id': targetUserId
        }
      };

      print('Sending OneSignal notification for friend request: target_user_id=$targetUserId, player_id=$playerId, title=$title, content=$content');

      // Invia la notifica tramite HTTP request
      final response = await http.post(
        Uri.parse(oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic NGEwMGZmMDItY2RkNy00ZDc3LWI0NzEtZGYzM2FhZWU1OGUz', // OneSignal REST API Key
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('OneSignal notification sent successfully: ${result['id']}');
      } else {
        print('OneSignal API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error sending OneSignal notification: $e');
    }
  }

  Future<void> _sendCommentNotification(String videoUserId, String commenterName, Map<String, dynamic> video) async {
    try {
      // Configurazione OneSignal
      const String oneSignalAppId = '8ad10111-3d90-4ec2-a96d-28f6220ab3a0';
      const String oneSignalApiUrl = 'https://api.onesignal.com/notifications';
      
      // Ottieni il OneSignal Player ID dell'utente proprietario del video
      final targetUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('onesignal_player_id')
          .get();

      if (!targetUserSnapshot.exists) {
        print('OneSignal Player ID not found for video owner: $videoUserId');
        return;
      }

      final String playerId = targetUserSnapshot.value.toString();
      
      // Prepara il contenuto della notifica
      const String title = '💬 New Comment!';
      final String content = '$commenterName commented on your video';
      const String clickUrl = 'https://fluzar.com/deep-redirect';
      const String largeIcon = 'https://img.onesignal.com/tmp/a74d2f7f-f359-4df4-b7ed-811437987e91/oxcPer7LSBS4aCGcVMi3_120x120%20app%20logo%20grande%20con%20sfondo%20bianco.png?_gl=1*1x2tx4r*_gcl_au*NjI1OTE1MTUyLjE3NTI0Mzk0Nzc.*_ga*MTY2MzE2MzA0MC4xNzUyNDM5NDc4*_ga_Z6LSTXWLPN*czE3NTI0NTEwMDkkbzMkZzAkdDE3NTI0NTEwMDkkajYwJGwwJGgyOTMzMzMxODk';

      // Prepara il payload per OneSignal
      final Map<String, dynamic> payload = {
        'app_id': oneSignalAppId,
        'include_player_ids': [playerId],
        'channel_for_external_user_ids': "push",
        'headings': {
          'en': title
        },
        'contents': {
          'en': content
        },
        'url': clickUrl,
        'chrome_web_icon': largeIcon,
        'data': {
          'type': 'video_comment',
          'from_user_id': _currentUser!.uid,
          'from_display_name': commenterName,
          'video_id': video['id'],
          'video_title': video['title'] ?? 'Your video'
        }
      };

      print('Sending OneSignal notification for video comment: video_owner_id=$videoUserId, player_id=$playerId, title=$title, content=$content');

      // Invia la notifica tramite HTTP request
      final response = await http.post(
        Uri.parse(oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic NGEwMGZmMDItY2RkNy00ZDc3LWI0NzEtZGYzM2FhZWU1OGUz', // OneSignal REST API Key
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('OneSignal comment notification sent successfully: ${result['id']}');
      } else {
        print('OneSignal API error for comment notification: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error sending OneSignal comment notification: $e');
    }
  }

  Future<void> _acceptFriendRequest(String targetUserId) async {
    if (_currentUser == null) return;

    try {
      setState(() {
        _isSearching = true;
      });

      // Carica i dati dell'utente target per ottenere il displayName
      final targetUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .get();
      
      String targetDisplayName = 'Unknown User';
      String targetUsername = 'unknown';
      String targetProfileImageUrl = '';
      
      if (targetUserSnapshot.exists) {
        final targetUserData = targetUserSnapshot.value as Map<dynamic, dynamic>;
        targetDisplayName = targetUserData['displayName'] ?? 'Unknown User';
        targetUsername = targetUserData['username'] ?? 'unknown';
        targetProfileImageUrl = targetUserData['profileImageUrl'] ?? '';
      }

      // Crea l'oggetto amico per il proprietario del profilo
      final friendForOwner = {
        'uid': targetUserId,
        'displayName': targetDisplayName,
        'username': targetUsername,
        'profileImageUrl': targetProfileImageUrl,
        'friendshipDate': DateTime.now().millisecondsSinceEpoch,
      };

      // Crea l'oggetto amico per l'utente che ha inviato la richiesta
      final friendForRequester = {
        'uid': _currentUser!.uid,
        'displayName': _currentUser!.displayName ?? 'Unknown User',
        'username': _currentUser!.email?.split('@')[0] ?? 'unknown',
        'profileImageUrl': _currentUser!.photoURL ?? '',
        'friendshipDate': DateTime.now().millisecondsSinceEpoch,
      };

      // Salva l'amico nella cartella alreadyfriends del proprietario del profilo
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('alreadyfriends')
          .child(targetUserId)
          .set(friendForOwner);

      // Salva l'amico nella cartella alreadyfriends dell'utente che ha inviato la richiesta
      await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .child('alreadyfriends')
          .child(_currentUser!.uid)
          .set(friendForRequester);

      // Rimuovi la richiesta dalla cartella friends (perché ora sono amici)
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('friends')
          .child(targetUserId)
          .remove();

      // Rimuovi anche la richiesta dalla cartella friends dell'altro utente se esiste
      await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .child('friends')
          .child(_currentUser!.uid)
          .remove();

      // Invia notifica push OneSignal
      await _sendOneSignalNotification(targetUserId, _currentUser!.displayName ?? 'Unknown User');

      // Mostra messaggio di successo
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Friend request accepted!', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }

      // Aggiorna lo stato
      setState(() {
        _friendshipStatus[targetUserId] = true;
        _receivedRequests[targetUserId] = false;
        _pendingRequests[targetUserId] = false;
      });

      // Ricarica i risultati per aggiornare lo stato
      if (_searchController.text.isNotEmpty) {
        _searchUsers(_searchController.text);
      }

    } catch (e) {
      print('Error accepting friend request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Error accepting friend request', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _sendFriendRequest(String targetUserId) async {
    if (_currentUser == null) return;

    try {
      setState(() {
        _isSearching = true;
      });

      // Controlla se sono già amici
      final alreadyFriendsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('alreadyfriends')
          .child(targetUserId)
          .get();

      if (alreadyFriendsSnapshot.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[700], size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('You are already friends with this user!', style: TextStyle(color: Colors.black))),
                ],
              ),
              backgroundColor: Colors.white,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: EdgeInsets.all(16),
            ),
          );
        }
        return;
      }



      // Controlla se c'è già una richiesta pendente
      final pendingRequestsSnapshot = await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .child('friends')
          .get();

      if (pendingRequestsSnapshot.exists) {
        final pendingRequests = pendingRequestsSnapshot.value as Map<dynamic, dynamic>;
        bool hasPendingRequest = false;
        
        pendingRequests.forEach((requestId, requestData) {
          if (requestData is Map) {
            final request = Map<String, dynamic>.from(requestData);
            if (request['fromUserId'] == _currentUser!.uid && request['status'] == 'pending') {
              hasPendingRequest = true;
            }
          }
        });

        if (hasPendingRequest) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.grey[700], size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('You have already sent a friend request to this user!', style: TextStyle(color: Colors.black))),
                  ],
                ),
                backgroundColor: Colors.white,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: EdgeInsets.all(16),
              ),
            );
          }
          return;
        }
      }

      // Carica i dati dell'utente target per ottenere il displayName
      final targetUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .get();
      
      String targetDisplayName = 'Unknown User';
      if (targetUserSnapshot.exists) {
        final targetUserData = targetUserSnapshot.value as Map<dynamic, dynamic>;
        targetDisplayName = targetUserData['displayName'] ?? 'Unknown User';
      }

      // Crea la richiesta di amicizia
      final friendRequest = {
        'fromUserId': _currentUser!.uid,
        'fromDisplayName': _currentUser!.displayName ?? 'Unknown User',
        'fromUsername': _currentUser!.email?.split('@')[0] ?? 'unknown',
        'fromProfileImageUrl': _currentUser!.photoURL ?? '',
        'status': 'pending',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Salva la richiesta nel database del target user usando solo l'ID dell'utente corrente come chiave
      await _database
          .child('users')
          .child('users')
          .child(targetUserId)
          .child('profile')
          .child('friends')
          .child(_currentUser!.uid)
          .set(friendRequest);

      // Invia notifica push OneSignal all'utente target
      await _sendOneSignalNotification(targetUserId, friendRequest['fromDisplayName'].toString());

      // Mostra messaggio di successo
              if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                    children: [
                  Icon(Icons.check_circle, color: Colors.grey[700], size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('Friend request sent!', style: TextStyle(color: Colors.black))),
                ],
              ),
              backgroundColor: Colors.white,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: EdgeInsets.all(16),
            ),
    );
  }

      // Aggiorna lo stato per questo utente
      setState(() {
        _pendingRequests[targetUserId] = true;
        _receivedRequests[targetUserId] = false; // Reset received request status
      });
      
      // Ricarica i risultati per aggiornare lo stato
      if (_searchController.text.isNotEmpty) {
        _searchUsers(_searchController.text);
      }
    } catch (e) {
      print('Error sending friend request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                                  Expanded(child: Text('Error sending friend request', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _setupNotificationsListener() {
    if (_currentUser != null) {
      final ref = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('notifications');
      _notificationsStream = ref.onValue;
      _notificationsStream!.listen((event) {
        int count = 0;
        if (event.snapshot.value != null && event.snapshot.value is Map) {
          final data = event.snapshot.value as Map;
          for (final n in data.values) {
            if (n is Map && (n['read'] == null || n['read'] == false)) {
              count++;
            }
          }
        }
        setState(() {
          _unreadNotifications = count;
        });
      });
      
      // Listener per l'immagine profilo
      final profileRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('profileImageUrl');
      profileRef.onValue.listen((event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          setState(() {
            _profileImageUrl = event.snapshot.value.toString();
          });
        } else {
          setState(() {
            _profileImageUrl = null;
          });
        }
      });
    }
  }

  Future<void> _loadProfileImage() async {
    if (_currentUser == null) return;
    
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('profileImageUrl')
          .get();
      
      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _profileImageUrl = snapshot.value.toString();
        });
      }
    } catch (e) {
      print('Error loading profile image: $e');
    }
  }

  // Carica l'immagine profilo dell'utente da Firebase
  Future<String?> _loadUserProfileImage(String userId) async {
    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(userId)
          .child('profile')
          .child('profileImageUrl')
          .get();
      
      if (snapshot.exists && snapshot.value is String) {
        return snapshot.value as String;
      }
      return null;
    } catch (e) {
      print('Error loading user profile image for $userId: $e');
      return null;
    }
  }

  // Carica il nome utente dal profilo
  Future<String?> _loadUserName(String userId) async {
    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(userId)
          .child('profile')
          .child('username')
          .get();
      
      if (snapshot.exists && snapshot.value is String) {
        return snapshot.value as String;
      }
      return null;
    } catch (e) {
      print('Error loading username for $userId: $e');
      return null;
    }
  }

  Future<void> _loadFriendsRanking() async {
    if (_currentUser == null) return;
    
    setState(() {
      _isLoadingRanking = true;
    });
    
    try {
      print('Loading friends ranking...');
      
      // Se non abbiamo ancora caricato gli amici, caricali prima
      if (_friendIds.isEmpty) {
        await _loadFriendsIds();
      }
      
      if (_friendIds.isEmpty) {
        print('No friends found for ranking');
        setState(() {
          _friendsRanking = [];
          _isLoadingRanking = false;
        });
        return;
      }
      
      List<Map<String, dynamic>> rankingData = [];
      
      // Carica i dati di ogni amico
      for (String friendId in _friendIds) {
        try {
          final friendSnapshot = await _database
              .child('users')
              .child('users')
              .child(friendId)
              .child('profile')
              .get();
          
          if (friendSnapshot.exists && friendSnapshot.value is Map) {
            final friendData = Map<String, dynamic>.from(friendSnapshot.value as Map);
            
            // Estrai i dati necessari
            final viralystScore = friendData['viralystScore'] as int? ?? 0;
            final username = friendData['username'] as String? ?? 'Unknown User';
            final profileImageUrl = friendData['profileImageUrl'] as String?;
            final bio = friendData['bio'] as String? ?? '';
            
            rankingData.add({
              'uid': friendId,
              'username': username,
              'viralystScore': viralystScore,
              'profileImageUrl': profileImageUrl,
              'bio': bio,
            });
            
            print('Loaded friend $username with score: $viralystScore');
          }
        } catch (e) {
          print('Error loading friend $friendId data: $e');
          // Aggiungi comunque l'amico con score 0 se non riusciamo a caricare i dati
          rankingData.add({
            'uid': friendId,
            'username': 'Unknown User',
            'viralystScore': 0,
            'profileImageUrl': null,
            'bio': '',
          });
        }
      }
      
      // Ordina per viralystScore decrescente
      rankingData.sort((a, b) => (b['viralystScore'] as int).compareTo(a['viralystScore'] as int));
      
      setState(() {
        _friendsRanking = rankingData;
        _isLoadingRanking = false;
      });
      
      // Carica lo stato online degli amici dopo aver caricato la classifica
      _loadFriendsOnlineStatus();
      
      print('Friends ranking loaded: ${rankingData.length} friends');
      
    } catch (e) {
      print('Error loading friends ranking: $e');
      setState(() {
        _friendsRanking = [];
        _isLoadingRanking = false;
      });
    }
  }

  void _setupOnlineStatus() {
    if (_currentUser == null) return;
    
    // Monitora lo stato di connessione del client corrente
    final connectedRef = _database.child('.info/connected');
    connectedRef.onValue.listen((snapshot) {
      if (snapshot.snapshot.value == true) {
        // Client è connesso, imposta lo stato online
        final userStatusRef = _database.child('status').child(_currentUser!.uid);
        userStatusRef.set({
          'online': true,
          'last_active': ServerValue.timestamp,
        });
        
        // Imposta lo stato offline quando il client si disconnette
        userStatusRef.onDisconnect().set({
          'online': false,
          'last_active': ServerValue.timestamp,
        });
        
        print('User ${_currentUser!.uid} is now online');
      } else {
        print('User ${_currentUser!.uid} is offline');
      }
    });
  }

  void _loadFriendsOnlineStatus() {
    if (_friendIds.isEmpty) return;
    
    // Cancella sottoscrizioni precedenti per evitare leak
    for (final sub in _friendStatusSubscriptions) {
      sub.cancel();
    }
    _friendStatusSubscriptions.clear();
    
    // Monitora lo stato online di tutti gli amici
    for (String friendId in _friendIds) {
      final statusRef = _database.child('status').child(friendId);
      final sub = statusRef.onValue.listen((snapshot) {
        if (snapshot.snapshot.exists && snapshot.snapshot.value is Map) {
          final statusData = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
          final isOnline = statusData['online'] as bool? ?? false;
          
          if (mounted) {
            setState(() {
              _onlineStatus[friendId] = isOnline;
            });
          }
          
          print('Friend $friendId online status: $isOnline');
        } else {
          if (mounted) {
            setState(() {
              _onlineStatus[friendId] = false;
            });
          }
        }
      });
      _friendStatusSubscriptions.add(sub);
    }
  }

  // Carica il referral code dell'utente (stesso path di referral_code_page.dart)
  Future<void> _loadReferralCode() async {
    if (_currentUser == null) return;
    
    try {
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
      
      final snapshot = await userRef.get();
      
      if (snapshot.exists && snapshot.value is Map) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        
        // Get referral code (stesso metodo di referral_code_page.dart)
        if (userData.containsKey('referral_code')) {
          setState(() {
            _referralCode = userData['referral_code'] as String?;
          });
        }
      }
    } catch (e) {
      print('Error loading referral code: $e');
    }
  }

  // Carica le visualizzazioni dei video per l'utente corrente controllando direttamente la cartella viewers
  Future<void> _loadVideoViews() async {
    // Mantieni compatibilità chiamando il loader limitato ai video mostrati
    await _loadCountsAndViewsForDisplayedVideos();
  }

  // Carica conteggi commenti e stato "visto" SOLO per i video mostrati nei tab
  Future<void> _loadCountsAndViewsForDisplayedVideos() async {
    if (_currentUser == null) return;
    try {
      final Set<String> seenIds = {};
      final List<Map<String, dynamic>> subset = [];
      for (final v in _topLikedVideos.take(3)) {
        final id = v['id']?.toString();
        if (id != null && seenIds.add(id)) subset.add(v);
      }
      for (final v in _recentVideos.take(3)) {
        final id = v['id']?.toString();
        if (id != null && seenIds.add(id)) subset.add(v);
      }
      List<Future<void>> futures = [];
      for (final video in subset) {
        futures.add(_checkVideoView(video));
        futures.add(_loadCommentCount(video['id'], video['userId']));
      }
      await Future.wait(futures);
      print('Loaded counts/views for displayed videos: ${subset.length}');
    } catch (e) {
      print('Error loading counts/views for displayed videos: $e');
    }
  }

  // Metodo helper per controllare se un singolo video è stato visto
  Future<void> _checkVideoView(Map<String, dynamic> video) async {
    if (_currentUser == null) return;
    
    final videoId = video['id'] as String;
    final videoUserId = video['userId'] as String;
    
    try {
      // Controlla se l'utente corrente è presente nella cartella viewers del video
      final viewerSnapshot = await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('viewers')
          .child(_currentUser!.uid)
          .get();
      
      _hasUserViewedVideo[videoId] = viewerSnapshot.exists;
    } catch (e) {
      print('Error checking view for video $videoId: $e');
      _hasUserViewedVideo[videoId] = false;
    }
  }

  // Salva una visualizzazione di un video
  Future<void> _saveVideoView(String videoId, String videoUserId) async {
    if (_currentUser == null) return;
    
    try {
      // Salva la visualizzazione nella cartella dell'utente corrente
      final userViewRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('video_views')
          .child(videoId);
      
      await userViewRef.set({
        'videoId': videoId,
        'videoUserId': videoUserId,
        'viewedAt': ServerValue.timestamp,
        'viewerId': _currentUser!.uid,
      });
      
      // Salva anche nella cartella del video per tracciare tutti i visualizzatori
      final videoViewRef = _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('viewers')
          .child(_currentUser!.uid);
      
      await videoViewRef.set({
        'viewerId': _currentUser!.uid,
        'viewerDisplayName': _currentUser!.displayName ?? 'Anonymous',
        'viewedAt': ServerValue.timestamp,
      });
      
      // Aggiorna lo stato locale
      setState(() {
        _hasUserViewedVideo[videoId] = true;
      });
      
      // Aggiorna l'ordinamento per riflettere il nuovo stato
      _updateVideosProgressively(_friendsVideos);
      
      print('Video view saved for video $videoId by user ${_currentUser!.uid}');
    } catch (e) {
      print('Error saving video view: $e');
    }
  }

  // Condividi l'invito per amici esterni all'app (prende sempre il referral code live da Firebase)
  Future<void> _shareInviteToFriends() async {
    if (_currentUser == null) return;
    try {
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
      final snapshot = await userRef.get();
      String? referralCode;
      if (snapshot.exists && snapshot.value is Map) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        if (userData.containsKey('referral_code')) {
          referralCode = userData['referral_code'] as String?;
        }
      }
      if (referralCode == null || referralCode.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Referral code not available. Try again later.'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
              final String message = 'Hey! Join me on Fluzar and get 500 bonus credits! Use my referral code: $referralCode. Download it now: https://fluzar.com';
      await Share.share(
        message,
                  subject: 'Join Fluzar - Social Media Management Made Easy With AI',
      );
    } catch (e) {
      print('Error sharing invite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing referral code'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark 
          ? Color(0xFF121212) 
          : Colors.white,
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
      child: SafeArea(
              child: Stack(
            children: [
                  // Header con logo e pulsanti (sempre visibile)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildHeader(context),
                  ),
                  
                  // Sezione superiore animata (barra di ricerca e tab bar)
                  Positioned(
                    top: 80, // Posizione sotto l'header
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                    animation: _topSectionAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -_topSectionAnimation.value * 200), // Nasconde verso l'alto
                        child: Opacity(
                          opacity: 1.0 - _topSectionAnimation.value,
                          child: Column(
                            children: [
                  // Search bar with glass effect
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            onChanged: (value) {
                              _searchUsers(value);
                            },
                            decoration: InputDecoration(
                              hintText: 'Make friends...',
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
                              suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    iconSize: 16,
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchResults = [];
                                        _isSearching = false;
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
                  
                  const SizedBox(height: 12),
                  
                  // Tab bar with glass effect
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
                              indicatorColor: Colors.white, // Indicatore bianco per il tab selezionato
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
                                                  Icons.trending_up, 
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
                                                    Icons.trending_up, 
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? Text('Top Likes', style: TextStyle(color: Colors.white))
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
                                                  child: Text('Top Likes', style: TextStyle(color: Colors.white)),
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
                                                  Icons.schedule, 
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
                                                    Icons.schedule, 
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? Text('Recent', style: TextStyle(color: Colors.white))
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
                                                  child: Text('Recent', style: TextStyle(color: Colors.white)),
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
                                                  Icons.leaderboard, 
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
                                                    Icons.leaderboard, 
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          const SizedBox(width: 4),
                                          isSelected
                                              ? Text('Ranking', style: TextStyle(color: Colors.white))
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
                                                  child: Text('Ranking', style: TextStyle(color: Colors.white)),
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
                  
                                 // Rimosso lo spazio extra
                            ],
                          ),
                        ),
                      );
                    },
                     ),
                   ),
                  
                  // Contenuto principale con TabBarView - ora si espande per riempire tutto lo schermo
                  Positioned(
                    top: 0, // Inizia dall'alto per riempire tutto lo schermo
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedBuilder(
                      animation: _topSectionAnimation,
                      builder: (context, child) {
                        // Calcola l'altezza del contenuto in base alla visibilità della sezione superiore
                        final topSectionHeight = 140.0; // Altezza ulteriormente ridotta della sezione superiore
                        final headerHeight = 80.0; // Altezza dell'header
                        
                        // Quando la sezione superiore è nascosta, il contenuto si espande per riempire tutto
                        final contentTop = _topSectionAnimation.value > 0.5 
                            ? headerHeight 
                            : headerHeight + topSectionHeight;
                        
                        return Container(
                          margin: EdgeInsets.only(top: contentTop),
                    child: (_searchFocusNode.hasFocus || _searchController.text.isNotEmpty)
                        ? _buildSearchResults(theme)
                        : _isLoading || _isLoadingFriendsVideos
                            ? Column(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _isLoading ? 'Loading feed...' : 'Loading friends videos...',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: 200,
                                    child: Center(
                                      child: Lottie.asset(
                                        'assets/animations/MainScene.json',
                                        width: 180,
                                        height: 100,
                                        fit: BoxFit.contain,
                                        repeat: true,
                                        animate: true,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : TabBarView(
                                controller: _tabController,
                                physics: NeverScrollableScrollPhysics(), // Disabilita lo scroll orizzontale automatico
                                children: [
                                  _buildTopLikedSection(theme),
                                  _buildRecentSection(theme),
                                  _buildExploreSection(theme),
                                ],
                                    ),
                        );
                      },
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
                    onPressed: () {
                      _hasNavigatedAway = true;
                      Navigator.pop(context);
                    },
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
              
              // Freccia e icona profilo a destra
              Row(
                children: [
                  // Freccia per mostrare/nascondere la sezione superiore
                  if (!_isTopSectionVisible)
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 28,
                      ),
                      onPressed: _showTopSection,
                    ),
                  // Icona profilo a destra
                  IconButton(
                    icon: _profileImageUrl != null
                        ? Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: ClipOval(
                              child: Image.network(
                                _profileImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildDefaultProfileImage(theme);
                                },
                              ),
                            ),
                          )
                        : _buildDefaultProfileImage(theme),
                    onPressed: () {
                      _hasNavigatedAway = true;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileEditPage(),
                        ),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultProfileImage(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C63FF),
            const Color(0xFF8B7CF6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.person,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    return _isSearching
        ? Column(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    'Searching...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              Container(
                height: 200,
                child: Center(
                  child: Lottie.asset(
                    'assets/animations/MainScene.json',
                    width: 180,
                    height: 100,
                    fit: BoxFit.contain,
                    repeat: true,
                    animate: true,
                  ),
                ),
              ),
            ],
          )
        : ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _searchResults.length + 1, // +1 per la card di invito
            itemBuilder: (context, index) {
              if (index == 0) {
                // Prima card sempre per invitare amici esterni
                return _buildInviteFriendsCard(theme);
              }
              final user = _searchResults[index - 1];
              return _buildUserCard(theme, user);
            },
          );
  }

  Widget _buildInviteFriendsCard(ThemeData theme) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
            Color(0xFF764ba2), // Colore finale: viola al 100%
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF667eea).withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Naviga alla pagina referral code
            _hasNavigatedAway = true;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ReferralCodePage(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(12), // Ridotto il padding per renderla più piccola
            child: Row(
              children: [
                // Icona invito
                Container(
                  width: 50, // Ridotto da 60 a 50
                  height: 50, // Ridotto da 60 a 50
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.person_add_alt_1,
                    color: Colors.white,
                    size: 24, // Ridotto da 30 a 24
                  ),
                ),
                
                SizedBox(width: 12), // Ridotto da 16 a 12
                
                // Informazioni invito
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invite Friends',
                        style: TextStyle(
                          fontSize: 16, // Ridotto da 18 a 16
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2), // Ridotto da 4 a 2
                      Text(
                        'Share Fluzar with friends outside the app',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13, // Ridotto da 14 a 13
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Pulsante share
                GestureDetector(
                  onTap: () {
                    _shareInviteToFriends();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Ridotto il padding
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.share,
                          color: Colors.white,
                          size: 14, // Ridotto da 16 a 14
                        ),
                        SizedBox(width: 4), // Ridotto da 6 a 4
                        Text(
                          'Share',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11, // Ridotto da 12 a 11
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

  Widget _buildUserCard(ThemeData theme, Map<String, dynamic> user) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
          borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _navigateToUserProfile(user['userId']),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
            children: [
                // Immagine profilo
              Container(
                  width: 60,
                  height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Color(0xFF6C63FF).withOpacity(0.2),
                    width: 2,
                  ),
                ),
                  child: ClipOval(
                    child: Image.network(
                      user['profileImageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                  decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFF8B7CF6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 30,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                SizedBox(width: 16),
                
                // Informazioni utente
                Expanded(
                  child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                        user['displayName'],
                style: TextStyle(
                          fontSize: 18,
                            fontWeight: FontWeight.bold,
                          color: theme.textTheme.titleLarge?.color,
                        ),
                      ),
                      SizedBox(height: 4),
                        Text(
                        '@${user['username']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                          fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                                // Icona invio richiesta di amicizia
                GestureDetector(
                  onTap: () {
                    if (_friendshipStatus[user['userId']] == true) {
                      // Già amici, non fare nulla
                      return;
                    } else if (_pendingRequests[user['userId']] == true) {
                      // Richiesta già inviata, non fare nulla
                      return;
                    } else if (_receivedRequests[user['userId']] == true) {
                      // Richiesta ricevuta, accetta
                      _acceptFriendRequest(user['userId']);
                    } else {
                      // Invia richiesta di amicizia
                      _sendFriendRequest(user['userId']);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _friendshipStatus[user['userId']] == true 
                          ? null
                          : _pendingRequests[user['userId']] == true
                              ? null
                              : _receivedRequests[user['userId']] == true
                                  ? null
                                  : LinearGradient(
                                      colors: [
                                        Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                        Color(0xFF764ba2), // Colore finale: viola al 100%
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                                    ),
                      color: _friendshipStatus[user['userId']] == true 
                          ? Colors.grey[300] 
                          : _pendingRequests[user['userId']] == true
                              ? Colors.orange[300]
                              : _receivedRequests[user['userId']] == true
                                  ? Colors.blue[300]
                                  : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                        _friendshipStatus[user['userId']] == true 
                          ? 'Friends'
                            : _pendingRequests[user['userId']] == true
                              ? 'Pending'
                                : _receivedRequests[user['userId']] == true
                                  ? 'Accept'
                                  : 'Add Friend',
                      style: TextStyle(
                        color: _friendshipStatus[user['userId']] == true 
                            ? Colors.grey[600] 
                                    : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                
                // Icona freccia per indicare che è cliccabile
                SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedPost(ThemeData theme, Map<String, dynamic> post) {
    // Determina l'URL del video
    String videoUrl = '';
    final videoId = post['id'] as String? ?? '';
    final userId = post['userId'] as String;
    final bool isNewFormat = videoId.contains(userId);
    
    // Usa la stessa logica di profile_edit_page.dart
    if (isNewFormat) {
      // Per il nuovo formato: usa media_url
      videoUrl = post['media_url'] ?? '';
    } else {
      // Per il vecchio formato: usa video_path o cloudflare_url
      videoUrl = post['video_path'] ?? post['cloudflare_url'] ?? '';
    }

    return AnimatedBuilder(
      animation: _topSectionAnimation,
      builder: (context, child) {
        // Calcola l'altezza dinamica in base allo stato dell'animazione
        final screenHeight = MediaQuery.of(context).size.height;
        final safeAreaTop = MediaQuery.of(context).padding.top;
        final headerHeight = 60.0; // Altezza approssimativa dell'header
        final topSectionHeight = 160.0; // Altezza ulteriormente ridotta della sezione superiore
        
        // Quando la sezione superiore è nascosta, il video occupa tutto lo spazio disponibile
        final isTopSectionHidden = _topSectionAnimation.value > 0.5;
        final finalHeight = isTopSectionHidden 
            ? screenHeight - safeAreaTop - headerHeight - 20 // Quasi tutto lo schermo
            : screenHeight * 0.85; // Altezza normale

    return Container(
          margin: isTopSectionHidden ? EdgeInsets.zero : EdgeInsets.only(bottom: 8),
          height: finalHeight, // Altezza dinamica che si espande quando la sezione superiore è nascosta
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
            offset: Offset(0, 4),
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
        children: [
          // Video principale che occupa tutto lo spazio
          Container(
            width: double.infinity,
            height: double.infinity,
            child: _buildVideoContent(post, videoUrl),
          ),
          
          // Card utente in alto (allineata con stella e centrata)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _navigateToUserProfile(post['userId']),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Indicatore per video non visto
                      if (!(_hasUserViewedVideo[post['id']] ?? false))
                        Container(
                          margin: EdgeInsets.only(right: 6),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Color(0xFF6C63FF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF6C63FF).withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.network(
                            post['profileImageUrl'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF6C63FF),
                                      Color(0xFF8B7CF6),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '@${post['username']}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Caption in basso (se presente)
          if (post['caption'] != null && post['caption'].toString().isNotEmpty)
            Positioned(
              bottom: 20,
              left: 16,
              right: 100, // Lascia spazio per i pulsanti a destra
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  post['caption'],
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          
          // Pulsanti laterali a destra (spostati in alto)
          Positioned(
            right: 16,
            top: 20,
            child: Column(
                            children: [
                // Pulsante stella con ombra scura rotonda
                GestureDetector(
                  onTap: () => _handleVideoStar(post),
                  child: Container(
                    margin: EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _starAnimationControllers[post['id']] ?? const AlwaysStoppedAnimation(0),
                          builder: (context, child) {
                            final scale = _starScaleAnimations[post['id']]?.value ?? 1.0;
                            final rotation = _starRotationAnimations[post['id']]?.value ?? 0.0;
                            final animationValue = _starAnimationControllers[post['id']]?.value ?? 0.0;
                            final isStarred = _isVideoStarredByCurrentUser(post);
                            
                            return Stack(
                              children: [
                                Transform.scale(
                                  scale: scale,
                                  child: Transform.rotate(
                                    angle: rotation,
                                    child: Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.4),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                          // Effetto glow quando la stella è piena e animata
                                          if (isStarred && scale > 1.0)
                                            BoxShadow(
                                              color: Color(0xFFFFD700).withOpacity(0.6 * (scale - 1.0) / 0.8),
                                              blurRadius: 20 * scale,
                                              spreadRadius: 5 * scale,
                                            ),
                                          if (isStarred && scale > 1.0)
                                            BoxShadow(
                                              color: Color(0xFFFF6B6B).withOpacity(0.4 * (scale - 1.0) / 0.8),
                                              blurRadius: 15 * scale,
                                              spreadRadius: 3 * scale,
                                            ),
                                        ],
                                      ),
                                    child: isStarred
                                        ? ShaderMask(
                                            shaderCallback: (Rect bounds) {
                                              return LinearGradient(
                                                colors: [
                                                  Color(0xFF6C63FF),
                                                  Color(0xFFFF6B6B),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ).createShader(bounds);
                                            },
                                            child: Icon(
                                              Icons.star,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          )
                                        : Icon(
                                            Icons.star_border,
                                            color: Colors.white,
                                            size: 28,
                                            ),
                                          ),
                          ),
                                ),
                                
                                // Effetto particelle/sparkle quando si mette la stella
                                if (animationValue > 0.3 && animationValue < 0.8 && isStarred)
                                  Positioned.fill(
                                    child: Stack(
                                      children: List.generate(8, (index) {
                                        final angle = (index * 45) * (3.14159 / 180);
                                        final distance = 40.0 + (animationValue * 20);
                                        final opacity = (0.8 - animationValue) * 0.8;
                                        
                                        return Positioned(
                                          left: 20 + (distance * math.cos(angle)),
                                          top: 20 + (distance * math.sin(angle)),
                                          child: Transform.rotate(
                                            angle: animationValue * 2 * 3.14159,
                                            child: Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: Color(0xFFFFD700).withOpacity(opacity),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Color(0xFFFFD700).withOpacity(opacity * 0.5),
                                                    blurRadius: 4,
                                                    spreadRadius: 1,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
          
                // Pulsante commenti (con icona e conteggio)
                GestureDetector(
                  onTap: () => _handleVideoComment(post),
                  child: Container(
                    margin: EdgeInsets.only(bottom: 20),
                    child: Builder(
                      builder: (context) {
                        final cacheKey = '${post['userId']}_${post['id']}';
                        final commentCount = _commentsCountCache[cacheKey] ?? 0;
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icona commenti
                              Icon(
                                Icons.comment,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(height: 2),
                              // Numero commenti
                              Text(
                                '${commentCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
          
                // Pulsante menu
                GestureDetector(
                  onTap: () => _showVideoOptions(post),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                          Icons.more_horiz,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                ),
              ),
            ],
          ),
          ),
          
          // Casella emoji minimal sotto la progress bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.2),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _quickEmojis.map((emoji) {
                  return GestureDetector(
                    onTapDown: (details) {
                      final RenderBox renderBox = context.findRenderObject() as RenderBox;
                      final localPosition = renderBox.globalToLocal(details.globalPosition);
                      _handleQuickEmojiComment(post, emoji, localPosition.dx, localPosition.dy);
                    },
                    child: Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        emoji,
                        style: TextStyle(
                          fontSize: 18,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 0.5),
                              blurRadius: 1,
                              color: Colors.black.withOpacity(0.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          // Layer per i confetti animati (nascosti durante l'interazione con la barra di progresso)
          if (!(_isProgressBarInteracting[videoId] == true))
            Positioned.fill(
              child: Stack(
                children: _confettiParticles.entries
                    .where((entry) => entry.key.startsWith(post['id']))
                    .map((entry) {
                  final animationId = entry.key;
                  final particles = entry.value;
                  final controller = _activeConfettiControllers[animationId];
                  
                  if (controller == null) return Container();
                  
                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final animationValue = controller.value;
                      
                      return Stack(
                        children: particles.map((particle) {
                          // Usa una curva di easing più professionale
                          final easedValue = Curves.easeOutCubic.transform(animationValue);
                          
                          // Calcola la posizione corrente della particella con movimento più fluido
                          final currentX = particle.startX + (particle.endX - particle.startX) * easedValue;
                          final currentY = particle.startY + (particle.endY - particle.startY) * easedValue;
                          final currentRotation = particle.rotation + particle.rotationSpeed * easedValue * math.pi;
                          
                          // Calcola l'opacità con fade out più graduale
                          final opacity = animationValue < 0.7 ? 1.0 : (1.0 - (animationValue - 0.7) / 0.3);
                          
                          // Calcola la scala per effetto di crescita e diminuzione
                          final scale = animationValue < 0.3 
                              ? 0.5 + (animationValue / 0.3) * 0.5 // Cresce da 0.5 a 1.0
                              : animationValue > 0.7 
                                  ? 1.0 - ((animationValue - 0.7) / 0.3) * 0.2 // Diminuisce leggermente
                                  : 1.0;
                          
                          return Positioned(
                            left: currentX - (particle.size * scale) / 2,
                            top: currentY - (particle.size * scale) / 2,
                            child: Transform.scale(
                              scale: scale,
                              child: Transform.rotate(
                                angle: currentRotation,
                                child: Opacity(
                                  opacity: opacity,
                                  child: Text(
                                    particle.emoji,
                                    style: TextStyle(
                                      fontSize: particle.size,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(0, 1),
                                          blurRadius: 2,
                                          color: Colors.black.withOpacity(0.2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          

          
          // Progress bar avanzata stile video_quick_view_page
          Positioned(
            left: 0,
            right: 0,
            bottom: 60, // Posizionata sopra le emoticon
              child: (_videoControllers[videoId] != null)
                  ? ValueListenableBuilder<VideoPlayerValue>(
                                            valueListenable: _videoControllers[videoId]!,
                      builder: (context, value, child) {
                      final currentMs = value.position.inMilliseconds.toDouble();
                      final durationMs = value.duration?.inMilliseconds.toDouble() ?? 1.0;
                      final max = durationMs > 0 ? durationMs : 1.0;
                      final clamped = currentMs.clamp(0.0, max);
                      
                      // Converti millisecondi in formato mm:ss
                      final currentMinutes = (currentMs / 60000).floor();
                      final currentSeconds = ((currentMs % 60000) / 1000).floor();
                      final totalMinutes = (durationMs / 60000).floor();
                      final totalSeconds = ((durationMs % 60000) / 1000).floor();
                      
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            // Progress bar con area di cliccaggio estesa
                            Container(
                              height: 32, // Area di cliccaggio estesa verticalmente per facilità d'uso
                              child: GestureDetector(
                                onTapDown: (details) {
                                  // Calcola la posizione del tap relativa alla progress bar
                                  final RenderBox renderBox = context.findRenderObject() as RenderBox;
                                  final localPosition = renderBox.globalToLocal(details.globalPosition);
                                  final progressBarWidth = renderBox.size.width - 32; // Sottrai il padding
                                  final tapPosition = localPosition.dx - 16; // Sottrai il padding sinistro
                                  
                                  // Calcola la percentuale e il tempo corrispondente
                                  if (progressBarWidth > 0) {
                                    final percentage = (tapPosition / progressBarWidth).clamp(0.0, 1.0);
                                    final newTime = (max * percentage).toInt();
                                    _videoControllers[videoId]?.seekTo(Duration(milliseconds: newTime));
                                    
                                    // Attiva l'effetto di interazione
                                    if (!(_isProgressBarInteracting[videoId] == true)) {
                                      _startProgressBarInteraction(videoId);
                                    }
                                    
                                    // Disattiva l'effetto dopo un breve delay
                                    Future.delayed(Duration(milliseconds: 300), () {
                                      if (mounted && (_isProgressBarInteracting[videoId] == true)) {
                                        _endProgressBarInteraction(videoId);
                                      }
                                    });
                                  }
                                },
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: AnimatedContainer(
                                    duration: Duration(milliseconds: 200),
                                    height: _isProgressBarInteracting[videoId] == true ? 8 : 4,
                                    child: SliderTheme(
                          data: SliderThemeData(
                                        thumbShape: RoundSliderThumbShape(
                                          enabledThumbRadius: _isProgressBarInteracting[videoId] == true ? 6 : 0,
                                        ),
                            trackHeight: _isProgressBarInteracting[videoId] == true ? 8 : 4,
                                        activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white.withOpacity(0.3),
                                        thumbColor: _isProgressBarInteracting[videoId] == true ? Colors.white : Colors.transparent,
                                        overlayColor: Colors.white.withOpacity(0.2),
                          ),
                          child: Slider(
                                        value: clamped,
                            min: 0.0,
                                        max: max,
                                        onChanged: (v) {
                                          _videoControllers[videoId]?.seekTo(Duration(milliseconds: v.toInt()));
                                          if (!(_isProgressBarInteracting[videoId] == true)) {
                              _startProgressBarInteraction(videoId);
                                          }
                            },
                                        onChangeEnd: (_) {
                                          if (_isProgressBarInteracting[videoId] == true) {
                              _endProgressBarInteraction(videoId);
                                          }
                                        },
                                        // Permette di cliccare ovunque nella progress bar per navigare
                                        onChangeStart: (_) {
                                          if (!(_isProgressBarInteracting[videoId] == true)) {
                                            _startProgressBarInteraction(videoId);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            // Spazio aumentato tra progress bar e indicatori di tempo
                            SizedBox(height: 12),
                            
                            // Indicatori di tempo
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Tempo corrente
                                  Text(
                                    '${currentMinutes.toString().padLeft(2, '0')}:${currentSeconds.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  
                                  // Tempo totale
                                  Text(
                                    '${totalMinutes.toString().padLeft(2, '0')}:${totalSeconds.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          ),
                        );
                      },
                    )
                  : const SizedBox.shrink(),
          ),
        ],
        ),
      ),
    );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    } else {
      return number.toString();
    }
  }
  
  // Helper functions for formatting time - formato più compatto
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds'; // Non aggiungo padding per i minuti per risparmiare spazio
  }

  // Carica il conteggio dei commenti nella cache
  Future<void> _loadCommentCount(String videoId, String videoUserId) async {
    final cacheKey = '${videoUserId}_$videoId';
    
    // Se abbiamo già il valore in cache, non ricaricare
    if (_commentsCountCache.containsKey(cacheKey)) {
      return;
    }
    
    try {
      final commentsSnapshot = await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .get();
      
      int commentCount = 0;
      if (commentsSnapshot.exists) {
        final dynamic raw = commentsSnapshot.value;
        if (raw is Map) {
          commentCount = raw.length;
        } else if (raw is List) {
          commentCount = raw.where((e) => e != null).length;
        }
      }
      
      // Salva in cache
      _commentsCountCache[cacheKey] = commentCount;
    } catch (e) {
      print('Errore nel caricamento dei commenti per il video $videoId: $e');
      _commentsCountCache[cacheKey] = 0;
    }
  }

  // Calcola il numero di commenti dalla cartella comments
  Future<int> _getCommentsCount(String videoId, String videoUserId) async {
    final cacheKey = '${videoUserId}_$videoId';
    
    // Controlla se abbiamo già il valore in cache
    if (_commentsCountCache.containsKey(cacheKey)) {
      return _commentsCountCache[cacheKey]!;
    }
    
    try {
      final commentsSnapshot = await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .get();
      
      int commentCount = 0;
      if (commentsSnapshot.exists) {
        final dynamic raw = commentsSnapshot.value;
        if (raw is Map) {
          commentCount = raw.length;
        } else if (raw is List) {
          commentCount = raw.where((e) => e != null).length;
        }
      }
      
      // Salva in cache
      _commentsCountCache[cacheKey] = commentCount;
      return commentCount;
    } catch (e) {
      print('Errore nel calcolo dei commenti per il video $videoId: $e');
      return 0;
    }
  }

  Widget _buildVideoContent(Map<String, dynamic> post, String videoUrl) {
    final videoId = post['id'] as String;
    final userId = post['userId'] as String;
    final bool isNewFormat = videoId.contains(userId);
    
    // Usa la stessa logica di profile_edit_page.dart
    String actualVideoUrl = '';
    String thumbnailUrl = '';
    
    if (isNewFormat) {
      // Per il nuovo formato: usa media_url
      actualVideoUrl = post['media_url'] ?? '';
      thumbnailUrl = post['media_url'] ?? '';
    } else {
      // Per il vecchio formato: usa video_path o cloudflare_url (come in profile_edit_page.dart)
      actualVideoUrl = post['video_path'] ?? post['cloudflare_url'] ?? '';
      thumbnailUrl = post['video_path'] ?? post['cloudflare_url'] ?? '';
    }
    
    // Ottieni thumbnail separato se disponibile
    if (post['thumbnail_cloudflare_url'] != null && post['thumbnail_cloudflare_url'].toString().isNotEmpty) {
      thumbnailUrl = post['thumbnail_cloudflare_url'].toString();
    } else if (post['thumbnail_path'] != null && post['thumbnail_path'].toString().isNotEmpty) {
      thumbnailUrl = post['thumbnail_path'].toString();
    }
    
    final controller = _videoControllers[videoId];
    final isInitialized = _videoInitialized[videoId] == true;
    
    if (actualVideoUrl.isNotEmpty && controller != null && isInitialized) {
      // Fix iOS: verifica che il controller sia ancora valido
      if (controller.value.hasError) {
        print('Video controller has error for $videoId: ${controller.value.errorDescription}');
        return _buildVideoPlaceholder();
      }
      
      // Per tutti i video, usa Center e AspectRatio per rispettare il rapporto corretto
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Sfondo nero per i bordi
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16/9, // Fix iOS: fallback aspect ratio
            child: GestureDetector(
              onTapDown: (TapDownDetails details) {
                // Check if tap is in the video area (quasi tutta l'area del video)
                final RenderBox renderBox = context.findRenderObject() as RenderBox;
                final size = renderBox.size;
                final tapX = details.localPosition.dx;
                final tapY = details.localPosition.dy;
                
                // Define video area (90% of video width and height)
                final videoAreaWidth = size.width * 0.9;
                final videoAreaHeight = size.height * 0.9;
                final centerX = size.width / 2;
                final centerY = size.height / 2;
                
                final isInVideoArea = (tapX >= centerX - videoAreaWidth / 2 &&
                                     tapX <= centerX + videoAreaWidth / 2 &&
                                     tapY >= centerY - videoAreaHeight / 2 &&
                                     tapY <= centerY + videoAreaHeight / 2);
                
                if (isInVideoArea) {
                  // Toggle video playback for taps in the video area
                  _toggleVideoPlayback(controller, videoId);
                } else {
                  // Toggle controls visibility for taps outside video area
                  _toggleControlsVisibility(videoId);
                }
              },
              child: Stack(
                children: [
                  // Fix iOS: aggiungi controllo di errore per VideoPlayer
                  controller.value.hasError 
                    ? _buildVideoPlaceholder()
                    : VideoPlayer(controller),
                  
                  // Controlli play/pause overlay - mostra solo quando in pausa
                   if (_showVideoControls[videoId] == true && !(_videoPlaying[videoId] ?? false))
                     AnimatedOpacity(
                       opacity: 1.0,
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
                             Icons.play_arrow, // Mostra sempre l'icona di play (triangolo)
                             color: Colors.white,
                             size: 37,
                           ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (thumbnailUrl.isNotEmpty) {
      // Mostra il thumbnail come fallback (come fa profile_edit_page.dart)
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Sfondo nero per i bordi
        child: Center(
          child: Image.network(
            thumbnailUrl,
            fit: BoxFit.contain, // Mantiene il rapporto d'aspetto originale
            errorBuilder: (context, error, stackTrace) {
              return _buildVideoPlaceholder();
            },
          ),
        ),
      );
    } else if (actualVideoUrl.isNotEmpty) {
      // Mostra placeholder mentre il video si carica
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  'Loading video...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            Container(
              height: 200,
              child: Center(
                child: Lottie.asset(
                  'assets/animations/MainScene.json',
                  width: 180,
                  height: 100,
                  fit: BoxFit.contain,
                  repeat: true,
                  animate: true,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Mostra placeholder se non c'è video
      return _buildVideoPlaceholder();
    }
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C63FF),
            const Color(0xFF8B7CF6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.video_library,
          color: Colors.white,
          size: 64,
        ),
      ),
    );
  }

  Widget _buildTopLikedSection(ThemeData theme) {
    return _topLikedVideos.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _friendIds.isEmpty 
                    ? Lottie.asset(
                        'assets/animations/social_share.json',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      )
                    : Icon(
                        Icons.trending_up,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                SizedBox(height: 16),
                Text(
                  _friendIds.isEmpty ? 'No friends found' : 'No most liked videos',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    fontStyle: _friendIds.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (!_friendIds.isEmpty) ...[
                  SizedBox(height: 8),
                  Text(
                    'The most liked videos will appear here',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ],
                if (_friendIds.isEmpty) ...[
                  SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                          Color(0xFF764ba2), // Colore finale: viola al 100%
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _shareInviteToFriends,
                      icon: Icon(Icons.share, size: 18),
                      label: Text('Invite Friends'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: () async {
              await _refreshFeed();
            },
            color: Color(0xFF6C63FF),
            child: PageView.builder(
              controller: _verticalPageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onVerticalPageChanged,
              itemCount: _topLikedVideos.length,
              itemBuilder: (context, index) {
                final post = _topLikedVideos[index];
                return _buildFeedPost(theme, post);
              },
            ),
          );
  }

  Widget _buildRecentSection(ThemeData theme) {
    return _recentVideos.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _friendIds.isEmpty 
                    ? Lottie.asset(
                        'assets/animations/social_share.json',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      )
                    : Icon(
                        Icons.schedule,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                SizedBox(height: 16),
                Text(
                  _friendIds.isEmpty ? 'No friends found' : 'No recent videos',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    fontStyle: _friendIds.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (!_friendIds.isEmpty) ...[
                  SizedBox(height: 8),
                  Text(
                    'The most recent videos will appear here',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ],
                if (_friendIds.isEmpty) ...[
                  SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                          Color(0xFF764ba2), // Colore finale: viola al 100%
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _shareInviteToFriends,
                      icon: Icon(Icons.share, size: 18),
                      label: Text('Invite Friends'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: () async {
              await _refreshFeed();
            },
            color: Color(0xFF6C63FF),
            child: PageView.builder(
              controller: _verticalPageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onVerticalPageChanged,
              itemCount: _recentVideos.length,
              itemBuilder: (context, index) {
                final post = _recentVideos[index];
                return _buildFeedPost(theme, post);
              },
            ),
          );
  }

  Widget _buildExploreSection(ThemeData theme) {
    return _isLoadingRanking
        ? Column(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    'Loading ranking...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              Container(
                height: 200,
                child: Center(
                  child: Lottie.asset(
                    'assets/animations/MainScene.json',
                    width: 180,
                    height: 100,
                    fit: BoxFit.contain,
                    repeat: true,
                    animate: true,
                  ),
                ),
              ),
            ],
          )
        : _friendsRanking.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _friendIds.isEmpty 
                        ? Lottie.asset(
                            'assets/animations/social_share.json',
                            width: 200,
                            height: 200,
                            fit: BoxFit.contain,
                          )
                        : Icon(
                            Icons.leaderboard,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                    SizedBox(height: 16),
                    Text(
                      _friendIds.isEmpty ? 'No friends found' : 'No ranking data',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        fontStyle: _friendIds.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    if (!_friendIds.isEmpty) ...[
                      SizedBox(height: 8),
                      Text(
                        'Friends ranking will appear here',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (_friendIds.isEmpty) ...[
                      SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                              Color(0xFF764ba2), // Colore finale: viola al 100%
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF667eea).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _shareInviteToFriends,
                          icon: Icon(Icons.share, size: 18),
                          label: Text('Invite Friends'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadFriendsRanking();
                },
                color: Color(0xFF6C63FF),
                child: ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _friendsRanking.length, // Rimosso +1 per l'header
                  itemBuilder: (context, index) {
                    final friend = _friendsRanking[index];
                    return _buildRankingCard(theme, friend, index + 1);
                  },
                ),
              );
  }

  Widget _buildRankingCard(ThemeData theme, Map<String, dynamic> friend, int index) {
    
    return GestureDetector(
      onTap: () {
        // Naviga alla pagina del profilo dell'utente
        _hasNavigatedAway = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileEditPage(
              userId: friend['uid'],
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              // Naviga alla pagina del profilo dell'utente
              _hasNavigatedAway = true;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileEditPage(
                    userId: friend['uid'],
                  ),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  // Badge posizione con gradienti dei piani premium
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: index == 1 
                          ? LinearGradient(
                              colors: [const Color(0xFF00C9FF), const Color(0xFF92FE9D)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : index == 2
                              ? LinearGradient(
                                  colors: [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : index == 3
                                  ? LinearGradient(
                                      colors: [const Color(0xFF6C63FF), const Color(0xFF4A45B1)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                      color: index > 3 ? Colors.grey[400] : null,
                      boxShadow: index <= 3 ? [
                        BoxShadow(
                          color: (index == 1 
                              ? const Color(0xFF00C9FF) 
                              : index == 2 
                                  ? const Color(0xFFFF6B6B) 
                                  : const Color(0xFF6C63FF)).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Center(
                      child: Text(
                        index.toString(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  
                  // Immagine profilo
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: friend['profileImageUrl'] != null && friend['profileImageUrl'].isNotEmpty
                          ? Image.network(
                              friend['profileImageUrl']!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildDefaultProfileImage(theme);
                              },
                            )
                          : _buildDefaultProfileImage(theme),
                    ),
                  ),
                  SizedBox(width: 16),
                  
                  // Informazioni utente
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend['username'] ?? 'Unknown User',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.titleLarge?.color,
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            // Indicatore online/offline
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _onlineStatus[friend['uid']] == true 
                                    ? Colors.green 
                                    : Colors.grey[400],
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              _onlineStatus[friend['uid']] == true ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: _onlineStatus[friend['uid']] == true 
                                    ? Colors.green 
                                    : Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Fluzar Score in cerchio
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF6C63FF),
                          Color(0xFF8B7CF6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF6C63FF).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatNumber(friend['viralystScore'] ?? 0),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Score',
                            style: TextStyle(
                              fontSize: 7,
                              color: Colors.white.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Icona freccia per indicare che è cliccabile
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey[400],
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, int videoCount, IconData icon) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFF6C63FF).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Color(0xFF6C63FF),
            size: 24,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
                Text(
                  '${_friendIds.length} friends • $videoCount videos',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.video_library,
            color: Color(0xFF6C63FF),
            size: 20,
          ),
        ],
      ),
    );
  }

  // Funzioni helper per i social media
  Color _getPlatformColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Colors.blue;
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

  // Carica gli account social per un video specifico
  Future<Map<String, List<Map<String, dynamic>>>> _loadVideoSocialAccounts(String videoId, String userId) async {
    try {
      final isNewFormat = videoId.contains(userId);
      Map<String, List<Map<String, dynamic>>> socialAccounts = {};
      
      if (isNewFormat) {
        // Formato nuovo: accounts in sottocartelle
        final platforms = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
        for (final platform in platforms) {
          final platformRef = _database
              .child('users')
              .child('users')
              .child(userId)
              .child('videos')
              .child(videoId)
              .child('accounts')
              .child(platform);
          
          final accounts = await _fetchAccountsFromSubfolders(platformRef);
          if (accounts.isNotEmpty) {
            socialAccounts[platform] = accounts;
          }
        }
      } else {
        // Formato vecchio: accounts direttamente nel video
        final videoSnapshot = await _database
            .child('users')
            .child('users')
            .child(userId)
            .child('videos')
            .child(videoId)
            .get();
        
        if (videoSnapshot.exists) {
          final videoData = videoSnapshot.value as Map<dynamic, dynamic>;
          final accounts = videoData['accounts'];
          
          if (accounts != null && accounts is Map) {
            for (final platform in accounts.keys) {
              final platformAccounts = accounts[platform];
              if (platformAccounts is List) {
                List<Map<String, dynamic>> processedAccounts = [];
                for (var account in platformAccounts) {
                  if (account is Map) {
                    processedAccounts.add(Map<String, dynamic>.from(account));
                  }
                }
                if (processedAccounts.isNotEmpty) {
                  socialAccounts[platform.toString()] = processedAccounts;
                }
              }
            }
          }
        }
      }
      
      return socialAccounts;
    } catch (e) {
      print('Error loading social accounts: $e');
      return {};
    }
  }

  // Helper per fetch accounts da sottocartelle
  Future<List<Map<String, dynamic>>> _fetchAccountsFromSubfolders(DatabaseReference platformRef) async {
    final snapshot = await platformRef.get();
    List<Map<String, dynamic>> accounts = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is Map && value.isNotEmpty) {
          accounts.add(Map<String, dynamic>.from(value));
        }
      }
    } else if (snapshot.exists && snapshot.value is List) {
      final data = snapshot.value as List<dynamic>;
      for (final value in data) {
        if (value is Map && value.isNotEmpty) {
          accounts.add(Map<String, dynamic>.from(value));
        }
      }
    }
    return accounts;
  }

  // Funzioni per aprire i social media
  void _openSocialMedia(String url) async {
    // Imposta il flag per indicare che stiamo aprendo un URL esterno
    _justOpenedExternalUrl = true;
    
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

  void _openTikTokWithMediaId(String username, String mediaId) async {
    // First try to open TikTok app with the video URL
    final tiktokVideoUri = Uri.parse('tiktok://video/$mediaId');
    
    try {
      if (await canLaunchUrl(tiktokVideoUri)) {
        await launchUrl(tiktokVideoUri);
        return;
      }
    } catch (e) {
      print('Error launching TikTok app with video ID: $e');
    }
    
    // Fallback to web URL
    final webVideoUri = Uri.parse('https://www.tiktok.com/@$username/video/$mediaId');
    try {
      if (await canLaunchUrl(webVideoUri)) {
        await launchUrl(webVideoUri, mode: LaunchMode.externalApplication);
      } else {
        final webProfileUri = Uri.parse('https://www.tiktok.com/@$username');
        if (await canLaunchUrl(webProfileUri)) {
          await launchUrl(webProfileUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      print('Error launching TikTok web URL: $e');
    }
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
        final snapshot = await FirebaseDatabase.instance.ref().child(path).get();
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          print('[FACEBOOK PAGE_ID SEARCH] Found data in path: $path, entries: ${data.length}');
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

  // Funzione per ottenere l'immagine del profilo dell'account social
  Future<String?> _getSocialProfileImage(String userId, String platform, String accountId) async {
    try {
      String? imageUrl;
      
      if (platform.toLowerCase() == 'youtube') {
        // Per YouTube usa thumbnail_url
        final snapshot = await FirebaseDatabase.instance.ref()
            .child('users')
            .child(userId)
            .child(platform.toLowerCase())
            .child(accountId)
            .child('thumbnail_url')
            .get();
        
        if (snapshot.exists) {
          imageUrl = snapshot.value?.toString();
          print('[PROFILE IMAGE] YouTube thumbnail_url trovato: $imageUrl');
        }
      } else if (platform.toLowerCase() == 'threads') {
        // Per Threads usa il percorso speciale: users/users/[userId]/social_accounts/threads/[accountId]/profile_image_url
        final snapshot = await FirebaseDatabase.instance.ref()
            .child('users')
            .child('users')
            .child(userId)
            .child('social_accounts')
            .child('threads')
            .child(accountId)
            .child('profile_image_url')
            .get();
        
        if (snapshot.exists) {
          imageUrl = snapshot.value?.toString();
          print('[PROFILE IMAGE] Threads profile_image_url trovato: $imageUrl');
        }
      } else {
        // Per Instagram, Facebook, TikTok usa profile_image_url
        final snapshot = await FirebaseDatabase.instance.ref()
            .child('users')
            .child(userId)
            .child(platform.toLowerCase())
            .child(accountId)
            .child('profile_image_url')
            .get();
        
        if (snapshot.exists) {
          imageUrl = snapshot.value?.toString();
          print('[PROFILE IMAGE] $platform profile_image_url trovato: $imageUrl');
        }
      }
      
      if (imageUrl == null || imageUrl.isEmpty) {
        print('[PROFILE IMAGE] Nessuna immagine trovata per $platform accountId: $accountId');
      }
      
      return imageUrl;
    } catch (e) {
      print('[PROFILE IMAGE] Errore nel recupero immagine per $platform: $e');
      return null;
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
        // Prima ottieni il video ID dal video corrente
        final videoId = account['video_id']?.toString();
        final userId = account['video_user_id']?.toString();
        if (videoId != null && userId != null) {
          // Controlla se è formato nuovo
          final isNewFormat = videoId.contains(userId);
          
          String? mediaId;
          String? accountId;
          
          if (isNewFormat) {
            // --- FORMATO NUOVO: users/users/[uid]/videos/[idvideo]/accounts/Instagram/ ---
            final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Instagram');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, potrebbe essere un oggetto singolo o una lista di oggetti
              if (videoAccounts is Map) {
                // Caso: un solo account per piattaforma (oggetto diretto)
                final accountDisplayName = videoAccounts['account_display_name']?.toString();
                if (accountDisplayName == displayName) {
                  mediaId = videoAccounts['media_id']?.toString();
                  accountId = videoAccounts['account_id']?.toString();
                  print('[INSTAGRAM] Trovato media_id=$mediaId, accountId=$accountId per display_name=$displayName (formato nuovo - singolo account)');
                }
              } else if (videoAccounts is List) {
                // Caso: più account per piattaforma (lista di oggetti)
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
            // --- FORMATO VECCHIO: users/users/[uid]/videos/[idvideo]/accounts/Instagram/[numero]/ ---
            final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Instagram');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value as List<dynamic>;
              
              // Cerca l'account che corrisponde al display_name
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
            }
          }
          
          if (accountId != null) {
            // --- CONTROLLO facebook_access_token PRIMA DI PROCEDERE ---
            final instagramAccountSnap = await db.child('users').child(userId).child('instagram').child(accountId!).get();
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
          
          if (mediaId != null && mediaId.isNotEmpty && accountId != null) {
            // Ora ottieni l'access token dal proprietario del video: users/[userId]/instagram/[accountId]/facebook_access_token
            final snap = await db.child('users').child(userId).child('instagram').child(accountId!).child('facebook_access_token').get();
            String? accessToken;
            if (snap.exists) {
              accessToken = snap.value?.toString();
              print('[INSTAGRAM] Facebook access token trovato per accountId $accountId dal proprietario del video $userId');
            } else {
              print('[INSTAGRAM] Nessun facebook_access_token trovato per accountId $accountId dal proprietario del video $userId');
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
            print('[INSTAGRAM] Nessun media_id o accountId trovato per display_name=$displayName');
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
        final videoId = account['video_id']?.toString();
        final userId = account['video_user_id']?.toString();
        if (videoId != null && userId != null) {
          // Controlla se è formato nuovo
          final isNewFormat = videoId.contains(userId);
          
          String? postId;
          String? accountId;
          
          if (isNewFormat) {
            // --- FORMATO NUOVO: users/users/[uid]/videos/[idvideo]/accounts/Threads/ ---
            final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Threads');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, potrebbe essere un oggetto singolo o una lista di oggetti
              if (videoAccounts is Map) {
                // Caso: un solo account per piattaforma (oggetto diretto)
                final accountDisplayName = videoAccounts['account_display_name']?.toString();
                if (accountDisplayName == displayName) {
                  postId = videoAccounts['post_id']?.toString(); // <-- uso post_id
                  accountId = videoAccounts['account_id']?.toString();
                  print('[THREADS] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - singolo account)');
                }
              } else if (videoAccounts is List) {
                // Caso: più account per piattaforma (lista di oggetti)
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
            // --- FORMATO VECCHIO: users/users/[uid]/videos/[idvideo]/accounts/Threads/[numero]/ ---
            final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Threads');
            final videoAccountsSnap = await videoAccountsRef.get();
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value as List<dynamic>;
              
              // Cerca l'account che corrisponde al display_name
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
            }
          }
          
          if (postId != null && postId.isNotEmpty && accountId != null && accountId.isNotEmpty) {
            // Prendi l'access token dal proprietario del video: users/users/[userId]/social_accounts/threads/[accountId]/access_token
            final accessTokenSnap = await db.child('users').child('users').child(userId).child('social_accounts').child('threads').child(accountId).child('access_token').get();
            String? accessToken;
            if (accessTokenSnap.exists) {
              accessToken = accessTokenSnap.value?.toString();
              print('[THREADS] Access token trovato per accountId $accountId dal proprietario del video $userId');
            } else {
              print('[THREADS] Nessun access token trovato per accountId $accountId dal proprietario del video $userId');
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

  Future<void> _openFacebookPostOrProfile(Map<String, dynamic> account) async {
    final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? '';
    String? url;
    print('[FACEBOOK] Richiesta link per displayName=$displayName');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final db = FirebaseDatabase.instance.ref();
        
        // Prima ottieni il video ID dal video corrente
        final videoId = account['video_id']?.toString();
        final userId = account['video_user_id']?.toString();
        
        if (videoId != null && userId != null) {
          // Controlla se è formato nuovo
          final isNewFormat = videoId.contains(userId);
          
          String? postId;
          String? accountId;
          
          if (isNewFormat) {
            // --- FORMATO NUOVO: users/users/[uid]/videos/[idvideo]/accounts/Facebook/ ---
            final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Facebook');
            final videoAccountsSnap = await videoAccountsRef.get();
            
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, potrebbe essere un oggetto singolo o una lista di oggetti
              if (videoAccounts is Map) {
                // Caso: un solo account per piattaforma (oggetto diretto)
                final accountDisplayName = videoAccounts['account_display_name']?.toString();
                
                if (accountDisplayName == displayName) {
                  postId = videoAccounts['post_id']?.toString();
                  accountId = videoAccounts['account_id']?.toString();
                  print('[FACEBOOK] Trovato post_id=$postId, accountId=$accountId per display_name=$displayName (formato nuovo - singolo account)');
                }
              } else if (videoAccounts is List) {
                // Caso: più account per piattaforma (lista di oggetti)
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
            // --- FORMATO VECCHIO: users/users/[uid]/videos/[idvideo]/accounts/Facebook/[numero]/ ---
            final videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Facebook');
            final videoAccountsSnap = await videoAccountsRef.get();
            
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value as List<dynamic>;
              
              // Cerca l'account che corrisponde al display_name
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
            }
          }
          
          if (postId != null && postId.isNotEmpty && accountId != null) {
            // Ora ottieni l'access token dal proprietario del video: users/[userId]/facebook/[accountId]/access_token
            final snap = await db.child('users').child(userId).child('facebook').child(accountId).child('access_token').get();
            String? accessToken;
            if (snap.exists) {
              accessToken = snap.value?.toString();
              print('[FACEBOOK] Access token trovato per accountId $accountId dal proprietario del video $userId');
            } else {
              print('[FACEBOOK] Nessun access token trovato per accountId $accountId dal proprietario del video $userId');
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
              print('[FACEBOOK] Nessun access token valido');
            }
          } else {
            print('[FACEBOOK] Nessun post_id o accountId trovato per display_name=$displayName');
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
                  "Instagram does not allow access to public post links unless the Instagram account is linked to a Facebook Page.",
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

  Future<void> _openInstagramProfile(String username) async {
    // Try opening Instagram app with username first
    final instagramUserUri = Uri.parse('instagram://user?username=$username');
    try {
      if (await canLaunchUrl(instagramUserUri)) {
        await launchUrl(instagramUserUri);
        return;
      }
    } catch (e) {
      print('Error launching Instagram app with username: $e');
    }
    
    // Fallback to web URL
    final webUri = Uri.parse('https://www.instagram.com/$username/');
    try {
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        print('Could not launch $webUri');
      }
    } catch (e) {
      print('Error launching web URL: $e');
    }
  }
} 