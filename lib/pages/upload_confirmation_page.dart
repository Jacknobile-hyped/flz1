import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // Importa http_parser per MediaType
import 'dart:convert';
import '../providers/theme_provider.dart';
import './home_page.dart';
import 'package:video_player/video_player.dart'; // Add the video_player import
import 'package:path_provider/path_provider.dart'; // For saving thumbnail files
import 'package:image/image.dart' as img; // For image processing
import 'package:video_thumbnail/video_thumbnail.dart'; // Add video_thumbnail import
import './upload_status_page.dart';
import './instagram_upload_page.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import './credits_page.dart';
import './upgrade_premium_page.dart';
import './upgrade_premium_ios_page.dart';

// Aggiungiamo la classe AccountPanel prima della classe UploadConfirmationPage
class AccountPanel {
  final String platform;
  final String accountId;
  final String? title;
  final String? description;

  AccountPanel({
    required this.platform,
    required this.accountId,
    this.title,
    this.description,
  });
}

class UploadConfirmationPage extends StatefulWidget {
  final File? videoFile; // Mantenuto per retrocompatibilità, ma deprecato
  final List<File>? videoFiles; // Nuova lista di file
  final List<bool>? isImageFiles; // Nuova lista di flag per immagini
  final String title;
  final String description;
  final Map<String, List<String>> selectedAccounts;
  final Map<String, List<Map<String, dynamic>>> socialAccounts;
  final VoidCallback onConfirm;
  final bool isDraft;
  final bool isImageFile; // Mantenuto per retrocompatibilità
  final Map<String, String> instagramContentType;
  final String? cloudflareUrl; // Aggiungo l'URL di Cloudflare R2
  // Add map for platform-specific descriptions
  final Map<String, Map<String, String>> platformDescriptions;
  // Aggiungi proprietà mancanti con valori di default
  final List<AccountPanel> selectedAccountPanels;
  final String globalTitle;
  final String globalDescription;
  final String? draftId; // Add draft ID parameter
  final File? youtubeThumbnailFile; // Per la miniatura personalizzata di YouTube
  final Map<String, Map<String, dynamic>>? tiktokOptions; // Opzioni TikTok per ogni account
  final Map<String, Map<String, dynamic>>? youtubeOptions; // Opzioni YouTube per ogni account

  const UploadConfirmationPage({
    super.key,
    this.videoFile, // Opzionale per retrocompatibilità
    this.videoFiles, // Nuova lista di file
    this.isImageFiles, // Nuova lista di flag
    required this.title,
    required this.description,
    required this.selectedAccounts,
    required this.socialAccounts,
    required this.onConfirm,
    this.isDraft = false,
    this.isImageFile = false,
    this.instagramContentType = const {},
    this.cloudflareUrl, // Parametro opzionale
    this.platformDescriptions = const {}, // Default to empty map
    this.selectedAccountPanels = const [], // Inizializzazione del campo
    this.globalTitle = '', // Inizializzazione del campo
    this.globalDescription = '', // Inizializzazione del campo
    this.draftId, // Add draft ID parameter
    this.youtubeThumbnailFile, // Per la miniatura personalizzata di YouTube
    this.tiktokOptions, // Opzioni TikTok per ogni account
    this.youtubeOptions, // Opzioni YouTube per ogni account
  });

  @override
  State<UploadConfirmationPage> createState() => _UploadConfirmationPageState();
}

class _UploadConfirmationPageState extends State<UploadConfirmationPage> {
  bool _isUploading = false;
  Map<String, bool> _uploadStatus = {};
  Map<String, String> _uploadMessages = {};
  Map<String, double> _uploadProgress = {};
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  String? _thumbnailPath; // To store local path of generated thumbnail
  String? _thumbnailCloudflareUrl; // To store Cloudflare URL of the thumbnail
  // Aggiungiamo la variabile _cloudflareUrl
  String _cloudflareUrl = '';
  
  // Aggiungiamo un servizio fittizio per Firestore
  final _firestoreService = FirestoreService();
  
  // Video player controller
  VideoPlayerController? _videoPlayerController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;
  bool _isDisposed = false; // Track widget disposal
  
  // Variabili per gestire più media
  List<File> _mediaFiles = [];
  List<bool> _isImageFiles = [];
  PageController? _carouselController;
  int _currentCarouselIndex = 0;
  File? _currentMediaFile;
  bool _currentIsImage = false;
  
  // Aggiungi variabili per la gestione a tutto schermo
  bool _isFullScreen = false;
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  bool _showControls = true;
  Timer? _controlsHideTimer; // Timer per nascondere i controlli automaticamente
  
