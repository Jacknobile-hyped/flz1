import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:lottie/lottie.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'dart:io'; // <--- AGGIUNTO per Platform
import 'upgrade_premium_page.dart';
import 'upgrade_premium_ios_page.dart';
import 'refeeral_code_page.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isPremium = false;
  int _userCredits = 0;
  bool _isAdLoadingOrShowing = false;
  DateTime? _lastLoadCreditsTime;

  // Animazione per i crediti
  late AnimationController _creditsAnimationController;
  late Animation<double> _creditsAnimation;
  late AnimationController _numberAnimationController;
  late Animation<double> _numberAnimation;
  int _displayedCredits = 0;
  double _wheelProgress = 0.0;
  bool _hasAnimatedCredits = false;

  RewardedAd? _rewardedAd;
  final String _rewardedAdUnitId = Platform.isAndroid
      ? 'ca-app-pub-7193745489519791/3013557988'
      : 'ca-app-pub-7193745489519791/9347987301';

  @override
  void initState() {
    super.initState();
    
    // Inizializza il Mobile Ads SDK
    MobileAds.instance.initialize();
    
    // Configura il test device ID per ricevere annunci di test
    _configureAdMob();
    
    // Inizializza il controller dell'animazione per la ruota
    _creditsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Inizializza l'animazione della ruota
    _creditsAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _creditsAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    // Inizializza il controller dell'animazione per il numero
    _numberAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Inizializza l'animazione del numero
    _numberAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _numberAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    // Listener per aggiornare il valore visualizzato durante l'animazione del numero
    _numberAnimation.addListener(() {
      setState(() {
        _displayedCredits = _numberAnimation.value.round();
      });
    });
    
    // Listener per aggiornare il progresso della ruota
    _creditsAnimation.addListener(() {
      setState(() {
        _wheelProgress = _creditsAnimation.value / 500.0;
      });
    });
    
    _loadUserCredits();
  }

  // Configura AdMob con test device ID e altre impostazioni
  Future<void> _configureAdMob() async {
    try {
      // Imposta il test device ID per ricevere annunci di test
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
        testDeviceIds: [
          '5030a8db-97d8-41fc-8ae2-10ca1ad1abe1', // Test device ID principale
          '24F5D64EAF3D2818CA7EE64905F89482',     // Test device ID dal log
        ],
      ));
      
      print('[AdMob] Configurazione completata');
      print('[AdMob] Test device IDs configurati:');
      print('[AdMob] - 5030a8db-97d8-41fc-8ae2-10ca1ad1abe1');
      print('[AdMob] - 24F5D64EAF3D2818CA7EE64905F89482');
      
      // Imposta altre configurazioni per migliorare la performance
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.pg,
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
        tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
      ));
      
      print('[AdMob] Configurazioni aggiuntive applicate');
    } catch (e) {
      print('[AdMob] Errore durante la configurazione: $e');
    }
  }

  @override
  void dispose() {
    _creditsAnimationController.dispose();
    _numberAnimationController.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  Future<void> _loadUserCredits() async {
    if (_currentUser == null || !mounted) return;
    
    // Controlliamo se abbiamo già caricato i crediti recentemente (entro 2 minuti)
    final now = DateTime.now();
    if (_lastLoadCreditsTime != null && 
        now.difference(_lastLoadCreditsTime!).inMinutes < 2) {
      return;
    }
    
    _lastLoadCreditsTime = now;
    
    try {
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
          
      final creditsSnapshot = await userRef.child('credits').get();
      final isPremiumSnapshot = await userRef.child('isPremium').get();

      if (!mounted) return;

      bool isPremium = false;
      if (isPremiumSnapshot.exists) {
        isPremium = (isPremiumSnapshot.value as bool?) ?? false;
      }

      int currentCredits = 0;
      if (creditsSnapshot.exists) {
        currentCredits = (creditsSnapshot.value as int?) ?? 0;
      }
      
      setState(() {
        _userCredits = currentCredits;
        _isPremium = isPremium;
        _hasAnimatedCredits = false;
      });
      
      // Avvia l'animazione dei crediti
      if (!_hasAnimatedCredits && _userCredits > 0) {
        _startCreditsAnimation();
      }
    } catch (e) {
      print('Error loading user credits: $e');
    }
  }

  void _startCreditsAnimation() {
    if (!mounted || _userCredits <= 0) return;
    
    double wheelAnimationEndValue = _isPremium ? _userCredits.toDouble() : 500.0;
    
    _creditsAnimation = Tween<double>(
      begin: 0,
      end: wheelAnimationEndValue,
    ).animate(CurvedAnimation(
      parent: _creditsAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _wheelProgress = 0.0;
    
    _numberAnimation = Tween<double>(
      begin: 0,
      end: _userCredits.toDouble(),
    ).animate(CurvedAnimation(
      parent: _numberAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _creditsAnimationController.forward(from: 0);
    _numberAnimationController.forward(from: 0);
    
    _hasAnimatedCredits = true;
  }

  // Method to handle watching ads for credits - versione migliorata con retry e gestione errori
  Future<void> _showRewardedAd() async {
    print('[AdMob] ===== INIZIO _showRewardedAd() =====');
    print('[AdMob] Stato attuale _isAdLoadingOrShowing: $_isAdLoadingOrShowing');
    
    if (_isAdLoadingOrShowing) {
      print('[AdMob] Ad già in caricamento/visualizzazione, ignoro richiesta');
      return;
    }
    
    setState(() {
      _isAdLoadingOrShowing = true;
    });
    print('[AdMob] Stato aggiornato _isAdLoadingOrShowing: $_isAdLoadingOrShowing');
    
    // Mostra snackbar di caricamento
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.white,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.fixed,
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Loading ad...',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    
    // Prova a caricare l'ad con retry
    await _loadRewardedAdWithRetry();
  }

  // Metodo per caricare l'ad con retry automatico
  Future<void> _loadRewardedAdWithRetry({int retryCount = 0}) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    
    print('[AdMob] Tentativo ${retryCount + 1} di $maxRetries');
    
    try {
      await RewardedAd.load(
        adUnitId: _rewardedAdUnitId,
        request: AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) async {
            print('[AdMob] ===== AD CARICATO CON SUCCESSO =====');
            print('[AdMob] Tentativo ${retryCount + 1} riuscito!');
            
            _rewardedAd = ad;
            
            // Configura i callback per il ciclo di vita dell'ad
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdShowedFullScreenContent: (ad) {
                print('[AdMob] Ad mostrato a schermo intero');
              },
              onAdDismissedFullScreenContent: (ad) {
                print('[AdMob] Ad chiuso dall\'utente');
                ad.dispose();
                _rewardedAd = null;
                if (mounted) setState(() => _isAdLoadingOrShowing = false);
              },
                         onAdFailedToShowFullScreenContent: (ad, error) {
             print('[AdMob] Errore nel mostrare l\'ad: ${error.message}');
             ad.dispose();
             _rewardedAd = null;
             if (mounted) setState(() => _isAdLoadingOrShowing = false);
             
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text(
                   'Errore durante la visualizzazione dell\'annuncio',
                   style: TextStyle(color: Colors.black87),
                 ),
                 backgroundColor: Colors.white,
                 duration: Duration(seconds: 3),
               ),
             );
           },
            );
            
            // Mostra l'ad
            try {
              print('[AdMob] Mostro l\'ad...');
              await ad.show(
                onUserEarnedReward: (ad, reward) {
                  print('[AdMob] ===== REWARD EARNED =====');
                  print('[AdMob] Amount: ${reward.amount}, Type: ${reward.type}');
                  _addCreditsForRewardedAd();
                },
              );
              print('[AdMob] Ad mostrato con successo');
                         } catch (e) {
               print('[AdMob] Errore durante ad.show(): $e');
               ad.dispose();
               _rewardedAd = null;
               if (mounted) setState(() => _isAdLoadingOrShowing = false);
               
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(
                   content: Text('Errore durante la visualizzazione dell\'annuncio'),
                   backgroundColor: Colors.white,
                   duration: Duration(seconds: 3),
                 ),
               );
             }
          },
          onAdFailedToLoad: (LoadAdError error) async {
            print('[AdMob] ===== AD FAILED TO LOAD =====');
            print('[AdMob] Errore: ${error.message}');
            print('[AdMob] Codice: ${error.code}');
            print('[AdMob] Dominio: ${error.domain}');
            
            // Gestisci errori specifici
            String errorMessage = 'Unable to load ad';
            if (error.code == 3) { // NO_FILL
              errorMessage = 'No ad available at the moment. Try again later.';
            } else if (error.code == 2) { // NETWORK_ERROR
              errorMessage = 'Network error. Check your connection.';
            } else if (error.code == 1) { // INVALID_REQUEST
              errorMessage = 'Invalid request. Try again.';
            }
            
                         // Se non abbiamo raggiunto il numero massimo di tentativi, riprova
             if (retryCount < maxRetries - 1) {
               print('[AdMob] Riprovo tra ${retryDelay.inSeconds} secondi...');
               
               if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                     content: Text(
                       'Retry automatically... (${retryCount + 1}/$maxRetries)',
                       style: TextStyle(color: Colors.black87),
                     ),
                     backgroundColor: Colors.white,
                     duration: Duration(seconds: 2),
                   ),
                 );
               }
               
               // Aspetta e riprova
               await Future.delayed(retryDelay);
               await _loadRewardedAdWithRetry(retryCount: retryCount + 1);
             } else {
               // Tutti i tentativi falliti
               print('[AdMob] Tutti i tentativi falliti. Interrompo.');
               if (mounted) {
                 setState(() => _isAdLoadingOrShowing = false);
                 
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                     content: Text(
                       errorMessage,
                       style: TextStyle(color: Colors.black87),
                     ),
                     backgroundColor: Colors.white,
                     duration: Duration(seconds: 4),
                     action: SnackBarAction(
                       label: 'Retry',
                       textColor: Colors.black87,
                       onPressed: () {
                         _showRewardedAd();
                       },
                     ),
                   ),
                 );
               }
             }
          },
        ),
      );
    } catch (e) {
      print('[AdMob] Errore generale durante il caricamento: $e');
      
      if (retryCount < maxRetries - 1) {
        print('[AdMob] Riprovo per errore generale...');
        await Future.delayed(retryDelay);
        await _loadRewardedAdWithRetry(retryCount: retryCount + 1);
      } else {
        if (mounted) {
          setState(() => _isAdLoadingOrShowing = false);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'An error occurred. Try again later.',
                style: TextStyle(color: Colors.black87),
              ),
              backgroundColor: Colors.white,
              duration: Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.black87,
                onPressed: () {
                  _showRewardedAd();
                },
              ),
            ),
          );
        }
      }
    }
  }

  // Method to give user credits after watching ad
  Future<void> _addCreditsForRewardedAd() async {
    if (_currentUser == null || !mounted) return;
    
    print('[Credits] Inizio aggiunta crediti per RewardedAd');
    print('[Credits] User ID: ${_currentUser!.uid}');
    print('[Credits] Path: users/users/${_currentUser!.uid}/credits');
    
    try {
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
      
      print('[Credits] Recupero crediti attuali...');
      final creditsSnapshot = await userRef.child('credits').get();
      
      if (!mounted) {
        print('[Credits] Widget non più montato, interrompo operazione');
        return;
      }
      
      int currentCredits = (creditsSnapshot.exists ? (creditsSnapshot.value as int?) : 0) ?? 0;
      print('[Credits] Crediti attuali: $currentCredits');
      print('[Credits] Utente premium: $_isPremium');
      
      int newCredits = _isPremium
          ? currentCredits + 250
          : (currentCredits + 250).clamp(0, double.infinity).toInt();
      
      print('[Credits] Nuovi crediti calcolati: $newCredits');
      
      print('[Credits] Aggiornamento database...');
      await userRef.child('credits').set(newCredits);
      print('[Credits] Database aggiornato con successo');
      
      setState(() {
        _userCredits = newCredits;
      });
      print('[Credits] Stato locale aggiornato: $_userCredits');
      
      // Forza il caricamento dei crediti da Firebase per assicurarsi che i dati siano sincronizzati
      print('[Credits] Forzatura caricamento crediti da Firebase dopo aggiornamento...');
      await _loadUserCredits();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.stars, color: Colors.black87),
              SizedBox(width: 10),
              Text(
                'You earned 250 credits!',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.fixed,
        ),
      );
      print('[Credits] Messaggio di successo mostrato');
    } catch (e) {
      print('[Credits] Errore aggiunta crediti: $e');
      print('[Credits] Stack trace: ${StackTrace.current}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Avvia l'animazione dei crediti solo se non è stata già eseguita
    if (!_hasAnimatedCredits && _userCredits > 0) {
      _startCreditsAnimation();
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
        body: Stack(
          children: [
            // Main content area
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 100, 0, 0),
                child: Column(
                  children: [
                    _buildCreditsIndicator(theme),
                    _buildReferralInviteCard(theme),
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
                      Icons.stars,
                      size: 14,
                      color: const Color(0xFF6C63FF),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Credits',
                      style: TextStyle(
                        color: const Color(0xFF6C63FF),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
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

  Widget _buildCreditsIndicator(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final double percentage = _isPremium ? 1.0 : (_userCredits / 500).clamp(0.0, 1.0);
    final double animatedPercentage = _isPremium ? 1.0 : _wheelProgress.clamp(0.0, 1.0);
    
    const List<Color> creditsGradient = [
      Color(0xFF667eea),
      Color(0xFF764ba2),
    ];
    
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          
          Center(
            child: Column(
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: creditsGradient[0].withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceVariant,
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: CustomPaint(
                          painter: GradientCircularProgressPainter(
                            progress: animatedPercentage,
                            strokeWidth: 20,
                            backgroundColor: theme.colorScheme.surfaceVariant,
                            gradient: LinearGradient(
                              colors: creditsGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ),
                          ),
                        ),
                      ),
                      
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 5,
                              spreadRadius: 1,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.95),
                            ],
                            stops: const [0.7, 1.0],
                          ),
                        ),
                      ),
                      
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return LinearGradient(
                                colors: creditsGradient,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ).createShader(bounds);
                            },
                            child: Text(
                              _isPremium ? '∞' : _displayedCredits.toString(),
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 0.9,
                              ),
                            ),
                          ),
                          Text(
                            _isPremium ? 'Premium' : 'Credits',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF).withOpacity(0.7) : theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                if (_isPremium)
                  Column(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              creditsGradient[0].withOpacity(0.1),
                              creditsGradient[1].withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180),
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: creditsGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ).createShader(bounds);
                          },
                          child: Text(
                            'Uploads illimitati',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                
                if (!_isPremium)
                  Column(
                    children: [
                      // Bottone Watch Ad con crediti integrati
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.75,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(25),
                                onTap: _showRewardedAd,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.ondemand_video, color: Colors.white, size: 20),
                                      SizedBox(width: 10),
                                      Text(
                                        'Watch Ad Now',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        '(+250 credits)',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
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
                      
                      const SizedBox(height: 16),
                      
                      // Bottone Upgrade
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.75,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: creditsGradient,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: creditsGradient[0].withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(25),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => Platform.isIOS
                                          ? const UpgradePremiumIOSPage(suppressExtraPadding: true, fromGettingStarted: true)
                                          : const UpgradePremiumPage(suppressExtraPadding: true, fromGettingStarted: true),
                                    ),
                                  ).then((_) => _loadUserCredits());
                                },
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.star, color: Colors.white, size: 20),
                                      SizedBox(width: 10),
                                      Text(
                                        'Upgrade to Premium',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
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
                
                if (_isPremium)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: creditsGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180),
                          ),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: creditsGradient[0].withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.white, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Premium Active',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
    );
     }

     // Card minimal per invitare l'utente a guadagnare crediti tramite referral code
  Widget _buildReferralInviteCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ReferralCodePage(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          padding: const EdgeInsets.all(20),
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
           child: Row(
             children: [
               Container(
                 padding: const EdgeInsets.all(14),
                 decoration: BoxDecoration(
                   // Icona con effetto vetro semi-trasparente
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
                         ? Colors.black.withOpacity(0.3)
                         : Colors.black.withOpacity(0.15),
                       blurRadius: 10,
                       offset: const Offset(0, 3),
                     ),
                     BoxShadow(
                       color: isDark 
                         ? Colors.white.withOpacity(0.1)
                         : Colors.white.withOpacity(0.4),
                       blurRadius: 1,
                       spreadRadius: -1,
                       offset: const Offset(0, 1),
                     ),
                   ],
                 ),
                 child: ShaderMask(
                   shaderCallback: (Rect bounds) {
                     return LinearGradient(
                       colors: [
                         const Color(0xFF667eea),
                         const Color(0xFF764ba2),
                       ],
                       begin: Alignment.topLeft,
                       end: Alignment.bottomRight,
                     ).createShader(bounds);
                   },
                   child: Icon(
                     Icons.card_giftcard, 
                     color: Colors.white, 
                     size: 28
                   ),
                 ),
               ),
               const SizedBox(width: 18),
               Expanded(
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     ShaderMask(
                       shaderCallback: (Rect bounds) {
                         return LinearGradient(
                           colors: [
                             const Color(0xFF667eea),
                             const Color(0xFF764ba2),
                           ],
                           begin: Alignment.topLeft,
                           end: Alignment.bottomRight,
                         ).createShader(bounds);
                       },
                       child: Text(
                         'Earn extra free credits!',
                         style: theme.textTheme.titleMedium?.copyWith(
                           fontWeight: FontWeight.bold,
                           color: Colors.white,
                         ),
                       ),
                     ),
                     const SizedBox(height: 4),
                     Text(
                       'Invite your friends with your referral code and get bonus credits.',
                       style: theme.textTheme.bodySmall?.copyWith(
                         color: isDark 
                             ? Colors.white.withOpacity(0.7)
                             : theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                       ),
                     ),
                   ],
                 ),
               ),
               const SizedBox(width: 8),
               ShaderMask(
                 shaderCallback: (Rect bounds) {
                   return LinearGradient(
                     colors: [
                       const Color(0xFF667eea),
                       const Color(0xFF764ba2),
                     ],
                     begin: Alignment.topLeft,
                     end: Alignment.bottomRight,
                   ).createShader(bounds);
                 },
                 child: Icon(
                   Icons.arrow_forward_ios,
                   color: Colors.white,
                   size: 16,
                 ),
               ),
             ],
           ),
         ),
       ),
     );
   }
 }
 
 // Custom painter for gradient circular progress indicator
class GradientCircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final LinearGradient gradient;

  GradientCircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Draw background circle
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw progress arc with gradient
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Create gradient shader
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = gradient.createShader(rect);
    progressPaint.shader = shader;

    // Draw the progress arc
    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      rect,
      -3.14159 / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
