import 'package:flutter/material.dart';
import 'dart:ui'; // Import for ImageFilter
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../services/youtube_service.dart';
import '../services/facebook_service.dart';
import '../services/instagram_service.dart';
import '../services/tiktok_service.dart';
import '../services/threads_service.dart';
import '../services/twitter_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'social/social_account_details_page.dart';

class ScheduledPostDetailsPage extends StatefulWidget {
  final Map<String, dynamic> post;

  const ScheduledPostDetailsPage({
    super.key,
    required this.post,
  });

  @override
  State<ScheduledPostDetailsPage> createState() => _ScheduledPostDetailsPageState();
}

class _ScheduledPostDetailsPageState extends State<ScheduledPostDetailsPage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isDeleting = false;
  Map<String, dynamic>? _youtubeStatus;
  final YouTubeService _youtubeService = YouTubeService();
  final FacebookService _facebookService = FacebookService();
  final InstagramService _instagramService = InstagramService();
  final TikTokService _tiktokService = TikTokService();
  final ThreadsService _threadsService = ThreadsService();
  final TwitterService _twitterService = TwitterService();
  
  // Gestione video player
  VideoPlayerController? _videoPlayerController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;
  bool _isDisposed = false;
  bool _showControls = false;
  bool _isFullScreen = false;
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  Timer? _autoplayTimer;
  Timer? _countdownTimer;

  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

  // Map to hold the remaining time values that gets updated by the timer
  Map<String, int> _timeRemaining = {
    'days': 0,
    'hours': 0,
    'minutes': 0,
    'seconds': 0,
  };
  
  // Flag to indicate if the scheduled time is in the past
  bool _isScheduledInPast = false;
  
  // Flag to indicate if we're currently calculating time
  bool _isCalculatingTime = true;

  int _currentPage = 0;
  late TabController _tabController;
  final PageController _pageController = PageController();

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
    
    // Carica i dati e inizializza il video player come in draft_details_page.dart
    _loadPostDataAndInitialize();
    
    // Initialize the countdown
    _calculateTimeRemaining();
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoplayTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _countdownTimer?.cancel();
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    _carouselController?.dispose();
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // Check if the content is an image
  bool get _isImage => widget.post['media_type'] == 'image';

  Future<void> _checkYouTubeStatus() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final videoId = widget.post['youtube_video_id'] as String;
      final status = await _youtubeService.checkVideoStatus(videoId);
      
      if (mounted) {
        setState(() {
          _youtubeStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Errore nel controllo dello stato di YouTube: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deletePost() async {
    if (_isDeleting) return;
    
    setState(() {
      _isDeleting = true;
    });
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      final postId = widget.post['id'] as String;
      final youtubeVideoId = widget.post['youtube_video_id'] as String?;
      final platform = widget.post['platform'] as String?;
      final scheduledTime = widget.post['scheduled_time'] as int?;
      final hasYouTube = platform?.toLowerCase() == 'youtube' && youtubeVideoId != null;
      final hasFacebook = platform?.toLowerCase() == 'facebook' && scheduledTime != null;
      final hasInstagram = platform?.toLowerCase() == 'instagram' && scheduledTime != null;
      final hasTikTok = platform?.toLowerCase() == 'tiktok' && scheduledTime != null;

      bool hasYouTubeError = false;
      String? youtubeErrorMessage;
      bool hasFacebookError = false;
      String? facebookErrorMessage;
      bool hasInstagramError = false;
      String? instagramErrorMessage;
      bool hasTikTokError = false;
      String? tiktokErrorMessage;
      
      // Se è un video YouTube, elimina anche da YouTube
      if (hasYouTube) {
        // Mostriamo un messaggio di caricamento
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eliminazione del video YouTube in corso...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        try {
          final deleted = await _youtubeService.deleteYouTubeVideo(youtubeVideoId!);
          
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
      
      // Se è un post Facebook, elimina anche dal Cloudflare KV
      if (hasFacebook) {
        // Mostriamo un messaggio di caricamento
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eliminazione del post Facebook in corso...'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.blue,
            ),
          );
        }
        
        try {
          print('Tentativo di eliminazione del post Facebook con scheduled_time: $scheduledTime');
          final deleted = await _facebookService.deleteFacebookScheduledPost(scheduledTime!, currentUser.uid);
          
          if (!deleted) {
            hasFacebookError = true;
            facebookErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su Facebook';
            print('Errore durante l\'eliminazione del post Facebook: post non eliminato dal KV');
          } else {
            print('Post Facebook eliminato con successo dal KV con scheduled_time: $scheduledTime');
          }
        } catch (fbError) {
          print('Errore durante l\'eliminazione del post Facebook: $fbError');
          hasFacebookError = true;
          
          // Verifica se l'errore è dovuto a problemi di rete o API
          if (fbError.toString().contains('timeout') || 
              fbError.toString().contains('connection')) {
            facebookErrorMessage = 'Problemi di connessione. Il post verrà eliminato, ma potrebbe essere necessario eliminare manualmente il post su Facebook.';
          } else {
            facebookErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su Facebook. Verifica manualmente.';
          }
        }
      }

      // Se è un post Instagram, elimina anche dal Cloudflare KV
      if (hasInstagram) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eliminazione del post Instagram in corso...'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.purple,
            ),
          );
        }
        try {
          print('Tentativo di eliminazione del post Instagram con scheduled_time: $scheduledTime');
          final deleted = await _instagramService.deleteInstagramScheduledPost(scheduledTime!, currentUser.uid);
          if (!deleted) {
            hasInstagramError = true;
            instagramErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su Instagram';
            print('Errore durante l\'eliminazione del post Instagram: post non eliminato dal KV');
          } else {
            print('Post Instagram eliminato con successo dal KV con scheduled_time: $scheduledTime');
          }
        } catch (igError) {
          print('Errore durante l\'eliminazione del post Instagram: $igError');
          hasInstagramError = true;
          if (igError.toString().contains('timeout') || igError.toString().contains('connection')) {
            instagramErrorMessage = 'Problemi di connessione. Il post verrà eliminato, ma potrebbe essere necessario eliminare manualmente il post su Instagram.';
          } else {
            instagramErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su Instagram. Verifica manualmente.';
          }
        }
      }

      // Se è un post TikTok, elimina anche dal Cloudflare KV
      if (hasTikTok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eliminazione del post TikTok in corso...'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.black,
            ),
          );
        }
        try {
          print('Tentativo di eliminazione del post TikTok con scheduled_time: $scheduledTime');
          final deleted = await _tiktokService.deleteTikTokScheduledPost(scheduledTime!, currentUser.uid);
          if (!deleted) {
            hasTikTokError = true;
            tiktokErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su TikTok';
            print('Errore durante l\'eliminazione del post TikTok: post non eliminato dal KV');
          } else {
            print('Post TikTok eliminato con successo dal KV con scheduled_time: $scheduledTime');
          }
        } catch (tkError) {
          print('Errore durante l\'eliminazione del post TikTok: $tkError');
          hasTikTokError = true;
          if (tkError.toString().contains('timeout') || tkError.toString().contains('connection')) {
            tiktokErrorMessage = 'Problemi di connessione. Il post verrà eliminato, ma potrebbe essere necessario eliminare manualmente il post su TikTok.';
          } else {
            tiktokErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su TikTok. Verifica manualmente.';
          }
        }
      }
      
      if (mounted) {
        // Gestisci i messaggi di errore per tutte le piattaforme
        String errorMessage = '';
        if (hasYouTubeError && youtubeErrorMessage != null) {
          errorMessage += youtubeErrorMessage;
        }
        if (hasFacebookError && facebookErrorMessage != null) {
          if (errorMessage.isNotEmpty) errorMessage += '\n';
          errorMessage += facebookErrorMessage;
        }
        if (hasInstagramError && instagramErrorMessage != null) {
          if (errorMessage.isNotEmpty) errorMessage += '\n';
          errorMessage += instagramErrorMessage;
        }
        if (hasTikTokError && tiktokErrorMessage != null) {
          if (errorMessage.isNotEmpty) errorMessage += '\n';
          errorMessage += tiktokErrorMessage;
        }
        
        if (errorMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          
          // Diamo all'utente il tempo di leggere il messaggio prima di tornare indietro
          await Future.delayed(Duration(seconds: 2));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Post eliminato con successo'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        // Torna alla pagina precedente
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        
        String errorMessage = 'Errore durante l\'eliminazione: $e';
        
        // Rendi il messaggio più leggibile
        if (e.toString().contains('Too many attempts')) {
          errorMessage = 'Too many requests. Please try again later.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permission denied. You may need to re-authenticate your account.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
  
  Future<void> _showDeleteConfirmation() async {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: theme.dialogBackgroundColor,
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'Elimina Post',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sei sicuro di voler eliminare questo post programmato?',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              SizedBox(height: 8),
              if (widget.post['youtube_video_id'] != null)
                Text(
                  'Il video verrà eliminato anche da YouTube.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (widget.post['platform']?.toString().toLowerCase() == 'facebook')
                Text(
                  'Il post verrà eliminato anche da Facebook.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Annulla',
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
              child: Text('Elimina'),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePost();
              },
            ),
          ],
        );
      },
    );
  }

  // Metodo per eliminare un post per un account specifico
  Future<void> _deletePostForAccount(String accountId) async {
    print('=== DEBUG: _deletePostForAccount INIZIATO ===');
    print('=== DEBUG: accountId ricevuto: $accountId ===');
    print('=== DEBUG: widget.post completo: \\${widget.post} ===');
    
    if (_isDeleting) {
      print('=== DEBUG: Eliminazione già in corso, esco ===');
      return;
    }
    
    setState(() {
      _isDeleting = true;
    });
    
    try {
      // Mostra messaggio di caricamento
      if (mounted) {
        final accountName = _getAccountNameById(accountId);
        _showCustomSnackBar('Removing scheduled post for $accountName...');
      }
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('=== DEBUG: ERRORE - User non autenticato ===');
        throw Exception('User not authenticated');
      }
      
      final userId = widget.post['user_id'] as String?;
      if (userId == null || userId.isEmpty) {
        print('=== DEBUG: ERRORE - user_id non trovato nel post ===');
        throw Exception('user_id not found in post');
      }
      
      final postId = widget.post['id'] as String;
      final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
      
      if (scheduledTime == null) {
        print('=== DEBUG: ERRORE - scheduled_time non trovato nel post ===');
        throw Exception('scheduled_time not found in post');
      }
      
      // Determina la piattaforma dall'accountId ricevuto
      final accounts = widget.post['accounts'] as Map<dynamic, dynamic>?;
      String? platform;
      Map<dynamic, dynamic>? accountData;
      
      if (accounts != null) {
        for (String currentPlatform in accounts.keys) {
          final platformData = accounts[currentPlatform] as Map<dynamic, dynamic>?;
          if (platformData != null) {
            // Cerca l'account con l'ID specifico tra tutte le chiavi uniche
            for (String uniqueKey in platformData.keys) {
              final data = platformData[uniqueKey] as Map<dynamic, dynamic>?;
              if (data != null) {
                final currentAccountId = data['account_id'] as String?;
                if (currentAccountId == accountId) {
                  platform = currentPlatform;
                  accountData = data;
                  break;
                }
              }
            }
            if (platform != null) break;
          }
        }
      }
      
      print('=== DEBUG: Piattaforma determinata: $platform ===');
      
      if (platform == null) {
        print('=== DEBUG: ERRORE - Piattaforma non trovata per accountId: $accountId ===');
        throw Exception('Platform not found for accountId: $accountId');
      }
      
      // --- LOGICA SPECIFICA YOUTUBE ---
      if (platform.toLowerCase() == 'youtube') {
        bool hasError = false;
        String? errorMessage;
        try {
          // Prendi videoId dalla struttura accountData o dal post
          String? youtubeVideoId = accountData?['youtube_video_id'] as String? ?? widget.post['youtube_video_id'] as String?;
          if (youtubeVideoId == null) {
            hasError = true;
            errorMessage = 'YouTube video ID not found';
          } else {
            final deleted = await _youtubeService.deleteYouTubeVideo(youtubeVideoId);
            if (!deleted) {
              hasError = true;
              errorMessage = 'Error during YouTube video deletion.';
            }
          }
        } catch (e) {
          hasError = true;
          errorMessage = 'Error during YouTube video deletion: $e';
        }
        // Aggiorna Firebase (rimuovi solo la piattaforma YouTube o l\'intero post se era solo YouTube)
        try {
          final postRef = FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(userId)
              .child('scheduled_posts')
              .child(postId);
          final postSnapshot = await postRef.get();
          if (!postSnapshot.exists) {
            throw Exception('Post not found in Firebase');
          }
          final postData = postSnapshot.value as Map<dynamic, dynamic>;
          final isMultiPlatform = postData['is_multi_platform'] == true;
          if (isMultiPlatform) {
            final accountsData = postData['accounts'] as Map<dynamic, dynamic>?;
            if (accountsData != null && accountsData.containsKey(platform)) {
              // Trova la chiave unica per questo account specifico
              String? uniqueKeyToRemove;
              final platformData = accountsData[platform] as Map<dynamic, dynamic>?;
              if (platformData != null) {
                for (String uniqueKey in platformData.keys) {
                  final accountData = platformData[uniqueKey] as Map<dynamic, dynamic>?;
                  if (accountData != null && accountData['account_id'] == accountId) {
                    uniqueKeyToRemove = uniqueKey;
                    break;
                  }
                }
              }
              
              if (uniqueKeyToRemove != null) {
                // Rimuovi solo la chiave unica specifica
                await postRef.child('accounts').child(platform).child(uniqueKeyToRemove).remove();
                
                // Controlla se ci sono altri account per questa piattaforma
                final updatedPlatformData = accountsData[platform] as Map<dynamic, dynamic>?;
                if (updatedPlatformData != null && updatedPlatformData.length <= 1) {
                  // Se era l'ultimo account per questa piattaforma, rimuovi l'intera piattaforma
                  await postRef.child('accounts').child(platform).remove();
                  final remainingAccounts = Map<String, dynamic>.from(accountsData);
                  remainingAccounts.remove(platform);
                  final newPlatformsCount = remainingAccounts.length;
                  await postRef.child('platforms_count').set(newPlatformsCount);
                  if (remainingAccounts.isEmpty) {
                    await postRef.remove();
                  }
                }
              } else {
                throw Exception('Account $accountId not found in platform $platform');
              }
            } else {
              throw Exception('Platform $platform not found in Firebase');
            }
          } else {
            await postRef.remove();
          }
        } catch (firebaseError) {
          hasError = true;
          errorMessage = (errorMessage != null ? errorMessage + '\n' : '') + 'Firebase update error: $firebaseError';
        }
        // Mostra risultato
        if (mounted) {
          if (hasError) {
            _showCustomSnackBar(errorMessage ?? 'Error during deletion', isError: true);
          } else {
            Navigator.pop(context);
          }
        }
        setState(() {
          _isDeleting = false;
        });
        print('=== DEBUG: _deletePostForAccount COMPLETATO (YouTube) ===');
        return;
      }
      // --- FINE LOGICA YOUTUBE ---
      
      // LOGICA ALTRE PIATTAFORME (INVARIATA)
      bool hasError = false;
      String? errorMessage;
      print('=== DEBUG: INIZIO ELIMINAZIONE DAL KV ===');
      print('=== DEBUG: Piattaforma: $platform ===');
      print('=== DEBUG: scheduledTime: $scheduledTime ===');
      print('=== DEBUG: userId: $userId ===');
      try {
        bool deleted = false;
        switch (platform.toLowerCase()) {
          case 'facebook':
            deleted = await _facebookService.deleteFacebookScheduledPost(scheduledTime, userId);
            break;
          case 'instagram':
            deleted = await _instagramService.deleteInstagramScheduledPost(scheduledTime, userId);
            break;
          case 'tiktok':
            deleted = await _tiktokService.deleteTikTokScheduledPost(scheduledTime, userId);
            break;
          case 'threads':
            // Cerca l'account ID nella nuova struttura con chiavi uniche
            String? threadsAccountId;
            final accounts = widget.post['accounts'] as Map<dynamic, dynamic>?;
            if (accounts != null && accounts.containsKey(platform)) {
              final platformData = accounts[platform] as Map<dynamic, dynamic>?;
              if (platformData != null) {
                for (String uniqueKey in platformData.keys) {
                  final accountData = platformData[uniqueKey] as Map<dynamic, dynamic>?;
                  if (accountData != null) {
                    threadsAccountId = accountData['account_id'] as String?;
                    break; // Prendi il primo account trovato per Threads
                  }
                }
              }
            }
            if (threadsAccountId != null) {
              deleted = await _threadsService.deleteThreadsScheduledPost(scheduledTime, threadsAccountId);
            } else {
              hasError = true;
              errorMessage = 'Threads account ID not found';
            }
            break;
          case 'twitter':
            deleted = await _twitterService.deleteTwitterScheduledPost(scheduledTime, userId);
            break;
          default:
            hasError = true;
            errorMessage = 'Unsupported platform: $platform';
        }
        if (!hasError && !deleted) {
          hasError = true;
          errorMessage = 'Error during deletion from KV';
        }
      } catch (e) {
        hasError = true;
        errorMessage = 'Error during deletion: $e';
      }
      print('=== DEBUG: FINE ELIMINAZIONE DAL KV ===');
      // Mostra il risultato (resto invariato)
      if (mounted) {
        if (hasError) {
          _showCustomSnackBar(errorMessage ?? 'Error during deletion', isError: true);
        } else {
          // ... esistente: aggiorna Firebase, mostra successo, aggiorna UI ...
          // Controlla se ci sono altri account rimanenti
          bool shouldNavigateBack = true;
          
          // Elimina l'account da Firebase dopo il successo dell'eliminazione dal KV
          try {
            print('=== DEBUG: INIZIO ELIMINAZIONE ACCOUNT DA FIREBASE ===');
            
            // Path corretto con doppio "users" come nella struttura del database
            final postRef = FirebaseDatabase.instance
                .ref()
                .child('users')
                .child('users')
                .child(userId)
                .child('scheduled_posts')
                .child(postId);
            
            print('=== DEBUG: Path Firebase: users/users/$userId/scheduled_posts/$postId ===');
            
            // Ottieni l'attuale post
            final postSnapshot = await postRef.get();
            if (!postSnapshot.exists) {
              print('=== DEBUG: ERRORE - Post non trovato in Firebase ===');
              throw Exception('Post not found in Firebase');
            }
            
            final postData = postSnapshot.value as Map<dynamic, dynamic>;
            print('=== DEBUG: Post data da Firebase: $postData ===');
            
            // Verifica se è un post multi-piattaforma
            final isMultiPlatform = postData['is_multi_platform'] == true;
            print('=== DEBUG: isMultiPlatform: $isMultiPlatform ===');
            
            if (isMultiPlatform) {
              // Per post multi-piattaforma, rimuovi solo l'account specifico
              final accountsData = postData['accounts'] as Map<dynamic, dynamic>?;
              if (accountsData != null && accountsData.containsKey(platform)) {
                print('=== DEBUG: Rimuovo account $accountId da piattaforma $platform da Firebase ===');
                
                // Trova la chiave unica per questo account specifico
                String? uniqueKeyToRemove;
                final platformData = accountsData[platform] as Map<dynamic, dynamic>?;
                if (platformData != null) {
                  for (String uniqueKey in platformData.keys) {
                    final accountData = platformData[uniqueKey] as Map<dynamic, dynamic>?;
                    if (accountData != null && accountData['account_id'] == accountId) {
                      uniqueKeyToRemove = uniqueKey;
                      break;
                    }
                  }
                }
                
                if (uniqueKeyToRemove != null) {
                  // Rimuovi solo la chiave unica specifica
                  await postRef.child('accounts').child(platform).child(uniqueKeyToRemove).remove();
                  
                  // Controlla se ci sono altri account per questa piattaforma
                  final updatedPlatformData = accountsData[platform] as Map<dynamic, dynamic>?;
                  if (updatedPlatformData != null && updatedPlatformData.length <= 1) {
                    // Se era l'ultimo account per questa piattaforma, rimuovi l'intera piattaforma
                    await postRef.child('accounts').child(platform).remove();
                    final remainingAccounts = Map<String, dynamic>.from(accountsData);
                    remainingAccounts.remove(platform);
                    final newPlatformsCount = remainingAccounts.length;
                    await postRef.child('platforms_count').set(newPlatformsCount);
                    print('=== DEBUG: platforms_count aggiornato a: $newPlatformsCount ===');
                    
                    // Se non ci sono più account, elimina l'intero post
                    if (remainingAccounts.isEmpty) {
                      print('=== DEBUG: Nessun account rimanente, elimino l\'intero post ===');
                      await postRef.remove();
                    }
                    
                    // Controlla se ci sono altri account rimanenti
                    shouldNavigateBack = remainingAccounts.isEmpty;
                    print('=== DEBUG: Account rimanenti: ${remainingAccounts.keys.toList()} ===');
                    print('=== DEBUG: Dovrebbe navigare indietro: $shouldNavigateBack ===');
                  }
                  
                  print('=== DEBUG: SUCCESSO - Account rimosso da Firebase ===');
                } else {
                  print('=== DEBUG: ERRORE - Account $accountId non trovato in piattaforma $platform in Firebase ===');
                  throw Exception('Account $accountId not found in platform $platform');
                }
              } else {
                print('=== DEBUG: ERRORE - Piattaforma $platform non trovata in Firebase ===');
                throw Exception('Platform $platform not found in Firebase');
              }
            } else {
              // Per post singola piattaforma, elimina l'intero post
              print('=== DEBUG: Post singola piattaforma, elimino l\'intero post ===');
              await postRef.remove();
              print('=== DEBUG: SUCCESSO - Post rimosso da Firebase ===');
            }
            
            print('=== DEBUG: FINE ELIMINAZIONE ACCOUNT DA FIREBASE ===');
            
          } catch (firebaseError) {
            print('=== DEBUG: ECCEZIONE durante eliminazione da Firebase: $firebaseError ===');
            print('=== DEBUG: Stack trace: ${StackTrace.current} ===');
            
            // Mostra un messaggio di avviso ma non blocca il flusso
            if (mounted) {
              _showCustomSnackBar('Post removed from KV but Firebase update error: $firebaseError', isError: true);
            }
          }
          
          print('=== DEBUG: Mostro messaggio di successo ===');
          final accountName = _getAccountNameById(accountId);
          // _showCustomSnackBar('Scheduled post removed successfully for $accountName', isSuccess: true);
          
          // Controlla se navigare indietro o rimanere nella pagina
          if (shouldNavigateBack) {
            print('=== DEBUG: Navigo indietro ===');
            Navigator.pop(context);
          } else {
            print('=== DEBUG: Rimanendo nella pagina per altri account ===');
            // Ricarica i dati del post per aggiornare la UI
            setState(() {
              // Aggiorna il post rimuovendo l'account eliminato
              final updatedAccounts = Map<String, dynamic>.from(widget.post['accounts'] ?? {});
              updatedAccounts.remove(platform);
              widget.post['accounts'] = updatedAccounts;
              widget.post['platforms_count'] = updatedAccounts.length;
            });
          }
        }
      }
    } catch (e) {
      print('=== DEBUG: ECCEZIONE GENERALE catturata: $e ===');
      print('=== DEBUG: Stack trace: ${StackTrace.current} ===');
      
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        
        String errorMessage = 'Errore durante l\'eliminazione: $e';
        
        // Rendi il messaggio più leggibile
        if (e.toString().contains('Too many attempts')) {
          errorMessage = 'Too many requests. Please try again later.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permission denied. You may need to re-authenticate your account.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      print('=== DEBUG: FINALLY - Reset _isDeleting ===');
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
      print('=== DEBUG: _deletePostForAccount COMPLETATO ===');
    }
  }

  void _showDeleteAccountConfirmation(String accountId) {
    final theme = Theme.of(context);
    
    // Usa la stessa logica del container account per ottenere il display_name
    final accountName = _getAccountNameById(accountId);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: theme.dialogBackgroundColor,
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Delete Scheduled Post',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this scheduled post for $accountName?',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone. The post will be permanently removed from the scheduling queue.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
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
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
            ),
                elevation: 0,
              ),
              child: Text(
                'Delete',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePostForAccount(accountId);
              },
            ),
          ],
          actionsPadding: EdgeInsets.fromLTRB(24, 0, 24, 24),
        );
      },
    );
  }

  // Metodo per eliminare tutti gli account contemporaneamente
  Future<void> _deleteAllAccounts() async {
    if (_isDeleting) return;
    
    setState(() {
      _isDeleting = true;
    });
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      final userId = widget.post['user_id'] as String?;
      if (userId == null || userId.isEmpty) {
        throw Exception('user_id not found in post');
      }
      
      final postId = widget.post['id'] as String;
      final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
      
      if (scheduledTime == null) {
        throw Exception('scheduled_time not found in post');
      }
      
      final accounts = widget.post['accounts'] as Map<dynamic, dynamic>?;
      if (accounts == null || accounts.isEmpty) {
        throw Exception('No accounts found to delete');
      }
      
      // Mostra messaggio di caricamento
      if (mounted) {
        _showCustomSnackBar('Removing scheduled post for all accounts...');
      }
      
      List<String> errors = [];
      List<String> successes = [];
      
      // Elimina ogni account
      for (String platform in accounts.keys) {
        final platformData = accounts[platform] as Map<dynamic, dynamic>?;
        if (platformData != null) {
          // Itera su tutte le chiavi uniche per questa piattaforma
          for (String uniqueKey in platformData.keys) {
            final accountData = platformData[uniqueKey] as Map<dynamic, dynamic>?;
            if (accountData != null) {
              final accountId = accountData['account_id'] as String?;
              if (accountId != null) {
            try {
              // Logica specifica per YouTube
              if (platform.toLowerCase() == 'youtube') {
                final youtubeVideoId = accountData['youtube_video_id'] as String? ?? widget.post['youtube_video_id'] as String?;
                if (youtubeVideoId != null) {
                  final deleted = await _youtubeService.deleteYouTubeVideo(youtubeVideoId);
                  if (deleted) {
                    successes.add('$platform');
                  } else {
                    errors.add('$platform');
                  }
                } else {
                  errors.add('$platform (no video ID)');
                }
              } else {
                // Logica per altre piattaforme
                bool deleted = false;
                switch (platform.toLowerCase()) {
                  case 'facebook':
                    deleted = await _facebookService.deleteFacebookScheduledPost(scheduledTime, userId);
                    break;
                  case 'instagram':
                    deleted = await _instagramService.deleteInstagramScheduledPost(scheduledTime, userId);
                    break;
                  case 'tiktok':
                    deleted = await _tiktokService.deleteTikTokScheduledPost(scheduledTime, userId);
                    break;
                  case 'threads':
                    deleted = await _threadsService.deleteThreadsScheduledPost(scheduledTime, accountId);
                    break;
                  case 'twitter':
                    deleted = await _twitterService.deleteTwitterScheduledPost(scheduledTime, userId);
                    break;
                }
                
                if (deleted) {
                  successes.add('$platform');
                } else {
                  errors.add('$platform');
                }
              }
            } catch (e) {
              errors.add('$platform: ${e.toString()}');
            }
          }
        }
      }
    }
  }
      
      // Elimina l'intero post da Firebase
      try {
        final postRef = FirebaseDatabase.instance
            .ref()
            .child('users')
            .child('users')
            .child(userId)
            .child('scheduled_posts')
            .child(postId);
        
        await postRef.remove();
      } catch (firebaseError) {
        errors.add('Firebase: ${firebaseError.toString()}');
      }
      
      // Mostra risultato
      if (mounted) {
        if (errors.isEmpty && successes.isNotEmpty) {
          // _showCustomSnackBar('Scheduled post removed successfully for all accounts', isSuccess: true);
        } else if (errors.isNotEmpty && successes.isNotEmpty) {
          _showCustomSnackBar('Partially completed: ${successes.join(', ')} succeeded, ${errors.join(', ')} removed', isError: true);
        } else if (errors.isNotEmpty) {
          _showCustomSnackBar('Successfully removed post for all accounts: ${successes.join(', ')}', isError: true);
        }
        
        // Torna alla pagina precedente
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Error during deletion: $e';
        
        if (e.toString().contains('Too many attempts')) {
          errorMessage = 'Too many requests. Please try again later.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permission denied. You may need to re-authenticate your account.';
        }
        
        _showCustomSnackBar(errorMessage, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  // Metodo per mostrare conferma eliminazione di tutti gli account
  void _showDeleteAllAccountsConfirmation() {
    final theme = Theme.of(context);
    final accounts = widget.post['accounts'] as Map<dynamic, dynamic>?;
    
    // Calcola il numero totale di account nella nuova struttura con chiavi uniche
    int accountsCount = 0;
    if (accounts != null) {
      for (String platform in accounts.keys) {
        final platformData = accounts[platform] as Map<dynamic, dynamic>?;
        if (platformData != null) {
          accountsCount += platformData.length;
        }
      }
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: theme.dialogBackgroundColor,
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.delete_forever,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Delete All Accounts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this scheduled post for all $accountsCount accounts?',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action will permanently remove the scheduled post from all connected platforms and cannot be undone.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
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
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                'Delete All',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAllAccounts();
              },
            ),
          ],
          actionsPadding: EdgeInsets.fromLTRB(24, 0, 24, 24),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;
    final videoBackgroundColor = Color(0xFF2C3E50).withOpacity(0.9);

    // Usa la struttura multi-piattaforma se presente
    final isMultiPlatform = widget.post['is_multi_platform'] == true;
    Map<String, dynamic> accounts = {};
    if (isMultiPlatform) {
      final accountsData = widget.post['accounts'] as Map<dynamic, dynamic>?;
      if (accountsData != null) {
        accountsData.forEach((platform, platformData) {
          if (platform is String && platformData is Map) {
            // Gestisce la nuova struttura con chiavi uniche
            List<Map<String, dynamic>> platformAccounts = [];
            platformData.forEach((uniqueKey, accountData) {
              if (accountData is Map) {
                platformAccounts.add({
                  'id': accountData['account_id'] ?? '',
                  'username': accountData['account_username'] ?? '',
                  'display_name': accountData['account_display_name'] ?? accountData['account_username'] ?? '',
                  'profile_image_url': accountData['account_profile_image_url'] ?? '',
                });
              }
            });
            if (platformAccounts.isNotEmpty) {
              accounts[platform] = platformAccounts;
            }
          }
        });
      }
    } else {
    final platform = widget.post['platform'] as String? ?? '';
    final accountId = widget.post['account_id'] as String? ?? '';
      if (platform.isNotEmpty && accountId.isNotEmpty) {
        accounts = {
            platform: [
              {
                'id': accountId,
                'username': widget.post['account_username'] ?? accountId,
                'display_name': widget.post['account_display_name'] ?? widget.post['account_username'] ?? accountId,
                'profile_image_url': widget.post['account_profile_image_url'] ?? '',
              }
            ]
        };
          }
    }

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
          bottom: !_isFullScreen,
          top: !_isFullScreen,
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : _isFullScreen
                  ? _buildFullScreenVideo(theme, mediaWidth, mediaHeight)
                  // Layout con Stack per permettere al contenuto di scorrere dietro i selettori
                  : Stack(
                      children: [
                        // Main content area - no padding, content can scroll behind floating elements
                        SafeArea(
                          child: Column(
                            children: [
                        Expanded(
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
                              _buildVideoSection(theme, mediaWidth, videoBackgroundColor),
                              _buildAccountsSection(theme, accounts),
                            ],
                          ),
                        ),
                        // Footer: container della data schedulata
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: _buildScheduledDateContainer(theme),
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
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 22,
                ),
                onPressed: _isDeleting ? null : _showDeleteAllAccountsConfirmation,
              ),
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(VideoPlayerController controller) {
    // Check if the video is horizontal (aspect ratio > 1)
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
      // For vertical videos, maintain the standard AspectRatio
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
  }

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

  Widget _buildFullScreenVideo(ThemeData theme, double mediaWidth, double mediaHeight) {
    final videoBackgroundColor = Colors.black;
    final bool hasMediaUrls = _mediaUrls.isNotEmpty;
    
    return GestureDetector(
      onTap: () {
        print("Tap on fullscreen container");
        // Per immagini e carosello, mostra sempre i controlli quando si tocca
        // Per video, toggle i controlli
        if (_isImage || hasMediaUrls) {
          setState(() {
            _showControls = true;
          });
          // Nascondi i controlli dopo 3 secondi se è un video nel carosello
          if (hasMediaUrls && _currentCarouselIndex < _isImageList.length && !_isImageList[_currentCarouselIndex] && _videoPlayerController != null && _isVideoInitialized) {
            Future.delayed(Duration(seconds: 3), () {
              if (mounted && !_isDisposed && _videoPlayerController != null && _videoPlayerController!.value.isPlaying) {
                setState(() {
                  _showControls = false;
                });
              }
            });
          }
        } else {
          setState(() {
            _showControls = !_showControls;
          });
        }
      },
      child: Container(
        width: mediaWidth,
        height: mediaHeight,
        color: videoBackgroundColor,
        child: Stack(
          children: [
            // Contenuto media in fullscreen
            if (hasMediaUrls)
              // Carosello in fullscreen
              Stack(
                children: [
                  _buildCarouselMediaPreview(theme),
                  // Controlli video per carosello in fullscreen (se il media corrente è un video)
                  if (_currentCarouselIndex < _isImageList.length && !_isImageList[_currentCarouselIndex] && _videoPlayerController != null && _isVideoInitialized)
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
                                  size: 40,
                                ),
                                padding: EdgeInsets.all(8),
                                onPressed: _toggleVideoPlayback,
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
                                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                                      trackHeight: 3,
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
                      ),
                    ),
                ],
              )
            else if (_isImage)
              // Immagine singola in fullscreen
              Center(
                child: widget.post['media_url'] != null && 
                     widget.post['media_url'].toString().isNotEmpty
                     ? _buildImagePreview(widget.post['media_url'])
                     : _loadCloudflareImage(),
              )
            else if (_isVideoInitialized && _videoPlayerController != null)
              // Video singolo in fullscreen
              Center(
                child: _buildVideoPlayer(_videoPlayerController!),
              ),
            
            // Controlli in modalità fullscreen
            AnimatedOpacity(
              opacity: (_isImage || hasMediaUrls) ? 1.0 : (_showControls ? 1.0 : 0.0),
              duration: Duration(milliseconds: 300),
              child: Stack(
                children: [
                  // Overlay semi-trasparente (solo per video)
                  if (!_isImage && !hasMediaUrls)
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
                  
                  // Pulsante Play/Pause al centro (solo per video)
                  if (!_isImage && !hasMediaUrls && _videoPlayerController != null)
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
                  
                  // Progress bar (solo per video singolo)
                  if (!_isImage && !hasMediaUrls && _videoPlayerController != null)
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
                                activeTrackColor: Colors.white,
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
    );
  }

  void _initializePlayer() {
    // Skip video initialization for images
    if (_isImage) {
      return;
    }
    
    // Usa media_url dal nuovo formato scheduled_posts
    final mediaUrl = widget.post['media_url'] as String?;
    
    if (mediaUrl == null || mediaUrl.isEmpty) {
      setState(() {
        _isVideoInitialized = false;
      });
      return;
    }
    
    // Check if it's a remote URL (Cloudflare)
    if (mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://')) {
      setState(() {
        _isVideoInitialized = false;
        _showControls = true; // Show controls when initializing
        _isPlaying = false; // Reset playing state
      });
      
      // Clean up any existing controller first
      if (_videoPlayerController != null) {
        _videoPlayerController!.removeListener(_onVideoPositionChanged);
        _videoPlayerController!.dispose();
      }
      
      try {
        // Initialize the controller with the remote video URL
        _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(mediaUrl));
        
        // Add listener for player events
        _videoPlayerController!.addListener(_onVideoPositionChanged);
        
        _videoPlayerController!.initialize().then((_) {
          if (!mounted || _isDisposed) return;
          
          // Determine if the video is horizontal (aspect ratio > 1)
          final bool isHorizontalVideo = _videoPlayerController!.value.aspectRatio > 1.0;
          
          setState(() {
            _isVideoInitialized = true;
            _videoDuration = _videoPlayerController!.value.duration;
            _currentPosition = Duration.zero;
            _showControls = true; // Keep controls visible
          });
          
        }).catchError((error) {
          // Handle errors properly
          setState(() {
            _isVideoInitialized = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to play remote video: ${error.toString().substring(0, min(error.toString().length, 50))}...'),
              duration: Duration(seconds: 3),
            ),
          );
        });
      } catch (e) {
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating remote video player: ${e.toString().substring(0, min(e.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Local file path (legacy support)
      // Check if the file exists
      final videoFile = File(mediaUrl);
      if (!videoFile.existsSync()) {
        setState(() {
          _isVideoInitialized = false;
        });
        return;
      }
      
      // Clean up any existing controller first
      if (_videoPlayerController != null) {
        _videoPlayerController!.removeListener(_onVideoPositionChanged);
        _videoPlayerController!.dispose();
      }
      
      setState(() {
        _isVideoInitialized = false;
        _showControls = true; // Show controls when initializing
        _isPlaying = false; // Reset playing state
      });
      
      try {
        // Initialize the controller with the local video file
        _videoPlayerController = VideoPlayerController.file(videoFile);
        
        // Add listener for player events
        _videoPlayerController!.addListener(_onVideoPositionChanged);
        
        _videoPlayerController!.initialize().then((_) {
          if (!mounted || _isDisposed) return;
          
          // Determine if the video is horizontal (aspect ratio > 1)
          final bool isHorizontalVideo = _videoPlayerController!.value.aspectRatio > 1.0;
          
          setState(() {
            _isVideoInitialized = true;
            _videoDuration = _videoPlayerController!.value.duration;
            _currentPosition = Duration.zero;
            _showControls = true; // Keep controls visible
          });
          
        }).catchError((error) {
          // Handle errors properly
          setState(() {
            _isVideoInitialized = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to play local video: ${error.toString().substring(0, min(error.toString().length, 50))}...'),
              duration: Duration(seconds: 3),
            ),
          );
        });
      } catch (e) {
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating local video player: ${e.toString().substring(0, min(e.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
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
      print('Initializing network video player for URL (scheduled_post_details_page): $videoUrl');
      
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
      
      print('Network video player initialized successfully (scheduled_post_details_page) for URL: $videoUrl');
    } catch (e) {
      print('Error initializing network video player (scheduled_post_details_page): $e');
      
      if (mounted && !_isDisposed) {
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to play video: ${e.toString().substring(0, min(e.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Build carousel media preview (carosello multi-media)
  Widget _buildCarouselMediaPreview(ThemeData theme) {
    final mediaUrlsToUse = _mediaUrls;
    
    print('_buildCarouselMediaPreview (scheduled_post_details_page) - mediaUrlsToUse.length: ${mediaUrlsToUse.length}');
    print('_buildCarouselMediaPreview (scheduled_post_details_page) - _carouselController: ${_carouselController != null}');
    
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
      print('Created carousel controller on-the-fly (scheduled_post_details_page)');
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
        
        // Pulsante fullscreen per carosello (solo se non è già in fullscreen)
        if (!_isFullScreen)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(15),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 24,
                ),
                padding: EdgeInsets.all(4),
                constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: _toggleFullScreen,
              ),
            ),
          ),
      ],
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
    
    // Reset controls - mostra sempre i controlli quando si cambia pagina in fullscreen
    setState(() {
      _showControls = true;
      _isPlaying = false;
    });
    
    // Initialize video player for current media if it's a video
    if (index < _mediaUrls.length) {
      final mediaUrl = _mediaUrls[index];
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
          _initializeNetworkVideoPlayer(mediaUrl).then((_) {
            // Mostra i controlli quando il video è inizializzato in fullscreen
            if (mounted && _isFullScreen) {
              setState(() {
                _showControls = true;
              });
            }
          });
        } else {
          _currentVideoUrl = null;
          // Per immagini in fullscreen, mantieni i controlli visibili
          if (mounted && _isFullScreen) {
            setState(() {
              _showControls = true;
            });
          }
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
          ? (widget.post['thumbnail_url'] as String?)
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
        _buildVideoPlayer(_videoPlayerController!),
        
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
    );
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
  
  void _toggleVideoPlayback() {
    if (_videoPlayerController == null) {
      _initializePlayer();
      return;
    }
    
    if (!_videoPlayerController!.value.isInitialized) {
      return;
    }
    
    if (_videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
      _autoplayTimer?.cancel();
      setState(() {
        _isPlaying = false;
        _showControls = true; // Show controls when paused
      });
    } else {
      // Retry play if there's an error or player is at end
      if (_videoPlayerController!.value.position >= _videoPlayerController!.value.duration) {
        // If the video has ended, restart from the beginning
        _videoPlayerController!.seekTo(Duration.zero);
      }
      
      _videoPlayerController!.play().then((_) {
        // Update state only if play succeeded
        if (mounted && !_isDisposed) {
          setState(() {
            _isPlaying = true;
          });
        }
      }).catchError((error) {
        // Show error message
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error playing video. Try again.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
      
      setState(() {
        _isPlaying = true; // Update immediately for UI feedback
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
  
  // Helper function for formatting time
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildAccountsList(Map<String, dynamic> accounts, ThemeData theme) {
    try {
      final Map<String, List<Map<String, dynamic>>> platformsMap = {};
      
      // Process accounts data
      accounts.forEach((platform, platformAccounts) {
        if (platform is String && platformAccounts is List) {
          final processedAccounts = <Map<String, dynamic>>[];
          
          for (var account in platformAccounts) {
            if (account is Map) {
              final username = account['username']?.toString() ?? '';
              
              processedAccounts.add({
                'username': username,
                'display_name': account['display_name']?.toString(),
                'profile_image_url': account['profile_image_url']?.toString(),
                'id': account['id']?.toString(),
              });
            }
          }
          
          if (processedAccounts.isNotEmpty) {
            platformsMap[platform] = processedAccounts;
          }
        }
      });

      if (platformsMap.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
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
          ...platformsMap.entries.map((entry) {
          final platform = entry.key;
            final platformAccounts = entry.value;
          
          return Container(
              width: double.infinity, // Ensure it takes all available width
              margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              // Glass effect container similar to video_details_page
              color: theme.brightness == Brightness.dark 
                  ? Colors.white.withOpacity(0.15) 
                  : Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.4),
                width: 1,
              ),
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
                      // Glassy header similar to video_details_page
                      color: theme.brightness == Brightness.dark 
                          ? Colors.white.withOpacity(0.1) 
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark 
                            ? Colors.white.withOpacity(0.15)
                            : Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
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
                            // Glassy badge around the platform logo
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
                  
                  // Divider
                  Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant),
                  
                                    // List of accounts for this platform
                ...platformAccounts.map((account) {
                    final username = account['username']?.toString() ?? '';
                    final accountId = account['id']?.toString() ?? '';
                    
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
                          // Profile image with shadow and border - now clickable
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
                          
                          // Account details - now clickable
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
                        // Info button per mostrare i dettagli
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
                        const SizedBox(width: 8),
                        // Delete button per rimuovere l'account
                        IconButton(
                          onPressed: () => _showDeleteAccountConfirmation(accountId),
                          icon: Icon(Icons.delete_outline, size: 20),
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.red,
                            backgroundColor: Colors.red.withOpacity(0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          tooltip: 'Delete post for this account',
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

  Widget _buildScheduledDateContainer(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
          colors: [
            Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
            Color(0xFF764ba2), // Colore finale: viola al 100%
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF667eea).withOpacity(0.3),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.schedule,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scheduled For',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _getFormattedScheduledDate(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Icon button top right
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                          Color(0xFF764ba2), // Colore finale: viola al 100%
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                      ).createShader(bounds);
                    },
                    child: Icon(Icons.error_outline, color: Colors.white, size: 20),
                  ),
                  tooltip: 'Scheduling delay info',
                  onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        backgroundColor: theme.dialogBackgroundColor,
                        title: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.error_outline,
                                color: Colors.orange,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Scheduling Delay',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: theme.textTheme.titleLarge?.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'After the scheduled date and time, it may take up to 5 minutes for all posts to be completed. Please be patient while the scheduling process finishes on all platforms.',
                              style: TextStyle(
                                fontSize: 16,
                                color: theme.textTheme.bodyLarge?.color,
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 16),
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This is a normal delay due to platform processing times.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Close',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                        actionsPadding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                      );
                    },
                  );
                },
              ),
            ),
            ],
          ),
          SizedBox(height: 20),
          // Countdown timer
          _isCalculatingTime
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCountdownItem(theme, _timeRemaining['days']!, 'Days'),
                        _buildCountdownSeparator(),
                        _buildCountdownItem(theme, _timeRemaining['hours']!, 'Hours'),
                        _buildCountdownSeparator(),
                        _buildCountdownItem(theme, _timeRemaining['minutes']!, 'Min'),
                        _buildCountdownSeparator(),
                        _buildCountdownItem(theme, _timeRemaining['seconds']!, 'Sec'),
                      ],
                    ),
        ],
      ),
    );
  }

  // Show post details bottom sheet
  void _showPostDetailsBottomSheet(BuildContext context, Map<String, dynamic> account, String platform) {
    final theme = Theme.of(context);
    final platformColor = (platform.toLowerCase() == 'threads' && theme.brightness == Brightness.dark)
        ? Colors.white
        : _getPlatformColor(platform);
    
    // Extract account and post data
    final username = account['username'] as String? ?? '';
    final displayName = account['display_name'] as String? ?? username;
    final profileImageUrl = account['profile_image_url'] as String?;
    
    // Get post title and description from the accounts structure
    final accounts = widget.post['accounts'] as Map<dynamic, dynamic>?;
    String? title;
    String? description;
    
    // Cerca nella nuova struttura con chiavi uniche
    if (accounts != null && accounts.containsKey(platform)) {
      final platformData = accounts[platform] as Map<dynamic, dynamic>?;
      if (platformData != null) {
        // Prendi il primo account trovato per questa piattaforma
        for (String uniqueKey in platformData.keys) {
          final accountData = platformData[uniqueKey] as Map<dynamic, dynamic>?;
          if (accountData != null) {
            title = accountData['title'] as String? ?? widget.post['title'] as String? ?? '';
            // Only use the account-specific description, don't fallback to general description
            description = accountData['description'] as String? ?? '';
            break;
          }
        }
      }
    }
    
    // Fallback se non trovato nella nuova struttura
    if (title == null) {
      title = widget.post['title'] as String? ?? '';
    }
    if (description == null) {
      description = '';
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
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
            // Drag indicator
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.3),
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
                    color: theme.dividerColor.withOpacity(0.2),
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
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withOpacity(0.6)),
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
                    color: theme.dividerColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Profile image - now clickable
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context); // Close the bottom sheet first
                      _navigateToSocialAccountDetails(account, platform);
                    },
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
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: platformColor,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  // Account details - now clickable
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context); // Close the bottom sheet first
                        _navigateToSocialAccountDetails(account, platform);
                      },
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
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
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
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text(
                          (title?.isNotEmpty == true) ? title! : 'No title available',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                    
                    Text(
                      'Description',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Text(
                        (description?.isNotEmpty == true) 
                            ? description! 
                            : 'No description available',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    
                    // Scheduled Time
                    SizedBox(height: 20),
                    Text(
                      'Scheduled Date',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getFormattedScheduledDate(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
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
  }
  
  // Get formatted scheduled date
  String _getFormattedScheduledDate() {
    final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
    if (scheduledTime == null) return 'No date set';
    
    final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    return '${scheduledDateTime.day}/${scheduledDateTime.month}/${scheduledDateTime.year} at ${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildImagePreview(String imageUrl) {
    // Check if it's a remote URL
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
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
          print('Error loading remote image: $error');
              return Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 48,
              );
            },
      );
    }
    
    // Try local file
    final imageFile = File(imageUrl);
    if (imageFile.existsSync()) {
      return Image.file(
            imageFile,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading local image: $error');
              return Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 48,
              );
            },
      );
    } 
    
    // Fallback
    return Icon(
      Icons.image_not_supported,
      color: Colors.grey[400],
      size: 48,
    );
  }

  // Helper method to open remote video in browser
  void _openRemoteVideo(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      print('Errore durante l\'apertura del video: $e');
      if (mounted) {
        _showCustomSnackBar('Error opening video. Please try again later.', isError: true);
      }
    }
  }

  // Metodo per caricare i dati del post da Firebase
  Future<void> _loadPostDataFromFirebase() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }

      // Determina userId dal post (se presente) o dall'utente corrente
      final String userId =
          (widget.post['user_id'] as String?) ?? currentUser.uid;

      // Costruisci il postId dal post (id, key o unique_post_id)
      final dynamic rawPostId =
          widget.post['id'] ?? widget.post['key'] ?? widget.post['unique_post_id'];
      if (rawPostId == null) {
        return;
      }
      final String postId = rawPostId.toString();

      final postPath = 'users/users/$userId/scheduled_posts/$postId';
      print(
          '[SCHEDULED_POST_DETAILS] Loading post from Firebase path: $postPath');

      // Aggiungi timeout per evitare attese troppo lunghe
      final postSnapshot = await FirebaseDatabase.instance
          .ref()
          .child(postPath)
          .get()
          .timeout(Duration(seconds: 5)); // Timeout di 5 secondi

      if (postSnapshot.exists) {
        final postData = postSnapshot.value as Map<dynamic, dynamic>;
        
        // Aggiorna widget.post con i dati da Firebase
        widget.post.addAll(Map<String, dynamic>.from(postData));
        
        // Carica i dati dell'account se necessario
        await _loadAccountData(currentUser);
      }
    } catch (e) {
      // Non bloccare l'inizializzazione se c'è un errore
    }
  }
  
  // Metodo separato per caricare i dati dell'account
  Future<void> _loadAccountData(User currentUser) async {
    final isMultiPlatform = widget.post['is_multi_platform'] == true;
    
    if (isMultiPlatform) {
      // Per post multi-piattaforma, i dati degli account sono già presenti nella struttura 'accounts'
      // Non serve caricare nulla da Firebase
      return;
    }
    
    // Per post singola piattaforma (vecchio formato), mantieni la logica esistente
    // Se i dati dell'account sono già presenti, non serve ricaricarli
    if (widget.post['account_username'] != null && widget.post['account_username'].toString().isNotEmpty &&
        widget.post['account_display_name'] != null && widget.post['account_display_name'].toString().isNotEmpty &&
        widget.post['account_profile_image_url'] != null && widget.post['account_profile_image_url'].toString().isNotEmpty) {
      return;
    }
    
    final accountId = widget.post['account_id'] as String?;
    final platform = widget.post['platform'] as String?;
    
    if (accountId != null && accountId.isNotEmpty && platform != null) {
      try {
        // Costruisci il path per recuperare i dati dell'account
        final socialAccountPath = 'users/users/${currentUser.uid}/social_accounts/${platform.toLowerCase()}/$accountId';
        
        final socialAccountSnapshot = await FirebaseDatabase.instance
            .ref()
            .child(socialAccountPath)
            .get()
            .timeout(Duration(seconds: 3));
        
        if (socialAccountSnapshot.exists) {
          final socialAccountData = socialAccountSnapshot.value as Map<dynamic, dynamic>;
          
          // Cerca il campo username o display_name nel social account
          String? accountUsername = socialAccountData['username']?.toString() ?? 
                                  socialAccountData['display_name']?.toString() ??
                                  socialAccountData['channel_name']?.toString();
          
          // Cerca il campo display_name nel social account
          String? accountDisplayName = socialAccountData['display_name']?.toString() ??
                                     socialAccountData['name']?.toString() ??
                                     socialAccountData['channel_name']?.toString();
          
          // Cerca il campo profile_image_url nel social account
          String? accountProfileImageUrl = socialAccountData['profile_image_url']?.toString() ??
                                         socialAccountData['thumbnail_url']?.toString() ??
                                         '';
          
          if (accountUsername != null && accountUsername.isNotEmpty) {
            widget.post['account_username'] = accountUsername;
          }
          
          if (accountDisplayName != null && accountDisplayName.isNotEmpty) {
            widget.post['account_display_name'] = accountDisplayName;
          }
          
          if (accountProfileImageUrl != null && accountProfileImageUrl.isNotEmpty) {
            widget.post['account_profile_image_url'] = accountProfileImageUrl;
          }
        }
      } catch (e) {
        // Silently handle errors
      }
    }
  }

  // Calculate time remaining until scheduled post
  void _calculateTimeRemaining() {
    final scheduledTime = widget.post['scheduled_time'] as int?;
    
    if (scheduledTime == null) {
      setState(() {
        _isCalculatingTime = false;
        _isScheduledInPast = true;
      });
      return;
    }
    
    final now = DateTime.now();
    final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    final difference = scheduledDateTime.difference(now);
    
    // Check if scheduled time is in the past
    if (difference.isNegative) {
      setState(() {
        _isCalculatingTime = false;
        _isScheduledInPast = true;
        _timeRemaining = {
          'days': 0,
          'hours': 0,
          'minutes': 0,
          'seconds': 0,
        };
      });
      return;
    }
    
    // Calculate days, hours, minutes, and seconds
    final days = difference.inDays;
    final hours = difference.inHours.remainder(24);
    final minutes = difference.inMinutes.remainder(60);
    final seconds = difference.inSeconds.remainder(60);
    
    setState(() {
      _isCalculatingTime = false;
      _isScheduledInPast = false;
      _timeRemaining = {
        'days': days,
        'hours': hours,
        'minutes': minutes,
        'seconds': seconds,
      };
    });
  }

  // Start a countdown timer to update the time remaining
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _calculateTimeRemaining();
        });
      }
    });
  }

  // Build countdown item widget
  Widget _buildCountdownItem(ThemeData theme, int value, String label) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  // Build separator for countdown timer
  Widget _buildCountdownSeparator() {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withOpacity(0.3),
    );
  }

  // Metodo per costruire la sezione video
  Widget _buildVideoSection(ThemeData theme, double mediaWidth, Color videoBackgroundColor) {
    // Check if we have media_urls - prioritize media_urls over media_url
    final bool hasMediaUrls = _mediaUrls.isNotEmpty;
    final bool hasMultipleMedia = hasMediaUrls && _mediaUrls.length > 1;
    
    print('_buildVideoSection (scheduled_post_details_page) - hasMediaUrls: $hasMediaUrls, hasMultipleMedia: $hasMultipleMedia');
    print('_buildVideoSection (scheduled_post_details_page) - _mediaUrls.length: ${_mediaUrls.length}');
    
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
                if (!hasMediaUrls) {
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
                child: hasMediaUrls
                    ? _buildCarouselMediaPreview(theme)
                    : Stack(
                  children: [
                    // If it's an image, display it directly
                    if (_isImage)
                      Stack(
                        children: [
                          Center(
                            child: widget.post['media_url'] != null && 
                                 widget.post['media_url'].toString().isNotEmpty
                                 ? _buildImagePreview(widget.post['media_url'])
                                 : _loadCloudflareImage(),
                          ),
                          // Pulsante fullscreen per immagine
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.fullscreen,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: _toggleFullScreen,
                              ),
                            ),
                          ),
                        ],
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
                    // Otherwise show thumbnail from Cloudflare if available
                    else if (widget.post['thumbnail_url'] != null &&
                            widget.post['thumbnail_url'].toString().isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: Center(
                          child: Image.network(
                            widget.post['thumbnail_url'],
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
                                _isImage ? Icons.image_not_supported : Icons.video_library,
                                color: Colors.grey[400],
                                size: 48,
                              ),
                            ),
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

  // Metodo per costruire la sezione accounts (come in draft_details_page.dart)
  Widget _buildAccountsSection(ThemeData theme, Map<String, dynamic> accounts) {
    // Usa la struttura accounts passata come parametro
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
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 137.4, 24, 24), // Aggiunto 113.4px (3cm) di padding superiore
                child: _buildAccountsList(accounts, theme),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to load image from Cloudflare
  Widget _loadCloudflareImage() {
    // First try thumbnail_url
    final thumbnailUrl = widget.post['thumbnail_url'] as String?;
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
            errorBuilder: (context, url, error) {
              return Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 48,
              );
            },
      );
    }
    
    // Default fallback
    return Icon(
      Icons.image_not_supported,
      color: Colors.grey[400],
      size: 48,
    );
  }

  // Helper function to get the appropriate thumbnail widget for loading state
  Widget _getLoadingThumbnail() {
    print('Getting loading thumbnail for scheduled post details');
    
    // First try thumbnail_url
    final thumbnailUrl = widget.post['thumbnail_url'] as String?;
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
    
    // Fallback to default
    return _getFallbackThumbnail();
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

  // Metodo per caricare i dati e inizializzare il video player
  Future<void> _loadPostDataAndInitialize() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Carica i dati da Firebase se necessario
      await _loadPostDataFromFirebase();
      
      // Gestione carosello: controlla se abbiamo media_urls (lista media)
      final postDataToCheck = widget.post;
      final dynamic rawMediaUrls = postDataToCheck['media_urls'];
      Map<dynamic, dynamic>? mediaUrlsData;
      if (rawMediaUrls is Map) {
        mediaUrlsData = rawMediaUrls;
      } else if (rawMediaUrls is List) {
        // Converte una lista in mappa indicizzata (0,1,2,...) per compatibilità
        mediaUrlsData = {
          for (int i = 0; i < rawMediaUrls.length; i++) i.toString(): rawMediaUrls[i],
        };
      } else {
        mediaUrlsData = null;
      }
      
      print('Checking media_urls in scheduled_post_details_page - keys: ${postDataToCheck.keys.toList()}');
      print('media_urls raw type: ${rawMediaUrls.runtimeType}, value: $rawMediaUrls');
      print('media_urls normalized map type: ${mediaUrlsData.runtimeType}, value: $mediaUrlsData');
      
      if (mediaUrlsData != null && mediaUrlsData.isNotEmpty) {
        final normalizedMediaUrlsMap = mediaUrlsData!;
        print('Found media_urls with ${mediaUrlsData.length} items (scheduled_post_details_page)');
        
        // Converti l'oggetto Map in lista ordinata
        final sortedKeys = mediaUrlsData.keys.toList()..sort((a, b) {
          final aInt = int.tryParse(a.toString()) ?? 0;
          final bInt = int.tryParse(b.toString()) ?? 0;
          return aInt.compareTo(bInt);
        });
        
        // Popola le liste media/immagini
        _mediaUrls = sortedKeys
            .map((key) => normalizedMediaUrlsMap[key].toString())
            .toList();
        
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
        
        print('Populated _mediaUrls with ${_mediaUrls.length} items, isImageList: $_isImageList (scheduled_post_details_page)');
        
        // Inizializza il controller del carosello se abbiamo almeno un media
        if (_mediaUrls.isNotEmpty) {
          _carouselController = PageController(initialPage: 0);
          print('Initialized carousel controller for ${_mediaUrls.length} media (scheduled_post_details_page)');
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
        
        // Inizializza il video player per media singolo
      if (!_isImage) {
        _initializePlayer();
      }
      }
      
      // Avvia il timer di aggiornamento posizione solo per i contenuti non carosello
      if (_mediaUrls.isEmpty) {
      _startPositionUpdateTimer();
      setState(() {
        _showControls = true;
        });
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper method to create custom minimal SnackBar
  void _showCustomSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    final theme = Theme.of(context);
    
    // Check if this is a loading message (removing post)
    bool isLoading = message.contains('Removing scheduled post for') || message.contains('Removing scheduled post for all accounts');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              )
            else if (isSuccess)
              Icon(Icons.check_circle, color: Colors.green, size: 20)
            else if (isError)
              Icon(Icons.error_outline, color: Colors.red, size: 20)
            else
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: isLoading 
            ? BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(0),
                bottomRight: Radius.circular(0),
              )
            : BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
        ),
        margin: EdgeInsets.zero,
        elevation: 8,
        duration: isLoading ? Duration(seconds: 10) : Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  // Helper method to get account name by accountId
  String _getAccountNameById(String accountId) {
    final accounts = widget.post['accounts'] as Map<dynamic, dynamic>?;
    
    if (accounts != null) {
      for (String platform in accounts.keys) {
        final platformData = accounts[platform] as Map<dynamic, dynamic>?;
        if (platformData != null) {
          // Cerca l'account con l'ID specifico tra tutte le chiavi uniche
          for (String uniqueKey in platformData.keys) {
            final data = platformData[uniqueKey] as Map<dynamic, dynamic>?;
            if (data != null) {
              final currentAccountId = data['account_id'] as String?;
              if (currentAccountId == accountId) {
                return data['account_display_name'] as String? ?? 
                       data['account_username'] as String? ?? 
                       'this account';
              }
            }
          }
        }
      }
    }
    
    return 'this account';
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
      'username': account['username']?.toString() ?? '',
      'displayName': account['display_name']?.toString() ?? account['username']?.toString() ?? '',
      'profileImageUrl': account['profile_image_url']?.toString() ?? '',
      'id': account['id']?.toString() ?? account['username']?.toString() ?? '', // Use account ID if available, fallback to username
      'channel_id': account['id']?.toString() ?? account['username']?.toString() ?? '', // Use account ID if available, fallback to username
      'user_id': account['id']?.toString() ?? account['username']?.toString() ?? '', // Use account ID if available, fallback to username
      'followersCount': '0', // Default value since we don't have this info in scheduled post
      'bio': '', // Default empty bio since we don't have this info in scheduled post
      'location': '', // Default empty location since we don't have this info in scheduled post
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
} 