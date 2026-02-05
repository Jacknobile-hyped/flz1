import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../providers/theme_provider.dart';
import './post_scheduler_page.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import './credits_page.dart';
import './upgrade_premium_page.dart';
import './upgrade_premium_ios_page.dart';

class SchedulePostPage extends StatefulWidget {
  final File? videoFile; // Mantenuto per retrocompatibilità, ma deprecato
  final List<File>? videoFiles; // Nuova lista di file
  final List<bool>? isImageFiles; // Nuova lista di flag per immagini
  final String title;
  final String description;
  final Map<String, List<String>> selectedAccounts;
  final Map<String, List<Map<String, dynamic>>> socialAccounts;
  final DateTime scheduledDateTime;
  final VoidCallback onConfirm;
  final Map<String, Map<String, String>> platformDescriptions;
  final String? cloudflareUrl;
  final bool isImageFile; // Mantenuto per retrocompatibilità
  final Map<String, String> instagramContentType;
  final bool isPremium;
  final String? draftId; // Add draftId
  final File? youtubeThumbnailFile; // Per la miniatura personalizzata di YouTube
  final Map<String, Map<String, dynamic>>? youtubeOptions; // Opzioni YouTube per ogni account

  const SchedulePostPage({
    super.key,
    this.videoFile, // Opzionale per retrocompatibilità
    this.videoFiles, // Nuova lista di file
    this.isImageFiles, // Nuova lista di flag
    required this.title,
    required this.description,
    required this.selectedAccounts,
    required this.socialAccounts,
    required this.scheduledDateTime,
    required this.onConfirm,
    this.platformDescriptions = const {},
    this.cloudflareUrl,
    this.isImageFile = false,
    this.instagramContentType = const {},
    this.isPremium = false,
    this.draftId, // Add draftId
    this.youtubeThumbnailFile, // Per la miniatura personalizzata di YouTube
    this.youtubeOptions, // Opzioni YouTube per ogni account
  });

  @override
  State<SchedulePostPage> createState() => _SchedulePostPageState();
}

class _SchedulePostPageState extends State<SchedulePostPage> {
  bool _isUploading = false;
  bool _isDisposed = false; // Track widget disposal
  bool _isSaving = false;
  
  // Firebase database reference
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  // Video player controller
  VideoPlayerController? _videoPlayerController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;
  
  // Variables for fullscreen mode
  bool _isFullScreen = false;
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  bool _showControls = true;
  Timer? _controlsHideTimer; // Timer per nascondere i controlli automaticamente
  
  // Thumbnail path
  String? _thumbnailPath;
  
  // Variabili per gestire più media
  List<File> _mediaFiles = [];
  List<bool> _isImageFiles = [];
  PageController? _carouselController;
  int _currentCarouselIndex = 0;
  File? _currentMediaFile;
  bool _currentIsImage = false;
  
  // Platform logos for UI display
  final Map<String, String> _platformLogos = {
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'Instagram': 'assets/loghi/logo_insta.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
  };


  
  // Variabili per gestione crediti utenti non premium (solo per YouTube)
  int _userCredits = 0;
  bool _isLoadingCredits = true;
  bool _showCreditsWarning = false;
  
  // Variabili per gestione disclaimer (mostrato solo al primo video)
  bool _showDisclaimer = false;
  bool _isCheckingVideos = true;

