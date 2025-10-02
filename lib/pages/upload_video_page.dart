import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter e ShaderMask
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../providers/theme_provider.dart';
import './scheduled_posts_page.dart';
import './upload_confirmation_page.dart';
import './schedule_post_page.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import './video_editor_page.dart';
import '../main.dart'; // Import per il routeObserver
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
// Aggiungo gli import necessari per la top bar
import './about_page.dart';
// rimosso: notifications page non più usata qui
import './settings_page.dart';
import './profile_edit_page.dart';
import 'social/social_account_details_page.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

// Enum for upload state
enum UploadState { notStarted, uploading, completed, error }

// Enum for upload steps
enum UploadStep { selectMedia, addDetails, selectAccounts }

// Class for tracking upload status
class UploadStatus {
  final String platform;
  final String accountId;
  UploadState state;
  String? error;
  double progress;

  UploadStatus({
    required this.platform,
    required this.accountId,
    this.state = UploadState.notStarted,
    this.error,
    this.progress = 0.0,
  });
}

class UploadVideoPage extends StatefulWidget {
  final Map<String, dynamic>? draftData;
  final DateTime? scheduledDateTime;
  final String? draftId; // Add draft ID parameter
  final bool forcePickVideo;

  const UploadVideoPage({
    super.key,
    this.draftData,
    this.scheduledDateTime,
    this.draftId, // Add draft ID parameter
    this.forcePickVideo = false,
  });

  @override
  State<UploadVideoPage> createState() => _UploadVideoPageState();
}

class _UploadVideoPageState extends State<UploadVideoPage> with WidgetsBindingObserver, RouteAware {
  // Current step in the upload process
  UploadStep _currentStep = UploadStep.selectMedia;
  
  // Variables for top bar functionality
  int _unreadNotifications = 0;
  int _unreadComments = 0;
  int _unreadStars = 0;
  Stream<DatabaseEvent>? _notificationsStream;
  Stream<DatabaseEvent>? _commentsStream;
  Stream<DatabaseEvent>? _starsStream;
  String? _profileImageUrl; // URL dell'immagine profilo dal database
  
  // PageController for horizontal swiping
  late PageController _pageController;
  
  // Flag per evitare caricamenti ripetuti degli account
  bool _accountsLoaded = false;
  DateTime? _lastAccountsLoadTime;

  final ImagePicker _picker = ImagePicker();
  File? _videoFile;
  bool _isImageFile = false;
  bool _isVideoFromUrl = false; // Track if video was loaded from URL
  String? _thumbnailPath;
  File? _youtubeThumbnailFile; // Per la miniatura personalizzata di YouTube
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _promptController = TextEditingController();
  final Map<String, List<String>> _selectedAccounts = {};
  String? _pressedButton; // To track the pressed button
  bool _isUploading = false;
  bool _isGeneratingDescription = false;
  bool _useChatGPT = false;
  bool _showCheckmark = false;
  DateTime? _scheduledDateTime;
  bool _isScheduled = false;
  bool _isPremium = false; // Track if user is premium
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final ScrollController _scrollController = ScrollController();
  double _scrollPosition = 0.0;
  Timer? _scrollDebounceTimer; // Spostato qui per debounce scroll
  
  // Controller for video playback
  VideoPlayerController? _videoPlayerController;
  bool _isVideoInitialized = false;
  bool _isVideoFullscreen = false;
  bool _isVideoLocked = false;
  bool _isVideoPlaying = false;
  bool _showVideoControls = true;
  Timer? _controlsHideTimer;
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  
  // Variable to track the last expanded social panel
  String? _currentlyExpandedPlatform;
  
  // GlobalKeys for each platform panel
  final Map<String, GlobalKey> _platformKeys = {};

  final List<Color> _gradientColors = [
    const Color(0xFF6C63FF),
    const Color(0xFF4A45B1),
    const Color(0xFFFF6B6B),
    const Color(0xFFEE0979),
    const Color(0xFF00C9FF),
    const Color(0xFF92FE9D),
  ];
  Map<String, List<Map<String, dynamic>>> _socialAccounts = {
    'TikTok': [],
    'YouTube': [],
    'Instagram': [],
    'Facebook': [],
    'Twitter': [],
    'Threads': [],
  };

  final Map<String, String> _platformLogos = {
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'Instagram': 'assets/loghi/logo_insta.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
  };

  final Map<String, IconData> _platformIcons = {
    'TikTok': Icons.music_note,
    'YouTube': Icons.play_arrow,
    'Instagram': Icons.camera_alt,
    'Facebook': Icons.facebook,
    'Twitter': Icons.chat,
    'Threads': Icons.chat,
  };

  // ChatGPT Configuration
  static const String _apiKey = '';
  static const int _maxTokens = 150;

  Map<String, UploadStatus> _uploadStatuses = {};
  bool _showStickyButton = false;
  bool _isMenuExpanded = false;
  double _lastScrollPosition = 0.0;
  final Map<String, bool> _usePlatformSpecificContent = {};
  final Map<String, TextEditingController> _platformTitleControllers = {};
  final Map<String, TextEditingController> _platformDescriptionControllers = {};
  final Map<String, int> _platformDescriptionLengths = {};
  final Map<String, bool> _useChatGPTforPlatform = {};
  final Map<String, TextEditingController> _platformPromptControllers = {};

  // Character limits for platform descriptions
  final Map<String, int> _platformDescriptionLimits = {
    'TikTok': 2200,
    'YouTube': 5000,
    'Instagram': 2200,
    'Facebook': 8000,
    'Twitter': 280,
    'Threads': 500,
  };

  // Limits for ChatGPT generation for each platform
  final Map<String, int> _platformChatGPTLimits = {
    'TikTok': 500,
    'YouTube': 500,
    'Instagram': 500,
    'Facebook': 500,
    'Twitter': 250,
    'Threads': 400,
  };

  // Track user credits
  int _userCredits = 750; // Default value, will be loaded from database

  bool _isCreatingDescription = false;
  String? _generatedDescription;
  int _currentDescriptionCharacterCount = 0;
  Set<String> _selectedPlatforms = {};
  String _tabValue = "details";
  final bool _isVideoSupported = true;
  
  // Flag to indicate if we have access to Instagram Stories API beta
  final bool _hasInstagramStoriesAPIAccess = false;
  
  // Map to store account-specific content configurations
  Map<String, Map<String, dynamic>>? _accountSpecificContent;

  // Update the data structure to track expanded state for each platform
  Map<String, bool> _expandedState = {};

  // Aggiungo la variabile per tracciare se stiamo modificando una bozza esistente
  bool _isEditingDraft = false;
  
  // Variabile per tracciare se stiamo ricaricando la pagina dopo il salvataggio di una draft
  bool _isRefreshingAfterDraftSave = false;

  // Sostituisco il listener del controller con un ValueNotifier per la descrizione principale
  final ValueNotifier<int> _descriptionLengthNotifier = ValueNotifier<int>(0);

  // TikTok specific options
  Map<String, Map<String, dynamic>> _tiktokOptions = {};
  String? _tiktokPrivacyLevel;
  bool _tiktokAllowComments = false;
  bool _tiktokAllowDuets = false;
  bool _tiktokAllowStitch = false;
  bool _tiktokCommercialContent = false;
  bool _tiktokOwnBrand = false;
  bool _tiktokBrandedContent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting('it_IT', null);
    _scrollController.addListener(_onScrollDebounced); // Cambiato listener
    
    // Initialize top bar functionality
    _setupNotificationsListener();
    _loadProfileImage();
    
