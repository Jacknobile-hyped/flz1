import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart';
import 'settings_page.dart';
import '../services/email_service.dart';

/// Pagina di modifica e visualizzazione profilo
/// 
/// Utilizzo:
/// - Per modificare il proprio profilo: ProfileEditPage()
/// - Per visualizzare il profilo di un altro utente: ProfileEditPage(userId: 'user_id')
/// 
/// La pagina mostra automaticamente i controlli di modifica solo al proprietario del profilo.
/// Gli altri utenti possono solo visualizzare le informazioni pubbliche.
class ProfileEditPage extends StatefulWidget {
  final String? userId; // ID dell'utente di cui visualizzare il profilo (null = profilo corrente)
  
  const ProfileEditPage({super.key, this.userId});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  // Determina se l'utente corrente è il proprietario del profilo
  bool get _isOwner => widget.userId == null || widget.userId == _currentUser?.uid;
  String get _targetUserId => widget.userId ?? _currentUser?.uid ?? '';
  
  // Controllers per i campi di testo
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  // Variabili di stato
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  bool _isProfilePublic = true;
  bool _showViralystScore = true;
  bool _showVideoCount = true;
  bool _showLikeCount = true;
  bool _showCommentCount = true;
  bool _hasChanges = false; // Per tracciare se ci sono modifiche
  
  // Username validation
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  String _usernameErrorMessage = '';
  
  // Valori originali per il confronto
  bool _originalIsProfilePublic = true;
  bool _originalShowViralystScore = true;
  bool _originalShowVideoCount = true;
  bool _originalShowLikeCount = true;
  bool _originalShowCommentCount = true;
  
  // Immagini
  File? _selectedProfileImage;
  File? _selectedCoverImage;
  String? _currentProfileImageUrl;
  String? _currentCoverImageUrl;
  final ImagePicker _picker = ImagePicker();
  
  // Dati utente
  Map<String, dynamic> _userData = {};
  
  // Animazioni
  late AnimationController _fadeAnimationController;
  late AnimationController _slideAnimationController;
  late AnimationController _scoreAnimationController; // Nuovo controller per l'animazione del score
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scoreAnimation; // Nuova animazione per il score
  
  // Animazione per la stella
  Map<String, AnimationController> _starAnimationControllers = {};
  Map<String, Animation<double>> _starScaleAnimations = {};
  Map<String, Animation<double>> _starRotationAnimations = {};
  
  // Animazione per la stella dei commenti
  Map<String, AnimationController> _commentStarAnimationControllers = {};
  Map<String, Animation<double>> _commentStarScaleAnimations = {};
  Map<String, Animation<double>> _commentStarRotationAnimations = {};
  
  // Animazione per i pulsanti impostazioni
  late AnimationController _settingsAnimationController;
  late Animation<double> _settingsRotationAnimation;
  late Animation<double> _settingsButtonsOpacityAnimation;
  late Animation<double> _settingsButtonsScaleAnimation;
  bool _showSettingsButtons = false;
  
  // Listener per l'immagine profilo (come nel main.dart)
  StreamSubscription? _profileImageSubscription;
  StreamSubscription? _currentUserProfileImageSubscription;
  
  // Statistiche utente
  int _totalVideos = 0;
  int _totalViews = 0;
  int _totalLikes = 0;
  int _totalComments = 0;
  int _viralystScore = 0;
  
  // Video con più like
  List<Map<String, dynamic>> _topVideos = [];
  bool _isLoadingTopVideos = false;
  
  // Ultimi aggiornamenti (ultimi 5 post)
  List<Map<String, dynamic>> _recentPosts = [];
  bool _isLoadingRecentPosts = false;
  
  // PageView controller per i video
  final PageController _videoPageController = PageController(viewportFraction: 0.85);
  int _currentVideoPage = 0;
  
  // PageView controller per i post recenti
  final PageController _recentPostsPageController = PageController(viewportFraction: 0.85);
  int _currentRecentPostPage = 0;
  
  // VideoPlayer controllers per l'autoplay
  Map<String, VideoPlayerController> _videoControllers = {};
  Map<String, bool> _videoInitialized = {};
  Map<String, bool> _videoPlaying = {};
  Map<String, bool> _showVideoControls = {};
  // Stato interazione barra di progresso per ogni video
  Map<String, bool> _isProgressBarInteracting = {};
  final Map<String, Map<String, dynamic>> _videoMediaDetailsCache = {};
  // Controller per i caroselli media nelle card video
  final Map<String, PageController> _mediaCarouselControllers = {};
  final Map<String, int> _mediaCarouselIndexes = {};
  // Controller video dedicati ai caroselli (diversi dall'autoplay principale)
  final Map<String, VideoPlayerController> _carouselVideoControllers = {};
  final Map<String, bool> _carouselVideoInitialized = {};
  final Map<String, bool> _carouselVideoPlaying = {};

  // Friend requests
  List<Map<String, dynamic>> _friendRequests = [];
  bool _isLoadingFriendRequests = false;

  // Amici
  List<Map<String, dynamic>> _friends = [];
  bool _isLoadingFriends = false;
  StreamSubscription<DatabaseEvent>? _friendsSubscription;

  // Controllo amicizia per utenti non proprietari
  bool _isCurrentUserFriend = false;
  bool _isLoadingFriendshipStatus = false;
  bool _hasPendingRequest = false;
  bool _hasReceivedRequest = false;
  
  // Controllo tendina amici
  bool _showFriendsListModal = false;
  
                  // Controllo popup Fluzar Score
  bool _showViralystScorePopup = false;
  
  // Search bar per filtrare amici
  final TextEditingController _friendsSearchController = TextEditingController();
  final FocusNode _friendsSearchFocusNode = FocusNode();
  String _friendsSearchQuery = '';
  bool _isSearchExpanded = false;
  
  // Animation controller per la search bar
  late AnimationController _searchAnimationController;
  late Animation<double> _searchWidthAnimation;
  late Animation<double> _searchOpacityAnimation;

  // Cache per i conteggi dei commenti
  Map<String, int> _commentsCountCache = {};
  
  // Profile image URL for current user (for comment input)
  String? _currentUserProfileImageUrl;
  String? _profileImageUrl; // URL dell'immagine profilo dal database (come in community_page.dart)
  
