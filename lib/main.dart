import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';  // Add this import for ImageFilter
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:lottie/lottie.dart'; // Importa lottie
import 'package:video_player/video_player.dart'; // Importa video_player
import 'package:onesignal_flutter/onesignal_flutter.dart'; // Importa OneSignal
import 'firebase_options.dart';
import 'pages/upload_video_page.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';
import 'pages/social_accounts_page.dart' hide routeObserver;
import 'pages/home_page.dart';
import 'pages/social/tiktok_page.dart';
import 'pages/social/youtube_page.dart';
import 'pages/social/instagram_page.dart';
import 'pages/social/facebook_page.dart';
import 'pages/social/twitter_page.dart';
import 'pages/social/snapchat_page.dart';
import 'pages/social/threads_page.dart';
import 'pages/profile_page.dart';
import 'pages/profile_edit_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/onboarding_profile_page.dart';
import 'pages/about_page.dart';
import 'pages/help/forgot_password_page.dart';
import 'package:firebase_database/firebase_database.dart';
import 'providers/theme_provider.dart';
import 'pages/upgrade_premium_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'pages/notifications_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'pages/scheduled_posts_page.dart';
import 'pages/premium_home_page.dart';
import 'pages/payment_success_page.dart';
import 'package:app_links/app_links.dart';
import 'dart:async'; // Importa StreamSubscription
import 'services/stripe_service.dart'; // Importa StripeService
import 'services/deep_link_service.dart'; // Importa DeepLinkService
import 'services/onesignal_service.dart'; // Importa OneSignalService
import 'package:flutter/services.dart';
import 'services/email_service.dart';
import 'widgets/email_verification_dialog.dart';
import 'pages/trends_page.dart';
import 'pages/history_page.dart';
import 'package:path_provider/path_provider.dart'; // Per gestione cache
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'services/navigation_service.dart';
import 'pages/upgrade_premium_ios_page.dart';

// Logger condizionale per debug/release
class AppLogger {
  static void debug(String message) {
    assert(() {
      print('DEBUG: $message');
      return true;
    }());
  }
  
  static void info(String message) {
    print('INFO: $message');
  }
  
  static void error(String message) {
    print('ERROR: $message');
  }
}

// Definiamo un RouteObserver globale per tracciare le navigazioni
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configura inizialmente la status bar (verrà aggiornata dinamicamente nel build)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light, // iOS default
    statusBarIconBrightness: Brightness.dark, // Android default (icone scure)
    systemNavigationBarColor: Colors.transparent, // Trasparente per iOS home indicator
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  
  // Initialize Firebase with the correct URL
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set the database URL
  FirebaseDatabase.instance.databaseURL = 'https://share-magica-default-rtdb.europe-west1.firebasedatabase.app';

  // Inizializza Google Mobile Ads SDK in modo semplice
  await MobileAds.instance.initialize();

  // Initialize Firebase App Check with debug provider
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );

  // Initialize date formatting for Italian locale
  await initializeDateFormatting('it_IT', null);

  // Inizializza OneSignal
  try {
    await OneSignalService.initialize();
    await OneSignalService.requestPermission();
  } catch (e) {
    print('Errore nell\'inizializzazione di OneSignal: $e');
    // Continua comunque, OneSignal verrà inizializzato quando necessario
  }

  // Inizializza Stripe
  try {
    await StripeService.initializeStripe();
    print('Stripe inizializzato con successo');
  } catch (e) {
    print('Errore nell\'inizializzazione di Stripe: $e');
    // Continua comunque, Stripe verrà inizializzato quando necessario
  }

  // Inizializza il sistema di badge dell'app
  try {
    await FlutterAppBadger.isAppBadgeSupported();
    print('App badge supportato su questo dispositivo');
  } catch (e) {
    print('App badge non supportato su questo dispositivo: $e');
  }

  // Optional: If you're using Firebase Emulator
  // FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);

  // LOG e CANCELLA tutte le cache note dell'app (temp, cache, support, immagini)
  Future<void> logAndDeleteDir(Directory dir, String label) async {
    if (await dir.exists()) {
      final files = await dir.list(recursive: true).toList();
      print('[$label] Contenuto PRIMA della cancellazione:');
      for (final f in files) {
        print('[$label]   ${f.path}');
      }
      try {
        await dir.delete(recursive: true);
        print('[$label] Directory eliminata con successo');
      } catch (e) {
        print('[$label] Errore durante la cancellazione: $e');
      }
    } else {
      print('[$label] Directory non esistente');
    }
    // Dopo la cancellazione, logga di nuovo
    if (await dir.exists()) {
      final files = await dir.list(recursive: true).toList();
      print('[$label] Contenuto DOPO la cancellazione:');
      for (final f in files) {
        print('[$label]   ${f.path}');
      }
    } else {
      print('[$label] Directory non esistente DOPO la cancellazione');
    }
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final appCacheDir = await getApplicationCacheDirectory();
    final appSupportDir = await getApplicationSupportDirectory();
    final imageCacheDir1 = Directory('${tempDir.path}/libCachedImageData');
    final imageCacheDir2 = Directory('${appCacheDir.path}/libCachedImageData');
    final videoCacheDir1 = Directory('${tempDir.path}/video_cache');
    final videoCacheDir2 = Directory('${appCacheDir.path}/video_cache');

    await logAndDeleteDir(tempDir, 'TEMP');
    await logAndDeleteDir(appCacheDir, 'APP_CACHE');
    await logAndDeleteDir(appSupportDir, 'APP_SUPPORT');
    await logAndDeleteDir(imageCacheDir1, 'IMG_CACHE_TEMP');
    await logAndDeleteDir(imageCacheDir2, 'IMG_CACHE_APP');
    await logAndDeleteDir(videoCacheDir1, 'VIDEO_CACHE_TEMP');
    await logAndDeleteDir(videoCacheDir2, 'VIDEO_CACHE_APP');
  } catch (e) {
    print('[CACHE] Errore generale durante la pulizia: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.theme.brightness == Brightness.dark;
    // Imposta la status bar e navigation bar in base al tema
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      // Status bar (zona con batteria, orario, connessione)
      statusBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS - controlla il colore del testo
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, // Android - controlla il colore delle icone
      // Navigation bar (zona menu in basso per Android) e home indicator iOS
      systemNavigationBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
    
    return MaterialApp(
              title: 'Fluzar',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.theme,
      navigatorObservers: [routeObserver],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('it'),
      ],
      routes: {
        '/': (context) {
          final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          print('Main app route / called with arguments: $arguments');
          return const SplashScreen();
        },
        '/onboarding': (context) => const OnboardingPage(),
        '/auth': (context) => const AuthPage(),
        '/tiktok': (context) => const TikTokPage(),
        '/youtube': (context) => const YouTubePage(),
        '/instagram': (context) => const InstagramPage(),
        '/facebook': (context) => const FacebookPage(),
        '/twitter': (context) => const TwitterPage(),
        '/snapchat': (context) => const SnapchatPage(),
        '/threads': (context) => const ThreadsPage(),
        '/accounts': (context) => const SocialAccountsPage(),
        '/upload': (context) => const UploadVideoPage(),
        '/profile': (context) => const ProfilePage(),
        '/trends': (context) => const TrendsPage(),
        '/history': (context) => const HistoryPage(),
        '/scheduled-posts': (context) {
          final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return ScheduledPostsPage(arguments: arguments);
        },
      },
      builder: (context, child) {
        return _DeepLinkHandler(child: child!);
      },
    );
  }
}

class _DeepLinkHandler extends StatefulWidget {
  final Widget child;
  
  const _DeepLinkHandler({required this.child});

  @override
  State<_DeepLinkHandler> createState() => _DeepLinkHandlerState();
}