    // Preload accounts with a slight delay to improve performance
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted) _loadSocialAccounts();
    });
    _loadUserCredits();
    
    // Initialize the PageController
    _pageController = PageController(initialPage: _currentStep.index);
    
    // Initialize platform keys
    for (var platform in _socialAccounts.keys) {
      _platformKeys[platform] = GlobalKey();
    }
    
    // Initialize platform-specific content flags (default to true = use global content)
    _socialAccounts.keys.forEach((platform) {
      _usePlatformSpecificContent[platform] = true;
      _platformTitleControllers[platform] = TextEditingController();
      _platformDescriptionControllers[platform] = TextEditingController();
      _platformPromptControllers[platform] = TextEditingController();
      _platformDescriptionLengths[platform] = 0;
      _useChatGPTforPlatform[platform] = false;
      
      // Add listener to monitor description length - ottimizzato per ridurre setState
      _platformDescriptionControllers[platform]!.addListener(() {
        // Aggiorna solo la lunghezza senza chiamare setState globale
          _platformDescriptionLengths[platform] = _platformDescriptionControllers[platform]!.text.length;
      });
    });
    
    // Sostituisco il listener con ValueNotifier
    _descriptionController.addListener(() {
      _descriptionLengthNotifier.value = _descriptionController.text.length;
      // Aggiorna description lengths per piattaforme che usano contenuto globale
        _socialAccounts.keys.forEach((platform) {
          if (_usePlatformSpecificContent[platform] == true) {
            _platformDescriptionLengths[platform] = _descriptionController.text.length;
          }
      });
    });
    
    // Load draft data if available
    if (widget.draftData != null) {
      // Imposta la modalità modifica bozza
      _isEditingDraft = true;
      _loadDraftData();
    }
    
    // Set scheduling data if provided
    if (widget.scheduledDateTime != null) {
      setState(() {
        _scheduledDateTime = widget.scheduledDateTime;
        _isScheduled = true;
      });
    }
    
    // Initialize expanded state for all platforms to false
    for (var platform in _socialAccounts.keys) {
      _expandedState[platform] = false;
    }

    // Se richiesto, apri subito la galleria video
    if (widget.forcePickVideo) {
      Future.delayed(Duration.zero, () async {
        final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
        if (video != null) {
          final videoFile = File(video.path);
          setState(() {
            _videoFile = videoFile;
            _showCheckmark = true;
            _isImageFile = false;
          });
          // Open the video editor page immediatamente
          await _openVideoEditor(videoFile);
        }
      });
    }
  }

  @override
  void dispose() {
    // Disiscrive il widget dal routeObserver
    routeObserver.unsubscribe(this);
    
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    _scrollDebounceTimer?.cancel();
    
    // Clean up notification stream
    _notificationsStream = null;
    
    // Dispose the PageController
    _pageController.dispose();
    
    // Dispose all platform-specific controllers
    _platformTitleControllers.forEach((_, controller) => controller.dispose());
    _platformDescriptionControllers.forEach((_, controller) => controller.dispose());
    _platformPromptControllers.forEach((_, controller) => controller.dispose());
    
    // Make sure to dispose video player controller
    if (_videoPlayerController != null) {
      _videoPlayerController!.pause();
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }
    
    // Dispose timers
    _positionUpdateTimer?.cancel();
    _controlsHideTimer?.cancel();
    
    _descriptionLengthNotifier.dispose();
    
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando l'app torna in primo piano, ricarica gli account social solo se necessario
    if (state == AppLifecycleState.resumed) {
      // Forza il ricaricamento solo se siamo nella schermata di selezione account
      if (_currentStep == UploadStep.selectAccounts) {
        _accountsLoaded = false;
        _loadSocialAccounts();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Registra il widget con il routeObserver
    final route = ModalRoute.of(context);
    if (route != null && route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }
  
  // Chiamato quando questa route non è più visibile (un'altra pagina è stata spinta sopra)
  @override
  void didPushNext() {
    // Salva lo stato che la pagina non è più visibile
    // print('UploadVideoPage non più visibile');
    
    // Resetta la flag se stiamo navigando verso una pagina degli account social
    // ma solo se siamo nella schermata di selezione account
    if (_currentStep == UploadStep.selectAccounts) {
      _accountsLoaded = false;
    }
  }
  
  // Chiamato quando questa route diventa visibile di nuovo dopo un pop di un'altra route
  @override
  void didPopNext() {
    // La pagina è tornata visibile dopo che un'altra pagina è stata rimossa
    // print('UploadVideoPage tornata visibile, ricarico gli account social');
    
    // Carica gli account social solo se siamo nella schermata di selezione account
    if (_currentStep == UploadStep.selectAccounts) {
      // Resetta la flag per forzare un ricaricamento
      _accountsLoaded = false;
      _loadSocialAccounts();
      
      // Forziamo un aggiornamento dell'UI
      setState(() {
        // Force UI update
      });
    }
  }

  // Metodo per navigare a una pagina social e ricaricare gli account quando si torna
  Future<void> _navigateToSocialPage(String routeName) async {
    // Resetta la flag per forzare un ricaricamento al ritorno
    _accountsLoaded = false;
    
    // Navigate to the social account page
    final result = await Navigator.pushNamed(context, routeName);
    
    // If the result is true, reload the social accounts
    if (result == true) {
      // print('Risultato positivo dalla navigazione, ricarico gli account');
      await _loadSocialAccounts();
      
      // If we're on the account selection step, also refresh the UI
      if (_currentStep == UploadStep.selectAccounts) {
        setState(() {
          // Force UI update
        });
      }
    }
  }

  // Video control methods
  void _startPositionUpdateTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(Duration(milliseconds: 200), (timer) { // Ridotto da 100 a 200ms per migliorare performance
      if (_videoPlayerController != null && 
          _videoPlayerController!.value.isInitialized && 
          mounted) {
        setState(() {
          _currentPosition = _videoPlayerController!.value.position;
          _videoDuration = _videoPlayerController!.value.duration;
        });
      }
    });
  }
  
  void _toggleVideoPlayback() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      if (_videoPlayerController!.value.isPlaying) {
        _pauseVideo();
      } else {
        _playVideo();
      }
    }
  }
  
  void _playVideo() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized) {
      _videoPlayerController!.play();
      setState(() {
        _isVideoPlaying = true;
        _showVideoControls = true;
      });
      
      // Update position immediately
      _currentPosition = _videoPlayerController!.value.position;
      _videoDuration = _videoPlayerController!.value.duration;
      
      // Hide controls automatically after 3 seconds
      _controlsHideTimer?.cancel();
      _controlsHideTimer = Timer(Duration(seconds: 3), () {
        if (mounted && _videoPlayerController?.value.isPlaying == true) {
          setState(() {
            _showVideoControls = false;
          });
        }
      });
    }
  }
  
  void _pauseVideo() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized) {
      _videoPlayerController!.pause();
      setState(() {
        _isVideoPlaying = false;
        _showVideoControls = true;
      });
      
      // Update position immediately
      _currentPosition = _videoPlayerController!.value.position;
      _videoDuration = _videoPlayerController!.value.duration;
      
      // Cancel auto-hide timer when video is paused
      _controlsHideTimer?.cancel();
    }
  }
  
  void _toggleFullScreen() {
    setState(() {
      _isVideoFullscreen = !_isVideoFullscreen;
      _showVideoControls = true;
    });
    
    // Reset timer for auto-hide controls when entering fullscreen
    if (_isVideoFullscreen) {
      _controlsHideTimer?.cancel();
      _controlsHideTimer = Timer(Duration(seconds: 3), () {
        if (mounted && _isVideoFullscreen) {
          setState(() {
            _showVideoControls = false;
          });
        }
      });
    } else {
      // Cancel timer when exiting fullscreen
      _controlsHideTimer?.cancel();
    }
  }
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    } else {
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
  }
  
  Widget _buildVideoPlayer(VideoPlayerController controller) {
    final bool isHorizontalVideo = controller.value.aspectRatio > 1.0;
    
    if (isHorizontalVideo) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
  }

  // Method to go to next step
  void _goToNextStep() {
    // Close keyboard when navigating to next step
    FocusScope.of(context).unfocus();
    
    // Validate that a video is selected before proceeding from step 1
    // Skip validation if we're refreshing after draft save
    if (_currentStep == UploadStep.selectMedia && _videoFile == null && !_isRefreshingAfterDraftSave) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Seleziona un video prima di procedere'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    
    // Title is now optional for all platforms including YouTube
    // Removed validation check that previously made title required for YouTube
    
    // Ensure video is paused when navigating between steps
    if (_videoPlayerController != null && _videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
    }
    
    setState(() {
      if (_currentStep == UploadStep.selectMedia) {
        _currentStep = UploadStep.addDetails;
        _pageController.animateToPage(
          1,
          duration: Duration(milliseconds: 300), // Ridotto da 400 a 300ms
          curve: Curves.easeOutCubic, // Curva più performante
        );
      } else if (_currentStep == UploadStep.addDetails) {
        _currentStep = UploadStep.selectAccounts;
        
        // Improved animation for transition to accounts section
        _pageController.animateToPage(
          2,
          duration: Duration(milliseconds: 200),  // Ridotto da 250 a 200ms
          curve: Curves.easeOutCubic,   // Curva più performante
        );
      }
    });
  }

  // Method to go to previous step
  void _goToPreviousStep() {
    // Ensure video is paused when navigating between steps
    if (_videoPlayerController != null && _videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
    }
    
    setState(() {
      if (_currentStep == UploadStep.selectAccounts) {
        _currentStep = UploadStep.addDetails;
        _pageController.animateToPage(
          1,
          duration: Duration(milliseconds: 200),  // Ridotto da 250 a 200ms
          curve: Curves.easeOutCubic,   // Curva più performante
        );
      } else if (_currentStep == UploadStep.addDetails) {
        _currentStep = UploadStep.selectMedia;
        _pageController.animateToPage(
          0,
          duration: Duration(milliseconds: 300), // Ridotto da 400 a 300ms
          curve: Curves.easeOutCubic, // Curva più performante
        );
      }
    });
  }

  // Check if current step can proceed
  bool _canProceedFromCurrentStep() {
    switch (_currentStep) {
      case UploadStep.selectMedia:
        return _videoFile != null;
      case UploadStep.addDetails:
        return true; // Always allow proceeding from details step
      case UploadStep.selectAccounts:
        return _selectedAccounts.isNotEmpty;
      default:
        return false;
    }
  }

  // Add method to load user credits
  Future<void> _loadUserCredits() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final creditsSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('credits')
          .get();

      // Get premium status
      final isPremiumSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('isPremium')
          .get();

      if (mounted) {
        setState(() {
          _userCredits = (creditsSnapshot.value as int?) ?? 750;
          _isPremium = (isPremiumSnapshot.value as bool?) ?? false;
        });
      }
    } catch (e) {
      print('Error loading user credits: $e');
    }
  }
  void _loadDraftDataFromService(Map<String, dynamic>? draftData, String? draftId) {
    if (draftData == null) return;
    
    // Imposta il draftId se fornito
    if (draftId != null) {
      // TODO: Gestire il draftId se necessario
    }
    
    // Carica i dati del draft usando la stessa logica di _loadDraftData
    final draft = draftData;
    
    // Set video file - handle both video_path and media_url
    String? videoPath = draft['video_path'] ?? draft['media_url'];
    if (videoPath != null) {
      // Check if it's a URL (starts with http:// or https://)
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        _loadVideoFromUrl(videoPath);
      } else {
        // Handle local file path
        final videoFile = File(videoPath);
        
        // Check if file exists
        if (videoFile.existsSync()) {
          setState(() {
            _videoFile = videoFile;
            _showCheckmark = true;
            _isImageFile = videoPath.toLowerCase().endsWith('.jpg') || 
                         videoPath.toLowerCase().endsWith('.jpeg') || 
                         videoPath.toLowerCase().endsWith('.png');
            _isVideoFromUrl = false; // Reset flag for local files
          });
          
          // Initialize video player if it's a video
          if (!_isImageFile) {
            _initializeVideoPlayer(videoFile);
          }
          
          // Passa al secondo step dopo un breve ritardo
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _goToNextStep();
            }
          });
        } else {
          // Try to find the file in the app's local storage
          final fileName = videoPath.split('/').last;
          getApplicationDocumentsDirectory().then((directory) {
            final localPath = '${directory.path}/$fileName';
            final localFile = File(localPath);
            if (localFile.existsSync()) {
                          setState(() {
              _videoFile = localFile;
              _showCheckmark = true;
              _isImageFile = localPath.toLowerCase().endsWith('.jpg') || 
                           localPath.toLowerCase().endsWith('.jpeg') || 
                           localPath.toLowerCase().endsWith('.png');
              _isVideoFromUrl = false; // Reset flag for local files
              _isVideoFromUrl = false; // Reset flag for local files
            });
              
              // Initialize video player if it's a video
              if (!_isImageFile) {
                _initializeVideoPlayer(localFile);
              }
              
              // Passa al secondo step dopo un breve ritardo
              Future.delayed(Duration(milliseconds: 500), () {
                if (mounted) {
                  _goToNextStep();
                }
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not find video file: $fileName'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          });
        }
      }
    }
    
    // Set title and description
    _titleController.text = draft['title'] ?? '';
    _descriptionController.text = draft['description'] ?? '';
    
    // Load YouTube thumbnail if available
    final youtubeThumbnailPath = draft['youtube_thumbnail_path'];
    if (youtubeThumbnailPath != null && youtubeThumbnailPath.isNotEmpty) {
      final thumbnailFile = File(youtubeThumbnailPath);
      if (thumbnailFile.existsSync()) {
        setState(() {
          _youtubeThumbnailFile = thumbnailFile;
        });
      }
    }
    
    // Set selected accounts with safe type casting
    try {
      final accounts = draft['accounts'];
      if (accounts != null) {
        Map<String, List<String>> selectedAccountsTemp = {};
        
        (accounts as Map).forEach((key, value) {
          if (key is String) {
            // Converti la chiave della piattaforma al formato corretto per _selectedAccounts
            String platformKey = key;
            if (key.isNotEmpty) {
              platformKey = key[0].toUpperCase() + key.substring(1).toLowerCase();
            }
            
            List<String> accountIds = [];
            
            if (value is List) {
              // Estrai gli ID degli account dalla lista
              for (var account in value) {
                if (account is Map) {
                  // Per YouTube, salva sia id che channel_id per garantire la corrispondenza
                  if (platformKey == 'Youtube' || platformKey == 'YouTube') {
                    platformKey = 'YouTube'; // Normalizza il nome della piattaforma
                    
                    if (account.containsKey('channel_id')) {
                      accountIds.add(account['channel_id'].toString());
                    } else if (account.containsKey('id')) {
                      accountIds.add(account['id'].toString());
                    } else if (account.containsKey('username')) {
                      accountIds.add(account['username'].toString());
                    }
                  } else {
                    // Per altre piattaforme, usa il metodo standard
                    if (account.containsKey('id')) {
                      accountIds.add(account['id'].toString());
                    } else if (account.containsKey('username')) {
                      accountIds.add(account['username'].toString());
                    }
                  }
                }
              }
            }
            
            if (accountIds.isNotEmpty) {
              selectedAccountsTemp[platformKey] = accountIds;
            }
          }
        });
        
        // Salva gli account selezionati temporaneamente
        // Li sostituiremo con gli ID corretti dopo aver caricato gli account
        _selectedAccounts.clear();
        _selectedAccounts.addAll(selectedAccountsTemp);
        
        print('Loaded accounts (preliminary): $_selectedAccounts');
      }
      
    } catch (e) {
      debugPrint('Error loading accounts data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading accounts data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _loadDraftData() {
    final draft = widget.draftData!;
    
    // Set video file - handle both video_path and media_url
    String? videoPath = draft['video_path'] ?? draft['media_url'];
    if (videoPath != null) {
      // Check if it's a URL (starts with http:// or https://)
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        _loadVideoFromUrl(videoPath);
      } else {
        // Handle local file path
        final videoFile = File(videoPath);
        
        // Check if file exists
        if (videoFile.existsSync()) {
          setState(() {
            _videoFile = videoFile;
            _showCheckmark = true;
            _isImageFile = videoPath.toLowerCase().endsWith('.jpg') || 
                         videoPath.toLowerCase().endsWith('.jpeg') || 
                         videoPath.toLowerCase().endsWith('.png');
            _isVideoFromUrl = false; // Reset flag for local files
          });
          
          // Initialize video player if it's a video
          if (!_isImageFile) {
            _initializeVideoPlayer(videoFile);
          }
          
          // Passa al secondo step dopo un breve ritardo
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              _goToNextStep();
            }
          });
        } else {
          // Try to find the file in the app's local storage
          final fileName = videoPath.split('/').last;
          getApplicationDocumentsDirectory().then((directory) {
            final localPath = '${directory.path}/$fileName';
            final localFile = File(localPath);
            if (localFile.existsSync()) {
                          setState(() {
              _videoFile = localFile;
              _showCheckmark = true;
              _isImageFile = localPath.toLowerCase().endsWith('.jpg') || 
                           localPath.toLowerCase().endsWith('.jpeg') || 
                           localPath.toLowerCase().endsWith('.png');
              _isVideoFromUrl = false; // Reset flag for local files
              _isVideoFromUrl = false; // Reset flag for local files
            });
              
              // Initialize video player if it's a video
              if (!_isImageFile) {
                _initializeVideoPlayer(localFile);
              }
              
              // Passa al secondo step dopo un breve ritardo
              Future.delayed(Duration(milliseconds: 500), () {
                if (mounted) {
                  _goToNextStep();
                }
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not find video file: $fileName'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          });
        }
      }
    }
    
    // Set title and description
    _titleController.text = draft['title'] ?? '';
    _descriptionController.text = draft['description'] ?? '';
    
    // Load YouTube thumbnail if available
    final youtubeThumbnailPath = draft['youtube_thumbnail_path'];
    if (youtubeThumbnailPath != null && youtubeThumbnailPath.isNotEmpty) {
      final thumbnailFile = File(youtubeThumbnailPath);
      if (thumbnailFile.existsSync()) {
        setState(() {
          _youtubeThumbnailFile = thumbnailFile;
        });
      }
    }
    
    // Set selected accounts with safe type casting
    try {
      final accounts = draft['accounts'];
      if (accounts != null) {
        Map<String, List<String>> selectedAccountsTemp = {};
        
        (accounts as Map).forEach((key, value) {
          if (key is String) {
            // Converti la chiave della piattaforma al formato corretto per _selectedAccounts
            // (prima lettera maiuscola, resto minuscolo)
            String platformKey = key;
            if (key.isNotEmpty) {
              platformKey = key[0].toUpperCase() + key.substring(1).toLowerCase();
            }
            
            List<String> accountIds = [];
            
            if (value is List) {
              // Estrai gli ID degli account dalla lista
              for (var account in value) {
                if (account is Map) {
                  // Per YouTube, salva sia id che channel_id per garantire la corrispondenza
                  if (platformKey == 'Youtube' || platformKey == 'YouTube') {
                    platformKey = 'YouTube'; // Normalizza il nome della piattaforma
                    
                    if (account.containsKey('channel_id')) {
                      accountIds.add(account['channel_id'].toString());
                    } else if (account.containsKey('id')) {
                      accountIds.add(account['id'].toString());
                    } else if (account.containsKey('username')) {
                      accountIds.add(account['username'].toString());
                    }
                  } else {
                    // Per altre piattaforme, usa il metodo standard
                    if (account.containsKey('id')) {
                      accountIds.add(account['id'].toString());
                    } else if (account.containsKey('username')) {
                      accountIds.add(account['username'].toString());
                    }
                  }
                }
              }
            }
            
            if (accountIds.isNotEmpty) {
              selectedAccountsTemp[platformKey] = accountIds;
            }
          }
        });
        
        // Salva gli account selezionati temporaneamente
        // Li sostituiremo con gli ID corretti dopo aver caricato gli account
        _selectedAccounts.clear();
        _selectedAccounts.addAll(selectedAccountsTemp);
        
        print('Loaded accounts (preliminary): $_selectedAccounts');
      }
      
    } catch (e) {
      debugPrint('Error loading accounts data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading accounts data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleAccount(String platform, String accountId) {
    print('Toggling account selection: Platform=$platform, AccountID=$accountId');
    
    // Check if trying to select YouTube account with image file
    if (platform == 'YouTube' && _isImageFile && !(_selectedAccounts[platform]?.contains(accountId) ?? false)) {
      // Show warning message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'YouTube does not support image uploads. Please select a video file.',
            style: TextStyle(fontSize: 14, color: Colors.black),
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.white,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: EdgeInsets.all(16),
          elevation: 2,
        ),
      );
      return; // Prevent selection
    }
    
    // Prima verifica se l'account è già selezionato
    bool isAlreadySelected = _selectedAccounts[platform]?.contains(accountId) ?? false;
    
    setState(() {
      if (!_selectedAccounts.containsKey(platform)) {
        _selectedAccounts[platform] = [];
      }
      
      if (isAlreadySelected) {
        print('Removing account: $accountId from platform: $platform');
        _selectedAccounts[platform]!.remove(accountId);
        if (_selectedAccounts[platform]!.isEmpty) {
          _selectedAccounts.remove(platform);
        }
      } else {
        print('Adding account: $accountId to platform: $platform');
        _selectedAccounts[platform]!.add(accountId);
        

        
        // Non mostrare più il popup di configurazione automaticamente
        // _showAccountConfigBottomSheet(platform, accountId);
      }
    });
  }


  // Navigate to social account details page
  void _navigateToSocialAccountDetails(Map<String, dynamic> account, String platform) {
    final accountData = {
      'username': account['username']?.toString() ?? '',
      'displayName': account['display_name']?.toString() ?? account['username']?.toString() ?? '',
      'profileImageUrl': account['profile_image_url']?.toString() ?? '',
      'id': (account['id'] ?? account['channel_id'] ?? account['user_id'] ?? account['username'] ?? '').toString(),
      'channel_id': (account['channel_id'] ?? account['id'] ?? account['username'] ?? '').toString(),
      'user_id': (account['user_id'] ?? account['id'] ?? account['username'] ?? '').toString(),
      'followersCount': (account['followers_count'] ?? account['follower_count'] ?? account['subscriber_count'] ?? '0').toString(),
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


  // Nuovo metodo per mostrare il popup di configurazione dell'account
  void _showAccountConfigBottomSheet(String platform, String accountId) {
    // Troviamo i dati dell'account
    final account = _socialAccounts[platform]?.firstWhere(
      (acc) => acc['id'] == accountId,
      orElse: () => <String, dynamic>{},
    );
    
    if (account == null || account.isEmpty) return;
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accountUsername = account['username'] as String? ?? '';
    final displayName = account['display_name'] ?? accountUsername;
    final profileImageUrl = account['profile_image_url'] as String?;
    
    // Inizializza i controller con i valori esistenti o con i valori globali
    if (_platformTitleControllers[platform] == null) {
      _platformTitleControllers[platform] = TextEditingController();
    }
    
    if (_platformDescriptionControllers[platform] == null) {
      _platformDescriptionControllers[platform] = TextEditingController();
    }
    
    if (_platformPromptControllers[platform] == null) {
      _platformPromptControllers[platform] = TextEditingController();
    }
    
    // Se si usa il contenuto globale, popoliamo con i valori globali
    if (_usePlatformSpecificContent[platform] ?? true) {
      _platformTitleControllers[platform]!.text = _titleController.text;
      _platformDescriptionControllers[platform]!.text = _descriptionController.text;
    }
    
    // Creiamo un ID univoco per questo account
    final String accountConfigId = "${platform}_${accountId}";
    
    // Inizializziamo la mappa di configurazione specifica per account se non esiste
    if (_accountSpecificContent == null) {
      _accountSpecificContent = {};
    }
    
    // Ottieni la configurazione esistente o crea una nuova
    final accountConfig = _accountSpecificContent![accountConfigId] ?? {
      'useGlobalContent': true,
      'useAI': false,
      'title': _titleController.text,
      'description': _descriptionController.text,
      'prompt': '',
    };
    
    // Controller temporanei per questo account specifico
    final titleController = TextEditingController(text: accountConfig['title'] ?? _titleController.text);
    final descriptionController = TextEditingController(text: accountConfig['description'] ?? _descriptionController.text);
    final promptController = TextEditingController(text: accountConfig['prompt'] ?? '');
    
    // Stato locale per il bottom sheet
    bool useGlobalContent = accountConfig['useGlobalContent'] ?? true;
    bool useAI = accountConfig['useAI'] ?? false;
    bool isGeneratingDescription = false;
    

    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            // Ottimizzazione: rimuovo updateBothStates per evitare setState globali
            // void updateBothStates(Function() fn) {
            //   // Update dialog's state
            //   dialogSetState(fn);
            //   // Update parent's state
            //   setState(fn);
            // }
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 15,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 50,
                        height: 5,
                        margin: EdgeInsets.only(top: 12, bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[700] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    // Account header
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 15, 20, 5),
                      child: Row(
                        children: [
                          _buildAccountProfileImage(profileImageUrl, accountUsername, theme),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  platform == 'TikTok' ? accountUsername : '@$accountUsername',
                                  style: TextStyle(
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          Image.asset(
                            _platformLogos[platform] ?? '',
                            width: 32,
                            height: 32,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 20, color: isDark ? Colors.grey[800] : null),
                    
                    // Content toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            'Use general content',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Switch(
                            value: useGlobalContent,
                            onChanged: (value) {
                              dialogSetState(() {
                                useGlobalContent = value;
                                if (value) {
                                  // Passa a contenuto generale
                                  titleController.text = _titleController.text;
                                  descriptionController.text = _descriptionController.text;
                                }
                              });
                            },
                            activeColor: Color(0xFF667eea),
                          ),
                        ],
                      ),
                    ),
                    
                    // Contenuto scrollabile - ottimizzato per performance
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        physics: BouncingScrollPhysics(), // Fisica più fluida
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title field
                            if (_platformSupportsTitle(platform))
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Title',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      if (useGlobalContent && platform != 'YouTube')
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
                                          'General content',
                                          style: TextStyle(
                                              color: Colors.white,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 13,
                                            ),
                                          ),
                                        )
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Card(
                                    elevation: 0,
                                    color: isDark ? Colors.grey[800] : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: TextField(
                                        enabled: platform == 'YouTube' ? true : !useGlobalContent,
                                        controller: titleController,
                                        textInputAction: TextInputAction.next, // Migliora UX
                                        decoration: InputDecoration(
                                          hintText: 'Specific title for $platform',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.all(12),
                                          hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
                                          suffixIcon: (platform == 'YouTube' || !useGlobalContent)
                                            ? ShaderMask(
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
                                                child: Icon(
                                                Icons.edit,
                                                size: 16,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : ShaderMask(
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
                                                child: Icon(
                                                Icons.sync,
                                                size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                        ),
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                ],
                              ),
                            
                            // Description field
                            if (_platformSupportsDescription(platform))
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Description',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      if (!useGlobalContent)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
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
                                              'Use AI',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 4),
                                            Switch(
                                              value: useAI,
                                              onChanged: (value) {
                                                dialogSetState(() {
                                                  useAI = value;
                                                });
                                              },
                                              activeColor: Color(0xFF667eea),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ],
                                        )
                                      else
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
                                          'General content',
                                          style: TextStyle(
                                              color: Colors.white,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 13,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  
                                  // Prompt AI per descrizione
                                  if (!useGlobalContent && useAI)
                                    Column(
                                      children: [
                                        Card(
                                          elevation: 0,
                                          color: isDark ? Colors.grey[800] : null,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                              width: 1,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: TextField(
                                              controller: promptController,
                                              decoration: InputDecoration(
                                                hintText: 'What is this content about?',
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.all(12),
                                                hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
                                                suffixIcon: IconButton(
                                                  icon: isGeneratingDescription
                                                    ? SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: theme.colorScheme.primary,
                                                        ),
                                                      )
                                                    : Icon(
                                                        Icons.auto_awesome,
                                                        color: theme.colorScheme.primary,
                                                      ),
                                                  onPressed: isGeneratingDescription 
                                                    ? null 
                                                    : () async {
                                                        dialogSetState(() {
                                                          isGeneratingDescription = true;
                                                        });
                                                        
                                                        try {
                                                          // Utilizzo l'implementazione esistente
                                                          await _generatePlatformSpecificDescription(
                                                            platform, 
                                                            promptController.text,
                                                            (result) {
                                                              dialogSetState(() {
                                                                descriptionController.text = result;
                                                              });
                                                            }
                                                          );
                                                        } finally {
                                                          dialogSetState(() {
                                                            isGeneratingDescription = false;
                                                          });
                                                        }
                                                      },
                                                ),
                                              ),
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: 12),
                                      ],
                                    ),
                                    
                                  Card(
                                    elevation: 0,
                                    color: isDark ? Colors.grey[800] : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: TextField(
                                        enabled: !useGlobalContent,
                                        controller: descriptionController,
                                                                              maxLines: _getDescriptionMaxLines(platform),
                                        maxLength: _getCharacterLimitForPlatformAndAccount(platform, accountId),
                                        textInputAction: TextInputAction.done, // Migliora UX
                                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                                          return null; // Disabilita il contatore standard
                                        },
                                        decoration: InputDecoration(
                                          hintText: 'Specific description for $platform',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.all(12),
                                          hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
                                        ),
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  // Contatore caratteri e barra di progresso
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          if (!useGlobalContent && useAI && descriptionController.text.isNotEmpty)
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.auto_awesome,
                                                  size: 12,
                                                  color: theme.colorScheme.primary,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Generated with AI',
                                                  style: TextStyle(
                                                    color: theme.colorScheme.primary,
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else
                                            SizedBox.shrink(),
                                      Text(
                                            '${descriptionController.text.length} / ${_getCharacterLimitForPlatformAndAccount(platform, accountId)}',
                                        style: TextStyle(
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: descriptionController.text.length / _getCharacterLimitForPlatformAndAccount(platform, accountId),
                                          minHeight: 4,
                                          backgroundColor: isDark ? Colors.grey[700] : Colors.grey[200],
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            _getProgressColor(
                                              descriptionController.text.length / _getCharacterLimitForPlatformAndAccount(platform, accountId),
                                              theme,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            
                              // Sezione Privacy per TikTok
                              if (platform == 'TikTok')
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 20),
                                    Text(
                                      'Privacy Settings',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    
                                    // Privacy Level Dropdown
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.grey[700] : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                                          width: 1,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _tiktokOptions[accountId]?['privacy_level'],
                                          hint: Text(
                                            'Select privacy level (required)',
                                            style: TextStyle(
                                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                          isExpanded: true,
                                          icon: Icon(
                                            Icons.arrow_drop_down,
                                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          ),
                                          items: [
                                            DropdownMenuItem(
                                              value: 'SELF_ONLY',
                                              child: Text('Private (Only me)'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'FRIENDS',
                                              child: Text('Friends'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'PUBLIC',
                                              child: Text('Public'),
                                            ),
                                          ],
                                          onChanged: (String? newValue) {
                                            dialogSetState(() {
                                              // Initialize TikTok options for this account if not exists
                                              if (!_tiktokOptions.containsKey(accountId)) {
                                                _tiktokOptions[accountId] = {
                                                  'privacy_level': null,
                                                  'allow_comments': true,
                                                  'allow_duets': true,
                                                  'allow_stitch': true,
                                                  'commercial_content': false,
                                                  'own_brand': false,
                                                  'branded_content': false,
                                                };
                                              }
                                              
                                              _tiktokOptions[accountId]!['privacy_level'] = newValue;
                                              
                                              // Handle commercial content restrictions
                                              if (newValue == 'SELF_ONLY' && _tiktokOptions[accountId]!['branded_content']) {
                                                _tiktokOptions[accountId]!['branded_content'] = false;
                                                _tiktokOptions[accountId]!['commercial_content'] = false;
                                              }
                                            });
                                          },
                                          dropdownColor: isDark ? Colors.grey[700] : Colors.white,
                                          style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black87,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    
                                    // Interaction Settings Section
                                    Text(
                                      'Interaction Settings',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    
                                    // Comments
                                    CheckboxListTile(
                                      title: Text(
                                        'Allow comments',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      value: _tiktokOptions[accountId]?['allow_comments'] ?? true,
                                      onChanged: (bool? value) {
                                        dialogSetState(() {
                                          if (!_tiktokOptions.containsKey(accountId)) {
                                            _tiktokOptions[accountId] = {
                                              'privacy_level': null,
                                              'allow_comments': true,
                                              'allow_duets': true,
                                              'allow_stitch': true,
                                              'commercial_content': false,
                                              'own_brand': false,
                                              'branded_content': false,
                                            };
                                          }
                                          _tiktokOptions[accountId]!['allow_comments'] = value ?? true;
                                        });
                                      },
                                      activeColor: Color(0xFF667eea),
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity: ListTileControlAffinity.leading,
                                    ),
                                    
                                    // Duets (only for videos, not photos)
                                    if (!_isImageFile)
                                      CheckboxListTile(
                                        title: Text(
                                          'Allow duets',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        value: _tiktokOptions[accountId]?['allow_duets'] ?? true,
                                        onChanged: (bool? value) {
                                          dialogSetState(() {
                                            if (!_tiktokOptions.containsKey(accountId)) {
                                              _tiktokOptions[accountId] = {
                                                'privacy_level': null,
                                                'allow_comments': true,
                                                'allow_duets': true,
                                                'allow_stitch': true,
                                                'commercial_content': false,
                                                'own_brand': false,
                                                'branded_content': false,
                                              };
                                            }
                                            _tiktokOptions[accountId]!['allow_duets'] = value ?? true;
                                          });
                                        },
                                        activeColor: Color(0xFF667eea),
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity: ListTileControlAffinity.leading,
                                      ),
                                    
                                    // Stitch (only for videos, not photos)
                                    if (!_isImageFile)
                                      CheckboxListTile(
                                        title: Text(
                                          'Allow stitch',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        value: _tiktokOptions[accountId]?['allow_stitch'] ?? true,
                                        onChanged: (bool? value) {
                                          dialogSetState(() {
                                            if (!_tiktokOptions.containsKey(accountId)) {
                                              _tiktokOptions[accountId] = {
                                                'privacy_level': null,
                                                'allow_comments': true,
                                                'allow_duets': true,
                                                'allow_stitch': true,
                                                'commercial_content': false,
                                                'own_brand': false,
                                                'branded_content': false,
                                              };
                                            }
                                            _tiktokOptions[accountId]!['allow_stitch'] = value ?? true;
                                          });
                                        },
                                        activeColor: Color(0xFF667eea),
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity: ListTileControlAffinity.leading,
                                      ),
                                    
                                    SizedBox(height: 16),
                                    
                                    // Commercial Content Section
                                    Text(
                                      'Commercial Content Disclosure',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    
                                    // Commercial Content Toggle
                                    SwitchListTile(
                                      title: Text(
                                        'This content promotes a brand, product, or service',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      value: _tiktokOptions[accountId]?['commercial_content'] ?? false,
                                      onChanged: (bool value) {
                                        dialogSetState(() {
                                          if (!_tiktokOptions.containsKey(accountId)) {
                                            _tiktokOptions[accountId] = {
                                              'privacy_level': null,
                                              'allow_comments': true,
                                              'allow_duets': true,
                                              'allow_stitch': true,
                                              'commercial_content': false,
                                              'own_brand': false,
                                              'branded_content': false,
                                            };
                                          }
                                          _tiktokOptions[accountId]!['commercial_content'] = value;
                                          if (!value) {
                                            _tiktokOptions[accountId]!['own_brand'] = false;
                                            _tiktokOptions[accountId]!['branded_content'] = false;
                                          }
                                        });
                                      },
                                      activeColor: Color(0xFF667eea),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    
                                    // Commercial Content Options (only shown when commercial content is enabled)
                                    if (_tiktokOptions[accountId]?['commercial_content'] == true)
                                      Column(
                                        children: [
                                          SizedBox(height: 8),
                                          
                                          // Own Brand
                                          CheckboxListTile(
                                            title: Text(
                                              'Your own brand',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                            subtitle: Text(
                                              'Content will be labeled as "Promotional Content"',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              ),
                                            ),
                                            value: _tiktokOptions[accountId]?['own_brand'] ?? false,
                                            onChanged: (bool? value) {
                                              dialogSetState(() {
                                                if (!_tiktokOptions.containsKey(accountId)) {
                                                  _tiktokOptions[accountId] = {
                                                    'privacy_level': null,
                                                    'allow_comments': true,
                                                    'allow_duets': true,
                                                    'allow_stitch': true,
                                                    'commercial_content': false,
                                                    'own_brand': false,
                                                    'branded_content': false,
                                                  };
                                                }
                                                _tiktokOptions[accountId]!['own_brand'] = value ?? false;
                                              });
                                            },
                                            activeColor: Color(0xFF667eea),
                                            contentPadding: EdgeInsets.zero,
                                            controlAffinity: ListTileControlAffinity.leading,
                                          ),
                                          
                                          // Branded Content
                                          CheckboxListTile(
                                            title: Text(
                                              'Branded content',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                            subtitle: Text(
                                              'Content will be labeled as "Paid Partnership"',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              ),
                                            ),
                                            value: _tiktokOptions[accountId]?['branded_content'] ?? false,
                                            onChanged: _tiktokOptions[accountId]?['privacy_level'] == 'SELF_ONLY' 
                                              ? null 
                                              : (bool? value) {
                                                  dialogSetState(() {
                                                    if (!_tiktokOptions.containsKey(accountId)) {
                                                      _tiktokOptions[accountId] = {
                                                        'privacy_level': null,
                                                        'allow_comments': true,
                                                        'allow_duets': true,
                                                        'allow_stitch': true,
                                                        'commercial_content': false,
                                                        'own_brand': false,
                                                        'branded_content': false,
                                                      };
                                                    }
                                                    _tiktokOptions[accountId]!['branded_content'] = value ?? false;
                                                  });
                                                },
                                            activeColor: Color(0xFF667eea),
                                            contentPadding: EdgeInsets.zero,
                                            controlAffinity: ListTileControlAffinity.leading,
                                          ),
                                          
                                          // Warning message for branded content with private privacy
                                          if (_tiktokOptions[accountId]?['privacy_level'] == 'SELF_ONLY')
                                            Container(
                                              margin: EdgeInsets.only(top: 8),
                                              padding: EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.orange.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.warning_amber_outlined,
                                                    color: Colors.orange,
                                                    size: 16,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Branded content cannot be private',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.orange[700],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          
                                          // Compliance declaration messages
                                          if (_tiktokOptions[accountId]?['commercial_content'] == true)
                                            Container(
                                              margin: EdgeInsets.only(top: 12),
                                              padding: EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.blue.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.info_outline,
                                                        color: Colors.blue,
                                                        size: 16,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Compliance Declaration',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: isDark ? Colors.blue[200] : Colors.blue[700],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 8),
                                                  _getTikTokComplianceMessage(accountId),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                            
                              // Sezione thumbnail personalizzata SOLO per YouTube verificato
                              if (platform == 'YouTube' && !_isImageFile && _isYouTubeAccountVerified(accountId))
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 20),
                                  Text(
                                      'Thumbnail',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                    SizedBox(height: 12),
                                    // Container principale per la thumbnail con proporzioni 16:9
                                  Container(
                                    width: double.infinity,
                                      height: 180, // 16:9 ratio (320x180)
                                    decoration: BoxDecoration(
                                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                      child: _youtubeThumbnailFile != null
                                          ? Stack(
                                              children: [
                                                // Immagine della thumbnail
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.file(
                                                    _youtubeThumbnailFile!,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                                // Overlay scuro per migliorare la visibilità dei controlli
                                                Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(12),
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topCenter,
                                                      end: Alignment.bottomCenter,
                                                      colors: [
                                                        Colors.transparent,
                                                        Colors.black.withOpacity(0.3),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // Pulsante X per rimuovere la thumbnail (cerchio più piccolo)
                                                Positioned(
                                                  top: 6,
                                                  right: 6,
                                                  child: Container(
                                                    width: 18,
                                                    height: 18,
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.6),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: IconButton(
                                                      icon: Icon(
                                                        Icons.close,
                                                        color: Colors.white,
                                                        size: 14,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _youtubeThumbnailFile = null;
                                                        });
                                                        dialogSetState(() {});
                                                      },
                                                      tooltip: 'Remove thumbnail',
                                                      padding: EdgeInsets.zero,
                                                      constraints: BoxConstraints(
                                                        minWidth: 18,
                                                        minHeight: 18,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Center(
                                    child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                                  Icon(
                                                    Icons.image_outlined,
                                                    size: 48,
                                                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                                                  ),
                                        SizedBox(height: 12),
                                                  Text(
                                                    'No thumbnail selected',
                                                    style: TextStyle(
                                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  SizedBox(height: 16),
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
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: ElevatedButton.icon(
                                                      onPressed: () => _pickYouTubeThumbnail(dialogSetState),
                                                    icon: Icon(Icons.upload_file, size: 18),
                                                    label: Text('Select Thumbnail'),
                                                    style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.transparent,
                                                      foregroundColor: Colors.white,
                                                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        elevation: 0,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Max 2MB, JPG/PNG, 1280x720 recommended',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                                
                                // Messaggio informativo per account YouTube non verificati
                                if (platform == 'YouTube' && !_isImageFile && !_isYouTubeAccountVerified(accountId))
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(height: 20),
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.blue.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: Colors.blue,
                                              size: 20,
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'YouTube allows custom thumbnails only for verified accounts with phone number verification.',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: isDark ? Colors.blue[200] : Colors.blue[700],
                                                ),
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
                    ),
                    
                    // Bottoni di azione
                    Container(
                       padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: theme.colorScheme.primary.withOpacity(0.5),
                                ),
                              ),
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
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
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
                              onPressed: () {
                                // Salva le impostazioni
                                _accountSpecificContent![accountConfigId] = {
                                  'useGlobalContent': useGlobalContent,
                                  'useAI': useAI,
                                  'title': titleController.text,
                                  'description': descriptionController.text,
                                  'prompt': promptController.text,
                                };
                                
                                // Salva le opzioni TikTok se la piattaforma è TikTok
                                if (platform == 'TikTok') {
                                  if (!_tiktokOptions.containsKey(accountId)) {
                                    _tiktokOptions[accountId] = {
                                      'privacy_level': null,
                                      'allow_comments': false,
                                      'allow_duets': false,
                                      'allow_stitch': false,
                                      'commercial_content': false,
                                      'own_brand': false,
                                      'branded_content': false,
                                    };
                                  }
                                  // Le opzioni TikTok sono già state aggiornate durante l'interazione dell'utente
                                }
                                
                                // Update ChatGPT flag for this platform
                                _useChatGPTforPlatform[platform] = useAI;
                                
                                // Aggiorna il conteggio della descrizione
                                _platformDescriptionLengths[platform] = descriptionController.text.length;
                                
                                // Update platform controllers with the new values
                                _platformTitleControllers[platform]!.text = titleController.text;
                                _platformDescriptionControllers[platform]!.text = descriptionController.text;
                                _platformPromptControllers[platform]!.text = promptController.text;
                                
                                // Make sure Instagram content type persists when dialog is closed
                                // Now content type is only changed via the buttons below description
                                
                                // Ottimizzazione: aggiorna solo i dati necessari senza setState globale
                                // setState(() {
                                //   // This forces a refresh of the main UI
                                // });
                                
                                // Chiudi il bottom sheet
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                  elevation: 0,
                              ),
                              child: Text(
                                'Save',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
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
            );
          }
        );
      },
    );
  }

  // Method to check if YouTube account is verified
  bool _isYouTubeAccountVerified(String accountId) {
    try {
      // Cerca l'account nei dati già caricati
      final youtubeAccounts = _socialAccounts['YouTube'] ?? [];
      final account = youtubeAccounts.firstWhere(
        (acc) => acc['id'] == accountId,
        orElse: () => <String, dynamic>{},
      );
      
      // Controlla se l'account ha il flag is_verified
      return account['is_verified'] == true;
    } catch (e) {
      print('Error checking YouTube account verification status: $e');
      return false;
    }
  }

  // Method to check if a Twitter account is verified
  bool _isTwitterAccountVerified(String accountId) {
    try {
      // Cerca l'account nei dati già caricati
      final twitterAccounts = _socialAccounts['Twitter'] ?? [];
      final account = twitterAccounts.firstWhere(
        (acc) => acc['id'] == accountId,
        orElse: () => <String, dynamic>{},
      );
      
      // Controlla se l'account ha il flag verified
      return account['verified'] == true;
    } catch (e) {
      print('Error checking Twitter account verification status: $e');
      return false;
    }
  }

  // Method to get dynamic character limit for Twitter based on verification status
  int _getTwitterCharacterLimit(String accountId) {
    if (_isTwitterAccountVerified(accountId)) {
      return 25000; // 25,000 characters for verified Twitter accounts
    } else {
      return 280; // Standard 280 characters for unverified Twitter accounts
    }
  }

  // Method to get character limit for a specific platform and account
  int _getCharacterLimitForPlatformAndAccount(String platform, String accountId) {
    if (platform == 'Twitter') {
      return _getTwitterCharacterLimit(accountId);
    } else {
      return _platformDescriptionLimits[platform] ?? 2200;
    }
  }
  // Method to pick YouTube thumbnail
  Future<void> _pickYouTubeThumbnail([void Function(void Function())? dialogSetState]) async {
    // Utilizza il metodo helper per richiedere i permessi della galleria
    bool hasPermission = await _requestGalleryPermission();
    if (!hasPermission) {
      return; // Esci se i permessi non sono stati concessi
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280, // YouTube maxres thumbnail size
        maxHeight: 720,
        imageQuality: 90,
      );
      
      if (image != null) {
        setState(() {
          _youtubeThumbnailFile = File(image.path);
        });
        print('***YOUTUBE THUMBNAIL*** upload_video_page.dart: selezionata thumbnail path: \'${image.path}\', exists: \'${File(image.path).existsSync()}\'');
        
        // Aggiorna anche il bottom sheet se è aperto
        if (dialogSetState != null) {
          // Piccolo delay per assicurarsi che l'immagine sia caricata
          Future.delayed(Duration(milliseconds: 100), () {
            dialogSetState(() {});
          });
        }
      }
    } catch (e) {
      print('Error picking YouTube thumbnail: $e');
      _showPermissionSnackBar('Error selecting thumbnail: $e');
    }
  }

  // Method to handle when a video is picked
  Future<void> _pickMedia() async {
    // Gestione permessi multi-piattaforma
    PermissionStatus status;
    bool isAndroid = false;
    bool isIOS = false;
    try {
      isAndroid = Theme.of(context).platform == TargetPlatform.android;
      isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    } catch (_) {}

    if (isAndroid) {
      print('[PERMISSION] Android: controllo stato permessi...');
      final photosGranted = await Permission.photos.isGranted;
      final videosGranted = await Permission.videos.isGranted;
      final storageGranted = await Permission.storage.isGranted;
      final cameraGranted = await Permission.camera.isGranted;
      print('[PERMISSION] Stato: photos=$photosGranted, videos=$videosGranted, storage=$storageGranted, camera=$cameraGranted');
      if (photosGranted || videosGranted || storageGranted || cameraGranted) {
        status = PermissionStatus.granted;
      } else {
        print('[PERMISSION] Nessun permesso già concesso, chiedo in sequenza...');
        status = await Permission.photos.request();
        print('[PERMISSION] Dopo richiesta photos: ${status.toString()}');
        if (!status.isGranted) {
          status = await Permission.videos.request();
          print('[PERMISSION] Dopo richiesta videos: ${status.toString()}');
        }
        if (!status.isGranted) {
          status = await Permission.storage.request();
          print('[PERMISSION] Dopo richiesta storage: ${status.toString()}');
        }
        if (!status.isGranted) {
          status = await Permission.camera.request();
          print('[PERMISSION] Dopo richiesta camera: ${status.toString()}');
        }
      }
    } else if (isIOS) {
      print('[PERMISSION] iOS: controllo stato permessi...');
      final photosGranted = await Permission.photos.isGranted;
      final cameraGranted = await Permission.camera.isGranted;
      print('[PERMISSION] Stato iOS: photos=$photosGranted, camera=$cameraGranted');
      
      if (photosGranted || cameraGranted) {
        status = PermissionStatus.granted;
      } else {
        print('[PERMISSION] iOS: nessun permesso già concesso, apro direttamente la tendina per permettere selezione media...');
        // Su iOS, non richiediamo permessi qui - lasciamo che image_picker gestisca i permessi quando necessario
        // Questo permette all'utente di vedere la tendina di selezione e accettare i permessi reali del sistema
        status = PermissionStatus.granted;
      }
    } else {
      print('[PERMISSION] Altro OS: chiedo permesso photos e camera...');
      status = await Permission.photos.request();
      print('[PERMISSION] Dopo richiesta photos: ${status.toString()}');
      if (!status.isGranted) {
        status = await Permission.camera.request();
        print('[PERMISSION] Dopo richiesta camera: ${status.toString()}');
      }
    }

    if (status.isGranted) {
      print('[PERMISSION] Permesso CONCESSO, apro la tendina media!');
      final theme = Theme.of(context);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 15,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            margin: EdgeInsets.symmetric(horizontal: 8),
            padding: EdgeInsets.only(top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar for drag indication
                Container(
                  width: 50,
                  height: 5,
                  margin: EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_photo_alternate,
                          color: theme.colorScheme.primary,
                          size: 22,
                        ),
                      ),
                      SizedBox(width: 16),
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
                          'Select media type',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                // Media options
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark ? Colors.grey[850] : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Immagine dalla galleria
                      _buildMediaOptionTile(
                        context,
                        Icons.photo_library_outlined,
                        'Image from gallery',
                        'Upload an image from your device',
                        BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        () async {
                          Navigator.pop(context);
                          // Richiedi permesso specifico per la galleria
                          if (await _requestGalleryPermission()) {
                            final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                            if (image != null) {
                              setState(() {
                                _videoFile = File(image.path);
                                _showCheckmark = true;
                                _isImageFile = true;
                              });
                              // Go directly to step 2
                              _goToNextStep();
                            }
                          }
                        },
                      ),
                      Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey.shade200),
                      // Video dalla galleria
                      _buildMediaOptionTile(
                        context,
                        Icons.videocam_outlined,
                        'Video from gallery',
                        'Upload a video from your device',
                        null,
                        () async {
                          Navigator.pop(context);
                          // Richiedi permesso specifico per la galleria
                          if (await _requestGalleryPermission()) {
                            final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
                            if (video != null) {
                              final videoFile = File(video.path);
                              setState(() {
                                _videoFile = videoFile;
                                _showCheckmark = true;
                                _isImageFile = false;
                              });
                              // Open the video editor page immediately
                              await _openVideoEditor(videoFile);
                            }
                          }
                        },
                      ),
                      Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey.shade200),
                      // Scatta foto
                      _buildMediaOptionTile(
                        context,
                        Icons.photo_camera_outlined,
                        'Take photo',
                        'Use the camera to take a new image',
                        null,
                        () async {
                          Navigator.pop(context);
                          // Richiedi permesso specifico per la fotocamera
                          if (await _requestCameraPermission()) {
                            final XFile? image = await _picker.pickImage(source: ImageSource.camera);
                            if (image != null) {
                              setState(() {
                                _videoFile = File(image.path);
                                _showCheckmark = true;
                                _isImageFile = true;
                              });
                              // Go directly to step 2
                              _goToNextStep();
                            }
                          }
                        },
                      ),
                      Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey.shade200),
                      // Registra video
                      _buildMediaOptionTile(
                        context,
                        Icons.videocam,
                        'Record video',
                        'Use the camera to record a new video',
                        BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        () async {
                          Navigator.pop(context);
                          // Richiedi permesso specifico per la fotocamera
                          if (await _requestCameraPermission()) {
                            final XFile? video = await _picker.pickVideo(source: ImageSource.camera);
                            if (video != null) {
                              final videoFile = File(video.path);
                              setState(() {
                                _videoFile = videoFile;
                                _showCheckmark = true;
                                _isImageFile = false;
                              });
                              // Open the video editor page immediately
                              await _openVideoEditor(videoFile);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          );
        },
      );
      return;
    } else if (status.isPermanentlyDenied) {
      print('[PERMISSION] Permesso PERMANENTEMENTE NEGATO, mostro dialog impostazioni.');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Permission required'),
            content: Text('To select a video or photo from the gallery, you need to grant access to photos.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await openAppSettings();
                },
                child: Text('Open settings'),
              ),
            ],
          ),
        );
      }
      return;
    } else {
      print('[PERMISSION] Permesso NEGATO, mostro snackbar. Stato: ${status.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permission required to access the gallery.')),
        );
      }
      return;
    }
  }

  /// Richiede specificamente il permesso per accedere alla galleria foto/video
  Future<bool> _requestGalleryPermission() async {
    PermissionStatus status;
    bool isAndroid = false;
    bool isIOS = false;
    
    try {
      isAndroid = Theme.of(context).platform == TargetPlatform.android;
      isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    } catch (_) {}

    if (isAndroid) {
      print('[PERMISSION] Android: richiedo permesso galleria...');
      final photosGranted = await Permission.photos.isGranted;
      final storageGranted = await Permission.storage.isGranted;
      
      if (photosGranted || storageGranted) {
        status = PermissionStatus.granted;
      } else {
        // Prova prima con photos, poi con storage per compatibilità
        status = await Permission.photos.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      }
    } else if (isIOS) {
      print('[PERMISSION] iOS: controllo se permesso galleria già concesso...');
      final photosGranted = await Permission.photos.isGranted;
      if (photosGranted) {
        status = PermissionStatus.granted;
      } else {
        print('[PERMISSION] iOS: permesso non concesso, ma lascio che image_picker gestisca la richiesta...');
        // Su iOS, non richiediamo il permesso qui - lasciamo che image_picker lo gestisca
        // Questo evita il popup "Permission required" e permette i dialoghi di sistema reali
        status = PermissionStatus.granted;
      }
    } else {
      status = await Permission.photos.request();
    }

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        _showPermissionDeniedDialog('Gallery', 'To select photos and videos from your gallery, you need to grant access to photos.');
      } else {
        _showPermissionSnackBar('Gallery permission required to access your photos and videos.');
      }
      return false;
    }

    return true;
  }

  /// Richiede specificamente il permesso per accedere alla fotocamera
  Future<bool> _requestCameraPermission() async {
    PermissionStatus status;
    bool isIOS = false;
    
    try {
      isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    } catch (_) {}
    
    if (isIOS) {
      print('[PERMISSION] iOS: controllo se permesso fotocamera già concesso...');
      final cameraGranted = await Permission.camera.isGranted;
      if (cameraGranted) {
        status = PermissionStatus.granted;
      } else {
        print('[PERMISSION] iOS: permesso non concesso, ma lascio che image_picker gestisca la richiesta...');
        // Su iOS, non richiediamo il permesso qui - lasciamo che image_picker lo gestisca
        // Questo evita il popup "Permission required" e permette i dialoghi di sistema reali
        status = PermissionStatus.granted;
      }
    } else {
      print('[PERMISSION] Android/Altro: richiedo permesso fotocamera...');
      status = await Permission.camera.request();
    }

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        _showPermissionDeniedDialog('Camera', 'To take photos and record videos, you need to grant access to the camera.');
      } else {
        _showPermissionSnackBar('Camera permission required to take photos and record videos.');
      }
      return false;
    }

    return true;
  }

  /// Mostra un dialog per permessi negati permanentemente
  void _showPermissionDeniedDialog(String permissionType, String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionType Permission Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Mostra una snackbar per permessi negati temporaneamente
  void _showPermissionSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // New method to open the video editor and go to next step after editing
  Future<void> _openVideoEditor(File videoFile) async {
    // Navigate to the VideoEditorPage
    final editedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoEditorPage(videoFile: videoFile),
      ),
    );
    
    // If user edited and saved the video, update the file
    if (editedFile != null) {
      setState(() {
        _videoFile = editedFile;
      });
    }
    
    // Initialize the player with the new file
    _initializeVideoPlayer(_videoFile!);
    
    // Go to step 2 after video editing
    _goToNextStep();
  }

  // Mostra opzioni di modifica video
  void _showVideoEditOptions() {
    if (_isImageFile || _videoFile == null) return;
    
    final theme = Theme.of(context);
    
    // Mostra un tooltip o snackbar per informare l'utente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.edit, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Do you want to edit this video before uploading?'),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Edit',
            textColor: Colors.white,
            onPressed: () {
              _navigateToVideoEditor();
            },
          ),
          backgroundColor: theme.colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: Duration(seconds: 5),
        ),
      );
    });
  }
  
  // Naviga alla pagina di modifica video
  Future<void> _navigateToVideoEditor() async {
    if (_videoFile == null || _isImageFile) return;
    
    // Ferma il video player prima di navigare
    _stopVideoBeforeNavigation();
    
    // Importa la pagina solo quando necessario per evitare dipendenze circolari
    // Devi aggiungere questo import in testa al file:
    // import './video_editor_page.dart';
    
    final editedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoEditorPage(videoFile: _videoFile!),
      ),
    );
    
    // Se l'utente ha modificato e salvato il video, aggiorna il file
    if (editedFile != null) {
      setState(() {
        _videoFile = editedFile;
      });
      
      // Reinizializza il player con il nuovo file
      _initializeVideoPlayer(editedFile);
      

    }
  }

  // Helper per costruire le opzioni media nella tendina
  Widget _buildMediaOptionTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    BorderRadius? borderRadius,
    VoidCallback onTap
  ) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
  Future<void> _validateAndProceed(bool isScheduling) async {
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a media before proceeding')),
      );
      return;
    }

    if (_selectedAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one account before proceeding')),
      );
      return;
    }
    
    // Validate YouTube titles if YouTube accounts are selected
    if (!_validateYouTubeTitles()) {
      _showYouTubeTitleError();
      return;
    }

    // Validate TikTok video length if TikTok accounts are selected
    if (!await _validateTikTokVideoLength()) {
      _showTikTokVideoLengthError();
      return;
    }
    
    // Validate TikTok privacy settings if TikTok accounts are selected
    if (!_validateTikTokPrivacySettings()) {
      _showTikTokPrivacyError();
      return;
    }
    
    // Check for YouTube unverified accounts with videos longer than 15 minutes
    if (!_isImageFile && _videoDuration.inMinutes > 15) {
      final youtubeAccounts = _selectedAccounts['YouTube'] ?? [];
      final unverifiedAccounts = <String>[];
      
      for (final accountId in youtubeAccounts) {
        if (!_isYouTubeAccountVerified(accountId)) {
          // Get account display name
          final account = _socialAccounts['YouTube']?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
          final displayName = account?['display_name'] ?? account?['username'] ?? accountId;
          unverifiedAccounts.add(displayName);
        }
      }
      
      if (unverifiedAccounts.isNotEmpty) {
        final accountNames = unverifiedAccounts.join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Videos longer than 15 minutes require verified YouTube accounts. Unverified accounts: $accountNames',
              style: TextStyle(fontSize: 14, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            backgroundColor: Colors.white,
            duration: Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: EdgeInsets.all(16),
            elevation: 2,
          ),
        );
        return;
      }
    }
    
    // Title is now optional for all platforms including YouTube

    if (isScheduling) {
      // Se _scheduledDateTime è già impostato (provenendo da scheduled_posts_page),
      // salta la selezione della data e dell'ora e passa direttamente alla pagina di conferma
      if (_scheduledDateTime != null) {
        // Passa direttamente alla pagina di conferma della programmazione
        _stopVideoBeforeNavigation();
        
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SchedulePostPage(
              videoFile: _videoFile!,
              title: _titleController.text,
              description: _descriptionController.text,
              selectedAccounts: _selectedAccounts,
              socialAccounts: _socialAccounts,
              scheduledDateTime: _scheduledDateTime!,
              onConfirm: () {
                setState(() {
                  _isScheduled = true;
                });
              },
              platformDescriptions: _buildPlatformDescriptions(),
              isImageFile: _isImageFile, // Aggiungo il parametro mancante
              isPremium: _isPremium, // Passa lo stato premium
              draftId: widget.draftId, // Passa draftId
              youtubeThumbnailFile: _youtubeThumbnailFile, // Passa la thumbnail YouTube
            ),
          ),
        );

        // When returning from schedule page, ensure video is still stopped
        if (_videoPlayerController != null) {
          if (_videoPlayerController!.value.isPlaying) {
            _videoPlayerController!.pause();
          }
        }

        if (result == true) {
          setState(() {
            _isScheduled = true;
          });
          _refreshPage();
        }
        return;
      }
      
      final theme = Theme.of(context);
      final now = DateTime.now();
      
      // Show date picker with custom theme
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _scheduledDateTime ?? now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: theme.colorScheme.primary,
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

      if (picked != null) {
        // Show time picker with custom theme
        final TimeOfDay? time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_scheduledDateTime ?? now),
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

        if (time != null) {
          final scheduledDateTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
          
          // Navigate to the new SchedulePostPage
          // Stop video before navigation to prevent memory issues
          _stopVideoBeforeNavigation();
          
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SchedulePostPage(
                videoFile: _videoFile!,
                title: _titleController.text,
                description: _descriptionController.text,
                selectedAccounts: _selectedAccounts,
                socialAccounts: _socialAccounts,
                scheduledDateTime: scheduledDateTime,
                onConfirm: () {
                  setState(() {
                    _scheduledDateTime = scheduledDateTime;
                    _isScheduled = true;
                  });
                },
                platformDescriptions: _buildPlatformDescriptions(),
                isImageFile: _isImageFile, // Aggiungo il parametro mancante
                isPremium: _isPremium, // Passa lo stato premium
                draftId: widget.draftId, // Passa draftId
                youtubeThumbnailFile: _youtubeThumbnailFile, // Passa la thumbnail YouTube
              ),
            ),
          );

          // When returning from schedule page, ensure video is still stopped
          if (_videoPlayerController != null) {
            if (_videoPlayerController!.value.isPlaying) {
              _videoPlayerController!.pause();
            }
          }

          if (result == true) {
            setState(() {
              _scheduledDateTime = scheduledDateTime;
              _isScheduled = true;
            });
            _refreshPage();
          }
        }
      }
    } else {
      // Show confirmation page for immediate upload
      // Stop video before navigation to prevent memory issues
      _stopVideoBeforeNavigation();
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UploadConfirmationPage(
            videoFile: _videoFile!,
            title: _titleController.text,
            description: _getDescriptionForConfirmation(),
            selectedAccounts: _selectedAccounts,
            socialAccounts: _socialAccounts,
            onConfirm: () {},
            isDraft: false,
            isImageFile: _isImageFile,
            platformDescriptions: _buildPlatformDescriptions(),
            draftId: widget.draftId, // Pass the draft ID
            youtubeThumbnailFile: _youtubeThumbnailFile, // Passa la thumbnail YouTube
            tiktokOptions: _tiktokOptions, // Passa le opzioni TikTok
          ),
        ),
      );

      // When returning from confirmation page, ensure video is still stopped
      if (_videoPlayerController != null) {
        if (_videoPlayerController!.value.isPlaying) {
          _videoPlayerController!.pause();
        }
      }

      if (result == true) {
        _uploadVideo();
      }
    }
  }

  Future<void> _uploadVideo() async {
    try {
      if (_videoFile == null) {
        throw Exception('No video file selected');
      }
      if (_selectedAccounts.isEmpty) {
        throw Exception('No social media accounts selected');
      }

      // Check if user has enough credits
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final creditsSnapshot = await FirebaseDatabase.instance.ref()
            .child('users')
            .child('users') // Match the path style with the rest of the database
            .child(currentUser.uid)
            .child('credits')
            .get();

        int userCredits = creditsSnapshot.exists ? (creditsSnapshot.value as int?) ?? 0 : 0;
        
        if (userCredits < 250) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Not enough credits. You need 250 credits to upload a video.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Initialize the upload status
      setState(() {
        _isUploading = true;
        _uploadStatuses.clear();
      });

      // Prima di tutto, carica il file su Cloudflare R2
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploading media to cloud storage...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Aggiungi un UploadStatus per Cloudflare
      _uploadStatuses['Cloudflare_storage'] = UploadStatus(
        platform: 'Cloudflare',
        accountId: 'R2Storage',
        state: UploadState.uploading,
        progress: 0.0,
      );

      // Carica il file su Cloudflare R2
      String? cloudflareUrl;
      try {
        cloudflareUrl = await _uploadToCloudflare(_videoFile!, isImage: _isImageFile);
        
        if (cloudflareUrl == null) {
          throw Exception('Failed to upload media to Cloudflare');
        }
        
        // Aggiorna lo stato di upload
        _uploadStatuses['Cloudflare_storage'] = UploadStatus(
          platform: 'Cloudflare',
          accountId: 'R2Storage',
          state: UploadState.completed,
          progress: 1.0,
        );
        
        print('Successfully uploaded media to Cloudflare: $cloudflareUrl');
        
        // Mostra una notifica di successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Media uploaded to cloud storage successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // Aggiorna lo stato di upload
        _uploadStatuses['Cloudflare_storage'] = UploadStatus(
          platform: 'Cloudflare',
          accountId: 'R2Storage',
          state: UploadState.error,
          error: e.toString(),
        );
        
        throw Exception('Failed to upload media to Cloudflare: $e');
      }

      // Prepare upload status trackers
      for (var platform in _selectedAccounts.keys) {
        for (var accountId in _selectedAccounts[platform]!) {
          final key = '${platform}_$accountId';
          _uploadStatuses[key] = UploadStatus(
            platform: platform,
            accountId: accountId,
          );
        }
      }

      List<Future> uploadTasks = [];
      List<String> uploadedPlatforms = [];

      // Prepara gli upload per ogni piattaforma selezionata
      for (var platform in _selectedAccounts.keys) {
        for (var accountId in _selectedAccounts[platform]!) {
          switch (platform) {
            case 'Twitter':
              uploadTasks.add(_uploadToTwitter(accountId, cloudflareUrl).then((_) {
                uploadedPlatforms.add(platform);
              }).catchError((e) {
                print('Error uploading to Twitter: $e');
                throw e;
              }));
              break;
            case 'YouTube':
              uploadTasks.add(_uploadToYouTube(accountId, cloudflareUrl).then((_) {
                uploadedPlatforms.add(platform);
              }));
              break;
            case 'TikTok':
              uploadTasks.add(_uploadToTikTok(accountId, cloudflareUrl).then((_) {
                uploadedPlatforms.add(platform);
              }));
              break;
            case 'Instagram':
              uploadTasks.add(_uploadToInstagram(accountId, cloudflareUrl).then((_) {
                uploadedPlatforms.add(platform);
              }));
              break;
            case 'Facebook':
              uploadTasks.add(_uploadToFacebook(accountId, cloudflareUrl).then((_) {
                uploadedPlatforms.add(platform);
              }));
              break;
            case 'Threads':
              uploadTasks.add(_uploadToThreads(accountId, cloudflareUrl).then((_) {
                uploadedPlatforms.add(platform);
              }));
              break;
          }
        }
      }

      // Esegui tutti gli upload in parallelo
      await Future.wait(uploadTasks);

      // Salva la cronologia del post
      if (currentUser != null && uploadedPlatforms.isNotEmpty) {
        // Deduct 250 credits after successful upload
        final creditsRef = _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('credits');
        
        // Get current credits
        final creditsSnapshot = await creditsRef.get();
        int currentCredits = creditsSnapshot.exists ? (creditsSnapshot.value as int?) ?? 0 : 0;
        
        // Update credits (deduct 250)
        await creditsRef.set(currentCredits - 250);
        
        // Prepare post data
        final postData = {
          'title': _titleController.text,
          'video_path': cloudflareUrl, // URL Cloudflare del video
          'cloudflare_url': cloudflareUrl, // Aggiungi URL Cloudflare
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'platforms': uploadedPlatforms,
          'is_scheduled': false,
          'scheduled_time': null,
          'status': 'published',
        };
        
        // Add description only if it's not empty and user hasn't disabled global content
        bool shouldUseGlobalDescription = true;
        
        // Check if any account has disabled global content
        for (var platform in _selectedAccounts.keys) {
          for (var accountId in _selectedAccounts[platform]!) {
            if (_accountSpecificContent != null) {
              final configKey = '${platform}_$accountId';
              if (_accountSpecificContent!.containsKey(configKey) && 
                  !(_accountSpecificContent![configKey]?['useGlobalContent'] ?? true)) {
                shouldUseGlobalDescription = false;
                break;
              }
            }
          }
          if (!shouldUseGlobalDescription) break;
        }
        
        // Only add description if user hasn't disabled global content and description is not empty
        if (shouldUseGlobalDescription && _descriptionController.text.isNotEmpty) {
          postData['description'] = _descriptionController.text;
        }
        
        await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('posts')
            .push()
            .set(postData);
      }

      if (mounted) {
        // Stop video before navigation to confirmation page
        _stopVideoBeforeNavigation();
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UploadConfirmationPage(
              videoFile: _videoFile!,
              title: _titleController.text,
              description: _getDescriptionForConfirmation(),
              selectedAccounts: _selectedAccounts,
              socialAccounts: _socialAccounts,
              onConfirm: () {},
              isDraft: false,
              isImageFile: _isImageFile,
              cloudflareUrl: cloudflareUrl, // Passa l'URL di Cloudflare
              platformDescriptions: _buildPlatformDescriptions(),
              draftId: widget.draftId, // Pass the draft ID
              youtubeThumbnailFile: _youtubeThumbnailFile, // Passa la thumbnail YouTube
              tiktokOptions: _tiktokOptions, // Passa le opzioni TikTok
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uploadedPlatforms.isEmpty
                ? 'No videos were uploaded, please check errors and try again'
                : 'Video uploaded successfully to all platforms!'
            ),
            backgroundColor: uploadedPlatforms.isEmpty ? Colors.red : Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      print('Error in _uploadVideo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during upload: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // Metodo per aggiornare lo stato di upload
  void _updateUploadStatus(String platform, String accountId, {
    UploadState? state,
    String? error,
    double? progress,
  }) {
    final key = '${platform}_$accountId';
    setState(() {
      final status = _uploadStatuses[key];
      if (status != null) {
        if (state != null) status.state = state;
        if (error != null) status.error = error;
        if (progress != null) status.progress = progress;
      }
    });
  }

  // Helper method to sanitize database paths
  String _sanitizePath(String path) {
    return path.replaceAll(RegExp(r'[@.#$\[\]]'), '_');
  }
  Future<void> _loadSocialAccounts() async {
    if (!mounted) return;
    
    // Controllo se gli account sono già stati caricati recentemente (entro gli ultimi 30 secondi)
    final now = DateTime.now();
    if (_accountsLoaded && _lastAccountsLoadTime != null) {
      final difference = now.difference(_lastAccountsLoadTime!);
      // Se gli account sono stati caricati negli ultimi 30 secondi e non siamo nella schermata di selezione account
      if (difference.inSeconds < 30 && _currentStep != UploadStep.selectAccounts) {
        // print('Account social già caricati recentemente (${difference.inSeconds}s fa), evito ricaricamento non necessario');
        return;
      }
    }
    
    // Start loading indicator if we're on the account selection step
    bool showLoadingIndicator = _currentStep == UploadStep.selectAccounts;
    if (showLoadingIndicator && mounted) {
      setState(() {
        _isUploading = true; // Reuse the loading indicator
      });
    }
    
    // print('Caricamento account social in corso...');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Check mounted again after any async operation
      if (!mounted) return;

      // Load Twitter accounts
      final twitterSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .get();
      
      if (!mounted) return;
      
      if (twitterSnapshot.exists) {
        final twitterData = twitterSnapshot.value as Map<dynamic, dynamic>;
        final twitterAccounts = twitterData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          return {
            'id': entry.key,
            'username': accountData['username'] ?? '',
            'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
            'profile_image_url': accountData['profile_image_url'] ?? '',
            'followers_count': accountData['followers_count']?.toString() ?? '0',
            'access_token': accountData['access_token'] ?? '',
            'access_token_secret': accountData['access_token_secret'] ?? '',
            'bearer_token': accountData['bearer_token'] ?? '',
            'verified': accountData['verified'] ?? false, // <-- AGGIUNTO
          };
        }).where((account) => 
          account['username'].toString().isNotEmpty && 
          account['access_token'].toString().isNotEmpty
        ).toList();

        if (mounted) {
          setState(() {
            _socialAccounts['Twitter'] = twitterAccounts;
          });
        }
      }

      if (!mounted) return;

      // Load YouTube accounts (robust to unexpected data shapes)
      final youtubeSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .get();
      
      if (!mounted) return;
      
      if (youtubeSnapshot.exists) {
        final dynamic rawYouTube = youtubeSnapshot.value;
        final List<Map<String, dynamic>> youtubeAccounts = [];

        // Case 1: Map of accounts keyed by accountId
        if (rawYouTube is Map) {
          for (final entry in rawYouTube.entries) {
            final dynamic value = entry.value;
            if (value is Map) {
              final Map accountData = value;
              if (accountData['status'] == 'active') {
                youtubeAccounts.add({
                  'id': entry.key.toString(),
                  'username': (accountData['channel_name'] ?? '').toString(),
                  'display_name': (accountData['channel_name'] ?? '').toString(),
                  'profile_image_url': (accountData['thumbnail_url'] ?? '').toString(),
                  'followers_count': (accountData['subscriber_count']?.toString() ?? '0'),
                  'channel_id': (accountData['channel_id'] ?? '').toString(),
                  'video_count': (accountData['video_count']?.toString() ?? '0'),
                  'access_token': (accountData['access_token'] ?? '').toString(),
                  'is_verified': accountData['is_verified'] == true,
                });
              }
            } else {
              // Skip non-map entries (e.g., stray strings)
              // print('Skipping unexpected YouTube account entry for key ${entry.key}: ${value.runtimeType}');
            }
          }
        }
        // Case 2: List of account objects
        else if (rawYouTube is List) {
          for (int i = 0; i < rawYouTube.length; i++) {
            final dynamic item = rawYouTube[i];
            if (item is Map) {
              final Map accountData = item;
              if (accountData['status'] == 'active') {
                youtubeAccounts.add({
                  'id': (accountData['id'] ?? i.toString()).toString(),
                  'username': (accountData['channel_name'] ?? '').toString(),
                  'display_name': (accountData['channel_name'] ?? '').toString(),
                  'profile_image_url': (accountData['thumbnail_url'] ?? '').toString(),
                  'followers_count': (accountData['subscriber_count']?.toString() ?? '0'),
                  'channel_id': (accountData['channel_id'] ?? '').toString(),
                  'video_count': (accountData['video_count']?.toString() ?? '0'),
                  'access_token': (accountData['access_token'] ?? '').toString(),
                  'is_verified': accountData['is_verified'] == true,
                });
              }
            }
          }
        } else {
          // print('YouTube snapshot has unexpected type: ${rawYouTube.runtimeType}');
        }

        if (mounted) {
          setState(() {
            _socialAccounts['YouTube'] = youtubeAccounts;
          });
        }
      }
      
      if (!mounted) return;
      
      // Load TikTok accounts
      final tiktokSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('tiktok')
          .get();
      
      if (!mounted) return;
      
      if (tiktokSnapshot.exists) {
        final tiktokData = tiktokSnapshot.value as Map<dynamic, dynamic>;
        final tiktokAccounts = tiktokData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['status'] != 'active') return null;
          
          // Debug print rimossi per evitare spam nei log
          // print('TikTok account data: ${accountData.keys}');
          // if (accountData.containsKey('display_name')) {
          //   print('Found display_name: ${accountData['display_name']}');
          // }
          
          return {
            'id': entry.key,
            'username': accountData['username'] ?? '',
            'display_name': accountData['display_name'] ?? accountData['displayName'] ?? accountData['name'] ?? accountData['username'] ?? 'TikTok Account',
            'profile_image_url': accountData['profile_image_url'] ?? accountData['avatar_url'] ?? accountData['avatarUrl'] ?? '',
            'followers_count': accountData['followers_count']?.toString() ?? accountData['follower_count']?.toString() ?? accountData['followerCount']?.toString() ?? '0',
            'access_token': accountData['access_token'] ?? '',
          };
        }).where((account) => account != null).cast<Map<String, dynamic>>().toList();

        if (mounted) {
          setState(() {
            _socialAccounts['TikTok'] = tiktokAccounts;
          });
        }
      }
      
      // Also check TikTok accounts in social_accounts path
      if (!mounted) return;
      
      final tiktokSocialSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('tiktok')
          .get();
          
      if (!mounted) return;
      
      if (tiktokSocialSnapshot.exists) {
        final tiktokSocialData = tiktokSocialSnapshot.value as Map<dynamic, dynamic>;
        final tiktokSocialAccounts = tiktokSocialData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['status'] != 'active') return null;
          
          // Debug print rimossi per evitare spam nei log
          // print('TikTok social account data: ${accountData.keys}');
          // if (accountData.containsKey('display_name')) {
          //   print('Found social display_name: ${accountData['display_name']}');
          // }
          
          return {
            'id': entry.key,
            'username': accountData['username'] ?? '',
            'display_name': accountData['display_name'] ?? accountData['username'] ?? 'TikTok Account',
            'profile_image_url': accountData['profile_image_url'] ?? accountData['avatar_url'] ?? '',
            'followers_count': accountData['followers_count']?.toString() ?? accountData['follower_count']?.toString() ?? '0',
            'access_token': accountData['access_token'] ?? '',
          };
        }).where((account) => account != null).cast<Map<String, dynamic>>().toList();
        
        if (mounted && tiktokSocialAccounts.isNotEmpty) {
          print('Found ${tiktokSocialAccounts.length} TikTok accounts in social_accounts path');
          setState(() {
            // Merge with existing accounts, prioritizing the ones we just found
            final existingAccounts = _socialAccounts['TikTok'] ?? [];
            final existingIds = existingAccounts.map((acc) => acc['id']).toSet();
            final newAccounts = tiktokSocialAccounts.where((acc) => !existingIds.contains(acc['id'])).toList();
            
            if (newAccounts.isNotEmpty) {
              _socialAccounts['TikTok'] = [...existingAccounts, ...newAccounts];
              print('Added ${newAccounts.length} new TikTok accounts from social_accounts path');
            }
          });
        }
      }
      
      if (!mounted) return;
      
      // Load Facebook accounts
      final facebookSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('facebook')
          .get();
      
      if (!mounted) return;
      
      if (facebookSnapshot.exists) {
        final facebookData = facebookSnapshot.value as Map<dynamic, dynamic>;
        final facebookAccounts = facebookData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['status'] != 'active') return null;
          return {
            'id': entry.key,
            'username': accountData['name'] ?? '',
            'display_name': accountData['display_name'] ?? accountData['name'] ?? '',
            'profile_image_url': accountData['profile_image_url'] ?? '',
            'followers_count': accountData['followers_count']?.toString() ?? '0',
            'page_id': accountData['page_id'] ?? '',
            'page_type': accountData['page_type'] ?? '',
            'access_token': accountData['access_token'] ?? '',
          };
        }).where((account) => account != null).cast<Map<String, dynamic>>().toList();

        if (mounted) {
          setState(() {
            _socialAccounts['Facebook'] = facebookAccounts;
          });
        }
      }

      if (!mounted) return;

      // Load Instagram accounts
      final instagramSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('instagram')
          .get();
      
      if (!mounted) return;
      
      if (instagramSnapshot.exists) {
        final instagramData = instagramSnapshot.value as Map<dynamic, dynamic>;
        final instagramAccounts = instagramData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['status'] != 'active') return null;
          // Controlla se esiste il campo access_token e non è vuoto
          if (!accountData.containsKey('access_token') || accountData['access_token'] == null || accountData['access_token'].toString().isEmpty) {
            return null; // Non mostrare account senza access_token
          }
          return {
            'id': entry.key,
            'username': accountData['username'] ?? '',
            'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
            'profile_image_url': accountData['profile_image_url'] ?? '',
            'followers_count': accountData['followers_count']?.toString() ?? '0',
            'user_id': accountData['user_id'] ?? '',
            'access_token': accountData['access_token'] ?? '',
          };
        }).where((account) => account != null).cast<Map<String, dynamic>>().toList();

        if (mounted) {
          setState(() {
            _socialAccounts['Instagram'] = instagramAccounts;
          });
        }
      }
      
      if (!mounted) return;
      
      // Load Threads accounts
      final threadsSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('threads')
          .get();
      
      if (!mounted) return;
      
      if (threadsSnapshot.exists) {
        // print('Found Threads accounts for user ${currentUser.uid}');
        final threadsData = threadsSnapshot.value as Map<dynamic, dynamic>;
        final threadsAccounts = threadsData.entries.map((entry) {
          final accountData = entry.value as Map<dynamic, dynamic>;
          if (accountData['status'] != 'active') return null;
          return {
            'id': entry.key,
            'username': accountData['username'] ?? '',
            'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
            'profile_image_url': accountData['profile_image_url'] ?? '',
            'followers_count': '0', // Threads API non fornisce il numero di followers
            'user_id': accountData['user_id'] ?? entry.key,
            'access_token': accountData['access_token'] ?? '',
          };
        }).where((account) => account != null).cast<Map<String, dynamic>>().toList();

        // print('Loaded ${threadsAccounts.length} Threads accounts');
        if (mounted) {
          setState(() {
            _socialAccounts['Threads'] = threadsAccounts;
          });
        }
      } else {
        // print('No Threads accounts found for user ${currentUser.uid}');
        if (mounted) {
          setState(() {
            _socialAccounts['Threads'] = [];
          });
        }
      }
      
      // Dopo aver caricato tutti gli account, aggiorna gli account selezionati
      // se proveniamo da una bozza
      if (_isEditingDraft && widget.draftData != null && mounted) {
        print('Editing existing draft, updating selected accounts...');
        // Usa WidgetsBinding per assicurarsi che lo stato sia stabile
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateSelectedAccountsWithRealIds();
          
          // Se siamo in modalità modifica e gli account sono stati caricati,
          // vai direttamente al terzo step (selezione account)
          if (_currentStep == UploadStep.addDetails) {
            print('Moving to account selection step...');
            // Aggiungi un breve ritardo per assicurarsi che la UI sia aggiornata
            Future.delayed(Duration(milliseconds: 300), () {
              if (mounted) {
                _goToNextStep(); // Va al terzo step (account)
                // Espandi le piattaforme selezionate dopo un breve ritardo
                Future.delayed(Duration(milliseconds: 500), () {
                  if (mounted) {
                    _expandSelectedPlatforms();
                  }
                });
              }
            });
          }
        });
      }
    } catch (e) {
      print('Error loading social accounts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading social accounts: $e')),
        );
      }
    } finally {
      // Imposta la flag per indicare che gli account sono stati caricati
      _accountsLoaded = true;
      _lastAccountsLoadTime = DateTime.now();
      // print('Social accounts loaded successfully.');
      
      // Hide loading indicator if it was shown
      if (mounted && _isUploading) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }
  
  // Metodo per espandere automaticamente le piattaforme selezionate
  void _expandSelectedPlatforms() {
    if (_selectedAccounts.isEmpty) return;
    
    print('Expanding selected platforms: $_selectedAccounts');
    
    setState(() {
      // Chiudi tutte le piattaforme inizialmente
      for (var platform in _expandedState.keys) {
        _expandedState[platform] = false;
      }
      
      // Apri solo le piattaforme selezionate
      for (var platform in _selectedAccounts.keys) {
        // Normalizza il nome della piattaforma (per gestire sia "Youtube" che "YouTube")
        String normalizedPlatform = platform;
        if (platform.toLowerCase() == 'youtube') {
          normalizedPlatform = 'YouTube';
        }
        
        if (_expandedState.containsKey(normalizedPlatform)) {
          _expandedState[normalizedPlatform] = true;
          print('Setting $normalizedPlatform to expanded');
        }
      }
    });
    
    // Scorri fino alla prima piattaforma espansa
    if (_selectedAccounts.isNotEmpty) {
      // Ottieni la prima piattaforma selezionata, assicurandosi che sia normalizzata
      String firstPlatform = _selectedAccounts.keys.first;
      if (firstPlatform.toLowerCase() == 'youtube') {
        firstPlatform = 'YouTube';
      }
      
      // Utilizziamo un leggero ritardo per dare tempo alla UI di aggiornarsi
      Future.delayed(Duration(milliseconds: 300), () {
        if (!mounted) return;
        
        if (_platformKeys.containsKey(firstPlatform)) {
          final platformKey = _platformKeys[firstPlatform];
          if (platformKey?.currentContext != null) {
            Scrollable.ensureVisible(
              platformKey!.currentContext!,
              duration: Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        }
      });
    }
  }

  // Metodo per aggiornare gli account selezionati con gli ID reali
  void _updateSelectedAccountsWithRealIds() {
    if (!_isEditingDraft || widget.draftData == null) return;
    
    try {
      // Se non abbiamo ancora account selezionati, non c'è nulla da aggiornare
      if (_selectedAccounts.isEmpty) return;
      
      print('Updating selected accounts with real IDs. Current selection: $_selectedAccounts');
      print('Available social accounts: $_socialAccounts');
      
      Map<String, List<String>> updatedSelectedAccounts = {};
      
      // Per ogni piattaforma negli account selezionati
      for (var platform in _selectedAccounts.keys) {
        List<String> accountIds = [];
        
        // Verifica se abbiamo account per questa piattaforma
        if (_socialAccounts.containsKey(platform)) {
          final accounts = _socialAccounts[platform];
          
          if (accounts != null && accounts.isNotEmpty) {
            // Per ogni ID o username memorizzato temporaneamente
            for (var tempId in _selectedAccounts[platform]!) {
              // Prima verifica se l'ID corrisponde direttamente
              var matchingAccount = accounts.firstWhere(
                (acc) => acc['id'] == tempId,
                orElse: () => <String, dynamic>{},
              );
              
              // Se non trovato, prova a cercare per username
              if (matchingAccount.isEmpty) {
                matchingAccount = accounts.firstWhere(
                  (acc) => acc['username'] == tempId || 
                          acc['username']?.toLowerCase() == tempId.toLowerCase() ||
                          '@${acc['username']}' == tempId ||
                          // Per YouTube, controlla anche channel_id
                          (platform == 'YouTube' && acc['channel_id'] == tempId),
                  orElse: () => <String, dynamic>{},
                );
              }
              
              // Se trovato, aggiungi l'ID reale
              if (matchingAccount.isNotEmpty && matchingAccount['id'] != null) {
                accountIds.add(matchingAccount['id'].toString());
                print('Found matching account for $tempId: ${matchingAccount['id']} (${matchingAccount['username']})');
              } else {
                print('No matching account found for: $tempId');
              }
            }
          }
        } else {
          print('Platform $platform not found in social accounts');
        }
        
        // Aggiorna la selezione con gli ID reali
        if (accountIds.isNotEmpty) {
          updatedSelectedAccounts[platform] = accountIds;
        }
      }
      
      // Controlla anche se ci sono account YouTube nella bozza originale
      final draftAccounts = widget.draftData!['accounts'];
      if (draftAccounts != null && draftAccounts is Map && draftAccounts.containsKey('youtube')) {
        final youtubeAccounts = draftAccounts['youtube'];
        if (youtubeAccounts is List && youtubeAccounts.isNotEmpty && _socialAccounts.containsKey('YouTube')) {
          // Assicurati che YouTube sia nella lista delle piattaforme aggiornate
          if (!updatedSelectedAccounts.containsKey('YouTube')) {
            updatedSelectedAccounts['YouTube'] = [];
          }
          
          // Trova gli account YouTube corrispondenti
          for (var ytAccount in youtubeAccounts) {
            if (ytAccount is Map) {
              // Cerca di identificare l'account YouTube in base a channel_id o username
              String? channelId = ytAccount['channel_id']?.toString();
              String? username = ytAccount['username']?.toString();
              
              // Cerca un account corrispondente nella lista degli account caricati
              var matchingAccount = _socialAccounts['YouTube']!.firstWhere(
                (acc) => (channelId != null && acc['channel_id'] == channelId) || 
                         (username != null && acc['username'] == username),
                orElse: () => <String, dynamic>{},
              );
              
              if (matchingAccount.isNotEmpty && matchingAccount['id'] != null) {
                final accountId = matchingAccount['id'].toString();
                if (!updatedSelectedAccounts['YouTube']!.contains(accountId)) {
                  updatedSelectedAccounts['YouTube']!.add(accountId);
                  print('Added YouTube account: $accountId (${matchingAccount['username']})');
                }
              }
            }
          }
          
          // Se dopo tutto non abbiamo trovato account YouTube validi, rimuovi la piattaforma
          if (updatedSelectedAccounts['YouTube']!.isEmpty) {
            updatedSelectedAccounts.remove('YouTube');
          }
        }
      }
      
      // Controlla anche se ci sono account TikTok nella bozza originale
      if (draftAccounts != null && draftAccounts is Map && draftAccounts.containsKey('tiktok')) {
        final tiktokAccounts = draftAccounts['tiktok'];
        if (tiktokAccounts is List && tiktokAccounts.isNotEmpty && _socialAccounts.containsKey('TikTok')) {
          // Assicurati che TikTok sia nella lista delle piattaforme aggiornate
          if (!updatedSelectedAccounts.containsKey('TikTok')) {
            updatedSelectedAccounts['TikTok'] = [];
          }
          
          // Trova gli account TikTok corrispondenti
          for (var tkAccount in tiktokAccounts) {
            if (tkAccount is Map) {
              // Cerca di identificare l'account TikTok in base a username
              String? username = tkAccount['username']?.toString();
              
              // Cerca un account corrispondente nella lista degli account caricati
              var matchingAccount = _socialAccounts['TikTok']!.firstWhere(
                (acc) => username != null && acc['username'] == username,
                orElse: () => <String, dynamic>{},
              );
              
              if (matchingAccount.isNotEmpty && matchingAccount['id'] != null) {
                final accountId = matchingAccount['id'].toString();
                if (!updatedSelectedAccounts['TikTok']!.contains(accountId)) {
                  updatedSelectedAccounts['TikTok']!.add(accountId);
                  print('Added TikTok account: $accountId (${matchingAccount['username']})');
                }
              }
            }
          }
          
          // Se dopo tutto non abbiamo trovato account TikTok validi, rimuovi la piattaforma
          if (updatedSelectedAccounts['TikTok']!.isEmpty) {
            updatedSelectedAccounts.remove('TikTok');
          }
        }
      }
      
      // Aggiorna lo stato con gli ID reali
      if (updatedSelectedAccounts.isNotEmpty) {
        setState(() {
          _selectedAccounts.clear();
          _selectedAccounts.addAll(updatedSelectedAccounts);
        });
        
        print('Updated selected accounts with real IDs: $_selectedAccounts');
        
        // Espandi automaticamente le piattaforme selezionate
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _expandSelectedPlatforms();
        });
      } else {
        print('No accounts were matched - keeping original selection');
      }
    } catch (e) {
      print('Error updating selected accounts: $e');
    }
  }

  Future<void> _uploadToTwitter(String accountId, String? cloudflareUrl) async {
    try {
      _updateUploadStatus('Twitter', accountId, state: UploadState.uploading);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      print('Uploading to Twitter with account ID: $accountId');

      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      
      print('Account data retrieved: ${accountData['access_token']} - ${accountData['access_token_secret']}');

      // Initialize Twitter API with empty bearer token to force OAuth 1.0a for all operations
      final twitter = v2.TwitterApi(
        bearerToken: '',  // Empty bearer token to force OAuth 1.0a
        oauthTokens: v2.OAuthTokens(
          consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
          consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
          accessToken: accountData['access_token'] ?? '',
          accessTokenSecret: accountData['access_token_secret'] ?? '',
        ),
        retryConfig: v2.RetryConfig(
          maxAttempts: 5,
          onExecute: (event) => print(
            'Retry after ${event.intervalInSeconds} seconds... '
            '[${event.retryCount} times]'
          ),
        ),
        timeout: const Duration(seconds: 30),
      );

      print('Starting media upload...');
      
      // Upload the video using the media upload endpoint (v1.1)
      final uploadResponse = await twitter.media.uploadMedia(
        file: _videoFile!,
        onProgress: (event) {
          switch (event.state) {
            case v2.UploadState.preparing:
              print('Upload is preparing...');
              _updateUploadStatus('Twitter', accountId, progress: 0.1);
              break;
            case v2.UploadState.inProgress:
              print('${event.progress}% completed...');
              _updateUploadStatus('Twitter', accountId, progress: event.progress / 100);
              break;
            case v2.UploadState.completed:
              print('Upload has completed!');
              _updateUploadStatus('Twitter', accountId, progress: 1.0);
              break;
          }
        },
        onFailed: (error) {
          print('Upload failed: ${error.message}');
          _updateUploadStatus(
            'Twitter',
            accountId,
            state: UploadState.error,
            error: error.message,
          );
          throw Exception(error.message);
        },
      );

      if (uploadResponse.data == null) {
        throw Exception('Failed to upload media to Twitter');
      }

      print('Video uploaded successfully, creating tweet...');

      // Create tweet with the uploaded video using OAuth 1.0a
      final tweet = await twitter.tweets.createTweet(
        text: _descriptionController.text,
        media: v2.TweetMediaParam(
          mediaIds: [uploadResponse.data!.id],
        ),
      );

      // Save tweet ID in the account data
      if (tweet.data != null) {
        final accountIndex = _socialAccounts['Twitter']?.indexWhere(
          (account) => account['id'] == accountId
        );
        
        if (accountIndex != null && accountIndex >= 0) {
          setState(() {
            _socialAccounts['Twitter']![accountIndex]['tweet_id'] = tweet.data.id;
          });
        }
      }

      _updateUploadStatus('Twitter', accountId, state: UploadState.completed);
      print('Tweet posted successfully with video!');
    } catch (e) {
      print('Error during Twitter upload: $e');
      _updateUploadStatus(
        'Twitter',
        accountId,
        state: UploadState.error,
        error: e.toString(),
      );
      rethrow;
    }
  }
  Future<void> _uploadToYouTube(String accountId, String? cloudflareUrl) async {
    try {
      _updateUploadStatus('YouTube', accountId, state: UploadState.uploading);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      print('Uploading to YouTube with account ID: $accountId');

      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('YouTube account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      
      // Initialize Google Sign-In
      final GoogleSignIn _googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube'
        ],
        clientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
        signInOption: SignInOption.standard,
      );

      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign in cancelled');
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null) {
        throw Exception('Failed to get access token');
      }

      // Prepare video metadata
      final videoTitle = _titleController.text.isNotEmpty ? _titleController.text : _videoFile!.path.split('/').last;
      final videoMetadata = {
        'snippet': {
          'title': videoTitle,
          'description': _descriptionController.text,
          'categoryId': '22', // People & Blogs category
        },
        'status': {
          'privacyStatus': 'public',
          'madeForKids': false,
        }
      };

      // First, upload the video
      final uploadResponse = await http.post(
        Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status'),
        headers: {
          'Authorization': 'Bearer ${googleAuth.accessToken}',
          'Content-Type': 'application/octet-stream',
          'X-Upload-Content-Type': 'video/*',
          'X-Upload-Content-Length': _videoFile!.lengthSync().toString(),
        },
        body: await _videoFile!.readAsBytes(),
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload video: ${uploadResponse.body}');
      }

      final uploadResponseData = json.decode(uploadResponse.body);
      final videoId = uploadResponseData['id'];

      // Then, update the video metadata
      final metadataResponse = await http.put(
        Uri.parse('https://www.googleapis.com/youtube/v3/videos?part=snippet,status'),
        headers: {
          'Authorization': 'Bearer ${googleAuth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'id': videoId,
          ...videoMetadata,
        }),
      );

      if (metadataResponse.statusCode != 200) {
        throw Exception('Failed to update video metadata: ${metadataResponse.body}');
      }

      // Upload custom thumbnail if available
      if (_youtubeThumbnailFile != null) {
        try {
          print('Uploading custom thumbnail for YouTube video: $videoId');
          
          // Upload the thumbnail
          final thumbnailResponse = await http.post(
            Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$videoId'),
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'image/jpeg',
            },
            body: await _youtubeThumbnailFile!.readAsBytes(),
          );

          if (thumbnailResponse.statusCode == 200) {
            print('Custom thumbnail uploaded successfully to YouTube!');
          } else {
            print('Warning: Failed to upload custom thumbnail: ${thumbnailResponse.body}');
            // Don't throw error here, as the video upload was successful
          }
        } catch (e) {
          print('Warning: Error uploading custom thumbnail: $e');
          // Don't throw error here, as the video upload was successful
        }
      }

      // Update account data with the new video
      await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(accountId)
          .update({
        'video_count': (accountData['video_count'] ?? 0) + 1,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });

      // Save video information to Firebase
      final videoRef = _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .push();

      // Prepare video data
      final videoData = {
        'account_id': accountId,
        'account_username': accountData['channel_name'],
        'media_id': videoId,
        'platforms': ['YouTube'],
        'status': 'published',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'title': videoTitle,
        'video_path': cloudflareUrl ?? '', // URL Cloudflare del video
        'user_id': currentUser.uid,
      };
      
      // Add description only if it's not empty and user hasn't disabled global content
      bool shouldUseGlobalDescription = true;
      
      // Check if this specific account has disabled global content
      if (_accountSpecificContent != null) {
        final configKey = 'YouTube_$accountId';
        if (_accountSpecificContent!.containsKey(configKey) && 
            !(_accountSpecificContent![configKey]?['useGlobalContent'] ?? true)) {
          shouldUseGlobalDescription = false;
        }
      }
      
      // Only add description if user hasn't disabled global content and description is not empty
      if (shouldUseGlobalDescription && _descriptionController.text.isNotEmpty) {
        videoData['description'] = _descriptionController.text;
      }
      
      await videoRef.set(videoData);

      _updateUploadStatus('YouTube', accountId, state: UploadState.completed);
      print('Video uploaded successfully to YouTube!');
    } catch (e) {
      print('Error during YouTube upload: $e');
      _updateUploadStatus(
        'YouTube',
        accountId,
        state: UploadState.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> _uploadToTikTok(String accountId, String? cloudflareUrl) async {
    try {
      _updateUploadStatus('TikTok', accountId, state: UploadState.uploading);
      // Implementa la logica di upload per TikTok
      await Future.delayed(const Duration(seconds: 2)); // Simulazione
      _updateUploadStatus('TikTok', accountId, state: UploadState.completed);
    } catch (e) {
      _updateUploadStatus('TikTok', accountId,
        state: UploadState.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> _uploadToInstagram(String accountId, String? cloudflareUrl) async {
    try {
      _updateUploadStatus('Instagram', accountId, state: UploadState.uploading);
      // Implementa la logica di upload per Instagram
      await Future.delayed(const Duration(seconds: 2)); // Simulazione
      _updateUploadStatus('Instagram', accountId, state: UploadState.completed);
    } catch (e) {
      _updateUploadStatus('Instagram', accountId,
        state: UploadState.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<String?> _uploadToFacebook(String accountId, String? cloudflareUrl) async {
    try {
      setState(() {
        _uploadStatuses['Facebook_$accountId'] = UploadStatus(
          platform: 'Facebook',
          accountId: accountId,
          state: UploadState.uploading
        );
      });

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('facebook')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('Facebook account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final pageId = accountData['page_id'];
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Facebook access token not found');
      }
      
      if (pageId == null || pageId.isEmpty) {
        throw Exception('Facebook page ID not found');
      }

      // Prepare the video file
      final videoFile = _videoFile!;
      final fileSize = await videoFile.length();
      
      // Log network conditions to help with debugging
      print('Starting Facebook upload for file size: $fileSize bytes');
      
      // STEP 1: Start upload session
      final startSessionResponse = await http.post(
        Uri.parse('https://graph.facebook.com/v18.0/$pageId/videos'),
        body: {
          'access_token': accessToken,
          'upload_phase': 'start',
          'file_size': fileSize.toString(),
        },
      ).timeout(const Duration(seconds: 60), onTimeout: () {
        throw TimeoutException('Start session request timed out');
      });
      
      if (startSessionResponse.statusCode != 200) {
        throw Exception('Failed to create Facebook upload session: ${startSessionResponse.body}');
      }
      
      final sessionData = json.decode(startSessionResponse.body);
      final uploadSessionId = sessionData['upload_session_id'];
      
      // STEP 2: Upload the video data in chunks
      int offset = 0;
      final chunkSize = 250 * 1024; // Further reduced to 250KB as per VEDI.md
      
      final videoBytes = await videoFile.readAsBytes();
      
      while (offset < fileSize) {
        final end = offset + chunkSize < fileSize ? offset + chunkSize : fileSize;
        final chunk = videoBytes.sublist(offset, end);
        
        bool chunkUploaded = false;
        int retryCount = 0;
        const maxRetries = 5; // Increased from 3 to 5
        
        // Retry loop for this chunk
        while (!chunkUploaded && retryCount < maxRetries) {
          try {
            // Create URL with query parameters
            final uri = Uri.parse('https://graph.facebook.com/v18.0/$pageId/videos')
                .replace(queryParameters: {
              'access_token': accessToken,
              'upload_phase': 'transfer',
              'upload_session_id': uploadSessionId,
              'start_offset': offset.toString(),
            });
            
            // Send the chunk as raw binary data
            final transferRequest = http.Request('POST', uri);
            transferRequest.bodyBytes = chunk;
            
            final client = http.Client();
            // Implement longer timeout for request (60 seconds)
            final transferResponse = await client.send(transferRequest)
                .timeout(const Duration(seconds: 60), onTimeout: () {
              throw TimeoutException('Upload chunk request timed out');
            });
            
            final transferResponseBody = await http.Response.fromStream(transferResponse);
            
            if (transferResponseBody.statusCode != 200) {
              throw Exception('Failed to upload video chunk to Facebook: ${transferResponseBody.body}');
            }
            
            // Chunk was successful
            chunkUploaded = true;
            client.close();
            
            // Update progress indicator (0.0 to 1.0)
            final progress = (offset + chunk.length) / fileSize;
            setState(() {
              _uploadStatuses['Facebook_$accountId'] = UploadStatus(
                platform: 'Facebook',
                accountId: accountId,
                state: UploadState.uploading,
                progress: progress
              );
            });
            
            // Report progress more explicitly
            print('Successfully uploaded chunk: $offset to ${offset + chunk.length} of $fileSize');
          } catch (e) {
            retryCount++;
            print('Error uploading chunk at offset $offset (attempt $retryCount): $e');
            
            if (retryCount >= maxRetries) {
              throw Exception('Failed to upload video chunk after $maxRetries attempts: $e');
            }
            
            // Wait longer before retry with exponential backoff (minimum 5 seconds)
            final backoffSeconds = 5 * (retryCount + 1); // 10, 15, 20, 25 seconds
            print('Retrying in $backoffSeconds seconds...');
            await Future.delayed(Duration(seconds: backoffSeconds));
          }
        }
        
        offset = end;
      }
      
      // STEP 3: Finalize the upload
      bool finalizationSuccess = false;
      int finalizeRetryCount = 0;
      const maxFinalizeRetries = 3;
      
      while (!finalizationSuccess && finalizeRetryCount < maxFinalizeRetries) {
        try {
          print('Attempting to finalize Facebook upload...');
          final finishResponse = await http.post(
            Uri.parse('https://graph.facebook.com/v18.0/$pageId/videos'),
            body: {
              'access_token': accessToken,
              'upload_phase': 'finish',
              'upload_session_id': uploadSessionId,
              'title': _titleController.text.isNotEmpty ? _titleController.text : 'Video from Fluzar',
              'description': _descriptionController.text,
            },
          ).timeout(const Duration(seconds: 60), onTimeout: () {
            throw TimeoutException('Finalize request timed out');
          });
          
          if (finishResponse.statusCode != 200) {
            throw Exception('Failed to finalize Facebook video upload: ${finishResponse.body}');
          }
          
          final finishData = json.decode(finishResponse.body);
          final videoId = finishData['id'];
          finalizationSuccess = true;
          print('Successfully uploaded video to Facebook with ID: $videoId');
          
          setState(() {
            _uploadStatuses['Facebook_$accountId'] = UploadStatus(
              platform: 'Facebook',
              accountId: accountId,
              state: UploadState.completed,
              progress: 1.0
            );
          });

          return videoId;
        } catch (e) {
          finalizeRetryCount++;
          print('Error finalizing upload (attempt $finalizeRetryCount): $e');
          
          if (finalizeRetryCount >= maxFinalizeRetries) {
            throw Exception('Failed to finalize video upload after $maxFinalizeRetries attempts: $e');
          }
          
          // Longer wait before retry with exponential backoff
          final backoffSeconds = 8 * finalizeRetryCount;
          print('Retrying finalization in $backoffSeconds seconds...');
          await Future.delayed(Duration(seconds: backoffSeconds));
        }
      }
      
      throw Exception('Failed to complete Facebook upload process');
    } catch (e) {
      setState(() {
        _uploadStatuses['Facebook_$accountId'] = UploadStatus(
          platform: 'Facebook',
          accountId: accountId,
          state: UploadState.error,
          error: e.toString(),
          progress: 0.0
        );
      });
      rethrow;
    }
  }

  Future<void> _uploadToThreads(String accountId, String? cloudflareUrl) async {
    try {
      _updateUploadStatus('Threads', accountId, state: UploadState.uploading);
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      print('Uploading to Threads with account ID: $accountId');

      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('Threads account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final userId = accountData['user_id'] ?? accountId;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Threads access token not found');
      }
      
      // Nota: L'API di Threads attualmente non supporta la pubblicazione diretta di contenuti tramite API
      // Questo è un placeholder per futura implementazione quando l'API sarà disponibile
      // Per ora mostreremo un messaggio all'utente spiegando la limitazione

      await Future.delayed(const Duration(seconds: 2)); // Simula un ritardo di rete
      
      // Update upload status to show a message to the user
      _updateUploadStatus(
        'Threads', 
        accountId,
        state: UploadState.error,
        error: 'Threads API currently does not support direct posting. The video will need to be posted manually.',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Threads API limitations: direct posting not available. Please post manually.',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
              ),
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        );
      }
      
      // Update the last sync time for the account
      await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .update({
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });
      
      print('Threads upload process completed (with API limitation notice)');
      
    } catch (e) {
      print('Error during Threads upload process: $e');
      _updateUploadStatus(
        'Threads', 
        accountId,
        state: UploadState.error,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<String?> _uploadToCloudflare(File file, {bool isImage = false, String? customPath}) async {
    try {
      print('[Cloudflare] Inizio upload ${isImage ? "image" : "video"}: ${file.path}');
      if (!file.existsSync()) {
        print('[Cloudflare] Errore: file non esiste: ${file.path}');
        return null;
      }
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('[Cloudflare] Errore: utente non autenticato');
        return null;
      }
      final String accessKeyId = '5e181628bad7dc5481c92c6f3899efd6';
      final String secretKey = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
      final String endpoint = 'https://3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com';
      final String bucketName = 'videos';
      final String accountId = '3d945eb681944ec5965fecf275e41a9b';
      final String region = 'auto';
      final String fileExtension = file.path.split('.').last;
      final String fileName = customPath ??
        'media_${DateTime.now().millisecondsSinceEpoch}_${currentUser.uid}.${fileExtension}';
      final String fileKey = fileName;
      final bytes = await file.readAsBytes();
      final contentLength = bytes.length;
      final List<int> contentHash = sha256.convert(bytes).bytes;
      final String payloadHash = hex.encode(contentHash);
      final String httpMethod = 'PUT';
      final String contentType = isImage ? 'image/jpeg' : 'video/mp4';
      final now = DateTime.now().toUtc();
      final String amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
      final String dateStamp = DateFormat("yyyyMMdd").format(now);
      final Uri uri = Uri.parse('$endpoint/$bucketName/$fileKey');
      final String host = uri.host;
      final Map<String, String> headers = {
        'host': host,
        'content-type': contentType,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate
      };
      String canonicalHeaders = '';
      String signedHeaders = '';
      final sortedHeaderKeys = headers.keys.toList()..sort();
      for (final key in sortedHeaderKeys) {
        canonicalHeaders += '${key.toLowerCase()}:${headers[key]}\n';
        signedHeaders += '${key.toLowerCase()};';
      }
      signedHeaders = signedHeaders.substring(0, signedHeaders.length - 1);
      final String canonicalUri = '/$bucketName/$fileKey';
      final String canonicalQueryString = '';
      final String canonicalRequest = '$httpMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
      final String algorithm = 'AWS4-HMAC-SHA256';
      final String scope = '$dateStamp/$region/s3/aws4_request';
      final String stringToSign = '$algorithm\n$amzDate\n$scope\n${hex.encode(sha256.convert(utf8.encode(canonicalRequest)).bytes)}';
      List<int> getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
        final kDate = Hmac(sha256, utf8.encode('AWS4$key')).convert(utf8.encode(dateStamp)).bytes;
        final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
        final kService = Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
        final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
        return kSigning;
      }
      final signingKey = getSignatureKey(secretKey, dateStamp, region, 's3');
      final signature = hex.encode(Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).bytes);
      final String authorizationHeader = '$algorithm Credential=$accessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
      final String uploadUrl = '$endpoint/$bucketName/$fileKey';
      final http.Request request = http.Request('PUT', Uri.parse(uploadUrl));
      request.headers['Host'] = host;
      request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = contentLength.toString();
      request.headers['X-Amz-Content-Sha256'] = payloadHash;
      request.headers['X-Amz-Date'] = amzDate;
      request.headers['Authorization'] = authorizationHeader;
      request.bodyBytes = bytes;
      print('[Cloudflare] Inizio upload HTTP PUT su $uploadUrl');
      final response = await http.Client().send(request);
      final responseBody = await response.stream.bytesToString();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final String publicUrl = 'https://pub-$accountId.r2.dev/$fileKey';
        print('[Cloudflare] Upload riuscito! Public URL: $publicUrl');
        return publicUrl;
      } else {
        print('[Cloudflare] Errore upload: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      print('[Cloudflare] Errore generale upload: $e');
      return null;
    }
  }

  Future<void> _saveAsDraft() async {
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video first')),
      );
      return;
    }

    if (_selectedAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one account')),
      );
      return;
    }

    // Validate YouTube titles if YouTube accounts are selected
    if (!_validateYouTubeTitles()) {
      _showYouTubeTitleError();
      return;
    }

    // Validate TikTok video length if TikTok accounts are selected
    if (!await _validateTikTokVideoLength()) {
      _showTikTokVideoLengthError();
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Upload to Cloudflare - always upload both videos and images
        String? cloudflareVideoUrl = await _uploadToCloudflare(
          _videoFile!, 
          isImage: _isImageFile
        );
        
        // Generate thumbnail only if it's a video file
        String? thumbnailPath;
        String? thumbnailCloudflareUrl;
        if (!_isImageFile) {
          thumbnailPath = await _generateThumbnail(_videoFile!);
          if (thumbnailPath != null) {
            // Upload thumbnail to Cloudflare
            thumbnailCloudflareUrl = await _uploadThumbnailToCloudflare(File(thumbnailPath));
          }
        }
        
        final videoRef = _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('videos')
            .push();

        // Prepare accounts data following the same structure as schedule_confirmation.dart
        final accountsData = <String, List<Map<String, dynamic>>>{};
        for (var platform in _selectedAccounts.keys) {
          final accounts = _selectedAccounts[platform]!;
          final platformAccounts = <Map<String, dynamic>>[];
          
          for (var accountId in accounts) {
            final account = _socialAccounts[platform]?.firstWhere(
              (acc) => acc['id'] == accountId,
              orElse: () => <String, dynamic>{},
            );
            
            if (account != null && account.isNotEmpty) {
              platformAccounts.add({
                'username': account['username'] ?? '',
                'display_name': account['display_name'] ?? account['username'] ?? '',
                'profile_image_url': account['profile_image_url'] ?? '',
                'followers_count': account['followers_count']?.toString() ?? '0',
              });
            }
          }
          
          if (platformAccounts.isNotEmpty) {
            accountsData[platform.toLowerCase()] = platformAccounts;
          }
        }

        // Get video duration if it's a video file
        Map<String, int>? videoDuration;
        if (!_isImageFile) {
          videoDuration = await _getVideoDurationForDatabase();
        }

        // Copia il video in app_flutter se non già presente
        final appDocDir = await getApplicationDocumentsDirectory();
        final fileName = _videoFile!.path.split('/').last;
        final appFlutterPath = '${appDocDir.path}/$fileName';
        File appFlutterFile = File(appFlutterPath);
        if (_videoFile!.path != appFlutterPath) {
          await _videoFile!.copy(appFlutterPath);
          // Video copiato in app_flutter
        } else {
          // Video già in app_flutter
        }

        final videoData = {
          'id': videoRef.key,
          'title': _titleController.text,
          'platforms': _selectedAccounts.keys.toList(),
          'status': 'draft', // Always save as draft when using _saveAsDraft
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'video_path': appFlutterPath, // path in app_flutter
          'cloudflare_url': cloudflareVideoUrl ?? '',
          'thumbnail_path': thumbnailCloudflareUrl ?? (_isImageFile ? cloudflareVideoUrl : null) ?? '',
          'accounts': accountsData,
          'user_id': currentUser.uid,
          'scheduled_time': null, // No scheduled time for drafts
          'is_image': _isImageFile, // Add flag to indicate if this is an image
          // Add video duration information if available
          if (videoDuration != null) ...{
            'video_duration_seconds': videoDuration['total_seconds'],
            'video_duration_minutes': videoDuration['minutes'],
            'video_duration_remaining_seconds': videoDuration['seconds'],
          },
        };
        
        // Add description only if it's not empty
        if (_descriptionController.text.isNotEmpty) {
          videoData['description'] = _descriptionController.text;
        }

        // Add Cloudflare thumbnail URL if available (for videos)
        if (thumbnailCloudflareUrl != null) {
          videoData['thumbnail_cloudflare_url'] = thumbnailCloudflareUrl;
        }
        
        // Add Cloudflare URL for both videos and images
        if (cloudflareVideoUrl != null) {
          videoData['cloudflare_url'] = cloudflareVideoUrl;
          
          // For images, also set as thumbnail URL to ensure consistent display
          if (_isImageFile) {
            videoData['thumbnail_cloudflare_url'] = cloudflareVideoUrl;
          }
        }

        // Add YouTube thumbnail file path if available
        if (_youtubeThumbnailFile != null) {
          videoData['youtube_thumbnail_path'] = _youtubeThumbnailFile!.path;
        }

        await videoRef.set(videoData);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.black),
                SizedBox(width: 8),
                Text(
                  _isImageFile ? 'Image saved as draft successfully' : 'Video saved as draft successfully',
                  style: TextStyle(color: Colors.black),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
            duration: Duration(seconds: 3),
          ),
        );
        _refreshPage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving draft: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }
  // Generate a thumbnail from the video file
  Future<String?> _generateThumbnail(File videoFile) async {
    if (_isImageFile) return null;
    
    try {
      print('Generating thumbnail for: ${videoFile.path}');
      
      // Use video_thumbnail package to generate thumbnail
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        quality: 80,
        maxWidth: 320, // Reasonable width for thumbnails
        timeMs: 500, // Take frame at 500ms
      );
      
      if (thumbnailBytes == null) {
        print('Failed to generate thumbnail: thumbnailBytes is null');
        return null;
      }
      
      // Save the thumbnail locally
      final thumbnailFile = await _saveThumbnailToFile(thumbnailBytes, videoFile);
      if (thumbnailFile != null) {
        print('Thumbnail generated and saved at: ${thumbnailFile.path}');
        return thumbnailFile.path;
      } else {
        print('Failed to save thumbnail file');
        return null;
      }
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }
  
  // Save thumbnail bytes to a file
  Future<File?> _saveThumbnailToFile(Uint8List thumbnailBytes, File videoFile) async {
    try {
      final fileName = videoFile.path.split('/').last;
      final thumbnailFileName = '${fileName.split('.').first}_thumbnail.jpg';
      
      // Get the app's temporary directory
      final directory = await getTemporaryDirectory();
      final thumbnailPath = '${directory.path}/$thumbnailFileName';
      
      // Save the file
      final file = File(thumbnailPath);
      await file.writeAsBytes(thumbnailBytes);
      return file;
    } catch (e) {
      print('Error saving thumbnail file: $e');
      return null;
    }
  }
  
  // Upload thumbnail to Cloudflare R2
  Future<String?> _uploadThumbnailToCloudflare(File thumbnailFile) async {
    try {
      if (!thumbnailFile.existsSync()) {
        print('Thumbnail file does not exist: ${thumbnailFile.path}');
        return null;
      }
      
      // Upload the thumbnail with an appropriate path in Cloudflare
      final String videoFileName = _videoFile?.path.split('/').last.split('.').first ?? 'unknown';
      final String thumbnailCloudPath = 'videos/thumbnails/${videoFileName}_thumbnail.jpg';
      
      // Use the existing method to upload to Cloudflare with the thumbnail path
      try {
        final thumbnailUrl = await _uploadToCloudflare(
          thumbnailFile, 
          isImage: true,
          customPath: thumbnailCloudPath
        );
        return thumbnailUrl;
      } catch (e) {
        print('Error in Cloudflare upload for thumbnail: $e');
        // Even if Cloudflare upload fails, we still have a local thumbnail
        // so we can continue with the draft creation
        return null;
      }
    } catch (e) {
      print('Error uploading thumbnail: $e');
      return null;
    }
  }

  // Metodo per generare descrizione generale
  Future<void> _generateDescription() async {
    if (_promptController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insert a prompt for the description')),
      );
      return;
    }

    setState(() {
      _isGeneratingDescription = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': 'Write a description for social media. The response must be properly coded and must not exceed 180 characters including spaces, and the emoji must be in a readable format. Here are the topics of the video: ${_promptController.text}',
            }
          ],
          'max_tokens': _maxTokens,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String generatedText = data['choices'][0]['message']['content'];
        
        // Clean up any potential encoding issues
        generatedText = generatedText
            .replaceAll(RegExp(r'\\u[0-9a-fA-F]{4}'), '') // Remove broken unicode
            .replaceAll(RegExp(r'[^\x00-\x7F]+'), '') // Remove non-ASCII chars
            .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
            .trim();
        
        setState(() {
          _descriptionController.text = generatedText;
        });
      } else {
        throw Exception('Failed to generate description: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating description: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isGeneratingDescription = false;
      });
    }
  }

  // Metodo per generare descrizione per una piattaforma specifica
  Future<void> _generatePlatformDescription(String platform) async {
    if (_platformPromptControllers[platform]?.text.isEmpty ?? true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insert a prompt for the description')),
      );
      return;
    }

    setState(() {
      _isGeneratingDescription = true;
      // Importante: imposta una variabile specifica per ogni piattaforma per evitare interferenze
      _platformDescriptionLengths[platform] = 0; // Reset counter temporaneamente
    });

    try {
      // Update UI to show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating description...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': 'Write a description for ${platform} based on this information: ${_platformPromptControllers[platform]?.text}. '
                  'The response must be properly formatted and not exceed ${_platformChatGPTLimits[platform]} characters. '
                  'If the platform is Twitter, include relevant hashtags. '
                  'Do not use phrases with "discover", "explore", "join us" or similar. Use emojis in readable format.',
            }
          ],
          'max_tokens': _maxTokens,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String generatedText = data['choices'][0]['message']['content'];
        
        // Clean up any potential encoding issues
        generatedText = generatedText
            .replaceAll(RegExp(r'\\u[0-9a-fA-F]{4}'), '') // Remove broken unicode
            .replaceAll(RegExp(r'[^\x00-\x7F]+'), '') // Remove non-ASCII chars
            .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
            .trim();
        
        setState(() {
          // Use platform-specific controller
          if (_platformDescriptionControllers[platform] != null) {
            _platformDescriptionControllers[platform]!.text = generatedText;
            _platformDescriptionLengths[platform] = generatedText.length;
          }
        });
      } else {
        throw Exception('Failed to generate description: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating description: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isGeneratingDescription = false;
      });
    }
  }

  Widget _buildDescriptionInput() {
    final theme = Theme.of(context);
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 300),
      crossFadeState: _useChatGPT ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: Card(
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextField(
          controller: _descriptionController,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
              hintText: 'Descrivi il tuo contenuto in modo coinvolgente...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
            style: TextStyle(
              fontSize: 15,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ),
      ),
      secondChild: Column(
        children: [
          Card(
            elevation: 1,
            shadowColor: Colors.black.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _promptController,
              decoration: InputDecoration(
                  hintText: 'Di cosa parla il tuo contenuto?',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                suffixIcon: IconButton(
                  icon: _isGeneratingDescription 
                      ? SizedBox(
                        width: 20,
                        height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                      )
                      : Icon(
                          Icons.auto_awesome,
                          color: theme.colorScheme.primary,
                        ),
                  onPressed: _isGeneratingDescription ? null : _generateDescription,
                  ),
                ),
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.05),
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
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Generated description with AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _descriptionController.text.isEmpty
                  ? Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'The generated description will appear here...',
                      style: TextStyle(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                        ),
                      ),
                    )
                  : Text(
                      _descriptionController.text,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Enhanced refresh method
  Future<void> _refreshPage() async {
    // Set flag to indicate we're refreshing after draft save
    _isRefreshingAfterDraftSave = true;
    
    setState(() {
      _videoFile = null;
      _thumbnailPath = null;
      _titleController.clear();
      _descriptionController.clear();
      _promptController.clear();
      _selectedAccounts.clear();
      _uploadStatuses.clear();
      _showCheckmark = false;
      _isImageFile = false;
      _isVideoFromUrl = false;
      _currentStep = UploadStep.selectMedia; // Reset to first step
      
      // Clear TikTok options (privacy settings, interaction settings, commercial content)
      _tiktokOptions.clear();
      
      // Reset the page controller
      _pageController.animateToPage(
        0,
        duration: Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      
      // Reset platform specific content flags to default (true = use global content)
      _socialAccounts.keys.forEach((platform) {
        _usePlatformSpecificContent[platform] = true;
        
        // Clear platform specific controllers
        if (_platformTitleControllers.containsKey(platform)) {
          _platformTitleControllers[platform]!.clear();
        }
        if (_platformDescriptionControllers.containsKey(platform)) {
          _platformDescriptionControllers[platform]!.clear();
        }
        if (_platformPromptControllers.containsKey(platform)) {
          _platformPromptControllers[platform]!.clear();
        }
        
        // Reset custom flags
        _useChatGPTforPlatform[platform] = false;
        
        // Reset description length counters
        _platformDescriptionLengths[platform] = 0;
      });
      
      // Clear account-specific content (custom descriptions for each account)
      _accountSpecificContent?.clear();
      
      // Close all social platform dropdowns
      _expandedState.clear();
      _currentlyExpandedPlatform = null;
    });
    
    await Future.wait([
      _loadSocialAccounts(),
    ]);
    
    // Reset the flag after refresh is complete
    _isRefreshingAfterDraftSave = false;

  }

  // Add confirmation dialog method
  Future<void> _showRefreshConfirmation() async {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          child: Container(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                
                // Title
                Text(
                  'Confirm Refresh',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'This will reset all your current progress',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Actions list
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildActionItem(Icons.clear, 'Clear selected video'),
                      _buildActionItem(Icons.description, 'Clear all descriptions'),
                      _buildActionItem(Icons.people, 'Deselect all accounts'),
                      _buildActionItem(Icons.settings, 'Reset all custom settings'),
                      _buildActionItem(Icons.video_settings, 'Clear TikTok settings'),
                      _buildActionItem(Icons.arrow_back, 'Return to step 1'),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _refreshPage();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Confirm',
                          style: TextStyle(
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
  }

  Widget _buildActionItem(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey[600],
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Debounce scroll per evitare troppi setState
  void _onScrollDebounced() {
    if (_scrollDebounceTimer?.isActive ?? false) _scrollDebounceTimer!.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 150), () { // Aumentato da 80 a 150ms
      if (!mounted) return;
      final newPosition = _scrollController.position.pixels;
      if ((newPosition - _scrollPosition).abs() > 5) { // Aumentato threshold da 2 a 5
            setState(() {
          _scrollPosition = newPosition;
            });
        }
      });
  }

  // Inizializza il controller del video
  void _initializeVideoPlayer(File videoFile) {
    // Disponi il controller precedente se esiste
    if (_videoPlayerController != null) {
      if (_videoPlayerController!.value.isPlaying) {
        _videoPlayerController!.pause();
      }
      _videoPlayerController!.dispose();
    }
    
    // Crea un nuovo controller
    _videoPlayerController = VideoPlayerController.file(videoFile);
    
    // Inizializza e riproduci il video
    _videoPlayerController!.initialize().then((_) {
      if (!mounted) return; // Check if widget is still mounted
      setState(() {
        _isVideoInitialized = true;
        _videoDuration = _videoPlayerController!.value.duration;
        _currentPosition = Duration.zero;
      });
      // Loop the video but don't play it automatically
      _videoPlayerController!.setLooping(true);
      // Keep video paused by default
      _videoPlayerController!.pause();
      
      // Start position update timer
      _startPositionUpdateTimer();
    });
  }

  // New helper method to show YouTube shorts info dialog
  void _showYouTubeShortsInfoDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Image.asset(
                'assets/loghi/logo_yt.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              const Text(
                'YouTube Video Formats',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YouTube automatically determines if your video will be classified as a "Short" based on:',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Duration must be 60 seconds or less',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.crop_portrait,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Vertical format (9:16 aspect ratio)',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'No manual selection is needed. Your video will automatically appear in the appropriate format based on these criteria.',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Got it',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
        return Scaffold(
       resizeToAvoidBottomInset: false,
       backgroundColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50],
       body: SafeArea(
        child: Stack(
          children: [
            // Main content area with PageView for horizontal swiping - adjusted for top bar
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.15), // Reduced padding for top bar
                  child: PageView(
                    controller: _pageController,
                    physics: NeverScrollableScrollPhysics(), // Disable horizontal swiping completely
                    onPageChanged: (index) {
                      // Only allow navigation to the next page if a video is selected
                      if (index > 0 && _videoFile == null) {
                        _pageController.animateToPage(
                          0,
                          duration: Duration(milliseconds: 300), // Ridotto da 400 a 300ms
                          curve: Curves.easeOutCubic, // Curva più performante
                        );
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Select a video before proceeding',
                              style: TextStyle(color: Colors.black),
                            ),
                            backgroundColor: Colors.white,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                        return;
                      }
                      
                      setState(() {
                        _currentStep = UploadStep.values[index];
                      });
                    },
                    children: [
                      // Step 1: Media selection
                      _buildMediaSelectionStep(theme),
                      
                      // Step 2: Details
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _buildDetailsStep(theme),
                      ),
                      
                      // Step 3: Accounts selection
                      SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _buildAccountsSelectionStep(theme),
                      ),
                    ],
                  ),
                ),
            
            // Top bar positioned at the top
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            
            // Floating progress indicator at top - similar to history page search bar
            Positioned(
              top: MediaQuery.of(context).size.height * 0.08, // 8% dell'altezza dello schermo
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildMinimalisticStepIndicator(context),
              ),
            ),
            
            // Refresh button in top-left corner
            Positioned(
              top: MediaQuery.of(context).size.height * 0.09, // 10% dell'altezza dello schermo
              left: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.refresh, color: theme.colorScheme.primary),
                  tooltip: 'Refresh',
                  onPressed: _showRefreshConfirmation,
                ),
              ),
            ),
            
            
            // Upload progress indicator - displayed when saving draft
            if (_isUploading)
              Positioned(
                bottom: 20 + MediaQuery.of(context).size.height * 0.10, // 20px + 6% dell'altezza dello schermo
                left: 20,
                right: 20,
                  child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Preparing the file...',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            LinearProgressIndicator(
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Fullscreen video overlay
            if (_isVideoFullscreen && !_isImageFile && _isVideoInitialized && _videoPlayerController != null)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showVideoControls = !_showVideoControls;
                    });
                    
                    // Reset timer for auto-hide controls
                    _controlsHideTimer?.cancel();
                    if (_showVideoControls) {
                      _controlsHideTimer = Timer(Duration(seconds: 3), () {
                        if (mounted && _isVideoFullscreen) {
                          setState(() {
                            _showVideoControls = false;
                          });
                        }
                      });
                    }
                  },
                  child: Container(
                    color: Colors.black,
                    child: Stack(
                      children: [
                        // Video player
                        _buildVideoPlayer(_videoPlayerController!),
                        
                        // Fullscreen controls
                        AnimatedOpacity(
                          opacity: _showVideoControls ? 1.0 : 0.0,
                          duration: Duration(milliseconds: 300),
                          child: Stack(
                            children: [
                              // Semi-transparent overlay
                              Container(
                                width: double.infinity,
                                height: double.infinity,
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
                              
                              // Exit fullscreen button
                              Positioned(
                                top: 20,
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
                              
                              // Play/Pause button at center
                              Center(
                                child: GestureDetector(
                                  onTap: _toggleVideoPlayback,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _videoPlayerController!.value.isPlaying 
                                        ? Icons.pause 
                                        : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                              
                              // Progress bar at bottom
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
                                          activeTrackColor: theme.colorScheme.primary,
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
                                            final newPosition = Duration(seconds: value.toInt());
                                            _videoPlayerController?.seekTo(newPosition);
                                            setState(() {
                                              _currentPosition = newPosition;
                                            });
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
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }

  // Build a minimalistic step indicator
  Widget _buildMinimalisticStepIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            // Effetto vetro sospeso - sfondo trasparente per mostrare il contenuto dietro
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final isActive = index == _currentStep.index;
              final isCompleted = index < _currentStep.index;
              return Row(
                children: [
                  // Circle indicator
                  GestureDetector(
                    onTap: () {
                      // Consenti la navigazione quando il video è selezionato o quando si va al primo step
                      if (_videoFile != null || index == 0) {
                        setState(() {
                          _currentStep = UploadStep.values[index];
                          // Usa il controller per navigare effettivamente alla pagina
                          _pageController.animateToPage(
                            index,
                            duration: Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        });
                      } else if (index > 0 && _videoFile == null) {
                        // Mostra un messaggio se si tenta di navigare senza selezionare un video
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Select a video before proceeding',
                              style: TextStyle(color: Colors.black),
                            ),
                            backgroundColor: Colors.white,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted 
                            ? Color(0xFF667eea) // Use gradient start color for completed
                            : isActive
                                ? Color(0xFF667eea).withOpacity(0.1) // Use gradient start color with opacity for active
                                : (theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.grey.shade100),
                        border: Border.all(
                          color: isActive || isCompleted 
                              ? Color(0xFF667eea) // Use gradient start color for border
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 14,
                              )
                            : Text(
                                (index + 1).toString(),
                                style: TextStyle(
                                  color: isActive 
                                      ? Color(0xFF667eea) // Use gradient start color for active text
                                      : Colors.grey.shade500,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                      ),
                    ),
                  ),
                  // Line between steps (except after last) with gradient
                  if (index < 2)
                    Container(
                      width: 32,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: index < _currentStep.index
                            ? LinearGradient(
                                colors: [
                                  Color(0xFF667eea), // Initial color: blu violaceo
                                  Color(0xFF764ba2), // Final color: viola
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                transform: GradientRotation(135 * 3.14159 / 180), // 135 degrees
                              )
                            : null,
                      color: index < _currentStep.index
                            ? null
                          : Colors.grey.shade300,
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }


  // Build the content for the current step
  Widget _buildCurrentStepContent(ThemeData theme) {
    switch (_currentStep) {
      case UploadStep.selectMedia:
        return Container(); // Empty container as media step is handled separately
      case UploadStep.addDetails:
        return _buildDetailsStep(theme);
      case UploadStep.selectAccounts:
        return _buildAccountsSelectionStep(theme);
    }
  }

  // Build the media selection step content
  Widget _buildMediaSelectionStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            // Title and description - only show when no media selected
            if (_videoFile == null)
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.cloud_upload_outlined,
                          size: 24,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Media',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Choose a video or image to upload to your social media accounts',
                              style: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: theme.colorScheme.secondary,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Supported formats: MP4, MOV, JPG, PNG',
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Add space only when the info box is shown (no media selected)
            if (_videoFile == null) 
            SizedBox(height: 24),
            
            // Media upload card - with height based on whether media is selected
            Container(
              height: _videoFile != null ? MediaQuery.of(context).size.height * 0.75 - 50.6 : 320, // Reduced by 2cm (75.6 logical pixels)
              padding: _videoFile != null ? EdgeInsets.only(top: 16) : EdgeInsets.zero, // Add top padding when video is selected
              child: Card(
                elevation: 2,
                margin: EdgeInsets.zero, // Remove margin to eliminate white space
                shadowColor: Colors.black.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: theme.colorScheme.primary.withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: GestureDetector(
                  onTap: _videoFile != null && !_isImageFile ? () {
                    // Show/hide video controls on tap
                    setState(() {
                      _showVideoControls = !_showVideoControls;
                    });
                    
                    // Hide controls automatically after 3 seconds
                    _controlsHideTimer?.cancel();
                    if (_showVideoControls) {
                      _controlsHideTimer = Timer(Duration(seconds: 3), () {
                        if (mounted && _videoPlayerController?.value.isPlaying == true) {
                          setState(() {
                            _showVideoControls = false;
                          });
                        }
                      });
                    }
                  } : _pickMedia,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _videoFile == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 48,
                                  color: theme.colorScheme.primary,
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
                                  'Tap to select media',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: theme.colorScheme.secondary.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'Video: MP4, MOV • Images: JPG, PNG',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildSelectedMediaPreview(theme),
                  ),
                ),
              ),
            ),
            // Remove this SizedBox that was creating white space at the bottom
            // SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  // New method to extract media preview for better organization
  Widget _buildSelectedMediaPreview(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double containerHeight = constraints.maxHeight * 1;
        

        
        return Stack(
          children: [
            // Video preview or Image preview
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _isImageFile 
                ? Image.file(
                    _videoFile!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: containerHeight,
                  )
                : _isVideoInitialized && _videoPlayerController != null
                  ? Container(
                      width: double.infinity,
                      height: containerHeight,
                      color: const Color(0xFF1E1E1E),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _buildVideoPlayer(_videoPlayerController!),
                            
                            // Video controls overlay
                            AnimatedOpacity(
                              opacity: _showVideoControls ? 1.0 : 0.0,
                              duration: Duration(milliseconds: 300),
                              child: Stack(
                                children: [
                                  // Semi-transparent overlay
                                  Container(
                                    width: double.infinity,
                                    height: double.infinity,
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
                                  
                                  // Play/Pause button at center
                                  Center(
                                    child: GestureDetector(
                              onTap: _toggleVideoPlayback,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _videoPlayerController!.value.isPlaying 
                                    ? Icons.pause 
                                    : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                      ),
                                    ),
                                  ),
                                  
                                  // Progress bar at bottom
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
                                              activeTrackColor: theme.colorScheme.primary,
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
                                                final newPosition = Duration(seconds: value.toInt());
                                                _videoPlayerController?.seekTo(newPosition);
                                                setState(() {
                                                  _currentPosition = newPosition;
                                                });
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
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Loading video...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
            ),
              
            // Control buttons
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  // Show URL indicator if video was loaded from URL
                  if (_isVideoFromUrl)
                    Container(
                      margin: EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'URL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Fullscreen button for videos
                  if (!_isImageFile && _videoFile != null && _isVideoInitialized)
                    InkWell(
                      onTap: _toggleFullScreen,
                      child: Container(
                        margin: EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isVideoFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  
                  // Video editor button
                  if (!_isImageFile && _videoFile != null)
                    InkWell(
                      onTap: _navigateToVideoEditor,
                      child: Container(
                        margin: EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: () {
                      // Clear video selection
                      setState(() {
                        // Dispose the video controller
                        if (_videoPlayerController != null) {
                          _videoPlayerController!.pause();
                          _videoPlayerController!.dispose();
                          _videoPlayerController = null;
                          _isVideoInitialized = false;
                        }
                        _videoFile = null;
                        _showCheckmark = false;
                        _isImageFile = false;
                        _isVideoFromUrl = false;
                        _isVideoFullscreen = false;
                        _isVideoLocked = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Build the details step content
  Widget _buildDetailsStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and description header
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.description,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Details',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Add a description for your post (optional)',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Streamlined info container
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.green[800],
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'General content for all accounts (customizable in the next step)',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 24),
          
          // Combined content box for title and description
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                
                // Description section with AI toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Description',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Use AI',
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _useChatGPT,
                          onChanged: (value) {
                            setState(() {
                              _useChatGPT = value;
                            });
                          },
                          activeColor: Color(0xFF667eea),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildEnhancedDescriptionInput(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build enhanced description input with lighter color background
  Widget _buildEnhancedDescriptionInput(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 300),
      crossFadeState: _useChatGPT ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: _descriptionController,
            maxLines: 8, // Default large size for main description
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Describe your content in a compelling way...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
            ),
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black87,
              height: 1.5,
            ),
          ),
        ),
      ),
      secondChild: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: _promptController,
                decoration: InputDecoration(
                  hintText: 'What is the content about?',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
                  suffixIcon: IconButton(
                    icon: _isGeneratingDescription 
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                      : Icon(
                        Icons.auto_awesome,
                        color: theme.colorScheme.primary,
                      ),
                    onPressed: _isGeneratingDescription ? null : _generateDescription,
                  ),
                ),
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.03),
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
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Generated description with AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _descriptionController.text.isEmpty
                  ? Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'The generated description will appear here...',
                    style: TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                )
                  : Text(
                  _descriptionController.text,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // Build the accounts selection step content
  Widget _buildAccountsSelectionStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    // Preload accounts when this widget is built to prevent lag
    // ma solo se non sono stati caricati di recente
    final now = DateTime.now();
    if (!_accountsLoaded || (_lastAccountsLoadTime != null && now.difference(_lastAccountsLoadTime!).inSeconds > 60)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSocialAccounts();
      });
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and description
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.people_alt_outlined,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Accounts',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Choose which social media accounts to post to',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Account counter badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _getAccountsColor(theme),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _getTotalSelectedAccounts().toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Customisable features for each accounts',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
                  
                    SizedBox(height: 24),
          
          // Social accounts section (temporarily hide TikTok)
          ..._socialAccounts.entries.where((entry) => entry.key != 'Twitter' && entry.key != 'TikTok').map((entry) {
            final platform = entry.key;
            final accounts = entry.value;
            final isDark = theme.brightness == Brightness.dark;
            
            // Ensure that we have a key for this platform
            if (!_platformKeys.containsKey(platform)) {
              _platformKeys[platform] = GlobalKey();
            }
            
            // Make sure we have an expanded state for this platform
            if (!_expandedState.containsKey(platform)) {
              _expandedState[platform] = false;
            }
            
            return Container(
              key: _platformKeys[platform],
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900]! : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    curve: Curves.fastOutSlowIn,
                    decoration: BoxDecoration(
                      color: isDark ? Color(0xFF121212) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ExpansionTile(
                      key: PageStorageKey<String>('expansion_${platform}_1'),
                      initiallyExpanded: _expandedState[platform] ?? false,
                      maintainState: true,
                      backgroundColor: Colors.transparent,
                      collapsedBackgroundColor: Colors.transparent,
                      onExpansionChanged: (isExpanded) {
                        // When expanded, close all other panels
                        if (isExpanded) {
                          // Close all panels first
                          _closeAllPanelsExcept(platform);
                          
                          // Position the dropdown in the visible area
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _posizionaTendinaNellaParteAlta(platform);
                            }
                          });
                        } else {
                          // If this platform is being closed, update its state
                          setState(() {
                            _expandedState[platform] = false;
                          });
                        }
                      },
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.asset(
                          _platformLogos[platform] ?? '',
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                        ),
                      ),
                      title: Text(
                        platform,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Show selected accounts count badge
                          if (_selectedAccounts.containsKey(platform) && _selectedAccounts[platform]!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _selectedAccounts[platform]!.length.toString(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          // Icona con rotazione animata
                          CustomAnimatedRotation(
                            turns: _expandedState[platform] == true ? 0.5 : 0,
                            duration: Duration(milliseconds: 200),
                            child: Icon(Icons.keyboard_arrow_down),
                          ),
                        ],
                      ),
                      children: [
                        // Platform account selection section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Available accounts',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextButton.icon(
                                    icon: Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    label: Text(
                                      'Formats',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    onPressed: () {
                                      // Show platform info dialog
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          title: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.05),
                                                      blurRadius: 10,
                                                      spreadRadius: 1,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Image.asset(
                                                  _platformLogos[platform] ?? '',
                                                  width: 32,
                                                  height: 32,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                '$platform Info',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: double.maxFinite,
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.grey.shade100,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.03),
                                                      blurRadius: 10,
                                                      spreadRadius: 1,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: SingleChildScrollView(
                                                  child: Text(
                                                    _getPlatformInstructions(platform),
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      height: 1.5,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text(
                                                'Got it',
                                                style: TextStyle(
                                                  color: theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              
                              // Account items list
                              if (accounts.isEmpty)
                                Container(
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.account_circle_outlined,
                                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'No ${platform} accounts connected',
                                          style: TextStyle(
                                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          // Naviga direttamente alla pagina del social specifico
                                          _navigateToSocialPage('/${_getPlatformRouteName(platform)}');
                                        },
                                        child: Text('Connect'),
                                        style: TextButton.styleFrom(
                                          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                          foregroundColor: theme.colorScheme.primary,
                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Builder(
                                  builder: (context) {
                                    final List<dynamic> listAccounts = accounts is List
                                        ? accounts
                                        : (accounts is Map
                                            ? (accounts as Map).values.toList()
                                            : <dynamic>[]);
                                    return ListView.builder(
                                      key: PageStorageKey<String>('accounts_list_$platform'),
                                      shrinkWrap: true,
                                      physics: NeverScrollableScrollPhysics(),
                                      itemCount: listAccounts.length,
                                      itemBuilder: (context, index) {
                                        final rawAccount = listAccounts[index];
                                        final Map<String, dynamic> accountMap =
                                            rawAccount is Map ? Map<String, dynamic>.from(rawAccount as Map) : {
                                              'id': rawAccount?.toString() ?? ''
                                            };
                                        // Safe normalized fields
                                        final accountId = (accountMap['id'] ?? accountMap['channel_id'] ?? accountMap['user_id'] ?? accountMap['username'] ?? '').toString();
                                        final isSelected = _selectedAccounts[platform]?.contains(accountId) ?? false;
                                        final profileImageUrl = accountMap['profile_image_url'] as String?;
                                        final username = (accountMap['username'] ?? accountMap['display_name'] ?? '').toString();
                                        final followersCount = (accountMap['followers_count'] ?? accountMap['follower_count'] ?? accountMap['subscriber_count'] ?? '0').toString();
                                        final displayName = (accountMap['display_name'] ?? username).toString();

                                        return Column(
                                          children: [
                                            // Add divider between items (except the first one)
                                            if (index > 0)
                                              Divider(height: 1, indent: 72, endIndent: 16, color: Colors.grey.shade200),
                                            
                                            Container(
                                              margin: EdgeInsets.symmetric(vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                leading: _buildAccountProfileImage(
                                                  profileImageUrl,
                                                  username,
                                                  theme
                                                ),
                                                title: Text(
                                                  displayName,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark ? Colors.white : Colors.black87,
                                                    fontSize: 15,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                                subtitle: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // Only show username for non-TikTok accounts, since TikTok API doesn't allow it
                                                    if (platform != 'TikTok')
                                                      Text(
                                                        '@$username',
                                                        style: TextStyle(
                                                          color: Colors.grey[600],
                                                          fontSize: 13,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.people_outline,
                                                          size: 12,
                                                          color: Colors.grey[500],
                                                        ),
                                                        SizedBox(width: 4),
                                                        Text(
                                                          '$followersCount followers',
                                                          style: TextStyle(
                                                            color: Colors.grey[600],
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                trailing: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // Settings button for selected accounts
                                                    if (isSelected)
                                                      IconButton(
                                                        icon: Icon(
                                                          Icons.settings,
                                                          color: theme.colorScheme.primary,
                                                          size: 20,
                                                        ),
                                                        onPressed: () {
                                                          _showAccountConfigBottomSheet(platform, accountId);
                                                        },
                                                        tooltip: 'Configure content',
                                                        padding: EdgeInsets.zero,
                                                        constraints: BoxConstraints(
                                                          minWidth: 36,
                                                          minHeight: 36,
                                                        ),
                                                      ),
                                                    Switch(
                                                      value: isSelected,
                                                      onChanged: (platform == 'YouTube' && _isImageFile)
                                                          ? null
                                                          : (value) => _toggleAccount(platform, accountId),
                                                      activeColor: Color(0xFF667eea),
                                                    ),
                                                  ],
                                                ),
                                                onTap: () => _navigateToSocialAccountDetails(accountMap, platform),
                                                tileColor: isSelected ? theme.colorScheme.primary.withOpacity(0.05) : null,
                                                selectedTileColor: theme.colorScheme.primary.withOpacity(0.05),
                                              ),
                                            ),
                                            
                                            // Removed content type buttons for Instagram (now only shown in account settings)
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
          
          // Action buttons at the bottom
          SizedBox(height: 78), // Aumentato di 1 cm (38 pixel)
          _buildActionButtons(theme),
          
          // Padding finale della pagina
          SizedBox(height: 78), // Aggiunto 1 cm di padding finale
        ],
      ),
    );
  }

  // Get color for account selection based on count
  Color _getAccountsColor(ThemeData theme) {
    if (_selectedAccounts.isEmpty) {
      return Colors.grey;
    } else {
      return theme.colorScheme.primary; // Always blue when there are selected accounts
    }
  }

  // Get total count of selected accounts
  int _getTotalSelectedAccounts() {
    int total = 0;
    _selectedAccounts.values.forEach((accounts) => total += accounts.length);
    return total;
  }

  // Build TikTok specific options
  Widget _buildTikTokOptions(ThemeData theme, String accountId) {
    final isDark = theme.brightness == Brightness.dark;
    
    // Initialize TikTok options for this account if not exists
    if (!_tiktokOptions.containsKey(accountId)) {
      _tiktokOptions[accountId] = {
        'privacy_level': null,
        'allow_comments': true,
        'allow_duets': true,
        'allow_stitch': true,
        'commercial_content': false,
        'own_brand': false,
        'branded_content': false,
      };
    }
    
    return Container(
      margin: EdgeInsets.only(top: 8, left: 16, right: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy Level Section
          Text(
            'Privacy Settings',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          
          // Privacy Level Dropdown
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _tiktokOptions[accountId]!['privacy_level'],
                hint: Text(
                  'Select privacy level',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                isExpanded: true,
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                items: [
                  DropdownMenuItem(
                    value: 'SELF_ONLY',
                    child: Text('Private (Only me)'),
                  ),
                  DropdownMenuItem(
                    value: 'FRIENDS',
                    child: Text('Friends'),
                  ),
                  DropdownMenuItem(
                    value: 'PUBLIC',
                    child: Text('Public'),
                  ),
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    _tiktokOptions[accountId]!['privacy_level'] = newValue;
                    
                    // Handle commercial content restrictions
                    if (newValue == 'SELF_ONLY' && _tiktokOptions[accountId]!['branded_content']) {
                      _tiktokOptions[accountId]!['branded_content'] = false;
                      _tiktokOptions[accountId]!['commercial_content'] = false;
                    }
                  });
                },
                dropdownColor: isDark ? Colors.grey[700] : Colors.white,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
          
          // Interaction Settings Section
          Text(
            'Interaction Settings',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          
          // Comments
          CheckboxListTile(
            title: Text(
              'Allow comments',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            value: _tiktokOptions[accountId]!['allow_comments'] ?? true,
            onChanged: (bool? value) {
              setState(() {
                _tiktokOptions[accountId]!['allow_comments'] = value ?? true;
              });
            },
            activeColor: Color(0xFF667eea),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          
          // Duets (only for videos, not photos)
          if (!_isImageFile)
            CheckboxListTile(
              title: Text(
                'Allow duets',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              value: _tiktokOptions[accountId]!['allow_duets'] ?? true,
              onChanged: (bool? value) {
                setState(() {
                  _tiktokOptions[accountId]!['allow_duets'] = value ?? true;
                });
              },
              activeColor: Color(0xFF667eea),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          
          // Stitch (only for videos, not photos)
          if (!_isImageFile)
            CheckboxListTile(
              title: Text(
                'Allow stitch',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              value: _tiktokOptions[accountId]!['allow_stitch'] ?? true,
              onChanged: (bool? value) {
                setState(() {
                  _tiktokOptions[accountId]!['allow_stitch'] = value ?? true;
                });
              },
              activeColor: Color(0xFF667eea),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          
          SizedBox(height: 16),
          
          // Commercial Content Section
          Text(
            'Commercial Content Disclosure',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          
          // Commercial Content Toggle
          SwitchListTile(
            title: Text(
              'This content promotes a brand, product, or service',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            value: _tiktokOptions[accountId]!['commercial_content'],
            onChanged: (bool value) {
              setState(() {
                _tiktokOptions[accountId]!['commercial_content'] = value;
                if (!value) {
                  _tiktokOptions[accountId]!['own_brand'] = false;
                  _tiktokOptions[accountId]!['branded_content'] = false;
                }
              });
            },
            activeColor: Color(0xFF667eea),
            contentPadding: EdgeInsets.zero,
          ),
          
          // Commercial Content Options (only shown when commercial content is enabled)
          if (_tiktokOptions[accountId]!['commercial_content'])
            Column(
              children: [
                SizedBox(height: 8),
                
                // Own Brand
                CheckboxListTile(
                  title: Text(
                    'Your own brand',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Content will be labeled as "Promotional Content"',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  value: _tiktokOptions[accountId]!['own_brand'],
                  onChanged: (bool? value) {
                    setState(() {
                      _tiktokOptions[accountId]!['own_brand'] = value ?? false;
                    });
                  },
                  activeColor: Color(0xFF667eea),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                
                // Branded Content
                CheckboxListTile(
                  title: Text(
                    'Branded content',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Content will be labeled as "Paid Partnership"',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  value: _tiktokOptions[accountId]!['branded_content'],
                  onChanged: _tiktokOptions[accountId]!['privacy_level'] == 'SELF_ONLY' 
                    ? null 
                    : (bool? value) {
                        setState(() {
                          _tiktokOptions[accountId]!['branded_content'] = value ?? false;
                        });
                      },
                  activeColor: Color(0xFF667eea),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                
                // Warning message for branded content with private privacy
                if (_tiktokOptions[accountId]!['privacy_level'] == 'SELF_ONLY')
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          color: Colors.orange,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Branded content cannot be private',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // Build account profile image with fallback
  Widget _buildAccountProfileImage(String? profileImageUrl, String username, ThemeData theme) {
    final firstLetter = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final randomColor = _getPlatformColor(username);
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: randomColor.withOpacity(0.1),
        border: Border.all(color: randomColor.withOpacity(0.2), width: 1),
      ),
      child: profileImageUrl != null && profileImageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                profileImageUrl,
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (context, error, stackTrace) => Center(
        child: Text(
                    firstLetter,
          style: TextStyle(
                      fontSize: 20,
            fontWeight: FontWeight.bold,
                      color: randomColor,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                firstLetter,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: randomColor,
                ),
          ),
        ),
      );
  }
  
  // Metodo per ottenere le istruzioni specifiche per ciascuna piattaforma
  String _getPlatformInstructions(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return '⏰ Duration\n• Mobile: 10 min max\n• Web: 60 min max\n\n'
               '💾 File Size\n• Maximum: 500 MB\n\n'
               '🎬 Supported Formats\n• MP4 or MOV (iOS: MOV; Android: MP4, WEBM also supported)\n\n'
               '📝 Caption Limit\n• Up to 2,200 characters\n• For ads: 100 characters (no emojis)\n\n'
               '📐 Aspect Ratio\n• 9:16 (preferred)\n• Also supports 1:1 and 16:9';
      case 'youtube':
        return '⏰ Duration\n• Standard: 12 hours max\n• Shorts: 60 seconds max\n\n'
               '💾 File Size\n• Standard: 128 GB max\n• Shorts: 2 GB max\n\n'
               '🎬 Formats\n• MP4, MOV, AVI, WMV, WebM\n\n'
               '📝 Description\n• Up to 5,000 characters\n\n'
               '📐 Aspect Ratio\n• Standard: 16:9 (recommended)\n• Shorts: 9:16 (1080×1920)\n\n'
               '⚙️ Note\n• Vertical videos >1min become regular videos (verified accounts)';
      case 'instagram':
        return '⏰ Duration\n• Feed: 15 min (in-app), 60 min (desktop)\n• Reels: 3 min recorded, 15 min uploaded\n\n'
               '💾 File Size\n• Feed & Reels: 4 GB max\n\n'
               '🎬 Formats\n• JPG/PNG (photos), MP4/MOV (videos)\n• Reels: MP4/MOV, H.264/AAC, 30fps+\n\n'
               '📝 Description\n• Up to 2,200 characters\n\n'
               '📐 Aspect Ratio\n• Feed: 1.91:1 to 9:16\n• Reels: 9:16 (1080×1920)\n\n'
               'ℹ️ Note: Photos → feed, vertical videos → Reels';
      case 'facebook':
        return '⏰ Duration\n• Page videos: 240 min (4 hours) max, min 1 second\n\n'
               '💾 File Size\n• Maximum: 4 GB\n\n'
               '🎬 Supported Formats\n• MP4, MOV (also AVI, WMV, etc.)\n\n'
               '📝 Description\n• Up to 8,000 characters\n\n'
               '📐 Aspect Ratio\n• 16:9 landscape, 9:16 portrait';
      case 'twitter':
        return '⏰ Duration\n• Standard User: 2 minutes 20 seconds (140s)\n• Premium (X Blue): 2 hours (web), 10 minutes (mobile app)\n\n'
               '💾 File Size\n• Standard User: 512 MB\n• Premium: 2 GB (mobile), 8 GB (web)\n\n'
               '🎬 Supported Formats\n• MP4 (H.264, AAC), MOV\n\n'
               '📝 Captions (Tweet limit)\n• Standard User: 280 characters\n• Premium: 25,000 characters (for long posts)\n\n'
               '⚙️ Technical\n• Resolution: Up to 1920×1200 (web), 1280×720 (mobile)\n• Aspect ratios: 16:9, 9:16, 1:1';
      case 'threads':
        return '⏰ Duration\n• Up to 5 minutes\n\n'
               '💾 File Size\n• Under 5 GB\n\n'
               '🎬 Supported Formats\n• MP4, GIF\n\n'
               '📝 Description\n• Maximum 500 characters\n\n'
               '🖼️ Media\n• Up to 10 media per post\n• Linked to Instagram account';
      default:
        return 'Please check platform specifications for supported video formats.';
    }
  }



  // Metodo per chiudere tutti i pannelli tranne quello selezionato
  void _closeAllPanelsExcept(String targetPlatform) {
    setState(() {
      for (var platform in _expandedState.keys) {
        _expandedState[platform] = (platform == targetPlatform);
      }
    });
  }
  
  // Metodo per assicurarsi che il pannello espanso sia visibile
  void _posizionaTendinaNellaParteAlta(String platform) {
    if (_platformKeys.containsKey(platform)) {
      final platformKey = _platformKeys[platform];
      if (platformKey?.currentContext != null) {
        // Usa una breve pausa per permettere al widget di espandersi prima di scrollare
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            Scrollable.ensureVisible(
              platformKey!.currentContext!,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
        }
      });
    }
    }
  }
  
  // AnimatedRotation custom per sistemi che non supportano il widget nativo
  Widget CustomAnimatedRotation({
    required double turns,
    required Duration duration,
    required Widget child,
    Curve curve = Curves.easeInOut,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: turns),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Transform.rotate(
          angle: value * 2 * 3.14159265359, // Converte giri in radianti
          child: child,
        );
      },
      child: child,
    );
  }

  // Check if platform supports title field
  bool _platformSupportsTitle(String platform) {
    switch(platform) {
      case 'TikTok':
      case 'Instagram':
      case 'Facebook':
      case 'Twitter':
      case 'Threads':
        return false; // These platforms don't need a title
      case 'YouTube':
        return true; // YouTube requires a title
      default:
        return true; // By default, all other platforms support titles
    }
  }

  // Check if YouTube is selected
  bool _isYouTubeSelected() {
    return _selectedAccounts.containsKey('YouTube') && 
           _selectedAccounts['YouTube']!.isNotEmpty;
  }

  // Check if platform supports description field
  bool _platformSupportsDescription(String platform) {
    return true; // By default, all platforms support descriptions
  }

  // Check if platform supports scheduling
  bool _platformSupportsScheduling(String platform) {
    return true; // By default, all platforms support scheduling
  }

  // Get maximum characters for platform
  int _getMaxCharactersForPlatform(String platform) {
    // For Twitter, we need to check if any selected account is verified
    if (platform == 'Twitter') {
      final twitterAccounts = _selectedAccounts['Twitter'] ?? [];
      if (twitterAccounts.isNotEmpty) {
        // Check if any selected Twitter account is verified
        for (final accountId in twitterAccounts) {
          if (_isTwitterAccountVerified(accountId)) {
            return 25000; // Return 25,000 for verified accounts
          }
        }
      }
      return 280; // Default to 280 for unverified accounts
    }
    return _platformDescriptionLimits[platform] ?? 2200;
  }

  // Get maximum lines for description field based on platform
  int _getDescriptionMaxLines(String platform) {
    switch(platform) {
      case 'TikTok':
      case 'Instagram':
      case 'Facebook':
      case 'Twitter':
      case 'Threads':
        return 8; // Increase height by approximately 2cm
      default:
        return 5; // Default height for other platforms
    }
  }
  // Build action buttons for the final step
  Widget _buildActionButtons(ThemeData theme) {
    bool canProceed = _selectedAccounts.isNotEmpty && _videoFile != null;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _scheduledDateTime != null ? 'Schedule your post' : 'Ready to post?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 4),
          Text(
            _scheduledDateTime != null 
                ? 'Your post will be published at the scheduled time' 
                : 'Choose an option below to continue',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 16),
          
          // Only show "Upload Now" button if not coming from scheduled_posts_page
          if (_scheduledDateTime == null) ...[
            // Upload now button
            Container(
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
              child: ElevatedButton.icon(
                onPressed: canProceed ? () => _validateAndProceed(false) : null,
                icon: Icon(Icons.cloud_upload_outlined),
                label: Text('Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  minimumSize: Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
              ),
            ),
            SizedBox(height: 12),
          ],
          
          // Schedule post button - always shown, but with different styling if it's the only option
          OutlinedButton.icon(
            onPressed: canProceed ? 
              () {
                _validateAndProceed(true);
              } : null,
            icon: Icon(Icons.schedule),
            label: Text('Schedule Post'),
            style: _scheduledDateTime != null
                ? ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    minimumSize: Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  )
                : OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    minimumSize: Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: canProceed 
                            ? theme.colorScheme.primary.withOpacity(0.5)
                            : Colors.grey.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                  ),
          ),
          
          // Save as Draft button - only shown when NOT editing an existing draft AND not scheduling
          if (!_isEditingDraft && _scheduledDateTime == null) ...[
            SizedBox(height: 12),
            TextButton.icon(
              onPressed: canProceed ? _saveAsDraft : null,
              icon: Icon(Icons.save_outlined),
              label: Text('Save as Draft'),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.grey[300] : Colors.grey[700],
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                minimumSize: Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSocialPlatformsStep(ThemeData theme) {
    // Whether we have at least one platform selected
    bool hasSelectedPlatforms = _selectedAccounts.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Social Platforms',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Select the platforms where you want to share your content',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          if (!_isPremium) 
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.secondary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gli utenti non premium possono programmare post solo su YouTube',
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 24),
          
          // Select all accounts button
          _buildSelectAllRow(theme),
          
          SizedBox(height: 16),
          
          // Platform selection cards (temporarily hide TikTok)
          ..._socialAccounts.entries.where((entry) => entry.key != 'Twitter' && entry.key != 'TikTok').map((entry) {
            final platform = entry.key;
            final accounts = entry.value;
            final isDark = theme.brightness == Brightness.dark;
            
            // Ensure that we have a key for this platform
            if (!_platformKeys.containsKey(platform)) {
              _platformKeys[platform] = GlobalKey();
            }
            
            // Make sure we have an expanded state for this platform
            if (!_expandedState.containsKey(platform)) {
              _expandedState[platform] = false;
            }
            
            return Container(
              key: _platformKeys[platform],
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900]! : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    curve: Curves.fastOutSlowIn,
                    decoration: BoxDecoration(
                      color: isDark ? Color(0xFF121212) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ExpansionTile(
                      key: PageStorageKey<String>('expansion_${platform}_2'),
                      initiallyExpanded: _expandedState[platform] ?? false,
                      maintainState: true,
                      backgroundColor: Colors.transparent,
                      collapsedBackgroundColor: Colors.transparent,
                      onExpansionChanged: (isExpanded) {
                        // When expanded, close all other panels
                        if (isExpanded) {
                          // Close all panels first
                          _closeAllPanelsExcept(platform);
                          
                          // Position the dropdown in the visible area
                          _posizionaTendinaNellaParteAlta(platform);
                        } else {
                          // If this platform is being closed, update its state
                          setState(() {
                            _expandedState[platform] = false;
                          });
                        }
                      },
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.asset(
                          _platformLogos[platform] ?? '',
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                        ),
                      ),
                      title: Text(
                        platform,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Show selected accounts count badge
                          if (_selectedAccounts.containsKey(platform) && _selectedAccounts[platform]!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _selectedAccounts[platform]!.length.toString(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          // Icona con rotazione animata
                          CustomAnimatedRotation(
                            turns: _expandedState[platform] == true ? 0.5 : 0,
                            duration: Duration(milliseconds: 200),
                            child: Icon(Icons.keyboard_arrow_down),
                          ),
                        ],
                      ),
                      children: [
                        // Platform account selection section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Available accounts',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextButton.icon(
                                    icon: Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    label: Text(
                                      'Formats',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    onPressed: () {
                                      // Show platform info dialog
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          title: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.05),
                                                      blurRadius: 10,
                                                      spreadRadius: 1,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Image.asset(
                                                  _platformLogos[platform] ?? '',
                                                  width: 32,
                                                  height: 32,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                '$platform Info',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: double.maxFinite,
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.grey.shade100,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.03),
                                                      blurRadius: 10,
                                                      spreadRadius: 1,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: SingleChildScrollView(
                                                  child: Text(
                                                    _getPlatformInstructions(platform),
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      height: 1.5,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text(
                                                'Got it',
                                                style: TextStyle(
                                                  color: theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              
                              // Account items list
                              if (accounts.isEmpty)
                                Container(
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.account_circle_outlined,
                                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'No ${platform} accounts connected',
                                          style: TextStyle(
                                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          // Naviga direttamente alla pagina del social specifico
                                          _navigateToSocialPage('/${_getPlatformRouteName(platform)}');
                                        },
                                        child: Text('Connect'),
                                        style: TextButton.styleFrom(
                                          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                          foregroundColor: theme.colorScheme.primary,
                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ListView.builder(
                                  key: PageStorageKey<String>('accounts_list_$platform'),
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: accounts.length,
                                  itemBuilder: (context, index) {
                                    final rawAccount = accounts[index];
                                    final Map<String, dynamic> accountMap =
                                        rawAccount is Map ? Map<String, dynamic>.from(rawAccount as Map) : {
                                          'id': rawAccount?.toString() ?? ''
                                        };
                                    // Safe normalized fields
                                    final accountId = (accountMap['id'] ?? accountMap['channel_id'] ?? accountMap['user_id'] ?? accountMap['username'] ?? '').toString();
                                    final isSelected = _selectedAccounts[platform]?.contains(accountId) ?? false;
                                    final profileImageUrl = accountMap['profile_image_url'] as String?;
                                    final username = (accountMap['username'] ?? accountMap['display_name'] ?? '').toString();
                                    final followersCount = (accountMap['followers_count'] ?? accountMap['follower_count'] ?? accountMap['subscriber_count'] ?? '0').toString();
                                    final displayName = (accountMap['display_name'] ?? username).toString();
                                  
                                  return Column(
                                    children: [
                                      // Add divider between items (except the first one)
                                        if (index > 0)
                                        Divider(height: 1, indent: 72, endIndent: 16, color: Colors.grey.shade200),
                                        
                                      Container(
                                        margin: EdgeInsets.symmetric(vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          leading: _buildAccountProfileImage(
                                            profileImageUrl,
                                            username,
                                            theme
                                          ),
                                          title: Text(
                                            displayName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Only show username for non-TikTok accounts, since TikTok API doesn't allow it
                                              if (platform != 'TikTok')
                                                Text(
                                                  '@$username',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.people_outline,
                                                    size: 12,
                                                    color: Colors.grey[500],
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    '$followersCount followers',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                                ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Settings button for selected accounts
                                              if (isSelected)
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.settings,
                                                    color: theme.colorScheme.primary,
                                                    size: 20,
                                                  ),
                                                  onPressed: () {
                                                    _showAccountConfigBottomSheet(platform, accountId);
                                                  },
                                                  tooltip: 'Configure content',
                                                  padding: EdgeInsets.zero,
                                                  constraints: BoxConstraints(
                                                    minWidth: 36,
                                                    minHeight: 36,
                                                  ),
                                                ),
                                              Switch(
                                                value: isSelected,
                                                onChanged: (platform == 'YouTube' && _isImageFile)
                                                    ? null
                                                    : (value) => _toggleAccount(platform, accountId),
                                                activeColor: Color(0xFF667eea),
                                              ),
                                            ],
                                          ),
                                          onTap: () => _navigateToSocialAccountDetails(accountMap, platform),
                                          tileColor: isSelected ? theme.colorScheme.primary.withOpacity(0.05) : null,
                                          selectedTileColor: theme.colorScheme.primary.withOpacity(0.05),
                                        ),
                                      ),
                                      
                                        // Removed content type buttons for Instagram (now only shown in account settings)
                                    ],
                                  );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
          
          // Action buttons at the bottom
          SizedBox(height: 78), // Aumentato di 1 cm (38 pixel)
          _buildActionButtons(theme),
          
          // Padding finale della pagina
          SizedBox(height: 78), // Aggiunto 1 cm di padding finale
        ],
      ),
    );
  }

  Widget _buildPlatformCard({
    required String platform,
    required List<Map<String, dynamic>> accounts,
    required bool isExpanded,
    required ThemeData theme,
  }) {
    // Get platform specific color
    Color platformColor = _getPlatformColor(platform);
    
    // Get icon for the platform
    IconData platformIcon = _getPlatformIcon(platform);
    
    // Check if this platform has selected accounts
    final hasSelectedAccounts = _selectedAccounts.containsKey(platform) && 
                               _selectedAccounts[platform]!.isNotEmpty;
    
    // Determina se evidenziare la piattaforma (quando ha account selezionati)
    final bool shouldHighlight = hasSelectedAccounts;
    
    // Build selected accounts count text
    String selectedAccountsText = '';
    if (hasSelectedAccounts) {
      final selectedCount = _selectedAccounts[platform]?.length ?? 0;
      selectedAccountsText = 'Selected: $selectedCount ${selectedCount == 1 ? 'account' : 'accounts'}';
    }
    
    return Container(
      key: _platformKeys[platform],
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: shouldHighlight ? platformColor.withOpacity(0.5) : Colors.grey.withOpacity(0.2),
          width: shouldHighlight ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Platform header
          InkWell(
            onTap: () {
              // Ottimizzazione: aggiorna solo lo stato dell'espansione senza rebuild globale
              setState(() {
                _expandedState[platform] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    platformIcon,
                    color: platformColor,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          platform,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (hasSelectedAccounts) ...[
                          SizedBox(height: 4),
                          Text(
                            selectedAccountsText,
                            style: TextStyle(
                              color: platformColor.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          
          // Rest of the widget remains unchanged
        ],
      ),
    );
  }
  // Metodo per costruire la riga "Seleziona tutti gli account"
  Widget _buildSelectAllRow(ThemeData theme) {
    bool hasAccountsForAllPlatforms = true;
    int totalAccounts = 0;
    
    // Controlla se ci sono account disponibili per tutte le piattaforme
    for (var platform in _socialAccounts.keys) {
      if (_socialAccounts[platform]?.isEmpty ?? true) {
        hasAccountsForAllPlatforms = false;
        break;
      }
      totalAccounts += _socialAccounts[platform]?.length ?? 0;
    }
    
    // Controlla se tutti gli account disponibili sono selezionati
    bool allAccountsSelected = false;
    int selectedAccountsCount = 0;
    
    for (var platform in _selectedAccounts.keys) {
      selectedAccountsCount += _selectedAccounts[platform]?.length ?? 0;
    }
    
    allAccountsSelected = selectedAccountsCount == totalAccounts && selectedAccountsCount > 0;
    
    // Se non ci sono account disponibili per tutte le piattaforme, non mostrare il selettore
    if (!hasAccountsForAllPlatforms || totalAccounts == 0) {
      return SizedBox.shrink();
    }
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.surfaceVariant,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Select all accounts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Switch(
            value: allAccountsSelected,
            activeColor: Color(0xFF667eea),
            onChanged: (value) {
              setState(() {
                if (value) {
                  // Seleziona tutti gli account disponibili
                  _selectedAccounts.clear();
                  
                  for (var platform in _socialAccounts.keys) {
                    final accounts = _socialAccounts[platform];
                    if (accounts != null && accounts.isNotEmpty) {
                      _selectedAccounts[platform] = accounts
                          .map((account) => account['id'].toString())
                          .toList();
                    }
                  }
                } else {
                  // Deseleziona tutti gli account
                  _selectedAccounts.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  // Metodo per ottenere il colore specifico della piattaforma
  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return Colors.black;
      case 'youtube':
        return Colors.red;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue.shade800;
      case 'twitter':
        return Colors.blue;
      case 'threads':
        return Colors.black87;
      default:
        return Colors.grey;
    }
  }

  // Metodo per ottenere l'icona specifica della piattaforma
  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return _platformIcons['TikTok'] ?? Icons.music_note;
      case 'youtube':
        return _platformIcons['YouTube'] ?? Icons.play_arrow;
      case 'instagram':
        return _platformIcons['Instagram'] ?? Icons.camera_alt;
      case 'facebook':
        return _platformIcons['Facebook'] ?? Icons.facebook;
      case 'twitter':
        return _platformIcons['Twitter'] ?? Icons.chat;
      case 'threads':
        return _platformIcons['Threads'] ?? Icons.chat;
      default:
        return Icons.public;
    }
  }

  // Get color for progress bar based on percentage
  Color _getProgressColor(double percentage, ThemeData theme) {
    if (percentage < 0.7) {
      return theme.colorScheme.primary;
    } else if (percentage < 0.9) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  // Stop video before navigation
  void _stopVideoBeforeNavigation() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
    }
  }




  // Generate platform-specific description
  Future<void> _generatePlatformSpecificDescription(String platform, String prompt, Function(String) onComplete) async {
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a prompt for the description')),
      );
      return;
    }

    try {
      // Update UI to show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating description...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': 'Write a description for ${platform} based on this information: ${prompt}. '
                  'The response must be properly formatted and not exceed ${_platformChatGPTLimits[platform]} characters. '
                  'If the platform is Twitter, include relevant hashtags. '
                  'Do not use phrases with "discover", "explore", "join us" or similar. Use emojis in readable format.',
            }
          ],
          'max_tokens': _maxTokens,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String generatedText = data['choices'][0]['message']['content'];
        
        // Clean up any potential encoding issues
        generatedText = generatedText
            .replaceAll(RegExp(r'\\u[0-9a-fA-F]{4}'), '') // Remove broken unicode
            .replaceAll(RegExp(r'[^\x00-\x7F]+'), '') // Remove non-ASCII chars
            .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
            .trim();
      
      onComplete(generatedText);
      } else {
        throw Exception('Failed to generate description: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating description: ${e.toString()}')),
      );
    }
  }

  // Build platform descriptions for all selected accounts
  Map<String, Map<String, String>> _buildPlatformDescriptions() {
    final Map<String, Map<String, String>> descriptions = {};
    
    for (final platform in _selectedAccounts.keys) {
      // Create a map for this platform if it doesn't exist
      if (!descriptions.containsKey(platform)) {
        descriptions[platform] = {};
      }
      
      for (final accountId in _selectedAccounts[platform]!) {
        final accountKey = accountId;
        String? descToUse;
        // Check if we have account-specific content
        if (_accountSpecificContent != null) {
          final configKey = '${platform}_$accountId';
          if (_accountSpecificContent!.containsKey(configKey) && 
              !(_accountSpecificContent![configKey]?['useGlobalContent'] ?? true)) {
            // Use account-specific description (either manually entered or AI-generated)
            descToUse = _accountSpecificContent![configKey]?['description'];
          } else {
            // Use global description only if useGlobalContent is true
            if (_accountSpecificContent![configKey]?['useGlobalContent'] ?? true) {
              descToUse = _descriptionController.text;
            } else {
              // User has explicitly disabled global content, don't use it
              descToUse = null;
            }
          }
        } else {
          // Use global description as fallback only if no account-specific config exists
          descToUse = _descriptionController.text;
        }
        // Inserisci solo se non vuota
        if (descToUse != null && descToUse.trim().isNotEmpty) {
          descriptions[platform]![accountKey] = descToUse;
        } else {
          // Se vuota, assicurati che la chiave non esista
          descriptions[platform]!.remove(accountKey);
        }
        // Titolo (come prima)
        if (_accountSpecificContent != null) {
          final configKey = '${platform}_$accountId';
          if (_accountSpecificContent!.containsKey(configKey) && 
              _platformTitleControllers.containsKey(platform) && 
              _platformTitleControllers[platform]!.text.isNotEmpty) {
            descriptions[platform]!['${accountKey}_title'] = _platformTitleControllers[platform]!.text;
          } else if (_accountSpecificContent![configKey]?['useGlobalContent'] ?? true) {
            // Use global title only if useGlobalContent is true
            if (_titleController.text.isNotEmpty) {
              descriptions[platform]!['${accountKey}_title'] = _titleController.text;
            }
          }
          // If useGlobalContent is false, don't add any title
        } else if (_titleController.text.isNotEmpty) {
          descriptions[platform]!['${accountKey}_title'] = _titleController.text;
        }
      }
    }
    
    return descriptions;
  }

  String _getPlatformRouteName(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return 'tiktok';
      case 'youtube':
        return 'youtube';
      case 'instagram':
        return 'instagram';
      case 'facebook':
        return 'facebook';
      case 'twitter':
        return 'twitter';
      case 'threads':
        return 'threads';
      default:
        throw Exception('Unknown platform');
    }
  }

  // Add validation method for YouTube titles
  bool _validateYouTubeTitles() {
    // Check if YouTube accounts are selected
    if (_selectedAccounts.containsKey('YouTube') && _selectedAccounts['YouTube']!.isNotEmpty) {
      // For each YouTube account, check if title is provided
      for (final accountId in _selectedAccounts['YouTube']!) {
        final titleController = _platformTitleControllers['YouTube'];
        final globalTitle = _titleController.text.trim();
        
        // Check if there's a platform-specific title or global title
        if ((titleController == null || titleController.text.trim().isEmpty) && globalTitle.isEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  // Show YouTube title validation error
  void _showYouTubeTitleError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [

              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'YouTube title is required',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 3),
        elevation: 4,
      ),
    );
  }

  // Add method to get video duration
  Future<Duration?> _getVideoDuration(File videoFile) async {
    try {
      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      return duration;
    } catch (e) {
      print('Error getting video duration: $e');
      return null;
    }
  }

  // Add validation method for TikTok video length
  Future<bool> _validateTikTokVideoLength() async {
    // Check if TikTok accounts are selected
    if (_selectedAccounts.containsKey('TikTok') && _selectedAccounts['TikTok']!.isNotEmpty) {
      if (_videoFile != null && !_isImageFile) {
        final duration = await _getVideoDuration(_videoFile!);
        if (duration != null) {
          // TikTok requirements: minimum 3 seconds, maximum 10 minutes
          final minDuration = Duration(seconds: 3);
          final maxDuration = Duration(minutes: 10);
          
          if (duration < minDuration || duration > maxDuration) {
            return false;
          }
        }
      }
    }
    return true;
  }

  // Show TikTok video length validation error
  void _showTikTokVideoLengthError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TikTok video must be between 3 seconds and 10 minutes',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 4),
        elevation: 4,
      ),
    );
  }

  // Add validation method for TikTok privacy settings
  List<String> _getTikTokAccountsWithoutPrivacy() {
    List<String> accountsWithoutPrivacy = [];
    
    // Check if TikTok accounts are selected
    if (_selectedAccounts.containsKey('TikTok') && _selectedAccounts['TikTok']!.isNotEmpty) {
      for (final accountId in _selectedAccounts['TikTok']!) {
        // Check if privacy level is set for this account
        if (_tiktokOptions[accountId]?['privacy_level'] == null) {
          // Get account display name
          final account = _socialAccounts['TikTok']?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
          final displayName = account?['display_name'] ?? account?['username'] ?? accountId;
          accountsWithoutPrivacy.add(displayName);
        }
      }
    }
    return accountsWithoutPrivacy;
  }

  // Add validation method for TikTok privacy settings
  bool _validateTikTokPrivacySettings() {
    return _getTikTokAccountsWithoutPrivacy().isEmpty;
  }

  // Show TikTok privacy validation error
  void _showTikTokPrivacyError() {
    final accountsWithoutPrivacy = _getTikTokAccountsWithoutPrivacy();
    final accountNames = accountsWithoutPrivacy.join(', ');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Please select privacy level for TikTok account${accountsWithoutPrivacy.length > 1 ? 's' : ''}: $accountNames',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 6),
        elevation: 4,
      ),
    );
  }

  // Get TikTok compliance message based on selected commercial content options
  Widget _getTikTokComplianceMessage(String accountId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.blue[200] : Colors.blue[700];
    
    if (!_tiktokOptions.containsKey(accountId)) {
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontStyle: FontStyle.italic,
          ),
          children: [
            TextSpan(text: 'By publishing, you accept the '),
            TextSpan(
              text: 'TikTok Music Usage Confirmation',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokMusicPolicy(),
            ),
          ],
        ),
      );
    }
    
    final options = _tiktokOptions[accountId]!;
    final ownBrand = options['own_brand'] ?? false;
    final brandedContent = options['branded_content'] ?? false;
    
    if (ownBrand && brandedContent) {
      // Both options selected
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontStyle: FontStyle.italic,
          ),
          children: [
            TextSpan(text: 'By publishing, you accept the '),
            TextSpan(
              text: 'Branded Content Policy',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokBrandedContentPolicy(),
            ),
            TextSpan(text: ' and the '),
            TextSpan(
              text: 'TikTok Music Usage Confirmation',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokMusicPolicy(),
            ),
          ],
        ),
      );
    } else if (brandedContent) {
      // Only branded content selected
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontStyle: FontStyle.italic,
          ),
          children: [
            TextSpan(text: 'By publishing, you accept the '),
            TextSpan(
              text: 'Branded Content Policy',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokBrandedContentPolicy(),
            ),
            TextSpan(text: ' and the '),
            TextSpan(
              text: 'TikTok Music Usage Confirmation',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokMusicPolicy(),
            ),
          ],
        ),
      );
    } else if (ownBrand) {
      // Only own brand selected
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontStyle: FontStyle.italic,
          ),
          children: [
            TextSpan(text: 'By publishing, you accept the '),
            TextSpan(
              text: 'TikTok Music Usage Confirmation',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokMusicPolicy(),
            ),
          ],
        ),
      );
    } else {
      // No specific options selected (shouldn't happen if commercial_content is true)
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontStyle: FontStyle.italic,
          ),
          children: [
            TextSpan(text: 'By publishing, you accept the '),
            TextSpan(
              text: 'TikTok Music Usage Confirmation',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchTikTokMusicPolicy(),
            ),
          ],
        ),
      );
    }
  }

  // Launch TikTok Music Usage Confirmation policy
  void _launchTikTokMusicPolicy() async {
    const url = 'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      print('Error launching TikTok music policy: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossibile aprire la pagina della politica musicale di TikTok'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Launch TikTok Branded Content Policy
  void _launchTikTokBrandedContentPolicy() async {
    const url = 'https://www.tiktok.com/legal/page/global/bc-policy/en';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      print('Error launching TikTok branded content policy: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossibile aprire la pagina della politica sui contenuti di marca di TikTok'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Method to get description for confirmation page based on user preferences
  String _getDescriptionForConfirmation() {
    // Check if any account has disabled global content
    bool shouldUseGlobalDescription = true;
    
    for (var platform in _selectedAccounts.keys) {
      for (var accountId in _selectedAccounts[platform]!) {
        if (_accountSpecificContent != null) {
          final configKey = '${platform}_$accountId';
          if (_accountSpecificContent!.containsKey(configKey) && 
              !(_accountSpecificContent![configKey]?['useGlobalContent'] ?? true)) {
            shouldUseGlobalDescription = false;
            break;
          }
        }
      }
      if (!shouldUseGlobalDescription) break;
    }
    
    // Return global description only if user hasn't disabled it and it's not empty
    if (shouldUseGlobalDescription && _descriptionController.text.isNotEmpty) {
      return _descriptionController.text;
    }
    
    // Return empty string if user has disabled global content or description is empty
    return '';
  }

  // Function to get video duration in seconds and minutes for database
  Future<Map<String, int>?> _getVideoDurationForDatabase() async {
    if (_isImageFile || _videoFile == null) {
      return null; // Non serve per le immagini o se non c'è un file video
    }
    
    try {
      final VideoPlayerController controller = VideoPlayerController.file(_videoFile!);
      await controller.initialize();
      
      final Duration duration = controller.value.duration;
      final int totalSeconds = duration.inSeconds;
      final int minutes = totalSeconds ~/ 60;
      final int seconds = totalSeconds % 60;
      
      await controller.dispose();
      
      return {
        'total_seconds': totalSeconds,
        'minutes': minutes,
        'seconds': seconds,
      };
    } catch (e) {
      print('Error getting video duration: $e');
      return null;
    }
  }

  // Top bar functionality methods
  void _setupNotificationsListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final ref = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
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
        _updateAppBadge();
      });
      
      // Listener per notifiche commenti
      final commentsRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('notificationcomment');
      _commentsStream = commentsRef.onValue;
      _commentsStream!.listen((event) {
        int count = 0;
        if (event.snapshot.value != null && event.snapshot.value is Map) {
          final data = event.snapshot.value as Map;
          for (final c in data.values) {
            if (c is Map && (c['read'] == null || c['read'] == false)) {
              count++;
            }
          }
        }
        setState(() {
          _unreadComments = count;
        });
        _updateAppBadge();
      });
      
      // Listener per notifiche stelle
      final starsRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('notificationstars');
      _starsStream = starsRef.onValue;
      _starsStream!.listen((event) {
        int count = 0;
        if (event.snapshot.value != null && event.snapshot.value is Map) {
          final data = event.snapshot.value as Map;
          for (final s in data.values) {
            if (s is Map && (s['read'] == null || s['read'] == false)) {
              count++;
            }
          }
        }
        setState(() {
          _unreadStars = count;
        });
        _updateAppBadge();
      });
      
      // Listener per l'immagine profilo
      final profileRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
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

  /// Aggiorna il badge dell'icona dell'app con il numero totale di notifiche non lette
  void _updateAppBadge() {
    try {
      final totalUnread = _unreadNotifications + _unreadComments + _unreadStars;
      if (totalUnread > 0) {
        FlutterAppBadger.updateBadgeCount(totalUnread);
      } else {
        FlutterAppBadger.removeBadge();
      }
    } catch (e) {
      print('Error updating app badge: $e');
    }
  }

  /// Carica l'immagine profilo dal database Firebase
  Future<void> _loadProfileImage() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
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

  Widget _buildDefaultProfileImage(ThemeData theme) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C63FF),
            const Color(0xFF8B7CF6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  Widget _buildTopBar() {
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
                        'assets/onboarding/circleICON.png',
                        width: 36,
                        height: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                      'Fluzar',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        fontFamily: 'Ethnocentric',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // rimosso: icona notifiche dalla top bar dell'upload
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
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  // Pulsante immagine profilo
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

  /// Carica un video da un URL e lo salva come file temporaneo
  Future<void> _loadVideoFromUrl(String url) async {
    try {
      setState(() {
        _showCheckmark = false;
      });

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Text('Downloading video from URL...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 30), // Long duration for download
        ),
      );

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      // Download the video
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        // Write the video data to file
        await file.writeAsBytes(response.bodyBytes);

        // Determine if it's an image based on content type or file extension
        bool isImage = false;
        final contentType = response.headers['content-type'];
        if (contentType != null) {
          isImage = contentType.startsWith('image/');
        } else {
          // Fallback to URL extension check
          isImage = url.toLowerCase().contains('.jpg') || 
                   url.toLowerCase().contains('.jpeg') || 
                   url.toLowerCase().contains('.png');
        }

        setState(() {
          _videoFile = file;
          _showCheckmark = true;
          _isImageFile = isImage;
          _isVideoFromUrl = true; // Mark that this video was loaded from URL
        });

        // Initialize video player if it's a video
        if (!_isImageFile) {
          _initializeVideoPlayer(file);
        }

        // Hide loading indicator
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video downloaded successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Passa al secondo step dopo un breve ritardo
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _goToNextStep();
          }
        });
      } else {
        throw Exception('Failed to download video: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading video from URL: $e');
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading video: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}