  // Debounce per prevenire doppi tap (fix iOS)
  Map<String, DateTime> _lastStarTapTime = {};
  static const Duration _starDebounceTime = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadUserData();
    _loadProfileImage(); // Carica l'immagine profilo come nel main.dart
    _loadCurrentUserProfileImage(); // Carica l'immagine profilo dell'utente corrente come in community_page.dart
    _loadTopVideos();
    _loadRecentPosts();
    _loadFriendRequests();
    _loadFriends();
    _checkFriendshipStatus();
    _setupChangeListeners();
    _setupProfileImageListener();
  }

  void _setupChangeListeners() {
    // Ascolta i cambiamenti nei controller di testo
    _usernameController.addListener(_checkForChanges);
    _displayNameController.addListener(_checkForChanges);
    _locationController.addListener(_checkForChanges);
    
    // Aggiungi listener per aggiornare lo stato quando l'username cambia
    _usernameController.addListener(() {
      setState(() {});
    });
  }
  
  void _restoreDefaultSystemUiStyle() {
    // Ripristina uno stile coerente con il tema ATTUALE dell'app (non solo quello di sistema),
    // in linea con quanto fatto in upload_video_page.dart:
    // - tema chiaro  → status bar e navigation bar bianche, icone scure
    // - tema scuro   → status bar e navigation bar scure, icone chiare
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, // Android
      systemNavigationBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  void _setupProfileImageListener() {
    if (_targetUserId.isEmpty) return;
    
    // Cancella i listener precedenti se esistono
    _profileImageSubscription?.cancel();
    _currentUserProfileImageSubscription?.cancel();
    
    // Real-time listener per l'immagine profilo dell'utente target (come nel main.dart)
    final profileRef = _database
        .child('users')
        .child('users')
        .child(_targetUserId)
        .child('profile')
        .child('profileImageUrl');
    
    _profileImageSubscription = profileRef.onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        setState(() {
          _currentProfileImageUrl = event.snapshot.value.toString();
        });
      } else {
        setState(() {
          _currentProfileImageUrl = null;
        });
      }
    });
    
    // Se l'utente corrente è diverso dall'utente target, imposta anche il listener per l'utente corrente
    if (_currentUser != null && _currentUser!.uid != _targetUserId) {
      final currentUserProfileRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('profileImageUrl');
      
      _currentUserProfileImageSubscription = currentUserProfileRef.onValue.listen((event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          setState(() {
            _currentUserProfileImageUrl = event.snapshot.value.toString();
            _profileImageUrl = event.snapshot.value.toString(); // Aggiorna anche _profileImageUrl
          });
        } else {
          setState(() {
            _currentUserProfileImageUrl = null;
            _profileImageUrl = null; // Aggiorna anche _profileImageUrl
          });
        }
      });
    }
    
    // Se l'utente corrente è lo stesso dell'utente target, imposta il listener per l'utente corrente
    if (_currentUser != null && _currentUser!.uid == _targetUserId) {
      final currentUserProfileRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('profileImageUrl');
      
      _currentUserProfileImageSubscription = currentUserProfileRef.onValue.listen((event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          setState(() {
            _currentUserProfileImageUrl = event.snapshot.value.toString();
            _profileImageUrl = event.snapshot.value.toString(); // Aggiorna anche _profileImageUrl
          });
        } else {
          setState(() {
            _currentUserProfileImageUrl = null;
            _profileImageUrl = null; // Aggiorna anche _profileImageUrl
          });
        }
      });
    }
  }

  void _checkForChanges() {
    // Controlla se ci sono modifiche rispetto ai dati originali
    bool hasTextChanges = _usernameController.text != (_userData['username'] ?? '') ||
                         _displayNameController.text != (_userData['displayName'] ?? '') ||
                         _locationController.text != (_userData['location'] ?? '');
    
    bool hasImageChanges = _selectedProfileImage != null || _selectedCoverImage != null;
    
    // Controlla modifiche nelle opzioni di privacy e statistiche
    bool hasPrivacyChanges = _isProfilePublic != _originalIsProfilePublic ||
                            _showViralystScore != _originalShowViralystScore ||
                            _showVideoCount != _originalShowVideoCount ||
                            _showLikeCount != _originalShowLikeCount ||
                            _showCommentCount != _originalShowCommentCount;
    
    // Controlla se l'username è valido per abilitare il salvataggio
    bool isUsernameValid = _usernameController.text.trim().isNotEmpty && _isUsernameAvailable && !_isCheckingUsername;
    
    setState(() {
      _hasChanges = hasTextChanges || hasImageChanges || hasPrivacyChanges;
    });
  }

  bool _isPublishedVideoData(Map<dynamic, dynamic> data) {
    if (data['is_draft'] == true || data['isDraft'] == true || data['draft'] == true) {
      return false;
    }

    final dynamic statusValue = data['status'] ?? data['Status'] ?? data['video_status'];
    if (statusValue == null) {
      return true;
    }

    final String status = statusValue.toString().toLowerCase();
    if (status.isEmpty) {
      return true;
    }

    return !status.contains('draft');
  }

  void _initializeAnimations() {
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scoreAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _settingsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _scoreAnimation = Tween<double>(
      begin: 0.0,
      end: _viralystScore.toDouble(),
    ).animate(CurvedAnimation(
      parent: _scoreAnimationController,
      curve: Curves.easeOut,
    ));
    
    _settingsRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.375, // 135 gradi (3/8 di giro)
    ).animate(CurvedAnimation(
      parent: _settingsAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _settingsButtonsOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _settingsAnimationController,
      curve: Curves.easeOut,
    ));
    
    _settingsButtonsScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _settingsAnimationController,
      curve: Curves.elasticOut,
    ));
    
    _searchWidthAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _searchOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimationController.forward();
    _slideAnimationController.forward();
    _scoreAnimationController.forward();
  }

  void _initializeStarAnimation(String videoId) {
    if (!_starAnimationControllers.containsKey(videoId)) {
      _starAnimationControllers[videoId] = AnimationController(
        duration: Duration(milliseconds: 600), // Animazione uniformata
        vsync: this,
      );
      
      _starScaleAnimations[videoId] = Tween<double>(
        begin: 1.0,
        end: 1.6, // Scala uniformata
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
      // Error loading user profile image – ignore and fallback
      return null;
    }
  }

  /// Carica l'immagine profilo dal database Firebase (come nel main.dart)
  Future<void> _loadProfileImage() async {
    if (_targetUserId.isEmpty) return;
    
    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('profileImageUrl')
          .get();
      
      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _currentProfileImageUrl = snapshot.value.toString();
        });
      }
    } catch (e) {
      // Error loading profile image – ignore silently
    }
  }
  
  /// Carica l'immagine profilo dell'utente corrente dal database Firebase (come in community_page.dart)
  Future<void> _loadCurrentUserProfileImage() async {
    if (_currentUser == null) return;
    
    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('profileImageUrl')
          .get();
      
      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _profileImageUrl = snapshot.value.toString();
          _currentUserProfileImageUrl = snapshot.value.toString();
        });
      }
    } catch (e) {
      // Error loading current user profile image – ignore silently
    }
  }

  @override
  void didUpdateWidget(ProfileEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Se l'utente target è cambiato, ricarica i dati e l'immagine profilo
    if (oldWidget.userId != widget.userId) {
      _loadUserData();
      _loadProfileImage();
      _loadCurrentUserProfileImage(); // Ricarica anche l'immagine profilo dell'utente corrente
      _setupProfileImageListener();
    }
  }

  @override
  void dispose() {
    _restoreDefaultSystemUiStyle();
    _fadeAnimationController.dispose();
    _slideAnimationController.dispose();
    _scoreAnimationController.dispose();
    _settingsAnimationController.dispose();
    _searchAnimationController.dispose();
    
    // Pulisci le animazioni delle stelle
    _starAnimationControllers.values.forEach((controller) => controller.dispose());
    
    // Pulisci le animazioni delle stelle dei commenti
    _commentStarAnimationControllers.values.forEach((controller) => controller.dispose());
    
    _videoPageController.dispose();
    _recentPostsPageController.dispose();
    
    // Dispose di tutti i VideoPlayer controllers
    _videoControllers.values.forEach((controller) {
      try {
        controller.pause();
        controller.dispose();
      } catch (e) {
        // Error disposing video controller
      }
    });
    _videoControllers.clear();
    _videoInitialized.clear();
    _videoPlaying.clear();
    _showVideoControls.clear();
    _videoMediaDetailsCache.clear();
    
    _disposeMediaCarousels();
    
    _usernameController.dispose();
    _displayNameController.dispose();
    _locationController.dispose();
    _friendsSearchController.dispose();
    _friendsSearchFocusNode.dispose();
    
    // Cancella la subscription degli amici
    _friendsSubscription?.cancel();
    
    // Cancella i listener per l'immagine profilo (come nel main.dart)
    _profileImageSubscription?.cancel();
    _currentUserProfileImageSubscription?.cancel();
    
    // Pulisci la cache del debounce (fix iOS)
    _lastStarTapTime.clear();
    
    super.dispose();
  }

  @override
  void deactivate() {
    // Quando si esce dalla pagina (back o cambio schermata), metti in pausa
    // tutti i video in riproduzione senza distruggerli, così non continuano
    // a suonare in background.
    _videoControllers.forEach((key, controller) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
          _videoPlaying[key] = false;
        }
      } catch (_) {}
    });
    _carouselVideoControllers.forEach((key, controller) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
          _carouselVideoPlaying[key] = false;
        }
      } catch (_) {}
    });
    super.deactivate();
  }

  void _disposeMediaCarousels() {
    _mediaCarouselControllers.values.forEach((controller) {
      try {
        controller.dispose();
      } catch (_) {}
    });
    _mediaCarouselControllers.clear();
    _mediaCarouselIndexes.clear();
    _disposeAllCarouselVideoControllers();
  }

  void _disposeAllCarouselVideoControllers() {
    _carouselVideoControllers.values.forEach((controller) {
      try {
        controller.pause();
        controller.dispose();
      } catch (_) {}
    });
    _carouselVideoControllers.clear();
    _carouselVideoInitialized.clear();
    _carouselVideoPlaying.clear();
  }

  // Metodo helper per conversione sicura da dynamic a bool
  bool _safeBoolConversion(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    if (value is int) {
      return value != 0;
    }
    return defaultValue;
  }

  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'y';
    }
    return false;
  }

  Future<void> _prefetchVideoMediaDetails(List<Map<String, dynamic>> videos) async {
    if (videos.isEmpty) return;
    
    final List<Future<void>> futures = [];
    
    for (final video in videos) {
      final String? videoId = video['id']?.toString();
      final String userId = video['userId']?.toString() ?? video['user_id']?.toString() ?? _targetUserId;
      if (videoId == null || userId.isEmpty) continue;
      
      if (_videoMediaDetailsCache.containsKey(videoId)) {
        _applyMediaDetailsToVideo(video, _videoMediaDetailsCache[videoId]!);
        continue;
      }
      
      futures.add(_fetchAndCacheVideoMedia(video, videoId, userId));
    }
    
    if (futures.isEmpty) return;
    
    await Future.wait(futures);
  }

  Future<void> _fetchAndCacheVideoMedia(Map<String, dynamic> video, String videoId, String userId) async {
    try {
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(userId)
          .child('videos')
          .child(videoId)
          .get();
      
      if (!snapshot.exists || snapshot.value is! Map) return;
      final Map<String, dynamic> data = Map<String, dynamic>.from(
        (snapshot.value as Map).map((key, value) => MapEntry(key.toString(), value)),
      );
      
      _videoMediaDetailsCache[videoId] = data;
      _applyMediaDetailsToVideo(video, data);
    } catch (e) {
      // Error fetching media details – ignore, we can still use basic video data
    }
  }

  void _applyMediaDetailsToVideo(Map<String, dynamic> video, Map<String, dynamic> details) {
    if (details.containsKey('cloudflare_urls')) {
      video['cloudflare_urls'] = details['cloudflare_urls'];
    }
    if (details.containsKey('is_image')) {
      video['is_image'] = details['is_image'];
    }
    if (details.containsKey('thumbnail_url')) {
      video['thumbnail_url'] = details['thumbnail_url'];
    }
    if (details.containsKey('media_url')) {
      video['media_url'] = details['media_url'];
    }
    if (details.containsKey('thumbnail_path') && (video['thumbnail_path'] == null || (video['thumbnail_path'] as String?)?.isEmpty == true)) {
      video['thumbnail_path'] = details['thumbnail_path'];
    }
    if (details.containsKey('thumbnail_cloudflare_url') && (video['thumbnail_cloudflare_url'] == null || (video['thumbnail_cloudflare_url'] as String?)?.isEmpty == true)) {
      video['thumbnail_cloudflare_url'] = details['thumbnail_cloudflare_url'];
    }
  }

  bool _parseShowViralystScoreSetting(dynamic value) {
    if (value is String && value == 'isProfilePublic') {
      return _isProfilePublic;
    }
    return _safeBoolConversion(value, true);
  }

  // Controlla se l'username è disponibile
  Future<void> _checkUsernameAvailability(String username) async {
    if (username.trim().isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = true;
        _usernameErrorMessage = '';
      });
      return;
    }

    // Se l'username è lo stesso dell'utente corrente, è sempre disponibile
    if (_currentUser != null) {
      final currentUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .get();
      
      if (currentUserSnapshot.exists) {
        final userData = currentUserSnapshot.value as Map<dynamic, dynamic>;
        final currentUsername = userData['username'] ?? '';
        
        // Controlla anche nel profilo
        final profileSnapshot = await _database
            .child('users')
            .child('users')
            .child(_currentUser!.uid)
            .child('profile')
            .get();
            
        String profileUsername = '';
        if (profileSnapshot.exists) {
          final profileData = profileSnapshot.value as Map<dynamic, dynamic>;
          profileUsername = profileData['username'] ?? '';
        }
        
        if (username.trim().toLowerCase() == currentUsername.toLowerCase() || 
            username.trim().toLowerCase() == profileUsername.toLowerCase()) {
          setState(() {
            _isCheckingUsername = false;
            _isUsernameAvailable = true;
            _usernameErrorMessage = '';
          });
          return;
        }
      }
    }

    setState(() {
      _isCheckingUsername = true;
    });

    try {
      // Controlla se l'username esiste già nel database
      final usernameQuery = await _database
          .child('users')
          .child('users')
          .orderByChild('username')
          .equalTo(username.trim().toLowerCase())
          .get();

      // Controlla anche nel campo profile.username
      final profileUsernameQuery = await _database
          .child('users')
          .child('users')
          .orderByChild('profile/username')
          .equalTo(username.trim().toLowerCase())
          .get();

      bool isAvailable = true;
      String errorMessage = '';

      // Se trova risultati, l'username non è disponibile
      if (usernameQuery.exists && usernameQuery.children.isNotEmpty) {
        // Controlla se il risultato trovato è dell'utente corrente
        bool isCurrentUser = false;
        for (final child in usernameQuery.children) {
          if (child.key == _currentUser?.uid) {
            isCurrentUser = true;
            break;
          }
        }
        
        if (!isCurrentUser) {
          isAvailable = false;
          errorMessage = 'Username already in use';
        }
      }

      // Controlla anche nel campo profile.username
      if (profileUsernameQuery.exists && profileUsernameQuery.children.isNotEmpty) {
        // Controlla se il risultato trovato è dell'utente corrente
        bool isCurrentUser = false;
        for (final child in profileUsernameQuery.children) {
          if (child.key == _currentUser?.uid) {
            isCurrentUser = true;
            break;
          }
        }
        
        if (!isCurrentUser) {
          isAvailable = false;
          errorMessage = 'Username already in use';
        }
      }

      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = isAvailable;
        _usernameErrorMessage = errorMessage;
      });
    } catch (e) {
              // Error checking username availability
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameErrorMessage = 'Errore nel controllo username';
      });
    }
  }

  Future<void> _loadUserData() async {
    if (_targetUserId.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Carica dati utente
      final userSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        
        // Carica statistiche totali
        final totalsSnapshot = await _database
            .child('users')
            .child('users')
            .child(_targetUserId)
            .child('totals')
            .get();
            
        Map<String, dynamic> totals = {};
        if (totalsSnapshot.exists) {
          totals = Map<String, dynamic>.from(totalsSnapshot.value as Map<dynamic, dynamic>);
        }
        
        // Carica video totali
        final videosSnapshot = await _database
            .child('users')
            .child('users')
            .child(_targetUserId)
            .child('videos')
            .get();
            
        int videoCount = 0;
        if (videosSnapshot.exists) {
          final videos = videosSnapshot.value as Map<dynamic, dynamic>;
          videoCount = videos.values.where((videoData) {
            if (videoData is Map) {
              return _isPublishedVideoData(Map<dynamic, dynamic>.from(videoData));
            }
            return true;
          }).length;
        }
        
        // Carica dati profilo (inclusa immagine)
        final profileSnapshot = await _database
            .child('users')
            .child('users')
            .child(_targetUserId)
            .child('profile')
            .get();
            
        Map<String, dynamic> profileData = {};
        String? profileImageUrl = userData['profileImageUrl']; // Fallback al vecchio path
        String? coverImageUrl = userData['coverImageUrl']; // Fallback al vecchio path
        final dynamic rawShowViralystScore = (profileSnapshot.exists && profileSnapshot.value is Map)
            ? (profileSnapshot.value as Map<dynamic, dynamic>)['showViralystScore']
            : null;
        
        if (profileSnapshot.exists) {
          profileData = Map<String, dynamic>.from(profileSnapshot.value as Map<dynamic, dynamic>);
          profileImageUrl = profileData['profileImageUrl'] ?? profileImageUrl;
          coverImageUrl = profileData['coverImageUrl'] ?? coverImageUrl;
        }
        
        setState(() {
          _userData = Map<String, dynamic>.from(userData);
          // Aggiungi i dati del profilo a _userData per renderli accessibili
          _userData.addAll(profileData);
          _usernameController.text = profileData['username'] ?? userData['username'] ?? '';
          _displayNameController.text = profileData['displayName'] ?? userData['displayName'] ?? '';
          _locationController.text = profileData['location'] ?? userData['location'] ?? '';
          _currentProfileImageUrl = profileImageUrl;
          _currentCoverImageUrl = coverImageUrl;
          
          // Carica anche l'immagine profilo dell'utente corrente per i commenti
          if (_currentUser != null && _currentUser!.uid == _targetUserId) {
            _currentUserProfileImageUrl = profileImageUrl;
          }
          
          // Inizializza lo stato dell'username come disponibile se è lo stesso dell'utente corrente
          if (_usernameController.text.trim().isNotEmpty) {
            _isUsernameAvailable = true;
            _usernameErrorMessage = '';
          }
          
          // Impostazioni privacy (caricate dalla cartella profile) - conversione sicura dei tipi
          _isProfilePublic = _safeBoolConversion(profileData['isProfilePublic'], true);
          _showViralystScore = _parseShowViralystScoreSetting(rawShowViralystScore);
          _showVideoCount = _safeBoolConversion(profileData['showVideoCount'], true);
          _showLikeCount = _safeBoolConversion(profileData['showLikeCount'], true);
          _showCommentCount = _safeBoolConversion(profileData['showCommentCount'], true);
          
          // Salva i valori originali per il confronto
          _originalIsProfilePublic = _isProfilePublic;
          _originalShowViralystScore = _showViralystScore;
          _originalShowVideoCount = _showVideoCount;
          _originalShowLikeCount = _showLikeCount;
          _originalShowCommentCount = _showCommentCount;

          // Statistiche reali da Firebase
          _totalVideos = videoCount;
          _totalViews = totals['total_views'] ?? 0;
          _totalLikes = totals['total_likes'] ?? 0;
          _totalComments = totals['total_comments'] ?? 0;
          
          // Leggi streak_bonuses dal profilo
          int streakBonuses = 0;
          if (profileData.containsKey('streak_bonuses')) {
            final value = profileData['streak_bonuses'];
            if (value is int) {
              streakBonuses = value;
            } else if (value is String) {
              streakBonuses = int.tryParse(value) ?? 0;
            }
          }
          
          _viralystScore = _calculateViralystScore(videoCount, totals['total_views'] ?? 0, totals['total_likes'] ?? 0, streakBonuses);
          
          // Aggiorna l'animazione del score
          _updateScoreAnimation();
          
          // Reset delle modifiche
          _hasChanges = false;
        });
        
                        // Salva il fluzar score nel database Firebase (fuori dal setState)
        await _saveViralystScoreToFirebase(_viralystScore);
      }
      
      // Controlla lo stato di amicizia dopo aver caricato i dati utente
      _checkFriendshipStatus();
      
      // Reinizializza il listener degli amici per il nuovo utente target
      _initializeFriendsListener();
    } catch (e) {
      // Error loading user data - silently handled
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  int _calculateViralystScore(int videos, int views, int likes, int streakBonuses) {
    // Formula: numero video x 10 + numero like x 0,005 + numero commenti x 0,05 + streak_bonuses x 100
    // Arrotondare sempre per eccesso al numero naturale maggiore
    double score = (videos * 10) + (likes * 0.005) + (views * 0.05) + (streakBonuses * 100);
    return score.ceil(); // Arrotonda per eccesso
  }
  
  Future<void> _saveViralystScoreToFirebase(int viralystScore) async {
    try {
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('viralystScore')
          .set(viralystScore);
      
                              // Fluzar score salvato in Firebase
    } catch (e) {
                              // Errore nel salvataggio del fluzar score
    }
  }
  
  void _updateScoreAnimation() {
    _scoreAnimation = Tween<double>(
      begin: 0.0,
      end: _viralystScore.toDouble(),
    ).animate(CurvedAnimation(
      parent: _scoreAnimationController,
      curve: Curves.easeOut,
    ));
    
    _scoreAnimationController.reset();
    _scoreAnimationController.forward();
  }

  // Funzione per abbreviare i numeri superiori a 999
  String _abbreviateNumber(int number) {
    if (number < 1000) {
      return number.toString();
    } else if (number < 1000000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
  }
  
  void _toggleSettingsButtons() {
    setState(() {
      _showSettingsButtons = !_showSettingsButtons;
    });
    
    if (_showSettingsButtons) {
      _settingsAnimationController.forward();
    } else {
      _settingsAnimationController.reverse();
    }
  }

  Future<void> _acceptFriendRequest(Map<String, dynamic> request, StateSetter? setModalState) async {
    try {
      final requestId = request['requestId'];
      final fromUserId = request['fromUserId'];
      
      // Ottieni i dati completi dell'utente che ha inviato la richiesta
      final fromUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(fromUserId)
          .get();
      
      Map<String, dynamic> fromUserData = {};
      if (fromUserSnapshot.exists) {
        fromUserData = Map<String, dynamic>.from(fromUserSnapshot.value as Map<dynamic, dynamic>);
      }
      
      // Ottieni i dati completi dell'utente che accetta la richiesta
      final currentUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .get();
      
      Map<String, dynamic> currentUserData = {};
      if (currentUserSnapshot.exists) {
        currentUserData = Map<String, dynamic>.from(currentUserSnapshot.value as Map<dynamic, dynamic>);
      }
      
      // Crea l'oggetto amico per il proprietario del profilo (che accetta la richiesta)
      final friendForOwner = {
        'userId': fromUserId,
        'displayName': fromUserData['displayName'] ?? request['fromDisplayName'] ?? 'Unknown User',
        'username': fromUserData['username'] ?? request['fromUsername'] ?? 'unknown',
        'profileImageUrl': fromUserData['profileImageUrl'] ?? request['fromProfileImageUrl'] ?? '',
        'friendshipDate': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Crea l'oggetto amico per l'utente che ha inviato la richiesta
      final friendForRequester = {
        'userId': _targetUserId,
        'displayName': currentUserData['displayName'] ?? _userData['displayName'] ?? 'Unknown User',
        'username': currentUserData['username'] ?? _userData['username'] ?? 'unknown',
        'profileImageUrl': currentUserData['profileImageUrl'] ?? _userData['profileImageUrl'] ?? '',
        'friendshipDate': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Salvando amico per il proprietario
      // Salvando amico per il richiedente
      
      // Salva l'amico nella cartella alreadyfriends del proprietario del profilo
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('alreadyfriends')
          .child(fromUserId)
          .set(friendForOwner);
      
      // Salva l'amico nella cartella alreadyfriends dell'utente che ha inviato la richiesta
      await _database
          .child('users')
          .child('users')
          .child(fromUserId)
          .child('profile')
          .child('alreadyfriends')
          .child(_targetUserId)
          .set(friendForRequester);
      
      // Rimuovi la richiesta dalla cartella friends (perché ora sono amici)
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('friends')
          .child(requestId)
          .remove();
      
      // Rimuovi anche la richiesta dalla cartella friends dell'altro utente se esiste
      await _database
          .child('users')
          .child('users')
          .child(fromUserId)
          .child('profile')
          .child('friends')
          .child(requestId)
          .remove();
      
      // Invia notifica push OneSignal all'utente che ha inviato la richiesta
      await _sendOneSignalNotification(fromUserId, currentUserData['displayName'] ?? _userData['displayName'] ?? 'Unknown User', 'friend_request_accepted');
      
      // Aggiorna immediatamente la lista locale delle richieste
      setState(() {
        _friendRequests.removeWhere((req) => req['requestId'] == requestId);
      });
      
      // Aggiorna anche la tendina se è aperta
      if (setModalState != null) {
        setModalState(() {
          _friendRequests.removeWhere((req) => req['requestId'] == requestId);
        });
      }
      
      // Aggiorna lo stato di amicizia per l'utente corrente
      _checkFriendshipStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('${request['fromDisplayName']} is now your friend!', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      // Error accepting friend request
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
    }
  }
  Future<void> _declineFriendRequest(Map<String, dynamic> request, StateSetter? setModalState) async {
    try {
      final requestId = request['requestId'];
      final fromUserId = request['fromUserId'];
      
      // Crea l'oggetto utente rifiutato per il proprietario del profilo
      final declinedUser = {
        'userId': fromUserId,
        'displayName': request['fromDisplayName'],
        'username': request['fromUsername'],
        'profileImageUrl': request['fromProfileImageUrl'],
        'declineDate': DateTime.now().millisecondsSinceEpoch,
        'status': 'declined',
      };
      
      // Salva l'utente rifiutato nella cartella declinedfriends del proprietario del profilo
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('declinedfriends')
          .child(fromUserId)
          .set(declinedUser);
      
      // Rimuovi la richiesta dal database
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('friends')
          .child(requestId)
          .remove();
      
      // Aggiorna immediatamente la lista locale delle richieste
      setState(() {
        _friendRequests.removeWhere((req) => req['requestId'] == requestId);
      });
      
      // Aggiorna anche la tendina se è aperta
      if (setModalState != null) {
        setModalState(() {
          _friendRequests.removeWhere((req) => req['requestId'] == requestId);
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.close, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Friend request from ${request['fromDisplayName']} declined', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      // Error declining friend request
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Error declining friend request', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _loadFriendRequests() async {
    if (!_isOwner) return; // Solo il proprietario può vedere le richieste

    setState(() {
      _isLoadingFriendRequests = true;
    });

    try {
      final friendsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('friends')
          .get();

      if (friendsSnapshot.exists) {
        final friends = friendsSnapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> requests = [];

        friends.forEach((requestId, requestData) {
          if (requestData is Map) {
            final request = Map<String, dynamic>.from(requestData);
            if (request['status'] == 'pending') {
              request['requestId'] = requestId; // requestId ora è l'ID dell'utente che ha inviato la richiesta
              requests.add(request);
            }
          }
        });

        setState(() {
          _friendRequests = requests;
          _isLoadingFriendRequests = false;
        });
      } else {
        setState(() {
          _friendRequests = [];
          _isLoadingFriendRequests = false;
        });
      }
    } catch (e) {
              // Error loading friend requests
      setState(() {
        _friendRequests = [];
        _isLoadingFriendRequests = false;
      });
    }
  }

  void _initializeFriendsListener() {
    // Cancella eventuali subscription precedenti
    _friendsSubscription?.cancel();

    // Per i proprietari della pagina, carica gli amici dell'utente corrente
    // Per i non proprietari, carica gli amici dell'utente del profilo visualizzato
    final String userIdToLoad = _isOwner ? _currentUser!.uid : _targetUserId;
    
    final friendsRef = _database
        .child('users')
        .child('users')
        .child(userIdToLoad)
        .child('profile')
        .child('alreadyfriends');

    setState(() {
      _isLoadingFriends = true;
    });

    // Listener per amici in tempo reale
    _friendsSubscription = friendsRef.onValue.listen((event) async {
      if (!mounted) return;

      List<Map<String, dynamic>> friendsList = [];
      
      if (event.snapshot.exists) {
        final friends = event.snapshot.value as Map<dynamic, dynamic>;
        
        // Carica i dati completi del profilo per ogni amico
        for (final friendId in friends.keys) {
          try {
            final friendProfileRef = _database
                .child('users')
                .child('users')
                .child(friendId)
                .child('profile');
            
            final friendProfileSnapshot = await friendProfileRef.get();
            
            if (friendProfileSnapshot.exists && friendProfileSnapshot.value is Map) {
              final friendProfile = Map<String, dynamic>.from(friendProfileSnapshot.value as Map);
              
              // Crea l'oggetto amico con tutti i dati necessari
              final friend = {
                'friendId': friendId,
                'uid': friendId,
                'displayName': friendProfile['displayName'] ?? 'Unknown User',
                'username': friendProfile['username'] ?? 'unknown',
                'profileImageUrl': friendProfile['profileImageUrl'] ?? '',
                'friendshipDate': friends[friendId] is Map ? friends[friendId]['friendshipDate'] ?? 0 : 0,
              };
              
              friendsList.add(friend);
            }
          } catch (e) {
            // Error loading friend profile – aggiungi comunque l'amico con dati di base
            final friend = {
              'friendId': friendId,
              'uid': friendId,
              'displayName': 'Unknown User',
              'username': 'unknown',
              'profileImageUrl': '',
              'friendshipDate': friends[friendId] is Map ? friends[friendId]['friendshipDate'] ?? 0 : 0,
            };
            friendsList.add(friend);
          }
        }
      }

      if (mounted) {
        setState(() {
          _friends = friendsList;
          _isLoadingFriends = false;
        });
      }
    }, onError: (error) {
      // Error loading friends – ignore to avoid breaking the page
      if (mounted) {
        setState(() {
          _friends = [];
          _isLoadingFriends = false;
        });
      }
    });
  }

  Future<void> _loadFriends() async {
    _initializeFriendsListener();
  }

  // Metodo helper per determinare se mostrare le statistiche private
  bool _shouldShowPrivateStats() {
    // Se è il proprietario del profilo, mostra sempre tutto
    if (_isOwner) return true;
    
    // Se il profilo è pubblico, mostra tutto
    if (_isProfilePublic) return true;
    
    // Se il profilo non è pubblico, mostra solo agli amici
    return _isCurrentUserFriend;
  }

  // Metodo helper per determinare se mostrare le statistiche specifiche
  bool _shouldShowVideoCount() {
    // Se è il proprietario del profilo, rispetta le sue impostazioni
    if (_isOwner) return _showVideoCount;
    
    // Se è un amico, mostra sempre (indipendentemente dalle impostazioni)
    if (_isCurrentUserFriend) return true;
    
    // Per tutti gli altri (non-amici), rispetta le impostazioni del proprietario
    return _showVideoCount;
  }

  bool _shouldShowLikeCount() {
    // Se è il proprietario del profilo, rispetta le sue impostazioni
    if (_isOwner) return _showLikeCount;
    
    // Se è un amico, mostra sempre (indipendentemente dalle impostazioni)
    if (_isCurrentUserFriend) return true;
    
    // Per tutti gli altri (non-amici), rispetta le impostazioni del proprietario
    return _showLikeCount;
  }

  bool _shouldShowCommentCount() {
    // Se è il proprietario del profilo, rispetta le sue impostazioni
    if (_isOwner) return _showCommentCount;
    
    // Se è un amico, mostra sempre (indipendentemente dalle impostazioni)
    if (_isCurrentUserFriend) return true;
    
    // Per tutti gli altri (non-amici), rispetta le impostazioni del proprietario
    return _showCommentCount;
  }

  bool _shouldShowViralystScore() {
    // Se è il proprietario del profilo, rispetta le sue impostazioni
    if (_isOwner) return _showViralystScore;
    
    // Se è un amico, mostra sempre (indipendentemente dalle impostazioni)
    if (_isCurrentUserFriend) return true;
    
    // Per tutti gli altri (non-amici), rispetta le impostazioni del proprietario
    return _isProfilePublic && _showViralystScore;
  }

  Future<void> _checkFriendshipStatus() async {
    // Se l'utente corrente è il proprietario del profilo, non serve controllare
    if (_isOwner) {
      setState(() {
        _isCurrentUserFriend = true;
        _isLoadingFriendshipStatus = false;
        _hasPendingRequest = false;
        _hasReceivedRequest = false;
      });
      return;
    }

    // Se non c'è un utente corrente, non è amico
    if (_currentUser == null) {
      setState(() {
        _isCurrentUserFriend = false;
        _isLoadingFriendshipStatus = false;
        _hasPendingRequest = false;
        _hasReceivedRequest = false;
      });
      return;
    }

    setState(() {
      _isLoadingFriendshipStatus = true;
    });

    try {
      // Controlla se l'utente corrente è nella lista amici del proprietario del profilo
      final friendshipSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('alreadyfriends')
          .child(_currentUser!.uid)
          .get();

      // Controlla se c'è una richiesta pendente dal punto di vista dell'utente corrente
      final pendingRequestSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
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

      // Controlla se l'utente corrente ha ricevuto una richiesta dal proprietario del profilo
      final receivedRequestSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('friends')
          .child(_targetUserId)
          .get();

      bool hasReceivedRequest = false;
      if (receivedRequestSnapshot.exists) {
        final requestData = receivedRequestSnapshot.value as Map<dynamic, dynamic>;
        final status = requestData['status']?.toString();
        hasReceivedRequest = status == 'pending';
      }

      setState(() {
        _isCurrentUserFriend = friendshipSnapshot.exists;
        _hasPendingRequest = hasPendingRequest;
        _hasReceivedRequest = hasReceivedRequest;
        _isLoadingFriendshipStatus = false;
      });
    } catch (e) {
              // Error checking friendship status
      setState(() {
        _isCurrentUserFriend = false;
        _hasPendingRequest = false;
        _hasReceivedRequest = false;
        _isLoadingFriendshipStatus = false;
      });
    }
  }

  Future<void> _sendFriendRequest() async {
    if (_currentUser == null || _isOwner) return;

    try {
      // Controlla se sono già amici
      final alreadyFriendsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('alreadyfriends')
          .child(_targetUserId)
          .get();

      if (alreadyFriendsSnapshot.exists) {
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
        return;
      }

      // Controlla se c'è già una richiesta pendente
      final pendingRequestSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('friends')
          .child(_currentUser!.uid)
          .get();

      if (pendingRequestSnapshot.exists) {
        final requestData = pendingRequestSnapshot.value as Map<dynamic, dynamic>;
        final status = requestData['status']?.toString();
        if (status == 'pending') {
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
          return;
        }
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

      // Salva la richiesta nel database del target user
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('friends')
          .child(_currentUser!.uid)
          .set(friendRequest);

      // Invia notifica push OneSignal
      await _sendOneSignalNotification(_targetUserId, friendRequest['fromDisplayName'].toString(), 'friend_request');

      // Mostra messaggio di successo
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

      // Aggiorna lo stato
      setState(() {
        _hasPendingRequest = true;
        _hasReceivedRequest = false;
      });

    } catch (e) {
              // Error sending friend request
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
  }

  Future<void> _acceptFriendRequestFromProfile() async {
    if (_currentUser == null || _isOwner) return;

    try {
      // Carica i dati dell'utente target per ottenere il displayName
      final targetUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
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
        'uid': _targetUserId,
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
          .child(_targetUserId)
          .set(friendForOwner);

      // Salva l'amico nella cartella alreadyfriends dell'utente che ha inviato la richiesta
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('alreadyfriends')
          .child(_currentUser!.uid)
          .set(friendForRequester);

      // Rimuovi la richiesta dalla cartella friends
      await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile')
          .child('friends')
          .child(_targetUserId)
          .remove();

      // Rimuovi anche la richiesta dalla cartella friends dell'altro utente se esiste
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .child('friends')
          .child(_currentUser!.uid)
          .remove();

      // Invia notifica push OneSignal
      await _sendOneSignalNotification(_targetUserId, _currentUser!.displayName ?? 'Unknown User', 'friend_request_accepted');

      // Mostra messaggio di successo
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

      // Aggiorna lo stato
      setState(() {
        _isCurrentUserFriend = true;
        _hasReceivedRequest = false;
        _hasPendingRequest = false;
      });

    } catch (e) {
      // Error accepting friend request
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
  }

  Future<void> _sendOneSignalNotification(String targetUserId, String fromDisplayName, String notificationType) async {
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
        // OneSignal Player ID not found for user
        return;
      }

      final String playerId = targetUserSnapshot.value.toString();
      
      // Prepara il contenuto della notifica in base al tipo
      String title;
      String content;
      String clickUrl;
      
      if (notificationType == 'friend_request_accepted') {
        title = '✅ Friend Request Accepted!';
        content = '$fromDisplayName accepted your friend request';
        clickUrl = 'https://fluzar.com/deep-redirect';
      } else {
        title = '👋 New Friend Request!';
        content = '$fromDisplayName wants to be your friend';
        clickUrl = 'https://fluzar.com/deep-redirect';
      }
      
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
          'type': notificationType,
          'from_user_id': _targetUserId,
          'from_display_name': fromDisplayName,
          'target_user_id': targetUserId
        }
      };

              // Sending OneSignal notification

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
                  // OneSignal notification sent successfully
      } else {
                  // OneSignal API error
      }
    } catch (e) {
              // Error sending OneSignal notification
    }
  }

  Future<void> _loadTopVideos() async {
    if (_targetUserId.isEmpty) return;

    setState(() {
      _isLoadingTopVideos = true;
    });

    try {
      // Carica tutti i video dell'utente
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('videos')
          .get();

      if (videosSnapshot.exists) {
        final videos = videosSnapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> videoList = [];

        // Converti i video in una lista con total_likes
        videos.forEach((videoId, videoData) {
          if (videoData is Map) {
            final rawVideo = Map<dynamic, dynamic>.from(videoData);
            if (!_isPublishedVideoData(rawVideo)) {
              return;
            }
            final video = Map<String, dynamic>.from(rawVideo);
            video['id'] = videoId;
            video['userId'] = _targetUserId; // Aggiungi l'ID dell'utente proprietario del video
            
            // Assicurati che total_likes sia un numero
            int totalLikes = 0;
            if (video['total_likes'] != null) {
              totalLikes = video['total_likes'] is int 
                  ? video['total_likes'] 
                  : int.tryParse(video['total_likes'].toString()) ?? 0;
            }
            
            video['total_likes'] = totalLikes;
            videoList.add(video);
          }
        });

        // Ordina per total_likes decrescente e prendi i primi 3 per risparmiare memoria
        videoList.sort((a, b) => (b['total_likes'] as int).compareTo(a['total_likes'] as int));
        final topVideos = videoList.take(3).toList();

        _disposeMediaCarousels();
        await _prefetchVideoMediaDetails(topVideos);
        
        setState(() {
          _topVideos = topVideos;
          _isLoadingTopVideos = false;
        });
        
        // Inizializza i VideoPlayer controllers per i video
        await _initializeVideoControllers();
        
        // Avvia il primo video se disponibile
        if (topVideos.isNotEmpty) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _handlePageChange(0);
            }
          });
        }
      } else {
        _disposeMediaCarousels();
        await _prefetchVideoMediaDetails([]);
        setState(() {
          _topVideos = [];
          _isLoadingTopVideos = false;
        });
      }
    } catch (e) {
      _disposeMediaCarousels();
      // Error loading top videos
      await _prefetchVideoMediaDetails([]);
      setState(() {
        _topVideos = [];
        _isLoadingTopVideos = false;
      });
    }
  }
  Future<void> _loadRecentPosts() async {
    if (_targetUserId.isEmpty) return;

    setState(() {
      _isLoadingRecentPosts = true;
    });

    try {
      // Carica tutti i video dell'utente
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('videos')
          .get();

      List<Map<String, dynamic>> allPosts = [];

      if (videosSnapshot.exists) {
        final videos = videosSnapshot.value as Map<dynamic, dynamic>;
        
        // Converti i video in una lista
        videos.forEach((videoId, videoData) {
          if (videoData is Map) {
            final rawVideo = Map<dynamic, dynamic>.from(videoData);
            if (!_isPublishedVideoData(rawVideo)) {
              return;
            }
            final video = Map<String, dynamic>.from(rawVideo);
            video['id'] = videoId;
            video['userId'] = _targetUserId; // Aggiungi l'ID dell'utente proprietario del video
            
            // Determina se è un video del nuovo formato
            final bool isNewFormat = videoId.contains(_targetUserId);
            
            // Calcola il timestamp per l'ordinamento
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
            
            video['sort_timestamp'] = timestamp;
            allPosts.add(video);
          }
        });
      }

      // Carica anche i scheduled_posts pubblicati
      final scheduledPostsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('scheduled_posts')
          .get();

      if (scheduledPostsSnapshot.exists) {
        final scheduledPosts = scheduledPostsSnapshot.value as Map<dynamic, dynamic>;
        
        scheduledPosts.forEach((postId, postData) {
          if (postData is Map) {
            final rawPost = Map<dynamic, dynamic>.from(postData);
            if (!_isPublishedVideoData(rawPost)) {
              return;
            }
            final post = Map<String, dynamic>.from(rawPost);
            post['id'] = postId;
            post['userId'] = _targetUserId; // Aggiungi l'ID dell'utente proprietario del post
            
            // Controlla se il post è stato pubblicato
            final scheduledTime = post['scheduled_time'] as int?;
            final accounts = post['accounts'] as Map<dynamic, dynamic>? ?? {};
            final hasYouTube = accounts.containsKey('YouTube');
            
            if (hasYouTube && scheduledTime != null) {
              final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (scheduledDateTime.isBefore(now)) {
                // Post pubblicato, aggiungilo alla lista
                post['sort_timestamp'] = scheduledTime;
                allPosts.add(post);
              }
            }
          }
        });
      }

      // Ordina per timestamp decrescente (più recenti prima) e prendi i primi 3
      allPosts.sort((a, b) => (b['sort_timestamp'] as int).compareTo(a['sort_timestamp'] as int));
      final recentPosts = allPosts.take(3).toList();

      await _prefetchVideoMediaDetails(recentPosts);
      
      setState(() {
        _recentPosts = recentPosts;
        _isLoadingRecentPosts = false;
      });
      
      // Inizializza i VideoPlayer controllers per i post recenti
      await _initializeRecentPostsVideoControllers();
      
      // Avvia il primo video se disponibile
      if (recentPosts.isNotEmpty) {
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _handleRecentPostPageChange(0);
          }
        });
      }
    } catch (e) {
              // Error loading recent posts
      await _prefetchVideoMediaDetails([]);
      setState(() {
        _recentPosts = [];
        _isLoadingRecentPosts = false;
      });
    }
  }
  
  Future<void> _initializeRecentPostsVideoControllers() async {
    // Inizializza solo i controller per i primi 3 post per risparmiare memoria
    final postsToInitialize = _recentPosts.take(3).toList();
    
    for (final post in postsToInitialize) {
      final postId = post['id'] as String;
      final bool isNewFormat = postId.contains(_targetUserId);
      
      String videoUrl = '';
      String thumbnailUrl = '';
      if (isNewFormat) {
        videoUrl = post['media_url'] ?? '';
        thumbnailUrl = post['thumbnail_url'] ?? post['media_url'] ?? '';
      } else {
        videoUrl = post['video_path'] ?? post['cloudflare_url'] ?? '';
        thumbnailUrl = post['thumbnail_path'] ?? post['thumbnail_cloudflare_url'] ?? post['thumbnail_url'] ?? '';
      }
      final carouselMediaUrls = _getCarouselMediaUrls(Map<String, dynamic>.from(post));
      final bool isPhotoMedia = _isPhotoMedia(videoUrl, thumbnailUrl, Map<String, dynamic>.from(post), carouselMediaUrls: carouselMediaUrls);
      if (isPhotoMedia || carouselMediaUrls.isNotEmpty) {
        continue;
      }
      
      if (videoUrl.isNotEmpty) {
        try {
          final controller = VideoPlayerController.network(videoUrl);
          _videoControllers[postId] = controller;
          _videoInitialized[postId] = false;
          
          // Inizializza il controller
          await controller.initialize();
          controller.setLooping(true);
          controller.setVolume(1.0); // Abilita l'audio
          
          setState(() {
            _videoInitialized[postId] = true;
            _videoPlaying[postId] = false; // Inizialmente in pausa
            _showVideoControls[postId] = false; // Inizialmente nascondi i controlli
          });
        } catch (e) {
          // Error initializing video controller for recent post
        }
      }
    }
  }

  Future<void> _initializeVideoControllers() async {
    // Dispose dei controller esistenti
    _videoControllers.values.forEach((controller) {
      controller.dispose();
    });
    _videoControllers.clear();
    _videoInitialized.clear();
    
    // Inizializza solo i controller per i primi 3 video per risparmiare memoria
    final videosToInitialize = _topVideos.take(3).toList();
    
    for (final video in videosToInitialize) {
      final videoId = video['id'] as String;
      final bool isNewFormat = videoId.contains(_targetUserId);
      
      String videoUrl = '';
      String thumbnailUrl = '';
      if (isNewFormat) {
        videoUrl = video['media_url'] ?? '';
        thumbnailUrl = video['thumbnail_url'] ?? video['media_url'] ?? '';
      } else {
        videoUrl = video['video_path'] ?? video['cloudflare_url'] ?? '';
        thumbnailUrl = video['thumbnail_path'] ?? video['thumbnail_cloudflare_url'] ?? video['thumbnail_url'] ?? '';
      }
      final carouselMediaUrls = _getCarouselMediaUrls(Map<String, dynamic>.from(video));
      final bool isPhotoMedia = _isPhotoMedia(videoUrl, thumbnailUrl, Map<String, dynamic>.from(video), carouselMediaUrls: carouselMediaUrls);
      if (isPhotoMedia || carouselMediaUrls.isNotEmpty) {
        continue;
      }
      
      if (videoUrl.isNotEmpty) {
        try {
          final controller = VideoPlayerController.network(videoUrl);
          _videoControllers[videoId] = controller;
          _videoInitialized[videoId] = false;
          
          // Inizializza il controller
          await controller.initialize();
          controller.setLooping(true);
          controller.setVolume(1.0); // Abilita l'audio
          
                  setState(() {
          _videoInitialized[videoId] = true;
          _videoPlaying[videoId] = false; // Inizialmente in pausa
          _showVideoControls[videoId] = false; // Inizialmente nascondi i controlli
        });
        } catch (e) {
          // Error initializing video controller
        }
      }
    }
  }
  
  void _onVideoVisibilityChanged(String videoId, bool isVisible) {
    final controller = _videoControllers[videoId];
    if (controller != null && _videoInitialized[videoId] == true) {
      if (isVisible) {
        // Avvia il video quando diventa visibile
        controller.play();
      } else {
        // Pausa il video quando non è più visibile
        controller.pause();
        controller.seekTo(Duration.zero); // Torna all'inizio
      }
    }
  }
  
  void _handleRecentPostPageChange(int newPageIndex) {
    setState(() {
      _currentRecentPostPage = newPageIndex;
    });
    
    // Pausa tutti i video dei post recenti
    _videoControllers.forEach((videoId, controller) {
      if (_recentPosts.any((post) => post['id'] == videoId)) {
        if (controller.value.isPlaying) {
          controller.pause();
          controller.seekTo(Duration.zero);
        }
      }
    });
    
    // Gestisci i controller in modo dinamico per i post recenti
    _manageRecentPostsVideoControllers(newPageIndex);
    
    // Avvia il video del post corrente
    if (newPageIndex < _recentPosts.length) {
      final currentPost = _recentPosts[newPageIndex];
      final postId = currentPost['id'] as String;
      final controller = _videoControllers[postId];
      
      if (controller != null && _videoInitialized[postId] == true) {
        // Piccolo delay per assicurarsi che il video sia visibile
        Future.delayed(Duration(milliseconds: 300), () {
          if (mounted && _currentRecentPostPage == newPageIndex) {
            controller.play();
          }
        });
      }
    }
  }

  Future<void> _manageRecentPostsVideoControllers(int currentPageIndex) async {
    // Mantieni solo i controller per i post visibili (corrente ± 1)
    final visibleRange = 1; // Mantieni solo il post corrente e quelli adiacenti
    final startIndex = (currentPageIndex - visibleRange).clamp(0, _recentPosts.length - 1);
    final endIndex = (currentPageIndex + visibleRange).clamp(0, _recentPosts.length - 1);
    
    // Lista dei post che dovrebbero avere controller attivi
    final List<String> activePostIds = [];
    for (int i = startIndex; i <= endIndex; i++) {
      if (i < _recentPosts.length) {
        final post = _recentPosts[i];
        final postId = post['id'] as String;
        activePostIds.add(postId);
      }
    }
    
    // Dispose dei controller non più necessari
    final postIdsToRemove = <String>[];
    _videoControllers.forEach((postId, controller) {
      if (_recentPosts.any((post) => post['id'] == postId) && !activePostIds.contains(postId)) {
        controller.dispose();
        postIdsToRemove.add(postId);
      }
    });
    
    // Rimuovi i controller dalla mappa
    for (final postId in postIdsToRemove) {
      _videoControllers.remove(postId);
      _videoInitialized.remove(postId);
    }
    
    // Inizializza i controller mancanti per i post visibili
    for (final postId in activePostIds) {
      if (!_videoControllers.containsKey(postId)) {
        await _initializeSingleRecentPostController(postId);
      }
    }
  }

  Future<void> _initializeSingleRecentPostController(String postId) async {
    final post = _recentPosts.firstWhere((p) => p['id'] == postId);
    final bool isNewFormat = postId.contains(_targetUserId);
    
    String videoUrl = '';
    if (isNewFormat) {
      videoUrl = post['media_url'] ?? '';
    } else {
      videoUrl = post['video_path'] ?? post['cloudflare_url'] ?? '';
    }
    
    if (videoUrl.isNotEmpty) {
      try {
        final controller = VideoPlayerController.network(videoUrl);
        _videoControllers[postId] = controller;
        _videoInitialized[postId] = false;
        
        await controller.initialize();
        controller.setLooping(true);
        controller.setVolume(1.0); // Abilita l'audio
        
        setState(() {
          _videoInitialized[postId] = true;
          _videoPlaying[postId] = false; // Inizialmente in pausa
          _showVideoControls[postId] = false; // Inizialmente nascondi i controlli
        });
      } catch (e) {
        // Error initializing video controller for recent post – ignore
      }
    }
  }

  void _handlePageChange(int newPageIndex) {
    setState(() {
      _currentVideoPage = newPageIndex;
    });
    
    // Pausa tutti i video
    _videoControllers.forEach((videoId, controller) {
      if (controller.value.isPlaying) {
        controller.pause();
        controller.seekTo(Duration.zero);
      }
    });
    _pauseAllCarouselVideos(triggerRebuild: false);
    
    // Gestisci i controller in modo dinamico
    _manageVideoControllers(newPageIndex);
    
    // Avvia il video della pagina corrente
    if (newPageIndex < _topVideos.length) {
      final currentVideo = _topVideos[newPageIndex];
      final videoId = currentVideo['id'] as String;
      final controller = _videoControllers[videoId];
      
      if (controller != null && _videoInitialized[videoId] == true) {
        // Piccolo delay per assicurarsi che il video sia visibile
        Future.delayed(Duration(milliseconds: 300), () {
          if (mounted && _currentVideoPage == newPageIndex) {
            controller.play();
          }
        });
      }
    }
  }

  Future<void> _manageVideoControllers(int currentPageIndex) async {
    // Mantieni solo i controller per i video visibili (corrente ± 1)
    final visibleRange = 1; // Mantieni solo il video corrente e quelli adiacenti
    final startIndex = (currentPageIndex - visibleRange).clamp(0, _topVideos.length - 1);
    final endIndex = (currentPageIndex + visibleRange).clamp(0, _topVideos.length - 1);
    
    // Lista dei video che dovrebbero avere controller attivi
    final List<String> activeVideoIds = [];
    for (int i = startIndex; i <= endIndex; i++) {
      if (i < _topVideos.length) {
        final video = _topVideos[i];
        final videoId = video['id'] as String;
        activeVideoIds.add(videoId);
      }
    }
    
    // Dispose dei controller non più necessari
    final videoIdsToRemove = <String>[];
    _videoControllers.forEach((videoId, controller) {
      if (!activeVideoIds.contains(videoId)) {
        controller.dispose();
        videoIdsToRemove.add(videoId);
      }
    });
    
    // Rimuovi i controller dalla mappa
    for (final videoId in videoIdsToRemove) {
      _videoControllers.remove(videoId);
      _videoInitialized.remove(videoId);
    }
    
    // Inizializza i controller mancanti per i video visibili
    for (final videoId in activeVideoIds) {
      if (!_videoControllers.containsKey(videoId)) {
        await _initializeSingleVideoController(videoId);
      }
    }
  }

  Future<void> _initializeSingleVideoController(String videoId) async {
    final video = _topVideos.firstWhere((v) => v['id'] == videoId);
    final bool isNewFormat = videoId.contains(_targetUserId);
    
    String videoUrl = '';
    if (isNewFormat) {
      videoUrl = video['media_url'] ?? '';
    } else {
      videoUrl = video['video_path'] ?? video['cloudflare_url'] ?? '';
    }
    
    if (videoUrl.isNotEmpty) {
      try {
        final controller = VideoPlayerController.network(videoUrl);
        _videoControllers[videoId] = controller;
        _videoInitialized[videoId] = false;
        
        await controller.initialize();
        controller.setLooping(true);
        controller.setVolume(1.0);
        
        setState(() {
          _videoInitialized[videoId] = true;
          _videoPlaying[videoId] = false; // Inizialmente in pausa
          _showVideoControls[videoId] = false; // Inizialmente nascondi i controlli
        });
      } catch (e) {
        // Error initializing video controller – ignore
      }
    }
  }

  void _openUserProfile(String? userId) {
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open user profile'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileEditPage(userId: userId),
      ),
    );
  }

  void _toggleVideoPlayback(VideoPlayerController controller) {
    if (controller.value.isPlaying) {
      controller.pause();
      setState(() {
        // Trova il videoId corrispondente al controller
        final videoId = _videoControllers.entries
            .firstWhere((entry) => entry.value == controller)
            .key;
        _videoPlaying[videoId] = false;
        _showVideoControls[videoId] = true; // Mostra i controlli quando in pausa
      });
    } else {
      controller.play();
      setState(() {
        // Trova il videoId corrispondente al controller
        final videoId = _videoControllers.entries
            .firstWhere((entry) => entry.value == controller)
            .key;
        _videoPlaying[videoId] = true;
        _showVideoControls[videoId] = false; // Nascondi i controlli quando riproduce
      });
      
      // Nascondi i controlli dopo 3 secondi se il video sta riproducendo
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            final videoId = _videoControllers.entries
                .firstWhere((entry) => entry.value == controller)
                .key;
            if (_videoPlaying[videoId] == true) {
              _showVideoControls[videoId] = false;
            }
          });
        }
      });
    }
  }
  
  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      
      if (image != null) {
        setState(() {
          _selectedProfileImage = File(image.path);
          _hasChanges = true; // Marca che ci sono modifiche
        });
      }
    } catch (e) {
              // Error picking profile image
      _showErrorSnackBar('Error selecting profile image');
    }
  }
  
  Future<void> _pickCoverImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 400,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _selectedCoverImage = File(image.path);
          _hasChanges = true; // Marca che ci sono modifiche
        });
      }
    } catch (e) {
              // Error picking cover image
      _showErrorSnackBar('Error selecting cover image');
    }
  }

  Future<String?> _uploadProfileImage() async {
    if (_selectedProfileImage == null) return _currentProfileImageUrl;

    try {
      setState(() {
        _isUploadingImage = true;
      });

      // Cloudflare R2 credentials - usando le stesse credenziali di instagram_upload_page.dart
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos'; // Usa il bucket esistente come in instagram_upload_page.dart
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Generate a unique filename for profile image in a subfolder
      final String fileExtension = path.extension(_selectedProfileImage!.path);
      final String fileName = 'profile_${_targetUserId}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      final String fileKey = 'profile_images/$fileName'; // Organizza in sottocartella
      
      // Get file bytes and size
      final bytes = await _selectedProfileImage!.readAsBytes();
      final contentLength = bytes.length;
      
      // Calcola l'hash SHA-256 del contenuto
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = 'image/jpeg';
      
      // SigV4 richiede data in formato ISO8601
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host e URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileKey');
      final String host = uri.host;
      
      // Canonical request
      final Map<String, String> headers = {
        'host': host,
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate
      };
      
      String canonicalHeaders = '';
      String signedHeaders = '';
      
      // Ordina gli header in ordine lessicografico
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Firma
      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }
      
      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);
      
      // Authorization header
      final String authorizationHeader = '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
      
      // Create request URL
      final String uploadUrl = '$endpoint/$bucketName/$fileKey';
      
      // Create request with headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Add file body
      request.bodyBytes = bytes;
      
      // Send the request
      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL nel formato corretto
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        // Immagine profilo caricata con successo su Cloudflare R2
        
        return publicUrl;
      } else {
        throw Exception('Errore nel caricamento su Cloudflare R2: Codice ${response.statusCode}, Risposta: $responseBody');
      }
    } catch (e) {
              // Error uploading profile image
      _showErrorSnackBar('Error loading profile picture');
      return _currentProfileImageUrl;
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_isOwner || _targetUserId.isEmpty) return;

    // Controlla se l'username è valido
    if (_usernameController.text.trim().isEmpty) {
      _showErrorSnackBar('Username is required');
      return;
    }

    // Controlla se l'username è disponibile
    if (!_isUsernameAvailable) {
      _showErrorSnackBar('Username not available.');
      return;
    }

    // Se l'username è in fase di controllo, aspetta
    if (_isCheckingUsername) {
      _showErrorSnackBar('Wait for username verification...');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Upload immagini se selezionate
      String? profileImageUrl = await _uploadProfileImage();
      String? coverImageUrl = await _uploadCoverImage();
      
      // Prepara tutti i dati del profilo da salvare nella cartella profile
      final profileData = {
        'username': _usernameController.text.trim().toLowerCase(), // Salva sempre in lowercase
        'displayName': _displayNameController.text.trim(),
        'location': _locationController.text.trim(),
        'isProfilePublic': _isProfilePublic,
        'showViralystScore': _showViralystScore,
        'showVideoCount': _showVideoCount,
        'showLikeCount': _showLikeCount,
        'showCommentCount': _showCommentCount,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Aggiungi le immagini se presenti
      if (profileImageUrl != null) {
        profileData['profileImageUrl'] = profileImageUrl;
        profileData['profileImageUploadedAt'] = DateTime.now().millisecondsSinceEpoch;
        profileData['profileImageSource'] = 'cloudflare_r2';
      }
      
      if (coverImageUrl != null) {
        profileData['coverImageUrl'] = coverImageUrl;
        profileData['coverImageUploadedAt'] = DateTime.now().millisecondsSinceEpoch;
        profileData['coverImageSource'] = 'cloudflare_r2';
      }
      
      // Aggiorna solo i campi specificati nella cartella profile (preserva alreadyfriends, friends, etc.)
      await _database
          .child('users')
          .child('users')
          .child(_targetUserId)
          .child('profile')
          .update(profileData);
          
              // Dati profilo salvati in Firebase nella cartella profile
      
      _showSuccessSnackBar('Profile updated successfully!');

      // Aggiorna anche il profilo Firebase Auth se necessario
      if (_displayNameController.text.trim().isNotEmpty && _currentUser != null) {
        await _currentUser!.updateDisplayName(_displayNameController.text.trim());
      }

      // Invia email di benvenuto se è la prima volta che l'utente completa il profilo
      try {
        if (_currentUser != null && _currentUser!.email != null && _currentUser!.email!.isNotEmpty) {
          final displayName = _displayNameController.text.trim();
          if (displayName.isNotEmpty) {
            // Controlla se è la prima volta che l'utente completa il profilo
            final isFirstTimeSetup = _userData['onboardingCompleted'] != true;
            if (isFirstTimeSetup) {
              await EmailService.sendWelcomeEmail(_currentUser!.email!, displayName);
              
              // Marca l'onboarding come completato
              await _database
                  .child('users')
                  .child('users')
                  .child(_targetUserId)
                  .child('profile')
                  .update({'onboardingCompleted': true});
            }
          }
        }
    } catch (e) {
      // Errore nell'invio email di benvenuto – non bloccare il salvataggio del profilo
    }

      // Reset delle modifiche e delle immagini selezionate
      setState(() {
        _hasChanges = false;
        _selectedProfileImage = null;
        _selectedCoverImage = null;
        
        // Aggiorna i valori originali
        _originalIsProfilePublic = _isProfilePublic;
        _originalShowViralystScore = _showViralystScore;
        _originalShowVideoCount = _showVideoCount;
        _originalShowLikeCount = _showLikeCount;
        _originalShowCommentCount = _showCommentCount;
      });

      // Ricarica i dati del profilo per aggiornare la UI
      await _loadUserData();
      await _loadProfileImage();
      await _loadCurrentUserProfileImage();
      await _loadTopVideos();
      await _loadRecentPosts();
      await _loadFriends();
      
      // Non tornare alla pagina precedente, rimani nella pagina corrente
    } catch (e) {
              // Error saving profile
      _showErrorSnackBar('Error saving profile');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }
  Future<String?> _uploadCoverImage() async {
    if (_selectedCoverImage == null) return _currentCoverImageUrl;

    try {
      setState(() {
        _isUploadingImage = true;
      });

      // Cloudflare R2 credentials - usando le stesse credenziali di instagram_upload_page.dart
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos'; // Usa il bucket esistente come in instagram_upload_page.dart
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      
      // Generate a unique filename for cover image in a subfolder
      final String fileExtension = path.extension(_selectedCoverImage!.path);
      final String fileName = 'cover_${_targetUserId}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      final String fileKey = 'cover_images/$fileName'; // Organizza in sottocartella
      
      // Get file bytes and size
      final bytes = await _selectedCoverImage!.readAsBytes();
      final contentLength = bytes.length;
      
      // Calcola l'hash SHA-256 del contenuto
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      
      // Set up request information
      final String httpMethod = 'PUT';
      final String contentType = 'image/jpeg';
      
      // SigV4 richiede data in formato ISO8601
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      
      // Host e URI
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileKey');
      final String host = uri.host;
      
      // Canonical request
      final Map<String, String> headers = {
        'host': host,
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate
      };
      
      String canonicalHeaders = '';
      String signedHeaders = '';
      
      // Ordina gli header in ordine lessicografico
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      
      // Canonical request
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      
      // String to sign
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      
      // Firma
      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }
      
      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);
      
      // Authorization header
      final String authorizationHeader = '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
      
      // Create request URL
      final String uploadUrl = '$endpoint/$bucketName/$fileKey';
      
      // Create request with headers
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      
      // Add file body
      request.bodyBytes = bytes;
      
      // Send the request
      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Generate public URL nel formato corretto
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        
        // Immagine di copertina caricata con successo su Cloudflare R2
        
        return publicUrl;
      } else {
        throw Exception('Errore nel caricamento su Cloudflare R2: Codice ${response.statusCode}, Risposta: $responseBody');
      }
    } catch (e) {
              // Error uploading cover image
      _showErrorSnackBar('Error uploading cover image');
      return _currentCoverImageUrl;
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.grey[700], size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: Colors.black))),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }
  
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  void _showProfileImagePickerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Select profile image',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImagePickerButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickProfileImage(ImageSource.camera);
                    },
                  ),
                  _buildImagePickerButton(
                    icon: Icons.photo_library,
                    label: 'Photo Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickProfileImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
  
  void _showCoverImagePickerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Select cover image',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImagePickerButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickCoverImage(ImageSource.camera);
                    },
                  ),
                  _buildImagePickerButton(
                    icon: Icons.photo_library,
                    label: 'Photo Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickCoverImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showFriendRequestsBottomSheet() async {
    // Ricarica le richieste prima di aprire la tendina
    await _loadFriendRequests();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Titolo centrato
                    Expanded(
                      child: Center(
                        child: Text(
                          'Friend Requests (${_friendRequests.length})',
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
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: _isLoadingFriendRequests
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF6C63FF)),
                        ),
                      )
                    : _friendRequests.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No friend requests',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'You have no pending friend requests',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _friendRequests.length,
                            itemBuilder: (context, index) {
                              final request = _friendRequests[index];
                              return _buildFriendRequestCard(request, Theme.of(context), setModalState);
                            },
                          ),
              ),
            ],
          ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildImagePickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6C63FF),
                    const Color(0xFF8B7CF6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Estendi la cover dietro la status bar come nella pagina di auth
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, // Android
      systemNavigationBarColor: isDark ? Color(0xFF121212) : Colors.white, // Mantieni il colore di sfondo
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
    
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: theme.brightness,
        scaffoldBackgroundColor: isDark ? Color(0xFF121212) : Colors.white,
        cardColor: theme.brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          background: isDark ? Color(0xFF121212) : Colors.white,
          surface: theme.brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: isDark ? Color(0xFF121212) : Colors.white,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: _isLoading
            ? Center(
                child: Container(
                  width: 120,
                  height: 120,
                  child: Lottie.asset(
                    'assets/animations/MainScene.json',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                    repeat: true,
                    animate: true,
                  ),
                ),
              )
            : Stack(
                children: [
                  // Main content area - la cover si estende dietro la status bar
                  CustomScrollView(
                    physics: BouncingScrollPhysics(),
                    slivers: [
                      // Header con immagine di copertina e profilo
                      SliverToBoxAdapter(
                        child: _buildProfileHeader(theme),
                      ),
                        
                        // Statistiche (sovrapposte all'header)
                        SliverToBoxAdapter(
                          child: Transform.translate(
                            offset: Offset(0, -67), // Aggiunto 37 pixel (circa 1 cm) più in alto
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: _buildProfileStatsSection(theme),
                            ),
                          ),
                        ),
                        
                        // Sezione "My Activities" (simile all'immagine) - solo se l'utente ha accesso alle statistiche private
                        if (_shouldShowPrivateStats())
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: _buildTopVideosSection(theme),
                          ),
                        ),
                        
                        // Sezione "Recent Updates" - solo se l'utente ha accesso alle statistiche private
                        if (_shouldShowPrivateStats())
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                SizedBox(height: 30), // Spazio aggiuntivo tra le sezioni
                                _buildRecentPostsSection(theme),
                              ],
                            ),
                          ),
                        ),
                        
                        // Spazio finale
                        SliverToBoxAdapter(
                          child: SizedBox(height: 100), // Spazio per il cerchio fisso
                        ),
                      ],
                    ),
                  
                  
                  // Floating header
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(child: _buildHeader(context)),
                  ),
                  
                  // Fluzar Score e bottone amicizia fissi in basso
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Bottone richiesta amicizia (solo se non è il proprietario e non è amico)
                        if (!_isOwner && !_isCurrentUserFriend && !_hasPendingRequest && !_hasReceivedRequest)
                          Container(
                            margin: EdgeInsets.only(right: 12),
                            child: _buildFriendRequestButton(theme),
                          ),
                        // Bottone pending (quando la richiesta è stata inviata)
                        if (!_isOwner && _hasPendingRequest)
                          Container(
                            margin: EdgeInsets.only(right: 12),
                            child: _buildPendingRequestButton(theme),
                          ),
                        // Bottone accetta richiesta (solo se ha ricevuto una richiesta)
                        if (!_isOwner && _hasReceivedRequest)
                          Container(
                            margin: EdgeInsets.only(right: 12),
                            child: _buildAcceptRequestButton(theme),
                          ),
                        // Fluzar Score (solo se visibile)
                        if (_shouldShowViralystScore())
                          _buildViralystScoreFixed(theme),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      height: 56,
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
              // Freccia indietro + logo Fluzar (stile header AI)
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                      size: 22,
                    ),
                    onPressed: () {
                      // Ripristina subito i colori corretti di status/navigation bar
                      _restoreDefaultSystemUiStyle();
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
              // Lato destro: badge stile "AI Insights" + pulsante salva (solo owner e se ci sono modifiche)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person,
                          size: 14,
                          color: const Color(0xFF6C63FF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isOwner ? 'My Profile' : 'Profile',
                          style: TextStyle(
                            color: const Color(0xFF6C63FF),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isOwner && _hasChanges) const SizedBox(width: 8),
                  if (_isOwner && _hasChanges)
                    _isSaving
                        ? SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF6C63FF)),
                                ),
                              ),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.save,
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                              size: 22,
                            ),
                            onPressed: _saveProfile,
                          ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildProfileHeader(ThemeData theme) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final totalHeight = 488 + statusBarHeight;
    return Container(
      height: totalHeight,
      child: Stack(
        children: [
          // Immagine di copertina estesa fino alle icone di sistema
          Container(
            width: double.infinity,
            height: 388 + statusBarHeight,
            child: _selectedCoverImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    child: Image.file(
                      _selectedCoverImage!,
                      fit: BoxFit.cover,
                    ),
                  )
                : _currentCoverImageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                        child: Image.network(
                          _currentCoverImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildDefaultCoverImage();
                          },
                        ),
                      )
                    : _buildDefaultCoverImage(),
          ),
          
          // Overlay scuro per migliorare la leggibilità (esteso fino alle icone di sistema)
          Container(
            width: double.infinity,
            height: 388 + statusBarHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.5),
                ],
              ),
            ),
          ),
          
          // Username del proprietario in alto a sinistra
          Positioned(
            top: 74 + statusBarHeight,
            left: 16,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '@${_usernameController.text.isNotEmpty ? _usernameController.text.trim().toLowerCase() : (_userData['username'] ?? 'user')}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Settings Button with animated options (conditional)
          if (_isOwner)
            Positioned(
              top: 74 + statusBarHeight,
              right: 16,
              child: AnimatedBuilder(
                animation: _settingsAnimationController,
                builder: (context, child) {
                  return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                      // Pulsanti animati (nascosti/mostrati)
                      if (_showSettingsButtons) ...[
                  // Bottone modifica info
                        Transform.scale(
                          scale: _settingsButtonsScaleAnimation.value,
                          child: Opacity(
                            opacity: _settingsButtonsOpacityAnimation.value,
                            child: Container(
                    width: 28,
                    height: 28,
                              margin: EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 14,
                      ),
                      onPressed: _showEditInfoBottomSheet,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                          ),
                        ),
                  // Bottone cambio copertina
                        Transform.scale(
                          scale: _settingsButtonsScaleAnimation.value,
                          child: Opacity(
                            opacity: _settingsButtonsOpacityAnimation.value,
                            child: Container(
                    width: 28,
                    height: 28,
                              margin: EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 14,
                      ),
                      onPressed: _showCoverImagePickerDialog,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                          ),
                        ),
                  // Bottone amici
                        Transform.scale(
                          scale: _settingsButtonsScaleAnimation.value,
                          child: Opacity(
                            opacity: _settingsButtonsOpacityAnimation.value,
                            child: Stack(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                                  margin: EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.people,
                            color: Colors.white,
                            size: 14,
                          ),
                          onPressed: () => _showFriendRequestsBottomSheet(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      // Badge per le richieste in sospeso
                      if (_friendRequests.isNotEmpty)
                                  Positioned(
                                    top: 0,
                                    right: 8,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF6B6B),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _friendRequests.length > 9 ? '9+' : _friendRequests.length.toString(),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
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
                      // Pulsante impostazioni principale (sempre visibile)
                      Stack(
                        children: [
                          Transform.rotate(
                            angle: _settingsRotationAnimation.value * 2 * math.pi,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.settings,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                onPressed: _toggleSettingsButtons,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          // Badge per le richieste in sospeso (solo quando i pulsanti sono chiusi)
                          if (_friendRequests.isNotEmpty && !_showSettingsButtons)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _friendRequests.length > 9 ? '9+' : _friendRequests.length.toString(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                  );
                },
              ),
            ),
          
          // Immagine profilo al centro (cliccabile per il proprietario)
          Positioned(
            bottom: 255, // Aggiunto 75 pixel (circa 2 cm) più in alto
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isOwner ? _showProfileImagePickerDialog : null,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                  child: Stack(
                    children: [
                      // Immagine profilo
                      ClipOval(
                        child: Container(
                          width: 120,
                          height: 120,
                  child: _selectedProfileImage != null
                      ? Image.file(
                          _selectedProfileImage!,
                          fit: BoxFit.cover,
                        )
                      : _currentProfileImageUrl != null
                          ? Image.network(
                              _currentProfileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildDefaultProfileImage();
                              },
                            )
                          : _buildDefaultProfileImage(),
                ),
              ),
                      // Overlay di caricamento (solo quando sta caricando)
                      if (_isUploadingImage && _isOwner)
                        Container(
                  width: 120,
                  height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                          ),
                                  child: Center(
                                    child: SizedBox(
                              width: 24,
                              height: 24,
                                      child: CircularProgressIndicator(
                                strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
          
          // Informazioni utente sotto l'immagine profilo (centrate e più in alto)
          Positioned(
            bottom: 117, // Aggiunto 37 pixel (circa 1 cm) più in alto
            left: 20,
            right: 20,
            child: Column(
              children: [
                // Nome utente
                Text(
                  _displayNameController.text.isNotEmpty 
                      ? _displayNameController.text 
                      : 'Nome Utente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.7),
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                // Posizione (mostra solo se l'utente ha inserito una posizione)
                if (_locationController.text.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on, color: Colors.white.withOpacity(0.8), size: 16),
                    SizedBox(width: 4),
                    Text(
                        _locationController.text,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.7),
                            offset: Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // Avatar social degli amici
                _buildFriendsAvatars(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDefaultCoverImage() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      height: 388 + statusBarHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        child: Image.asset(
          'assets/wallpaper.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback al gradiente originale se l'immagine non carica
            return Container(
              decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF8A65), // Arancione per il cielo
            Color(0xFFFF7043), // Arancione più scuro
            Color(0xFF5D4037), // Marrone per le montagne
            Color(0xFF3E2723), // Marrone scuro per le montagne
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Silhouette delle montagne
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(double.infinity, 100),
              painter: MountainPainter(),
            ),
          ),
        ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildDefaultProfileImage() {
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
        size: 60,
        color: Colors.white,
      ),
    );
  }
  
  Widget _buildEditInfoButton(ThemeData theme) {
    if (!_isOwner) {
      return Container(); // Non mostrare il pulsante se non si è il proprietario
    }
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showEditInfoBottomSheet,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6C63FF),
                      const Color(0xFF8B7CF6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modifica Informazioni',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.titleLarge?.color,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Username, bio, privacy e impostazioni',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showEditInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          'Edit Information',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.titleLarge?.color,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildBasicInfoSection(Theme.of(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildProfileStatsSection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    

    
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
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
          child: Row(
        children: [
          // Prima colonna - Video count
          Expanded(
            child: _shouldShowVideoCount() 
              ? _buildStatItem(Icons.video_library, 'Post', _totalVideos.toString())
              : _buildLockedStatItem(Icons.video_library, 'Post'),
          ),
          // Linea divisoria
          Container(
            width: 1,
            height: 40,
            color: isDark ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.3),
          ),
          // Seconda colonna - Like count
          Expanded(
            child: _shouldShowLikeCount() 
              ? _buildStatItem(Icons.favorite, 'Likes', _totalLikes.toString())
              : _buildLockedStatItem(Icons.favorite, 'Likes'),
          ),
          // Linea divisoria
          Container(
            width: 1,
            height: 40,
            color: isDark ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.3),
          ),
          // Terza colonna - Commenti
          Expanded(
            child: _shouldShowCommentCount() 
              ? _buildStatItem(Icons.comment, 'Comments', _totalComments.toString())
              : _buildLockedStatItem(Icons.comment, 'Comments'),
          ),
        ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: const Color(0xFF6C63FF),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLockedStatItem(IconData icon, String label) {
    return Column(
      children: [
        Icon(
          Icons.lock,
          color: Colors.grey[400],
          size: 24,
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  Widget _buildBasicInfoSection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Username
          _buildUsernameField(),
          
          SizedBox(height: 16),
          
          // Display Name
          _buildTextField(
            controller: _displayNameController,
            label: 'Display Name',
            hint: 'Enter your name',
            icon: Icons.person,
            maxLength: 15,
          ),
          
          SizedBox(height: 16),
          
          // Location
          _buildTextField(
            controller: _locationController,
            label: 'Location (optional)',
            hint: 'e.g. San Francisco, CA',
            icon: Icons.location_on,
          ),
          
          SizedBox(height: 190), // Aumentato da 64 a 94 (+30 pixel aggiuntivi)
          
          // Pulsante per tutte le impostazioni
          Container(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Chiudi la tendina corrente
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(),
                  ),
                );
              },
              icon: Icon(Icons.settings, color: const Color(0xFF6C63FF)),
              label: Text(
                'All Settings',
                style: TextStyle(
                  color: const Color(0xFF6C63FF),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                side: BorderSide(color: const Color(0xFF6C63FF)),
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Username',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _usernameController,
          maxLength: 15,
          onChanged: (value) {
            // Aggiorna immediatamente lo stato per mostrare i messaggi
            setState(() {});
            // Controlla la disponibilità dell'username ad ogni lettera
            _checkUsernameAvailability(value);
          },
          decoration: InputDecoration(
            hintText: 'Enter your username',
            prefixIcon: Icon(Icons.alternate_email, color: const Color(0xFF6C63FF)),
            suffixIcon: _usernameController.text.isNotEmpty
                ? Icon(
                    _isUsernameAvailable ? Icons.check_circle : Icons.error,
                    color: _isUsernameAvailable ? Colors.green : Colors.red,
                    size: 20,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _usernameController.text.isNotEmpty && !_isUsernameAvailable
                    ? Colors.red
                    : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _usernameController.text.isNotEmpty && !_isUsernameAvailable
                    ? Colors.red
                    : const Color(0xFF6C63FF),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.red,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[800] 
                : Colors.grey[50],
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // Contatore personalizzato che include i messaggi di validazione
            counterText: '', // Nasconde il contatore predefinito
          ),
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
            return Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Messaggio di validazione a sinistra
                  Expanded(
                    child: _usernameController.text.isNotEmpty
                        ? Row(
                            children: [
                              if (_isCheckingUsername)
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF6C63FF)),
                                  ),
                                )
                              else
                                Icon(
                                  _isUsernameAvailable ? Icons.check_circle_outline : Icons.error_outline,
                                  color: _isUsernameAvailable ? Colors.green : Colors.red,
                                  size: 14,
                                ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isCheckingUsername 
                                      ? 'Checking...'
                                      : (_isUsernameAvailable ? 'Username available' : _usernameErrorMessage),
                                  style: TextStyle(
                                    color: _isCheckingUsername 
                                        ? const Color(0xFF6C63FF)
                                        : (_isUsernameAvailable ? Colors.green : Colors.red),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : SizedBox.shrink(),
                  ),
                  // Contatore caratteri a destra
                  Text(
                    '$currentLength/${maxLength ?? 15}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF6C63FF)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF6C63FF), width: 2),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[800] 
                : Colors.grey[50],
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // Nasconde il contatore di caratteri se maxLength è specificato
            counterText: maxLength != null ? '' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildTopVideosSection(ThemeData theme) {
    // Controlla se mostrare i video privati
    if (!_shouldShowPrivateStats()) {
      // Se il profilo è privato e l'utente corrente non è amico, non mostrare nulla
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.only(top: 0), // Ridotto da 10 a 0 per avvicinare alle statistiche
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo minimale per "Top 5 Most Liked"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Center(
              child: ShaderMask(
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
                        'Top 3 Most Liked',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                    fontSize: 20,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          
          // Mostra loading o lista dei video top
          if (_isLoadingTopVideos)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF6C63FF)),
              ),
            )
          else if (_topVideos.isEmpty)
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.video_library_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No posts published',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 480, // Aumentato da 420 a 480
              child: Column(
                children: [
                  // PageView per i video
                  Expanded(
                    child: PageView.builder(
                      controller: _videoPageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentVideoPage = index;
                        });
                        // Gestisci l'autoplay quando cambia la pagina
                        _handlePageChange(index);
                      },
                      padEnds: true,
                      itemCount: _topVideos.length,
                      itemBuilder: (context, index) {
                        final video = _topVideos[index];
                        return _buildHorizontalVideoCard(theme, video);
                      },
                    ),
                  ),
                  // Indicatori di pagina
                  if (_topVideos.length > 1)
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _topVideos.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: _currentVideoPage == index ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: _currentVideoPage == index
                                  ? const Color(0xFF6C63FF)
                                  : Colors.grey.withOpacity(0.4),
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
    );
  }

  Widget _buildRecentPostsSection(ThemeData theme) {
    // Controlla se mostrare i post privati
    if (!_shouldShowPrivateStats()) {
      // Se il profilo è privato e l'utente corrente non è amico, non mostrare nulla
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo minimale per "Recent Updates"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Center(
              child: ShaderMask(
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
                        'Recent Updates',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                    fontSize: 20,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          
          // Mostra loading o lista dei post recenti
          if (_isLoadingRecentPosts)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF00BFA6)),
              ),
            )
          else if (_recentPosts.isEmpty)
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.post_add_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No recent posts',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 480, // Stessa altezza della sezione top videos
              child: Column(
                children: [
                  // PageView per i post recenti
                  Expanded(
                    child: PageView.builder(
                      controller: _recentPostsPageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentRecentPostPage = index;
                        });
                        // Gestisci l'autoplay quando cambia la pagina
                        _handleRecentPostPageChange(index);
                      },
                      padEnds: true,
                      itemCount: _recentPosts.length,
                      itemBuilder: (context, index) {
                        final post = _recentPosts[index];
                        return _buildHorizontalRecentPostCard(theme, post);
                      },
                    ),
                  ),
                  // Indicatori di pagina
                  if (_recentPosts.length > 1)
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _recentPosts.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: _currentRecentPostPage == index ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                                                          color: _currentRecentPostPage == index
                                ? const Color(0xFF00BFA6)
                                : Colors.grey.withOpacity(0.4),
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
    );
  }

  Widget _buildRecentPostCard(ThemeData theme, Map<String, dynamic> post, int index) {
    final String postId = post['id'] ?? '';
    final String title = post['title'] ?? '';
    final String description = post['description'] ?? '';
    final List<String> platforms = List<String>.from(post['platforms'] ?? []);
    final int timestamp = post['sort_timestamp'] ?? 0;
    
    // Determina se è un post del nuovo formato
    final bool isNewFormat = postId.contains(_targetUserId);
    
    // Ottieni l'URL del thumbnail
    String thumbnailUrl = '';
    if (isNewFormat) {
      // Per il nuovo formato: usa media_url
      thumbnailUrl = post['media_url'] ?? '';
    } else {
      // Per il vecchio formato: usa thumbnail_path o thumbnail_cloudflare_url
      thumbnailUrl = post['thumbnail_path'] ?? post['thumbnail_cloudflare_url'] ?? '';
    }
    
    // Formatta la data
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final formattedDate = _formatDateRelative(date);
    
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[300],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumbnailUrl.isNotEmpty
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildPostPlaceholder();
                        },
                      )
                    : _buildPostPlaceholder(),
              ),
            ),
            SizedBox(width: 16),
            
            // Informazioni del post
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titolo
                  Text(
                    title.isNotEmpty ? title : 'Post senza titolo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleMedium?.color,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  
                  // Descrizione
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  
                  SizedBox(height: 8),
                  
                  // Piattaforme e data
                  Row(
                    children: [
                      // Piattaforme
                      if (platforms.isNotEmpty) ...[
                        ...platforms.take(3).map((platform) => Container(
                          margin: EdgeInsets.only(right: 4),
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPlatformColor(platform),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            platform.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )),
                        if (platforms.length > 3)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${platforms.length - 3}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Spacer(),
                      ],
                      
                      // Data
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
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
  }
  Widget _buildHorizontalRecentPostCard(ThemeData theme, Map<String, dynamic> post) {
    final String postId = post['id'] ?? '';
    final String title = post['title'] ?? '';
    final String description = post['description'] ?? '';
    final List<String> platforms = List<String>.from(post['platforms'] ?? []);
    final int timestamp = post['sort_timestamp'] ?? 0;
    
    // Determina se è un post del nuovo formato
    final bool isNewFormat = postId.contains(_targetUserId);
    
    // Ottieni l'URL del thumbnail
    String thumbnailUrl = '';
    // Ottieni anche l'URL media per determinare se è una foto
    String videoUrl = '';
    if (isNewFormat) {
      // Per il nuovo formato: usa media_url
      thumbnailUrl = post['media_url'] ?? '';
      videoUrl = post['media_url'] ?? '';
    } else {
      // Per il vecchio formato: usa thumbnail_path o thumbnail_cloudflare_url
      thumbnailUrl = post['thumbnail_path'] ?? post['thumbnail_cloudflare_url'] ?? '';
      videoUrl = post['video_path'] ?? post['cloudflare_url'] ?? '';
    }
    // Determina se il post è una immagine per mostrare il badge foto
    final List<String> carouselMediaUrls = _getCarouselMediaUrls(Map<String, dynamic>.from(post));
    final bool isPhotoMedia = _isPhotoMedia(videoUrl, thumbnailUrl, Map<String, dynamic>.from(post), carouselMediaUrls: carouselMediaUrls);
    
    // Formatta la data
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final formattedDate = _formatDateRelative(date);
    
    return Container(
      width: 200,
      margin: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Thumbnail/Video
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black, // Sfondo nero per i bordi
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildRecentPostContent(postId, thumbnailUrl),
            ),
          ),
          if (isPhotoMedia)
            Positioned(
              top: 8,
              right: 8,
              child: _buildPhotoBadge(),
            ),
          
          // Pulsante commenti sotto alla stella
          Positioned(
            top: 50,
            right: 8,
            child: GestureDetector(
              onTap: () => _handleVideoComment(post),
              child: FutureBuilder<int>(
                future: _getCommentsCount(postId, _targetUserId),
                builder: (context, snapshot) {
                  final commentCount = snapshot.data ?? 0;
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
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
                          size: 16,
                        ),
                        SizedBox(height: 1),
                        // Numero commenti
                        Text(
                          '${commentCount}',
                          style: TextStyle(
                            fontSize: 10,
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
          
          // Pulsante menu (tre puntini)
          Positioned(
            top: 100,
            right: 8,
            child: GestureDetector(
              onTap: () => _showVideoOptions(post),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
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
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Pulsante stella in alto a destra
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _handleVideoStar(post),
              child: AnimatedBuilder(
                animation: _starAnimationControllers[postId] ?? const AlwaysStoppedAnimation(1.0),
                builder: (context, child) {
                  final scaleAnimation = _starScaleAnimations[postId];
                  final rotationAnimation = _starRotationAnimations[postId];
                  
                  return Transform.scale(
                    scale: scaleAnimation?.value ?? 1.0,
                    child: Transform.rotate(
                      angle: rotationAnimation?.value ?? 0.0,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _isVideoStarredByCurrentUser(post)
                            ? ShaderMask(
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
                                  Icons.star,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              )
                            : Icon(
                                Icons.star_border,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Overlay con informazioni
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titolo
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  SizedBox(height: 4),
                  
                  // Piattaforme
                  if (platforms.isNotEmpty)
                    Row(
                      children: [
                        ...platforms.take(2).map((platform) => Container(
                          margin: EdgeInsets.only(right: 4),
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPlatformColor(platform),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            platform.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )),
                        if (platforms.length > 2)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${platforms.length - 2}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  
                  SizedBox(height: 4),
                  
                  // Data
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  // Progress bar sotto alla data (solo se la durata del video è valida > 0)
                  Builder(
                    builder: (_) {
                      final controller = _videoControllers[postId];
                      if (controller == null) return const SizedBox.shrink();
                      final durationMs = controller.value.duration?.inMilliseconds ?? 0;
                      if (durationMs <= 0) {
                        // Nessuna durata valida: non mostrare la progress bar
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          const SizedBox(height: 6),
                          SizedBox(
                        height: 18,
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: controller,
                          builder: (context, value, child) {
                                final currentPosition =
                                    value.position.inMilliseconds.toDouble();
                                final videoDuration =
                                    value.duration?.inMilliseconds.toDouble() ?? 0.0;
                                if (videoDuration <= 0) {
                                  return const SizedBox.shrink();
                                }
                                final clampedValue =
                                    currentPosition.clamp(0.0, videoDuration);
                            return Row(
                              children: [
                                // Minutaggio corrente (sinistra)
                                Text(
                                      _formatDuration(Duration(
                                          milliseconds: currentPosition.toInt())),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white.withOpacity(0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                // Progress bar al centro
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                  enabledThumbRadius: 0),
                                          trackHeight:
                                              (_isProgressBarInteracting[postId] ==
                                                      true)
                                                  ? 12
                                                  : 6,
                                      activeTrackColor: Colors.white,
                                          inactiveTrackColor:
                                              Colors.white.withOpacity(0.3),
                                      thumbColor: Colors.transparent,
                                      overlayColor: Colors.transparent,
                                          trackShape:
                                              const RoundedRectSliderTrackShape(),
                                    ),
                                    child: Slider(
                                      value: clampedValue,
                                      min: 0.0,
                                          max: videoDuration,
                                      onChanged: (v) {
                                            controller.seekTo(Duration(
                                                milliseconds: v.toInt()));
                                            setState(() {
                                              _isProgressBarInteracting[postId] =
                                                  true;
                                            });
                                      },
                                      onChangeEnd: (v) {
                                            setState(() {
                                              _isProgressBarInteracting[postId] =
                                                  false;
                                            });
                                      },
                                    ),
                                  ),
                                ),
                                // Minutaggio totale (destra)
                                Text(
                                      _formatDuration(Duration(
                                          milliseconds: videoDuration.toInt())),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white.withOpacity(0.8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          },
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
        ],
      ),
    );
  }

  Widget _buildRecentPostContent(String postId, String thumbnailUrl) {
    // Determina se è un post del nuovo formato
    final bool isNewFormat = postId.contains(_targetUserId);
    
    // Ottieni l'URL del video
    String videoUrl = '';
    if (isNewFormat) {
      // Per il nuovo formato: usa media_url
      videoUrl = thumbnailUrl; // Per i post recenti, media_url è il video
    } else {
      // Per il vecchio formato: usa video_path o cloudflare_url
      videoUrl = thumbnailUrl; // Per i post recenti, thumbnailUrl potrebbe essere il video
    }
    
    final controller = _videoControllers[postId];
    final isInitialized = _videoInitialized[postId] == true;
    
    if (videoUrl.isNotEmpty && controller != null && isInitialized) {
      // Per tutti i video, usa Center e AspectRatio per rispettare il rapporto corretto
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Sfondo nero per i bordi
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showVideoControls[postId] = !(_showVideoControls[postId] ?? false);
                });
                // Nascondi i controlli dopo 3 secondi se il video sta riproducendo
                if (controller.value.isPlaying) {
                  Future.delayed(Duration(seconds: 3), () {
                    if (mounted) {
                      setState(() {
                        _showVideoControls[postId] = false;
                      });
                    }
                  });
                }
              },
              child: Stack(
                children: [
                  VideoPlayer(controller),
                  // Controlli play/pause overlay
                  if (_showVideoControls[postId] == true)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showVideoControls[postId] = false;
                      });
                      // Nascondi i controlli dopo 3 secondi se il video sta riproducendo
                      if (controller.value.isPlaying) {
                        Future.delayed(Duration(seconds: 3), () {
                          if (mounted) {
                            setState(() {
                              _showVideoControls[postId] = false;
                            });
                          }
                        });
                      }
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: IconButton(
                            icon: Icon(
                              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                            padding: EdgeInsets.all(8),
                            onPressed: () {
                              _toggleVideoPlayback(controller);
                            },
                          ),
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
      // Mostra il thumbnail come fallback
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Sfondo nero per i bordi
        child: Center(
          child: Image.network(
            thumbnailUrl,
            fit: BoxFit.contain, // Mantiene il rapporto d'aspetto originale
            errorBuilder: (context, error, stackTrace) {
              return _buildPostPlaceholder();
            },
          ),
        ),
      );
    } else {
      // Mostra placeholder se non c'è né video né thumbnail
      return _buildPostPlaceholder();
    }
  }

  Widget _buildPostPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00BFA6),
            const Color(0xFF00D4A6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.post_add,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Colors.red;
      case 'instagram':
        return Color(0xFFE4405F);
      case 'facebook':
        return Color(0xFF1877F2);
      case 'twitter':
        return Color(0xFF1DA1F2);
      case 'tiktok':
        return Color(0xFF000000);
      case 'threads':
        return Color(0xFF000000);
      default:
        return Colors.grey;
    }
  }
  
  Widget _buildHorizontalVideoCard(ThemeData theme, Map<String, dynamic> video) {
    // Ottieni i dati del video
    final String videoId = video['id'] ?? '';
    final int totalLikes = video['total_likes'] ?? 0;
    
    // Dati per l'overlay
    final String title = video['title'] ?? video['description'] ?? '';
    final List<String> platforms = List<String>.from(video['platforms'] ?? []);
    final String formattedDate = _formatVideoDate(video);
    
    // Determina se è un video con formato diverso (ha l'ID dell'utente nel suo ID)
    final bool isNewFormat = videoId.contains(_targetUserId);
    
    // Ottieni l'URL del thumbnail in base al formato
    String thumbnailUrl = '';
    String videoUrl = '';
    if (isNewFormat) {
      // Per il nuovo formato: privilegia thumbnail_url se presente, altrimenti media_url
      thumbnailUrl = video['thumbnail_url'] ?? video['media_url'] ?? '';
      videoUrl = video['media_url'] ?? '';
    } else {
      // Per il vecchio formato: usa thumbnail_path o thumbnail_cloudflare_url
      thumbnailUrl = video['thumbnail_path'] ?? video['thumbnail_cloudflare_url'] ?? video['thumbnail_url'] ?? '';
      videoUrl = video['video_path'] ?? video['cloudflare_url'] ?? '';
    }
    final List<String> carouselMediaUrls = _getCarouselMediaUrls(video);
    final bool hasCarouselMedia = carouselMediaUrls.isNotEmpty;
    final bool isPhotoMedia = _isPhotoMedia(videoUrl, thumbnailUrl, video, carouselMediaUrls: carouselMediaUrls);
    
    // Debug prints rimossi per evitare flood di log
    final double starTop = isPhotoMedia ? 48 : 8;
    final double commentTop = isPhotoMedia ? 90 : 50;
    final double menuTop = isPhotoMedia ? 140 : 100;
    final bool showVideoProgress = !hasCarouselMedia && !isPhotoMedia;
    final Widget mediaContent = hasCarouselMedia
        ? _buildCarouselMediaViewer(videoId, carouselMediaUrls)
        : isPhotoMedia
            ? _buildPhotoMedia(thumbnailUrl, videoUrl)
            : _buildVideoContent(videoId, videoUrl, thumbnailUrl);
    
    return Container(
      width: 200,
      margin: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Video player o thumbnail
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: mediaContent,
            ),
          ),
          if (isPhotoMedia)
          Positioned(
            top: 8,
            right: 8,
            child: _buildPhotoBadge(),
          ),
          
          
          // Pulsante stella in alto a destra (solo se visibile)
          if (_shouldShowPrivateStats())
          Positioned(
            top: starTop,
            right: 8,
            child: GestureDetector(
              onTap: () => _handleVideoStar(video),
              child: AnimatedBuilder(
                animation: _starAnimationControllers[videoId] ?? const AlwaysStoppedAnimation(1.0),
                builder: (context, child) {
                  final scaleAnimation = _starScaleAnimations[videoId];
                  final rotationAnimation = _starRotationAnimations[videoId];
                  
                  return Transform.scale(
                    scale: scaleAnimation?.value ?? 1.0,
                    child: Transform.rotate(
                      angle: rotationAnimation?.value ?? 0.0,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _isVideoStarredByCurrentUser(video)
                            ? ShaderMask(
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
                                  Icons.star,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              )
                            : Icon(
                                Icons.star_border,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Pulsante commenti sotto alla stella
          Positioned(
            top: commentTop,
            right: 8,
                          child: GestureDetector(
                onTap: () => _handleVideoComment(video),
                child: FutureBuilder<int>(
                  future: _getCommentsCount(videoId, _targetUserId),
                  builder: (context, snapshot) {
                    final commentCount = snapshot.data ?? 0;
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
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
                            size: 16,
                          ),
                          SizedBox(height: 1),
                          // Numero commenti
                          Text(
                            '${commentCount}',
                            style: TextStyle(
                              fontSize: 10,
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
          
          // Pulsante menu (tre puntini)
          Positioned(
            top: menuTop,
            right: 8,
            child: GestureDetector(
              onTap: () => _showVideoOptions(video),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
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
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Overlay con informazioni
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titolo
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  SizedBox(height: 4),
                  
                  // Piattaforme
                  if (platforms.isNotEmpty)
                    Row(
                      children: [
                        ...platforms.take(2).map((platform) => Container(
                          margin: EdgeInsets.only(right: 4),
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPlatformColor(platform),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            platform.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )),
                        if (platforms.length > 2)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${platforms.length - 2}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  
                  SizedBox(height: 4),
                  
                  // Data
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  // Progress bar sotto alla data
                  SizedBox(height: 6),
                  if (showVideoProgress)
                    Builder(
                      builder: (_) {
                        final controller = _videoControllers[videoId];
                        if (controller == null) return SizedBox.shrink();
                        return SizedBox(
                          height: 18,
                          child: ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: controller,
                            builder: (context, value, child) {
                              final currentPosition = value.position.inMilliseconds.toDouble();
                              final videoDuration = value.duration?.inMilliseconds.toDouble() ?? 1.0;
                              if (videoDuration <= 0) {
                                // Nessuna durata valida: non mostrare la progress bar
                                return const SizedBox.shrink();
                              }
                              final clampedValue = currentPosition.clamp(0.0, videoDuration);
                              return Row(
                                children: [
                                  // Minutaggio corrente (sinistra)
                                  Text(
                                    _formatDuration(Duration(milliseconds: currentPosition.toInt())),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  // Progress bar al centro
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                                        trackHeight: (_isProgressBarInteracting[videoId] == true) ? 12 : 6,
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                                        thumbColor: Colors.transparent,
                                        overlayColor: Colors.transparent,
                                          trackShape: const RoundedRectSliderTrackShape(),
                                      ),
                                      child: Slider(
                                        value: clampedValue,
                                        min: 0.0,
                                          max: videoDuration,
                                        onChanged: (v) {
                                          controller.seekTo(Duration(milliseconds: v.toInt()));
                                          setState(() { _isProgressBarInteracting[videoId] = true; });
                                        },
                                        onChangeEnd: (v) {
                                          setState(() { _isProgressBarInteracting[videoId] = false; });
                                        },
                                      ),
                                    ),
                                  ),
                                  // Minutaggio totale (destra)
                                  Text(
                                    _formatDuration(Duration(milliseconds: videoDuration.toInt())),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getCarouselMediaUrls(Map<String, dynamic> video) {
    final urls = <String>[];
    final seen = <String>{};

    void addUrl(String? rawUrl) {
      if (rawUrl == null) return;
      final normalized = rawUrl.trim();
      if (normalized.isEmpty) return;
      if (seen.add(normalized)) {
        urls.add(normalized);
      }
    }

    void extract(dynamic source) {
      if (source == null) return;
      if (source is List) {
        for (final item in source) {
          extract(item);
        }
      } else if (source is Map) {
        source.values.forEach(extract);
      } else if (source is String) {
        addUrl(source);
      } else {
        addUrl(source.toString());
      }
    }

    extract(video['cloudflare_urls']);

    if (urls.isEmpty) {
      extract(video['media_urls']);
    }
    if (urls.isEmpty) {
      extract(video['media']);
    }

    return urls;
  }

  Widget _buildCarouselMediaViewer(String videoId, List<String> mediaUrls) {
    if (mediaUrls.isEmpty) {
      return _buildVideoPlaceholder();
    }

    final int itemCount = mediaUrls.length;
    final int storedIndex = _mediaCarouselIndexes[videoId] ?? 0;
    final int safeIndex = _clampCarouselIndex(storedIndex, itemCount);
    _mediaCarouselIndexes[videoId] = safeIndex;

    final controller = _mediaCarouselControllers.putIfAbsent(
      videoId,
      () => PageController(initialPage: safeIndex),
    );

    if (controller.hasClients) {
      final currentPage = controller.page?.round() ?? controller.initialPage;
      if (currentPage != safeIndex) {
        controller.jumpToPage(safeIndex);
      }
    }

    final int currentIndex = _mediaCarouselIndexes[videoId] ?? 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: controller,
          physics: const BouncingScrollPhysics(),
          itemCount: itemCount,
          onPageChanged: (index) {
            final previousIndex = _mediaCarouselIndexes[videoId] ?? 0;
            if (previousIndex != index) {
              _pauseCarouselVideo(videoId, previousIndex);
            }
            setState(() {
              _mediaCarouselIndexes[videoId] = index;
            });
          },
          itemBuilder: (context, index) {
            final mediaUrl = mediaUrls[index];
            if (_isImageUrl(mediaUrl)) {
              return _buildCarouselImageItem(mediaUrl);
            }
            return _buildCarouselVideoItem(videoId, index, mediaUrl);
          },
        ),
        if (itemCount > 1)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${currentIndex + 1}/$itemCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (itemCount > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                itemCount,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: currentIndex == index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: currentIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCarouselImageItem(String mediaUrl) {
    return Container(
      color: Colors.black,
      child: Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildVideoPlaceholder(),
      ),
    );
  }

  Widget _buildCarouselVideoItem(String videoId, int index, String mediaUrl) {
    final controllerKey = _carouselVideoControllerKey(videoId, index);
    VideoPlayerController? controller = _carouselVideoControllers[controllerKey];

    if (controller == null) {
      controller = VideoPlayerController.network(mediaUrl);
      _carouselVideoControllers[controllerKey] = controller;
      _carouselVideoInitialized[controllerKey] = false;
      _carouselVideoPlaying[controllerKey] = false;

      controller
        ..setLooping(true)
        ..setVolume(0.0);

      controller.initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _carouselVideoInitialized[controllerKey] = true;
        });
      }).catchError((error) {
        // Error initializing carousel video – ignore
      });
    }

    final bool isInitialized = _carouselVideoInitialized[controllerKey] ?? false;
    final bool isPlaying = _carouselVideoPlaying[controllerKey] ?? false;

    return GestureDetector(
      onTap: () => _toggleCarouselVideoPlayback(controllerKey),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller!.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
          ),
          AnimatedOpacity(
            opacity: isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _carouselVideoControllerKey(String videoId, int index) => '${videoId}_carousel_$index';

  int _clampCarouselIndex(int index, int length) {
    if (length <= 0) return 0;
    if (index < 0) return 0;
    if (index >= length) return length - 1;
    return index;
  }

  void _toggleCarouselVideoPlayback(String controllerKey) {
    final controller = _carouselVideoControllers[controllerKey];
    if (controller == null || !(_carouselVideoInitialized[controllerKey] ?? false)) {
      return;
    }

    final bool isPlaying = _carouselVideoPlaying[controllerKey] ?? false;

    if (isPlaying) {
      controller.pause();
      setState(() {
        _carouselVideoPlaying[controllerKey] = false;
      });
    } else {
      _pauseAllCarouselVideos(triggerRebuild: false);
      controller.play();
      setState(() {
        _carouselVideoPlaying[controllerKey] = true;
      });
    }
  }

  void _pauseCarouselVideo(String videoId, int index) {
    final key = _carouselVideoControllerKey(videoId, index);
    final controller = _carouselVideoControllers[key];
    if (controller != null && controller.value.isPlaying) {
      controller.pause();
      _carouselVideoPlaying[key] = false;
    }
  }

  void _pauseAllCarouselVideos({bool triggerRebuild = true}) {
    bool shouldUpdate = false;
    _carouselVideoControllers.forEach((key, controller) {
      if (controller.value.isPlaying) {
        controller.pause();
        _carouselVideoPlaying[key] = false;
        shouldUpdate = true;
      }
    });
    if (shouldUpdate && triggerRebuild && mounted) {
      setState(() {});
    }
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp'];
    return imageExtensions.any((ext) => lower.endsWith(ext));
  }
  Widget _buildPhotoMedia(String primaryUrl, String fallbackUrl) {
    final displayUrl = primaryUrl.isNotEmpty ? primaryUrl : fallbackUrl;
    if (displayUrl.isEmpty) {
      return _buildVideoPlaceholder();
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Image.network(
        displayUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildVideoPlaceholder();
        },
      ),
    );
  }

  Widget _buildVideoContent(String videoId, String videoUrl, String thumbnailUrl) {
    final controller = _videoControllers[videoId];
    final isInitialized = _videoInitialized[videoId] == true;
    
    if (videoUrl.isNotEmpty && controller != null && isInitialized) {
      // Per tutti i video, usa Center e AspectRatio per rispettare il rapporto corretto
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Sfondo nero per i bordi
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showVideoControls[videoId] = !(_showVideoControls[videoId] ?? false);
                });
                // Nascondi i controlli dopo 3 secondi se il video sta riproducendo
                if (controller.value.isPlaying) {
                  Future.delayed(Duration(seconds: 3), () {
                    if (mounted) {
                      setState(() {
                        _showVideoControls[videoId] = false;
                      });
                    }
                  });
                }
              },
              child: Stack(
                children: [
                  VideoPlayer(controller),
                  // Controlli play/pause overlay
                  if (_showVideoControls[videoId] == true)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showVideoControls[videoId] = false;
                      });
                      // Nascondi i controlli dopo 3 secondi se il video sta riproducendo
                      if (controller.value.isPlaying) {
                        Future.delayed(Duration(seconds: 3), () {
                          if (mounted) {
                            setState(() {
                              _showVideoControls[videoId] = false;
                            });
                          }
                        });
                      }
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: IconButton(
                            icon: Icon(
                              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                            padding: EdgeInsets.all(8),
                            onPressed: () {
                              _toggleVideoPlayback(controller);
                            },
                          ),
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
      // Mostra il thumbnail come fallback
      return Image.network(
        thumbnailUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildVideoPlaceholder();
        },
      );
    } else {
      // Mostra placeholder se non c'è né video né thumbnail
      return _buildVideoPlaceholder();
    }
  }
  
  Widget _buildVideoPlaceholder() {
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
        Icons.play_arrow,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildPhotoBadge() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.photo_outlined,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  bool _isPhotoMedia(String videoUrl, String thumbnailUrl, Map<String, dynamic> media, {List<String>? carouselMediaUrls}) {
    if (_isTruthy(media['is_image']) || _isTruthy(media['is_photo'])) {
      return true;
    }

    final dynamic mediaTypeRaw = media['media_type'] ?? media['mediaType'] ?? media['type'];
    final String mediaType = mediaTypeRaw?.toString().toLowerCase() ?? '';
    if (mediaType.contains('image') || mediaType.contains('photo')) {
      return true;
    }

    List<String> inferredCarouselUrls = carouselMediaUrls ?? const [];
    if (inferredCarouselUrls.isEmpty) {
      inferredCarouselUrls = _getCarouselMediaUrls(Map<String, dynamic>.from(media));
    }

    if (inferredCarouselUrls.isNotEmpty && inferredCarouselUrls.every(_isImageUrl)) {
      return true;
    }

    final String lowerVideoUrl = videoUrl.toLowerCase();
    final String lowerThumbnailUrl = thumbnailUrl.toLowerCase();
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp'];

    bool hasImageExtension(String url) {
      if (url.isEmpty) return false;
      return imageExtensions.any((ext) => url.endsWith(ext));
    }

    if (hasImageExtension(lowerVideoUrl)) {
      return true;
    }

    if (lowerVideoUrl.isEmpty && hasImageExtension(lowerThumbnailUrl)) {
      return true;
    }

    return false;
  }
  
  Widget _buildViralystScoreFixed(ThemeData theme) {
                    // Controlla se mostrare il Fluzar Score
    if (!_shouldShowPrivateStats()) {
      return GestureDetector(
        onTap: _showViralystScoreInfo,
        child: Container(
          width: 100, // Aumentato da 80 a 100
          height: 100, // Aumentato da 80 a 100
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: AssetImage('assets/onboarding/circleICON.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.lock,
                color: Colors.black,
                size: 24, // Aumentato da 16 a 24
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _showViralystScoreInfo,
      child: AnimatedBuilder(
        animation: _scoreAnimation,
        builder: (context, child) {
          return Container(
            width: 80, // Aumentato da 60 a 80
            height: 80, // Aumentato da 60 a 80
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/onboarding/circleICON.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Center(
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
                    _abbreviateNumber(_scoreAnimation.value.toInt()),
                    style: TextStyle(
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.purple,
                      fontSize: 19, // Ridotto da 22 a 16
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriendRequestButton(ThemeData theme) {
    return GestureDetector(
      onTap: _sendFriendRequest,
      child: Container(
        width: 60, // Ridotto da 80 a 60
        height: 60, // Ridotto da 80 a 60
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6C63FF),
              const Color(0xFFFF6B6B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.4),
              blurRadius: 10, // Ridotto da 15 a 10
              offset: Offset(0, 6), // Ridotto da 8 a 6
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_add,
                color: Colors.white,
                size: 16, // Ridotto da 20 a 16
              ),
              Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8, // Ridotto da 10 a 8
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequestButton(ThemeData theme) {
    return Container(
      width: 60, // Ridotto da 80 a 60
      height: 60, // Ridotto da 80 a 60
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange,
            Colors.orange[700]!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.4),
            blurRadius: 10, // Ridotto da 15 a 10
            offset: Offset(0, 6), // Ridotto da 8 a 6
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule,
              color: Colors.white,
              size: 16, // Ridotto da 20 a 16
            ),
            Text(
              'Pending',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8, // Ridotto da 10 a 8
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptRequestButton(ThemeData theme) {
    return GestureDetector(
      onTap: _acceptFriendRequestFromProfile,
      child: Container(
        width: 60, // Ridotto da 80 a 60
        height: 60, // Ridotto da 80 a 60
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green,
              Colors.green[700]!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.4),
              blurRadius: 10, // Ridotto da 15 a 10
              offset: Offset(0, 6), // Ridotto da 8 a 6
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check,
                color: Colors.white,
                size: 16, // Ridotto da 20 a 16
              ),
              Text(
                'Accept',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8, // Ridotto da 10 a 8
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}m';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
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

  String _formatDateRelative(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 3) {
      // Se supera i 3 giorni, mostra formato gg/mm/anno
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } else if (difference.inDays > 0) {
      // Se supera 1 giorno ma non 3, mostra "X day(s) ago"
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'now';
    }
  }

  String _formatVideoDate(Map<String, dynamic> video) {
    try {
      // Prova diversi campi per la data
      dynamic timestamp = video['created_at'] ?? 
                         video['uploaded_at'] ?? 
                         video['timestamp'] ?? 
                         video['date'];
      
      if (timestamp == null) return '';
      
      DateTime date;
      if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return '';
      }
      
      return _formatDateRelative(date);
    } catch (e) {
      return '';
    }
  }

  void _showViralystScoreInfo() {
    // Se l'utente corrente non è il proprietario della pagina, mostra la versione per visitatori
    if (_currentUser?.uid != _targetUserId) {
      _showViralystScoreInfoForVisitors();
      return;
    }
    
    setState(() {
      _showViralystScorePopup = true;
    });
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Color(0xFF1E1E1E) 
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icona Fluzar Score
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Color(0xFF667eea).withOpacity(0.1),
                    backgroundImage: const AssetImage('assets/onboarding/circleICON.png'),
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Titolo
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
                  'Fluzar Score',
                  style: TextStyle(
                      fontSize: 16,
                    fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Ethnocentric',
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Descrizione
                Column(
                  children: [
                    Text(
                      'Your Fluzar Score is a measure of your social media success and consistency',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                
                SizedBox(height: 20),
                
                // Lista dei fattori
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Color(0xFF2A2A2A) 
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildScoreFactor(Icons.video_library, 'Number of videos published'),
                      _buildScoreFactor(Icons.favorite, 'Total likes received'),
                                              _buildScoreFactor(Icons.comment, 'Total comments achieved'),
                      _buildScoreFactor(Icons.schedule, 'Consistency in posting'),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Pulsanti
                Row(
                  children: [
                    // Pulsante per disattivare
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _showViralystScorePopup = false;
                          });
                          _openSettingsPage();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Disable Score',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    
                    SizedBox(width: 12),
                    
                    // Pulsante chiudi
                    Expanded(
                      child: Container(
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _showViralystScorePopup = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                          ),
                          child: Text(
                            'Got it!',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
  }

  void _showViralystScoreInfoForVisitors() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Color(0xFF1E1E1E) 
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icona Fluzar Score
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Color(0xFF667eea).withOpacity(0.1),
                    backgroundImage: const AssetImage('assets/onboarding/circleICON.png'),
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Titolo
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
                  'Fluzar Score',
                  style: TextStyle(
                      fontSize: 12,
                    fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Ethnocentric',
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Descrizione per visitatori
                Text(
                  'The Fluzar Score is a measure of social media success and consistency.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 20),
                
                // Lista dei fattori
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Color(0xFF2A2A2A) 
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildScoreFactor(Icons.video_library, 'Number of videos published'),
                      _buildScoreFactor(Icons.favorite, 'Total likes received'),
                      _buildScoreFactor(Icons.comment, 'Total comments achieved'),
                      _buildScoreFactor(Icons.schedule, 'Consistency in posting'),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Solo pulsante chiudi per visitatori
                Container(
                  width: double.infinity,
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: Text(
                      'Got it!',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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

  Widget _buildScoreFactor(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6), // Ridotto da 8 a 6
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6), // Ridotto da 8 a 6
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6), // Ridotto da 8 a 6
            ),
            child: Icon(
              icon,
              size: 16, // Ridotto da 20 a 16
              color: const Color(0xFF6C63FF),
            ),
          ),
          SizedBox(width: 10), // Ridotto da 12 a 10
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12, // Ridotto da 14 a 12
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(),
      ),
    );
  }
  Widget _buildFriendRequestCard(Map<String, dynamic> request, ThemeData theme, StateSetter? setModalState) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: theme.brightness == Brightness.dark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
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
        children: [
          // Informazioni dell'utente
          GestureDetector(
            onTap: () => _openUserProfile(request['requestId']),
            child: Row(
              children: [
                // Immagine profilo
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: FutureBuilder<String?>(
                      future: _loadUserProfileImage(request['fromUserId'] ?? request['requestId']),
                      builder: (context, snapshot) {
                        final profileImageUrl = snapshot.data;
                        
                        if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
                          return Image.network(
                            profileImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
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
                            },
                          );
                        } else {
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
                      },
                    ),
                  ),
                ),
                SizedBox(width: 12),
                    
                // Informazioni utente
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['fromDisplayName'] ?? 'Unknown User',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.titleMedium?.color,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '@${request['fromUsername'] ?? 'unknown'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Wants to be your friend',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                // Icona per indicare che è cliccabile
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Pulsanti di azione
          Row(
            children: [
              // Accept Button
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptFriendRequest(request, setModalState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Accept',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(width: 12),
              
              // Pulsante Rifiuta
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _declineFriendRequest(request, setModalState),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[600],
                    side: BorderSide(color: Colors.red[300]!),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Decline',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsAvatars() {
    if (_isLoadingFriends) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      );
    }

    if (_friends.isEmpty) {
                      // Nascondi il badge se il popup del Fluzar Score è attivo o se la tendina Edit Information è aperta
      if (_showViralystScorePopup) {
        return SizedBox.shrink();
      }
      
      // Controlla se la tendina Edit Information è aperta (ModalRoute.isCurrent)
      final modalRoute = ModalRoute.of(context);
      if (modalRoute != null && modalRoute.isCurrent == false) {
        return SizedBox.shrink();
      }
      
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              'No friends yet',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    // Prendi i primi 3 amici per mostrare gli avatar
    final visibleFriends = _friends.take(3).toList();
    final remainingCount = _friends.length - 3;

    return GestureDetector(
      onTap: () {
        _showFriendsListModal = true;
        _showFriendsListBottomSheet();
      },
      child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...visibleFriends.asMap().entries.map((entry) {
          final index = entry.key;
          final friend = entry.value;
          final profileImageUrl = friend['profileImageUrl'] ?? '';
          
          return Transform.translate(
            offset: Offset(-8.0 * index, 0),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                image: profileImageUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(profileImageUrl),
                        fit: BoxFit.cover,
                        onError: (exception, stackTrace) {
                          // Fallback a un'icona se l'immagine non carica
                        },
                      )
                    : null,
                color: profileImageUrl.isEmpty ? Colors.grey[300] : null,
              ),
              child: profileImageUrl.isEmpty
                  ? Icon(
                      Icons.person,
                      color: Colors.grey[600],
                      size: 16,
                    )
                  : null,
            ),
          );
        }).toList(),
        
        // Mostra il contatore se ci sono più di 3 amici
        if (remainingCount > 0)
          Transform.translate(
            offset: Offset(-8.0 * visibleFriends.length, 0),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.9),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  '+$remainingCount',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }

  void _showFriendsListBottomSheet() {
    // Reset search when opening the bottom sheet
    _friendsSearchController.clear();
    _friendsSearchFocusNode.unfocus();
    _friendsSearchQuery = '';
    _isSearchExpanded = false;
    
    // Inizializza il controller se non è già stato fatto
    if (!_searchAnimationController.isCompleted && !_searchAnimationController.isAnimating) {
      _searchAnimationController.reset();
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header con search icon animata
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Titolo centrato che scompare quando la search si espande
                    if (!_isSearchExpanded)
                    Expanded(
                      child: Transform.translate(
                        offset: Offset(20, 0),
                        child: Center(
                          child: Text(
                              'Friends ${_friends.length}',
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
                    ),
                    
                    // Search bar che si espande
                    AnimatedContainer(
                      duration: Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: _isSearchExpanded 
                          ? MediaQuery.of(context).size.width - 32 // Larghezza completa meno padding
                          : 40,
                      height: 40,
                      child: _isSearchExpanded
                          ? Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[800] 
                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                                  color: const Color(0xFF6C63FF).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                              child: Center(
                  child: TextField(
                    controller: _friendsSearchController,
                                  focusNode: _friendsSearchFocusNode,
                                  autofocus: false,
                                  textAlignVertical: TextAlignVertical.center,
                    onChanged: (value) {
                      setState(() {
                        _friendsSearchQuery = value;
                      });
                                    setModalState(() {
                        _friendsSearchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search friends...',
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                      prefixIcon: Icon(
                        Icons.search,
                                      color: const Color(0xFF6C63FF),
                                      size: 20,
                      ),
                                    suffixIcon: IconButton(
                              icon: Icon(
                                        Icons.close,
                                color: Colors.grey[600],
                                        size: 20,
                              ),
                              onPressed: () {
                                _friendsSearchController.clear();
                                        _friendsSearchFocusNode.unfocus();
                                setState(() {
                                  _friendsSearchQuery = '';
                                          _isSearchExpanded = false;
                                        });
                                        setModalState(() {
                                          _friendsSearchQuery = '';
                                          _isSearchExpanded = false;
                                });
                              },
                                    ),
                      border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    isDense: true,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            )
                          : Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  setState(() {
                                    _isSearchExpanded = true;
                                  });
                                  setModalState(() {
                                    _isSearchExpanded = true;
                                  });
                                  
                                  // Ritarda l'apertura della tastiera per completare l'animazione
                                  Future.delayed(Duration(milliseconds: 400), () {
                                    if (_isSearchExpanded && mounted) {
                                      _friendsSearchFocusNode.requestFocus();
                                    }
                                  });
                                },
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.grey[800] 
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.search,
                                    color: Colors.grey[600],
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 8),
              
              // Friends list
              Expanded(
                child: _isLoadingFriends
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF6C63FF)),
                        ),
                      )
                    : _friends.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No friends yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Start connecting with other users!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _filteredFriends.isEmpty && _friendsSearchQuery.isNotEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No friends found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Try a different search term',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _filteredFriends.length,
                                itemBuilder: (context, index) {
                                  final friend = _filteredFriends[index];
                              final displayName = friend['displayName'] ?? 'Unknown User';
                              final username = friend['username'] ?? 'unknown';
                              final profileImageUrl = friend['profileImageUrl'] ?? '';
                              final friendshipDate = friend['friendshipDate'] ?? 0;
                              
                              return Container(
                                margin: EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  // Effetto vetro semi-trasparente opaco
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.15) 
                                      : Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(16),
                                  // Bordo con effetto vetro più sottile
                                  border: Border.all(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.4),
                                    width: 1,
                                  ),
                                  // Ombra per effetto profondità e vetro
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.black.withOpacity(0.4)
                                          : Colors.black.withOpacity(0.15),
                                      blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                                      spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                                      offset: const Offset(0, 10),
                                    ),
                                    // Ombra interna per effetto vetro
                                    BoxShadow(
                                      color: Theme.of(context).brightness == Brightness.dark 
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
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      Navigator.pop(context);
                                      // Navigate to friend's profile
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProfileEditPage(
                                            userId: friend['friendId'] ?? friend['uid'],
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          // Profile image
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              image: profileImageUrl.isNotEmpty
                                                  ? DecorationImage(
                                                      image: NetworkImage(profileImageUrl),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : null,
                                              color: profileImageUrl.isEmpty ? Colors.grey[300] : null,
                                            ),
                                            child: profileImageUrl.isEmpty
                                                ? Icon(
                                                    Icons.person,
                                                    color: Colors.grey[600],
                                                    size: 24,
                                                  )
                                                : null,
                                          ),
                                          SizedBox(width: 16),
                                          
                                          // Friend info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  displayName,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).textTheme.titleMedium?.color,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  '@$username',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                if (friendshipDate > 0) ...[
                                                  SizedBox(height: 4),
                                                  Text(
                                                    'Friends since ${_formatFriendshipDate(friendshipDate)}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[500],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          
                                          // Remove friend button (only if current user is the profile owner)
                                          if (_isOwner)
                                            IconButton(
                                              icon: Icon(
                                                Icons.person_remove,
                                                color: Colors.red[400],
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                _removeFriend(
                                                  friend['friendId'] ?? friend['uid'],
                                                  displayName,
                                                  setModalState, // Passa setModalState per aggiornare la tendina
                                                );
                                              },
                                              tooltip: 'Remove Friend',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
          },
        );
      },
    );
  }

  // Metodo per filtrare gli amici in base al testo di ricerca
  List<Map<String, dynamic>> get _filteredFriends {
    if (_friendsSearchQuery.isEmpty) {
      return _friends;
    }
    
    return _friends.where((friend) {
      final displayName = (friend['displayName'] ?? '').toString().toLowerCase();
      final username = (friend['username'] ?? '').toString().toLowerCase();
      final query = _friendsSearchQuery.toLowerCase();
      
      return displayName.contains(query) || username.contains(query);
    }).toList();
  }

  Future<void> _removeFriend(String friendId, String friendDisplayName, [StateSetter? setModalState]) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Mostra dialog di conferma minimal e professionale
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
                // Icona minimal
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_remove_outlined,
                    color: Colors.red[600],
                    size: 32,
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Titolo minimal
              Text(
                'Remove Friend',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 12),
                
                // Messaggio conciso
                Text(
                  'Remove $friendDisplayName from your friends?',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 24),
                
                // Pulsanti minimal
                Row(
                  children: [
                    // Pulsante Cancel
                    Expanded(
                      child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : Colors.black54,
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.grey[300]!,
                            width: 1,
                          ),
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                            fontWeight: FontWeight.w500,
                ),
              ),
            ),
                    ),
                    
                    SizedBox(width: 12),
                    
                    // Pulsante Remove
                    Expanded(
                      child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                ),
                          elevation: 0,
              ),
              child: Text(
                'Remove',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

    if (confirmed != true) return;

    try {
      // Rimuovi l'amico dalla lista del current user
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('profile')
          .child('alreadyfriends')
          .child(friendId)
          .remove();

      // Rimuovi il current user dalla lista dell'amico
      await _database
          .child('users')
          .child('users')
          .child(friendId)
          .child('profile')
          .child('alreadyfriends')
          .child(currentUser.uid)
          .remove();

      // Aggiorna immediatamente la lista locale degli amici
      setState(() {
        _friends.removeWhere((friend) => (friend['friendId'] ?? friend['uid']) == friendId);
      });
      
      // Aggiorna anche la tendina se è aperta
      if (setModalState != null) {
        setModalState(() {
          _friends.removeWhere((friend) => (friend['friendId'] ?? friend['uid']) == friendId);
        });
      }

      // Mostra messaggio di successo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$friendDisplayName removed from friends'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
              // Error removing friend
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing friend. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatFriendshipDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }

  // Metodi per gestire le stelle (copiati da community_page.dart)
  bool _isVideoStarredByCurrentUser(Map<String, dynamic> video) {
    if (_currentUser == null) return false;
    
    final starUsersRaw = video['star_users'];
    if (starUsersRaw == null) return false;
    
    // Gestione robusta per iOS: può arrivare come Map o List
    if (starUsersRaw is Map) {
      final starUsers = Map<String, dynamic>.from(starUsersRaw);
      return starUsers.containsKey(_currentUser!.uid);
    } else if (starUsersRaw is List) {
      // Alcune serializzazioni possono salvare l'elenco di userId come lista
      return starUsersRaw.contains(_currentUser!.uid);
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

  Future<void> _handleVideoStar(Map<String, dynamic> video) async {
    if (_currentUser == null) return;
    
    final videoId = video['id'] as String;
    
    // Se l'utente corrente è il proprietario della pagina, mostra la tendina con gli utenti che hanno messo stella
    if (_currentUser!.uid == _targetUserId) {
      _showStarredUsersSheet(video);
      return;
    }
    
    // Per gli altri utenti, gestisci normalmente l'aggiunta/rimozione della stella
    
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
        message = 'Star removed';
      } else {
        // Aggiungi la stella - attiva l'animazione solo quando si aggiunge
        _triggerStarAnimation(videoId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;
        // Ottieni il nome dell'utente proprietario del video
        final videoOwnerName = video['username'] ?? 'User';
        message = '$videoOwnerName thanks you for your support';
      }
      
      // Aggiorna il conteggio totale delle stelle
      await videoRef.child('star_count').set(newStarCount);

      // Verifica finale dello stato su Firebase per sicurezza (fix iOS)
      final finalStarSnapshot = await starUsersRef.child(currentUserId).get();
      final bool finalStarState = finalStarSnapshot.exists;

      // Aggiorna lo stato locale in base allo stato finale verificato
      if (mounted) {
        setState(() {
          // Aggiorna il conteggio stelle nel video locale
          video['star_count'] = newStarCount;

          // Garantisce che star_users sia una mappa
          final dynamic localStarUsers = video['star_users'];
          if (localStarUsers == null || localStarUsers is! Map) {
            video['star_users'] = <String, dynamic>{};
          }
          if (video['star_users'] is Map) {
            if (finalStarState) {
              (video['star_users'] as Map)[currentUserId] = true;
            } else {
              (video['star_users'] as Map).remove(currentUserId);
            }
          }
        });
      }

      // Ricarica lo stato attuale da Firebase per sincronizzare
      if (mounted) {
        try {
          final refreshSnapshot = await videoRef.get();
          if (refreshSnapshot.exists && refreshSnapshot.value is Map) {
            final refreshedVideo = Map<String, dynamic>.from(refreshSnapshot.value as Map);
            setState(() {
              video['star_count'] = refreshedVideo['star_count'] ?? newStarCount;
              video['star_users'] = refreshedVideo['star_users'] ?? video['star_users'];
            });
          }
        } catch (_) {}
      }

              // Stelle aggiornate per il video
      
      // Mostra feedback visivo
      if (mounted) {
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
              // Errore nella gestione della stella
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating star',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.red[100],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
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
          // Alcune serializzazioni iOS possono salvare come lista
          commentCount = raw.where((e) => e != null).length;
        }
      }
      
      // Salva in cache
      _commentsCountCache[cacheKey] = commentCount;
      
      return commentCount;
    } catch (e) {
              // Errore nel recupero del conteggio commenti
      return 0;
    }
  }

  // Comment star functions (copied from community_page.dart)
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
  
  void _initializeCommentStarAnimation(String commentId) {
    if (!_commentStarAnimationControllers.containsKey(commentId)) {
      _commentStarAnimationControllers[commentId] = AnimationController(
        duration: Duration(milliseconds: 600), // Animazione uniformata
        vsync: this,
      );
      
      _commentStarScaleAnimations[commentId] = Tween<double>(
        begin: 1.0,
        end: 1.6, // Scala uniformata
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
      
      if (hasUserStarred) {
        // Rimuovi la stella
        await starUsersRef.child(currentUserId).remove();
        newStarCount = math.max(0, currentStarCount - 1); // Previeni valori negativi
      } else {
        // Aggiungi la stella - attiva l'animazione solo quando si aggiunge
        _triggerCommentStarAnimation(commentId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;
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
      
              // Stelle aggiornate per il commento
      
    } catch (e) {
      // Errore nell'aggiornamento delle stelle del commento
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
          // Errore nel refresh del commento – ignora
        }
      }
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
      
      if (hasUserStarred) {
        // Rimuovi la stella
        await starUsersRef.child(currentUserId).remove();
        newStarCount = math.max(0, currentStarCount - 1); // Previeni valori negativi
      } else {
        // Aggiungi la stella - attiva l'animazione solo quando si aggiunge
        _triggerCommentStarAnimation(replyId);
        await starUsersRef.child(currentUserId).set(true);
        newStarCount = currentStarCount + 1;

        // Salva la stella nella cartella notificationstars del proprietario della risposta
        final replyOwnerId = reply['userId'] as String?;
        if (replyOwnerId != null && replyOwnerId != currentUserId) {
          final notificationStarRef = _database
              .child('users')
              .child('users')
              .child(replyOwnerId)
              .child('notificationstars')
              .child('${replyId}_${currentUserId}');

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
            'read': false,
          };

          await notificationStarRef.set(notificationStarData);
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
      
              // Stelle aggiornate per la risposta
      
    } catch (e) {
      // Errore nell'aggiornamento delle stelle della risposta
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
          // Errore nel refresh della risposta – ignora
        }
      }
    }
  }

  Future<void> _handleVideoComment(Map<String, dynamic> video) async {
    final videoId = video['id'] as String;
    final videoUserId = video['userId'] as String;
    final videoOwnerName = video['displayName'] as String? ?? 'Unknown User';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => Padding(
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
                
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.comment_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No comments yet',
                          style: TextStyle(
                            fontSize: 18,
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
                      ],
                    ),
                  );
                }
                
                final dynamic rawComments = snapshot.data!.snapshot.value;
                Map<dynamic, dynamic>? commentsData;
                if (rawComments is Map) {
                  commentsData = rawComments;
                } else if (rawComments is List) {
                  // iOS Firebase can return lists for arrays; convert to map with index as key
                  commentsData = {
                    for (int i = 0; i < rawComments.length; i++)
                      if (rawComments[i] != null) i.toString(): rawComments[i]
                  };
                } else {
                  commentsData = null;
                }
                if (commentsData == null || commentsData.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.comment_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No comments yet',
                          style: TextStyle(
                            fontSize: 18,
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
                      ],
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
                
                comments.sort((a, b) {
                  final aTime = a['timestamp'] as int? ?? 0;
                  final bTime = b['timestamp'] as int? ?? 0;
                  return bTime.compareTo(aTime); // Più recenti prima
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
                  child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
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
    final isPageOwner = _currentUser?.uid == _targetUserId; // Utente proprietario della pagina
    final canDeleteComment = isCommentOwner || isVideoOwner || isPageOwner;
    
    // Load profile image dynamically for this comment
    final userId = comment['userId']?.toString() ?? '';
    
    return FutureBuilder<String?>(
      future: userId.isNotEmpty ? _loadUserProfileImage(userId) : Future.value(null),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data ?? '';
    
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
              onTap: () => _openUserProfile(comment['userId']),
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
                        onTap: () => _openUserProfile(comment['userId']),
                        child: Text(
                          comment['userDisplayName'] ?? 'Anonymous',
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
                                                    Color(0xFF667eea),
                                                    Color(0xFF764ba2),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180),
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
    if (_currentUser == null) return;
    
    try {
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
        'userId': _currentUser!.uid,
        'userDisplayName': _currentUser!.displayName ?? 'Anonymous',
        'userProfileImage': _currentUser!.photoURL ?? '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'videoId': videoId,
        'replies_count': 0, // Inizializza il conteggio delle risposte
        'star_count': 0, // Inizializza il conteggio delle stelle
        'star_users': {}, // Inizializza la lista degli utenti che hanno messo stella
      };
      
      // Salva il commento nel database con timeout per iOS
      await commentRef.set(commentData).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Timeout nel salvataggio del commento', Duration(seconds: 10));
        },
      );
      
      // Aggiorna la cache del conteggio commenti
      final cacheKey = '${videoUserId}_$videoId';
      if (_commentsCountCache.containsKey(cacheKey)) {
        _commentsCountCache[cacheKey] = (_commentsCountCache[cacheKey] ?? 0) + 1;
      }
      
              // Commento salvato per il video
      
      // Mostra messaggio di successo
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Comment posted!', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.grey[700], size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Error posting comment', style: TextStyle(color: Colors.black))),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _showCommentOptionsDialog(Map<String, dynamic> comment, String videoUserId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Color(0xFF1E1E1E) 
                : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Opzioni
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Delete Comment',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showCommentDeleteDialog(comment, videoUserId);
                },
              ),
              
              // Spazio per evitare che il contenuto tocchi il bordo
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
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
                                    Color(0xFF667eea),
                                    Color(0xFF764ba2),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  transform: GradientRotation(135 * 3.14159 / 180),
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
      final videoId = comment['videoId'] ?? '';
      final commentId = comment['id'] ?? '';
      
      if (videoId.isEmpty || commentId.isEmpty) {
        // videoId o commentId mancanti – esci in silenzio
        return;
      }
      
      await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(commentId)
          .remove();
      
      // Aggiorna la cache del conteggio commenti
      final cacheKey = '${videoUserId}_$videoId';
      if (_commentsCountCache.containsKey(cacheKey)) {
        _commentsCountCache[cacheKey] = (_commentsCountCache[cacheKey] ?? 1) - 1;
        if (_commentsCountCache[cacheKey]! < 0) {
          _commentsCountCache[cacheKey] = 0;
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comment deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting comment'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
              
              // Header con titolo centrato (stile commenti)
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
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ),
                      ),
                      child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
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
      final currentUserDisplayName = _currentUser!.displayName ?? 'Anonymous';
      final currentUserProfileImage = _currentUser!.photoURL;
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
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'parentCommentId': parentCommentId,
        'videoId': videoId,
        'star_count': 0, // Inizializza il conteggio delle stelle
        'star_users': {}, // Inizializza la lista degli utenti che hanno messo stella
      };
      
      // Salva la risposta nel database con timeout per iOS
      await replyRef.set(replyData).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Timeout nel salvataggio della reply', Duration(seconds: 10));
        },
      );
      
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
      
      // Mostra feedback
      if (mounted) {
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
            backgroundColor: Color(0xFF667eea),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.all(16),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting reply'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _showRepliesSheet(Map<String, dynamic> parentComment, String videoUserId) {
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
                  
                  // Commento originale
                  Container(
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
                          onTap: () => _openUserProfile(parentComment['userId']),
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
                            child: FutureBuilder<String?>(
                              future: _loadUserProfileImage(parentComment['userId']),
                              builder: (context, snapshot) {
                                final currentProfileImageUrl = snapshot.data ?? parentComment['userProfileImage']?.toString() ?? '';
                                return ClipOval(
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
                                );
                              },
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
                                    onTap: () => _openUserProfile(parentComment['userId']),
                                    child: Text(
                                      parentComment['userDisplayName'] ?? 'Anonymous',
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
                  
                  final dynamic rawReplies = snapshot.data!.snapshot.value;
                  Map<dynamic, dynamic>? repliesData;
                  if (rawReplies is Map) {
                    repliesData = rawReplies;
                  } else if (rawReplies is List) {
                    // iOS Firebase can return lists for arrays; convert to map with index as key
                    repliesData = {
                      for (int i = 0; i < rawReplies.length; i++)
                        if (rawReplies[i] != null) i.toString(): rawReplies[i]
                    };
                  } else {
                    repliesData = null;
                  }
                  
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
                    child: _currentUserProfileImageUrl != null && _currentUserProfileImageUrl!.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              _currentUserProfileImageUrl!,
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

  Widget _buildReplyItem(Map<String, dynamic> reply, String videoUserId) {
    // Gestisci il timestamp
    DateTime replyTime;
    if (reply['timestamp'] is int) {
      replyTime = DateTime.fromMillisecondsSinceEpoch(reply['timestamp']);
    } else {
      replyTime = DateTime.now();
    }
    
    // Check if current user is the reply owner, video owner, or page owner
    final isReplyOwner = _currentUser?.uid == reply['userId'];
    final isVideoOwner = _currentUser?.uid == videoUserId;
    final isPageOwner = _currentUser?.uid == _targetUserId; // Utente proprietario della pagina
    final canDeleteReply = isReplyOwner || isVideoOwner || isPageOwner;
    
    // Load profile image dynamically for this reply
    final userId = reply['userId']?.toString() ?? '';
    final profileImageUrl = reply['userProfileImage']?.toString() ?? '';
    
    return FutureBuilder<String?>(
      future: userId.isNotEmpty ? _loadUserProfileImage(userId) : Future.value(null),
      builder: (context, snapshot) {
        final currentProfileImageUrl = snapshot.data ?? profileImageUrl;
    
    return GestureDetector(
      onLongPress: canDeleteReply ? () => _showReplyDeleteDialog(reply, videoUserId) : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indentazione per mostrare che è una risposta
            SizedBox(width: 20),
            
            // Avatar utente (cliccabile)
            GestureDetector(
              onTap: () => _openUserProfile(reply['userId']),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
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
                                size: 16,
                              ),
                            );
                          },
                        )
                      : Container(
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
                            size: 16,
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
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _openUserProfile(reply['userId']),
                        child: Text(
                          reply['userDisplayName'] ?? 'Anonymous',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context).textTheme.titleMedium?.color,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        _formatTimestamp(replyTime),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
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
                      color: Theme.of(context).textTheme.bodyMedium?.color,
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
                                                Color(0xFF667eea),
                                                Color(0xFF764ba2),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              transform: GradientRotation(135 * 3.14159 / 180),
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
    // Check if current user is the reply owner, video owner, or page owner
    final isReplyOwner = _currentUser?.uid == reply['userId'];
    final isVideoOwner = _currentUser?.uid == videoUserId;
    final isPageOwner = _currentUser?.uid == _targetUserId;
    final canDeleteReply = isReplyOwner || isVideoOwner || isPageOwner;
    
    String deleteText = 'Delete reply';
    if ((isVideoOwner || isPageOwner) && !isReplyOwner) {
      deleteText = 'Delete reply (as video/page owner)';
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
                                    Color(0xFF667eea),
                                    Color(0xFF764ba2),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  transform: GradientRotation(135 * 3.14159 / 180),
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

  void _showStarredUsersSheet(Map<String, dynamic> video) {
    final videoId = video['id'] as String;
    final starUsersRaw = video['star_users'];
    Map<String, dynamic>? starUsers;
    
    if (starUsersRaw != null && starUsersRaw is Map) {
      starUsers = Map<String, dynamic>.from(starUsersRaw);
    }
    
    if (starUsers == null || starUsers.isEmpty) {
      // Se non ci sono stelle, mostra un messaggio
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No stars yet',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Users who starred this post',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${starUsers?.length ?? 0}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Lista utenti che hanno messo stella
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _getStarredUsers(starUsers ?? {}),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                      ),
                    );
                  }
                  
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading users',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  
                  final users = snapshot.data ?? [];
                  
                  if (users.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.star_outline,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No users found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return _buildStarredUserItem(user);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getStarredUsers(Map<String, dynamic> starUsers) async {
    List<Map<String, dynamic>> users = [];
    
    for (String userId in starUsers.keys) {
      if (userId is! String) continue; // Salta se la chiave non è una stringa
      try {
        // Ottieni i dati dell'utente dal database
        final userSnapshot = await _database
            .child('users')
            .child('users')
            .child(userId)
            .child('profile')
            .get();
        
        if (userSnapshot.exists) {
          final userData = userSnapshot.value as Map<dynamic, dynamic>?;
          if (userData != null) {
            // Converti in Map<String, dynamic> per accesso sicuro
            final userDataMap = Map<String, dynamic>.from(userData);
            users.add({
              'uid': userId,
              'displayName': userDataMap['display_name'] ?? userDataMap['displayName'] ?? 'Anonymous',
              'profileImage': userDataMap['profileImageUrl'] ?? '',
              'username': userDataMap['username'] ?? '',
            });
          }
        }
      } catch (e) {
        // Aggiungi un utente con dati di fallback
        users.add({
          'uid': userId,
          'displayName': 'Unknown User',
          'profileImage': '',
          'username': '',
        });
      }
    }
    
    return users;
  }

  Widget _buildStarredUserItem(Map<String, dynamic> user) {
    return GestureDetector(
      onTap: () {
        // Naviga alla pagina del profilo dell'utente
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileEditPage(userId: user['uid']),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.grey[800] 
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar utente
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: user['profileImage'] != null && user['profileImage'].toString().isNotEmpty
                    ? Image.network(
                        user['profileImage'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF667eea),
                                  const Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ),
                            ),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 24,
                            ),
                          );
                        },
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF667eea),
                              const Color(0xFF764ba2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180),
                          ),
                        ),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        ),
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
                    user['displayName'] ?? 'Anonymous',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.titleMedium?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  if (user['username'] != null && user['username'].toString().isNotEmpty)
                    Text(
                      '@${user['username']}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            
            // Icona stella e freccia
            Row(
              mainAxisSize: MainAxisSize.min,
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
                  child: Icon(
                    Icons.star,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
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
      
      // Rimuovi la risposta dal database
      await _database
          .child('users')
          .child('users')
          .child(videoUserId)
          .child('videos')
          .child(videoId)
          .child('comments')
          .child(parentCommentId)
          .child('replies')
          .child(replyId)
          .remove();
      
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
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reply deleted'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting reply'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
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
                                        Color(0xFF667eea),
                                        Color(0xFF764ba2),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      transform: GradientRotation(135 * 3.14159 / 180),
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
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            
                            // Totale Comments
                            Column(
                              children: [
                                Icon(
                                  Icons.comment,
                                  color: Color(0xFF667eea),
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
                                    fontSize: 12,
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
                                                      } else if (platform.toLowerCase() == 'youtube') {
                                                        await _openYouTubePostOrProfile(accountWithVideoData);
                                                      } else if (platform.toLowerCase() == 'tiktok') {
                                                        await _openTikTokPostOrProfile(accountWithVideoData);
                                                      } else if (platform.toLowerCase() == 'twitter') {
                                                        await _openTwitterPostOrProfile(accountWithVideoData);
                                                      }
                                                    },
                                                    icon: Icon(Icons.open_in_new, size: 16),
                                                    label: Text('Open'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: _getPlatformColor(platform),
                                                      foregroundColor: Colors.white,
                                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                      minimumSize: Size(0, 32),
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
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF667eea),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('Close'),
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
      return {'likes': 0, 'comments': 0};
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

  // Mappa dei loghi delle piattaforme social
  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

  // Carica gli account social per un video specifico
  Future<Map<String, List<Map<String, dynamic>>>> _loadVideoSocialAccounts(String videoId, String userId) async {
    try {
      final isNewFormat = videoId.contains(userId);
      Map<String, List<Map<String, dynamic>>> socialAccounts = {};
      
      if (isNewFormat) {
        // Formato nuovo: accounts in sottocartelle (scheduled_posts -> videos)
        final platforms = ['Facebook', 'Instagram', 'YouTube', 'Threads', 'TikTok', 'Twitter'];
        for (final platform in platforms) {
          final scheduledPlatformRef = _database
              .child('users')
              .child('users')
              .child(userId)
              .child('scheduled_posts')
              .child(videoId)
              .child('accounts')
              .child(platform);
          final videosPlatformRef = _database
              .child('users')
              .child('users')
              .child(userId)
              .child('videos')
              .child(videoId)
              .child('accounts')
              .child(platform);
          
          List<Map<String, dynamic>> accounts = await _fetchAccountsFromSubfolders(scheduledPlatformRef);
          if (accounts.isEmpty) {
            accounts = await _fetchAccountsFromSubfolders(videosPlatformRef);
          }
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
      return {};
    }
  }

  // Helper per fetch accounts da sottocartelle
  Future<List<Map<String, dynamic>>> _fetchAccountsFromSubfolders(DatabaseReference platformRef) async {
    final snapshot = await platformRef.get();
    List<Map<String, dynamic>> accounts = [];
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      // Se è un oggetto diretto dell'account
      final bool looksLikeSingleAccount = data.containsKey('account_username') ||
          data.containsKey('account_display_name') ||
          data.containsKey('account_id') ||
          data.containsKey('youtube_video_id') ||
          data.containsKey('media_id') ||
          data.containsKey('post_id');
      if (looksLikeSingleAccount) {
        final account = Map<String, dynamic>.from(data);
        if ((account['post_id'] == null || account['post_id'].toString().isEmpty) &&
            account['youtube_video_id'] != null &&
            account['youtube_video_id'].toString().isNotEmpty) {
          account['post_id'] = account['youtube_video_id'].toString();
        }
        accounts.add(account);
      } else {
        // Altrimenti è una mappa di sotto-nodi account
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

  // Funzioni per aprire i social media
  Future<void> _openInstagramPostOrProfile(Map<String, dynamic> account) async {
    final displayName = account['account_display_name']?.toString() ?? account['display_name']?.toString() ?? '';
    final username = account['username']?.toString();
    String? url;
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
            // --- FORMATO NUOVO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db.child('users').child('users').child(userId).child('scheduled_posts').child(videoId).child('accounts').child('Instagram');
            var videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Instagram');
              videoAccountsSnap = await videoAccountsRef.get();
            }
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, può essere oggetto diretto, mappa indicizzata o lista
              if (videoAccounts is Map) {
                if (videoAccounts.containsKey('account_display_name')) {
                  // Oggetto diretto
                  final accountDisplayName = videoAccounts['account_display_name']?.toString();
                  if (accountDisplayName == displayName) {
                    mediaId = videoAccounts['media_id']?.toString();
                    accountId = videoAccounts['account_id']?.toString();
                  }
                } else {
                  // Mappa indicizzata
                  for (final entry in videoAccounts.entries) {
                    final accountData = entry.value;
                    if (accountData is Map) {
                      final accountDisplayName = accountData['account_display_name']?.toString();
                      if (accountDisplayName == displayName) {
                        mediaId = accountData['media_id']?.toString();
                        accountId = accountData['account_id']?.toString();
                        break;
                      }
                    }
                  }
                }
              } else if (videoAccounts is List) {
                // Caso: più account per piattaforma (lista di oggetti)
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['account_display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      mediaId = accountData['media_id']?.toString();
                      accountId = accountData['account_id']?.toString();
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
            } else {}
            if (accessToken != null) {
              final apiUrl = 'https://graph.facebook.com/v18.0/$mediaId?fields=id,media_type,media_url,permalink&access_token=$accessToken';
              final response = await HttpClient().getUrl(Uri.parse(apiUrl)).then((req) => req.close());
              final respBody = await response.transform(Utf8Decoder()).join();
              final data = respBody.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(respBody)) : null;
              if (data != null && data['permalink'] != null) {
                url = data['permalink'];
              } else {}
            } else {}
          } else {}
        } else {}
      } else {}
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
            // --- FORMATO NUOVO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db.child('users').child('users').child(userId).child('scheduled_posts').child(videoId).child('accounts').child('Threads');
            var videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Threads');
              videoAccountsSnap = await videoAccountsRef.get();
            }
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, può essere oggetto diretto, mappa indicizzata o lista
              if (videoAccounts is Map) {
                if (videoAccounts.containsKey('account_display_name')) {
                  final accountDisplayName = videoAccounts['account_display_name']?.toString();
                  if (accountDisplayName == displayName) {
                    postId = videoAccounts['post_id']?.toString(); // <-- uso post_id
                    accountId = videoAccounts['account_id']?.toString();
                  }
                } else {
                  for (final entry in videoAccounts.entries) {
                    final accountData = entry.value;
                    if (accountData is Map) {
                      final accountDisplayName = accountData['account_display_name']?.toString();
                      if (accountDisplayName == displayName) {
                        postId = accountData['post_id']?.toString(); // <-- uso post_id
                        accountId = accountData['account_id']?.toString();
                        break;
                      }
                    }
                  }
                }
              } else if (videoAccounts is List) {
                // Caso: più account per piattaforma (lista di oggetti)
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['account_display_name']?.toString();
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString(); // <-- uso post_id
                      accountId = accountData['account_id']?.toString();
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
            } else {}
            if (accessToken != null && accessToken.isNotEmpty) {
              // Chiamata corretta secondo la doc: GET https://graph.threads.net/v1.0/{media_id}?fields=permalink&access_token=...
              final apiUrl = 'https://graph.threads.net/v1.0/$postId?fields=permalink&access_token=$accessToken';
              final response = await HttpClient().getUrl(Uri.parse(apiUrl)).then((req) => req.close());
              final respBody = await response.transform(Utf8Decoder()).join();
              final data = respBody.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(respBody)) : null;
              if (data != null && data['permalink'] != null) {
                url = data['permalink'].toString();
              } else {}
            } else {}
          } else {}
        } else {}
      } else {}
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
            // --- FORMATO NUOVO: prova scheduled_posts poi fallback videos ---
            DatabaseReference videoAccountsRef = db.child('users').child('users').child(userId).child('scheduled_posts').child(videoId).child('accounts').child('Facebook');
            var videoAccountsSnap = await videoAccountsRef.get();
            if (!videoAccountsSnap.exists) {
              videoAccountsRef = db.child('users').child('users').child(userId).child('videos').child(videoId).child('accounts').child('Facebook');
              videoAccountsSnap = await videoAccountsRef.get();
            }
            
            if (videoAccountsSnap.exists) {
              final videoAccounts = videoAccountsSnap.value;
              
              // Nel formato nuovo, può essere oggetto diretto, mappa indicizzata o lista
              if (videoAccounts is Map) {
                if (videoAccounts.containsKey('account_display_name')) {
                  final accountDisplayName = videoAccounts['account_display_name']?.toString();
                  
                  if (accountDisplayName == displayName) {
                    postId = videoAccounts['post_id']?.toString();
                    accountId = videoAccounts['account_id']?.toString();
                  }
                } else {
                  for (final entry in videoAccounts.entries) {
                    final accountData = entry.value;
                    if (accountData is Map) {
                      final accountDisplayName = accountData['account_display_name']?.toString();
                      
                      if (accountDisplayName == displayName) {
                        postId = accountData['post_id']?.toString();
                        accountId = accountData['account_id']?.toString();
                        break;
                      }
                    }
                  }
                }
              } else if (videoAccounts is List) {
                // Caso: più account per piattaforma (lista di oggetti)
                for (final accountData in videoAccounts) {
                  if (accountData is Map) {
                    final accountDisplayName = accountData['account_display_name']?.toString();
                    
                    if (accountDisplayName == displayName) {
                      postId = accountData['post_id']?.toString();
                      accountId = accountData['account_id']?.toString();
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
            } else {}
            
            if (accessToken != null) {
              final apiUrl = 'https://graph.facebook.com/$postId?fields=permalink_url&access_token=$accessToken';
              final response = await HttpClient().getUrl(Uri.parse(apiUrl)).then((req) => req.close());
              final respBody = await response.transform(Utf8Decoder()).join();
              final data = respBody.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(respBody)) : null;
              if (data != null && data['permalink_url'] != null) {
                final permalink = data['permalink_url'].toString();
                if (permalink.startsWith('/')) {
                  url = 'https://www.facebook.com$permalink';
                } else {
                  url = permalink;
                }
              } else {}
            } else {}
          } else {}
        } else {}
      } else {}
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

  Future<void> _openYouTubePostOrProfile(Map<String, dynamic> account) async {
    final postId = account['post_id']?.toString();
    final mediaId = account['media_id']?.toString();
    final youTubeVideoId = account['youtube_video_id']?.toString();
    
    String url;
    if (postId != null && postId.isNotEmpty) {
      url = 'https://www.youtube.com/watch?v=$postId';
    } else if (mediaId != null && mediaId.isNotEmpty) {
      url = 'https://www.youtube.com/watch?v=$mediaId';
    } else if (youTubeVideoId != null && youTubeVideoId.isNotEmpty) {
      url = 'https://www.youtube.com/watch?v=$youTubeVideoId';
    } else {
      url = 'https://www.youtube.com/';
    }
    
    await _openSocialMedia(url);
  }

  Future<void> _openTikTokPostOrProfile(Map<String, dynamic> account) async {
    final videoId = account['video_id']?.toString();
    final username = account['account_username']?.toString() ?? account['username']?.toString() ?? '';
    
    String url;
    if (videoId != null && videoId.isNotEmpty) {
      url = 'https://www.tiktok.com/@$username/video/$videoId';
    } else {
      url = 'https://www.tiktok.com/@$username';
    }
    
    await _openSocialMedia(url);
  }

  Future<void> _openTwitterPostOrProfile(Map<String, dynamic> account) async {
    final tweetId = account['tweet_id']?.toString();
    final username = account['account_username']?.toString() ?? account['username']?.toString() ?? '';
    
    String url;
    if (tweetId != null && tweetId.isNotEmpty) {
      url = 'https://twitter.com/$username/status/$tweetId';
    } else {
      url = 'https://twitter.com/$username';
    }
    
    await _openSocialMedia(url);
  }

  Future<void> _openSocialMedia(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {}
    } catch (e) {}
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
    } catch (e) {}
    
    // Fallback to web URL
    final webUri = Uri.parse('https://www.instagram.com/$username/');
    try {
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {}
  }

  Future<String?> _getSocialProfileImage(String userId, String platform, String accountId) async {
    try {
      String? imageUrl;
      
      if (platform.toLowerCase() == 'youtube') {
        // Per YouTube usa thumbnail_url
        final snapshot = await _database
            .child('users')
            .child(userId)
            .child(platform.toLowerCase())
            .child(accountId)
            .child('thumbnail_url')
            .get();
        
        if (snapshot.exists) {
          imageUrl = snapshot.value?.toString();
        }
      } else if (platform.toLowerCase() == 'threads') {
        // Per Threads usa il percorso speciale: users/users/[userId]/social_accounts/threads/[accountId]/profile_image_url
        final snapshot = await _database
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
        }
      } else {
        // Per Instagram, Facebook, TikTok usa profile_image_url
        final snapshot = await _database
            .child('users')
            .child(userId)
            .child(platform.toLowerCase())
            .child(accountId)
            .child('profile_image_url')
            .get();
        
        if (snapshot.exists) {
          imageUrl = snapshot.value?.toString();
        }
      }
      
      if (imageUrl == null || imageUrl.isEmpty) {
        // Nessuna immagine trovata per questo account
      }
      
      return imageUrl;
    } catch (e) {
      return null;
    }
  }

} 

// Custom painter per disegnare le silhouette delle montagne
class MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFF2E1A0E)
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Prima montagna (sinistra)
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.6);
    path.lineTo(size.width * 0.2, size.height * 0.4);
    path.lineTo(size.width * 0.4, size.height * 0.7);
    path.lineTo(size.width * 0.6, size.height * 0.3);
    path.lineTo(size.width * 0.8, size.height * 0.5);
    path.lineTo(size.width, size.height * 0.8);
    path.lineTo(size.width, size.height);
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 