class _DeepLinkHandlerState extends State<_DeepLinkHandler> {
  late final StreamSubscription<Uri?> _linkSubscription;
  bool _deepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    
    // Listener globale per deep link (ora solo per altri servizi, non per pagamenti)
    _linkSubscription = AppLinks().uriLinkStream.listen((Uri? uri) async {
      if (uri != null && !_deepLinkHandled) {
        print('[GLOBAL DEEPLINK] Deep link intercettato: $uri');
        
        // Controlla se questo deep link è già stato gestito
        final prefs = await SharedPreferences.getInstance();
        final lastHandledLink = prefs.getString('last_handled_deep_link');
        final currentLink = uri.toString();
        
        if (lastHandledLink != currentLink) {
          // Marca il deep link come gestito
          _deepLinkHandled = true;
          await prefs.setString('last_handled_deep_link', currentLink);
          
          // Gestisci TUTTI i deep link custom viralyst://
          if (uri.scheme == 'viralyst') {
            print('[GLOBAL DEEPLINK] Passo a DeepLinkService: $uri');
            DeepLinkService.handleDeepLink(uri.toString(), context);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _isLoading = true;
  // Controller per l'animazione rotante
  late AnimationController _rotationController;
  // Controller per il video
  VideoPlayerController? _videoController;
  String? _videoError;


  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      )
    );
    
    // Inizializza il controller di rotazione
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    // Avvia la rotazione continua
    _rotationController.repeat();
    
    _controller.forward();
    
    // Inizializza il video controller dopo un breve delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _initializeVideo();
      }
    });
    
    // Avvia un timer semplice e poi procedi
    _initializeAppAndNavigate();
  }

  // Inizializza il video controller
  Future<void> _initializeVideo() async {
          AppLogger.debug('Inizializzazione video iniziata');
    
    if (!mounted) {
      print('DEBUG: Widget non montato, uscita');
      return;
    }
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Scegli il video in base alla modalità dark/light
    final videoPath = isDark 
      ? 'assets/provalogoanimatodark.mp4' // darkmode
      : 'assets/provaLOGOANIMATION.mp4';    // lightmode
          AppLogger.debug('Modalità ${isDark ? 'dark' : 'light'}, video path: $videoPath');
    
    _videoController = VideoPlayerController.asset(videoPath);
    _videoError = null;
    try {
      print('DEBUG: Inizializzazione controller video...');
      await _videoController!.initialize();
      AppLogger.debug('Controller video inizializzato con successo');
      
      // Configura il video per non riprodursi in loop
      _videoController!.setLooping(false);
      AppLogger.debug('Loop disabilitato');
      
      await _videoController!.play();
      AppLogger.debug('Video avviato');
      
      // Aggiungi listener per quando il video finisce
      _videoController!.addListener(() {
        // RIMUOVO la pausa automatica: il video si fermerà da solo
        // if (_videoController!.value.position >= _videoController!.value.duration) {
        //   _videoController!.pause();
        //   print('DEBUG: Video finito, pausato');
        // }
      });
      
      // Aggiorna l'UI quando il video è inizializzato
      if (mounted) {
        AppLogger.debug('Aggiornamento UI...');
        setState(() {});
      }
    } catch (e) {
      print('Errore nell\'inizializzazione del video: $e');
      if (mounted) {
        setState(() {
          _videoError = '';
        });
      }
    }
  }

  // Metodo semplificato per l'inizializzazione
  Future<void> _initializeAppAndNavigate() async {
    try {
      // Registra il tempo di inizio
      final startTime = DateTime.now();
      
      // Avvia tutte le operazioni di inizializzazione
      print('Inizializzazione dell\'app...');
      
      // Inizializza SharedPreferences
      await SharedPreferences.getInstance();
      
      // Identifica l'utente corrente
      final user = FirebaseAuth.instance.currentUser;
      
      // Carica i dati utente durante la splash screen se l'utente è autenticato
      if (user != null) {
        print('Utente autenticato, caricamento dati...');
        await _loadUserData(user);
        print('Caricamento dati completato');
      }
      
      // Garantisci un tempo minimo per la splash screen
      final minSplashDuration = Duration(milliseconds: 2000);
      final elapsedTime = DateTime.now().difference(startTime);
      
      if (elapsedTime < minSplashDuration) {
        print('Attendendo per completare il tempo minimo della splash screen...');
        await Future.delayed(minSplashDuration - elapsedTime);
      }
      
      // Naviga alla schermata appropriata solo dopo aver caricato tutti i dati
      if (mounted) {
        print('Navigazione alla schermata principale...');
        await Future.delayed(const Duration(milliseconds: 700)); // Delay aggiuntivo per il video
        _navigateToNextScreen();
      }
    } catch (e) {
      print('Errore durante l\'inizializzazione: $e');
      
      // Anche in caso di errore, prosegui dopo un breve ritardo
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        _navigateToNextScreen();
      }
    }
  }

  // Carica i dati utente
  Future<void> _loadUserData(User user) async {
    print('Inizio caricamento dati utente per: ${user.email}');
    
    try {
      // Carica preferenze utente
      final prefs = await SharedPreferences.getInstance();
      print('Preferenze caricate');
      
      // Carica dati da Realtime Database
      final database = FirebaseDatabase.instance;
      
      try {
        // Carica profilo utente
        print('Caricamento profilo utente...');
        final userRef = database.ref()
          .child('users')
          .child('users')
          .child(user.uid);
        
        final userSnapshot = await userRef.get();
        print('Profilo utente caricato: ${userSnapshot.exists ? 'trovato' : 'non trovato'}');
        
        // Migrate user data if needed (add referral_count field)
        if (userSnapshot.exists && userSnapshot.value is Map) {
          await _migrateUserData(database, user.uid, userSnapshot.value as Map<dynamic, dynamic>);
        }
        
        // Carica solo i primi 3 video/post per ottimizzare il caricamento
        print('Caricamento primi 3 video...');
        final videosRef = userRef.child('videos');
        await videosRef.limitToFirst(3).get();
        print('Primi 3 video caricati');
        
        // Carica account social
        print('Caricamento account social...');
        final socialAccountsRef = userRef.child('social_accounts');
        await socialAccountsRef.get();
        
        // Carica crediti
        print('Caricamento crediti...');
        final creditsRef = userRef.child('credits');
        await creditsRef.get();
        print('Crediti caricati');
        
        // Carica referral count
        print('Caricamento dati referral...');
        final referralCountRef = userRef.child('referral_count');
        await referralCountRef.get();
        print('Dati referral caricati');
        
        // Carica stato premium
        print('Caricamento stato premium...');
        final premiumRef = userRef.child('premium');
        await premiumRef.get();
        print('Stato premium caricato');
        
      } catch (dbError) {
        print('Errore durante il caricamento dei dati dal database: $dbError');
        // Continuiamo comunque, anche se alcuni dati non sono stati caricati
      }
      
      print('Tutti i dati utente caricati con successo');
    } catch (e) {
      print('Errore durante il caricamento dei dati utente: $e');
      // Non blocchiamo il flusso di avvio dell'app
    }
  }

  // Function to migrate user data to add referral_count field if missing
  Future<void> _migrateUserData(FirebaseDatabase database, String uid, Map<dynamic, dynamic> userData) async {
    try {
      // Debug the current state of the user data
      print('DEBUG MIGRATION: User $uid data check');
      print('DEBUG MIGRATION: Has referral_count: ${userData.containsKey('referral_count')}');
      print('DEBUG MIGRATION: Has referred_users: ${userData.containsKey('referred_users')}');
      
      if (userData.containsKey('referred_users')) {
        print('DEBUG MIGRATION: referred_users type: ${userData['referred_users'].runtimeType}');
        if (userData['referred_users'] is List) {
          print('DEBUG MIGRATION: referred_users length: ${(userData['referred_users'] as List).length}');
        } else {
          print('DEBUG MIGRATION: referred_users is not a List: ${userData['referred_users']}');
        }
      }
      
      // Check if the referral_count field is missing
      if (!userData.containsKey('referral_count') && userData.containsKey('referred_users')) {
        // Calculate referral count from referred_users list
        int referralCount = 0;
        if (userData['referred_users'] is List) {
          referralCount = (userData['referred_users'] as List).length;
        } else if (userData['referred_users'] is Map) {
          // Firebase sometimes stores lists as maps with numeric keys
          final Map<dynamic, dynamic> referredUsersMap = userData['referred_users'] as Map<dynamic, dynamic>;
          referralCount = referredUsersMap.length;
          print('DEBUG MIGRATION: Converted map length to count: $referralCount');
        }
        
        print('DEBUG MIGRATION: Setting referral_count to $referralCount');
        
        // Update the user document with the referral_count field
        await database
            .ref()
            .child('users')
            .child('users')
            .child(uid)
            .update({
              'referral_count': referralCount,
            });
        
        // Verify the update was successful
        final verifySnapshot = await database
            .ref()
            .child('users')
            .child('users')
            .child(uid)
            .get();
            
        if (verifySnapshot.exists && verifySnapshot.value is Map) {
          final verifyData = verifySnapshot.value as Map<dynamic, dynamic>;
          print('DEBUG MIGRATION: After update - referral_count: ${verifyData['referral_count']}');
        }
        
        print('User data migrated: added referral_count field');
      }
    } catch (e) {
      print('Error migrating user data: $e');
    }
  }

  // Naviga alla prossima schermata in base allo stato dell'utente
  Future<void> _navigateToNextScreen() async {
    if (mounted) {
      final user = FirebaseAuth.instance.currentUser;
      final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      print('Splash screen navigating with arguments: $arguments');
      
      if (user != null) {
        // Controlla se l'utente ha completato l'onboarding
        final profileSnapshot = await FirebaseDatabase.instance
            .ref()
            .child('users')
            .child('users')
            .child(user.uid)
            .child('profile')
            .child('onboardingCompleted')
            .get();
        
        final onboardingCompleted = profileSnapshot.value as bool? ?? false;
        
        if (onboardingCompleted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => MainScreen(initialArguments: arguments),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const OnboardingProfilePage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        }
      } else {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const OnboardingPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _rotationController.dispose(); // Importante: rilascia il controller di rotazione
    _videoController?.dispose(); // Rilascia il controller del video
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    
    // Debug per vedere lo stato del video controller
    AppLogger.debug('Video controller null: ${_videoController == null}');
    if (_videoController != null && _videoController!.value.isInitialized) {
      AppLogger.debug('Video initialized: ${_videoController!.value.isInitialized}');
      AppLogger.debug('Video playing: ${_videoController!.value.isPlaying}');
    }
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Video al centro
            if (_videoError != null)
              Positioned(
                top: size.height / 2 - 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(_videoError!, style: TextStyle(color: Colors.red, fontSize: 18)),
                ),
              )
            else if (_videoController != null && _videoController!.value.isInitialized)
              Positioned(
                top: size.height / 2 - 160 - 60 - (Platform.isIOS ? 50 : 0), // Spostato 50px più in alto per iOS
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    height: 352,
                    width: 352,
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
              ),

            // Gif di caricamento nella parte bassa
            Positioned(
              bottom: size.height * 0.001,
              left: 0,
              right: 0,
              child: Center(
                child: Lottie.asset(
                  'assets/animations/MainScene.json',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
            ),

          ],
        ),
      ),
    );
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
}