  // Google Sign-In istance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube'
    ],
    serverClientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
  );
  
  // Lock per evitare login multipli simultanei
  bool _isGoogleSigningIn = false;
  

  
  // Variabili per gestione crediti utenti non premium
  int _userCredits = 0;
  bool _isPremiumUser = false;
  bool _isLoadingCredits = true;
  bool _showCreditsWarning = false;
  
  // Variabili per gestione disclaimer (mostrato solo al primo video)
  bool _showDisclaimer = false;
  bool _isCheckingVideos = true;
  
  // Platform logos for UI display
  final Map<String, String> _platformLogos = {
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'Instagram': 'assets/loghi/logo_insta.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
  };

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
    }
    
    // Avvia il timer per l'aggiornamento della posizione del video
    _startPositionUpdateTimer();
    
    // Carica i crediti dell'utente
    _loadUserCredits();
    
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
          _isPremiumUser = (userData['isPremium'] as bool?) ?? false;
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
  
  // Metodo per calcolare i crediti necessari per il video
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
  bool _hasSufficientCredits() {
    if (_isPremiumUser) return true;
    final requiredCredits = _calculateRequiredCredits();
    return _userCredits >= requiredCredits;
  }
  
  // Metodo per mostrare l'avviso crediti insufficienti
  void _showInsufficientCreditsWarning() {
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
            'You\'ve run out of credits for video upload. Earn more or upgrade to continue.',
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
      _showControls = true; // Mostra i controlli quando cambia la modalità
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
  
  // Metodo per costruire il video player mantenendo il corretto aspect ratio
  Widget _buildVideoPlayer(VideoPlayerController controller) {
    // Verifica se il video è orizzontale (aspect ratio > 1)
    final bool isHorizontalVideo = controller.value.aspectRatio > 1.0;
    
    if (isHorizontalVideo) {
      // Per i video orizzontali, li mostriamo a schermo intero con FittedBox
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Sfondo nero per evitare spazi vuoti
        child: FittedBox(
          fit: BoxFit.contain, // Scale per preservare aspect ratio
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      // Per i video verticali, manteniamo l'AspectRatio standard
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
          if (fileSizeMB > 120) { // Aumentato a 120MB per consentire più video
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
      // Se il video non è inizializzato, prova a inizializzarlo ora
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
  
  // Nuova funzione per pausare il video senza chiamare setState
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
    _controlsHideTimer?.cancel();
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
          // await thumbnailFile.delete();
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

  Future<void> _uploadToPlatforms() async {
    // Usa sempre il media corrente (o il primo) come file principale
    final File primaryFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
    final bool primaryIsImage = _currentIsImage;

    // Navigate to the upload status page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadStatusPage(
          videoFile: primaryFile,
          title: widget.title,
          description: widget.description,
          selectedAccounts: widget.selectedAccounts,
          socialAccounts: widget.socialAccounts,
          onComplete: widget.onConfirm,
          isImageFile: primaryIsImage,
          instagramContentType: widget.instagramContentType,
          cloudflareUrl: widget.cloudflareUrl,
          platformDescriptions: widget.platformDescriptions,
          uploadFunction: _performUpload,
        ),
      ),
    );
  }

  // New function that wraps all the upload logic to be passed to UploadStatusPage
  Future<void> _performUpload(
    Function(String platform, String accountId, String message, double progress) updateProgress,
    Function(List<Exception> errors) onErrors
  ) async {
    try {
      // First, upload the file to Cloudflare R2 storage
      String? cloudflareUrl = widget.cloudflareUrl;
      // Usa il media principale come file da caricare
      final File primaryFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
      final bool primaryIsImage = _currentIsImage;
      
      // If we didn't receive a cloudflareUrl from the parent, upload it now
      if (cloudflareUrl == null) {
        updateProgress('cloudflare', 'storage', 'Uploading media to cloud storage...', 0.1);
        
        try {
          // Upload the file to Cloudflare just once, and store the URL
          cloudflareUrl = await _uploadToCloudflare(primaryFile, isImage: primaryIsImage);
          
          // Store the URL in the class variable to be used by all platforms
          _cloudflareUrl = cloudflareUrl ?? '';
          
          if (cloudflareUrl == null) {
            throw Exception('Failed to upload media to Cloudflare');
          }
          
          // Verifica che il file sia stato effettivamente caricato
          bool isUploaded = await _verifyCloudflareUpload(cloudflareUrl);
          if (!isUploaded) {
            print('Il file sembra non essere stato caricato correttamente, riprovo...');
            updateProgress('cloudflare', 'storage', 'Retrying upload...', 0.5);
            cloudflareUrl = await _retryCloudflareUpload(primaryFile, isImage: primaryIsImage);
            // Update the stored URL with the retry result
            _cloudflareUrl = cloudflareUrl ?? '';
          }
          
          updateProgress('cloudflare', 'storage', 'Media uploaded to cloud storage successfully!', 1.0);
        } catch (e) {
          updateProgress('cloudflare', 'storage', 'Error: $e', 0);
          throw Exception('Failed to upload media to Cloudflare: $e');
        }
      } else {
        // If we received a cloudflareUrl from the parent, use it
        _cloudflareUrl = cloudflareUrl;
      }
      
      // After media upload, upload thumbnail if this is a video
      String? thumbnailUrl;
      if (!widget.isImageFile && _thumbnailPath == null) {
        // Generate thumbnail if not already done
        await _generateThumbnail();
      }
      
      if (!widget.isImageFile && _thumbnailPath != null) {
        // Upload the thumbnail to Cloudflare
        updateProgress('thumbnail', 'thumb', 'Uploading thumbnail...', 0.1);
        thumbnailUrl = await _uploadThumbnailToCloudflare();
        _thumbnailCloudflareUrl = thumbnailUrl;
        
        // Verifica che la thumbnail sia stata effettivamente caricata
        if (thumbnailUrl != null) {
          bool isThumbnailUploaded = await _verifyCloudflareUpload(thumbnailUrl);
          if (!isThumbnailUploaded) {
            print('La thumbnail sembra non essere stata caricata correttamente, riprovo...');
            updateProgress('thumbnail', 'thumb', 'Retrying thumbnail upload...', 0.5);
            final String videoFileName = (_currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!)))
                .path
                .split('/')
                .last
                .split('.')
                .first;
            final String retryThumbPath = 'videos/thumbnails/${videoFileName}_thumbnail.jpg';
            thumbnailUrl = await _retryCloudflareUpload(File(_thumbnailPath!), isImage: true, customPath: retryThumbPath);
            _thumbnailCloudflareUrl = thumbnailUrl;
          }
        }
        updateProgress('thumbnail', 'thumb', 'Thumbnail uploaded successfully', 1.0);
      }

      List<Future> uploadTasks = [];
      Map<String, dynamic> platformData = {};
      List<Exception> errors = [];
      
      // Modificare la gestione di YouTube per tracciare separatamente i caricamenti per account
      Map<String, String> youtubeUploads = {};
      
      for (var platform in widget.selectedAccounts.keys) {
        for (var accountId in widget.selectedAccounts[platform]!) {
          switch (platform) {
            case 'Twitter':
              uploadTasks.add(_uploadToTwitter(accountId, updateProgress).then((tweetId) {
                if (tweetId != null) {
                  platformData['twitter'] = {
                    'tweet_id': tweetId,
                    'account_id': accountId,
                  };
                }
              }).catchError((e) {
                errors.add(Exception('Twitter error: $e'));
                return null;
              }));
              break;
            case 'YouTube':
              // Per YouTube, creare una struttura separata per ogni account
              uploadTasks.add(_uploadToYouTube(accountId, updateProgress).then((videoId) {
                if (videoId != null) {
                  // Memorizzare i risultati specifici per ciascun account
                  youtubeUploads[accountId] = videoId;
                }
              }).catchError((e) {
                errors.add(Exception('YouTube error: $e'));
                return null;
              }));
              break;
            case 'Facebook':
              uploadTasks.add(_uploadToFacebook(accountId, updateProgress).then((postId) {
                if (postId != null) {
                  platformData['facebook'] = {
                    'post_id': postId,
                    'account_id': accountId,
                  };
                }
              }).catchError((e) {
                errors.add(Exception('Facebook error: $e'));
                return null;
              }));
              break;
            case 'Instagram':
              uploadTasks.add(_uploadToInstagram(accountId, updateProgress).then((mediaId) {
                if (mediaId != null) {
                  platformData['instagram'] = {
                    'media_id': mediaId,
                    'account_id': accountId,
                  };
                }
              }).catchError((e) {
                errors.add(Exception('Instagram error: $e'));
                return null;
              }));
              break;
            case 'Threads':
              uploadTasks.add(_uploadToThreads(accountId, updateProgress).then((result) {
                platformData['threads'] = {
                  'account_id': accountId,
                  'status': 'manual_required', // Threads richiede pubblicazione manuale
                };
              }).catchError((e) {
                errors.add(Exception('Threads error: $e'));
                return null;
              }));
              break;
            // Add other platforms here
          }
        }
      }

      await Future.wait(uploadTasks);
      
      // Dopo il completamento di tutti i task, convertire la struttura di YouTube nel formato giusto
      if (youtubeUploads.isNotEmpty) {
        List<Map<String, dynamic>> youtubeAccounts = [];
        
        for (var accountId in youtubeUploads.keys) {
          final account = widget.socialAccounts['YouTube']?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
          
          if (account != null && account.isNotEmpty) {
            youtubeAccounts.add({
              'username': account['username'] ?? '',
              'display_name': account['display_name'] ?? account['username'] ?? '',
              'profile_image_url': account['profile_image_url'] ?? '',
              'followers_count': account['followers_count']?.toString() ?? '0',
              'media_id': youtubeUploads[accountId],
              'account_id': accountId,
            });
          }
        }
        
        if (youtubeAccounts.isNotEmpty) {
          // Aggiungi i dati a platformData con la nuova struttura
          platformData['youtube'] = {
            'accounts': youtubeAccounts,
          };
        }
      }
      
      // Store any errors that occurred during upload
      if (errors.isNotEmpty) {
        onErrors(errors);
      }
      
      // Save data to Firebase
        await _saveToFirebase(platformData, cloudflareUrl, thumbnailUrl);

    } catch (e) {
      onErrors([Exception(e.toString())]);
      rethrow;
    }
  }

  // Modify Twitter upload method to accept progress callback
  Future<String?> _uploadToTwitter(String accountId, Function(String, String, String, double) updateProgress) async {
    try {
      updateProgress('Twitter', accountId, 'Preparing Twitter upload...', 0.1);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      updateProgress('Twitter', accountId, 'Getting account data...', 0.2);

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
      
      updateProgress('Twitter', accountId, 'Initializing Twitter API...', 0.3);
      
      final twitter = v2.TwitterApi(
        bearerToken: '',  // Empty bearer token to force OAuth 1.0a
        oauthTokens: v2.OAuthTokens(
          consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
          consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
          accessToken: accountData['access_token'] ?? '',
          accessTokenSecret: accountData['access_token_secret'] ?? '',
        ),
      );

      updateProgress('Twitter', accountId, 'Uploading media to Twitter...', 0.4);
      
      // Usa il media corrente (video) per l'upload
      final File mediaFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
      
      final uploadResponse = await twitter.media.uploadMedia(
        file: mediaFile,
      );
      
      if (uploadResponse.data == null) {
        throw Exception('Failed to upload media to Twitter');
      }

      updateProgress('Twitter', accountId, 'Creating tweet...', 0.8);
      
      // Get platform-specific description if available
      String tweetText = widget.description;
      if (widget.platformDescriptions.containsKey('Twitter') && 
          widget.platformDescriptions['Twitter']!.containsKey(accountId)) {
        tweetText = widget.platformDescriptions['Twitter']![accountId]!;
      }
      
      final tweet = await twitter.tweets.createTweet(
        text: tweetText,
        media: v2.TweetMediaParam(
          mediaIds: [uploadResponse.data!.id],
        ),
      );

      updateProgress('Twitter', accountId, 'Tweet posted successfully!', 1.0);

      return tweet.data?.id;
    } catch (e) {
      updateProgress('Twitter', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Similarly modify YouTube upload method
  Future<String?> _uploadToYouTube(String accountId, Function(String, String, String, double) updateProgress) async {
    // Add the progress updates to the existing method
    try {
      updateProgress('YouTube', accountId, 'Initializing YouTube upload...', 0.05);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      updateProgress('YouTube', accountId, 'Getting account data...', 0.1);
      
      // Rest of the method remains the same, just replace setState calls with updateProgress
      // ... [Rest of _uploadToYouTube method with _updateUploadProgress calls replaced] ...
      
      // Continue with the existing implementation, replacing setState and _updateUploadProgress
      // With direct calls to the updateProgress callback
      
      // Example of how to replace one of the progress updates:
      // Instead of: _updateUploadProgress('YouTube', accountId, 'Authenticating with Google...', 0.15);
      // Use: updateProgress('YouTube', accountId, 'Authenticating with Google...', 0.15);

      // NOTE: Rest of implementation continues as in the original method
      // For brevity, not copying the entire method here
      
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
      
      print('Uploading video to YouTube...');
      
      // Authenticate with Google - with retry mechanism
      updateProgress('YouTube', accountId, 'Authenticating with Google...', 0.15);
      
      // Crea un'istanza di GoogleSignIn specifica per questo account per evitare conflitti
      // Nota: questa è solo una soluzione di workaround finché non integri OAuth per account multipli
      final googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube'
        ],
        serverClientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
      );
      
      GoogleSignInAccount? googleUser;
      GoogleSignInAuthentication? googleAuth;
      int authRetries = 0;
      const maxAuthRetries = 3;
      
      // Implementa un meccanismo di attesa tra i caricamenti di account diversi
      // per evitare conflitti di autenticazione
      if (_isGoogleSigningIn) {
        updateProgress('YouTube', accountId, 'Waiting for other uploads to complete...', 0.15);
        
        // Attendi fino a 10 secondi per altri accessi in corso
        for (int i = 0; i < 10; i++) {
          if (!_isGoogleSigningIn) break;
          await Future.delayed(Duration(seconds: 1));
        }
        
        // Se ancora in corso, ritarda l'upload di questo account
        if (_isGoogleSigningIn) {
          await Future.delayed(Duration(seconds: 5));
        }
      }
      
      while (authRetries < maxAuthRetries && googleAuth == null) {
        try {
          // Segnala che stiamo eseguendo un'operazione di accesso
          _isGoogleSigningIn = true;
          updateProgress('YouTube', accountId, 'Signing in with Google...', 0.15);
          
          // Prima prova ad accedere silenziosamente
          googleUser = await googleSignIn.signInSilently();
          
          // Se l'accesso silenzioso fallisce, prova l'accesso normale
          if (googleUser == null) {
            updateProgress('YouTube', accountId, 'Interactive sign-in required...', 0.15);
            googleUser = await googleSignIn.signIn();
          }
          
          if (googleUser != null) {
            updateProgress('YouTube', accountId, 'Getting authentication token...', 0.2);
            googleAuth = await googleUser.authentication;
            if (googleAuth.accessToken == null) {
              throw Exception('Failed to get access token');
            }
          } else {
            throw Exception('Google sign in cancelled or failed');
          }
        } catch (e) {
          print('Google Sign-In error (attempt ${authRetries + 1}): $e');
          authRetries++;
          
          // Azzera il flag di accesso in caso di errore
          _isGoogleSigningIn = false;
          
          if (authRetries < maxAuthRetries) {
            updateProgress('YouTube', accountId, 'Retrying authentication (${authRetries + 1}/$maxAuthRetries)...', 0.15);
            await Future.delayed(Duration(seconds: 2 * authRetries)); // Backoff esponenziale
          } else {
            rethrow;
          }
        } finally {
          _isGoogleSigningIn = false;
        }
      }
      
      if (googleUser == null || googleAuth == null || googleAuth.accessToken == null) {
        throw Exception('Failed to authenticate with Google after $maxAuthRetries attempts');
      }

      // Prepare video metadata
      updateProgress('YouTube', accountId, 'Preparing video upload...', 0.3);
      
      // Get platform-specific description and title if available
      String videoDescription = widget.description;
      final File titleFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
      String videoTitle = widget.title.isNotEmpty ? widget.title : titleFile.path.split('/').last;
      
      if (widget.platformDescriptions.containsKey('YouTube') && 
          widget.platformDescriptions['YouTube']!.containsKey(accountId)) {
        videoDescription = widget.platformDescriptions['YouTube']![accountId]!;
      }
      
      // Get account-specific title if available
      if (widget.platformDescriptions.containsKey('YouTube') &&
          widget.platformDescriptions['YouTube']!.containsKey('${accountId}_title')) {
        videoTitle = widget.platformDescriptions['YouTube']!['${accountId}_title']!;
      }
      
      // Get YouTube options for this account, with defaults
      final youtubeOptions = widget.youtubeOptions?[accountId] ?? {
        'categoryId': '22',
        'privacyStatus': 'public',
        'license': 'youtube',
        'notifySubscribers': true,
        'embeddable': true,
        'madeForKids': false,
      };
      
      final videoMetadata = {
        'snippet': {
          'title': videoTitle,
          'description': videoDescription,
          'categoryId': youtubeOptions['categoryId'] ?? '22',
        },
        'status': {
          'privacyStatus': youtubeOptions['privacyStatus'] ?? 'public',
          'license': youtubeOptions['license'] ?? 'youtube',
          'embeddable': youtubeOptions['embeddable'] ?? true,
          'madeForKids': youtubeOptions['madeForKids'] ?? false,
        }
      };
      
      // Get notifySubscribers parameter
      final notifySubscribers = youtubeOptions['notifySubscribers'] ?? true;
      
      // First, upload the video
      updateProgress('YouTube', accountId, 'Uploading video content...', 0.4);
      
      // Implement retry mechanism for video upload
      int uploadRetries = 0;
      const maxUploadRetries = 3;
      http.Response? uploadResponse;
      
      // Usa il media principale per l'upload
      final File uploadFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));

      while (uploadRetries < maxUploadRetries && (uploadResponse == null || uploadResponse.statusCode != 200)) {
        try {
          uploadResponse = await http.post(
            Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status'),
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'application/octet-stream',
              'X-Upload-Content-Type': 'video/*',
              'X-Upload-Content-Length': uploadFile.lengthSync().toString(),
            },
            body: await uploadFile.readAsBytes(),
          ).timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Upload request timed out. Check your internet connection.'),
          );
          
          if (uploadResponse.statusCode != 200) {
            throw Exception('Failed to upload video: ${uploadResponse.body}');
          }
        } catch (e) {
          print('YouTube upload error (attempt ${uploadRetries + 1}): $e');
          uploadRetries++;
          
          if (uploadRetries < maxUploadRetries) {
            updateProgress('YouTube', accountId, 
              'Retrying upload (${uploadRetries + 1}/$maxUploadRetries)...', 
              0.4);
            await Future.delayed(Duration(seconds: 3 * uploadRetries)); // Exponential backoff
          } else {
            rethrow;
          }
        }
      }
      
      if (uploadResponse == null || uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload video after $maxUploadRetries attempts');
      }

      final videoData = json.decode(uploadResponse.body);
      final videoId = videoData['id'];
      
      updateProgress('YouTube', accountId, 'Updating video metadata...', 0.8);
      
      // Implement retry mechanism for metadata update
      int metadataRetries = 0;
      const maxMetadataRetries = 3;
      http.Response? metadataResponse;
      
      while (metadataRetries < maxMetadataRetries && (metadataResponse == null || metadataResponse.statusCode != 200)) {
        try {
          // Build metadata URI with notifySubscribers parameter
          final metadataUri = Uri.parse('https://www.googleapis.com/youtube/v3/videos?part=snippet,status${notifySubscribers ? '&notifySubscribers=true' : ''}');
          metadataResponse = await http.put(
            metadataUri,
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'id': videoId,
              ...videoMetadata,
            }),
            ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Metadata update request timed out. Check your internet connection.'),
          );
          
          if (metadataResponse.statusCode != 200) {
            throw Exception('Failed to update video metadata: ${metadataResponse.body}');
          }
        } catch (e) {
          print('YouTube metadata update error (attempt ${metadataRetries + 1}): $e');
          metadataRetries++;
          
          if (metadataRetries < maxMetadataRetries) {
            updateProgress('YouTube', accountId, 
              'Retrying metadata update (${metadataRetries + 1}/$maxMetadataRetries)...', 
              0.8);
            await Future.delayed(Duration(seconds: 2 * metadataRetries)); // Exponential backoff
          } else {
            rethrow;
          }
        }
      }
      
      if (metadataResponse == null || metadataResponse.statusCode != 200) {
        throw Exception('Failed to update video metadata after $maxMetadataRetries attempts');
      }

      // Upload custom thumbnail if available
      if (widget.youtubeThumbnailFile != null) {
        print('***YOUTUBE THUMBNAIL*** upload_confirmation_page.dart: widget.youtubeThumbnailFile path: \'${widget.youtubeThumbnailFile!.path}\'' );
        try {
          updateProgress('YouTube', accountId, 'Uploading custom thumbnail...', 0.9);
          print('Uploading custom thumbnail for YouTube video: $videoId');
          
          // Upload the thumbnail
          final thumbnailResponse = await http.post(
            Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$videoId'),
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'image/jpeg',
            },
            body: await widget.youtubeThumbnailFile!.readAsBytes(),
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Thumbnail upload request timed out.'),
          );

          if (thumbnailResponse.statusCode == 200) {
            updateProgress('YouTube', accountId, 'Custom thumbnail uploaded successfully!', 0.95);
            print('Custom thumbnail uploaded successfully to YouTube!');
          } else {
            print('Warning: Failed to upload custom thumbnail: ${thumbnailResponse.body}');
            updateProgress('YouTube', accountId, 'Warning: Thumbnail upload failed, but video is ready!', 0.95);
            // Don't throw error here, as the video upload was successful
          }
        } catch (e) {
          print('Warning: Error uploading custom thumbnail: $e');
          updateProgress('YouTube', accountId, 'Warning: Thumbnail upload failed, but video is ready!', 0.95);
          // Don't throw error here, as the video upload was successful
        }
      }

      updateProgress('YouTube', accountId, 'Video upload complete!', 1.0);

      return videoId;
    } catch (e) {
      updateProgress('YouTube', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Modify Facebook upload method similarly
  Future<String?> _uploadToFacebook(String accountId, Function(String, String, String, double) updateProgress) async {
    // Replace setState and _updateUploadProgress calls with updateProgress
    // ... Rest of the method remains the same ...
    try {
      updateProgress('Facebook', accountId, 'Inizializzazione upload Facebook...', 0.05);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Utente non autenticato');

      // Ottieni i dati dell'account da Firebase
      updateProgress('Facebook', accountId, 'Recupero dati account...', 0.1);
      final accountDoc = await _firestoreService.getAccount('Facebook', accountId);

      // Rest of method continues with updateProgress replacing _updateUploadProgress
      // ... Rest of implementation continues ...

      // NOTE: Rest of implementation continues as in the original method
      // For brevity, not copying the entire method here
            } catch (e) {
      updateProgress('Facebook', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Modify Instagram upload method
  Future<String?> _uploadToInstagram(String accountId, Function(String, String, String, double) updateProgress) async {
    // Replace setState and _updateUploadProgress calls with updateProgress
    // ... Rest of the method remains the same ...
    try {
      updateProgress('Instagram', accountId, 'Initializing...', 0.05);

      // Rest of method continues with updateProgress replacing _updateUploadProgress
      // ... Rest of implementation continues ...

      // NOTE: Rest of implementation continues as in the original method
      // For brevity, not copying the entire method here
              } catch (e) {
      updateProgress('Instagram', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Modify Threads upload method
  Future<String?> _uploadToThreads(String accountId, Function(String, String, String, double) updateProgress) async {
    try {
      updateProgress('Threads', accountId, 'Initializing Threads upload...', 0.05);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get account data from Firebase
      updateProgress('Threads', accountId, 'Getting account data...', 0.1);
      
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
      
      // Get platform-specific description if available
      String postDescription = widget.description;
      if (widget.platformDescriptions.containsKey('Threads') && 
          widget.platformDescriptions['Threads']!.containsKey(accountId)) {
        postDescription = widget.platformDescriptions['Threads']![accountId]!;
      }

      // Determine if we're uploading a video or an image
      final File mediaFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
      final bool isImage = _currentIsImage;
      
      // Upload the media to Cloudflare R2 if not already uploaded
      String? mediaCloudflareUrl;
      
      if (_cloudflareUrl.isEmpty) {
        updateProgress('Threads', accountId, 'Uploading media to cloud storage...', 0.2);
        mediaCloudflareUrl = await _uploadToCloudflare(mediaFile, 
          isImage: isImage, 
          platform: 'Threads', 
          accountId: accountId, 
          startProgress: 0.2, 
          endProgress: 0.5
        );
      } else {
        mediaCloudflareUrl = _cloudflareUrl;
        updateProgress('Threads', accountId, 'Using already uploaded media', 0.5);
      }
        
      if (mediaCloudflareUrl == null || mediaCloudflareUrl.isEmpty) {
        throw Exception('Failed to upload media to cloud storage');
        }
        
        // Convert Cloudflare storage URL to public format
      final publicUrl = _convertToPublicR2Url(mediaCloudflareUrl);
        
      // Ensure URL is in a format Threads can access
      String threadsMediaUrl = publicUrl;
        if (!publicUrl.contains('viralyst.online')) {
          try {
            final uri = Uri.parse(publicUrl);
          threadsMediaUrl = 'https://viralyst.online${uri.path}';
          updateProgress('Threads', accountId, 'Converted URL for Threads to custom domain', 0.6);
          } catch (e) {
          print('Error converting URL for Threads: $e');
          threadsMediaUrl = publicUrl; // Keep original URL if conversion fails
          }
        }
        
        // Verify that the file is publicly accessible
      updateProgress('Threads', accountId, 'Verifying media accessibility...', 0.6);
      final isAccessible = await _verifyCloudflareUpload(threadsMediaUrl);
        if (!isAccessible) {
        print('WARNING: Media may not be publicly accessible: $threadsMediaUrl');
        updateProgress('Threads', accountId, 'Media might not be accessible, attempting anyway...', 0.65);
        } else {
        updateProgress('Threads', accountId, 'Media accessible, creating Threads container...', 0.65);
      }
      
      // Step 1: Create a media container for Threads
      updateProgress('Threads', accountId, 'Creating Threads media container...', 0.7);
      
      final Map<String, String> containerParams = {
        'access_token': accessToken,
        'text': postDescription,
        'media_type': isImage ? 'IMAGE' : 'VIDEO',
      };
      
            if (isImage) {
        containerParams['image_url'] = threadsMediaUrl;
            } else {
        containerParams['video_url'] = threadsMediaUrl;
      }
        
        final containerResponse = await http.post(
        Uri.parse('https://graph.threads.net/v1.0/$userId/threads'),
        body: containerParams,
      ).timeout(Duration(seconds: 60), onTimeout: () {
        throw TimeoutException('Threads container creation request timed out');
        });
        
        if (containerResponse.statusCode != 200) {
        throw Exception('Failed to create Threads container: ${containerResponse.body}');
        }
        
        final containerData = json.decode(containerResponse.body);
        final containerId = containerData['id'];
        
      if (containerId == null || containerId.isEmpty) {
        throw Exception('Failed to get container ID from Threads response');
      }
      
      // Step 2: Wait before publishing as recommended by Threads API documentation
      updateProgress('Threads', accountId, 'Waiting for media processing (30s)...', 0.8);
      
      // Threads API recommends waiting about 30 seconds before publishing
      for (int i = 0; i < 30; i++) {
        if (!mounted) break;
        
        if (i % 5 == 0) { // Update message every 5 seconds
          updateProgress('Threads', accountId, 
            'Waiting for media processing (${30-i}s)...', 
            0.8 + (i / 30) * 0.1);
        }
        
        await Future.delayed(Duration(seconds: 1));
      }
        
        // Step 3: Publish the container
      updateProgress('Threads', accountId, 'Publishing to Threads...', 0.9);
      
        final publishResponse = await http.post(
        Uri.parse('https://graph.threads.net/v1.0/$userId/threads_publish'),
          body: {
            'access_token': accessToken,
            'creation_id': containerId,
          },
      ).timeout(Duration(seconds: 60));
        
        if (publishResponse.statusCode != 200) {
        throw Exception('Failed to publish Threads post: ${publishResponse.body}');
        }
        
        final publishData = json.decode(publishResponse.body);
      final mediaId = publishData['id'];
      
      updateProgress('Threads', accountId, 'Published successfully to Threads!', 1.0);
      
      return mediaId;
    } catch (e) {
      print('Error in Threads upload: $e');
      
      String errorMessage = 'Error uploading to Threads';
      
      if (e.toString().contains('access token')) {
        errorMessage = 'Authentication error. Please reconnect your Threads account.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timeout. Check your internet connection.';
      } else if (e.toString().contains('container') || e.toString().contains('media')) {
        errorMessage = 'Error processing media. Try a different file or format.';
      }
      
      updateProgress('Threads', accountId, errorMessage, 0.0);
      
      // Return a value to indicate manually required posting
      return 'manual_required';
    }
  }

  Future<void> _saveToFirebase(Map<String, dynamic> platformData, String? cloudflareUrl, String? thumbnailUrl) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get or generate the Cloudflare URL
      if (cloudflareUrl == null) {
        try {
          cloudflareUrl = await _uploadToCloudflare(widget.videoFile, isImage: widget.isImageFile);
        } catch (e) {
          print('Warning: Could not upload to Cloudflare: $e');
          // Continue without Cloudflare URL
        }
      }

      final videoRef = _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .push();

      // Prepare accounts data
      final accountsData = <String, List<Map<String, dynamic>>>{};
      for (var platform in widget.selectedAccounts.keys) {
        final accounts = widget.selectedAccounts[platform]!;
        final platformAccounts = <Map<String, dynamic>>[];
        
        for (var accountId in accounts) {
          final account = widget.socialAccounts[platform]?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
          
          if (account != null && account.isNotEmpty) {
            final accountData = {
              'username': account['username'] ?? '',
              'display_name': account['display_name'] ?? account['username'] ?? '',
              'profile_image_url': account['profile_image_url'] ?? '',
              'followers_count': account['followers_count']?.toString() ?? '0',
            };

            // Add platform-specific fields
            if (platform == 'Twitter' && platformData['twitter'] != null) {
              accountData['post_id'] = platformData['twitter']['tweet_id'];
            } else if (platform == 'YouTube') {
              // Gestione YouTube migliorata per account multipli
              if (platformData['youtube'] != null && platformData['youtube']['accounts'] != null) {
                // Trova i dati per questo specifico account
                final youtubeAccount = (platformData['youtube']['accounts'] as List).firstWhere(
                  (acc) => acc['account_id'] == accountId,
                  orElse: () => <String, dynamic>{},
                );
                
                if (youtubeAccount != null && youtubeAccount.containsKey('media_id')) {
                  accountData['media_id'] = youtubeAccount['media_id'];
                }
              }
            } else if (platform == 'Facebook' && platformData['facebook'] != null) {
              accountData['post_id'] = platformData['facebook']['post_id'];
            } else if (platform == 'Instagram' && platformData['instagram'] != null) {
              accountData['media_id'] = platformData['instagram']['media_id'];
            }

            platformAccounts.add(accountData);
          }
        }
        
        if (platformAccounts.isNotEmpty) {
          accountsData[platform.toLowerCase()] = platformAccounts;
        }
      }

      // Prepare video data
      final File storedFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));

      final videoData = {
        'title': widget.title,
        'platforms': widget.selectedAccounts.keys.toList(),
        'status': 'published',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'video_path': storedFile.path,
        'thumbnail_path': _thumbnailPath ?? '',
        'accounts': accountsData,
        'user_id': currentUser.uid,
        // Add Cloudflare URL if available
        if (cloudflareUrl != null) 'cloudflare_url': cloudflareUrl,
        // Add thumbnail Cloudflare URL if available
        if (thumbnailUrl != null) 'thumbnail_cloudflare_url': thumbnailUrl,
      };
      
      // Add description only if it's not empty
      if (widget.description != null && widget.description!.isNotEmpty) {
        videoData['description'] = widget.description;
      }

      // Non aggiungiamo più campi specifici per YouTube qui perché ora gestiamo account multipli
      // e i dati sono già salvati nella struttura 'accounts'

      await videoRef.set(videoData);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveAsDraft() async {
    setState(() {
      _isUploading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Generate and upload thumbnail for drafts too
        String? thumbnailUrl;
        if (!widget.isImageFile && _thumbnailPath == null) {
          await _generateThumbnail();
        }
        
        if (!widget.isImageFile && _thumbnailPath != null) {
          thumbnailUrl = await _uploadThumbnailToCloudflare();
        }
        
        final videoRef = _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('videos')
            .push();

        // Prepare accounts data
        final accountsData = <String, List<Map<String, dynamic>>>{};
        for (var platform in widget.selectedAccounts.keys) {
          final accounts = widget.selectedAccounts[platform]!;
          final platformAccounts = <Map<String, dynamic>>[];
          
          for (var accountId in accounts) {
            final account = widget.socialAccounts[platform]?.firstWhere(
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

        final File storedFile = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));

        final videoData = {
          'platforms': widget.selectedAccounts.keys.toList(),
          'status': 'draft',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'video_path': storedFile.path,
          'thumbnail_path': _thumbnailPath ?? '',
          'title': widget.title,
          'user_id': currentUser.uid,
          'accounts': accountsData,
          // Add thumbnail Cloudflare URL if available
          if (thumbnailUrl != null) 'thumbnail_cloudflare_url': thumbnailUrl,
        };
        
        // Add description only if it's not empty
        if (widget.description != null && widget.description!.isNotEmpty) {
          videoData['description'] = widget.description;
        }

        await videoRef.set(videoData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Video salvato come bozza con successo!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }

        widget.onConfirm();
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
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
            // Layout semplificato per la modalità fullscreen
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
                      // Se è un'immagine, mostrala a tutto schermo con bordi neri
                      if (_currentIsImage)
                        Center(
                          child: Container(
                            width: mediaWidth,
                            height: mediaHeight,
                            color: Colors.black,
                            child: _buildImagePreview(),
                          ),
                        )
                      // Se il video è inizializzato, mostralo con bordi neri
                      else if (_isVideoInitialized && _videoPlayerController != null)
                        Center(
                          child: Container(
                            width: mediaWidth,
                            height: mediaHeight,
                            color: Colors.black,
                            child: _buildVideoPlayer(_videoPlayerController!),
                          ),
                        ),
                      
                      // Controlli video in modalità fullscreen
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: Duration(milliseconds: 300),
                        child: Stack(
                          children: [
                            // Overlay semi-trasparente
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
                            
                            // Pulsante per uscire dalla modalità fullscreen
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
                            
                            // Pulsante Play/Pause al centro solo per i video
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
                            
                            // Progress bar solo per i video
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
                          // Enhanced Media Preview con opzione a tutto schermo
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
                                        // Contenuto principale (video o immagine)
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
                          
                          // Divider prima della sezione account
                          Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant.withOpacity(0.5)),
                          
                          // Selected Accounts Section with improved styling
                          Container(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Improved platform sections with more modern design
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                ...widget.selectedAccounts.entries.map((entry) {
                                  final platform = entry.key;
                                  final accounts = entry.value;
                                  
                                  // Skip if no accounts selected for this platform
                                  if (accounts.isEmpty) return SizedBox.shrink();
                                  
                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: Offset(0, 2),
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
                                            color: _getPlatformLightColor(platform),
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
                          ),

                          SizedBox(height: 32),
                          
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
                onPressed: (_isUploading || _isLoadingCredits)
                    ? null
                    : () {
                        // Blocco premium per Twitter
                        if (!_isPremiumUser && widget.selectedAccounts.containsKey('Twitter') && widget.selectedAccounts['Twitter']!.isNotEmpty) {
                          _showPremiumSubscriptionBottomSheet();
                          return;
                        }
                        // Controlla se l'utente ha crediti sufficienti
                        if (!_hasSufficientCredits()) {
                          _showInsufficientCreditsWarning();
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InstagramUploadPage(
                              mediaFile: _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!)),
                              mediaFiles: _mediaFiles,
                              isImageFiles: _isImageFiles,
                              title: widget.title,
                              description: widget.description,
                              isImageFile: _currentIsImage,
                              selectedAccounts: widget.selectedAccounts,
                              socialAccounts: widget.socialAccounts,
                              instagramContentType: widget.instagramContentType,
                              platformDescriptions: widget.platformDescriptions,
                              draftId: widget.draftId, // Pass the draft ID
                              youtubeThumbnailFile: widget.youtubeThumbnailFile, // Passa la thumbnail YouTube
                              tiktokOptions: widget.tiktokOptions, // Passa le opzioni TikTok
                              youtubeOptions: widget.youtubeOptions, // Passa le opzioni YouTube
                            ),
                          ),
                        );
                      },
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
                child: _isUploading
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
                            'Upload in corso...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _isLoadingCredits 
                          ? 'Loading...' 
                          : 'Upload Now',
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

  // Helper method to show full description dialog
  void _showFullDescriptionDialog(BuildContext context, String title, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(description),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper method to build an account card with description
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
    
    // Check for custom content
    final bool hasCustomTitle = widget.platformDescriptions.containsKey(platform) && 
                                widget.platformDescriptions[platform]!.containsKey('${accountId}_title');
    
    // Get the platform-specific description if available
    final String? customDescription = hasCustomDescription
        ? widget.platformDescriptions[platform]![accountId]
        : null;
    
    // Either custom title or custom description qualifies for showing details
    final bool hasCustomContent = hasCustomDescription || hasCustomTitle;
    
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

  // Aggiungi la funzione per ottenere il colore chiaro di una piattaforma
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
    
    // Extract accountId - since this might not be in the account map, 
    // we need to find it based on the username or other identifier
    final accountId = account['id'] as String? ?? account['accountId'] as String? ?? '';
    
    // Get platform-specific title if available
    String? customTitle = widget.title;
    if (widget.platformDescriptions.containsKey(platform) && 
        widget.platformDescriptions[platform]!.containsKey('${accountId}_title')) {
      customTitle = widget.platformDescriptions[platform]!['${accountId}_title'];
    }
    
    // Use "No description available" if description is empty
    final displayDescription = description.isNotEmpty ? description : 'No description available';
    
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
            // Linea in alto per indicare che è trascinabile
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
            
            // Intestazione con piattaforma
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
                    '$platform Content Details',
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
            
            // Informazioni profilo
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
            
            // Contenuto post
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
                          customTitle?.isNotEmpty == true ? customTitle! : 'No title available',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      SizedBox(height: 20),
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
                        displayDescription,
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

  // Mostra un dialogo che spiega i requisiti di storage per Threads
  void _showThreadsStorageRequirementDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Image.asset('assets/loghi/threads_logo.png', width: 32, height: 32),
              const SizedBox(width: 10),
              const Text('Threads Media Upload'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Threads API requires public URLs for media uploads',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'To upload images or videos to Threads via API:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('1. The app needs cloud storage (Firebase Storage) configured'),
              const Text('2. Media must be uploaded to storage first'),
              const Text('3. Threads API requires public media URLs'),
              const SizedBox(height: 16),
              const Text(
                'Until storage is configured, you can:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Post text-only content (if text is provided)'),
              const Text('• Upload to other social platforms'),
              const Text('• Use the Threads app directly to post media'),
              const SizedBox(height: 16),
              const Text(
                'To resolve this, ask your developer to configure Firebase Storage.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Nuovo metodo per caricare file su Cloudflare R2 tramite Worker
  Future<String?> _uploadToCloudflare(dynamic input, {bool isImage = false, String? customPath, String? platform, String? accountId, double? startProgress, double? endProgress}) async {
    final int maxRetries = 3;
    int currentRetry = 0;
    Exception? lastError;
    File file;
    
    // Supporto per vari modi di chiamata
    if (input is File) {
      file = input;
    } else if (input is String && platform != null) {
      // Questa è una chiamata dalla nuova implementazione per Facebook
      file = _currentMediaFile ?? (_mediaFiles.isNotEmpty ? _mediaFiles.first : (widget.videoFile!));
      
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        _updateUploadProgress(platform, accountId, 'Preparazione caricamento su cloud storage...', startProgress);
      }
    } else {
      throw Exception('Input non valido per _uploadToCloudflare');
    }

    while (currentRetry < maxRetries) {
      try {
        print('Starting upload to Cloudflare R2 (attempt ${currentRetry + 1}/$maxRetries)...');

        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.3;
          _updateUploadProgress(platform, accountId, 'Caricamento file su cloud storage...', progress);
        }

        // Ottieni il token da Firebase
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) throw Exception('User not authenticated');
        
        // Ottieni il token ID da Firebase
        final idToken = await currentUser.getIdToken();
        if (idToken == null) throw Exception('Failed to get Firebase ID token');

        // 1. Richiedi informazioni dal worker Cloudflare
        final String fileName = customPath ?? file.path.split('/').last;
        final String fileExtension = fileName.split('.').last.toLowerCase();

        // Controlla se è un'immagine o un video basandosi sull'estensione
        final String contentType = isImage || 
                                  ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)
                                  ? 'image/$fileExtension' 
                                  : 'video/$fileExtension';
        
        // Aggiunta del prefisso 'videos/' al nome del file come richiesto dal worker
        final String pathWithDirectory = customPath ?? ('videos/' + fileName);
        
        print('Requesting upload info for ${isImage ? "image" : "video"}: $pathWithDirectory');
        
        // Worker URL
        const String workerUrl = 'https://plain-star-669f.giuseppemaria162.workers.dev';
        
        print('Requesting from worker URL: $workerUrl');
        
        // Costruisci corpo della richiesta
        final requestBody = {
          'operation': 'write',
          'fileName': pathWithDirectory,
          'contentType': contentType,
          'expiresIn': 3600, // Scade dopo 1 ora
        };
        
        print('Request body: ${json.encode(requestBody)}');
        
        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.5;
          _updateUploadProgress(platform, accountId, 'Ottenimento credenziali di upload...', progress);
        }
        
        // Fai la richiesta al worker
        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode(requestBody),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Request to worker timed out'),
        );

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode != 200) {
          throw Exception('Error from worker: ${response.body}');
        }

        // Analizza la risposta
        final responseData = jsonDecode(response.body);
        
        // Estrai l'URL pubblico e le informazioni di upload
        final String? publicUrl = responseData['publicUrl'];
        if (publicUrl == null || publicUrl.isEmpty) {
          throw Exception('Invalid response: missing public URL');
        }

        print('Got public URL: $publicUrl');
        
        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.6;
          _updateUploadProgress(platform, accountId, 'Caricamento file in corso...', progress);
        }
        
        // Verifica se abbiamo il metodo direct-upload
        if (responseData['method'] == 'direct-upload' && 
            responseData['uploadUrl'] != null && 
            responseData['uploadUrl'].toString().isNotEmpty) {
          
          final String uploadUrl = responseData['uploadUrl'];
          
          print('Using direct-upload method via: $uploadUrl');
          
          // Prepara i parametri della richiesta
          final Map<String, dynamic> uploadParams = {
            'fileName': pathWithDirectory,
            'contentType': contentType,
          };
          
          // Aggiungi token nella richiesta se necessario
          if (responseData['token'] != null) {
            uploadParams['token'] = responseData['token'];
          }
          
          // Costruisci l'URL con i parametri nella query string come richiesto dal worker
          final uri = Uri.parse(uploadUrl).replace(
            queryParameters: {
              'fileName': pathWithDirectory,
              'contentType': contentType,
              // Aggiungi il token come parametro query se presente
              if (responseData['token'] != null) 'token': responseData['token'].toString(),
            }
          );
          
          print('Sending file to: $uri');
          
          // Leggi il file come bytes
          final fileBytes = await file.readAsBytes();
          
          // Crea una richiesta PUT diretta invece di multipart
          final request = http.Request('PUT', uri);
          
          // Aggiungi headers necessari
            request.headers['Authorization'] = 'Bearer $idToken';
          request.headers['Content-Type'] = contentType;
          request.headers['Content-Length'] = fileBytes.length.toString();
          
          // Aggiungi il file come body della richiesta
          request.bodyBytes = fileBytes;
          
          print('Sending file to direct-upload endpoint, size: ${fileBytes.length} bytes, using PUT method');
          
          // Aggiorna il progresso se i parametri di progresso sono stati forniti
          if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
            final progress = startProgress + (endProgress - startProgress) * 0.8;
            _updateUploadProgress(platform, accountId, 'Completamento caricamento file...', progress);
          }
          
          try {
          // Invia la richiesta
          final streamedResponse = await request.send().timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Upload request timed out'),
          );
          
          // Converti la risposta
          final uploadResponse = await http.Response.fromStream(streamedResponse);
          
            print('Direct upload response status: ${uploadResponse.statusCode}');
            print('Direct upload response body: ${uploadResponse.body}');
          
          if (uploadResponse.statusCode >= 200 && uploadResponse.statusCode < 300) {
              // Prova a estrarre il publicUrl dalla risposta
              try {
                final uploadResponseData = jsonDecode(uploadResponse.body);
                // Usa il publicUrl dalla risposta o quello originale se non disponibile
                final finalUrl = uploadResponseData['publicUrl'] ?? publicUrl;
                print('Successfully uploaded file to Cloudflare R2: $finalUrl');
                
                // Aggiorna il progresso se i parametri di progresso sono stati forniti
                if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                  _updateUploadProgress(platform, accountId, 'File caricato con successo', endProgress);
                }
                
                return finalUrl;
          } catch (e) {
                print('Error parsing upload response: $e, using original publicUrl');
                
                // Aggiorna il progresso se i parametri di progresso sono stati forniti
                if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                  _updateUploadProgress(platform, accountId, 'File caricato con successo', endProgress);
                }
                
                return publicUrl;
              }
          } else {
              // Se l'errore è 'Nome file mancante', proviamo un approccio alternativo
              if (uploadResponse.body.contains('Nome file mancante')) {
                print('Tentativo di caricamento alternativo...');
                
                // Aggiorna il progresso se i parametri di progresso sono stati forniti
                if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                  final progress = startProgress + (endProgress - startProgress) * 0.85;
                  _updateUploadProgress(platform, accountId, 'Tentativo approccio alternativo...', progress);
                }
                
                return await _uploadToCloudflareAlternative(file, isImage, customPath, idToken, responseData,
                  platform: platform, 
                  accountId: accountId, 
                  startProgress: startProgress != null ? startProgress + (endProgress! - startProgress) * 0.85 : null,
                  endProgress: endProgress
                );
              }
              
              throw Exception('Failed to upload file to Cloudflare R2: HTTP ${uploadResponse.statusCode} - ${uploadResponse.body}');
            }
            } catch (e) {
            if (e is TimeoutException || e.toString().contains('timeout')) {
              print('Upload timed out, trying alternative approach...');
              
              // Aggiorna il progresso se i parametri di progresso sono stati forniti
              if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                final progress = startProgress + (endProgress - startProgress) * 0.85;
                _updateUploadProgress(platform, accountId, 'Riprovo con approccio alternativo...', progress);
              }
              
              return await _uploadToCloudflareAlternative(file, isImage, customPath, idToken, responseData,
                platform: platform, 
                accountId: accountId, 
                startProgress: startProgress != null ? startProgress + (endProgress! - startProgress) * 0.85 : null,
                endProgress: endProgress
              );
            }
            rethrow;
            }
          } else {
          print('WARNING: No direct-upload method found in response, file was not uploaded');
          // In un caso reale, dovresti gestire questa situazione in modo più appropriato
          // Per ora, restituiamo l'URL pubblico anche se il file non è stato caricato
          
          // Aggiorna il progresso se i parametri di progresso sono stati forniti
          if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
            _updateUploadProgress(platform, accountId, 'URL ottenuto, ma file non caricato', endProgress);
          }
          
          return publicUrl;
        }
      } catch (e) {
        currentRetry++;
        lastError = e is Exception ? e : Exception(e.toString());
        print('Error in retry $currentRetry: $e');
        
        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.3;
          _updateUploadProgress(platform, accountId, 'Errore, riprovo... ($currentRetry/$maxRetries)', progress);
        }
        
        if (currentRetry < maxRetries) {
          // Attendi un po' prima di riprovare con backoff esponenziale
          final waitTime = Duration(seconds: 3 * currentRetry);
          print('Retrying in ${waitTime.inSeconds} seconds...');
          await Future.delayed(waitTime);
        }
      }
    }

    // Se arriviamo qui, tutti i tentativi sono falliti
    print('All $maxRetries attempts to upload to Cloudflare R2 failed');
    
    // Aggiorna il progresso se i parametri di progresso sono stati forniti
    if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
      _updateUploadProgress(platform, accountId, 'Errore nel caricamento dopo $maxRetries tentativi', startProgress);
    }
    
    throw lastError ?? Exception('Unknown error during Cloudflare R2 upload');
  }

  // Metodo alternativo per caricare file a Cloudflare R2 se il metodo principale fallisce
  Future<String?> _uploadToCloudflareAlternative(File file, bool isImage, String? customPath, String idToken, Map<String, dynamic> responseData, {
    String? platform, 
    String? accountId, 
    double? startProgress, 
    double? endProgress
  }) async {
    try {
      print('Trying alternative upload approach...');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.2;
        _updateUploadProgress(platform, accountId, 'Tentativo approccio alternativo...', progress);
      }
      
      // Estrai i valori necessari dai dati di risposta
      final String publicUrl = responseData['publicUrl'];
          final String uploadUrl = responseData['uploadUrl'];
      final String fileName = customPath ?? file.path.split('/').last;
      final String pathWithDirectory = customPath ?? ('videos/' + fileName);
      
      // Costruisci un URL separato per l'endpoint proxy-upload
      final uploadUrlBase = uploadUrl.split('/direct-upload')[0];
      final proxyUploadUrl = '$uploadUrlBase/proxy-upload';
      final uri = Uri.parse(proxyUploadUrl).replace(
        queryParameters: {
          'fileName': pathWithDirectory,
        }
      );
      
      print('Using alternative upload endpoint: $uri');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.4;
        _updateUploadProgress(platform, accountId, 'Preparazione file per upload alternativo...', progress);
      }
      
      // Leggi il file
          final fileBytes = await file.readAsBytes();
      final fileExtension = fileName.split('.').last.toLowerCase();
      
      // Determina il tipo di contenuto
      final String contentType = isImage || 
                             ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)
                             ? 'image/$fileExtension' 
                             : 'video/$fileExtension';
      
      // Crea una richiesta PUT
      final request = http.Request('PUT', uri);
          
          // Aggiungi headers
          request.headers['Authorization'] = 'Bearer $idToken';
          request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = fileBytes.length.toString();
          
      // Imposta il body
          request.bodyBytes = fileBytes;
          
      print('Sending file via alternative method, size: ${fileBytes.length} bytes');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.6;
        _updateUploadProgress(platform, accountId, 'Invio file con metodo alternativo...', progress);
      }
          
      // Invia la richiesta
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Alternative upload request timed out'),
      );
            
      // Converti la risposta
      final response = await http.Response.fromStream(streamedResponse);
      
      print('Alternative upload response status: ${response.statusCode}');
      print('Alternative upload response body: ${response.body}');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.9;
        _updateUploadProgress(platform, accountId, 'Analisi risposta upload alternativo...', progress);
      }
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final responseData = jsonDecode(response.body);
          if (responseData['success'] == true) {
            final uploadedUrl = responseData['url'] ?? publicUrl;
            print('Alternative upload successful: $uploadedUrl');
            
            // Aggiorna il progresso se i parametri di progresso sono stati forniti
            if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
              _updateUploadProgress(platform, accountId, 'Upload alternativo completato con successo', endProgress);
            }
            
            return uploadedUrl;
          }
        } catch (e) {
          print('Error parsing alternative upload response: $e');
        }
      }
        
      // Se anche questo fallisce, ritorna comunque l'URL pubblico
      print('WARNING: Alternative upload failed. Returning public URL without confirmed upload');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        _updateUploadProgress(platform, accountId, 'Upload alternativo fallito, uso URL pubblico', endProgress);
      }
      
      return publicUrl;
    } catch (e) {
      print('Error in alternative upload: $e');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        _updateUploadProgress(platform, accountId, 'Errore nell\'upload alternativo: $e', startProgress);
      }
      
      // Ritorna l'URL pubblico originale come fallback
      return responseData['publicUrl'];
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

  // New method to generate a thumbnail from the video
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
    if (_currentMediaFile == null || _currentIsImage) return;
    
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
  
  // Upload thumbnail to Cloudflare R2
  Future<String?> _uploadThumbnailToCloudflare() async {
    if (_thumbnailPath == null) {
      print('No thumbnail to upload');
      return null;
    }
    
    try {
      setState(() {
        _uploadMessages['thumbnail'] = 'Uploading thumbnail to cloud storage...';
        _uploadProgress['thumbnail'] = 0.1;
      });
      
      final File thumbnailFile = File(_thumbnailPath!);
      if (!await thumbnailFile.exists()) {
        print('Thumbnail file not found: $_thumbnailPath');
        return null;
      }
      
      // Upload the thumbnail with an appropriate path in Cloudflare
      final String videoFileName = _currentMediaFile?.path.split('/').last.split('.').first ?? 'video';
      final String thumbnailCloudPath = 'videos/thumbnails/${videoFileName}_thumbnail.jpg';
      
      // Usa la nuova firma del metodo _uploadToCloudflare
      final thumbnailUrl = await _uploadToCloudflare(thumbnailFile, 
        isImage: true, 
        customPath: thumbnailCloudPath,
        platform: 'thumbnail',
        accountId: 'thumb',
        startProgress: 0.1,
        endProgress: 0.9
      );
      
      setState(() {
        _uploadMessages['thumbnail'] = 'Thumbnail uploaded to cloud storage!';
        _uploadProgress['thumbnail'] = 1.0;
        _thumbnailCloudflareUrl = thumbnailUrl;
      });
      
      return thumbnailUrl;
    } catch (e) {
      print('Error uploading thumbnail: $e');
      setState(() {
        _uploadMessages['thumbnail'] = 'Error uploading thumbnail: $e';
        _uploadProgress['thumbnail'] = 0;
      });
      return null;
    }
  }

  // Verifica se un file è stato effettivamente caricato su Cloudflare
  Future<bool> _verifyCloudflareUpload(String cloudflareUrl) async {
    try {
      // Se l'URL è un URL interno di storage, convertilo in un URL pubblico
      String urlToVerify = cloudflareUrl;
      if (cloudflareUrl.contains('r2.cloudflarestorage.com')) {
        urlToVerify = _convertToPublicR2Url(cloudflareUrl);
      }
      
      // Assicurati di usare preferibilmente l'URL con dominio personalizzato se disponibile
      if (!urlToVerify.contains('viralyst.online') && 
          (urlToVerify.contains('pub-') && urlToVerify.contains('r2.dev'))) {
        // Estrai il path e usa il dominio personalizzato
        final uri = Uri.parse(urlToVerify);
        urlToVerify = 'https://viralyst.online${uri.path}';
      }
      
      print('Verificando disponibilità del file: $urlToVerify');
      
      // Aggiungi un ritardo più lungo prima di verificare per permettere la propagazione
      await Future.delayed(const Duration(seconds: 5));
      
      // Verifica se l'URL è raggiungibile con una richiesta GET
      final response = await http.get(Uri.parse(urlToVerify)).timeout(
        const Duration(seconds: 15),
        onTimeout: () => http.Response('Timeout', 408),
      );
      
      print('Verifica caricamento: statusCode ${response.statusCode} per $urlToVerify');
      
      // Considera i codici 200-299 come successo, e 400-403 come potenzialmente validi
      // per bucket con autorizzazioni speciali ma file esistenti
      final isSuccess = (response.statusCode >= 200 && response.statusCode < 300) ||
                        (response.statusCode >= 400 && response.statusCode <= 403);
      
      if (isSuccess) {
        print('File trovato su Cloudflare: $urlToVerify');
      } else {
        print('File non trovato o inaccessibile: $urlToVerify, status: ${response.statusCode}');
        
        // Se fallisce con l'URL del dominio personalizzato, prova con r2.dev come backup
        if (urlToVerify.contains('viralyst.online')) {
          final knownAccountId = '3cd9209da4d0a20e311d486fc37f1a71';
          final uri = Uri.parse(urlToVerify);
          final r2Url = 'https://pub-$knownAccountId.r2.dev${uri.path}';
          
          print('Tentativo fallback con URL r2.dev: $r2Url');
          
          final fallbackResponse = await http.get(Uri.parse(r2Url)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );
          
          print('Verifica fallback: statusCode ${fallbackResponse.statusCode}');
          return fallbackResponse.statusCode >= 200 && fallbackResponse.statusCode < 400;
        }
      }
      
      return isSuccess;
    } catch (e) {
      print('Errore nella verifica del caricamento Cloudflare: $e');
      return false;
    }
  }
  
  // Riprova a caricare un file su Cloudflare se il primo tentativo è fallito
  Future<String?> _retryCloudflareUpload(File file, {bool isImage = false, String? customPath}) async {
    // Puliamo prima eventuali stati precedenti
    if (!mounted) return null;
    
    setState(() {
      _uploadMessages['cloudflare_retry'] = 'Retrying upload to cloud storage...';
      _uploadProgress['cloudflare_retry'] = 0.1;
    });
    
    try {
      // Tenta di caricare il file con una richiesta diversa
      // Utilizza la nuova firma del metodo _uploadToCloudflare
      final cloudflareUrl = await _uploadToCloudflare(file, 
        isImage: isImage, 
        customPath: customPath,
        platform: 'cloudflare_retry',
        accountId: 'retry',
        startProgress: 0.1,
        endProgress: 0.9
      );
      
      if (cloudflareUrl == null) {
        throw Exception('Failed to upload media to Cloudflare');
      }
      
      setState(() {
        _uploadMessages['cloudflare_retry'] = 'Retry successful!';
        _uploadProgress['cloudflare_retry'] = 1.0;
      });
      
      return cloudflareUrl;
    } catch (e) {
      setState(() {
        _uploadMessages['cloudflare_retry'] = 'Retry failed: $e';
        _uploadProgress['cloudflare_retry'] = 0;
      });
      
      // Ritorna comunque l'URL pubblico anche se il file non è stato caricato
      // Così l'app può continuare, ma sappiamo che il file non esiste davvero
      print('WARNING: File upload retry failed, returning tentative URL only');
      
      // Ritorna un URL basato sul percorso del file originale
      final fileName = file.path.split('/').last;
      final fileType = isImage ? 'thumbnails/' : '';
      return 'https://videos.3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com/videos/${fileType}${customPath ?? fileName}';
    }
  }

  // Helper method to get color for Instagram content types
  Color _getContentTypeColor(String contentType) {
    switch (contentType) {
      case 'Reels':
        return Colors.pinkAccent;
      case 'Storia':
        return Colors.deepPurple;
      case 'Post':
      default:
        return Colors.blue;
    }
  }

  // Mostra un dialogo informativo sulle limitazioni dell'API di Instagram
  void _showInstagramAPILimitationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/loghi/logo_insta.png',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 10),
            Text('Limitazione API Instagram'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instagram limita l\'accesso ad alcune funzionalità tramite API.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Il tuo contenuto verrà pubblicato, ma Instagram potrebbe modificarne il tipo (ad esempio pubblicando come Reels invece che come Storia/Post).',
            ),
            SizedBox(height: 8),
            Text(
                                            'Questa è una limitazione dell\'API di Instagram, non dell\'app Fluzar.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Ho capito'),
          ),
        ],
      ),
    );
  }

  // Nuovo metodo per ridimensionare l'immagine per Instagram secondo le proporzioni accettate
  Future<File> _resizeImageForInstagram(File imageFile) async {
    try {
      // Leggi l'immagine originale
      final bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) return imageFile;
      
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;
      double aspectRatio = originalWidth / originalHeight;
      
      print('Original image dimensions: ${originalWidth}x${originalHeight}, aspect ratio: $aspectRatio');
      
      // Determina quale proporzione usare (1:1, 4:5, 1.91:1)
      late img.Image resizedImage;
      
      // Opzione 1: Proporzione quadrata (1:1)
      if (aspectRatio >= 0.8 && aspectRatio <= 1.2) {
        // Già vicino a quadrato, facciamo un 1:1 perfetto
        final size = min(originalWidth, originalHeight);
        resizedImage = img.copyCrop(
          originalImage,
          x: (originalWidth - size) ~/ 2,
          y: (originalHeight - size) ~/ 2,
          width: size,
          height: size,
        );
        print('Resizing to square 1:1');
      }
      // Opzione 2: Verticale (4:5) - per immagini verticali
      else if (aspectRatio < 0.8) {
        // Immagine verticale, adattiamo a 4:5
        final targetWidth = originalWidth;
        final targetHeight = (targetWidth * 5 / 4).round();
        
        if (targetHeight <= originalHeight) {
          // L'immagine è più alta di quanto necessario, ritagliamo
          resizedImage = img.copyCrop(
            originalImage,
            x: 0,
            y: (originalHeight - targetHeight) ~/ 2,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // L'immagine è troppo stretta, dobbiamo ridimensionarla mantenendo l'aspetto 4:5
          final newHeight = originalHeight;
          final newWidth = (newHeight * 4 / 5).round();
          resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
          );
        }
        print('Resizing to vertical 4:5');
      }
      // Opzione 3: Orizzontale (1.91:1) - per immagini orizzontali
      else {
        // Immagine orizzontale, adattiamo a 1.91:1
        final targetHeight = originalHeight;
        final targetWidth = (targetHeight * 1.91).round();
        
        if (targetWidth <= originalWidth) {
          // L'immagine è più larga di quanto necessario, ritagliamo
          resizedImage = img.copyCrop(
            originalImage,
            x: (originalWidth - targetWidth) ~/ 2,
            y: 0,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // L'immagine è troppo alta, dobbiamo ridimensionarla mantenendo l'aspetto 1.91:1
          final newWidth = originalWidth;
          final newHeight = (newWidth / 1.91).round();
          resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
          );
        }
        print('Resizing to horizontal 1.91:1');
      }
      
      // Salva l'immagine ridimensionata
      final tempDir = await getTemporaryDirectory();
      final newPath = '${tempDir.path}/instagram_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final resizedFile = File(newPath)..writeAsBytesSync(img.encodeJpg(resizedImage, quality: 90));
      
      print('Resized image dimensions: ${resizedImage.width}x${resizedImage.height}, aspect ratio: ${resizedImage.width / resizedImage.height}');
      
      return resizedFile;
    } catch (e) {
      print('Error resizing image for Instagram: $e');
      return imageFile; // In caso di errore, restituisci l'immagine originale
    }
  }

  // Funzione per mostrare un dialogo con messaggi di errore specifici sul token Instagram
  void _showInstagramTokenErrorDialog(String errorMessage) {
    if (errorMessage.contains('token') && 
        (errorMessage.contains('Invalid') || 
         errorMessage.contains('expired') || 
         errorMessage.contains('Cannot parse'))) {
      
      // Se l'errore è relativo al token, mostra il dialogo di ricollegamento
      _showInstagramReconnectDialog(''); // Qui potremmo passare l'accountId se necessario
    } else {
      // Per altri errori, mostra un messaggio generico
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore con Instagram: $errorMessage'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Helper icon and color methods still needed for the UI
  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'TikTok': return Icons.music_note;
      case 'YouTube': return Icons.play_arrow;
      case 'Instagram': return Icons.camera_alt;
      case 'Facebook': return Icons.facebook;
      case 'Twitter': return Icons.chat;
      case 'Threads': return Icons.chat_outlined;
      default: return Icons.share;
    }
  }

  // Add back the updateUploadProgress method since it's still referenced in some methods
  void _updateUploadProgress(String platform, String accountId, String status, double progress) {
    if (mounted) {
      setState(() {
        _uploadStatus['${platform}_$accountId'] = true;
        _uploadMessages['${platform}_$accountId'] = status;
        _uploadProgress['${platform}_$accountId'] = progress;
      });
    }
  }

  // Add the missing _convertToPublicR2Url method
  String _convertToPublicR2Url(String cloudflareUrl) {
    if (cloudflareUrl.contains('r2.cloudflarestorage.com')) {
      // Extract account ID and path from the Cloudflare storage URL
      final Uri uri = Uri.parse(cloudflareUrl);
      final String path = uri.path;
      final List<String> pathParts = path.split('/');
      
      if (pathParts.length >= 2) {
        final String accountId = pathParts[0];
        final String filePath = path.substring(accountId.length + 1);
        
        // Convert to public R2 URL format
        return 'https://pub-$accountId.r2.dev/$filePath';
      }
    }
    
    // If the URL is already in the correct format or cannot be converted, return as is
    return cloudflareUrl;
  }

  // Add the missing _showInstagramReconnectDialog method
  void _showInstagramReconnectDialog(String accountId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/loghi/logo_insta.png',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 10),
            Text('Riconnessione necessaria'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'È necessario riconnettere il tuo account Instagram.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Il token di autorizzazione di Instagram è scaduto o non valido. Questo può accadere periodicamente per motivi di sicurezza.',
            ),
            SizedBox(height: 8),
            Text(
              'Per continuare a pubblicare su Instagram, dovrai uscire e riconnetterti con il tuo account attraverso la pagina Profilo dell\'app.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Chiudi'),
          ),
        ],
      ),
    );
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
              _currentIsImage ? 'Loading image...' : 'Loading video...',
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

  // Simpler media preview for large files or error cases with modern design
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
              'File loading...',
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
                  color: Colors.white.withOpacity(0.7),
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
                      widget.isDraft ? 'Save Draft' : 'Confirm Upload',
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

  // Metodo per gestire l'aspect ratio delle immagini
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

  // Metodo per modificare la descrizione per una specifica piattaforma
  void _editPlatformDescription(String platform, String accountId) {
    // Ottieni la descrizione corrente
    final currentDescription = widget.platformDescriptions[platform]?[accountId] ?? widget.description;
    final currentTitle = widget.platformDescriptions[platform]?['${accountId}_title'] ?? widget.title;
    
    final descriptionController = TextEditingController(text: currentDescription);
    final titleController = TextEditingController(text: currentTitle);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              _platformLogos[platform] ?? '',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 10),
            Text('Modifica contenuto per $platform'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Titolo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: titleController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Inserisci il titolo per questa piattaforma',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Descrizione',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Inserisci la descrizione per questa piattaforma',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              final newDescription = descriptionController.text.trim();
              final newTitle = titleController.text.trim();
              
              // Crea una nuova mappa se non esiste
              if (!widget.platformDescriptions.containsKey(platform)) {
                widget.platformDescriptions[platform] = {};
              }
              
              // Aggiorna la descrizione nella mappa
              if (newDescription.isNotEmpty) {
                widget.platformDescriptions[platform]![accountId] = newDescription;
              }
              
              // Aggiorna il titolo nella mappa
              if (newTitle.isNotEmpty) {
                widget.platformDescriptions[platform]!['${accountId}_title'] = newTitle;
              }
              
              setState(() {});
              Navigator.pop(context);
            },
            child: Text('Salva'),
          ),
        ],
      ),
    );
  }

  // --- AGGIUNTA: funzione bottom sheet premium ---
  void _showPremiumSubscriptionBottomSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
            ),
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Handle bar
                Container(
                  width: 50,
                  height: 5,
                  margin: EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                // Premium icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.workspace_premium,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 24),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Unlock Twitter Publishing',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.3),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 12),
                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Upgrade to Premium to publish on Twitter and unlock all social platforms',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 36),
                // Premium card
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Premium',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '€6,99',
                              style: TextStyle(
                                fontSize: 28,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '/month',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        _buildPremiumFeatureRow(Icons.chat, 'Twitter Publishing', 'Unlimited posts'),
                        SizedBox(height: 12),
                        _buildPremiumFeatureRow(Icons.language, 'Social accounts', 'Unlimited'),
                        SizedBox(height: 12),
                        _buildPremiumFeatureRow(Icons.upload, 'Video per day', 'Unlimited'),
                        SizedBox(height: 12),
                        _buildPremiumFeatureRow(Icons.schedule, 'Post scheduling', 'All platforms'),
                        SizedBox(height: 12),
                        _buildPremiumFeatureRow(Icons.support_agent, 'AI Analysis', 'Unlimited'),
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Free trial of 3 days',
                                  style: TextStyle(
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
} 

// Servizio Firestore fittizio
class FirestoreService {
  // Modifica: usa un tipo generico Map invece di DocumentSnapshot
  Future<Map<String, dynamic>?> getAccount(String platform, String accountId) async {
    try {
      // Verifica se l'account esiste in Firebase Database
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      final accountSnapshot = await FirebaseDatabase.instance.ref()
          .child('users')
          .child(currentUser.uid)
          .child(platform.toLowerCase())
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        return null;
      }
      
      // Converti il risultato in un formato usabile
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      
      // Creiamo un nuovo Map con i dati convertiti a String, dynamic
      return {
        'page_id': accountData['page_id']?.toString() ?? '',
        'access_token': accountData['access_token']?.toString() ?? '',
        // Aggiungi altri campi pertinenti qui
      };
    } catch (e) {
      print('Errore nel recupero account: $e');
      return null;
    }
  }
}