  @override
  void initState() {
    super.initState();
    
    // Inizializza le liste di media
    if (widget.videoFiles != null && widget.videoFiles!.isNotEmpty) {
      _mediaFiles = widget.videoFiles!;
      _isImageFiles = widget.isImageFiles ?? List.generate(_mediaFiles.length, (index) => false);
      
      // Inizializza il carosello se ci sono più file
      if (_mediaFiles.length > 1) {
        _carouselController = PageController(initialPage: 0);
      }
      
      // Imposta il media corrente
      _currentCarouselIndex = 0;
      _currentMediaFile = _mediaFiles[0];
      _currentIsImage = _isImageFiles[0];
    } else if (widget.videoFile != null) {
      // Retrocompatibilità: usa il singolo file
      _mediaFiles = [widget.videoFile!];
      _isImageFiles = [widget.isImageFile];
      _currentMediaFile = widget.videoFile!;
      _currentIsImage = widget.isImageFile;
    }
    
    if (widget.youtubeThumbnailFile != null) {
      print('***YOUTUBE THUMBNAIL*** schedule_post_page.dart: widget.youtubeThumbnailFile path: \'${widget.youtubeThumbnailFile!.path}\'' );
    } else {
      print('***YOUTUBE THUMBNAIL*** schedule_post_page.dart: widget.youtubeThumbnailFile is NULL');
    }
    
    // Initialize video player if not an image but with a delay
    if (_currentMediaFile != null && !_currentIsImage) {
      // Delay initialization to ensure widget is fully built
      Future.delayed(const Duration(milliseconds: 700), () { // Increased delay
        if (!_isDisposed) {
          // First check if the file is too large before trying anything
          _currentMediaFile!.length().then((fileSize) {
            final fileSizeMB = fileSize / (1024 * 1024);
            
            if (fileSizeMB > 200) {
              // For very large files, just set a flag that it's too large
              print('File too large (${fileSizeMB.toStringAsFixed(2)} MB), using static representation only');
              // Still generate a thumbnail but skip video player initialization
              _generateThumbnail();
            } else {
              // Generate thumbnail first
              _generateThumbnail();
              // Inizializza automaticamente il video player
              _initializeVideoPlayer();
            }
          }).catchError((error) {
            print('Error checking file size: $error');
            // Generate thumbnail anyway in case of error
            _generateThumbnail();
            // Prova comunque a inizializzare il video player
            _initializeVideoPlayer();
          });
        }
      });
    } else if (_currentMediaFile != null && _currentIsImage) {
      // For image files, just log the file size for debugging
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_isDisposed) {
          _currentMediaFile!.length().then((fileSize) {
            final fileSizeMB = fileSize / (1024 * 1024);
            print('Image file size: ${fileSizeMB.toStringAsFixed(2)} MB');
          }).catchError((error) {
            print('Error checking image file size: $error');
          });
        }
      });
    }
    
    // Start timer for video position updates
    _startPositionUpdateTimer();
    
    // Carica i crediti dell'utente (solo per utenti non premium)
    if (!widget.isPremium) {
      _loadUserCredits();
    } else {
      setState(() {
        _isLoadingCredits = false;
      });
    }
    
    // Controlla se è il primo video per mostrare il disclaimer
    _checkIfFirstVideo();
  }
  
  void _startPositionUpdateTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_videoPlayerController != null && 
          _videoPlayerController!.value.isInitialized && 
          !_isDisposed && mounted) {
        setState(() {
          _currentPosition = _videoPlayerController!.value.position;
          _videoDuration = _videoPlayerController!.value.duration;
        });
      }
    });
  }
  
  // Metodo per caricare i crediti dell'utente
  Future<void> _loadUserCredits() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      
      final userSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .get();
      
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        
        setState(() {
          _userCredits = (userData['credits'] as int?) ?? 0;
          _isLoadingCredits = false;
        });
      } else {
        setState(() {
          _isLoadingCredits = false;
        });
      }
    } catch (e) {
      print('Error loading user credits: $e');
      setState(() {
        _isLoadingCredits = false;
      });
    }
  }
  
  // Metodo per controllare se è il primo video (mostra disclaimer solo se la cartella videos non esiste o è vuota)
  Future<void> _checkIfFirstVideo() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _isCheckingVideos = false;
          _showDisclaimer = false;
        });
        return;
      }
      
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .get();
      
      if (!mounted) return;
      
      // Mostra il disclaimer solo se la cartella videos non esiste o è vuota
      bool shouldShowDisclaimer = false;
      if (!videosSnapshot.exists) {
        // La cartella non esiste
        shouldShowDisclaimer = true;
      } else {
        // La cartella esiste, controlla se è vuota
        final videos = videosSnapshot.value;
        if (videos == null || (videos is Map && videos.isEmpty)) {
          shouldShowDisclaimer = true;
        }
      }
      
      setState(() {
        _showDisclaimer = shouldShowDisclaimer;
        _isCheckingVideos = false;
      });
    } catch (e) {
      print('Error checking if first video: $e');
      // In caso di errore, non mostrare il disclaimer per sicurezza
      if (mounted) {
        setState(() {
          _showDisclaimer = false;
          _isCheckingVideos = false;
        });
      }
    }
  }
  
  // Metodo per calcolare i crediti necessari per i media
  int _calculateRequiredCredits() {
    try {
      int totalCredits = 0;
      for (var file in _mediaFiles) {
        final fileSize = file.lengthSync();
        final fileSizeMB = fileSize / (1024 * 1024);
        totalCredits += (fileSizeMB * 0.4).ceil();
      }
      return totalCredits > 0 ? totalCredits : 1;
    } catch (e) {
      print('Error calculating required credits: $e');
      return 1; // Default a 1 credito in caso di errore
    }
  }
  
  // Metodo per verificare se l'utente ha crediti sufficienti
  bool _hasSufficientCreditsForYouTube() {
    if (widget.isPremium) return true;
    
    // Per utenti non premium, controlla sempre i crediti se ci sono social media selezionati
    final hasAnySocialSelected = widget.selectedAccounts.values.any((accounts) => accounts.isNotEmpty);
    
    if (!hasAnySocialSelected) return true; // Se non ci sono social selezionati, non serve controllare i crediti
    
    final requiredCredits = _calculateRequiredCredits();
    
    // Debug log
    print('DEBUG CREDITS: isPremium=${widget.isPremium}, userCredits=$_userCredits, requiredCredits=$requiredCredits, hasAnySocial=$hasAnySocialSelected');
    print('DEBUG CREDITS: selectedAccounts=${widget.selectedAccounts}');
    
    return _userCredits >= requiredCredits;
  }
  
  // Metodo per mostrare l'avviso crediti insufficienti
  void _showInsufficientCreditsWarning() {
    print('DEBUG: Showing insufficient credits warning');
    setState(() {
      _showCreditsWarning = true;
    });
  }
  
  // Widget per l'avviso crediti insufficienti (stile video_stats_page modal)
  Widget _buildCreditsWarning() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final requiredCredits = _calculateRequiredCredits();
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Handle
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          // Title centered
          Text(
            'Insufficient Credits',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          // Description
          Text(
            'You\'ve run out of credits for video scheduling. Earn more or upgrade to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[700],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          // CTA buttons with 135° gradient
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreditsPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Get Credits',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Platform.isIOS
                              ? const UpgradePremiumIOSPage(suppressExtraPadding: true)
                              : const UpgradePremiumPage(suppressExtraPadding: true),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      _showControls = true; // Show controls when mode changes
    });
    
    // Non forzare la riproduzione del video quando si cambia modalità
    // Mantieni lo stato attuale di play/pause
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
  
  void _toggleVideoPlayback() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      if (_videoPlayerController!.value.isPlaying) {
        _pauseVideo();
      } else {
        _playVideo();
      }
    }
  }
  
  Future<void> _initializeVideoPlayer() async {
    // Dispose any existing controller first
    _disposeVideoController();
    
    if (_currentMediaFile == null || _currentIsImage) return;
    
    try {
      // Check file size before processing to avoid memory issues
      final fileSize = await _currentMediaFile!.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      print('Video file size: ${fileSizeMB.toStringAsFixed(2)} MB');
      
      // For very large files, don't try to initialize the player
      if (fileSizeMB > 100) { // Reduced from 150
        print('Video file too large to preview (${fileSizeMB.toStringAsFixed(2)} MB), skipping player initialization');
        return;
      }
      
      // Force a small delay before creating controller to allow memory cleanup
      await Future.delayed(const Duration(milliseconds: 100));
      
    _videoPlayerController = VideoPlayerController.file(_currentMediaFile!);
      _videoPlayerController!.setVolume(0.0); // Mute video to save resources
      _videoPlayerController!.setLooping(false); // Don't loop to save memory
      
      // Use a shorter timeout to avoid hanging
      await _videoPlayerController!.initialize().timeout(
        const Duration(seconds: 6), // Reduced from 8
        onTimeout: () {
          print('Video initialization timed out');
          _disposeVideoController(); // Make sure to dispose on timeout
          return;
        }
      ).then((_) {
        if (!mounted || _isDisposed) {
          _disposeVideoController();
          return;
        }
        
      setState(() {
        _isVideoInitialized = true;
      });
      }).catchError((error) {
        print('Error initializing video player: $error');
        _disposeVideoController();
      });
    } catch (e) {
      print('Exception during video controller creation: $e');
      _disposeVideoController();
    }
  }
  
  // Method to build video player maintaining correct aspect ratio
  Widget _buildVideoPlayer(VideoPlayerController controller) {
    // Check if video is horizontal (aspect ratio > 1)
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
  
  void _playVideo() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        !_isDisposed) {
      try {
        // If the video is too large, avoid playing it
        if (_currentMediaFile == null) return;
        _currentMediaFile!.length().then((fileSize) {
          final fileSizeMB = fileSize / (1024 * 1024);
          if (fileSizeMB > 120) { // Increased to 120MB to allow more videos
            // Just show a toast/snackbar instead of playing
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Video troppo grande per la riproduzione in anteprima'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
          
          // Safe to play smaller videos
          _videoPlayerController!.play();
          if (mounted) {
            setState(() {
              _isVideoPlaying = true;
              _showControls = true;
            });
            
            // Nascondi i controlli automaticamente dopo 3 secondi
            _controlsHideTimer?.cancel();
            _controlsHideTimer = Timer(Duration(seconds: 3), () {
              if (mounted && _videoPlayerController?.value.isPlaying == true) {
                setState(() {
                  _showControls = false;
                });
              }
            });
          }
        }).catchError((error) {
          print('Error checking file size for playback: $error');
        });
      } catch (e) {
        print('Error during video play: $e');
      }
    } else if (!_isVideoInitialized && !_isDisposed) {
      // If video is not initialized, try to initialize it now
      _initializeVideoPlayer().then((_) {
        if (_videoPlayerController != null && 
            _videoPlayerController!.value.isInitialized && 
            !_isDisposed && mounted) {
          setState(() {
            _isVideoPlaying = true;
            _showControls = true;
          });
          _videoPlayerController!.play();
          
          // Nascondi i controlli automaticamente dopo 3 secondi
          _controlsHideTimer?.cancel();
          _controlsHideTimer = Timer(Duration(seconds: 3), () {
            if (mounted && _videoPlayerController?.value.isPlaying == true) {
              setState(() {
                _showControls = false;
              });
            }
          });
        }
      });
    }
  }
  
  void _pauseVideo() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        !_isDisposed) {
      _videoPlayerController!.pause();
      setState(() {
        _isVideoPlaying = false;
        _showControls = true; // Mostra i controlli quando il video è in pausa
      });
      
      // Cancella il timer di auto-hide quando il video è in pausa
      _controlsHideTimer?.cancel();
    }
  }
  
  // New function to pause video without calling setState
  void _pauseVideoWithoutSetState() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        !_isDisposed) {
      _videoPlayerController!.pause();
      _isVideoPlaying = false;
    }
  }
  
  void _disposeVideoController() {
    if (_videoPlayerController != null) {
      _videoPlayerController!.pause();
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
      _isVideoInitialized = false;
      _isVideoPlaying = false;
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _positionUpdateTimer?.cancel();
    _controlsHideTimer?.cancel(); // Cancella il timer per i controlli
    _carouselController?.dispose();
    if (_videoPlayerController != null) {
      _videoPlayerController!.pause();
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
      _isVideoInitialized = false;
      _isVideoPlaying = false;
    }
    
    // Clean up any temp files if needed
    _cleanupTempFiles();
    
    super.dispose();
  }

  // Add a cleanup method to remove temporary files
  Future<void> _cleanupTempFiles() async {
    try {
      if (_thumbnailPath != null) {
        final thumbnailFile = File(_thumbnailPath!);
        if (await thumbnailFile.exists()) {
          // Keep for now as we might need it later
          print('Kept thumbnail file for later use');
        }
      }
    } catch (e) {
      print('Error cleaning up temp files: $e');
    }
  }

  @override
  void deactivate() {
    // Pause video when the page is no longer visible
    _pauseVideoWithoutSetState();
    super.deactivate();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Manage video playback based on app lifecycle
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pauseVideoWithoutSetState();
    }
  }

  Future<void> _saveScheduledPost() async {
    if (_isSaving) return;
    
    // Verifica che la data selezionata sia almeno 15 minuti nel futuro
    final now = DateTime.now();
    if (widget.scheduledDateTime.isBefore(now.add(const Duration(minutes: 15)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select a date and time at least 15 minutes in the future',
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
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
      return;
    }
    
    // Controlla se l'utente ha crediti sufficienti per YouTube (solo per utenti non premium)
    print('DEBUG: Checking credits before scheduling. isPremium=${widget.isPremium}, isLoadingCredits=$_isLoadingCredits');
    if (!widget.isPremium && !_isLoadingCredits) {
      final hasSufficientCredits = _hasSufficientCreditsForYouTube();
      print('DEBUG: Has sufficient credits: $hasSufficientCredits');
      if (!hasSufficientCredits) {
        print('DEBUG: Credits insufficient, showing warning');
        _showInsufficientCreditsWarning();
        return;
      }
    }
    
    // Debug per verificare lo stato premium
    print('isPremium status: ${widget.isPremium}');
    
    // Verifica premium status per lo scheduling
    bool isPremiumUser = widget.isPremium;
    
    // Verifica aggiuntiva del database in caso di problemi
    if (!isPremiumUser) {
      // Verifica diretta nel database Firebase
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          final userPremiumSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(currentUser.uid)
              .child('isPremium')
              .get();
              
          if (userPremiumSnapshot.exists) {
            isPremiumUser = userPremiumSnapshot.value as bool? ?? false;
            print('Premium status from database: $isPremiumUser');
          }
        }
      } catch (e) {
        print('Error checking premium status: $e');
      }
    }
    
    // Se non è premium, verifica piattaforme selezionate
    // if (!isPremiumUser) {
    //   // Per utenti non premium, verifica che ci sia solo YouTube selezionato
    //   bool hasNonYouTubeAccounts = false;
    //   
    //   for (var platform in widget.selectedAccounts.keys) {
    //     if (platform != 'YouTube' && widget.selectedAccounts[platform]!.isNotEmpty) {
    //       hasNonYouTubeAccounts = true;
    //       break;
    //     }
    //   }
    //   
    //   if (hasNonYouTubeAccounts) {
    //     // Mostra la bottom sheet di premium subscription
    //     _showPremiumSubscriptionBottomSheet();
    //     return;
    //   }
    // }
    // else {
    //   print('Utente premium: procedendo con lo scheduling multi-piattaforma');
    // }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Get the current user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // Generate and upload thumbnail if needed
      String? thumbnailUrl;
      if (!_currentIsImage && _thumbnailPath == null) {
        await _generateThumbnail();
      }
      
      // --- COSTRUZIONE SOCIALACCOUNTS COMPLETA ---
      // Ricostruisco la mappa socialAccounts per includere SOLO i dati degli account selezionati, ma con tutti i dettagli
      Map<String, List<Map<String, dynamic>>> fullSocialAccounts = {};
      for (final platform in widget.selectedAccounts.keys) {
        // Recupera tutti gli account disponibili per questa piattaforma
        final allAccounts = widget.socialAccounts[platform] ?? [];
        // Filtra solo quelli selezionati, ma includi tutti i dettagli
        final selectedIds = widget.selectedAccounts[platform] ?? [];
        final selectedAccounts = allAccounts.where((acc) => selectedIds.contains(acc['id'])).toList();
        fullSocialAccounts[platform] = selectedAccounts;
      }

      // Instead of processing the scheduling here, navigate to the PostSchedulerPage
      if (currentUser != null) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
          
          // Navigate to PostSchedulerPage with all required data
          // Determine the primary platform to schedule for
          String primaryPlatform = 'Twitter'; // Default fallback
          
          // Find the first platform with selected accounts
          for (var platform in widget.selectedAccounts.keys) {
            if (widget.selectedAccounts[platform]!.isNotEmpty) {
              primaryPlatform = platform;
              break;
            }
          }
          
          // --- LOG DI DEBUG PRIMA DELLA NAVIGAZIONE ---
          print('DEBUG SCHEDULE_POST_PAGE: selectedAccounts = ' + jsonEncode(widget.selectedAccounts));
          print('DEBUG SCHEDULE_POST_PAGE: fullSocialAccounts = ' + jsonEncode(fullSocialAccounts));
          print('DEBUG SCHEDULE_POST_PAGE: primaryPlatform = ' + primaryPlatform);
          // --- FINE LOG ---
          
          // Usa il media corrente (o il primo) come file principale
          final File primaryFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
          final bool primaryIsImage = _currentIsImage;
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostSchedulerPage(
                videoFile: primaryFile,
                // Passa tutti i media per supportare il carosello / multi-media
                mediaFiles: _mediaFiles.isNotEmpty ? List<File>.from(_mediaFiles) : null,
                isImageFiles: _isImageFiles.isNotEmpty ? List<bool>.from(_isImageFiles) : null,
                title: widget.title,
                description: widget.description,
                selectedAccounts: widget.selectedAccounts,
                socialAccounts: fullSocialAccounts,
                scheduledDateTime: widget.scheduledDateTime,
                platformDescriptions: widget.platformDescriptions,
                cloudflareUrl: widget.cloudflareUrl,
                isPremium: widget.isPremium, // Passa lo stato premium alla pagina di scheduling
                platform: primaryPlatform, // Add the required platform parameter
                onSchedulingComplete: () {
                  // This will be called when scheduling is complete
                  widget.onConfirm();
                },
                draftId: widget.draftId, // Add draftId
                youtubeThumbnailFile: widget.youtubeThumbnailFile, // Passa la thumbnail YouTube
                youtubeOptions: widget.youtubeOptions, // Passa le opzioni YouTube
              ),
            ),
          ).then((result) {
            // If scheduling was successful and we have a result, return to main page
            if (result == true) {
              Navigator.popUntil(context, (route) => route.isFirst);
            }
          });
        }
      }
    } catch (e) {
      print('Error scheduling post: $e');
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nella programmazione: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      
      // Reset saving state
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  
  // Mostra la bottom sheet di premium subscription
  // void _showPremiumSubscriptionBottomSheet() {
  //   final theme = Theme.of(context);
  //   showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true,
  //     backgroundColor: Colors.transparent,
  //     builder: (BuildContext context) {
  //       return Container(
  //         height: MediaQuery.of(context).size.height * 0.85,
  //         decoration: BoxDecoration(
  //           gradient: LinearGradient(
  //             begin: Alignment.topRight,
  //             end: Alignment.bottomLeft,
  //             colors: [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
  //           ),
  //           borderRadius: BorderRadius.only(
  //             topLeft: Radius.circular(28),
  //             topRight: Radius.circular(28),
  //           ),
  //           boxShadow: [
  //             BoxShadow(
  //               color: Colors.black.withOpacity(0.15),
  //               blurRadius: 15,
  //               offset: Offset(0, -3),
  //             ),
  //           ],
  //         ),
  //         child: SingleChildScrollView(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.center,
  //             children: [
  //               // Handle bar
  //               Container(
  //                 width: 50,
  //                 height: 5,
  //                 margin: EdgeInsets.only(top: 12, bottom: 20),
  //                 decoration: BoxDecoration(
  //                   color: Colors.white.withOpacity(0.3),
  //                   borderRadius: BorderRadius.circular(5),
  //                 ),
  //               ),
  //               
  //               // Premium icon
  //               Container(
  //                 width: 80,
  //                 height: 80,
  //                 decoration: BoxDecoration(
  //                   color: Colors.white.withOpacity(0.2),
  //                   shape: BoxShape.circle,
  //                 ),
  //                 child: Icon(
  //                   Icons.workspace_premium,
  //                   size: 40,
  //                   color: Colors.white,
  //                 ),
  //               ),
  //               
  //               SizedBox(height: 24),
  //               
  //               // Title
  //               Padding(
  //                 padding: const EdgeInsets.symmetric(horizontal: 24),
  //                 child: Text(
  //                   'Unlock the full potential',
  //                   style: TextStyle(
  //                     fontSize: 24,
  //                     fontWeight: FontWeight.bold,
  //                     color: Colors.white,
  //                     shadows: [
  //                       Shadow(
  //                         color: Colors.black.withOpacity(0.3),
  //                         offset: const Offset(0, 2),
  //                         blurRadius: 4,
  //                       ),
  //                     ],
  //                   ),
  //                   textAlign: TextAlign.center,
  //                 ),
  //               ),
  //               
  //               SizedBox(height: 12),
  //               
  //               // Subtitle
  //               Padding(
  //                 padding: const EdgeInsets.symmetric(horizontal: 32),
  //                 child: Text(
  //                   'Schedule on all social platforms with the premium plan',
  //                   style: TextStyle(
  //                     fontSize: 16,
  //                     color: Colors.white.withOpacity(0.9),
  //                     fontWeight: FontWeight.w500,
  //                   ),
  //                   textAlign: TextAlign.center,
  //                 ),
  //               ),
  //               
  //               SizedBox(height: 36),
  //               
  //               // Premium card
  //               Container(
  //                 margin: EdgeInsets.symmetric(horizontal: 24),
  //                 decoration: BoxDecoration(
  //                   color: Colors.white,
  //                   borderRadius: BorderRadius.circular(20),
  //                   boxShadow: [
  //                     BoxShadow(
  //                       color: Colors.black.withOpacity(0.1),
  //                       blurRadius: 10,
  //                       offset: const Offset(0, 4),
  //                     ),
  //                   ],
  //                 ),
  //                 child: Padding(
  //                   padding: const EdgeInsets.all(20),
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Text(
  //                         'Premium',
  //                         style: TextStyle(
  //                           fontWeight: FontWeight.bold,
  //                           fontSize: 20,
  //                           color: Colors.black87,
  //                         ),
  //                       ),
  //                       SizedBox(height: 4),
  //                       Row(
  //                         crossAxisAlignment: CrossAxisAlignment.end,
  //                         children: [
  //                           Text(
  //                             '€6,99',
  //                             style: TextStyle(
  //                               fontSize: 28,
  //                               color: theme.colorScheme.primary,
  //                               fontWeight: FontWeight.bold,
  //                             ),
  //                           ),
  //                           Text(
  //                             '/month',
  //                             style: TextStyle(
  //                               fontSize: 16,
  //                               color: Colors.grey[600],
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                       SizedBox(height: 20),
  //                       
  //                       // Features list
  //                       _buildPremiumFeatureRow(
  //                         Icons.schedule,
  //                         'Post scheduling',
  //                         'All platforms'
  //                       ),
  //                       SizedBox(height: 12),
  //                       _buildPremiumFeatureRow(
  //                         Icons.language,
  //                         'Social accounts',
  //                         'Unlimited'
  //                       ),
  //                       SizedBox(height: 12),
  //                       _buildPremiumFeatureRow(
  //                         Icons.upload,
  //                         'Video per day',
  //                         'Unlimited'
  //                       ),
  //                       SizedBox(height: 12),
  //                       _buildPremiumFeatureRow(
  //                         Icons.support_agent,
  //                         'AI Analysis',
  //                         'Unlimited'
  //                       ),
  //                       SizedBox(height: 16),
  //                       
  //                       // Trial info
  //                       Container(
  //                         padding: EdgeInsets.all(12),
  //                         decoration: BoxDecoration(
  //                           color: theme.colorScheme.primary.withOpacity(0.1),
  //                           borderRadius: BorderRadius.circular(12),
  //                         ),
  //                         child: Row(
  //                           children: [
  //                             Icon(
  //                               Icons.info_outline,
  //                               color: theme.colorScheme.primary,
  //                               size: 20,
  //                             ),
  //                             SizedBox(width: 10),
  //                             Expanded(
  //                               child: Text(
  //                                 'Free trial of 3 days',
  //                                 style: TextStyle(
  //                                   fontWeight: FontWeight.w500,
  //                                   color: theme.colorScheme.primary,
  //                                 ),
  //                               ),
  //                             ),
  //                           ],
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }
  
  // Helper per costruire le righe delle caratteristiche premium
  Widget _buildPremiumFeatureRow(IconData icon, String title, String description) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper method to format file size
  String _formatFileSize(File file) {
    try {
      int bytes = file.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < (1024 * 1024)) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < (1024 * 1024 * 1024)) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (e) {
      print('Error getting file size: $e');
      return 'N/A';
    }
  }

  Widget _buildVideoInfoItem(ThemeData theme, IconData icon, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: theme.colorScheme.primary,
          size: 22,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // Helper method to get platform background color
  Color _getPlatformBackgroundColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Color(0xFF1DA1F2);
      case 'youtube':
        return Color(0xFFFF0000);
      case 'tiktok':
        return Color(0xFF000000);
      case 'instagram':
        return Color(0xFFE1306C);
      case 'facebook':
        return Color(0xFF1877F2);
      case 'threads':
        return Color(0xFF000000);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;

    // Check if we should use a simpler layout for large files
    bool useSimpleLayout = false;
    try {
      if (!_currentIsImage && _thumbnailPath == null && !_isVideoInitialized) {
        useSimpleLayout = true;
      }
    } catch (e) {
      print('Error determining layout: $e');
      useSimpleLayout = true;
    }

    // Background color for video containers
    final videoBackgroundColor = isDark ? Color(0xFF1A1A1A) : Color(0xFF2C3E50).withOpacity(0.9);
    
    // Adjust video container size based on fullscreen mode
    final videoContainerHeight = _isFullScreen ? mediaHeight : 240.0;

    return Scaffold(
      backgroundColor: isDark ? Color(0xFF121212) : Colors.grey[100],
      appBar: null,
      body: Stack(
        children: [
          // Main content area - no padding, content can scroll behind floating header
          SafeArea(
            bottom: !_isFullScreen,
            top: !_isFullScreen,
            child: _isFullScreen
            // Simplified layout for fullscreen mode
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    _showControls = !_showControls;
                  });
                  
                  // Nascondi i controlli automaticamente dopo 3 secondi
                  _controlsHideTimer?.cancel();
                  if (_showControls) {
                    _controlsHideTimer = Timer(Duration(seconds: 3), () {
                      if (mounted && _videoPlayerController?.value.isPlaying == true) {
                        setState(() {
                          _showControls = false;
                        });
                      }
                    });
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black,
                  child: Stack(
                    children: [
                      // If it's an image, show it fullscreen with black borders
                      if (_currentIsImage)
                        Center(
                          child: Container(
                            width: mediaWidth,
                            height: mediaHeight,
                            color: Colors.black,
                            child: _buildImagePreview(),
                          ),
                        )
                      // If video is initialized, show it with black borders
                      else if (_isVideoInitialized && _videoPlayerController != null)
                        Center(
                          child: Container(
                            width: mediaWidth,
                            height: mediaHeight,
                            color: Colors.black,
                            child: _buildVideoPlayer(_videoPlayerController!),
                          ),
                        ),
                      
                      // Video controls in fullscreen mode
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
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
                            
                            // Button to exit fullscreen mode
                            Positioned(
                              top: 70,
                              left: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: IconButton(
                                  icon: Icon(Icons.fullscreen_exit, color: Colors.white),
                                  onPressed: () {
                                    _pauseVideo();
                                    _toggleFullScreen();
                                  },
                                ),
                              ),
                            ),
                            
                            // Play/Pause button in center only for videos
                            if (!_currentIsImage && _isVideoInitialized && _videoPlayerController != null)
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
                            
                            // Progress bar only for videos
                            if (!_currentIsImage && _isVideoInitialized && _videoPlayerController != null)
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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 100, 8, 8), // Aggiunto padding superiore per la top bar
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Enhanced Media Preview with fullscreen option
                          GestureDetector(
                            onTap: () {
                              // Mostra/nascondi i controlli al click sullo schermo
                              setState(() {
                                _showControls = !_showControls;
                              });
                              
                              // Nascondi i controlli automaticamente dopo 3 secondi
                              _controlsHideTimer?.cancel();
                              if (_showControls) {
                                _controlsHideTimer = Timer(Duration(seconds: 3), () {
                                  if (mounted && _videoPlayerController?.value.isPlaying == true) {
                                    setState(() {
                                      _showControls = false;
                                    });
                                  }
                                });
                              }
                            },
                            child: Container(
                              width: mediaWidth,
                              height: videoContainerHeight,
                              margin: EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: videoBackgroundColor,
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
                              child: _mediaFiles.length > 1
                                  ? _buildCarouselMediaPreview(theme, videoContainerHeight, useSimpleLayout)
                                  : Stack(
                                      children: [
                                        // Main content (video or image)
                                        if (_currentIsImage)
                                          Stack(
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                height: videoContainerHeight,
                                                color: Colors.black,
                                                child: Center(
                                                  child: _currentMediaFile != null
                                                      ? Image.file(
                                                          _currentMediaFile!,
                                                          fit: BoxFit.contain,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return Center(
                                                              child: Icon(
                                                                Icons.image_not_supported,
                                                                color: Colors.grey[400],
                                                                size: 48,
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : SizedBox(),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 12,
                                                right: 12,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.6),
                                                    borderRadius: BorderRadius.circular(25),
                                                  ),
                                                  child: IconButton(
                                                    icon: Icon(Icons.fullscreen, color: Colors.white, size: 24),
                                                    onPressed: () {
                                                      setState(() {
                                                        _isFullScreen = true;
                                                      });
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          useSimpleLayout
                                              ? _buildSimpleMediaPreview(theme)
                                              : _buildRichMediaPreview(theme),
                                      ],
                                    ),
                            ),
                          ),
                          
                          // Spacing after media container (ridotto per ridurre gap con account)
                          SizedBox(height: 0),
                          
                          // Divider before scheduling section
                          Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant.withOpacity(0.5)),
                          
                          // Scheduling Section with optimized date/time display
                          _buildSchedulingSection(theme),
                          SizedBox(height: 0),
                          
                          // Selected Accounts Section with improved styling
                          _buildAccountsSection(theme),
                          
                          SizedBox(height: 16),
                          
                          // Disclaimer con checkbox (mostrato solo se è il primo video)
                          if (_showDisclaimer && !_isCheckingVideos)
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: 16),
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark ? Color(0xFF2A2A2A) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? Colors.grey[700]! : theme.colorScheme.outline.withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'By publishing this content via Fluzar, you confirm that you:',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 12),
                                                                  Text(
                                    '• Authorize Fluzar to publish this content on the selected profiles/pages',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isDark ? Colors.grey[200] : Colors.grey[700],
                                  ),
                                ),
                                SizedBox(height: 4),
                                RichText(
                                  text: TextSpan(
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark ? Colors.grey[200] : Colors.grey[700],
                                    ),
                                    children: [
                                      TextSpan(text: '• Accept Fluzar\'s '),
                                      TextSpan(
                                        text: 'Terms of Service',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () async {
                                            final url = 'https://fluzar.com/terms-conditions';
                                            if (await canLaunchUrl(Uri.parse(url))) {
                                              await launchUrl(Uri.parse(url));
                                            }
                                          },
                                      ),
                                      TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Privacy Policy',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () async {
                                            final url = 'https://fluzar.com/privacy-policy';
                                            if (await canLaunchUrl(Uri.parse(url))) {
                                              await launchUrl(Uri.parse(url));
                                            }
                                          },
                                      ),
                                    ],
                                  ),
                                ),
                                // Mostra il disclaimer TikTok solo se è stato selezionato un account TikTok
                                if (widget.selectedAccounts.containsKey('TikTok') && 
                                    widget.selectedAccounts['TikTok']!.isNotEmpty) ...[
                                  SizedBox(height: 4),
                                  RichText(
                                    text: TextSpan(
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: isDark ? Colors.grey[200] : Colors.grey[700],
                                      ),
                                      children: [
                                        TextSpan(text: '• Accept TikTok\'s '),
                                        TextSpan(
                                          text: 'Music Usage Confirmation',
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            decoration: TextDecoration.underline,
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () async {
                                              final url = 'https://www.tiktok.com/legal/page/global/music-usage-confirmation/en';
                                              if (await canLaunchUrl(Uri.parse(url))) {
                                                await launchUrl(Uri.parse(url));
                                              }
                                            },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                SizedBox(height: 16),
                              ],
                            ),
                          ),

                          SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ),
          
          // Floating header - nasconde quando è in fullscreen
          if (!_isFullScreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _buildHeader(),
              ),
            ),
        ],
      ),
      // Avviso crediti insufficienti
      bottomSheet: _showCreditsWarning ? _buildCreditsWarning() : null,
      bottomNavigationBar: _isFullScreen
    ? null
    : Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: (_isSaving || _isLoadingCredits) ? null : _saveScheduledPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: _isSaving
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Pianificazione in corso...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _isLoadingCredits 
                          ? 'Caricamento...' 
                          : 'Proceed to scheduling',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // Build header like in about_page.dart
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
              Row(
                children: [
                  // Title in button form for the page
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Scheduling',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Method to handle aspect ratio for images
  Widget _buildImagePreview() {
    if (_currentMediaFile == null) {
      return Center(
        child: Icon(
          Icons.image_not_supported,
          color: Colors.grey[400],
          size: 48,
        ),
      );
    }
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black, // Sfondo nero per immagini che non coprono tutto lo spazio
      child: Center(
        child: Image.file(
          _currentMediaFile!,
          fit: BoxFit.contain, // Mantiene l'aspect ratio originale
          errorBuilder: (context, error, stackTrace) {
            print('Error loading image: $error');
            return Center(
              child: Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 48,
              ),
            );
          },
        ),
      ),
    );
  }

  // Simple media preview for large files or error cases with modern design
  Widget _buildSimpleMediaPreview(ThemeData theme) {
    return Container(
      color: theme.brightness == Brightness.dark ? Color(0xFF1A1A1A) : Color(0xFF2C3E50).withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentIsImage ? Icons.photo : Icons.video_library,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              _currentIsImage ? 'Immagine' : 'Video',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading file...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _currentMediaFile?.path.split('/').last ?? 'Unknown',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Rich media preview with improved video player controls
  Widget _buildRichMediaPreview(ThemeData theme) {
    if (_currentMediaFile == null) {
      return _buildPlaceholder(theme);
    }
    
    return _currentIsImage 
      ? Image.file(
          _currentMediaFile!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            print('Error loading image: $error');
            return _buildPlaceholder(theme);
          },
        )
      : _isVideoInitialized && _videoPlayerController != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              // Modern video player with dark background
              Container(
                color: Colors.black,
                child: Center(
                  child: _buildVideoPlayer(_videoPlayerController!),
                ),
              ),
              
              // Gradient overlay for controls visibility
              Container(
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
              
              // Video controls at bottom right - solo se i controlli sono visibili
              if (_showControls)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Row(
                    children: [
                      // Play/Pause button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: IconButton(
                          icon: Icon(
                            _videoPlayerController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: _toggleVideoPlayback,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Fullscreen button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: _toggleFullScreen,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Video progress indicator at bottom - sempre visibile
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: _videoPlayerController!.value.duration.inSeconds > 0
                        ? _videoPlayerController!.value.position.inSeconds / 
                          _videoPlayerController!.value.duration.inSeconds
                        : 0.0,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
              ),
            ],
          )
        : _buildPlaceholder(theme);
  }
  
  // Helper method to build a placeholder for media with modern design
  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.brightness == Brightness.dark ? Color(0xFF1A1A1A) : Color(0xFF2C3E50).withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentIsImage ? Icons.photo : Icons.video_library,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _currentMediaFile?.path.split('/').last ?? 'Unknown',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _currentIsImage ? 'Caricamento immagine...' : 'Caricamento video...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build carousel media preview for multiple media
  Widget _buildCarouselMediaPreview(ThemeData theme, double containerHeight, bool useSimpleLayout) {
    return Stack(
      children: [
        PageView.builder(
          controller: _carouselController,
          onPageChanged: _onCarouselPageChanged,
          itemCount: _mediaFiles.length,
          itemBuilder: (context, index) {
            final file = _mediaFiles[index];
            final isImage = _isImageFiles[index];
            final isCurrentPage = index == _currentCarouselIndex;
            
            if (isImage) {
              return Container(
                width: double.infinity,
                height: containerHeight,
                color: Colors.black,
                child: Center(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.image_not_supported,
                          color: Colors.grey[400],
                          size: 48,
                        ),
                      );
                    },
                  ),
                ),
              );
            } else {
              // Per i video, mostra il player se è la pagina corrente
              if (isCurrentPage) {
                // Mostra il video player anche se non è ancora inizializzato (mostrerà un placeholder)
                return useSimpleLayout
                    ? _buildSimpleMediaPreview(theme)
                    : _buildRichMediaPreview(theme);
              } else {
                // Placeholder per video non correnti
                return Container(
                  width: double.infinity,
                  height: containerHeight,
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
        
        // Indicatore di pagina (dots) in basso
        if (_mediaFiles.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _mediaFiles.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.symmetric(horizontal: 4),
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
        
        // Pulsante fullscreen per immagini
        if (_currentIsImage && !_isFullScreen)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(25),
              ),
              child: IconButton(
                icon: Icon(Icons.fullscreen, color: Colors.white, size: 24),
                onPressed: () {
                  setState(() {
                    _isFullScreen = true;
                  });
                },
              ),
            ),
          ),
      ],
    );
  }

  // Helper method to build scheduling section with professional and minimal design
  Widget _buildSchedulingSection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final difference = widget.scheduledDateTime.difference(now);
    
    String countdownText;
    if (difference.isNegative) {
      countdownText = "Now";
    } else if (difference.inDays > 0) {
      countdownText = "${difference.inDays}d ${difference.inHours % 24}h";
    } else if (difference.inHours > 0) {
      countdownText = "${difference.inHours}h ${difference.inMinutes % 60}m";
    } else if (difference.inMinutes > 0){
      countdownText = "${difference.inMinutes}m";
    } else {
      countdownText = "Now";
    }
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color(0xFF6C63FF),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Automatic publication',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Color(0xFF6C63FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SCHEDULED',
                  style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Date and Time cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? Color(0xFF2A2A2A) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Text(
                            'Date',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, yyyy').format(widget.scheduledDateTime),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? Color(0xFF2A2A2A) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Text(
                            'Time',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(widget.scheduledDateTime),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Countdown Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF2A2A2A) : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  'Scheduled',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const Spacer(),
                Text(
                  countdownText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build accounts section matching style from upload_confirmation_page
  Widget _buildAccountsSection(ThemeData theme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(width: 8),
                Text(
                  'Selected accounts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          
          // Improved platform sections with more modern design
          Column(
            children: [
              ...widget.selectedAccounts.entries.map((entry) {
                final platform = entry.key;
                final accounts = entry.value;
                
                // Skip if no accounts selected for this platform
                if (accounts.isEmpty) return SizedBox.shrink();
                
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Color(0xFF1E1E1E) : Colors.white, // Tutti i social ora usano sfondo bianco
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Platform header with improved design
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getPlatformLightColor(platform), // Usa il colore standard per tutti i social
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.withOpacity(0.1),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: _getPlatformColor(platform).withOpacity(0.1),
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                _platformLogos[platform] ?? '',
                                width: 16,
                                height: 16,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              platform.toUpperCase(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: (theme.brightness == Brightness.dark &&
                                        (platform.toLowerCase() == 'threads' ||
                                         platform.toLowerCase() == 'tiktok'))
                                    ? Colors.white
                                    : _getPlatformColor(platform),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // List of accounts for this platform
                      ...accounts.map((accountId) {
                        final account = widget.socialAccounts[platform]?.firstWhere(
                          (acc) => acc['id'] == accountId,
                          orElse: () => <String, dynamic>{},
                        );
                        
                        if (account == null || account.isEmpty) return SizedBox.shrink();
                        
                        // Check if there's a platform-specific description for this account
                        final hasCustomDescription = widget.platformDescriptions.containsKey(platform) && 
                                                    widget.platformDescriptions[platform]!.containsKey(accountId);
                        
                        return _buildAccountCard(
                          theme: theme,
                          platform: platform,
                          account: account,
                          accountId: accountId,
                          hasCustomDescription: hasCustomDescription,
                        );
                      }).toList(),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method to build an account card with description (identico a upload_confirmation_page.dart)
  Widget _buildAccountCard({
    required ThemeData theme,
    required String platform,
    required Map<String, dynamic> account,
    required String accountId,
    required bool hasCustomDescription,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final username = account['username'] as String? ?? '';
    final displayName = account['display_name'] as String? ?? username;
    final profileImageUrl = account['profile_image_url'] as String?;
    
    // Check for custom title
    final bool hasCustomTitle = widget.platformDescriptions.containsKey(platform) && 
                                widget.platformDescriptions[platform]!.containsKey('${accountId}_title');
    
    // Get the platform-specific description if available
    final String? customDescription = hasCustomDescription
        ? widget.platformDescriptions[platform]![accountId]
        : null;
    
    // Show details if there's a custom description or if it's YouTube (to show title)
    final bool hasCustomContent = hasCustomDescription || platform.toLowerCase() == 'youtube';
    
    // Per Threads e TikTok, usa bianco in dark mode invece di nero per l'icona
    final iconColor = (platform.toLowerCase() == 'threads' || platform.toLowerCase() == 'tiktok') && isDark
        ? Colors.white
        : _getPlatformColor(platform);
    
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
          Container(
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
              radius: 20,
              backgroundColor: theme.colorScheme.surface,
              backgroundImage: profileImageUrl?.isNotEmpty == true
                ? NetworkImage(profileImageUrl as String)
                : null,
              child: profileImageUrl?.isNotEmpty != true
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
          const SizedBox(width: 16),
          
          // Account details
          Expanded(
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
                // Per TikTok, non mostrare il nome utente con "@"
                if (platform.toLowerCase() != 'tiktok') ...[
                SizedBox(height: 2),
                Text(
                  '@$username',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),              
                ],
              ],
            ),
          ),
          
          // Info button only (no View button)
          IconButton(
            onPressed: hasCustomContent 
              ? () {
                  // Add accountId to the account map before passing to dialog
                  final accountWithId = Map<String, dynamic>.from(account);
                  accountWithId['id'] = accountId; // Ensure accountId is included
                  _showCustomDescriptionDialog(
                    context, 
                    platform, 
                    accountWithId, 
                    customDescription ?? ''
                  );
                }
              : null,
            icon: Icon(Icons.info_outline, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: iconColor,
              backgroundColor: _getPlatformLightColor(platform),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            tooltip: 'View post details',
          )
        ],
      ),
    );
  }

  // Method to show custom description dialog
  void _showCustomDescriptionDialog(BuildContext context, String platform, Map<String, dynamic> account, String description) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final username = account['username'] as String? ?? '';
    final displayName = account['display_name'] as String? ?? username;
    final profileImageUrl = account['profile_image_url'] as String?;
    final platformColor = _getPlatformColor(platform);
    // Per Threads e TikTok, usa bianco in dark mode invece di nero
    final displayPlatformColor = (platform.toLowerCase() == 'threads' || platform.toLowerCase() == 'tiktok') && isDark
        ? Colors.white
        : platformColor;
    
    // Use the proper title
    final accountId = account['id'] as String? ?? '';
    
    // Get the correct title for this platform/account
    String? customTitle = widget.title;
    if (widget.platformDescriptions.containsKey(platform) && 
        widget.platformDescriptions[platform]!.containsKey('${accountId}_title')) {
      customTitle = widget.platformDescriptions[platform]!['${accountId}_title'];
    }
    
    // Determine if we should show title section
    final bool shouldShowTitle = customTitle?.isNotEmpty == true || 
                                 widget.title.isNotEmpty || 
                                 platform.toLowerCase() == 'youtube';
    
    // Get the title to display
    final String titleToDisplay = customTitle?.isNotEmpty == true 
        ? customTitle! 
        : (widget.title.isNotEmpty ? widget.title : 'No title available');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
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
            // Drag indicator at top
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            
            // Header with platform
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
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
                      _platformLogos[platform] ?? '',
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
                      color: displayPlatformColor,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            
            // Profile information
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _getPlatformLightColor(platform),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Profile image
                  Container(
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
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                          ? NetworkImage(profileImageUrl)
                          : null,
                      child: profileImageUrl == null || profileImageUrl.isEmpty
                          ? Text(
                              username.isNotEmpty ? username[0].toUpperCase() : '',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: platformColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
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
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Post content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Add title section only for YouTube
                    if (platform.toLowerCase() == 'youtube') ...[
                      Text(
                        'Title',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          titleToDisplay,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    
                    Text(
                      'Description',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        description.isNotEmpty ? description : 'No description available',
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
  
  // Add the platform color helper methods
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

  // Get the platform color
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

  // Metodo per gestire il cambio di media nel carosello
  void _onCarouselPageChanged(int index) {
    if (index < 0 || index >= _mediaFiles.length) return;
    
    setState(() {
      _currentCarouselIndex = index;
      _currentMediaFile = _mediaFiles[index];
      _currentIsImage = _isImageFiles[index];
      
      // Ferma e dispone il video player corrente
      if (_videoPlayerController != null) {
        _videoPlayerController!.pause();
        _videoPlayerController!.dispose();
        _videoPlayerController = null;
        _isVideoInitialized = false;
        _isVideoPlaying = false;
      }
    });
    
    // Inizializza il video player per il nuovo media se è un video
    if (!_currentIsImage) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_isDisposed && mounted) {
          _initializeVideoPlayer();
        }
      });
    }
  }
  
  // Generate a thumbnail from the video
  Future<void> _generateThumbnail() async {
    if (_currentIsImage || _isDisposed || _currentMediaFile == null) return;
    
    try {
      print('Generating thumbnail for: ${_currentMediaFile!.path}');
      
      // Check file size before processing to avoid memory issues
      final fileSize = await _currentMediaFile!.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      print('Video file size: ${fileSizeMB.toStringAsFixed(2)} MB');
      
      // Use reduced settings for large files
      int targetQuality = 70; // Reduced from 80
      int targetWidth = 240; // Reduced from 320
      
      // Reduce quality for larger files to prevent memory issues
      if (fileSizeMB > 50) {
        targetQuality = 50; // Reduced from 60
        targetWidth = 180; // Reduced from 240
        print('Reducing thumbnail quality for large file');
      }
      
      // Skip thumbnail generation for extremely large files
      if (fileSizeMB > 200) {
        print('File too large (${fileSizeMB.toStringAsFixed(2)} MB), skipping thumbnail generation');
        return;
      }
      
      // Add a garbage collection hint before heavy operation
      await Future.delayed(Duration.zero);

      try {
        // Use video_thumbnail package to generate thumbnail with optimized settings
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: _currentMediaFile!.path,
          imageFormat: ImageFormat.JPEG,
          quality: targetQuality,
          maxWidth: targetWidth, // Smaller width for thumbnails
          timeMs: 500, // Take frame at 500ms
        ).timeout(
          const Duration(seconds: 6), // Reduced from 10
          onTimeout: () {
            print('Thumbnail generation timed out');
            return null;
          },
        );
      
        if (thumbnailBytes == null) {
          print('Failed to generate thumbnail: thumbnailBytes is null');
          return;
        }
        
        // Add another GC hint before file operations
        await Future.delayed(Duration.zero);
      
        // Save the thumbnail locally
        final thumbnailFile = await _saveThumbnailToFile(thumbnailBytes);
        if (thumbnailFile != null && mounted) {
          setState(() {
            _thumbnailPath = thumbnailFile.path;
          });
          print('Thumbnail generated and saved at: $_thumbnailPath');
        } else {
          print('Failed to save thumbnail file or widget unmounted');
        }
      } catch (e) {
        print('Error in thumbnail generation: $e');
        // Try fallback method for thumbnail generation if the main method fails
        await _generateFallbackThumbnail();
      }
    } catch (e) {
      print('Error generating thumbnail: $e');
    }
  }
  
  // Fallback method for thumbnail generation with even lower memory usage
  Future<void> _generateFallbackThumbnail() async {
    try {
      print('Attempting fallback thumbnail generation');
      
      // Use the absolute minimal settings
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: _currentMediaFile!.path,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        quality: 40,
        maxWidth: 160,
        timeMs: 1000,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Fallback thumbnail generation timed out');
          return null;
        },
      );
      
      if (thumbnailPath != null && mounted) {
        setState(() {
          _thumbnailPath = thumbnailPath;
        });
        print('Fallback thumbnail generated at: $_thumbnailPath');
      }
    } catch (e) {
      print('Error in fallback thumbnail generation: $e');
    }
  }
  
  // Save thumbnail bytes to a file
  Future<File?> _saveThumbnailToFile(Uint8List thumbnailBytes) async {
    try {
      // Use specific compression and sizing for more memory efficiency
      Uint8List? compressedBytes;
      
      try {
        // Downsample the image if it's large
        if (thumbnailBytes.length > 500 * 1024) { // If larger than 500KB
          final img.Image? decoded = img.decodeImage(thumbnailBytes);
          if (decoded != null) {
            // Resize to a smaller resolution
            final img.Image resized = img.copyResize(
              decoded,
              width: 240,
              interpolation: img.Interpolation.average,
            );
            
            // Re-encode at lower quality
            compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
            print('Thumbnail compressed from ${thumbnailBytes.length} to ${compressedBytes.length} bytes');
          }
        }
      } catch (e) {
        print('Error compressing thumbnail: $e - using original bytes');
      }
      
      final bytesToSave = compressedBytes ?? thumbnailBytes;
      
      final fileName = _currentMediaFile?.path.split('/').last ?? 'video';
      final thumbnailFileName = '${fileName.split('.').first}_thumbnail.jpg';
      
      // Get the app's temporary directory
      final directory = await getTemporaryDirectory();
      final thumbnailPath = '${directory.path}/$thumbnailFileName';
      
      // Save the file
      final file = File(thumbnailPath);
      await file.writeAsBytes(bytesToSave);
      
      // Force garbage collection hint after writing file
      await Future.delayed(Duration.zero);
      
      return file;
    } catch (e) {
      print('Error saving thumbnail file: $e');
      return null;
    }
  }
}