String snackbarError(dynamic error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'user-not-found':
        return 'Nessun utente trovato con questa email';
      case 'wrong-password':
        return 'Password errata';
      case 'invalid-email':
        return 'Indirizzo email non valido';
      case 'user-disabled':
        return 'Questo account è stato disabilitato';
      case 'email-already-in-use':
        return 'Email già registrata. Usa un\'altra email o accedi con quella esistente.';
      case 'weak-password':
        return 'Password troppo debole';
      case 'operation-not-allowed':
        return 'Questa operazione non è consentita';
      case 'network-request-failed':
        return 'Errore di rete';
      default:
        return error.message ?? 'Si è verificato un errore';
    }
  }
  return error.toString();
}

class AuthPage extends StatefulWidget {
  final bool? initialMode; // true = login, false = sign up, null = default (login)
  
  const AuthPage({super.key, this.initialMode});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  bool isLogin = true;
  bool isLoading = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // Imposta la modalità iniziale in base al parametro passato
    isLogin = widget.initialMode ?? true; // true = login (default), false = sign up
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animationController.forward();
    
    // Aggiungi listener ai controller per aggiornare lo stato del pulsante
    _emailController.addListener(_onFormChanged);
    _passwordController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  // Metodo chiamato quando cambiano i campi del form
  void _onFormChanged() {
    if (mounted) {
      setState(() {
        // Forza il rebuild per aggiornare lo stato del pulsante
      });
    }
  }




  void _toggleAuthMode() {
    setState(() {
      _formKey.currentState?.reset();
      isLogin = !isLogin;
      _acceptedTerms = false; // Reset dei termini quando si cambia modalità
      _animationController.reset();
      _animationController.forward();
    });
  }

  // Metodo per verificare se tutti i campi sono compilati correttamente per la registrazione
  bool _isSignUpFormValid() {
    if (isLogin) return true; // Per il login non serve questa validazione
    
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    // Verifica che email e password non siano vuoti e che i termini siano accettati
    return email.isNotEmpty && password.isNotEmpty && _acceptedTerms;
  }

  // Metodo per verificare se tutti i campi sono compilati correttamente per il login
  bool _isLoginFormValid() {
    if (!isLogin) return true; // Per la registrazione non serve questa validazione
    
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    // Verifica che email e password non siano vuoti
    return email.isNotEmpty && password.isNotEmpty;
  }

  Future<void> _signInWithGoogle() async {
    try {
      setState(() => isLoading = true);
      
      // Initialize Google Sign In with force account selection
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email'],
        // Explicit iOS clientId to fix iOS sign-in flow
        clientId: Platform.isIOS
            ? '1095391771291-ner3467g5fqv14j0l5886qe5u7sho8a2.apps.googleusercontent.com'
            : null,
        // Server client ID for backend auth / Firebase
        serverClientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
        signInOption: SignInOption.standard,
      );

      print('Starting Google Sign In...');
      
      // Sign out first to force the account picker to show
      try {
        await googleSignIn.signOut();
      } catch (e) {
        print('Pre-signOut failed: $e');
      }
      
      // Trigger the authentication flow with prompt for account selection
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      print('Google Sign In result: ${googleUser?.email ?? 'null'}');
      
      // If the user cancels the sign-in flow, return
      if (googleUser == null) {
        setState(() => isLoading = false);
        return;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      print('Got Google Auth tokens');

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      print('Created Firebase credential');

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      print('Firebase sign in successful: ${userCredential.user?.email}');
      
      // Check if the sign in was successful
      if (userCredential.user != null) {
        final user = userCredential.user!;
        final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
        
        // If this is a new user, create their Firestore document with referral code
        if (isNewUser) {
          try {
            // Per i nuovi utenti Google, crea direttamente il documento (email già verificata da Google)
            await _completeGoogleRegistration(user);
          } catch (e) {
            print('Error creating user document: $e');
            // Continue even if document creation fails
          }
        } else {
          // Utente esistente, controlla se ha completato l'onboarding
          final profileSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(user.uid)
              .child('profile')
              .child('onboardingCompleted')
              .get();
          
          final onboardingCompleted = profileSnapshot.value as bool? ?? false;
          
          if (mounted) {
            if (onboardingCompleted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainScreen()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const OnboardingProfilePage()),
              );
            }
          }
        }
      }
    } on FirebaseAuthException catch (e, st) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      String errorMessage = 'An error occurred during sign in';
      if (e.code == 'network-request-failed') {
        errorMessage = 'Please check your internet connection and try again';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'This account has been disabled';
      } else if (e.code == 'invalid-credential') {
        errorMessage = 'Invalid credentials';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
            action: SnackBarAction(
              label: 'OK',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } on PlatformException catch (e, st) {
      // Errors from google_sign_in plugin (iOS specific codes included)
      print('Google Sign-In PlatformException: ${e.code} - ${e.message} - ${e.details}');
      final detailed = 'Google Sign-In failed (iOS). Code: ${e.code}. Message: ${e.message ?? ''}.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    detailed,
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
          ),
        );
      }
    } catch (e, st) {
      print('Unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'An unexpected error occurred: ${e.toString()}',
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
            action: SnackBarAction(
              label: 'OK',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // Generate a unique referral code based on the user's UID
  String _generateReferralCode(String uid) {
    // Take the first 6 characters of the UID and convert to uppercase
    final baseCode = uid.substring(0, 6).toUpperCase();
    
    // Add a random element to ensure uniqueness
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7, 13);
    
    // Combine to create a unique but readable code
    return 'VIR$baseCode$timestamp';
  }

  // Generate a cryptographically secure nonce for Apple Sign In
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // Generate SHA256 hash of the nonce
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signInWithApple() async {
    try {
      setState(() => isLoading = true);
      
      // Generate nonce and its hash
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);
      
      print('Starting Apple Sign In...');
      // Check availability on iOS
      if (Platform.isIOS) {
        try {
          final isAvailable = await SignInWithApple.isAvailable();
          if (!isAvailable) {
            print('Apple Sign-In not available on this iOS version or device.');
          }
        } catch (e) {
          print('Availability check failed: $e');
        }
      }
      
      // Request Apple Sign In
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      
      print('Apple Sign In result: ${appleCredential.userIdentifier}');
      if (appleCredential.identityToken == null || appleCredential.identityToken!.isEmpty) {
        print('identityToken is NULL/EMPTY - cannot proceed to Firebase. This often happens if Apple did not return token.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Apple ha restituito identityToken nullo. Riprova o verifica le impostazioni del dispositivo/Apple ID.',
                      style: TextStyle(color: Colors.black87, fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.white,
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              margin: EdgeInsets.all(12),
              elevation: 4,
            ),
          );
        }
        return;
      }
      
      // Create Firebase credential
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      
      print('Created Firebase Apple credential');
      
      // Sign in to Firebase with Apple credential
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      
      print('Firebase Apple sign in successful: ${userCredential.user?.email}');
      
      // Check if the sign in was successful
      if (userCredential.user != null) {
        final user = userCredential.user!;
        final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
        
        // If this is a new user, create their document with referral code
        if (isNewUser) {
          try {
            // Per i nuovi utenti Apple, crea direttamente il documento
            await _completeAppleRegistration(user, appleCredential);
          } catch (e) {
            print('Error creating Apple user document: $e');
            // Continue even if document creation fails
          }
        } else {
          // Utente esistente, controlla se ha completato l'onboarding
          final profileSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child('users')
              .child(user.uid)
              .child('profile')
              .child('onboardingCompleted')
              .get();
          
          final onboardingCompleted = profileSnapshot.value as bool? ?? false;
          
          if (mounted) {
            if (onboardingCompleted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MainScreen()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const OnboardingProfilePage()),
              );
            }
          }
        }
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      print('Apple Sign In Error: ${e.code} - ${e.message}');
      String errorMessage = 'An error occurred during Apple sign in';
      
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          errorMessage = 'Apple sign in was canceled';
          break;
        case AuthorizationErrorCode.failed:
          errorMessage = 'Apple sign in failed';
          break;
        case AuthorizationErrorCode.invalidResponse:
          errorMessage = 'Invalid response from Apple';
          break;
        case AuthorizationErrorCode.notHandled:
          errorMessage = 'Apple sign in not handled';
          break;
        case AuthorizationErrorCode.notInteractive:
          errorMessage = 'Apple sign in not interactive';
          break;
        case AuthorizationErrorCode.unknown:
          errorMessage = 'Unknown Apple sign in error';
          break;
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
            action: SnackBarAction(
              label: 'OK',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e, st) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      String errorMessage = 'An error occurred during Apple sign in';
      if (e.code == 'network-request-failed') {
        errorMessage = 'Please check your internet connection and try again';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'This account has been disabled';
      } else if (e.code == 'invalid-credential') {
        errorMessage = 'Invalid Apple credentials';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
            action: SnackBarAction(
              label: 'OK',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } on PlatformException catch (e, st) {
      print('Apple Sign-In PlatformException: ${e.code} - ${e.message} - ${e.details}');
      final detailed = 'Apple Sign-In failed (iOS). Code: ${e.code}. Message: ${e.message ?? ''}.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    detailed,
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
          ),
        );
      }
    } catch (e, st) {
      print('Unexpected Apple sign in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'An unexpected error occurred: ${e.toString()}',
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
            action: SnackBarAction(
              label: 'OK',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch URL')),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (!isLogin && !_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Please accept the Terms & Conditions and Privacy Policy',
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
            action: SnackBarAction(
              label: 'OK',
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
        return;
      }

      try {
        setState(() => isLoading = true);
        
        if (isLogin) {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          
          // Controlla se l'utente ha completato l'onboarding
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final profileSnapshot = await FirebaseDatabase.instance
                .ref()
                .child('users')
                .child('users')
                .child(user.uid)
                .child('profile')
                .child('onboardingCompleted')
                .get();
            
            final onboardingCompleted = profileSnapshot.value as bool? ?? false;
            
            if (mounted) {
              if (onboardingCompleted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const MainScreen()),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const OnboardingProfilePage()),
                );
              }
            }
          }
        } else {
          // Per la registrazione, prima verifica se l'email esiste già
          final email = _emailController.text.trim();
          
          // CONTROLLO COMPLETO: Verifica sia Firebase Auth che registered_emails
          bool emailExists = false;
          String errorMessage = '';
          
          try {
            // 1. Controllo Firebase Auth (per sicurezza)
            final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
            if (methods.isNotEmpty) {
              emailExists = true;
              errorMessage = 'Email already registered. Use another email or sign in with existing credentials.';
              print('DEBUG: Email found in Firebase Auth: $email');
            }
            
            // 2. Controllo nostra cartella registered_emails (per performance)
            if (!emailExists) {
              final isRegistered = await EmailService.isEmailRegistered(email);
              if (isRegistered) {
                emailExists = true;
                errorMessage = 'Email already registered. Use another email or sign in with existing credentials.';
                print('DEBUG: Email found in registered_emails: $email');
              }
            }
            
            // 3. Se l'email esiste, mostra errore e blocca il processo
            if (emailExists) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            errorMessage,
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.white,
                    duration: const Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    margin: EdgeInsets.all(12),
                    elevation: 4,
                  ),
                );
              }
              return;
            }
            
            // 4. Se l'email non esiste, procedi con l'invio del codice
            print('DEBUG: Email not found, proceeding with verification code: $email');
            
          } catch (e) {
            print('DEBUG: Error during email verification: $e');
            // In caso di errore, procedi comunque con l'invio del codice
            // (meglio permettere una registrazione extra che bloccare una registrazione valida)
          }
          
          // Genera e invia il codice di verifica
          final codeSent = await EmailService.generateAndSendVerificationCode(email);
          
          if (!codeSent) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Error sending verification code. Please try again.',
                          style: TextStyle(color: Colors.black87, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.white,
                  duration: const Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  margin: EdgeInsets.all(12),
                  elevation: 4,
                ),
              );
            }
            return;
          }
          
          // Mostra il popup di verifica
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => EmailVerificationDialog(
                email: email,
                onVerificationSuccess: () async {
                  // Procedi con la registrazione dopo la verifica
                  await _completeRegistration(email);
                },
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      snackbarError(e),
                      style: TextStyle(color: Colors.black87, fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.white,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              margin: EdgeInsets.all(12),
              elevation: 4,
              action: SnackBarAction(
                label: 'OK',
                textColor: Theme.of(context).colorScheme.primary,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    }
  }

  // Metodo per completare la registrazione dopo la verifica email
  Future<void> _completeRegistration(String email) async {
    try {
      setState(() => isLoading = true);
      
      // Create the user account
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );
      
      // Get the new user's UID
      final newUserUid = userCredential.user!.uid;
      
      // Generate a unique referral code for the new user
      final referralCode = _generateReferralCode(newUserUid);
      
      // Get Firebase Realtime Database reference
      final database = FirebaseDatabase.instance;
      
      // Check if push notifications are enabled
      final pushNotificationsEnabled = await OneSignalService.areNotificationsEnabled();
      
      // Initialize the user data with default values
      final userData = {
        'uid': newUserUid,
        'email': email, // Aggiungi l'email al database
        'referral_code': referralCode,
        'invited_by': null,
        'referred_users': [],
        'referral_count': 0, // Initialize referral count
        'credits': 500, // Default credits
        'push_notifications_enabled': pushNotificationsEnabled, // Salva lo stato delle notifiche push
      };
      
      // Check if a referral code was provided
      final referralCodeInput = _referralCodeController.text.trim();
      if (referralCodeInput.isNotEmpty) {
        try {
          print('DEBUG REFERRAL: Processing referral code: $referralCodeInput');
          
          // Look for the referrer in Realtime Database
          final referrerQuery = await database
              .ref()
              .child('users')
              .child('users')
              .orderByChild('referral_code')
              .equalTo(referralCodeInput)
              .limitToFirst(1)
              .get();
          
          print('DEBUG REFERRAL: Query result exists: ${referrerQuery.exists}');
          print('DEBUG REFERRAL: Query children count: ${referrerQuery.children.length}');
          
          // If a referrer was found
          if (referrerQuery.exists && referrerQuery.children.isNotEmpty) {
            final referrerSnapshot = referrerQuery.children.first;
            final referrerData = Map<String, dynamic>.from(referrerSnapshot.value as Map);
            final referrerUid = referrerData['uid'] as String;
            
            print('DEBUG REFERRAL: Found referrer with UID: $referrerUid');
            print('DEBUG REFERRAL: Referrer current credits: ${referrerData['credits']}');
            print('DEBUG REFERRAL: Referrer current referral_count: ${referrerData['referral_count']}');
            
            // Update the new user's data with the referrer's UID
            userData['invited_by'] = referrerUid;
            userData['credits'] = 1000; // 500 default + 500 bonus
            // push_notifications_enabled è già impostato sopra
            
            // Aggiorna il referrer in modo sicuro
            final referrerUserRef = database.ref().child('users').child('users').child(referrerUid);
            
            // Leggi i dati attuali del referrer
            final currentReferrerSnapshot = await referrerUserRef.get();
            if (currentReferrerSnapshot.exists && currentReferrerSnapshot.value is Map) {
              final currentData = Map<String, dynamic>.from(currentReferrerSnapshot.value as Map);
              print('DEBUG REFERRAL: Current referrer data loaded successfully');
              
              List<String> referredUsers = [];
              if (currentData.containsKey('referred_users') && currentData['referred_users'] != null) {
                if (currentData['referred_users'] is List) {
                  referredUsers = List<String>.from(currentData['referred_users']);
                  print('DEBUG REFERRAL: Current referred_users (List): $referredUsers');
                } else if (currentData['referred_users'] is Map) {
                  referredUsers = (currentData['referred_users'] as Map).values.map((v) => v.toString()).toList();
                  print('DEBUG REFERRAL: Current referred_users (Map): $referredUsers');
                }
              } else {
                print('DEBUG REFERRAL: No referred_users found, starting with empty list');
              }
              
              if (!referredUsers.contains(newUserUid)) {
                print('DEBUG REFERRAL: Adding new user ${newUserUid} to referred_users');
                referredUsers.add(newUserUid);
                
                int rewardAmount;
                switch (referredUsers.length) {
                  case 1: rewardAmount = 1000; break;
                  case 2: rewardAmount = 1500; break;
                  case 3: rewardAmount = 3000; break;
                  default: rewardAmount = 1000; break;
                }
                
                final currentCredits = currentData['credits'] as int? ?? 0;
                final newCredits = currentCredits + rewardAmount;
                final newReferralCount = referredUsers.length;
                
                print('DEBUG REFERRAL: Current credits: $currentCredits');
                print('DEBUG REFERRAL: Reward amount: $rewardAmount');
                print('DEBUG REFERRAL: New credits: $newCredits');
                print('DEBUG REFERRAL: New referral_count: $newReferralCount');
                print('DEBUG REFERRAL: Updated referred_users: $referredUsers');
                
                // Aggiorna il referrer
                await referrerUserRef.update({
                  'referred_users': referredUsers,
                  'credits': newCredits,
                  'referral_count': newReferralCount,
                });
                
                print('DEBUG REFERRAL: Successfully updated referrer $referrerUid');
                
                // Verifica che l'aggiornamento sia avvenuto
                final verifySnapshot = await referrerUserRef.get();
                if (verifySnapshot.exists && verifySnapshot.value is Map) {
                  final verifyData = Map<String, dynamic>.from(verifySnapshot.value as Map);
                  print('DEBUG REFERRAL: Verification - credits: ${verifyData['credits']}');
                  print('DEBUG REFERRAL: Verification - referral_count: ${verifyData['referral_count']}');
                  print('DEBUG REFERRAL: Verification - referred_users: ${verifyData['referred_users']}');
                }
              } else {
                print('DEBUG REFERRAL: User ${newUserUid} already in referred_users list');
              }
            } else {
              print('DEBUG REFERRAL: Failed to load current referrer data');
            }
          } else {
            print('DEBUG REFERRAL: No referrer found with code: $referralCodeInput');
          }
        } catch (e) {
          print('DEBUG REFERRAL: Error processing referral: $e');
          // Continue with registration even if referral processing fails
        }
      }
      
      // Create the new user document in Realtime Database
      await database
          .ref()
          .child('users')
          .child('users')
          .child(newUserUid)
          .set(userData);
      
      // Salva l'utente nella cartella registered_emails per future verifiche
      try {
        await EmailService.saveRegisteredUser(email, newUserUid, userData);
        print('Utente salvato nella cartella registered_emails');
      } catch (e) {
        print('Errore nel salvare l\'utente in registered_emails: $e');
        // Non bloccare la registrazione se questo fallisce
      }
      
      // Email di benvenuto verrà inviata dopo il completamento del setup del profilo
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OnboardingProfilePage()),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage;
        if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
          errorMessage = 'Email already registered. Use another email or sign in with existing credentials.';
        } else {
          errorMessage = 'Error during registration: ${snackbarError(e)}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Widget _buildTermsAndPrivacy() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutCubic,
        )),
        child: Row(
          children: [
                                      Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      _acceptedTerms = !_acceptedTerms;
                                    });
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      height: 26,
                                      width: 46,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(13),
                                        color: _acceptedTerms 
                                            ? Color(0xFF6C63FF)
                                            : Colors.grey.shade300,
                                      ),
                                      child: Stack(
                                        children: [
                                          AnimatedPositioned(
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeInOut,
                                            left: _acceptedTerms ? 22 : 0,
                                            right: _acceptedTerms ? 0 : 22,
                                            top: 3,
                                            bottom: 3,
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 300),
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.05),
                                                    blurRadius: 2,
                                                    spreadRadius: 1,
                                                    offset: Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                              child: _acceptedTerms
                                                  ? Center(
                                                      child: Icon(
                                                        Icons.check,
                                                        color: Color(0xFF6C63FF),
                                                        size: 14,
                                                      ),
                                                    )
                                                  : Container(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'I accept the ',
                    style: TextStyle(fontSize: 14),
                  ),
                  InkWell(
                    onTap: () => _launchURL('https://viralyst.online/terms-conditions/'),
                    child: Text(
                      'Terms & Conditions',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const Text(
                    ' and ',
                    style: TextStyle(fontSize: 14),
                  ),
                  InkWell(
                    onTap: () => _launchURL('https://viralyst.online/privacy-policy/'),
                    child: Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    
    // Configura la system UI per la pagina di login/signup
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      // Status bar (zona con batteria, orario, connessione)
      statusBarColor: Platform.isIOS ? Colors.transparent : Colors.transparent, // Trasparente per entrambe le piattaforme
      statusBarBrightness: Brightness.dark, // iOS - sfondo scuro quindi icone chiare
      statusBarIconBrightness: Brightness.light, // Android - icone bianche
      // Navigation bar e home indicator (iOS)
      systemNavigationBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
    
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
            colors: [
              Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
              Color(0xFF764ba2), // Colore finale: viola al 100%
            ],
          ),
        ),
        child: SizedBox(
          height: size.height,
          child: Column(
            children: [
              // Top section with welcome text and illustration
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Welcome illustration
                    Container(
                      height: size.height * 0.15, // Increased height
                      width: size.width * 0.8,
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/onboarding/cerchiosenzasfondo.png'),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5), // Increased spacing
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            Text(
                              isLogin ? 'Welcome Back' : 'Create Account',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isLogin 
                                  ? 'Login to your account' 
                                  : 'Sign up to get started',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom white container with form
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position: _slideAnimation,
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Email field
                                      TextFormField(
                                        controller: _emailController,
                                        keyboardType: TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        decoration: InputDecoration(
                                          labelText: 'Email',
                                          hintText: 'Enter your email',
                                          prefixIcon: const Icon(Icons.email_outlined),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(15),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                                          floatingLabelAlignment: FloatingLabelAlignment.start,
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your email';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      // Password field
                                      TextFormField(
                                        controller: _passwordController,
                                        keyboardType: TextInputType.visiblePassword,
                                        textInputAction: TextInputAction.done,
                                        obscureText: _obscurePassword,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        decoration: InputDecoration(
                                          labelText: 'Password',
                                          hintText: isLogin ? 'Enter your password' : 'Create a password',
                                          prefixIcon: const Icon(Icons.lock_outline),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscurePassword = !_obscurePassword;
                                              });
                                            },
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(15),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                                          floatingLabelAlignment: FloatingLabelAlignment.start,
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your password';
                                          }
                                          if (!isLogin && value.length < 6) {
                                            return 'Password must be at least 6 characters';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      // Forgot password
                                      if (isLogin) ...[
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => const ForgotPasswordPage(),
                                                ),
                                              );
                                            },
                                            child: Text(
                                              'Forgot Password?',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.primary,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (!isLogin) ...[
                                        // Referral Code field
                                        TextFormField(
                                          controller: _referralCodeController,
                                          keyboardType: TextInputType.text,
                                          textInputAction: TextInputAction.done,
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          textCapitalization: TextCapitalization.characters,
                                          decoration: InputDecoration(
                                            labelText: 'Referral Code (Optional)',
                                            hintText: 'Enter referral code if you have one',
                                            prefixIcon: const Icon(Icons.card_giftcard_outlined),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(15),
                                              borderSide: BorderSide.none,
                                            ),
                                            filled: true,
                                            fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                                            floatingLabelAlignment: FloatingLabelAlignment.start,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildTermsAndPrivacy(),
                                      ],
                                      const SizedBox(height: 24),
                                      // Login/Sign up button
                                      SizedBox(
                                        height: 50,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                                              colors: [
                                                Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                                Color(0xFF764ba2), // Colore finale: viola al 100%
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(15),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0xFF667eea).withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton(
                                            onPressed: (isLoading || !(isLogin ? _isLoginFormValid() : _isSignUpFormValid())) ? null : _submitForm,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              foregroundColor: (isLogin ? _isLoginFormValid() : _isSignUpFormValid()) ? Colors.white : Colors.grey.shade700,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(15),
                                              ),
                                              elevation: 0,
                                              shadowColor: Colors.transparent,
                                            ),
                                            child: isLoading
                                                ? SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                    ),
                                                  )
                                                : Text(
                                                    isLogin ? 'LOGIN' : 'SIGN UP',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      // OR divider
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Divider(
                                              color: isDark ? Colors.grey[700] : Colors.grey[300],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            child: Text(
                                              'OR',
                                              style: TextStyle(
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Divider(
                                              color: isDark ? Colors.grey[700] : Colors.grey[300],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      // Google Sign In button
                                      SizedBox(
                                        height: 50,
                                        child: OutlinedButton.icon(
                                          onPressed: isLoading ? null : _signInWithGoogle,
                                          icon: Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: Image.asset(
                                              'assets/google_logo.png',
                                              height: 20,
                                            ),
                                          ),
                                          label: Text(
                                            'Continue with Google',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            side: BorderSide(
                                              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                            ),
                                            backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Apple Sign In button
                                      SizedBox(
                                        height: 50,
                                        child: OutlinedButton.icon(
                                          onPressed: isLoading ? null : _signInWithApple,
                                          icon: Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: Image.asset(
                                              'assets/loghi/LogoAppleNeroNoSfondo.png',
                                              height: 20,
                                            ),
                                          ),
                                          label: Text(
                                            'Continue with Apple',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            side: BorderSide(
                                              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                            ),
                                            backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      // Sign up/Login link
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            isLogin ? 'Don\'t have an account? ' : 'Already have an account? ',
                                            style: TextStyle(
                                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _toggleAuthMode,
                                            child: ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                                                  colors: [
                                                    Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                                    Color(0xFF764ba2), // Colore finale: viola al 100%
                                                  ],
                                                ).createShader(bounds);
                                              },
                                              child: Text(
                                                isLogin ? 'Sign up' : 'Login',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Metodo per completare la registrazione degli utenti Google dopo la verifica email
  Future<void> _completeGoogleRegistration(User user) async {
    try {
      setState(() => isLoading = true);
      
      // Generate a unique referral code
      final referralCode = _generateReferralCode(user.uid);
      
      // Get Firebase Realtime Database reference
      final database = FirebaseDatabase.instance;
      
      // Check if push notifications are enabled
      final pushNotificationsEnabled = await OneSignalService.areNotificationsEnabled();
      
      // Initialize the user data with default values
      final userData = {
        'uid': user.uid,
        'email': user.email, // Aggiungi l'email al database
        'referral_code': referralCode,
        'invited_by': null,
        'referred_users': [],
        'referral_count': 0, // Initialize referral count
        'credits': 500, // Default credits
        'push_notifications_enabled': pushNotificationsEnabled, // Salva lo stato delle notifiche push
      };
      
      // Check if a referral code was provided
      final referralCodeInput = _referralCodeController.text.trim();
      if (referralCodeInput.isNotEmpty) {
        try {
          print('DEBUG REFERRAL: Processing referral code: $referralCodeInput');
          
          // Look for the referrer in Realtime Database
          final referrerQuery = await database
              .ref()
              .child('users')
              .child('users')
              .orderByChild('referral_code')
              .equalTo(referralCodeInput)
              .limitToFirst(1)
              .get();
          
          print('DEBUG REFERRAL: Query result exists: ${referrerQuery.exists}');
          print('DEBUG REFERRAL: Query children count: ${referrerQuery.children.length}');
          
          // If a referrer was found
          if (referrerQuery.exists && referrerQuery.children.isNotEmpty) {
            final referrerSnapshot = referrerQuery.children.first;
            final referrerData = Map<String, dynamic>.from(referrerSnapshot.value as Map);
            final referrerUid = referrerData['uid'] as String;
            
            print('DEBUG REFERRAL: Found referrer with UID: $referrerUid');
            print('DEBUG REFERRAL: Referrer current credits: ${referrerData['credits']}');
            print('DEBUG REFERRAL: Referrer current referral_count: ${referrerData['referral_count']}');
            
            // Update the new user's data with the referrer's UID
            userData['invited_by'] = referrerUid;
            userData['credits'] = 1000; // 500 default + 500 bonus
            // push_notifications_enabled è già impostato sopra
            
            // Aggiorna il referrer in modo sicuro
            final referrerUserRef = database.ref().child('users').child('users').child(referrerUid);
            
            // Leggi i dati attuali del referrer
            final currentReferrerSnapshot = await referrerUserRef.get();
            if (currentReferrerSnapshot.exists && currentReferrerSnapshot.value is Map) {
              final currentData = Map<String, dynamic>.from(currentReferrerSnapshot.value as Map);
              print('DEBUG REFERRAL: Current referrer data loaded successfully');
              
              List<String> referredUsers = [];
              if (currentData.containsKey('referred_users') && currentData['referred_users'] != null) {
                if (currentData['referred_users'] is List) {
                  referredUsers = List<String>.from(currentData['referred_users']);
                  print('DEBUG REFERRAL: Current referred_users (List): $referredUsers');
                } else if (currentData['referred_users'] is Map) {
                  referredUsers = (currentData['referred_users'] as Map).values.map((v) => v.toString()).toList();
                  print('DEBUG REFERRAL: Current referred_users (Map): $referredUsers');
                }
              } else {
                print('DEBUG REFERRAL: No referred_users found, starting with empty list');
              }
              
              if (!referredUsers.contains(user.uid)) {
                print('DEBUG REFERRAL: Adding new user ${user.uid} to referred_users');
                referredUsers.add(user.uid);
                
                int rewardAmount;
                switch (referredUsers.length) {
                  case 1: rewardAmount = 1000; break;
                  case 2: rewardAmount = 1500; break;
                  case 3: rewardAmount = 3000; break;
                  default: rewardAmount = 1000; break;
                }
                
                final currentCredits = currentData['credits'] as int? ?? 0;
                final newCredits = currentCredits + rewardAmount;
                final newReferralCount = referredUsers.length;
                
                print('DEBUG REFERRAL: Current credits: $currentCredits');
                print('DEBUG REFERRAL: Reward amount: $rewardAmount');
                print('DEBUG REFERRAL: New credits: $newCredits');
                print('DEBUG REFERRAL: New referral_count: $newReferralCount');
                print('DEBUG REFERRAL: Updated referred_users: $referredUsers');
                
                // Aggiorna il referrer
                await referrerUserRef.update({
                  'referred_users': referredUsers,
                  'credits': newCredits,
                  'referral_count': newReferralCount,
                });
                
                print('DEBUG REFERRAL: Successfully updated referrer $referrerUid');
                
                // Verifica che l'aggiornamento sia avvenuto
                final verifySnapshot = await referrerUserRef.get();
                if (verifySnapshot.exists && verifySnapshot.value is Map) {
                  final verifyData = Map<String, dynamic>.from(verifySnapshot.value as Map);
                  print('DEBUG REFERRAL: Verification - credits: ${verifyData['credits']}');
                  print('DEBUG REFERRAL: Verification - referral_count: ${verifyData['referral_count']}');
                  print('DEBUG REFERRAL: Verification - referred_users: ${verifyData['referred_users']}');
                }
              } else {
                print('DEBUG REFERRAL: User ${user.uid} already in referred_users list');
              }
            } else {
              print('DEBUG REFERRAL: No referrer found with code: $referralCodeInput');
            }
          } else {
            print('DEBUG REFERRAL: No referrer found with code: $referralCodeInput');
          }
        } catch (e) {
          print('DEBUG REFERRAL: Error processing referral: $e');
          // Continue with registration even if referral processing fails
        }
      }
      
      // Create the new user document in Realtime Database
      await database
          .ref()
          .child('users')
          .child('users')
          .child(user.uid)
          .set(userData);
      
      // Salva l'utente nella cartella registered_emails per future verifiche
      try {
        if (user.email != null && user.email!.isNotEmpty) {
          await EmailService.saveRegisteredUser(user.email!, user.uid, userData);
          print('Utente salvato nella cartella registered_emails');
        } else {
          print('Email utente Google non disponibile, salto salvataggio in registered_emails');
        }
      } catch (e) {
        print('Errore nel salvare l\'utente in registered_emails: $e');
        // Non bloccare la registrazione se questo fallisce
      }
      
      // Email di benvenuto verrà inviata dopo il completamento del setup del profilo
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OnboardingProfilePage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Errore durante la registrazione: ${e.toString()}',
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // Metodo per completare la registrazione degli utenti Apple dopo l'autenticazione
  Future<void> _completeAppleRegistration(User user, AuthorizationCredentialAppleID appleCredential) async {
    try {
      setState(() => isLoading = true);
      
      // Generate a unique referral code
      final referralCode = _generateReferralCode(user.uid);
      
      // Get Firebase Realtime Database reference
      final database = FirebaseDatabase.instance;
      
      // Check if push notifications are enabled
      final pushNotificationsEnabled = await OneSignalService.areNotificationsEnabled();
      
      // Initialize the user data with default values
      final userData = {
        'uid': user.uid,
        'email': user.email ?? 'apple_user_${user.uid}', // Apple può fornire email anonima
        'referral_code': referralCode,
        'invited_by': null,
        'referred_users': [],
        'referral_count': 0, // Initialize referral count
        'credits': 500, // Default credits
        'push_notifications_enabled': pushNotificationsEnabled, // Salva lo stato delle notifiche push
      };
      
      // Check if a referral code was provided
      final referralCodeInput = _referralCodeController.text.trim();
      if (referralCodeInput.isNotEmpty) {
        try {
          print('DEBUG REFERRAL: Processing referral code: $referralCodeInput');
          
          // Look for the referrer in Realtime Database
          final referrerQuery = await database
              .ref()
              .child('users')
              .child('users')
              .orderByChild('referral_code')
              .equalTo(referralCodeInput)
              .limitToFirst(1)
              .get();
          
          print('DEBUG REFERRAL: Query result exists: ${referrerQuery.exists}');
          print('DEBUG REFERRAL: Query children count: ${referrerQuery.children.length}');
          
          // If a referrer was found
          if (referrerQuery.exists && referrerQuery.children.isNotEmpty) {
            final referrerSnapshot = referrerQuery.children.first;
            final referrerData = Map<String, dynamic>.from(referrerSnapshot.value as Map);
            final referrerUid = referrerData['uid'] as String;
            
            print('DEBUG REFERRAL: Found referrer with UID: $referrerUid');
            print('DEBUG REFERRAL: Referrer current credits: ${referrerData['credits']}');
            print('DEBUG REFERRAL: Referrer current referral_count: ${referrerData['referral_count']}');
            
            // Update the new user's data with the referrer's UID
            userData['invited_by'] = referrerUid;
            userData['credits'] = 1000; // 500 default + 500 bonus
            
            // Aggiorna il referrer in modo sicuro
            final referrerUserRef = database.ref().child('users').child('users').child(referrerUid);
            
            // Leggi i dati attuali del referrer
            final currentReferrerSnapshot = await referrerUserRef.get();
            if (currentReferrerSnapshot.exists && currentReferrerSnapshot.value is Map) {
              final currentData = Map<String, dynamic>.from(currentReferrerSnapshot.value as Map);
              print('DEBUG REFERRAL: Current referrer data loaded successfully');
              
              List<String> referredUsers = [];
              if (currentData.containsKey('referred_users') && currentData['referred_users'] != null) {
                if (currentData['referred_users'] is List) {
                  referredUsers = List<String>.from(currentData['referred_users']);
                  print('DEBUG REFERRAL: Current referred_users (List): $referredUsers');
                } else if (currentData['referred_users'] is Map) {
                  referredUsers = (currentData['referred_users'] as Map).values.map((v) => v.toString()).toList();
                  print('DEBUG REFERRAL: Current referred_users (Map): $referredUsers');
                }
              } else {
                print('DEBUG REFERRAL: No referred_users found, starting with empty list');
              }
              
              if (!referredUsers.contains(user.uid)) {
                print('DEBUG REFERRAL: Adding new user ${user.uid} to referred_users');
                referredUsers.add(user.uid);
                
                int rewardAmount;
                switch (referredUsers.length) {
                  case 1: rewardAmount = 1000; break;
                  case 2: rewardAmount = 1500; break;
                  case 3: rewardAmount = 3000; break;
                  default: rewardAmount = 1000; break;
                }
                
                final currentCredits = currentData['credits'] as int? ?? 0;
                final newCredits = currentCredits + rewardAmount;
                final newReferralCount = referredUsers.length;
                
                print('DEBUG REFERRAL: Current credits: $currentCredits');
                print('DEBUG REFERRAL: Reward amount: $rewardAmount');
                print('DEBUG REFERRAL: New credits: $newCredits');
                print('DEBUG REFERRAL: New referral_count: $newReferralCount');
                print('DEBUG REFERRAL: Updated referred_users: $referredUsers');
                
                // Aggiorna il referrer
                await referrerUserRef.update({
                  'referred_users': referredUsers,
                  'credits': newCredits,
                  'referral_count': newReferralCount,
                });
                
                print('DEBUG REFERRAL: Successfully updated referrer $referrerUid');
                
                // Verifica che l'aggiornamento sia avvenuto
                final verifySnapshot = await referrerUserRef.get();
                if (verifySnapshot.exists && verifySnapshot.value is Map) {
                  final verifyData = Map<String, dynamic>.from(verifySnapshot.value as Map);
                  print('DEBUG REFERRAL: Verification - credits: ${verifyData['credits']}');
                  print('DEBUG REFERRAL: Verification - referral_count: ${verifyData['referral_count']}');
                  print('DEBUG REFERRAL: Verification - referred_users: ${verifyData['referred_users']}');
                }
              } else {
                print('DEBUG REFERRAL: User ${user.uid} already in referred_users list');
              }
            } else {
              print('DEBUG REFERRAL: Failed to load current referrer data');
            }
          } else {
            print('DEBUG REFERRAL: No referrer found with code: $referralCodeInput');
          }
        } catch (e) {
          print('DEBUG REFERRAL: Error processing referral: $e');
          // Continue with registration even if referral processing fails
        }
      }
      
      // Create the new user document in Realtime Database
      await database
          .ref()
          .child('users')
          .child('users')
          .child(user.uid)
          .set(userData);
      
      // Salva l'utente nella cartella registered_emails per future verifiche
      try {
        if (user.email != null && user.email!.isNotEmpty && !user.email!.contains('privaterelay.appleid.com')) {
          await EmailService.saveRegisteredUser(user.email!, user.uid, userData);
          print('Utente Apple salvato nella cartella registered_emails');
        } else {
          print('Email utente Apple anonima o non disponibile, salto salvataggio in registered_emails');
        }
      } catch (e) {
        print('Errore nel salvare l\'utente Apple in registered_emails: $e');
        // Non bloccare la registrazione se questo fallisce
      }
      
      // Email di benvenuto verrà inviata dopo il completamento del setup del profilo
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OnboardingProfilePage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline, color: Colors.red, size: 20),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Errore durante la registrazione Apple: ${e.toString()}',
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            margin: EdgeInsets.all(12),
            elevation: 4,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.initialArguments});

  final Map<String, dynamic>? initialArguments;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final GlobalKey<HomePageState> _homePageKey = GlobalKey<HomePageState>();
  final GlobalKey<PremiumHomePageState> _premiumHomePageKey = GlobalKey<PremiumHomePageState>();
  final GlobalKey<ScheduledPostsPageState> _scheduledPostsPageKey = GlobalKey<ScheduledPostsPageState>();
  final GlobalKey<SocialAccountsPageState> _socialAccountsPageKey = GlobalKey<SocialAccountsPageState>();
  late List<Widget> _pages;
  int _unreadNotifications = 0;
  int _unreadComments = 0;
  int _unreadStars = 0;
  Stream<DatabaseEvent>? _notificationsStream;
  Stream<DatabaseEvent>? _commentsStream;
  Stream<DatabaseEvent>? _starsStream;
  bool? _isPremium; // null = loading
  String? _profileImageUrl; // URL dell'immagine profilo dal database

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _setupNotificationsListener();
    _setupOneSignalUser();
    _loadProfileImage();
  }

  Future<void> _checkPremiumStatus() async {
    if (_currentUser == null) {
      setState(() {
        _isPremium = false;
      });
      return;
    }
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('isPremium')
          .get();
      final newPremiumStatus = (snapshot.value as bool?) ?? false;
      setState(() {
        _isPremium = newPremiumStatus;
      });
      
      // RIMOSSO: Update OneSignal with premium status
    } catch (e) {
      setState(() {
        _isPremium = false;
      });
    }
  }

  void _setupNotificationsListener() {
    if (_currentUser != null) {
      // Listener per notifiche generali
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
        _updateAppBadge();
      });
      
      // Listener per notifiche commenti
      final commentsRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
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
          .child(_currentUser!.uid)
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

  /// Setup OneSignal user identification and tracking
  Future<void> _setupOneSignalUser() async {
    if (_currentUser != null) {
      try {
        await OneSignalService.updateUserProfile(_currentUser);
      } catch (e) {
        print('Error setting up OneSignal user: $e');
      }
    }
  }

  /// Carica l'immagine profilo dal database Firebase
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

  void _onItemTapped(int index) {
    bool isNavigatingToHome = index == 0 && _selectedIndex != 0;
    bool isNavigatingToSocialAccounts = index == 1 && _selectedIndex != 1;
    bool isNavigatingToScheduledPosts = index == 4 && _selectedIndex != 4;
    bool isNavigatingAwayFromScheduledPosts = _selectedIndex == 4 && index != 4;
    
    // Disattiva la pagina scheduled posts se stiamo navigando via da essa
    if (isNavigatingAwayFromScheduledPosts && _scheduledPostsPageKey.currentState != null) {
      _scheduledPostsPageKey.currentState!.deactivatePage();
    }
    
    setState(() {
      _selectedIndex = index;
    });
    
    if (isNavigatingToHome) {
      if (_isPremium == true && _premiumHomePageKey.currentState != null) {
        // Refresh accounts and check progress for premium users
        _premiumHomePageKey.currentState!.refreshSocialAccounts();
        _premiumHomePageKey.currentState!.refreshUserProgress();
      } else if (_isPremium == false && _homePageKey.currentState != null) {
        _homePageKey.currentState!.refreshCredits();
        // Also refresh accounts for regular users
        _homePageKey.currentState!.refreshSocialAccounts();
        _homePageKey.currentState!.refreshUserProgress();
      }
    }
    
    // Refresh social accounts count when navigating to social accounts page
    if (isNavigatingToSocialAccounts && _socialAccountsPageKey.currentState != null) {
      _socialAccountsPageKey.currentState!.refreshAccountsCount();
    }
    
    // Attiva lo scorrimento automatico quando si naviga alla pagina scheduled posts
    if (isNavigatingToScheduledPosts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Aspetta che la pagina sia completamente renderizzata
        Future.delayed(Duration(milliseconds: 300), () {
          if (mounted && _scheduledPostsPageKey.currentState != null) {
            _scheduledPostsPageKey.currentState!.activateAutoScroll();
          }
        });
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

  @override
  void dispose() {
    // I listener si cancellano automaticamente quando il widget viene distrutto
    // Non è necessario cancellarli manualmente per Stream<DatabaseEvent>
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Aggiorna la status bar e navigation bar in base al tema corrente
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      // Status bar (zona con batteria, orario, connessione)
      statusBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS - controlla il colore del testo
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, // Android - controlla il colore delle icone
      // Navigation bar (zona menu in basso per Android) e home indicator iOS
      systemNavigationBarColor: Platform.isIOS ? Colors.transparent : (isDark ? const Color(0xFF121212) : Colors.white),
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
    
    if (_isPremium == null) {
      return Scaffold(
        body: Center(
          child: Lottie.asset(
            'assets/animations/MainScene.json',
            width: 200,
            height: 200,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    _pages = [
      _isPremium == true
          ? PremiumHomePage(key: _premiumHomePageKey)
          : HomePage(key: _homePageKey, initialArguments: widget.initialArguments),
      SocialAccountsPage(key: _socialAccountsPageKey),
      const UploadVideoPage(),
      const HistoryPage(),
      ScheduledPostsPage(key: _scheduledPostsPageKey),
      Platform.isIOS ? const UpgradePremiumIOSPage() : const UpgradePremiumPage(),
    ];
    return DefaultTabController(
      length: _pages.length,
      initialIndex: _selectedIndex,
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // Main content area - no padding, content can scroll behind floating elements
              SafeArea(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _pages,
                ),
              ),
              
              // Floating header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: _buildHeader(),
                ),
              ),

              // Bottom navigation bar fixed; does not move with keyboard
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildFloatingNavBar(),
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
              // Notification prima
              Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsPage(),
                        ),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  if (_unreadNotifications > 0 || _unreadComments > 0 || _unreadStars > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: ((_unreadNotifications + _unreadComments + _unreadStars) > 9) ? 24 : 18,
                          minHeight: 18,
                        ),
                        child: Center(
                          child: Text(
                            '${((_unreadNotifications + _unreadComments + _unreadStars) > 9) ? '9+' : (_unreadNotifications + _unreadComments + _unreadStars)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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

  Widget _buildFloatingNavBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: 20, 
        vertical: Platform.isIOS ? 40 : 16, // 28 - 5 = 23 per iOS (2mm più in alto)
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home, theme, isDark),
              _buildNavItem(1, Icons.account_circle_outlined, Icons.account_circle, theme, isDark),
              _buildNavItem(2, Icons.upload_outlined, Icons.upload, theme, isDark),
              _buildNavItem(3, Icons.history_outlined, Icons.history, theme, isDark),
              _buildNavItem(4, Icons.schedule_outlined, Icons.schedule, theme, isDark, customSize: 20),
              _buildNavItem(5, Icons.star_outline, Icons.star, theme, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, ThemeData theme, bool isDark, {double? customSize}) {
    final isSelected = _selectedIndex == index;
    final iconSize = customSize ?? (isSelected ? 24 : 22);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: isSelected 
              ? ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                        const Color(0xFF667eea),
                        const Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Icon(
                    activeIcon,
                    color: Colors.white,
                    size: iconSize,
                  ),
                )
              : Icon(
                  icon,
                  color: isDark 
                      ? Colors.white.withOpacity(0.6)
                      : Colors.grey,
                  size: iconSize,
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
}



