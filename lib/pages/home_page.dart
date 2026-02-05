import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/tutorial_provider.dart';
import 'upload_video_page.dart';
import 'dart:io';
import 'social/social_account_details_page.dart';
import 'upgrade_premium_page.dart';
import 'upgrade_premium_ios_page.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'scheduled_posts_page.dart';
import 'scheduled_post_details_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'trends_page.dart';
import 'community_page.dart';
import 'swiftia_videoclip_page.dart';
import '../services/navigation_service.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import '../widgets/notification_permission_dialog.dart';
import '../services/notification_permission_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'multi_video_insights_page.dart';
import 'video_details_page.dart';
import 'draft_details_page.dart';
import 'dart:ui';

class HomePage extends StatefulWidget {
  final Map<String, dynamic>? initialArguments;
  
  const HomePage({super.key, this.initialArguments});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _hasConnectedAccounts = false;
  bool _hasUploadedVideo = false;
  bool _hasCompletedProfile = false;
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _socialAccounts = []; // Added for social accounts
  List<Map<String, dynamic>> _upcomingScheduledPosts = []; // New variable for upcoming scheduled posts
  bool _isLoading = true;
  bool _isWatchingAd = false; // Separate state for ad watching
  bool _isPremium = false; // Premium user status
  int _userCredits = 0; // Default value, will be loaded from database
  String _searchQuery = '';
  
  // Referral code related variables
  String? _referralCode;
  int _referredUsersCount = 0;
  
  // Variable to track if we should show upgrade popup
  bool _shouldShowUpgradePopup = false;
  
  // Variable to track if arguments have been processed
  bool _argumentsProcessed = false;
  
  // Variable to track notification permission status
  bool? _pushNotificationsEnabled;
  bool _notificationDialogShown = false;
  
  // Variables for trends data and animations
  List<Map<String, dynamic>> _topTrends = [];
  late AnimationController _trendChartAnimationController;
  late AnimationController _trendScoreAnimationController;
  late Animation<double> _trendChartAnimation;
  late Animation<double> _trendScoreAnimation;
  late PageController _trendPageController;
  int _currentTrendIndex = 0;
  late PageController _recentVideosPageController;
  int _currentVideoIndex = 0;
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;
  
  // Variable to track if getting started section is expanded
  bool _isGettingStartedExpanded = false;
  
  // Set to track which trend indices have completed their typing animation
  Set<int> _completedTypingAnimations = {};

  // Animazione per i crediti
  late AnimationController _creditsAnimationController;
  late Animation<double> _creditsAnimation;
  late AnimationController _numberAnimationController;
  late Animation<double> _numberAnimation;
  int _displayedCredits = 0;
  double _wheelProgress = 0.0; // Progresso della ruota (0.0 - 1.0)
  bool _hasAnimatedCredits = false; // Flag per tracciare se l'animazione è già stata eseguita

  // Scroll controller e animazione per il bottone floating
  late ScrollController _scrollController;
  late AnimationController _floatingButtonAnimationController;
  late Animation<double> _floatingButtonAnimation;
  bool _showFloatingButton = true;
  double _lastScrollPosition = 0.0;
  late AnimationController _ctaAttentionController;
  late Animation<double> _ctaShakeAnimation;
  bool _ctaAttentionActive = false;

  // Challenges section state (UI only for now)
  int _dailyGoalVideos = 2;
  int _dailyPublishedVideos = 1;
  int _currentStreakDays = 4;
  int _bestStreakDays = 9;
  String _todayCustomChallenge = 'Use a trend';
  int _customChallengeProgress = 0;
  int _customChallengeTarget = 1;
  // Map day key (yyyy-MM-dd) -> number of published videos for that day
  Map<String, int> _publishedVideosPerDay = {};
  // History of completed custom challenges
  List<Map<String, dynamic>> _completedCustomChallenges = [];
  // Last day (millisecondsSinceEpoch) when streak reward has been given
  int? _lastStreakRewardDateEpoch;

  // AI tips rotation state (100 high-signal tips)
  final List<String> _aiTips = [
    // Posting time & frequency
    'Post at the same time for 7 days in a row to see if your audience builds a habit.',
    'Run a "time A vs time B" test this week: post the same format at two different times and compare saves.',
    'If you post once a week, try two short posts + one long post instead of one big upload.',
    'Stop posting only when you are inspired; post on a schedule and use inspiration as a bonus.',
    'Use your analytics to find your 3 best posting hours and only post inside that window for 2 weeks.',

    // Content ideas & hooks
    'Turn your last 5 comments into 5 Q&A videos—audience questions are free content ideas.',
    'Record a "hot take" about your niche today: one thing you believe that most people do not say out loud.',
    'Take your best performing video and record a "part 2" that goes deeper instead of starting from scratch.',
    'Film a simple "before vs after" using the same framing and lighting to show transformation in 5 seconds.',
    'Write 10 hook ideas in text first, then film only the top 3—most creators do the opposite.',
    'Start one video with the exact sentence you would say to a friend, not to an algorithm.',
    'Use the phrase "Most people get this wrong:" in your next hook to trigger curiosity.',
    'Record a video where you explain a concept using only analogies and simple visuals.',
    'Turn a boring process into a "watch me do this in 30 seconds" time-lapse with captions.',
    'Make a video where you disagree with a popular trend in your niche (without attacking creators).',
    'Film a "3 things I would do if I started from zero today" video in your niche.',
    'Record a screen + face video explaining a tool or workflow you actually use every day.',
    'Tell a story in reverse: start from the result, then reveal how you got there step by step.',
    'Use the format "I tried X for 7 days, here is what actually happened" even if the result is small.',
    'Turn a long tutorial into a rapid-fire checklist video with 5–7 bullet points on screen.',

    // Audience psychology & relationship
    'Talk to one specific person in your mind when you film, not to "everyone on the internet".',
    'Share one honest failure story this week—audiences trust people who show their process, not just wins.',
    'Reply to a critical comment with a calm, thoughtful video instead of ignoring it.',
    'Save the names of 10 people who comment often and answer them first when you post.',
    'End one video by asking a question that can be answered with one word in the comments.',
    'When you get a DM with a good question, ask for permission to anonymize it and turn it into content.',
    'Share one belief you changed your mind about in your niche and why.',
    'Use "you" 5x more than "I" in your next script; people care about themselves more than your brand.',
    'Record a video where you apologize for something small you misunderstood and show the updated approach.',
    'Ask your audience to vote between two ideas in the comments and then actually create what they choose.',

    // Storytelling & structure
    'Use a three-act structure in a 30-second video: setup, tension, and payoff.',
    'Hide the main result until the last 5 seconds to keep watch time, but tease it strongly at the start.',
    'Try a video with no cuts for 20 seconds, only one strong idea and your face—no edits, just clarity.',
    'Re-record only the first 3 seconds of a good video to improve the hook instead of trashing the whole clip.',
    'Use on-screen text to "spoiler" the value of the video while your hook is still playing.',
    'Turn a boring metric (like number of followers) into a story about real people you helped.',
    'Write your video as 5 short slides, then record yourself reading and reacting to each slide.',
    'Try a "looped" video where the ending visually matches the beginning so replays feel natural.',
    'Tell a story where you are not the hero, but the guide helping someone else win.',
    'Record a video where you show your face only in the first and last 3 seconds, and visuals in the middle.',

    // Niche depth & authority
    'Make a video that only people deep in your niche will understand—that content builds strongest fans.',
    'Share one unpopular opinion about your niche tools that you discovered from real use, not theory.',
    'Explain a basic concept in your niche as if you were teaching it to a 10-year-old.',
    'Create a "myths vs facts" video with 3 common misconceptions in your topic.',
    'Publish a video where you change your mind in real time while reading new data or feedback.',
    'Show one mistake you still make today, even as an advanced creator in your niche.',
    'Compare two tools or strategies you actually used instead of reading from feature lists.',
    'Film your screen while you fix a real problem you had this week and narrate the decision process.',
    'Share a small framework you secretly use to make decisions (even if it is simple).',
    'Record a "what I would never do again" video for your niche.',

    // Retention & completion
    'Write your script, then remove the slowest sentence—tight scripts win watch time.',
    'Add one tiny visual surprise at second 8–12 (emoji, zoom, text pop) to catch people who are about to scroll.',
    'Use pattern interruption: change your tone or camera angle right when you say something important.',
    'Try ending one video 0.5 seconds earlier than feels comfortable—the brain fills the gap.',
    'Add a micro-reward midway: a quick joke, insight, or visual payoff before the final call to action.',
    'Avoid saying "in this video I will"—start with the actual value instead.',
    'Use "open loops": ask a question early and answer it only near the end of the video.',
    'Show the final result in the first second, then explain how to get there.',
    'Place your most important sentence exactly in the middle of the video where attention usually drops.',
    'Use B-roll of your hands or environment to keep visual motion while you speak.',

    // Repurposing & systems
    'Turn one long YouTube or podcast episode into 10 short clips and schedule them across platforms.',
    'Create one master script per week and adapt only the first 3 seconds for each platform.',
    'Save a folder of "evergreen clips" you can repost every 90 days with a new caption.',
    'Record a horizontal version and a vertical version of the same idea in the same session.',
    'Repost your best 5% of content without changing anything and watch how many people never saw it.',
    'Use templates: build 3 repeatable formats (e.g. tips, stories, reactions) and rotate them.',
    'Batch record all hooks for the week in one session, and record bodies on another day.',
    'When a post goes viral, immediately record a follow-up that references the comments.',
    'Group your ideas in themes (beginner, intermediate, advanced) and schedule them in cycles.',
    'Tag each published video in a simple spreadsheet: idea type, hook type, and result, to learn faster.',

    // Personal brand & positioning
    'Choose one sentence that explains what you do and repeat it in your bio, hooks and captions.',
    'Share a "this is who I am not for" video to filter out the wrong audience.',
    'Show your actual workspace or tools; people connect more with real environments than stock backgrounds.',
    'Tell the origin story of your brand in less than 45 seconds without sounding like a pitch.',
    'Pick one visual element (color, font, overlay) and use it in every video for 30 days.',
    'Show a timeline of your progress with screenshots or clips from older content.',
    'Record a video where you answer "Why did you start this account?" honestly.',
    'Share one thing you stand against in your industry and what you do differently.',
    'Make a "day in the life" video focused on decisions, not aesthetics.',
    'Admit one weakness or limitation and explain how you work around it—that builds trust.',

    // Analytics & iteration
    'Look at your last 20 posts and sort them by saves, not likes—saves show real value.',
    'Double down on the top 3 hooks that got people to watch past 3 seconds.',
    'Check which videos brought the most followers and make siblings of those ideas.',
    'Track only three metrics this month: watch time, saves and shares—ignore vanity metrics.',
    'When a video underperforms, ask: was the idea weak or was the hook unclear?',
    'Run one experiment per week and write the result, even if it fails.',
    'Compare how different platforms react to the same video; note where the audience is more serious vs casual.',
    'If comments show confusion, your next video should clarify, not move to a new topic.',
    'Screenshot your analytics every month to see long-term patterns instead of daily noise.',
    'Use your analytics to find which topics people stop watching, then cut those topics entirely for a month.',

    // Monetization & offers
    'Before selling anything, create a video that explains the problem clearly better than anyone else.',
    'Share a small win from a follower or client instead of always your own results.',
    'Add a soft CTA in only 1 out of 3 videos; the other two should be pure value or story.',
    'Test one video with a direct CTA to your newsletter or waitlist this week.',
    'Use behind-the-scenes content to show how your product or service is actually created.',
    'Create a short FAQ series where each video answers one objection people have before buying.',
    'Use social proof without flexing: "5 people tried this last week and here is what happened."',
    'Record a "who this is for / who this is not for" video about your offer.',
    'Explain the transformation your offer creates using a simple before/after table on screen.',
    'Share what you would recommend to someone who cannot afford your offer yet.',

    // Mindset & creative energy
    'Protect one "no scroll" hour per day where you only create, not consume.',
    'If you feel stuck, copy the structure (not the content) of your last successful video.',
    'Stop judging ideas while brainstorming; collect 20 quickly, then pick 3 the next day with a fresh mind.',
    'Set a tiny rule: you are allowed to delete a bad video, but only after posting the next one.',
    'Use constraints: film a video with only 30 words to force clarity.',
    'When you feel low-energy, record B-roll or simple visuals instead of skipping content entirely.',
    'Remember that your 100th video will make your 1st video look bad—that is a sign of progress.',
    'Once a month, make a video only for fun with zero strategy; sometimes that is what goes viral.',
    'Treat your content like reps at the gym: volume plus form over time beats perfection today.',
    'Remember: people do not remember the one video that failed, they remember the creator who kept going.',
  ];
  int _currentAiTipIndex = 0;
  Timer? _aiTipTimer;
  Timer? _videoScrollTimer;
  Timer? _ctaAttentionTimer;

  // Global keys for tutorial targets
  final GlobalKey _connectAccountsKey = GlobalKey(debugLabel: 'connectAccounts');
  final GlobalKey _uploadVideoKey = GlobalKey(debugLabel: 'uploadVideo');
  final GlobalKey _statsKey = GlobalKey(debugLabel: 'stats');

  RewardedAd? _rewardedAd;
  // Usa sempre l'ID di test per evitare problemi
  final String _rewardedAdUnitId = Platform.isAndroid
      ? 'ca-app-pub-7193745489519791/3013557988' // Android rewarded ad unit ID
      : 'ca-app-pub-7193745489519791/9347987301'; // iOS rewarded ad unit ID
  bool _isAdLoading = false;
  bool _isAdLoadingOrShowing = false;

  // Aggiungiamo un flag per tenere traccia di quando è stata l'ultima volta che abbiamo caricato i crediti
  DateTime? _lastLoadCreditsTime;
  
  // Video player per la card AI Videoclip
  VideoPlayerController? _aiVideoclipVideoController;
  bool _isAiVideoclipVideoReady = false;
  
  // Metodo per forzare il caricamento dei crediti da Firebase (ignora il controllo del timestamp)
  Future<void> _forceLoadUserCredits() async {
    if (_currentUser == null || !mounted) return;
    
    print('[Credits] Forzatura caricamento crediti da Firebase');
    
    try {
      // Load the user's current credit data
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
          
      final creditsSnapshot = await userRef.child('credits').get();
      final isPremiumSnapshot = await userRef.child('isPremium').get();

      if (!mounted) return; // Check if widget is still mounted

      // Get premium status
      bool isPremium = false;
      if (isPremiumSnapshot.exists) {
        isPremium = (isPremiumSnapshot.value as bool?) ?? false;
      }

      // Get current credits
      int currentCredits = 0;
      if (creditsSnapshot.exists) {
        currentCredits = (creditsSnapshot.value as int?) ?? 0;
      }
      
      print('[Credits] Crediti caricati da Firebase: $currentCredits');
      print('[Credits] Utente premium: $isPremium');
      
      // Update the state with the current values and reset animation flag
      setState(() {
        _userCredits = currentCredits;
        _isPremium = isPremium;
        _hasAnimatedCredits = false;
      });
      
      // Aggiorna il timestamp dell'ultimo caricamento
      _lastLoadCreditsTime = DateTime.now();
      
      print('[Credits] Caricamento forzato completato: $currentCredits');
    } catch (e) {
      print('[Credits] Errore caricamento forzato crediti: $e');
    }
  }
  
  // Metodo per inizializzare il video della card AI Videoclip (disabilitato)
  Future<void> _initializeAiVideoclipVideo() async {
    try {
      // Disabilitato: non caricare né riprodurre alcun video per evitare audio indesiderato
      if (_aiVideoclipVideoController != null) {
        try { _aiVideoclipVideoController!.pause(); } catch (_) {}
        await _aiVideoclipVideoController!.dispose();
        _aiVideoclipVideoController = null;
      }
      if (mounted) {
        setState(() {
          _isAiVideoclipVideoReady = false;
        });
      }
    } catch (e) {
      print('Errore inizializzazione video AI Videoclip: $e');
      if (mounted) {
        setState(() {
          _isAiVideoclipVideoReady = false;
        });
      }
    }
  }
  
  Future<void> _loadUserCredits() async {
    if (_currentUser == null || !mounted) return;
    
    // Controlliamo se abbiamo già caricato i crediti recentemente (entro 2 minuti)
    // per evitare di fare troppe chiamate al database
    final now = DateTime.now();
    if (_lastLoadCreditsTime != null && 
        now.difference(_lastLoadCreditsTime!).inMinutes < 2) {
      print('Skip loading credits - last load was less than 2 minutes ago');
      return;
    }
    
    // Aggiorniamo il timestamp dell'ultimo caricamento
    _lastLoadCreditsTime = now;
    
    try {
      // Load the user's current credit data
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid);
          
      final creditsSnapshot = await userRef.child('credits').get();
      final isPremiumSnapshot = await userRef.child('isPremium').get();
      final pushNotificationsSnapshot = await userRef.child('push_notifications_enabled').get();

      if (!mounted) return; // Check if widget is still mounted

      // Get premium status
      bool isPremium = false;
      if (isPremiumSnapshot.exists) {
        isPremium = (isPremiumSnapshot.value as bool?) ?? false;
      }

      // Get current credits
      int currentCredits = 0;
      if (creditsSnapshot.exists) {
        currentCredits = (creditsSnapshot.value as int?) ?? 0;
      }
      
      // Get push notifications status
      bool? pushNotificationsEnabled;
      if (pushNotificationsSnapshot.exists) {
        pushNotificationsEnabled = (pushNotificationsSnapshot.value as bool?) ?? false;
      }
      
      print('Crediti attuali: $currentCredits');
      print('Utente premium: $isPremium');
      print('Push notifications enabled: $pushNotificationsEnabled');
      
      print('Caricamento crediti completato: $currentCredits');
      
      // Update the state with the current values and reset animation flag
      setState(() {
        _userCredits = currentCredits;
        _isPremium = isPremium;
        _pushNotificationsEnabled = pushNotificationsEnabled;
        _hasAnimatedCredits = false;
      });
      
      // In questo caso non avviamo l'animazione direttamente
      // Sarà avviata nel metodo build quando il widget verrà ricostruito
      
      // Check for upgrade popup after loading user data
      if (!_shouldShowUpgradePopup && !_argumentsProcessed) {
        _checkForUpgradePopup();
      }
      
      // Check for notification permission dialog
      // _checkNotificationPermission(); // DISABLED: Notification popup disabled
    } catch (e) {
      print('Error loading user credits: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Inizializza il Mobile Ads SDK
    MobileAds.instance.initialize();
    // Imposta il test device ID (sostituisci con il tuo vero ID dopo il primo log)
    MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
      testDeviceIds: ['5030a8db-97d8-41fc-8ae2-10ca1ad1abe1'],
    ));
    print('[AdMob] Test device ID configurato: 5030a8db-97d8-41fc-8ae2-10ca1ad1abe1');
    // Reset _argumentsProcessed se ci sono nuovi argomenti
    if (widget.initialArguments != null && widget.initialArguments!['showUpgradePopup'] == true) {
      _argumentsProcessed = false;
    }
    
    // Inizializza il controller dell'animazione per la ruota
    _creditsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Durata di 1.5 secondi per l'animazione
    );
    
    // Inizializza l'animazione della ruota
    _creditsAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _creditsAnimationController,
        curve: Curves.easeOutCubic, // Curva di animazione più naturale
      ),
    );
    
    // Inizializza il controller dell'animazione per il numero
    _numberAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Durata di 1.5 secondi per l'animazione
    );
    
    // Inizializza l'animazione del numero
    _numberAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _numberAnimationController,
        curve: Curves.easeOutCubic, // Curva di animazione più naturale
      ),
    );
    
    // Listener per aggiornare il valore visualizzato durante l'animazione del numero
    _numberAnimation.addListener(() {
      setState(() {
        _displayedCredits = _numberAnimation.value.round();
      });
    });
    
    // Initialize animation controllers for trends
    _trendChartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _trendChartAnimation = CurvedAnimation(
      parent: _trendChartAnimationController,
      curve: Curves.easeOutCubic,
    );
    
    _trendScoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _trendScoreAnimation = CurvedAnimation(
      parent: _trendScoreAnimationController,
      curve: Curves.easeOutCubic,
    );
    
    // Initialize page controller for horizontal scrolling
    _trendPageController = PageController(viewportFraction: 0.9);
    _recentVideosPageController = PageController(viewportFraction: 0.85);
    
    // Initialize typing animation controller
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _typingAnimation = CurvedAnimation(
      parent: _typingAnimationController,
      curve: Curves.easeInOut,
    );
    
    // Initialize scroll controller per il bottone floating
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
    
    // Initialize animation controller per il bottone floating
    _floatingButtonAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _floatingButtonAnimation = CurvedAnimation(
      parent: _floatingButtonAnimationController,
      curve: Curves.easeInOut,
    );
    _floatingButtonAnimationController.value = 1.0; // Inizia visibile
    
    _ctaAttentionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ctaShakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -5.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -5.0, end: 5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5.0, end: -3.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(
        parent: _ctaAttentionController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Listener per aggiornare il progresso della ruota
    _creditsAnimation.addListener(() {
      setState(() {
        _wheelProgress = _creditsAnimation.value / 500.0; // Normalizza a 0.0 - 1.0
      });
    });
    
    _loadUserCredits();
    _loadChallengesSettings();
    _loadVideos();
    loadSocialAccounts();
    _loadUpcomingScheduledPosts(); // Load upcoming scheduled posts
    _loadTopTrends(); // Load trends data
    checkUserProgress();
    
    // Inizializza il video player per la card AI Videoclip
    _initializeAiVideoclipVideo();
    
    // Non precaricare gli annunci all'avvio
    // Delay the setup of tutorial keys to ensure the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupTutorialKeys();
      
      // Registro gli observer per i cambi di route
      final route = ModalRoute.of(context);
      if (route != null) {
        // Aggiungi un observer al route
        route.addScopedWillPopCallback(() {
          // Quando la route è pronta ad essere rimossa, resettiamo il flag
          setState(() {
            _hasAnimatedCredits = false;
          });
          // Restituiamo false per non impedire la navigazione
          return Future.value(false);
        });
      }
      
      // Check if we should show upgrade popup
      _checkForUpgradePopup();
    });
    
          // Set up a periodic timer to check upcoming scheduled posts every minute
    // ma non ricarichiamo i crediti ogni minuto
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        _loadUpcomingScheduledPosts();
        _loadTopTrends(); // Load trends data periodically
        // Non carichiamo i crediti qui per evitare rallentamenti
      } else {
        timer.cancel();
      }
    });

    // Rotate AI tips every 30 seconds
    _aiTipTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted || _aiTips.isEmpty) return;
      setState(() {
        _currentAiTipIndex =
            (_currentAiTipIndex + 1) % _aiTips.length;
      });
    });

    // Auto-scroll videos every 5 seconds
    _videoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      
      final recentVideos = _videos
          .where((video) => (video['status'] as String? ?? 'published') == 'published')
          .take(3)
          .toList();
      
      if (recentVideos.length <= 1) return;
      
      if (_recentVideosPageController.hasClients) {
        final nextIndex = (_currentVideoIndex + 1) % recentVideos.length;
        _recentVideosPageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _floatingButtonAnimationController.dispose();
    _ctaAttentionController.dispose();
    _creditsAnimationController.dispose();
    _numberAnimationController.dispose();
    _trendChartAnimationController.dispose();
    _trendScoreAnimationController.dispose();
    _trendPageController.dispose();
    _recentVideosPageController.dispose();
    _typingAnimationController.dispose();
    _rewardedAd?.dispose();
    _aiVideoclipVideoController?.dispose();
    _aiTipTimer?.cancel();
    _videoScrollTimer?.cancel();
    _ctaAttentionTimer?.cancel();
    super.dispose();
  }

  // Gestisce lo scroll per mostrare/nascondere il bottone floating
  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isScrollingUp = currentScroll < _lastScrollPosition;
    
    // Se siamo vicini alla fine della pagina (entro 50 pixel)
    if (maxScroll > 0 && currentScroll >= maxScroll - 50) {
      // Nascondi il bottone quando si arriva in fondo
      if (_showFloatingButton) {
        setState(() {
          _showFloatingButton = false;
        });
        _floatingButtonAnimationController.reverse();
      }
    } else if (isScrollingUp && currentScroll > 0) {
      // Mostra il bottone solo quando si scorre verso l'alto
      if (!_showFloatingButton) {
        setState(() {
          _showFloatingButton = true;
        });
        _floatingButtonAnimationController.forward();
      }
    }
    
    // Aggiorna la posizione precedente
    _lastScrollPosition = currentScroll;
  }

  void _updateCtaAttentionAnimation(bool hasConnectedAccounts) {
    final shouldAnimate = !hasConnectedAccounts && mounted;
    
    if (shouldAnimate && !_ctaAttentionActive) {
      // Avvia un timer che attiva l'animazione ogni 3 secondi
      _ctaAttentionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!mounted || _hasConnectedAccounts) {
          timer.cancel();
          _ctaAttentionController.stop();
          _ctaAttentionController.reset();
          _ctaAttentionActive = false;
          return;
        }
        // Avvia l'animazione una volta
        _ctaAttentionController.forward(from: 0);
      });
      // Avvia subito la prima animazione
      _ctaAttentionController.forward(from: 0);
      _ctaAttentionActive = true;
    } else if (!shouldAnimate && _ctaAttentionActive) {
      _ctaAttentionTimer?.cancel();
      _ctaAttentionTimer = null;
      _ctaAttentionController.stop();
      _ctaAttentionController.reset();
      _ctaAttentionActive = false;
    }
  }

  void _setupTutorialKeys() {
    if (!mounted) return;
    final tutorialProvider = Provider.of<TutorialProvider>(context, listen: false);
    tutorialProvider.setTargetKey(1, _connectAccountsKey);
    tutorialProvider.setTargetKey(2, _uploadVideoKey);
    tutorialProvider.setTargetKey(3, _statsKey);
  }

  // Method to check if we should show upgrade popup
  void _checkForUpgradePopup() {
    // Prevent multiple calls
    if (_shouldShowUpgradePopup || _argumentsProcessed) return;
    
    // Don't show popup if user is premium
    if (_isPremium) return;
    
    // Check if we have arguments from navigation
    final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    // Also check initial arguments passed to the widget
    final initialArgs = widget.initialArguments;
    
    // Check both navigation arguments and initial arguments
    bool shouldShow = false;
    if (arguments != null && arguments['showUpgradePopup'] == true) {
      shouldShow = true;
    } else if (initialArgs != null && initialArgs['showUpgradePopup'] == true) {
      shouldShow = true;
    }
    
    if (shouldShow && !_isPremium) {
      // Mark arguments as processed
      _argumentsProcessed = true;
      setState(() {
        _shouldShowUpgradePopup = true;
      });
      // Show popup after a short delay
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && _shouldShowUpgradePopup) {
          _showUpgradePopup();
        }
      });
    } else if (shouldShow && _isPremium) {
      // Se premium, consuma comunque l'argomento ma NON mostrare il popup
      _shouldShowUpgradePopup = false;
      _argumentsProcessed = true;
    }
  }

  // Method to check and show notification permission dialog
  void _checkNotificationPermission() {
    // Use the centralized service to check if we should show the dialog
    if (!NotificationPermissionService.shouldShowPermissionDialog(_pushNotificationsEnabled, _notificationDialogShown)) {
      return;
    }
    
    // Show dialog after a delay to avoid conflicts with other popups
    // For testing, reduced delay to 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && NotificationPermissionService.shouldShowPermissionDialog(_pushNotificationsEnabled, _notificationDialogShown)) {
        _showNotificationPermissionDialog();
      }
    });
  }

  // Method to show the notification permission dialog
  void _showNotificationPermissionDialog() {
    if (_notificationDialogShown) return;
    
    setState(() {
      _notificationDialogShown = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return NotificationPermissionDialog();
      },
    ).then((permissionGranted) {
      // Update local state based on the result
      if (permissionGranted == true) {
        setState(() {
          _pushNotificationsEnabled = true;
        });
        print('Notification permission granted');
      } else {
        print('Notification permission skipped or denied');
      }
    });
  }

  // Method to show the upgrade popup
  void _showUpgradePopup() {
    // Don't show popup if user is premium
    if (_isPremium) {
      setState(() {
        _shouldShowUpgradePopup = false;
      });
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _UpgradePopupDialog(
          onClose: () {
            Navigator.of(context).pop();
            setState(() {
              _shouldShowUpgradePopup = false;
              // Mark as processed to prevent showing again
              _argumentsProcessed = true;
            });
          },
          onUpgrade: () {
            Navigator.of(context).pop();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Platform.isIOS
                    ? const UpgradePremiumIOSPage(suppressExtraPadding: true)
                    : const UpgradePremiumPage(suppressExtraPadding: true),
              ),
            ).then((_) {
              // Check progress when returning, ma non ricarichiamo i crediti
              checkUserProgress();
            });
          },
        );
      },
    );
  }

  Future<void> checkUserProgress() async {
    if (_currentUser == null || !mounted) return;

    try {
      // Check if user has connected any social accounts - try both paths
      bool hasConnectedAccounts = false;
      
      // Try first path: users/{uid}/social_accounts
      final accountsSnapshot1 = await _database
          .child('users')
          .child(_currentUser.uid)
          .child('social_accounts')
          .get();

      if (!mounted) return;

      if (accountsSnapshot1.exists) {
        final accounts = accountsSnapshot1.value as Map<dynamic, dynamic>;
        hasConnectedAccounts = accounts.isNotEmpty;
      }

      // If not found in first path, try second path: users/users/{uid}/social_accounts
      if (!hasConnectedAccounts) {
        final accountsSnapshot2 = await _database
            .child('users')
            .child('users')
            .child(_currentUser.uid)
            .child('social_accounts')
            .get();

        if (!mounted) return;

        if (accountsSnapshot2.exists) {
          final accounts = accountsSnapshot2.value as Map<dynamic, dynamic>;
          hasConnectedAccounts = accounts.isNotEmpty;
        }
      }

      setState(() {
        _hasConnectedAccounts = hasConnectedAccounts;
      });
      _updateCtaAttentionAnimation(hasConnectedAccounts);

      // Check if user has uploaded any videos
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser.uid)
          .child('videos')
          .get();

      if (!mounted) return;

      bool hasPublishedVideo = false;
      if (videosSnapshot.exists) {
        final videos = videosSnapshot.value as Map<dynamic, dynamic>;
        
        // Check for any published videos (not just existence of videos)
        if (videos.isNotEmpty) {
          videos.forEach((key, value) {
            if (value is Map) {
              String status = value['status']?.toString() ?? 'published';
              final publishedAt = value['published_at'] as int?;
              final scheduledTime = value['scheduled_time'] as int?;
              final accounts = value['accounts'] as Map<dynamic, dynamic>? ?? {};
              final hasYouTube = accounts.containsKey('YouTube');
              
              // Gestisci i video YouTube schedulati con data passata
              if (status == 'scheduled' && hasYouTube && scheduledTime != null) {
                final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
                final now = DateTime.now();
                if (scheduledDateTime.isBefore(now)) {
                  status = 'published';
                }
              }
              
              if (status == 'published' || 
                  (status == 'scheduled' && publishedAt != null)) {
              hasPublishedVideo = true;
              }
            }
          });
        }
        
        // Controlla anche i scheduled_posts per YouTube con data passata
        final scheduledPostsSnapshot = await _database
            .child('users')
            .child('users')
            .child(_currentUser.uid)
            .child('scheduled_posts')
            .get();
            
        if (!mounted) return;
        
        if (scheduledPostsSnapshot.exists && !hasPublishedVideo) {
          final scheduledPosts = scheduledPostsSnapshot.value as Map<dynamic, dynamic>;
          scheduledPosts.forEach((key, value) {
            if (value is Map) {
              String status = value['status']?.toString() ?? 'scheduled';
              final scheduledTime = value['scheduled_time'] as int?;
              final accounts = value['accounts'] as Map<dynamic, dynamic>? ?? {};
              final platforms = accounts.keys.map((e) => e.toString().toLowerCase()).toList();
              final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
              final hasYouTube = accounts.containsKey('YouTube');
              
              if (status == 'scheduled' && isOnlyYouTube && hasYouTube && scheduledTime != null) {
                final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
                final now = DateTime.now();
                if (scheduledDateTime.isBefore(now)) {
                  hasPublishedVideo = true;
                }
              }
            }
          });
        }
        
        setState(() {
          _hasUploadedVideo = hasPublishedVideo;
        });
      }

      // Check if user has premium status
      final isPremiumSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser.uid)
          .child('isPremium')
          .get();

      if (!mounted) return;

      // Set premium status based on database value
      bool isPremium = false;
      if (isPremiumSnapshot.exists) {
        isPremium = (isPremiumSnapshot.value as bool?) ?? false;
      }

      setState(() {
        _hasCompletedProfile = isPremium;
        _isPremium = isPremium; // Update premium status
      });
    } catch (e) {
      print('Error checking user progress: $e');
    }
  }

  Future<void> _loadVideos() async {
    if (_currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final List<Map<String, dynamic>> videosList = [];
      
      // Carica i video da 'videos'
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser.uid)
          .child('videos')
          .get();

      if (!mounted) return; // Check if widget is still mounted

      if (videosSnapshot.exists) {
        final data = videosSnapshot.value as Map<dynamic, dynamic>;
        videosList.addAll(data.entries.map((entry) {
            final videoData = entry.value as Map<dynamic, dynamic>;
            final videoId = entry.key?.toString();
            final userId = videoData['user_id']?.toString();
            final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
          
          // Gestisci lo status come in history_page.dart
          String status = videoData['status']?.toString() ?? 'published';
          final publishedAt = videoData['published_at'] as int?;
          final scheduledTime = videoData['scheduled_time'] as int?;
          final fromScheduler = videoData['from_scheduler'] == true;
          
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
          
          // Gestisci i video YouTube schedulati con data passata
          if (status == 'scheduled') {
            final accounts = videoData['accounts'] as Map<dynamic, dynamic>? ?? {};
            final hasYouTube = accounts.containsKey('YouTube');
            if (hasYouTube && scheduledTime != null) {
              final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (scheduledDateTime.isBefore(now)) {
                status = 'published';
              }
            } else if (!hasYouTube) {
              if (publishedAt != null) {
                status = 'published';
              }
            }
          }
          
          if (publishedAt != null && (status == 'scheduled' || fromScheduler)) {
            status = 'published';
          }
            
            return {
              'id': entry.key,
              'title': videoData['title'] ?? '',
              'description': videoData['description'] ?? '',
              'duration': videoData['duration'] ?? '0:00',
              'uploadDate': _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(videoData['timestamp'] ?? 0)),
            'status': status,
              'video_path': isNewFormat ? (videoData['media_url'] ?? '') : (videoData['video_path'] ?? ''),
              'thumbnail_path': isNewFormat ? (videoData['thumbnail_url'] ?? '') : (videoData['thumbnail_path'] ?? ''),
              'thumbnail_url': videoData['thumbnail_url'],
              'thumbnail_cloudflare_url': videoData['thumbnail_cloudflare_url'] ?? '',
              'timestamp': videoData['timestamp'] ?? 0,
              'created_at': videoData['created_at'],
              'platforms': List<String>.from(videoData['platforms'] ?? []),
              'accounts': videoData['accounts'] ?? {},
              'user_id': videoData['user_id'] ?? '',
              'scheduled_time': videoData['scheduled_time'],
            'published_at': publishedAt,
              'youtube_video_id': videoData['youtube_video_id'],
              'is_image': videoData['is_image'] ?? false,
              'video_duration_seconds': videoData['video_duration_seconds'],
              'video_duration_minutes': videoData['video_duration_minutes'],
              'video_duration_remaining_seconds': videoData['video_duration_remaining_seconds'],
              'cloudflare_urls': videoData['cloudflare_urls'],
            };
        }).where((video) => video != null).cast<Map<String, dynamic>>());
      }
      
      // Carica anche i scheduled_posts per YouTube con data passata
      final scheduledPostsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser.uid)
          .child('scheduled_posts')
          .get();
          
      if (scheduledPostsSnapshot.exists && !mounted) return;
      
      if (scheduledPostsSnapshot.exists) {
        final scheduledData = scheduledPostsSnapshot.value as Map<dynamic, dynamic>;
        videosList.addAll(scheduledData.entries.map((entry) {
          final postData = entry.value as Map<dynamic, dynamic>;
          try {
            String status = postData['status']?.toString() ?? 'scheduled';
            final scheduledTime = postData['scheduled_time'] as int?;
            final accounts = postData['accounts'] as Map<dynamic, dynamic>? ?? {};
            final platforms = accounts.keys.map((e) => e.toString().toLowerCase()).toList();
            final isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
            final hasYouTube = accounts.containsKey('YouTube');
            
            // Solo per YouTube schedulati con data passata
            if (status == 'scheduled' && isOnlyYouTube && hasYouTube && scheduledTime != null) {
              final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (scheduledDateTime.isBefore(now)) {
                status = 'published';
                
                final videoId = entry.key?.toString();
                final userId = postData['user_id']?.toString() ?? _currentUser.uid;
                final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
                
                return {
                  'id': entry.key,
                  'title': postData['title'] ?? '',
                  'description': postData['description'] ?? '',
                  'duration': postData['duration'] ?? '0:00',
                  'uploadDate': _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(postData['timestamp'] ?? scheduledTime)),
                  'status': status,
                  'video_path': isNewFormat ? (postData['media_url'] ?? '') : (postData['video_path'] ?? ''),
                  'thumbnail_path': isNewFormat ? (postData['thumbnail_url'] ?? '') : (postData['thumbnail_path'] ?? ''),
                  'thumbnail_url': postData['thumbnail_url'],
                  'thumbnail_cloudflare_url': postData['thumbnail_cloudflare_url'] ?? '',
                  'timestamp': postData['timestamp'] ?? scheduledTime,
                  'created_at': postData['created_at'],
                  'platforms': List<String>.from(postData['platforms'] ?? platforms.map((e) => e.toString().toUpperCase())),
                  'accounts': accounts,
                  'user_id': userId,
                  'scheduled_time': scheduledTime,
                  'published_at': null,
                  'youtube_video_id': postData['youtube_video_id'],
                  'is_image': postData['is_image'] ?? false,
                  'video_duration_seconds': postData['video_duration_seconds'],
                  'video_duration_minutes': postData['video_duration_minutes'],
                  'video_duration_remaining_seconds': postData['video_duration_remaining_seconds'],
                  'cloudflare_urls': postData['cloudflare_urls'],
                };
              }
            }
            return null;
          } catch (e) {
            print('Error processing scheduled post: $e');
            return null;
          }
        }).where((video) => video != null).cast<Map<String, dynamic>>());
      }
      
      // Ordina i video
      videosList.sort((a, b) {
              final aVideoId = a['id']?.toString();
              final aUserId = a['user_id']?.toString();
              final aIsNewFormat = aVideoId != null && aUserId != null && aVideoId.contains(aUserId);
              
              final bVideoId = b['id']?.toString();
              final bUserId = b['user_id']?.toString();
              final bIsNewFormat = bVideoId != null && bUserId != null && bVideoId.contains(bUserId);
              
              int aTime;
              if (aIsNewFormat) {
                aTime = a['scheduled_time'] as int? ?? 
                       (a['created_at'] is int ? a['created_at'] : int.tryParse(a['created_at']?.toString() ?? '') ?? 0) ??
                       (a['timestamp'] is int ? a['timestamp'] : int.tryParse(a['timestamp'].toString()) ?? 0);
              } else {
                aTime = a['timestamp'] is int ? a['timestamp'] : int.tryParse(a['timestamp'].toString()) ?? 0;
              }
              
              int bTime;
              if (bIsNewFormat) {
                bTime = b['scheduled_time'] as int? ?? 
                       (b['created_at'] is int ? b['created_at'] : int.tryParse(b['created_at']?.toString() ?? '') ?? 0) ??
                       (b['timestamp'] is int ? b['timestamp'] : int.tryParse(b['timestamp'].toString()) ?? 0);
              } else {
                bTime = b['timestamp'] is int ? b['timestamp'] : int.tryParse(b['timestamp'].toString()) ?? 0;
              }
        
        // Per i video YouTube schedulati con data passata, usa scheduled_time come timestamp
        final aStatus = a['status'] as String? ?? '';
        final aScheduledTime = a['scheduled_time'] as int?;
        final aAccounts = a['accounts'] as Map<dynamic, dynamic>? ?? {};
        final aHasYouTube = aAccounts.containsKey('YouTube');
        if (aStatus == 'published' && aHasYouTube && aScheduledTime != null) {
          aTime = aScheduledTime;
        }
        
        final bStatus = b['status'] as String? ?? '';
        final bScheduledTime = b['scheduled_time'] as int?;
        final bAccounts = b['accounts'] as Map<dynamic, dynamic>? ?? {};
        final bHasYouTube = bAccounts.containsKey('YouTube');
        if (bStatus == 'published' && bHasYouTube && bScheduledTime != null) {
          bTime = bScheduledTime;
        }
              
              return bTime.compareTo(aTime);
            });
      
      if (mounted) {
        setState(() {
          _videos = videosList;
          _isLoading = false;
        });
        // Recalculate challenges based on the latest videos
        _recalculateChallengesFromVideos();
      }
    } catch (e) {
      print('Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Recalculate daily goal progress and streaks from the user's published videos
  void _recalculateChallengesFromVideos() {
    if (!mounted) return;

    // Map of day (year, month, day) -> number of published videos
    final Map<DateTime, int> publishedPerDay = {};
    final Map<String, int> publishedPerDayKeys = {};

    for (final video in _videos) {
      final status = (video['status'] ?? '').toString();
      if (status != 'published') continue;

      // Per i video YouTube schedulati con data passata, usa scheduled_time invece di timestamp
      int timestamp = video['timestamp'] as int? ?? 0;
      final scheduledTime = video['scheduled_time'] as int?;
      final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
      final hasYouTube = accounts.containsKey('YouTube');
      
      if (status == 'published' && hasYouTube && scheduledTime != null) {
        // Usa scheduled_time per i video YouTube schedulati con data passata
        timestamp = scheduledTime;
      }
      
      if (timestamp <= 0) continue;

      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final dayKey = DateTime(dateTime.year, dateTime.month, dateTime.day);

      publishedPerDay[dayKey] = (publishedPerDay[dayKey] ?? 0) + 1;
      final keyString =
          '${dayKey.year.toString().padLeft(4, '0')}-${dayKey.month.toString().padLeft(2, '0')}-${dayKey.day.toString().padLeft(2, '0')}';
      publishedPerDayKeys[keyString] =
          (publishedPerDayKeys[keyString] ?? 0) + 1;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Daily goal: how many videos published today
    final int dailyCount = publishedPerDay[today] ?? 0;

    // Current streak: consecutive days (starting from today backwards) with at least 1 published video
    int currentStreak = 0;
    DateTime cursor = today;
    while (true) {
      final countForDay = publishedPerDay[cursor] ?? 0;
      if (countForDay >= 1) {
        currentStreak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    // Best streak (record): longest sequence of consecutive days with at least 1 published video
    int bestStreak = 0;
    int currentSegment = 0;
    DateTime? previousDay;

    final sortedDays = publishedPerDay.keys.toList()..sort();
    for (final day in sortedDays) {
      final countForDay = publishedPerDay[day] ?? 0;
      if (countForDay >= 1) {
        if (previousDay != null && day.difference(previousDay).inDays == 1) {
          currentSegment++;
        } else {
          currentSegment = 1;
        }
        if (currentSegment > bestStreak) {
          bestStreak = currentSegment;
        }
        previousDay = day;
      }
    }

    setState(() {
      _dailyPublishedVideos = dailyCount;
      _currentStreakDays = currentStreak;
      _bestStreakDays = bestStreak;
      _publishedVideosPerDay = publishedPerDayKeys;
    });

    // Reward streak continuation: if user posted at least 1 video today and has not been rewarded yet today
    final bool hasPostedToday = dailyCount > 0;
    if (hasPostedToday) {
      final todayKey = DateTime(today.year, today.month, today.day).millisecondsSinceEpoch;
      bool alreadyRewardedToday = false;
      if (_lastStreakRewardDateEpoch != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(_lastStreakRewardDateEpoch!);
        alreadyRewardedToday =
            last.year == today.year && last.month == today.month && last.day == today.day;
      }
      if (!alreadyRewardedToday) {
        _lastStreakRewardDateEpoch = todayKey;
        _addViralystScoreForStreak(100);
      }
    }

    // Persist updated streak and daily goal configuration
    _saveChallengesToDatabase();
  }

  Future<void> _loadUpcomingScheduledPosts() async {
    if (_currentUser == null || !mounted) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fifteenMinutesFromNow = now + (15 * 60 * 1000); // 15 minutes in milliseconds
      
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('videos')
          .get();

      if (!snapshot.exists || !mounted) return;

      final data = snapshot.value as Map<dynamic, dynamic>;
      final upcomingPosts = data.entries.map((entry) {
        final post = entry.value as Map<dynamic, dynamic>;
        
        // Only include posts with status 'scheduled' and scheduled within the next 15 minutes
        if (post['status'] != 'scheduled') return null;
        
        // Skip if already published
        if (post['published_at'] != null) return null;
        
        // Check if scheduledTime is within the next 15 minutes
        final scheduledTime = post['scheduled_time'] as int?;
        if (scheduledTime == null || scheduledTime < now || scheduledTime > fifteenMinutesFromNow) return null;
        
        return {
          'id': entry.key.toString(),
          'scheduledTime': scheduledTime,
          'description': post['description']?.toString() ?? '',
          'title': post['title']?.toString() ?? '',
          'platforms': (post['platforms'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          'thumbnail_path': post['thumbnail_path']?.toString() ?? '',
          'video_path': post['video_path']?.toString() ?? '',
          'accounts': Map<String, dynamic>.from(post['accounts'] as Map<dynamic, dynamic>? ?? {}),
          'status': 'scheduled',
          'timestamp': post['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        };
      })
      .where((post) => post != null)
      .cast<Map<String, dynamic>>()
      .toList();
      
      // Sort by scheduled time (ascending)
      upcomingPosts.sort((a, b) {
        final aTime = a['scheduledTime'] as int;
        final bTime = b['scheduledTime'] as int;
        return aTime.compareTo(bTime);
      });

      if (mounted) {
        setState(() {
          _upcomingScheduledPosts = upcomingPosts;
        });
      }
    } catch (e) {
      print('Error loading upcoming scheduled posts: $e');
    }
  }

  Future<void> loadSocialAccounts() async {
    if (_currentUser == null || !mounted) return;

    try {
      List<Map<String, dynamic>> accountsList = [];
      Set<String> loadedAccountIds = {}; // Track loaded account IDs to prevent duplicates
      Set<String> processedTwitterUsernames = {}; // Track processed Twitter usernames
      
      // Helper function to update UI with current accounts
      void updateUI() {
        if (!mounted) return;
        setState(() {
          _socialAccounts = List.from(accountsList);
        });
      }
      
      // Helper function to add account and update UI
      void addAccount(Map<String, dynamic> account) {
        accountsList.add(account);
        updateUI(); // Update UI immediately when account is added
      }
      
      // STEP 1: Check direct structure under users/{uid}
      final userAccountsSnapshot = await _database
          .child('users')
          .child(_currentUser!.uid)
          .get();
          
      if (!mounted) return;
          
      if (userAccountsSnapshot.exists && userAccountsSnapshot.value is Map) {
        final userData = userAccountsSnapshot.value as Map<dynamic, dynamic>;
        
        // Extract TikTok accounts FIRST (priority)
        if (userData.containsKey('tiktok') && userData['tiktok'] is Map) {
          final accounts = userData['tiktok'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              addAccount({
                'id': accountId,
                'platform': 'tiktok',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract Instagram accounts (priority after TikTok)
        if (userData.containsKey('instagram') && userData['instagram'] is Map) {
          final accounts = userData['instagram'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              addAccount({
                'id': accountId,
                'platform': 'instagram',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract YouTube accounts (priority after TikTok and Instagram)
        if (userData.containsKey('youtube') && userData['youtube'] is Map) {
          final accounts = userData['youtube'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              addAccount({
                'id': accountId,
                'platform': 'youtube',
                'display_name': accountData['channel_name'] ?? '',
                'username': accountData['channel_name'] ?? '',
                'profile_image_url': accountData['thumbnail_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['subscriber_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract Facebook accounts
        if (userData.containsKey('facebook') && userData['facebook'] is Map) {
          final accounts = userData['facebook'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            String uniqueId = 'facebook_$accountId';
            if (accountData is Map && 
                accountData['status'] == 'active' && 
                !loadedAccountIds.contains(uniqueId) &&
                accountData['profile_image_url'] != null &&
                accountData['profile_image_url'].toString().isNotEmpty) {
              
              loadedAccountIds.add(uniqueId);
              addAccount({
                'id': accountId,
                'platform': 'facebook',
                'display_name': accountData['name'] ?? accountData['display_name'] ?? '',
                'username': accountData['username'] ?? accountData['name'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract Twitter accounts
        if (userData.containsKey('twitter') && userData['twitter'] is Map) {
          final accounts = userData['twitter'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              addAccount({
                'id': accountId,
                'platform': 'twitter',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
        
        
        // Extract Threads accounts
        if (userData.containsKey('threads') && userData['threads'] is Map) {
          final accounts = userData['threads'] as Map<dynamic, dynamic>;
          print('Found Threads accounts for user ${_currentUser!.uid}');
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              addAccount({
                'id': accountId,
                'platform': 'threads',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
          print('Loaded ${accounts.length} Threads accounts');
        }
        
      }
      
      // STEP 2: Check the nested 'users/users/uid' structure from the database
      final nestedUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .get();
          
      if (nestedUserSnapshot.exists && nestedUserSnapshot.value is Map) {
        final userData = nestedUserSnapshot.value as Map<dynamic, dynamic>;
        
        // REMOVED: User profile from users/users/{uid}/profile is no longer displayed
        // to avoid showing profile as a social account
        
        // Check for social_accounts node
        if (userData.containsKey('social_accounts') && userData['social_accounts'] is Map) {
          final socialAccounts = userData['social_accounts'] as Map<dynamic, dynamic>;
          
          // Process platform-specific accounts
          ['tiktok', 'instagram', 'youtube', 'twitter', 'facebook', 'threads'].forEach((platform) {
            if (socialAccounts.containsKey(platform) && socialAccounts[platform] is Map) {
              final accounts = socialAccounts[platform] as Map<dynamic, dynamic>;
              accounts.forEach((accountId, accountData) {
                if (accountData is Map && accountData['status'] != 'inactive') {
                  // Check if this account is already in the list
                  bool alreadyExists = accountsList.any((existing) => 
                    existing['platform'] == platform && 
                    (existing['id'] == accountId || existing['username'] == accountData['username']));
                  
                  if (!alreadyExists) {
                    addAccount({
                      'id': accountId,
                      'platform': platform,
                      'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                      'username': accountData['username'] ?? '',
                      'profile_image_url': accountData['profile_image_url'] ?? '',
                      'status': accountData['status'] ?? 'active',
                      'followers_count': accountData['followers_count'] ?? 0,
                    });
                  }
                }
              });
            }
          });
        }
        
        // Also check platform-specific nodes
        ['tiktok', 'instagram', 'youtube', 'facebook', 'twitter', 'threads'].forEach((platform) {
          if (userData.containsKey(platform) && userData[platform] is Map) {
            final accounts = userData[platform] as Map<dynamic, dynamic>;
            accounts.forEach((accountId, accountData) {
              if (accountData is Map && accountData['status'] != 'inactive') {
                // Check if this account is already in the list
                bool alreadyExists = accountsList.any((existing) => 
                  existing['platform'] == platform && 
                  (existing['id'] == accountId || existing['username'] == (accountData['username'] ?? '')));
                
                if (!alreadyExists) {
                  Map<String, dynamic> newAccount = {
                    'id': accountId,
                    'platform': platform,
                    'status': accountData['status'] ?? 'active',
                  };
                  
                  // Platform-specific fields
                  if (platform == 'youtube') {
                    newAccount['display_name'] = accountData['channel_name'] ?? '';
                    newAccount['username'] = accountData['channel_name'] ?? '';
                    newAccount['profile_image_url'] = accountData['thumbnail_url'] ?? '';
                    newAccount['followers_count'] = accountData['subscriber_count'] ?? 0;
                  } else {
                    newAccount['display_name'] = accountData['display_name'] ?? accountData['username'] ?? '';
                    newAccount['username'] = accountData['username'] ?? '';
                    newAccount['profile_image_url'] = accountData['profile_image_url'] ?? '';
                    newAccount['followers_count'] = accountData['followers_count'] ?? 0;
                  }
                  
                  addAccount(newAccount);
                }
              }
            });
          }
        });
        
        // Extract TikTok accounts (users/users/{uid}/tiktok)
        if (userData.containsKey('tiktok') && userData['tiktok'] is Map) {
          final accounts = userData['tiktok'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              // Check if this account is already in the list
              bool alreadyExists = accountsList.any((existing) =>
                existing['platform'] == 'tiktok' &&
                (existing['id'] == accountId || existing['username'] == (accountData['username'] ?? '')));
              if (!alreadyExists) {
                addAccount({
                  'id': accountId,
                  'platform': 'tiktok',
                  'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                  'username': accountData['username'] ?? '',
                  'profile_image_url': accountData['profile_image_url'] ?? '',
                  'status': accountData['status'] ?? 'active',
                  'followers_count': accountData['followers_count'] ?? 0,
                });
              }
            }
          });
        }
      }
      
      // STEP 3: Check social_accounts_index from databasefirebase.json
      final indexSnapshot = await _database
          .child('social_accounts_index')
          .get();
      
      if (!mounted) return;
      
      if (indexSnapshot.exists && indexSnapshot.value is Map) {
        final indexData = indexSnapshot.value as Map<dynamic, dynamic>;
        
        // Process Twitter accounts from the index structure
        if (indexData.containsKey('twitter') && indexData['twitter'] is Map) {
          final twitterIndex = indexData['twitter'] as Map<dynamic, dynamic>;
          print('Checking Twitter accounts from social_accounts_index');
          
          for (var entry in twitterIndex.entries) {
            String username = entry.key;
            dynamic userId = entry.value;
            
            if (userId == _currentUser!.uid && !processedTwitterUsernames.contains(username)) {
              processedTwitterUsernames.add(username);
              print('Found Twitter account in index: $username');
              
              // Check if this account is already in the list
              bool alreadyExists = accountsList.any((account) => 
                account['platform'] == 'twitter' && account['username'] == username);
              
              if (!alreadyExists) {
                // Fetch account details first and only after validation add to our list
                try {
                  final twitterSnapshot = await _database
                      .child('users')
                      .child(_currentUser!.uid)
                      .child('social_accounts')
                      .child('twitter')
                      .get();
                  
                  if (!mounted) return;
                  
                  if (twitterSnapshot.exists && twitterSnapshot.value is Map) {
                    final twitterAccounts = twitterSnapshot.value as Map<dynamic, dynamic>;
                    
                    for (var twitterEntry in twitterAccounts.entries) {
                      String id = twitterEntry.key;
                      dynamic data = twitterEntry.value;
                      String uniqueId = 'twitter_$id';
                      
                      if (data is Map && 
                          data['username'] == username && 
                          data['profile_image_url'] != null && 
                          data['profile_image_url'].toString().isNotEmpty &&
                          !loadedAccountIds.contains(uniqueId)) {
                        
                        loadedAccountIds.add(uniqueId);
                        
                        addAccount({
                          'id': id,
                          'platform': 'twitter',
                          'display_name': data['display_name'] ?? username,
                          'username': username,
                          'profile_image_url': data['profile_image_url'],
                          'status': data['status'] ?? 'active',
                          'followers_count': data['followers_count'] ?? 0,
                        });
                        
                        break; // Found valid account data, no need to continue
                      }
                    }
                  }
                } catch (e) {
                  print('Error loading Twitter account $username: $e');
                }
              }
            }
          }
        }
        
        // Process Threads accounts in a similar way if needed
        if (indexData.containsKey('threads') && indexData['threads'] is Map) {
          // Similar implementation as Twitter could be added here...
        }
      }

      // Final filter to remove any accounts without required fields
      accountsList = accountsList.where((account) => 
        account['profile_image_url'] != null &&
        account['profile_image_url'].toString().isNotEmpty &&
        account['display_name'] != null &&
        account['display_name'].toString().isNotEmpty
      ).toList();

      // Load recent videos data to prioritize accounts with recent activity
      await _loadRecentVideosData(accountsList);
      
      // Custom sorting to prioritize accounts with recent video activity
      accountsList.sort((a, b) {
        // First priority: accounts with recent video activity (last 7 days)
        bool aHasRecentActivity = a['has_recent_video'] == true;
        bool bHasRecentActivity = b['has_recent_video'] == true;
        
        if (aHasRecentActivity && !bHasRecentActivity) return -1;
        if (!aHasRecentActivity && bHasRecentActivity) return 1;
        
        // If both have or don't have recent activity, sort by platform priority
        String platformA = (a['platform'] as String).toLowerCase();
        String platformB = (b['platform'] as String).toLowerCase();
        
        // Define priority order: TikTok, Instagram, YouTube, Facebook, Threads, Twitter
        Map<String, int> priorityOrder = {
          'tiktok': 1,
          'instagram': 2,
          'youtube': 3,
          'facebook': 4,
          'threads': 5,
          'twitter': 6,
        };
        
        int priorityA = priorityOrder[platformA] ?? 999;
        int priorityB = priorityOrder[platformB] ?? 999;
        
        return priorityA.compareTo(priorityB);
      });

      if (mounted) {
        setState(() {
          _socialAccounts = accountsList;
        });
      }
      
      // Print debug info about accounts found
      print('Loaded ${accountsList.length} social accounts');
      for (var account in accountsList) {
        print('Account: ${account['platform']} - ${account['username']} (${account['display_name']})');
      }
      
    } catch (e) {
      print('Error loading social accounts: $e');
      if (mounted) {
        setState(() {
          _socialAccounts = [];
        });
      }
    }
  }

  // Method to load recent videos data and mark accounts with recent activity
  Future<void> _loadRecentVideosData(List<Map<String, dynamic>> accountsList) async {
    if (_currentUser == null || !mounted) return;
    
    try {
      // Get videos from the last 7 days
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('videos')
          .get();
          
      if (!mounted || !videosSnapshot.exists) return;
      
      final videosData = videosSnapshot.value as Map<dynamic, dynamic>;
      
      // Track which accounts have recent video activity
      Set<String> accountsWithRecentActivity = {};
      
      videosData.forEach((videoId, videoData) {
        if (videoData is Map) {
          final timestamp = videoData['timestamp'] as int? ?? 0;
          final status = videoData['status'] as String? ?? '';
          final accounts = videoData['accounts'] as Map<dynamic, dynamic>?;
          
          // Check if video is recent and published
          if (timestamp >= sevenDaysAgo && (status == 'published' || status == 'scheduled')) {
            if (accounts != null) {
              // Check which platforms this video was published to
              accounts.forEach((platform, platformAccounts) {
                if (platformAccounts is Map) {
                  platformAccounts.forEach((accountId, accountData) {
                    if (accountData is Map) {
                      final accountUsername = accountData['username'] as String? ?? '';
                      if (accountUsername.isNotEmpty) {
                        // Create unique identifier for this account
                        String accountKey = '${platform}_$accountUsername';
                        accountsWithRecentActivity.add(accountKey);
                      }
                    }
                  });
                }
              });
            }
          }
        }
      });
      
      // Mark accounts with recent activity
      for (var account in accountsList) {
        final platform = account['platform'] as String;
        final username = account['username'] as String;
        final accountKey = '${platform}_$username';
        
        account['has_recent_video'] = accountsWithRecentActivity.contains(accountKey);
        
        // Add timestamp info for debugging
        if (account['has_recent_video'] == true) {
          print('Account ${account['username']} (${account['platform']}) has recent video activity');
        }
      }
      
    } catch (e) {
      print('Error loading recent videos data: $e');
      // If there's an error, mark all accounts as no recent activity
      for (var account in accountsList) {
        account['has_recent_video'] = false;
      }
    }
  }

  Future<void> _loadTopTrends() async {
    if (!mounted) return;
    try {
      final DatabaseReference database = FirebaseDatabase.instance.ref();
      final List<String> platformNodes = [
        'TIKTOKTREND',
        'INSTAGRAMTREND',
        'FACEBOOKTREND',
        'TWITTERTREND',
        'THREADSTREND',
        'YOUTUBETREND',
      ];
      
      List<Map<String, dynamic>> allTrends = [];
      
      for (final node in platformNodes) {
        final DataSnapshot snapshot = await database.child(node).get();
        if (snapshot.exists && snapshot.value != null) {
          final dynamic data = snapshot.value;
          if (data is List) {
            allTrends.addAll((data as List).map((item) {
              if (item == null) return null;
              if (item is Map) {
                final trendData = item.map((key, value) => MapEntry(key.toString(), value));
                return {
                  'trend_name': trendData['trend_name'] ?? '',
                  'description': trendData['description'] ?? '',
                  'platform': node.replaceAll('TREND', '').toLowerCase(),
                  'category': trendData['category'] ?? '',
                  'trend_level': trendData['trend_level'] ?? '⏸',
                  'hashtags': trendData['hashtags'] ?? [],
                  'growth_rate': trendData['growth_rate'] ?? '',
                  'virality_score': _parseNumericValue(trendData['virality_score']),
                  'data_points': _parseDataPoints(trendData['data_points']),
                };
              }
              return null;
            }).whereType<Map<String, dynamic>>());
          } else if (data is Map) {
            final dataMap = data.map((key, value) => MapEntry(key.toString(), value));
            allTrends.addAll(dataMap.entries.map((entry) {
              final trendData = entry.value;
              if (trendData == null) return null;
              if (trendData is Map) {
                return {
                  'trend_name': trendData['trend_name'] ?? '',
                  'description': trendData['description'] ?? '',
                  'platform': node.replaceAll('TREND', '').toLowerCase(),
                  'category': trendData['category'] ?? '',
                  'trend_level': trendData['trend_level'] ?? '⏸',
                  'hashtags': trendData['hashtags'] ?? [],
                  'growth_rate': trendData['growth_rate'] ?? '',
                  'virality_score': _parseNumericValue(trendData['virality_score']),
                  'data_points': _parseDataPoints(trendData['data_points']),
                };
              }
              return null;
            }).whereType<Map<String, dynamic>>());
          }
        }
      }
      
      // Ordina i trend per virality_score e growth_rate, poi per trend_level
      allTrends.sort((a, b) {
        // Prima per trend_level (🔺 prima di ⏸)
        if (a['trend_level'] == '🔺' && b['trend_level'] != '🔺') return -1;
        if (a['trend_level'] != '🔺' && b['trend_level'] == '🔺') return 1;
        
        // Poi per virality_score
        final aScore = a['virality_score'] as num? ?? 0.0;
        final bScore = b['virality_score'] as num? ?? 0.0;
        return bScore.compareTo(aScore);
      });
      
      // Prendi solo i top 3 trend
      final topTrends = allTrends.take(3).toList();
      
      if (mounted) {
        setState(() {
          _topTrends = topTrends;
        });
        // Start animations after data is loaded
        _trendChartAnimationController.reset();
        _trendScoreAnimationController.reset();
        _typingAnimationController.reset();
        _trendChartAnimationController.forward();
        _trendScoreAnimationController.forward();
        _typingAnimationController.forward();
        
        // Add listener to track when typing animation completes for current index
        _typingAnimationController.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _completedTypingAnimations.add(_currentTrendIndex);
          }
        });
      }
    } catch (e) {
      print('Error loading top trends: $e');
      if (mounted) {
        setState(() {
          _topTrends = [];
        });
      }
    }
  }

  double _parseNumericValue(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  List<Map<String, dynamic>> _parseDataPoints(dynamic dataPoints) {
    if (dataPoints == null) return [];
    
    if (dataPoints is List) {
      return dataPoints.map((point) {
        if (point == null) return <String, dynamic>{};
        if (point is Map) {
          return point.map((k, v) => MapEntry(k.toString(), v));
        }
        return <String, dynamic>{};
      }).where((point) => point.isNotEmpty).toList();
    }
    
    return [];
  }

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }

  // Method to refresh progress status based on current data
  void _refreshProgressStatus() {
    // Check if social accounts are connected
    bool hasConnectedAccounts = _socialAccounts.isNotEmpty;
    
    // Check if videos have been published
    bool hasPublishedVideo = false;
    for (var video in _videos) {
      if (video['status'] == 'published' || 
         (video['status'] == 'scheduled' && video['published_at'] != null)) {
        hasPublishedVideo = true;
        break;
      }
    }
    
    // Update state only if values have changed
    if (hasConnectedAccounts != _hasConnectedAccounts || 
        hasPublishedVideo != _hasUploadedVideo) {
      setState(() {
        _hasConnectedAccounts = hasConnectedAccounts;
        _hasUploadedVideo = hasPublishedVideo;
      });
    }
    _updateCtaAttentionAnimation(hasConnectedAccounts);
    
    // Check for upgrade popup if user is not premium
    if (!_shouldShowUpgradePopup && !_argumentsProcessed) {
      _checkForUpgradePopup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Check progress status before building the UI
    // This ensures the steps update when navigating back to this page
    _refreshProgressStatus();
    
    // Avvia l'animazione dei crediti solo se non è stata già eseguita
    if (!_hasAnimatedCredits && _userCredits > 0) {
      _startCreditsAnimation();
    }
    
    // Check for upgrade popup when building (only for initial arguments)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isPremium && !_shouldShowUpgradePopup && !_argumentsProcessed) {
        _checkForUpgradePopup();
      }
    });
    
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
            SafeArea(
              child: _isLoading
                  ? Center(
                      child: Lottie.asset(
                        'assets/animations/MainScene.json',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    )
                  : _videos.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildVideosTab(theme),
            ),
            
            // Loading overlay for ad watching
            if (_isWatchingAd)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Lottie.asset(
                        'assets/animations/MainScene.json',
                        width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Loading ad...',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Getting Started Floating Button
            Positioned(
              bottom: 95, // Spostato 15 pixel più in basso (da 110 a 95)
              right: 20,
              child: FadeTransition(
                opacity: _floatingButtonAnimation,
                child: ScaleTransition(
                  scale: _floatingButtonAnimation,
                  child: _buildGettingStartedFloatingButton(theme),
                ),
              ),
            ),
            

          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.08, // 8% dell'altezza dello schermo
          ),
          sliver: SliverToBoxAdapter(
            child: _buildSocialAccountsStories(theme),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0), // Padding aumentato per distanziare le card dai bordi
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Upcoming scheduled posts section
              _buildUpcomingScheduledPosts(theme),
              
              // Challenges section
              _buildChallengesSection(theme),
              
              // CARD AI VIDEOCLIP: DISABILITATA
              // const SizedBox(height: 18),
              // _buildAiVideoclipCard(theme),
              
              // CARD TRENDS: visibile per tutti gli utenti
              _buildTrendsCard(theme),
              
              // CARD AI CONTENT INSIGHTS: analisi IA degli ultimi 5 video
              _buildAiContentInsightsCard(theme),
              
              // CARD COMMUNITY: visibile per tutti gli utenti
              _buildCommunityCard(theme),
              
              // Spacing between credits and getting started sections
              const SizedBox(height: 16),
              
              // Getting started section removed - now shown as dropdown
              
              // Add bottom padding for better scrolling experience
              const SizedBox(height: 60), // Aumentato di 30 pixel
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildVideosTab(ThemeData theme) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.08, // 8% dell'altezza dello schermo
          ),
          sliver: SliverToBoxAdapter(
            child: _buildSocialAccountsStories(theme),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildUpcomingScheduledPosts(theme),
              
              // Challenges section
              _buildChallengesSection(theme),
              
              // CARD AI VIDEOCLIP: DISABILITATA
              // const SizedBox(height: 18),
              // _buildAiVideoclipCard(theme),
              
              // CARD TRENDS: visibile per tutti gli utenti
              _buildTrendsCard(theme),
              
              // CARD AI CONTENT INSIGHTS: analisi IA degli ultimi 5 video
              _buildAiContentInsightsCard(theme),
              
              // CARD COMMUNITY: visibile per tutti gli utenti
              _buildCommunityCard(theme),
              
              const SizedBox(height: 16),
              // Getting started section removed - now shown as dropdown
              const SizedBox(height: 60), // Ridotto significativamente
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsTab(ThemeData theme) {
    // Removed analytics tab
    return Container();
  }

  Widget _buildVideosList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Videos list
        ...List.generate(_videos.length, (index) {
          final video = _videos[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video thumbnail with overlay
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant,
                          image: video['thumbnail_path']?.isNotEmpty == true
                            ? DecorationImage(
                                image: FileImage(File(video['thumbnail_path'])),
                                fit: BoxFit.cover,
                              )
                            : null,
                        ),
                        child: video['thumbnail_path']?.isEmpty == true
                          ? Center(
                              child: Icon(
                                Icons.movie_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                            )
                          : null,
                      ),
                    ),
                    // Play button overlay
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          onTap: () {
                            // TODO: Implement video playback
                          },
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.5),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Duration badge (gestisce caroselli, immagini e video)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Transform.scale(
                        scale: 1.2, // Scala leggermente più grande per questo badge
                        child: _buildHomeDurationBadge(video),
                      ),
                    ),
                    // Status badge (if scheduled or processing)
                    if (video['status'] != 'published')
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: video['status'] == 'scheduled'
                                ? Colors.blue.withOpacity(0.9)
                                : Colors.orange.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            video['status'].toString().toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // Video info
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video['title'],
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (video['description'].isNotEmpty) 
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            video['description'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Stats row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Upload date
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                video['uploadDate'],
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                          // Action buttons
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.share_outlined, size: 20),
                                onPressed: () {
                                  // TODO: Implement share functionality
                                },
                                splashRadius: 24,
                                tooltip: 'Share',
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () {
                                  // TODO: Implement edit functionality
                                },
                                splashRadius: 24,
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_vert, size: 20),
                                onPressed: () {
                                  // TODO: Show more options menu
                                },
                                splashRadius: 24,
                                tooltip: 'More options',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOnboardingList(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    // Define the steps with their data
    final List<Map<String, dynamic>> steps = [
      {
        'number': 1,
        'title': 'Connect Your Social Accounts',
        'description': 'Link your social media accounts to start sharing content',
        'isCompleted': _hasConnectedAccounts,
        'onTap': () {
          Navigator.pushNamed(context, '/accounts').then((_) {
            // Refresh accounts and check progress when returning
            loadSocialAccounts();
            checkUserProgress();
          });
        },
        'key': _connectAccountsKey,
        'icon': Icons.link,
      },
      {
        'number': 2,
        'title': 'Upload Your First Video',
        'description': 'Create and share your first video across your connected platforms',
        'isCompleted': _hasUploadedVideo,
        'onTap': () {
          NavigationService.navigateToUpload(context);
          // Refresh videos and check progress when returning
          _loadVideos();
          checkUserProgress();
        },
        'key': _uploadVideoKey,
        'icon': Icons.video_library,
      },
      {
        'number': 3,
        'title': _hasCompletedProfile ? 'Premium Active' : 'Unlock the full potential',
        'description': _hasCompletedProfile ? 
            'Enjoy unlimited uploads and premium features' : 
            'Upgrade to take your social media experience to the max with Fluzar',
        'isCompleted': _hasCompletedProfile,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Platform.isIOS
                  ? const UpgradePremiumIOSPage(suppressExtraPadding: true, fromGettingStarted: true)
                  : const UpgradePremiumPage(suppressExtraPadding: true, fromGettingStarted: true),
            ),
          ).then((_) {
            // Check progress when returning, ma non ricarichiamo i crediti
            checkUserProgress();
          });
        },
        'key': null,
        'icon': Icons.star,
      },
    ];

    // Calculate current progress
    int completedSteps = steps.where((step) => step['isCompleted'] as bool).length;
    int totalSteps = steps.length;
    int currentStep = completedSteps < totalSteps ? completedSteps + 1 : totalSteps;
    
    // Build the step widgets
    List<Widget> stepWidgets = [];
    
    // Add a top decoration for the first step
    stepWidgets.add(
      Container(
        margin: EdgeInsets.only(left: 22.5),
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          gradient: steps[0]['isCompleted'] as bool 
              ? LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  transform: GradientRotation(135 * 3.14159 / 180),
                )
              : null,
          color: steps[0]['isCompleted'] as bool ? null : Colors.grey.shade300,
        ),
      ),
    );
    
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final isActive = (i + 1) <= currentStep;
      final isCompleted = step['isCompleted'] as bool;
      
      // Add the step item
      stepWidgets.add(
        _buildStepItem(
          theme,
          number: step['number'] as int,
          title: step['title'] as String,
          description: step['description'] as String,
          isActive: isActive,
          isCompleted: isCompleted,
          icon: step['icon'] as IconData,
          onTap: step['onTap'] as VoidCallback,
          key: step['key'] as Key?,
        ),
      );
      
      // Add connecting line (don't show after last item)
      if (i < steps.length - 1) {
        stepWidgets.add(
          Container(
            margin: EdgeInsets.only(left: 22.5),
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isCompleted 
                      ? Color(0xFF667eea)
                      : Colors.grey.shade300,
                  i + 1 < currentStep 
                      ? Color(0xFF764ba2)
                      : Colors.grey.shade300,
                ],
                transform: GradientRotation(135 * 3.14159 / 180),
              ),
            ),
          ),
        );
      } else {
        // For the last item, add a bottom decoration to complete the visual
        stepWidgets.add(
          Container(
            margin: EdgeInsets.only(left: 22.5),
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              gradient: isCompleted 
                  ? LinearGradient(
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    )
                  : null,
              color: isCompleted ? null : Colors.grey.shade300,
            ),
          ),
        );
      }
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 10),
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
        children: [
          // Header cliccabile per espandere/chiudere
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isGettingStartedExpanded = !_isGettingStartedExpanded;
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      child: Text(
                        'Getting Started',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF667eea).withOpacity(0.1),
                                Color(0xFF764ba2).withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
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
                              '$completedSteps/$totalSteps Steps',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        AnimatedRotation(
                          turns: _isGettingStartedExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
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
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 24,
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
          // Contenuto espandibile
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _isGettingStartedExpanded 
                ? CrossFadeState.showSecond 
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Add all the step widgets
                  ...stepWidgets,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Floating button for Getting Started
  Widget _buildGettingStartedFloatingButton(ThemeData theme) {
    final int completedSteps = _getCompletedStepsCount();
    final int totalSteps = _getTotalStepsCount();
    final int remainingSteps = totalSteps - completedSteps;
    final bool shouldShake = !_hasConnectedAccounts;
    
    return AnimatedBuilder(
      animation: _ctaAttentionController,
      builder: (context, child) {
        final double dx = shouldShake ? _ctaShakeAnimation.value : 0.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: Container(
        width: 56, // Aumentato da 48 a 56 per dare più spazio al badge
        height: 56, // Aumentato da 48 a 56 per dare più spazio al badge
        child: Stack(
          children: [
            Positioned(
              left: 4, // Centrato nel nuovo container più grande
              top: 4,  // Centrato nel nuovo container più grande
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      _showGettingStartedBottomSheet();
                    },
                    child: Center(
                      child: Icon(
                        Icons.lightbulb_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Badge con numero di step mancanti
            if (remainingSteps > 0)
              Positioned(
                top: 2, // Aggiustato per il nuovo container più grande
                right: 2, // Aggiustato per il nuovo container più grande
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      remainingSteps.toString(),
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
      ),
    );
  }

  // Show Getting Started bottom sheet
  void _showGettingStartedBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          height: MediaQuery.of(context).size.height * 0.75, // Ridotto dal 85% al 75% (10% in meno)
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? Colors.grey[900]! : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const LinearGradient(
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
                        'Getting Started',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF667eea).withOpacity(0.1),
                            const Color(0xFF764ba2).withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: const GradientRotation(135 * 3.14159 / 180),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
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
                          '${_getCompletedStepsCount()}/${_getTotalStepsCount()} Steps',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildOnboardingStepsContent(theme),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper method to get completed steps count
  int _getCompletedStepsCount() {
    int count = 0;
    if (_hasConnectedAccounts) count++;
    if (_hasUploadedVideo) count++;
    if (_hasCompletedProfile) count++;
    return count;
  }

  // Helper method to get total steps count
  int _getTotalStepsCount() {
    return 3;
  }

  // Content for the onboarding steps (extracted from the original method)
  Widget _buildOnboardingStepsContent(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    // Define the steps with their data
    final List<Map<String, dynamic>> steps = [
      {
        'number': 1,
        'title': 'Connect Your Social Accounts',
        'description': 'Link your social media accounts to start sharing content',
        'isCompleted': _hasConnectedAccounts,
        'onTap': () {
          Navigator.pushNamed(context, '/accounts').then((_) {
            loadSocialAccounts();
            checkUserProgress();
          });
        },
        'key': _connectAccountsKey,
        'icon': Icons.link,
      },
      {
        'number': 2,
        'title': 'Upload Your First Video',
        'description': 'Create and share your first video across your connected platforms',
        'isCompleted': _hasUploadedVideo,
        'onTap': () {
          NavigationService.navigateToUpload(context);
          _loadVideos();
          checkUserProgress();
        },
        'key': _uploadVideoKey,
        'icon': Icons.video_library,
      },
      {
        'number': 3,
        'title': _hasCompletedProfile ? 'Premium Active' : 'Unlock the full potential',
        'description': _hasCompletedProfile ? 
            'Enjoy unlimited uploads and premium features' : 
            'Upgrade to take your social media experience to the max with Fluzar',
        'isCompleted': _hasCompletedProfile,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Platform.isIOS
                  ? const UpgradePremiumIOSPage(suppressExtraPadding: true, fromGettingStarted: true)
                  : const UpgradePremiumPage(suppressExtraPadding: true, fromGettingStarted: true),
            ),
          ).then((_) {
            checkUserProgress();
          });
        },
        'key': null,
        'icon': Icons.star,
      },
    ];

    // Calculate current progress
    int completedSteps = steps.where((step) => step['isCompleted'] as bool).length;
    int totalSteps = steps.length;
    int currentStep = completedSteps < totalSteps ? completedSteps + 1 : totalSteps;
    
    // Build the step widgets
    List<Widget> stepWidgets = [];
    
    // Add a top decoration for the first step
    stepWidgets.add(
      Container(
        margin: const EdgeInsets.only(left: 22.5),
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          gradient: steps[0]['isCompleted'] as bool 
              ? const LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  transform: GradientRotation(135 * 3.14159 / 180),
                )
              : null,
          color: steps[0]['isCompleted'] as bool ? null : Colors.grey.shade300,
        ),
      ),
    );
    
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final isActive = (i + 1) <= currentStep;
      final isCompleted = step['isCompleted'] as bool;
      
      // Add the step item
      stepWidgets.add(
        _buildStepItem(
          theme,
          number: step['number'] as int,
          title: step['title'] as String,
          description: step['description'] as String,
          isActive: isActive,
          isCompleted: isCompleted,
          icon: step['icon'] as IconData,
          onTap: step['onTap'] as VoidCallback,
          key: step['key'] as Key?,
        ),
      );
      
      // Add connecting line (don't show after last item)
      if (i < steps.length - 1) {
        stepWidgets.add(
          Container(
            margin: const EdgeInsets.only(left: 22.5),
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isCompleted 
                      ? const Color(0xFF667eea)
                      : Colors.grey.shade300,
                  i + 1 < currentStep 
                      ? const Color(0xFF764ba2)
                      : Colors.grey.shade300,
                ],
                transform: const GradientRotation(135 * 3.14159 / 180),
              ),
            ),
          ),
        );
      } else {
        // For the last item, add a bottom decoration to complete the visual
        stepWidgets.add(
          Container(
            margin: const EdgeInsets.only(left: 22.5),
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              gradient: isCompleted 
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    )
                  : null,
              color: isCompleted ? null : Colors.grey.shade300,
            ),
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: stepWidgets,
    );
  }

  Widget _buildStepItem(
    ThemeData theme, {
    required int number,
    required String title,
    required String description,
    required bool isActive,
    required bool isCompleted,
    required IconData icon,
    required VoidCallback onTap,
    Key? key,
  }) {
    final Color accentColor = isCompleted 
        ? Color(0xFF667eea)
        : isActive 
            ? Color(0xFF667eea)
            : Colors.grey.shade400;
            
    final Color backgroundColor = isCompleted 
        ? Color(0xFF667eea).withOpacity(0.1)
        : isActive 
            ? Color(0xFF667eea).withOpacity(0.05)
            : theme.colorScheme.surfaceVariant;
            
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: (!isActive && !isCompleted)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    key: key,
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                    margin: EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white.withOpacity(0.28)
                            : Colors.white.withOpacity(0.55),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.brightness == Brightness.dark
                              ? Colors.black.withOpacity(0.08)
                              : Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Step number/check circle
                        Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.0),
                            border: Border.all(
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.45)
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              number.toString(),
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade500,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.0),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.brightness == Brightness.dark
                                            ? Colors.white.withOpacity(0.4)
                                            : Colors.grey.shade400,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      icon,
                                      color: Colors.grey.shade500,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
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
              )
            : Container(
                key: key,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                margin: EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? theme.cardColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: (isActive || isCompleted)
                      ? Border.all(
                          color: Color(0xFF667eea).withOpacity(0.6), 
                          width: 2
                        )
                      : null,
                  boxShadow: (isActive || isCompleted)
                      ? [
                          BoxShadow(
                            color: Color(0xFF667eea).withOpacity(0.15),
                            blurRadius: 12,
                            spreadRadius: 1,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step number/check circle
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: (isActive || isCompleted)
                      ? LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        )
                      : null,
                  color: (isActive || isCompleted) ? null : backgroundColor,
                  border: Border.all(
                    color: accentColor,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 3,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: isCompleted
                      ? Icon(
                          Icons.check,
                          color: (isActive || isCompleted) ? Colors.white : accentColor,
                          size: 22,
                        )
                      : Text(
                          number.toString(),
                          style: TextStyle(
                            color: (isActive || isCompleted) ? Colors.white : accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isActive ? theme.textTheme.bodyLarge?.color : Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        // Step icon
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: (isActive || isCompleted)
                                ? LinearGradient(
                                    colors: [
                                      Color(0xFF667eea),
                                      Color(0xFF764ba2),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    transform: GradientRotation(135 * 3.14159 / 180),
                                  )
                                : null,
                            color: (isActive || isCompleted) ? null : backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            color: (isActive || isCompleted) ? Colors.white : accentColor,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: isActive ? Colors.grey.shade600 : Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                    if (isActive && !isCompleted) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: isActive 
                              ? LinearGradient(
                                  colors: [
                                    Color(0xFF667eea).withOpacity(0.1),
                                    Color(0xFF764ba2).withOpacity(0.1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  transform: GradientRotation(135 * 3.14159 / 180),
                                )
                              : null,
                          color: isActive ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                            'Start this step',
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (isCompleted) ...[
                      const SizedBox(height: 8),
                      Row(
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
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                          SizedBox(width: 6),
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
                              'Completed',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    // Removed analytics stats grid
    return Container();
  }

  Widget _buildStatCard(
    ThemeData theme,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    // Removed analytics stat card
    return Container();
  }


  
  // Method to handle watching ads for credits - versione aggiornata con log dettagliati
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
    print('[AdMob] Inizio caricamento RewardedAd...');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.white,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Lottie.asset(
                'assets/animations/MainScene.json',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
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
    try {
      // Imposta test device ID (sostituisci con il tuo vero ID se necessario)
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
        testDeviceIds: ['5030a8db-97d8-41fc-8ae2-10ca1ad1abe1'],
      ));
      await RewardedAd.load(
        adUnitId: _rewardedAdUnitId,
        request: AdRequest(),
                rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) async {
            print('[AdMob] ===== CALLBACK onAdLoaded TRIGGERED =====');
            print('[AdMob] Ad caricato con successo, provo a mostrarlo...');
            
            // Aggiungi tutti i callback per tracciare il ciclo di vita dell'ad
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdShowedFullScreenContent: (ad) {
                print('[AdMob] ===== CALLBACK onAdShowedFullScreenContent =====');
                print('[AdMob] Ad mostrato a schermo intero');
              },
              onAdDismissedFullScreenContent: (ad) {
                print('[AdMob] ===== CALLBACK onAdDismissedFullScreenContent =====');
                print('[AdMob] Ad chiuso dall\'utente');
                ad.dispose();
                if (mounted) setState(() => _isAdLoadingOrShowing = false);
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                print('[AdMob] ===== CALLBACK onAdFailedToShowFullScreenContent =====');
                print('[AdMob] Errore nel mostrare l\'ad: ${error.message}');
                ad.dispose();
                if (mounted) setState(() => _isAdLoadingOrShowing = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Errore durante la visualizzazione dell\'annuncio'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
            );
            
            try {
              print('[AdMob] Chiamata ad.show()...');
              await ad.show(
                onUserEarnedReward: (ad, reward) {
                  print('[AdMob] ===== CALLBACK onUserEarnedReward TRIGGERED =====');
                  print('[AdMob] Reward amount: \\${reward.amount}');
                  print('[AdMob] Reward type: ${reward.type}');
                  print('[AdMob] Chiamata _addCreditsForRewardedAd()...');
                  _addCreditsForRewardedAd();
                  print('[AdMob] ===== CALLBACK onUserEarnedReward COMPLETED =====');
                },
              );
              print('[AdMob] ad.show() completata');
            } catch (e) {
              print('[AdMob] ===== ERRORE durante ad.show() =====');
              print('[AdMob] Errore: ${e.toString()}');
              print('[AdMob] Stack trace: ${StackTrace.current}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Errore durante la visualizzazione dell\'annuncio'),
                  backgroundColor: Colors.red,
                ),
              );
              ad.dispose();
              if (mounted) setState(() => _isAdLoadingOrShowing = false);
            }
          },
          onAdFailedToLoad: (LoadAdError error) {
            print('[AdMob] ===== CALLBACK onAdFailedToLoad =====');
            print('[AdMob] Errore caricamento ad: ${error.message}');
            print('[AdMob] Error code: ${error.code}');
            print('[AdMob] Error domain: ${error.domain}');
            if (mounted) setState(() => _isAdLoadingOrShowing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Impossibile caricare l\'annuncio. Riprova più tardi.'),
                backgroundColor: Colors.red,
              ),
            );
          },
        ),
      );
    } catch (e) {
      print('[AdMob] Errore generale: \\${e.toString()}');
      if (mounted) setState(() => _isAdLoadingOrShowing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Si è verificato un errore. Riprova più tardi.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSocialAccountsStories(ThemeData theme, {bool showTabs = false}) {
    return Container(
      color: theme.brightness == Brightness.dark 
          ? Color(0xFF121212) 
          : Colors.white,
      child: SizedBox(
        height: 140, // Ridotto leggermente l'altezza complessiva
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0), // Ridotto il padding verticale
          scrollDirection: Axis.horizontal,
          itemCount: _socialAccounts.length + 1, // +1 for the "Add" story
          itemBuilder: (context, index) {
            // "Add new account" item
            if (index == 0) {
              return _buildStoryCircle(
                theme,
                isAddButton: true,
                onTap: () {
                  Navigator.pushNamed(context, '/accounts').then((_) {
                    // Refresh accounts and check progress when returning
                    loadSocialAccounts();
                    checkUserProgress();
                  });
                },
              );
            }
            
            // Account items
            final account = _socialAccounts[index - 1];
            return _buildStoryCircle(
              theme,
              imageUrl: account['profile_image_url'],
              platform: account['platform'],
              displayName: account['display_name'] ?? account['username'] ?? 'Account',
              accountData: account,
              onTap: () {
                // Navigate to account details page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SocialAccountDetailsPage(
                      account: {
                        'id': account['id'],
                        'username': account['username'],
                        'displayName': account['display_name'],
                        'profileImageUrl': account['profile_image_url'],
                        'followersCount': account['followers_count'],
                        'status': account['status'],
                      },
                      platform: account['platform'],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoryCircle(
    ThemeData theme, {
    String? imageUrl,
    String? platform,
    String? displayName,
    Map<String, dynamic>? accountData,
    bool isAddButton = false,
    required VoidCallback onTap,
  }) {
    // Platform-specific gradient colors
    Map<String, List<Color>> platformColors = {
      'twitter': [const Color(0xFF1DA1F2), const Color(0xFF0D8ECF)],
      'instagram': [const Color(0xFFC13584), const Color(0xFFF56040), const Color(0xFFFFDC80)],
      'facebook': [const Color(0xFF3B5998), const Color(0xFF2C4270)],
      'youtube': [const Color(0xFFFF0000), const Color(0xFFCC0000)],
      'threads': [const Color(0xFF000000), const Color(0xFF333333)],
      'tiktok': [const Color(0xFF000000), const Color(0xFF333333)],
    };

    // Platform icon
    IconData getPlatformIcon(String? platform) {
      switch (platform?.toLowerCase()) {
        case 'twitter':
          return Icons.short_text;
        case 'instagram':
          return Icons.camera_alt;
        case 'facebook':
          return Icons.facebook;
        case 'youtube':
          return Icons.play_arrow;
        case 'threads':
          return Icons.label;
        case 'tiktok':
          return Icons.music_note;
        default:
          return Icons.account_circle;
      }
    }

    // Widget per il logo del social media
    Widget _getSocialMediaLogo(String? platform) {
      if (platform == null || isAddButton) return const SizedBox.shrink();
      
      switch (platform.toLowerCase()) {
        case 'twitter':
          return Image.asset(
            'assets/loghi/logo_twitter.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF1DA1F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.short_text,
                  color: Colors.white,
                  size: 12,
                ),
              );
            },
          );
        case 'instagram':
          return Image.asset(
            'assets/loghi/logo_insta.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1306C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 12,
                ),
              );
            },
          );
        case 'facebook':
          return Image.asset(
            'assets/loghi/logo_facebook.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF1877F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.facebook,
                  color: Colors.white,
                  size: 12,
                ),
              );
            },
          );
        case 'youtube':
          return Image.asset(
            'assets/loghi/logo_yt.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 12,
                ),
              );
            },
          );
        case 'threads':
          return Image.asset(
            'assets/loghi/threads_logo.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_outlined,
                  color: Colors.white,
                  size: 12,
                ),
              );
            },
          );
        case 'tiktok':
          return Image.asset(
            'assets/loghi/logo_tiktok.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.music_note,
                  color: Colors.white,
                  size: 12,
                ),
              );
            },
          );
        default:
          return const SizedBox.shrink();
      }
    }

    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 85,
                  height: 85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isAddButton
                        ? LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.2),
                              Colors.white.withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: platformColors[platform?.toLowerCase()] ?? 
                                [theme.primaryColor, theme.primaryColorLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: isAddButton ? null : null,
                    border: isAddButton
                        ? Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: isAddButton
                            ? Colors.black.withOpacity(0.2)
                            : Colors.black.withOpacity(0.05),
                        blurRadius: isAddButton ? 15 : 3,
                        spreadRadius: isAddButton ? 1 : 0,
                        offset: const Offset(0, 4),
                      ),
                      if (isAddButton)
                        BoxShadow(
                          color: Colors.white.withOpacity(0.3),
                          blurRadius: 2,
                          spreadRadius: -2,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3.5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.cardColor,
                      image: !isAddButton && imageUrl != null && imageUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(imageUrl),
                              fit: BoxFit.cover,
                              onError: (exception, stackTrace) {
                                print('Error loading image: $exception');
                                print('Image URL: $imageUrl');
                              },
                            )
                          : null,
                    ),
                    child: isAddButton
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
                              Icons.add,
                              color: Colors.white,
                              size: 40,
                            ),
                          )
                        : (imageUrl == null || imageUrl.isEmpty)
                            ? Icon(
                                getPlatformIcon(platform),
                                color: platformColors[platform?.toLowerCase()]?[0] ?? theme.primaryColor,
                                size: 38,
                              )
                            : null,
                  ),
                ),
                // Logo del social media posizionato in basso a destra
                if (!isAddButton && platform != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: theme.cardColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2),
                      child: _getSocialMediaLogo(platform),
                    ),
                  ),
                // Badge per attività recente (in alto a destra)
                if (!isAddButton && accountData != null && accountData!['has_recent_video'] == true)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.videocam,
                        color: Colors.white,
                        size: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Flexible(
            child: Text(
              isAddButton ? 'Add' : (displayName ?? ''),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyMedium?.color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Method to navigate to ScheduledPostsPage
  void _navigateToScheduledPostsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ScheduledPostsPage(),
      ),
    ).then((_) {
      // Refresh scheduled posts when returning
      _loadUpcomingScheduledPosts();
      // Non ricarichiamo i crediti quando torniamo da questa pagina
    });
  }

  // Build the upcoming scheduled posts section
  Widget _buildUpcomingScheduledPosts(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (_upcomingScheduledPosts.isEmpty) {
      return SizedBox(); // Don't show anything if there are no upcoming posts
    }
    
    // Build the post items
    List<Widget> postWidgets = [];
    
    for (int i = 0; i < _upcomingScheduledPosts.length; i++) {
      final post = _upcomingScheduledPosts[i];
      
      // Add the post item
      postWidgets.add(
        _buildUpcomingPostItem(theme, post),
      );
      
      // Add divider between items (except after the last one)
      if (i < _upcomingScheduledPosts.length - 1) {
        postWidgets.add(
          Divider(
            height: 16,
            thickness: 1,
            color: Colors.grey.shade200,
          ),
        );
      }
    }
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Upcoming',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 14,
                      color: theme.primaryColor,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Next 15 min',
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          // Add all post items
          ...postWidgets,
          // Add See All link at the bottom
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _navigateToScheduledPostsPage,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: theme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUpcomingPostItem(ThemeData theme, Map<String, dynamic> post) {
    final scheduledTime = post['scheduledTime'] as int;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    
    // Format time remaining
    String timeRemaining;
    if (difference.inMinutes <= 0) {
      timeRemaining = 'Publishing now';
    } else if (difference.inMinutes == 1) {
      timeRemaining = '1 minute left';
    } else {
      timeRemaining = '${difference.inMinutes} minutes left';
    }
    
    // Format scheduled time
    final formattedTime = DateFormat('HH:mm').format(dateTime);
    
    // Get platform badges
    List<Widget> platformBadges = (post['platforms'] as List<String>).map((platform) {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _getPlatformColor(platform).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getPlatformIcon(platform),
              size: 14,
              color: _getPlatformColor(platform),
            ),
            SizedBox(width: 4),
            Text(
              platform,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getPlatformColor(platform),
              ),
            ),
          ],
        ),
      );
    }).toList();
    
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScheduledPostDetailsPage(post: post),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Video thumbnail or placeholder with countdown overlay
              Stack(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      image: post['thumbnail_path'] != null && post['thumbnail_path'].isNotEmpty
                          ? DecorationImage(
                              image: FileImage(File(post['thumbnail_path'])),
                              fit: BoxFit.cover,
                              onError: (error, stackTrace) {},
                            )
                          : null,
                    ),
                    child: post['thumbnail_path'] == null || post['thumbnail_path'].isEmpty
                        ? Center(
                            child: Icon(
                              Icons.video_library,
                              size: 28,
                              color: theme.primaryColor.withOpacity(0.6),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              SizedBox(width: 16),
              
              // Post details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Post title or description
                    Text(
                      post['title']?.isNotEmpty == true
                          ? post['title']
                          : (post['description']?.isNotEmpty == true
                              ? post['description']
                              : 'Scheduled post'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    
                    // Publication time
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Today at $formattedTime',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        Spacer(),
                        // Platform icons in a row
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: (post['platforms'] as List<String>).map((platform) {
                            return Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.all(3),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: _getPlatformColor(platform).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: _getPlatformWidget(platform, 10),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    
                    // Countdown indicator
                    Container(
                      margin: EdgeInsets.only(top: 6),
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            timeRemaining,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Action icon
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Helper icon method
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

  // Get a color for each platform
  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'TikTok':
        return Colors.black;
      case 'YouTube':
        return Colors.red;
      case 'Instagram':
        return Color(0xFFE1306C); // Instagram pink
      case 'Facebook':
        return Color(0xFF1877F2); // Facebook blue
      case 'Twitter':
        return Color(0xFF1DA1F2); // Twitter blue
      case 'Threads':
        return Color(0xFF000000); // Threads black
      default:
        return Colors.grey;
    }
  }

  // Helper method to get platform widget (icon or image)
  Widget _getPlatformWidget(String platform, double size) {
    switch (platform) {
      case 'YouTube':
        return Image.asset(
          'assets/loghi/logo_yt.png',
          width: size,
          height: size,
        );
      case 'TikTok':
        return Icon(
          Icons.music_note,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Instagram':
        return Icon(
          Icons.camera_alt,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Facebook':
        return Icon(
          Icons.facebook,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Twitter':
        return Icon(
          Icons.chat,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Threads':
        return Icon(
          Icons.chat_outlined,
          size: size,
          color: _getPlatformColor(platform),
        );
      default:
        return Icon(
          Icons.share,
          size: size,
          color: _getPlatformColor(platform),
        );
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
      await _forceLoadUserCredits();
      
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

  // Increment streak_bonuses when daily streak is completed
  Future<void> _addViralystScoreForStreak(int points) async {
    if (_currentUser == null) return;
    try {
      final userRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('profile');

      final snapshot = await userRef.child('streak_bonuses').get();
      int currentBonuses = 0;
      if (snapshot.exists) {
        final value = snapshot.value;
        if (value is int) {
          currentBonuses = value;
        } else if (value is String) {
          currentBonuses = int.tryParse(value) ?? 0;
        }
      }

      final newBonuses = currentBonuses + 1;
      await userRef.child('streak_bonuses').set(newBonuses);
      print('[Streak] streak_bonuses updated: $currentBonuses -> $newBonuses (+1 bonus)');
    } catch (e) {
      print('[Streak] Error updating streak_bonuses: $e');
    }
  }

  // Override del metodo didChangeDependencies per intercettare i cambi di route
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Non carichiamo automaticamente i crediti qui
    // Verranno caricati solo quando l'utente clicca sul pulsante Home nel menu
    
    // Verifichiamo lo stato di progresso dell'utente
    checkUserProgress();
    
    // Check for upgrade popup
    _checkForUpgradePopup();
    
    // Assicuriamoci che il video AI Videoclip sia in riproduzione
    if (_aiVideoclipVideoController != null && _isAiVideoclipVideoReady) {
      if (!_aiVideoclipVideoController!.value.isPlaying) {
        _aiVideoclipVideoController!.play();
      }
    }
  }

  // Override di didUpdateWidget senza ricaricare i crediti
  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset _argumentsProcessed se ci sono nuovi argomenti
    if (widget.initialArguments != oldWidget.initialArguments && widget.initialArguments != null && widget.initialArguments!['showUpgradePopup'] == true) {
      _argumentsProcessed = false;
        }
    // ... resto del codice ...
  }
  
  // Metodo centralizzato per avviare l'animazione dei crediti
  void _startCreditsAnimation() {
    if (!mounted || _userCredits <= 0) return;
    
    // L'animazione della ruota deve sempre fermarsi al 100% (500 crediti) per non premium
    // Per premium può andare oltre, ma sempre con la stessa velocità
    double wheelAnimationEndValue = _isPremium ? _userCredits.toDouble() : 500.0;
    
    // Aggiorna l'animazione della ruota (linea circolare)
    _creditsAnimation = Tween<double>(
      begin: 0,
      end: wheelAnimationEndValue,
    ).animate(CurvedAnimation(
      parent: _creditsAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Reset del progresso della ruota
    _wheelProgress = 0.0;
    
    // Aggiorna l'animazione del numero (fino al valore effettivo)
    _numberAnimation = Tween<double>(
      begin: 0,
      end: _userCredits.toDouble(),
    ).animate(CurvedAnimation(
      parent: _numberAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Avvia entrambe le animazioni
    _creditsAnimationController.forward(from: 0);
    _numberAnimationController.forward(from: 0);
    
    // Imposta il flag per indicare che l'animazione è stata eseguita
    _hasAnimatedCredits = true;
    
    print('Avviata animazione crediti: $_userCredits (ruota fino a: $wheelAnimationEndValue, numero fino a: $_userCredits)');
  }

  // Metodo pubblico per aggiornare i crediti quando l'utente naviga alla HomePage
  // tramite il pulsante Home nella barra di navigazione
  void refreshCredits() {
    print('Aggiornamento crediti richiesto da navigazione Home');
    setState(() {
      _hasAnimatedCredits = false;
    });
    _loadUserCredits();
    
    // Check for upgrade popup when returning to home
    if (!_isPremium && !_argumentsProcessed) {
      _checkForUpgradePopup();
    }
    
    // Assicuriamoci che il video AI Videoclip sia in riproduzione
    if (_aiVideoclipVideoController != null && _isAiVideoclipVideoReady) {
      if (!_aiVideoclipVideoController!.value.isPlaying) {
        _aiVideoclipVideoController!.play();
      }
    }
  }

  // Public wrapper methods for external access
  void refreshSocialAccounts() {
    loadSocialAccounts();
  }

  void refreshUserProgress() {
    checkUserProgress();
  }


  // Helper widget for reward tier card - improved design
  Widget _buildRewardTierCard(
    ThemeData theme, {
    required int number,
    required int credits,
    required bool isActive,
    required String description,
    bool isRepeating = false,
    bool isSpecial = false,
  }) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isActive 
            ? (isSpecial ? theme.primaryColor.withOpacity(0.2) : Colors.white)
            : Colors.grey[100],
        border: Border.all(
          color: isActive 
              ? (isSpecial ? theme.primaryColor : theme.primaryColor.withOpacity(0.3))
              : Colors.grey[300]!,
          width: isSpecial ? 2 : 1,
        ),
        boxShadow: isActive ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          )
        ] : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive 
                  ? (isSpecial ? theme.primaryColor : theme.primaryColor.withOpacity(0.8))
                  : Colors.grey[300],
              boxShadow: isActive ? [
                BoxShadow(
                  color: theme.primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ] : null,
            ),
            child: Center(
              child: isRepeating
                  ? const Icon(Icons.add, color: Colors.white, size: 20)
                  : Text(
                      '$number',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '+$credits',
            style: TextStyle(
              color: isActive 
                  ? (isSpecial ? theme.primaryColor : theme.primaryColor.withOpacity(0.8))
                  : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  // Helper widget for reward tier (legacy)
  Widget _buildRewardTier(
    ThemeData theme, {
    required int number,
    required int credits,
    required bool isActive,
    bool isRepeating = false,
  }) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? theme.primaryColor
                : Colors.grey[300],
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: theme.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              isRepeating ? '4+' : number.toString(),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 12,
              color: isActive ? theme.primaryColor : Colors.grey[600],
            ),
            Text(
              '$credits',
              style: TextStyle(
                color: isActive ? theme.primaryColor : Colors.grey[600],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        Text(
          'credits',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  
  // Helper widget for referral step
  Widget _buildReferralStep(
    ThemeData theme, {
    required int number,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.primaryColor,
            ),
            child: Center(
              child: Text(
                number.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
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
                    color: Colors.grey[800],
                  ),
                ),
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
      ),
    );
  }

  // Calculate the current referral tier
  String _getReferralTier() {
    if (_referredUsersCount >= 10) return 'Gold';
    if (_referredUsersCount >= 5) return 'Silver';
    if (_referredUsersCount >= 3) return 'Bronze';
    if (_referredUsersCount >= 1) return 'Starter';
    return 'New';
  }
  
  // Calculate progress width for the progress bar
  double _getProgressWidth() {
    if (_referredUsersCount == 0) return 0;
    // Calculate width based on progress through tiers
    final double baseWidth = MediaQuery.of(context).size.width - 80; // Accounting for padding
    if (_referredUsersCount >= 4) return baseWidth;
    return baseWidth * (_referredUsersCount / 4);
  }
  
  // Helper widget for referral step card
  Widget _buildReferralStepCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: theme.primaryColor,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper widget for step connector
  Widget _buildStepConnector(ThemeData theme) {
    return Container(
      width: 20,
      child: Center(
        child: Icon(
          Icons.arrow_forward,
          color: theme.primaryColor.withOpacity(0.5),
          size: 16,
        ),
      ),
    );
  }
  
  // Helper widget for getting started card (used for rewards in horizontal scrolling)
  Widget _buildGettingStartedCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required bool isCompleted,
  }) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCompleted ? theme.primaryColor.withOpacity(0.1) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? theme.primaryColor : theme.colorScheme.outline,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCompleted ? theme.primaryColor : Colors.grey[100],
              shape: BoxShape.circle,
              boxShadow: isCompleted
                  ? [
                      BoxShadow(
                        color: theme.primaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check, color: Colors.white, size: 24)
                  : Icon(icon, color: theme.iconTheme.color?.withOpacity(0.8), size: 24),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isCompleted ? theme.primaryColor : theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isCompleted ? theme.primaryColor.withOpacity(0.8) : theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  // Challenges section (UI only, no database wiring yet)
  Widget _buildChallengesSection(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final dailyProgress = _dailyGoalVideos > 0
        ? (_dailyPublishedVideos / _dailyGoalVideos).clamp(0.0, 1.0)
        : 0.0;
    final streakProgress =
        (_currentStreakDays / (_bestStreakDays == 0 ? 1 : _bestStreakDays)).clamp(0.0, 1.0);
    final customProgress = _customChallengeTarget > 0
        ? (_customChallengeProgress / _customChallengeTarget).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
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
                  'Challenges',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildChallengeCircle(
                  theme: theme,
                  title: 'Daily goal',
                  primaryColor: const Color(0xFF3B82F6), // Blue
                  icon: Icons.videocam_rounded,
                  progress: dailyProgress,
                  subtitleLines: [
                    'Daily goal: $_dailyGoalVideos',
                    'Completed: $_dailyPublishedVideos/$_dailyGoalVideos',
                  ],
                  onTap: _showDailyGoalSettings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -14), // raise streak card ~0.5cm
                  child: _buildChallengeCircle(
                    theme: theme,
                    title: 'Streak',
                    primaryColor: const Color(0xFF10B981), // Green
                    icon: Icons.local_fire_department_rounded,
                    progress: streakProgress,
                    subtitleLines: [
                    'Current streak: $_currentStreakDays',
                    'Best record: $_bestStreakDays',
                    ],
                    onTap: _showStreakDetails,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildChallengeCircle(
                  theme: theme,
                  title: 'Custom',
                  primaryColor: const Color(0xFFF97316), // Orange
                  icon: Icons.edit_rounded,
                  progress: customProgress,
                  subtitleLines: [
                    '"${_getShortCustomChallengeLabel()}"',
                    '$_customChallengeProgress/$_customChallengeTarget done',
                  ],
                  onTap: _showCustomChallengeSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: Color(0xFF667eea),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.1, 0.0),
                            end: const Offset(0.0, 0.0),
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      'AI tip: ${_getTodayAiTip()}',
                      key: ValueKey<int>(_currentAiTipIndex),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withOpacity(0.8)
                            : const Color(0xFF1A1A1A).withOpacity(0.8),
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

  Widget _buildChallengeCircle({
    required ThemeData theme,
    required String title,
    required Color primaryColor,
    required IconData icon,
    required double progress,
    required List<String> subtitleLines,
    required VoidCallback onTap,
  }) {
    final isCompleted = progress >= 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: isCompleted
                      ? [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.45),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.20),
                            blurRadius: 10,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: CustomPaint(
                        painter: GradientCircularProgressPainter(
                          progress: animatedValue.clamp(0.0, 1.0),
                          strokeWidth: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceVariant.withOpacity(0.4),
                          gradient: LinearGradient(
                            colors: [
                              primaryColor.withOpacity(0.9),
                              primaryColor.withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.cardColor.withOpacity(0.95),
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(
                                Icons.check_rounded,
                                color: primaryColor,
                                size: 28,
                              )
                            : Icon(
                                icon,
                                color: primaryColor,
                                size: 26,
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ...subtitleLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Reusable glass-style button used in challenges bottom sheets
  Widget _buildGlassChoiceButton(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    final Color baseColor = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.white.withOpacity(0.50);
    final Color selectedColor = isDark
        ? Colors.white.withOpacity(0.18)
        : Colors.white.withOpacity(0.80);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? selectedColor : baseColor,
            border: Border.all(
              color: selected
                  ? const Color(0xFF667eea).withOpacity(0.9)
                  : Colors.white.withOpacity(isDark ? 0.35 : 0.55),
              width: selected ? 1.7 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.45 : 0.10),
                blurRadius: selected ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? (isDark ? Colors.white : const Color(0xFF111827))
                    : (isDark
                        ? Colors.white.withOpacity(0.85)
                        : const Color(0xFF111827).withOpacity(0.85)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDailyGoalSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        int localDailyGoal = _dailyGoalVideos;

        void updateGoal(StateSetter setModalState, int newValue) {
          if (newValue < 1) newValue = 1;
          if (newValue > 20) newValue = 20;

          setModalState(() {
            localDailyGoal = newValue;
          });

          // Sync with main state so the home card is updated too
          setState(() {
            _dailyGoalVideos = newValue;
            if (_dailyPublishedVideos > _dailyGoalVideos) {
              _dailyPublishedVideos = _dailyGoalVideos;
            }
          });
          _saveChallengesToDatabase();
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'Daily goal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose how many videos you want to publish every day. Keep it realistic to build a strong habit.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Preset goals 1 / 2 / 3 with glass buttons, perfectly symmetric
                      Row(
                        children: [1, 2, 3].map((value) {
                          final isSelected = localDailyGoal == value;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _buildGlassChoiceButton(
                                theme,
                                label: '$value',
                                selected: isSelected,
                                onTap: () {
                                  updateGoal(setModalState, value);
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Custom goal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: theme.brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.white.withOpacity(0.55),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.35)
                                : Colors.black.withOpacity(0.06),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                  theme.brightness == Brightness.dark ? 0.45 : 0.10),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            // Decrease button
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: _buildGlassChoiceButton(
                                theme,
                                label: '−',
                                selected: false,
                                onTap: () {
                                  updateGoal(setModalState, localDailyGoal - 1);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Current value
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Current goal',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$localDailyGoal per day',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Increase button
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: _buildGlassChoiceButton(
                                theme,
                                label: '+',
                                selected: false,
                                onTap: () {
                                  updateGoal(setModalState, localDailyGoal + 1);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Helper to change daily goal with clamping and persistence
  void _changeDailyGoal(int delta) {
    setState(() {
      int next = _dailyGoalVideos + delta;
      if (next < 1) next = 1;
      if (next > 20) next = 20;
      _dailyGoalVideos = next;
      if (_dailyPublishedVideos > _dailyGoalVideos) {
        _dailyPublishedVideos = _dailyGoalVideos;
      }
    });
    _saveChallengesToDatabase();
  }

  void _showStreakDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Streak',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your streak grows every day you hit at least 1 video.\nDo not break the chain!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Each active day adds +100 points to your Fluzar Score.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactStreakStat(
                          theme: theme,
                          label: 'Current streak',
                      value: '$_currentStreakDays 🔥',
                          icon: Icons.local_fire_department_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCompactStreakStat(
                          theme: theme,
                          label: 'Best record',
                      value: '$_bestStreakDays',
                          icon: Icons.emoji_events_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildStreakLast30DaysChart(theme, isDark),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactStreakStat({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.55),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.35)
              : Colors.black.withOpacity(0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(isDark ? 0.45 : 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build 30-day streak graph based on days with at least one published video
  Widget _buildStreakLast30DaysChart(ThemeData theme, bool isDark) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Build a list of the last 30 days (oldest on the left)
    final List<DateTime> last30Days = List.generate(30, (index) {
      final day = today.subtract(Duration(days: 29 - index));
      return DateTime(day.year, day.month, day.day);
    });

    // Helper to convert day to string key
    String _dayKey(DateTime day) {
      return '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
    }

    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.50),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.30) : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.45 : 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Last 30 days',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Streak day',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'No post',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: last30Days.map((day) {
                final key = _dayKey(day);
                final count = _publishedVideosPerDay[key] ?? 0;
                final hasPost = count > 0;

                // Highlight today with a slightly taller bar
                final bool isToday = day == today;
                final double heightFactor = hasPost
                    ? (isToday ? 1.0 : 0.8)
                    : 0.3;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      height: 50 * heightFactor,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: hasPost
                            ? const Color(0xFF10B981)
                            : (isDark
                                ? Colors.white.withOpacity(0.10)
                                : Colors.black.withOpacity(0.06)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomChallengeSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final TextEditingController controller =
            TextEditingController(text: _todayCustomChallenge);

        final List<String> presets = [
          'Publish a talking video',
          'Use a trend',
          'Comment 10 posts',
          'Try a new style',
          'Improve a title',
          'Experiment with a new format',
        ];

        bool optionsExpanded = _hasCompletedCustomChallengeToday();
        bool completedToday = _hasCompletedCustomChallengeToday();

        return StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey[400],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Text(
                            'Custom challenge',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pick one of the suggested challenges or create your own. Micro-challenges keep you motivated every day.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Completion control
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.08)
                                  : Colors.white.withOpacity(0.55),
                              border: Border.all(
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white.withOpacity(0.35)
                                    : Colors.black.withOpacity(0.06),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(
                                      theme.brightness == Brightness.dark ? 0.45 : 0.10),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: completedToday
                                        ? const Color(0xFF10B981).withOpacity(0.15)
                                        : Colors.orange.withOpacity(0.12),
                                  ),
                                  child: Icon(
                                    completedToday
                                        ? Icons.check_circle_rounded
                                        : Icons.flag_rounded,
                                    size: 18,
                                    color: completedToday
                                        ? const Color(0xFF10B981)
                                        : Colors.orange,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    completedToday
                                        ? 'Nice! This will be saved in your history.'
                                        : 'Mark it as completed to keep track of your wins.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: _buildGlassChoiceButton(
                                    theme,
                                    label: completedToday ? 'Completed' : 'Mark done',
                                    selected: completedToday,
                                    onTap: () async {
                                      setModalState(() {
                                        completedToday = true;
                                      });
                                      await _markCustomChallengeCompletedToday();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Collapsible options section styled like social accounts panel
                          Container(
                            decoration: BoxDecoration(
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20),
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
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        optionsExpanded = !optionsExpanded;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.tips_and_updates,
                                            size: 18,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Challenge options',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          AnimatedRotation(
                                            turns: optionsExpanded ? 0.5 : 0.0,
                                            duration: const Duration(milliseconds: 200),
                                            child: Icon(
                                              Icons.keyboard_arrow_down,
                                              size: 20,
                                              color: theme.textTheme.bodySmall?.color
                                                  ?.withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 250),
                                    crossFadeState: optionsExpanded
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            'Suggested challenges',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Column(
                                            children: presets.map((challenge) {
                                              final isSelected =
                                                  _todayCustomChallenge == challenge;
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: SizedBox(
                                                  width: double.infinity,
                                                  child: _buildGlassChoiceButton(
                                                    theme,
                                                    label: challenge,
                                                    selected: isSelected,
                                                    onTap: () {
                                                      setState(() {
                                                        _todayCustomChallenge = challenge;
                                                        _customChallengeProgress = 0;
                                                        _customChallengeTarget = 1;
                                                      });
                                                      _saveChallengesToDatabase();
                                                      Navigator.of(context).pop();
                                                    },
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                          const SizedBox(height: 20),
                                          Text(
                                            'Or write your own',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(18),
                                              color: theme.brightness == Brightness.dark
                                                  ? Colors.white.withOpacity(0.08)
                                                  : Colors.white.withOpacity(0.55),
                                              border: Border.all(
                                                color: theme.brightness == Brightness.dark
                                                    ? Colors.white.withOpacity(0.35)
                                                    : Colors.black.withOpacity(0.06),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(
                                                      theme.brightness == Brightness.dark
                                                          ? 0.45
                                                          : 0.10),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            child: TextField(
                                              controller: controller,
                                              maxLines: 2,
                                              decoration: const InputDecoration(
                                                hintText: 'Example: Record a Q&A video',
                                                border: InputBorder.none,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                final text = controller.text.trim();
                                                if (text.isNotEmpty) {
                                                  setState(() {
                                                    _todayCustomChallenge = text;
                                                    _customChallengeProgress = 0;
                                                    _customChallengeTarget = 1;
                                                  });
                                                  _saveChallengesToDatabase();
                                                }
                                                Navigator.of(context).pop();
                                              },
                                              icon: const Icon(Icons.check_rounded, size: 18),
                                              label: const Text('Save challenge'),
                                              style: ElevatedButton.styleFrom(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(14),
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
                          const SizedBox(height: 18),
                          // Completed challenges history
                          if (_completedCustomChallenges.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Completed challenges',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Column(
                              children: _completedCustomChallenges
                                  .map((challenge) {
                                final title =
                                    (challenge['title'] as String?) ?? '';
                                final ts =
                                    (challenge['completed_at'] as int?) ?? 0;
                                final date = DateTime.fromMillisecondsSinceEpoch(
                                    ts > 0 ? ts : 0);
                                final formatted = ts > 0
                                    ? DateFormat('MMM d').format(date)
                                    : '';
                                final String challengeId =
                                    (challenge['id'] as String?) ??
                                        '${title}_$ts';
                                return Dismissible(
                                  key: Key('completed_challenge_$challengeId'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    margin:
                                        const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.red.shade400,
                                          Colors.red.shade600,
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.centerRight,
                                    padding:
                                        const EdgeInsets.only(right: 20),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  onDismissed: (direction) {
                                    _deleteCompletedCustomChallenge(
                                        challenge);
                                  },
                                  child: Container(
                                    margin:
                                        const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      color: theme.brightness ==
                                              Brightness.dark
                                          ? Colors.white.withOpacity(0.06)
                                          : Colors.white.withOpacity(0.85),
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.15),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          size: 18,
                                          color: Color(0xFF10B981),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              fontWeight:
                                                  FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (formatted.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            formatted,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              fontSize: 11,
                                              color: theme
                                                  .textTheme.bodySmall
                                                  ?.color
                                                  ?.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Once you complete challenges, they will appear here as a simple history of your wins.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getTodayAiTip() {
    if (_aiTips.isEmpty) {
      return '';
    }
    // Use the rotating index controlled by a periodic timer
    final safeIndex =
        _currentAiTipIndex % _aiTips.length;
    return _aiTips[safeIndex];
  }

  // Helper to shorten custom challenge label for the main card
  String _getShortCustomChallengeLabel() {
    const int maxChars = 11;
    final label = _todayCustomChallenge;
    if (label.length <= maxChars) {
      return label;
    }
    return '${label.substring(0, maxChars)}...';
  }

  // Check if today already has a completed custom challenge with the SAME title
  // in modo che cambiando challenge il pulsante torni "non completato"
  bool _hasCompletedCustomChallengeToday({String? challengeTitle}) {
    if (_completedCustomChallenges.isEmpty) return false;
    final now = DateTime.now();
    // Usa il titolo passato (se presente) oppure l'attuale challenge del giorno
    final String normalizedTitle =
        (challengeTitle ?? _todayCustomChallenge).trim();
    if (normalizedTitle.isEmpty) return false;
    for (final entry in _completedCustomChallenges) {
      final ts = (entry['completed_at'] as int?) ?? 0;
      if (ts <= 0) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final String entryTitle =
          (entry['title'] as String?)?.trim() ?? '';
      if (entryTitle.isEmpty) continue;
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day &&
          entryTitle == normalizedTitle) {
        return true;
      }
    }
    return false;
  }

  // Mark the current custom challenge as completed for today and save it to Firebase history
  Future<void> _markCustomChallengeCompletedToday() async {
    if (_currentUser == null || !mounted) return;
    if (_todayCustomChallenge.trim().isEmpty) return;

    final now = DateTime.now();

    final completedEntry = <String, dynamic>{
      'title': _todayCustomChallenge,
      'completed_at': now.millisecondsSinceEpoch,
    };

    setState(() {
      _customChallengeProgress = _customChallengeTarget;
      _completedCustomChallenges.insert(0, completedEntry);
    });
    _saveChallengesToDatabase();

    try {
      final challengesRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('challenges')
          .child('completed_custom_challenges');

      final newRef = challengesRef.push();
      // Salviamo anche l'ID generato dentro all'entry per poterlo riusare in locale
      final withId = Map<String, dynamic>.from(completedEntry)
        ..['id'] = newRef.key;
      await newRef.set(withId);
    } catch (e) {
      print('Error saving completed custom challenge: $e');
    }
  }

  // Load challenges configuration from Firebase under users/users/{uid}/challenges
  Future<void> _loadChallengesSettings() async {
    if (_currentUser == null || !mounted) return;

    try {
      final challengesRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('challenges');

      final snapshot = await challengesRef.get();

      if (!mounted) return;

      if (snapshot.exists && snapshot.value is Map) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        List<Map<String, dynamic>> completedChallenges = [];
        if (data['completed_custom_challenges'] is Map) {
          final raw = data['completed_custom_challenges'] as Map<dynamic, dynamic>;
          completedChallenges = raw.entries
              .where((e) => e.value is Map)
              .map((e) {
                final entryMap = (e.value as Map<dynamic, dynamic>)
                    .map((k, v) => MapEntry(k.toString(), v));
                // Salviamo anche l'ID Firebase per poter cancellare la challenge
                entryMap['id'] = e.key.toString();
                return entryMap;
              })
              .toList();
          completedChallenges.sort((a, b) {
            final at = (a['completed_at'] as int?) ?? 0;
            final bt = (b['completed_at'] as int?) ?? 0;
            return bt.compareTo(at);
          });
        }

        setState(() {
          _dailyGoalVideos =
              (data['daily_goal_videos'] as int?) ?? _dailyGoalVideos;
          _currentStreakDays =
              (data['current_streak_days'] as int?) ?? _currentStreakDays;
          _bestStreakDays =
              (data['best_streak_days'] as int?) ?? _bestStreakDays;
          _todayCustomChallenge =
              (data['custom_challenge_title'] as String?) ??
                  _todayCustomChallenge;
          _customChallengeProgress =
              (data['custom_challenge_progress'] as int?) ??
                  _customChallengeProgress;
          _customChallengeTarget =
              (data['custom_challenge_target'] as int?) ??
                  _customChallengeTarget;
          _completedCustomChallenges = completedChallenges;
          _lastStreakRewardDateEpoch =
              (data['last_streak_reward_date_epoch'] as int?) ??
                  _lastStreakRewardDateEpoch;
        });
      } else {
        // Create default challenges node the first time
        await _saveChallengesToDatabase();
      }
    } catch (e) {
      print('Error loading challenges settings: $e');
    }
  }

  // Elimina una challenge completata sia dalla lista locale che da Firebase
  Future<void> _deleteCompletedCustomChallenge(
      Map<String, dynamic> challenge) async {
    if (_currentUser == null || !mounted) return;

    try {
      final challengesRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('challenges')
          .child('completed_custom_challenges');

      final String title = (challenge['title'] as String?) ?? '';
      final int completedAt = (challenge['completed_at'] as int?) ?? 0;
      final String? id = challenge['id'] as String?;

      String? keyToDelete = id;

      // Se non abbiamo l'id, cerchiamo per title + completed_at (fallback per vecchi dati)
      if (keyToDelete == null || keyToDelete.isEmpty) {
        final snap = await challengesRef.get();
        if (snap.exists && snap.value is Map) {
          final raw = snap.value as Map<dynamic, dynamic>;
          raw.forEach((k, v) {
            if (keyToDelete != null) return;
            if (v is Map) {
              final vTitle = (v['title'] as String?) ?? '';
              final vTs = (v['completed_at'] as int?) ?? 0;
              if (vTitle == title && vTs == completedAt) {
                keyToDelete = k.toString();
              }
            }
          });
        }
      }

      if (keyToDelete != null && keyToDelete!.isNotEmpty) {
        await challengesRef.child(keyToDelete!).remove();
      }

      // Aggiorna lo stato locale
      setState(() {
        _completedCustomChallenges.removeWhere((c) {
          final cid = (c['id'] as String?) ?? '';
          if (id != null && id.isNotEmpty) {
            return cid == id;
          }
          // Fallback per vecchie entry senza id
          final cTitle = (c['title'] as String?) ?? '';
          final cTs = (c['completed_at'] as int?) ?? 0;
          return cTitle == title && cTs == completedAt;
        });
      });
    } catch (e) {
      print('Error deleting completed challenge: $e');
    }
  }

  // Persist challenges configuration to Firebase under users/users/{uid}/challenges
  Future<void> _saveChallengesToDatabase() async {
    if (_currentUser == null) return;

    try {
      final challengesRef = _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('challenges');

      await challengesRef.update({
        'daily_goal_videos': _dailyGoalVideos,
        'current_streak_days': _currentStreakDays,
        'best_streak_days': _bestStreakDays,
        'custom_challenge_title': _todayCustomChallenge,
        'custom_challenge_progress': _customChallengeProgress,
        'custom_challenge_target': _customChallengeTarget,
        'last_streak_reward_date_epoch': _lastStreakRewardDateEpoch,
      });
    } catch (e) {
      print('Error saving challenges settings: $e');
    }
  }

  // Card per navigare alla pagina dei trend social
  Widget _buildTrendsCard(ThemeData theme) {
    const double trendsSectionHeight = 320;
    final isDark = theme.brightness == Brightness.dark;
    return Transform.translate(
      offset: const Offset(0, -1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TrendsPage(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            margin: const EdgeInsets.only(top: 18, bottom: 10),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
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
              // Header con titolo
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
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
                      'AI-Trends Finder',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 0),
              
              // NUOVA SEZIONE: Top Trends scorrevoli orizzontalmente
                Row(
                  children: [
                    Text(
                      'Top Trends',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark 
                            ? Colors.white.withOpacity(0.9)
                          : const Color(0xFF1A1A1A).withOpacity(0.9),
                      ),
                    ),
                    const Spacer(),
                    Text(
                    _topTrends.isNotEmpty ? '${_topTrends.length} trends' : '3 trends',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark 
                            ? Colors.white.withOpacity(0.6)
                          : const Color(0xFF1A1A1A).withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
              if (_topTrends.isNotEmpty) ...[
                // Scroll orizzontale dei trend (come trends_page.dart)
                SizedBox(
                  height: trendsSectionHeight, // Aumentata ulteriormente per il grafico
                  child: PageView.builder(
                    controller: _trendPageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentTrendIndex = index;
                      });
                      // Start animations when scrolling between trends
                      _trendChartAnimationController.reset();
                      _trendScoreAnimationController.reset();
                      
                      // Only reset typing animation if it hasn't been completed for this index
                      if (!_completedTypingAnimations.contains(index)) {
                        _typingAnimationController.reset();
                        _typingAnimationController.forward();
                      } else {
                        // If animation already completed, set it to completed state
                        _typingAnimationController.forward();
                      }
                      
                      _trendChartAnimationController.forward();
                      _trendScoreAnimationController.forward();
                    },
                    itemCount: _topTrends.length,
                    itemBuilder: (context, index) {
                      final trend = _topTrends[index];
                      return Container(
                        margin: const EdgeInsets.only(right: 12),
                        child: _buildTrendCard(theme, trend, isDark, index),
                      );
                    },
                  ),
                ),
                
                const SizedBox(height: 16),
              ] else ...[
                // Loading state con singolo card placeholder (stessa dimensione del PageView)
                SizedBox(
                  height: trendsSectionHeight,
                  child: Align(
                    alignment: Alignment.center,
                    child: FractionallySizedBox(
                      widthFactor: 0.92,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.03)
                              : Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.black.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                Container(
                                width: 64,
                                height: 24,
                  decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : const Color(0xFFE5E6FF),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: isDark
                                      ? Colors.white.withOpacity(0.18)
                                      : Colors.black.withOpacity(0.08),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.7,
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: isDark
                                        ? Colors.white.withOpacity(0.12)
                                        : Colors.black.withOpacity(0.06),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                    color: isDark 
                        ? Colors.white.withOpacity(0.05)
                                        : Colors.black.withOpacity(0.03),
                  ),
                  child: Center(
                                    child: Lottie.asset(
                          'assets/animations/MainScene.json',
                                      width: trendsSectionHeight * 0.35,
                                      height: trendsSectionHeight * 0.35,
                          fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 10,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        color: isDark
                                            ? Colors.white.withOpacity(0.12)
                                            : Colors.black.withOpacity(0.08),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 48,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      color: isDark
                                          ? Colors.white.withOpacity(0.12)
                                          : Colors.black.withOpacity(0.08),
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
                const SizedBox(height: 16),
              ],
              
              // Footer con feature e freccia (PARTE BASSA - COME PRIMA)
              Row(
                children: [
                  // Feature badge con gradiente - mostrato solo quando i trend sono caricati
                  if (_topTrends.isNotEmpty)
                    Transform.translate(
                      offset: const Offset(0, -4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              color: Color(0xFF667eea).withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Real-time AI',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  const Spacer(),
                  
                  // Freccia con gradiente viola allineata con community card - solo se i trend sono caricati
                  if (_topTrends.isNotEmpty) ...[
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
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildTrendCard(ThemeData theme, Map<String, dynamic> trend, bool isDark, int index) {
    final platform = trend['platform'] as String;
    final trendName = trend['trend_name'] as String;
    final description = trend['description'] as String;
    final viralityScore = trend['virality_score'] as num? ?? 0.0;
    final growthRate = trend['growth_rate'] as String? ?? '';
    final trendLevel = trend['trend_level'] as String? ?? '⏸';
    final category = trend['category'] as String? ?? '';
    final hashtags = trend['hashtags'] as List<dynamic>? ?? [];
    final dataPoints = trend['data_points'] as List<dynamic>? ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? Color(0xFF1E1E1E)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with platform logo and trend level
            Row(
              children: [
                // Platform logo
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getPlatformColorForTrend(platform).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: _getPlatformLogo(platform),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    platform.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getPlatformColorForTrend(platform),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Trend name
            Text(
              trendName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark 
                    ? Colors.white
                    : Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 6),
            
            // Description with typing animation - fixed height container
            Container(
              height: 60, // Fixed height for 3 lines (11px font + line height ~23px each)
              child: description.isNotEmpty
                  ? TypingTextWidget(
                      text: description,
                      animation: _typingAnimation,
                      isCompleted: _completedTypingAnimations.contains(index),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark 
                            ? Colors.white.withOpacity(0.7)
                            : Colors.black.withOpacity(0.7),
                        height: 1.2, // Line height
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.visible,
                    )
                  : null,
            ),
            
            // Engagement rate chart (minimal, senza scritte)
            if (dataPoints.isNotEmpty)
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildEngagementChart(dataPoints, isDark),
                ),
              ),
            
            const SizedBox(height: 4),
            
            // Stats row - compact design like premium version
            Row(
              children: [
                Expanded(
                  child: _buildCompactStatItem(
                    'Score',
                    '${viralityScore.toStringAsFixed(0)}',
                    Icons.trending_up,
                    isDark,
                    targetScore: viralityScore.toDouble(),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildCompactStatItem(
                    'Growth',
                    growthRate.isNotEmpty ? _cleanGrowthRate(growthRate) : '0%',
                    Icons.speed,
                    isDark,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildCompactStatItem(
                    'Viral',
                    _getViralPosition(index),
                    Icons.whatshot,
                    isDark,
                  ),
                ),
              ],
            ),
            
          ],
        ),
      ),
    );
  }

  Widget _buildEngagementChart(List<dynamic> dataPoints, bool isDark) {
    if (dataPoints.isEmpty) return const SizedBox.shrink();
    
    // Estrai i valori di engagement rate dai dataPoints
    List<double> engagementValues = [];
    for (var point in dataPoints) {
      if (point is Map && point['engagement_rate'] != null) {
        engagementValues.add((point['engagement_rate'] as num).toDouble());
      }
    }
    
    if (engagementValues.isEmpty) return const SizedBox.shrink();
    
    // Calcolo il massimo e minimo per lo scaling
    final maxValue = engagementValues.reduce(max);
    final minValue = engagementValues.reduce(min);
    final range = maxValue - minValue;
    
    return AnimatedBuilder(
      animation: _trendChartAnimation,
      builder: (context, child) {
        return LineChart(
          LineChartData(
            gridData: FlGridData(show: false),
            titlesData: FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              enabled: false,
            ),
            lineBarsData: [
              LineChartBarData(
                spots: engagementValues.asMap().entries.map((e) {
                  final x = e.key.toDouble();
                  final y = range > 0 ? ((e.value - minValue) / range * 80).toDouble() : 40.0;
                  return FlSpot(x, y * _trendChartAnimation.value);
                }).toList(),
                isCurved: true,
                color: const Color(0xFF667eea),
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 3,
                      color: const Color(0xFF667eea),
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: const Color(0xFF667eea).withOpacity(0.1 * _trendChartAnimation.value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _getPlatformLogo(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return Image.asset(
          'assets/loghi/logo_tiktok.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.music_note,
              size: 20,
              color: _getPlatformColorForTrend(platform),
            );
          },
        );
      case 'youtube':
        return Image.asset(
          'assets/loghi/logo_yt.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.play_arrow,
              size: 20,
              color: _getPlatformColorForTrend(platform),
            );
          },
        );
      case 'instagram':
        return Image.asset(
          'assets/loghi/logo_insta.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.camera_alt,
              size: 20,
              color: _getPlatformColorForTrend(platform),
            );
          },
        );
      case 'facebook':
        return Image.asset(
          'assets/loghi/logo_facebook.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.facebook,
              size: 20,
              color: _getPlatformColorForTrend(platform),
            );
          },
        );
      case 'twitter':
        return Image.asset(
          'assets/loghi/logo_twitter.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.chat,
              size: 20,
              color: _getPlatformColorForTrend(platform),
            );
          },
        );
      case 'threads':
        return Image.asset(
          'assets/loghi/threads_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.chat_outlined,
              size: 20,
              color: _getPlatformColorForTrend(platform),
            );
          },
        );
      default:
        return Icon(
          Icons.share,
          size: 16,
          color: _getPlatformColorForTrend(platform),
        );
    }
  }

  Color _getPlatformColorForTrend(String platform) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return isDark ? Colors.white : const Color(0xFF000000);
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'instagram':
        return const Color(0xFFE4405F);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'twitter':
        return const Color(0xFF1DA1F2);
      case 'threads':
        return isDark ? Colors.white : const Color(0xFF000000);
      default:
        return isDark ? Colors.white : Colors.grey;
    }
  }

  Widget _buildCompactStatItem(String label, String value, IconData icon, bool isDark, {double? targetScore}) {
    return AnimatedBuilder(
      animation: _trendScoreAnimation,
      builder: (context, child) {
        // Use jackpot-style animation for score, regular value for others
        String displayValue = value;
        if (label == 'Score' && targetScore != null) {
          displayValue = (targetScore * _trendScoreAnimation.value).toStringAsFixed(0);
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 12,
                color: isDark 
                    ? Colors.white.withOpacity(0.7)
                    : Colors.black.withOpacity(0.7),
              ),
              const SizedBox(height: 2),
              Text(
                displayValue,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark 
                      ? Colors.white.withOpacity(0.9)
                      : Colors.black.withOpacity(0.9),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 7,
                  color: isDark 
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _cleanGrowthRate(String growthRate) {
    // Rimuovi "last week" e altri testi indesiderati in modo più aggressivo
    String cleaned = growthRate
        .replaceAll('last week', '')
        .replaceAll('Last week', '')
        .replaceAll('LAST WEEK', '')
        .replaceAll('(last week)', '')
        .replaceAll('(Last week)', '')
        .replaceAll('(LAST WEEK)', '')
        .replaceAll('()', '') // Rimuovi parentesi vuote
        .replaceAll('( )', '') // Rimuovi parentesi con spazio
        .trim();
    
    // Se è vuoto dopo la pulizia, restituisci 0%
    if (cleaned.isEmpty) {
      return '0%';
    }
    
    return cleaned;
  }

  String _getViralPosition(int index) {
    switch (index) {
      case 0:
        return '1°';
      case 1:
        return '2°';
      case 2:
        return '3°';
      default:
        return '${index + 1}°';
    }
  }


  // Card per navigare alla pagina AI Videoclip
  Widget _buildAiVideoclipCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SwiftiaVideoclipPage(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 10),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark 
                ? const Color(0xFF1A1A1A).withOpacity(0.95)
                : const Color(0xFFFAFAFA).withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.08),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
              if (!isDark)
              BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 1,
                  spreadRadius: -1,
                  offset: const Offset(0, 1),
                ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                  ? [
                      const Color(0xFF2A2A2A).withOpacity(0.3),
                      const Color(0xFF1A1A1A).withOpacity(0.1),
                    ]
                  : [
                      Colors.white.withOpacity(0.4),
                      Colors.white.withOpacity(0.2),
                    ],
            ),
          ),
          child: Stack(
            children: [
              Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  Row(
                          children: [
                      Lottie.asset(
                        'assets/animations/analizeAI.json',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ShaderMask(
                              shaderCallback: (Rect bounds) {
                            return const LinearGradient(
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
                            'AI-Videoclip',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                                  color: Colors.white,
                              fontSize: 16,
                              letterSpacing: -0.5,
                              fontFamily: 'Ethnocentric',
                            ),
                                ),
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(height: 20),
                        Text(
                    'Create engaging short-form videos from YouTube content using AI',
                    style: TextStyle(
                      fontSize: 15,
                            color: isDark 
                                ? Colors.white.withOpacity(0.7)
                          : const Color(0xFF1A1A1A).withOpacity(0.7),
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                          children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
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
                              color: const Color(0xFF667eea).withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'AI Videoclip generator',
                                style: TextStyle(
                                  fontSize: 12,
                                fontWeight: FontWeight.w600,
                                  color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                    ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(
                          Icons.arrow_forward_ios,
                          color: isDark
                              ? Colors.white.withOpacity(0.7)
                              : const Color(0xFF1A1A1A).withOpacity(0.6),
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
                            Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
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
                        color: const Color(0xFF667eea).withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 0,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Card per analizzare con l'IA gli ultimi 5 video pubblicati (solo UI)
  Widget _buildAiContentInsightsCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    // Filtra solo i video con status "published"
    final recentVideos = _videos
        .where((video) => (video['status'] as String? ?? 'published') == 'published')
        .take(3)
        .toList();
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MultiVideoInsightsPage(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 10),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con titolo
              Row(
                children: [
              Lottie.asset(
                'assets/animations/analizeAI.json',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
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
                      'AI Multi-Posts Insights',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Descrizione minimale
              Text(
                'Let AI compare multiple posts side by side, highlight the strongest content, and suggest how to improve the next posts.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark 
                      ? Colors.white.withOpacity(0.75)
                      : const Color(0xFF1A1A1A).withOpacity(0.75),
                  height: 1.25,
                ),
              ),
          const SizedBox(height: 16),
          
          // Sezione video con scroll orizzontale
          if (recentVideos.isEmpty)
            // Bottone se non ci sono video
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.pushNamed(context, '/upload');
                },
                borderRadius: BorderRadius.circular(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.5),
                          width: 1.2,
                        ),
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.white.withOpacity(0.35),
                        gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(isDark ? 0.14 : 0.5),
                            Colors.white.withOpacity(isDark ? 0.05 : 0.3),
                          ],
                    ),
                    boxShadow: [
                      BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.35 : 0.15),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (Rect bounds) {
                              return const LinearGradient(
                                colors: [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ).createShader(bounds);
                            },
                            child: const Icon(
                              Icons.cloud_upload_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                          ),
                          const SizedBox(width: 8),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (Rect bounds) {
                              return const LinearGradient(
                                colors: [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ).createShader(bounds);
                            },
                            child: const Text(
                        'Upload Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            // PageView orizzontale per i video
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 140,
                  child: PageView.builder(
                    controller: _recentVideosPageController,
                    scrollDirection: Axis.horizontal,
                    itemCount: recentVideos.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentVideoIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final video = recentVideos[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _buildCompactVideoCard(theme, video),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Indicatori di pagina
                if (recentVideos.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(recentVideos.length, (index) {
                      return Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _currentVideoIndex 
                              ? const Color(0xFF667eea)
                              : (isDark 
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.black.withOpacity(0.2)),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          
          const SizedBox(height: 12),
          // Footer minimale: badge AI e freccia
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667eea).withOpacity(0.25),
                      blurRadius: 6,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'AI-powered',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
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

  // Card per navigare alla pagina community
  Widget _buildCommunityCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CommunityPage(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 10),
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
                margin: const EdgeInsets.only(left: 8, right: 8),
                padding: const EdgeInsets.all(10),
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
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                    Icons.people, 
                    color: Colors.white, 
                    size: 22
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                            'Community',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                            child: Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect with creators & compete with friends',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark 
                            ? Colors.white.withOpacity(0.7)
                            : theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
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
                          child: Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
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
                            'Fluzar Score & Leaderboards',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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

  // Widget per costruire una card video nella home (simile a history_page)
  Widget _buildHomeVideoCard(ThemeData theme, Map<String, dynamic> video) {
    // Distinzione nuovo/vecchio formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    // DATA: Calcolo timestamp per visualizzazione
    int timestamp;
    if (isNewFormat) {
      timestamp = video['scheduled_time'] as int? ?? 
                 (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                 (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
    } else {
      timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
    }
    
    String status = video['status'] as String? ?? 'published';
    final publishedAt = video['published_at'] as int?;
    if (status == 'scheduled' && publishedAt != null) {
      status = 'published';
    }
    
    final scheduledTime = video['scheduled_time'] as int?;
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    final hasYouTube = accounts.containsKey('YouTube');
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final timeAgo = _formatTimestampForHome(dateTime);

    // SOCIAL MEDIA: platforms
    List<String> platforms;
    if (isNewFormat && video['accounts'] is Map) {
      platforms = (video['accounts'] as Map).keys.map((e) => e.toString()).toList();
    } else {
      platforms = List<String>.from(video['platforms'] ?? []);
    }

    // NUMERO ACCOUNT
    int accountCount = _countTotalAccountsForHome(video, isNewFormat);
    final accountText = accountCount > 0 
        ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
        : 'No accounts';

    final wasScheduled = (publishedAt != null && video['scheduled_time'] != null) || 
                        (status == 'scheduled' && hasYouTube && scheduledTime != null);

    // THUMBNAIL
    final videoPath = isNewFormat 
        ? video['media_url'] as String?
        : video['video_path'] as String?;
    final thumbnailPath = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_path'] as String?;
    final thumbnailCloudflareUrl = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_cloudflare_url'] as String?;
    
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.28),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.12),
                blurRadius: isDark ? 22 : 18,
                spreadRadius: isDark ? 0.5 : 0,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.55),
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
                      Colors.white.withOpacity(0.16),
                      Colors.white.withOpacity(0.08),
                    ]
                  : [
                      Colors.white.withOpacity(0.34),
                      Colors.white.withOpacity(0.24),
                    ],
            ),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => (video['status'] as String? ?? 'published') == 'draft'
                      ? DraftDetailsPage(video: video)
                      : VideoDetailsPage(video: video),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 150,
                        height: 110,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (videoPath?.isNotEmpty == true || thumbnailPath?.isNotEmpty == true)
                              _HomeVideoPreviewWidget(
                                videoPath: videoPath,
                                thumbnailPath: thumbnailPath,
                                thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                                width: 150,
                                height: 110,
                                isImage: video['is_image'] == true,
                                videoId: video['id'] as String?,
                                userId: video['user_id'] as String?,
                                status: video['status'] as String? ?? 'published',
                                isNewFormat: isNewFormat,
                              )
                            else
                              Container(
                                color: theme.colorScheme.surfaceVariant,
                                child: Center(
                                  child: Icon(
                                    video['is_image'] == true ? Icons.image : Icons.video_library,
                                    size: 28,
                                    color: theme.iconTheme.color?.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: _buildHomeDurationBadge(video),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Video details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Platform logos row
                        if (platforms.isNotEmpty)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width - 210,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  if (platforms.length <= 4)
                                    ...platforms.map((platform) => Padding(
                                      padding: const EdgeInsets.only(right: 7),
                                      child: _buildHomePlatformLogo(platform.toString()),
                                    ))
                                  else
                                    ...[
                                      ...platforms.take(4).map((platform) => Padding(
                                        padding: const EdgeInsets.only(right: 7),
                                        child: _buildHomePlatformLogo(platform.toString()),
                                      )),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '+${platforms.length - 4}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 15),
                        // Account info
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.people,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                accountText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Timestamp con status badge
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  wasScheduled ? 'Scheduled · $timeAgo' : timeAgo,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _HomeStatusChip(status: video['status'] as String? ?? 'published', wasScheduled: wasScheduled),
                          ],
                        ),
                      ],
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

  // Widget per costruire una card video compatta per il PageView orizzontale
  Widget _buildCompactVideoCard(ThemeData theme, Map<String, dynamic> video) {
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);

    int timestamp;
    if (isNewFormat) {
      timestamp = video['scheduled_time'] as int? ?? 
                 (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                 (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
    } else {
      timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
    }
    
    String status = video['status'] as String? ?? 'published';
    final publishedAt = video['published_at'] as int?;
    if (status == 'scheduled' && publishedAt != null) {
      status = 'published';
    }
    
    final scheduledTime = video['scheduled_time'] as int?;
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    final hasYouTube = accounts.containsKey('YouTube');
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final timeAgo = _formatTimestampForHome(dateTime);

    List<String> platforms;
    if (isNewFormat && video['accounts'] is Map) {
      platforms = (video['accounts'] as Map).keys.map((e) => e.toString()).toList();
    } else {
      platforms = List<String>.from(video['platforms'] ?? []);
    }

    int accountCount = _countTotalAccountsForHome(video, isNewFormat);
    final wasScheduled = (publishedAt != null && video['scheduled_time'] != null) || 
                        (status == 'scheduled' && hasYouTube && scheduledTime != null);

    final videoPath = isNewFormat 
        ? video['media_url'] as String?
        : video['video_path'] as String?;
    final thumbnailPath = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_path'] as String?;
    final thumbnailCloudflareUrl = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_cloudflare_url'] as String?;
    
    final isDark = theme.brightness == Brightness.dark;
    final title = video['title'] as String? ?? 'Untitled';
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.28),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MultiVideoInsightsPage(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  // Thumbnail compatta
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 100,
                        height: 120,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (videoPath?.isNotEmpty == true || thumbnailPath?.isNotEmpty == true)
                              _HomeVideoPreviewWidget(
                                videoPath: videoPath,
                                thumbnailPath: thumbnailPath,
                                thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                                width: 100,
                                height: 120,
                                isImage: video['is_image'] == true,
                                videoId: video['id'] as String?,
                                userId: video['user_id'] as String?,
                                status: video['status'] as String? ?? 'published',
                                isNewFormat: isNewFormat,
                              )
                            else
                              Container(
                                color: Colors.grey[300],
                                child: Icon(Icons.videocam_off, color: Colors.grey[600], size: 32),
                              ),
                            // Badge durata (gestisce caroselli, immagini e video)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: _buildHomeDurationBadge(video),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info compatta - impilate verticalmente
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Piattaforme (max 3 loghi + eventuale badge "+N")
                        if (platforms.isNotEmpty)
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              ...platforms.take(3).map((platform) => 
                                _buildHomePlatformLogo(platform)
                              ),
                              if (platforms.length > 3)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '+${platforms.length - 3}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        // Numero account
                        Row(
                          children: [
                            Icon(
                              Icons.account_circle_outlined,
                              size: 14,
                              color: isDark ? Colors.white.withOpacity(0.7) : Colors.black87.withOpacity(0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white.withOpacity(0.7) : Colors.black87.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Data
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            wasScheduled ? 'Scheduled · $timeAgo' : timeAgo,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Badge status
                        _HomeStatusChip(
                          status: video['status'] as String? ?? 'published',
                          wasScheduled: wasScheduled,
                        ),
                      ],
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

  // Helper methods per la home
  Widget _buildHomePlatformLogo(String platform) {
    String logoPath;
    double size = 24;
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'tiktok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
      case 'instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'threads':
        logoPath = 'assets/loghi/threads_logo.png';
        break;
      default:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.public,
            size: 14,
            color: Colors.grey,
          ),
        );
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        logoPath,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.public,
              size: 14,
              color: Colors.grey,
            ),
          );
        },
      ),
    );
  }

  // Nuovo metodo per mostrare la durata in modo statico
  Widget _buildHomeDurationBadge(Map<String, dynamic> video) {
    // Controlla se è un carosello (ha cloudflare_urls con più di una voce)
    final cloudflareUrls = video['cloudflare_urls'];
    bool isCarousel = false;
    
    if (cloudflareUrls != null) {
      if (cloudflareUrls is List) {
        isCarousel = (cloudflareUrls as List).length > 1;
      } else if (cloudflareUrls is Map) {
        isCarousel = (cloudflareUrls as Map).length > 1;
      } else if (cloudflareUrls is Map<dynamic, dynamic>) {
        // Gestione esplicita per Map<dynamic, dynamic> da Firebase
        isCarousel = cloudflareUrls.length > 1;
      }
    }
    
    // Se è un carosello, mostra "CAROUSEL"
    if (isCarousel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'CAROUSEL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    // Se è un'immagine, mostra "IMG"
    if (video['is_image'] == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'IMG',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    // Per i video, usa la vera durata dal database se disponibile
    String duration;
    
    // Controlla se abbiamo i dati della durata dal database
    final durationSeconds = video['video_duration_seconds'] as int?;
    final durationMinutes = video['video_duration_minutes'] as int?;
    final durationRemainingSeconds = video['video_duration_remaining_seconds'] as int?;
    
    if (durationSeconds != null && durationMinutes != null && durationRemainingSeconds != null) {
      // Usa i dati reali dal database
      duration = '$durationMinutes:${durationRemainingSeconds.toString().padLeft(2, '0')}';
    } else {
      // Fallback: usa una durata basata sull'ID del video (per compatibilità con video esistenti)
      final idString = video['id'] as String? ?? '';
      final hashCode = idString.hashCode.abs() % 300 + 30; // tra 30 e 329 secondi
      final minutes = hashCode ~/ 60;
      final seconds = hashCode % 60;
      
      duration = '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        duration,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatTimestampForHome(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    
    if (difference.inDays > 1) {
      return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}';
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

  int _countTotalAccountsForHome(Map<String, dynamic> video, bool isNewFormat) {
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    int totalCount = 0;
    
    if (accounts.isEmpty) return 0;
    
    if (isNewFormat) {
      accounts.forEach((platform, accountData) {
        if (accountData is Map) {
          totalCount += 1;
        } else if (accountData is List) {
          totalCount += accountData.length;
        } else if (accountData != null) {
          totalCount += 1;
        }
      });
    } else {
      accounts.forEach((platform, platformAccounts) {
        if (platformAccounts is List) {
          totalCount += platformAccounts.length;
        } else if (platformAccounts is Map) {
          totalCount += platformAccounts.length;
        } else if (platformAccounts != null) {
          totalCount += 1;
        }
      });
    }
    
    return totalCount;
  }


} 

// Widget per il preview video nella home
class _HomeVideoPreviewWidget extends StatefulWidget {
  final String? videoPath;
  final String? thumbnailPath;
  final String? thumbnailCloudflareUrl;
  final double width;
  final double height;
  final bool isImage;
  final String? videoId;
  final String? userId;
  final String status;
  final bool isNewFormat;

  const _HomeVideoPreviewWidget({
    required this.videoPath,
    this.thumbnailPath,
    this.thumbnailCloudflareUrl,
    required this.width,
    required this.height,
    this.isImage = false,
    this.videoId,
    this.userId,
    required this.status,
    required this.isNewFormat,
  });

  @override
  State<_HomeVideoPreviewWidget> createState() => _HomeVideoPreviewWidgetState();
}

class _HomeVideoPreviewWidgetState extends State<_HomeVideoPreviewWidget> {
  String? _firebaseThumbnailUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.status == 'published' && widget.videoId != null && widget.userId != null && !widget.isNewFormat) {
      _loadThumbnailFromFirebase();
    } else if (widget.isNewFormat) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadThumbnailFromFirebase() async {
    try {
      final database = FirebaseDatabase.instance.ref();
      final thumbnailRef = database
          .child('users')
          .child('users')
          .child(widget.userId!)
          .child('videos')
          .child(widget.videoId!)
          .child('thumbnail_cloudflare_url');
      
      final snapshot = await thumbnailRef.get();
      if (snapshot.exists && mounted) {
        final thumbnailUrl = snapshot.value as String?;
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
          setState(() {
            _firebaseThumbnailUrl = thumbnailUrl;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildThumbnail() {
    if (widget.isNewFormat) {
      if (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
        return _buildNetworkImage(widget.thumbnailPath!);
      } else if (widget.videoPath != null && widget.videoPath!.isNotEmpty) {
        return _buildNetworkImage(widget.videoPath!, isVideo: true);
      } else {
        return _buildPlaceholder();
      }
    }
    
    bool isVideoUrl = widget.videoPath != null && 
                      (widget.videoPath!.startsWith('http://') || 
                       widget.videoPath!.startsWith('https://'));
    
    bool isThumbnailUrl = widget.thumbnailPath != null && 
                          (widget.thumbnailPath!.startsWith('http://') || 
                           widget.thumbnailPath!.startsWith('https://'));
    
    bool isCloudflareUrl = widget.thumbnailCloudflareUrl != null && 
                           widget.thumbnailCloudflareUrl!.isNotEmpty &&
                           (widget.thumbnailCloudflareUrl!.startsWith('http://') || 
                            widget.thumbnailCloudflareUrl!.startsWith('https://'));
    
    bool isFirebaseThumbnailUrl = _firebaseThumbnailUrl != null && 
                                 _firebaseThumbnailUrl!.isNotEmpty &&
                                 (widget.status == 'published') &&
                                 !widget.isNewFormat;
    
    if (widget.isImage) {
      if (widget.isNewFormat && widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
        return _buildNetworkImage(widget.thumbnailPath!);
      }
      
      if (isFirebaseThumbnailUrl) {
        return _buildNetworkImage(_firebaseThumbnailUrl!);
      } else if (isVideoUrl) {
        return _buildNetworkImage(widget.videoPath!);
      } else if (isThumbnailUrl) {
        return _buildNetworkImage(widget.thumbnailPath!);
      } else if (isCloudflareUrl) {
        return _buildNetworkImage(widget.thumbnailCloudflareUrl!);
      }
      
      if (widget.videoPath != null && widget.videoPath!.isNotEmpty) {
        final file = File(widget.videoPath!);
        return FutureBuilder<bool>(
          future: file.exists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingPlaceholder();
            }
            final exists = snapshot.data ?? false;
            if (exists) {
              return _buildFileImage(file);
            } else {
              return _buildPlaceholder();
            }
          },
        );
      }
      return _buildPlaceholder();
    }
    
    if (widget.isNewFormat && widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
      return _buildNetworkImage(widget.thumbnailPath!);
    }
    
    if (isFirebaseThumbnailUrl) {
      return _buildNetworkImage(_firebaseThumbnailUrl!);
    }
    
    if (isCloudflareUrl) {
      return _buildNetworkImage(widget.thumbnailCloudflareUrl!);
    } else if (isThumbnailUrl) {
      return _buildNetworkImage(widget.thumbnailPath!);
    }
    
    if (isVideoUrl) {
      return _buildNetworkImage(widget.videoPath!, isVideo: true);
    }
    
    if (widget.thumbnailPath != null && widget.thumbnailPath!.isNotEmpty) {
      final file = File(widget.thumbnailPath!);
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingPlaceholder();
          }
          final exists = snapshot.data ?? false;
          if (exists) {
            return _buildFileImage(file);
          } else {
            return _buildPlaceholder();
          }
        },
      );
    }
    
    return _buildPlaceholder();
  }
  
  Widget _buildNetworkImage(String url, {bool isVideo = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildPlaceholder(isVideo: isVideo);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildLoadingPlaceholder();
            },
          ),
          if (isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFileImage(File file) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
      ),
    );
  }
  
  Widget _buildLoadingPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPlaceholder({bool isVideo = false}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceVariant,
        child: Center(
          child: Icon(
            widget.isImage ? Icons.image : (isVideo ? Icons.play_circle_outline : Icons.video_library),
            color: theme.iconTheme.color?.withOpacity(0.5),
            size: 32,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && widget.status == 'published' && widget.videoId != null && widget.userId != null && !widget.isNewFormat) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: _buildLoadingPlaceholder(),
      );
    }
    
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _buildThumbnail(),
    );
  }
}

// Status chip per la home
class _HomeStatusChip extends StatelessWidget {
  final String status;
  final bool wasScheduled;

  const _HomeStatusChip({required this.status, this.wasScheduled = false});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'published':
        backgroundColor = wasScheduled ? const Color(0xFF34C759).withOpacity(0.9) : const Color(0xFF34C759);
        textColor = Colors.white;
        icon = wasScheduled ? Icons.schedule_send : Icons.check_circle;
        label = wasScheduled ? 'SCHEDULED' : 'PUBLISHED';
        break;
      case 'scheduled':
        backgroundColor = const Color(0xFF34C759).withOpacity(0.9);
        textColor = Colors.white;
        icon = Icons.schedule_send;
        label = 'SCHEDULED';
        break;
      case 'processing':
        backgroundColor = const Color(0xFFFF9500);
        textColor = Colors.white;
        icon = Icons.pending;
        label = 'PROCESSING';
        break;
      case 'draft':
        backgroundColor = const Color(0xFF007AFF);
        textColor = Colors.white;
        icon = Icons.edit;
        label = 'DRAFT';
        break;
      case 'failed':
        backgroundColor = const Color(0xFFFF3B30);
        textColor = Colors.white;
        icon = Icons.error;
        label = 'FAILED';
        break;
      default:
        backgroundColor = Colors.grey;
        textColor = Colors.white;
        icon = Icons.help;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 8,
            color: textColor,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
} 

class _UpgradePopupDialog extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onUpgrade;
  const _UpgradePopupDialog({required this.onClose, required this.onUpgrade});

  @override
  State<_UpgradePopupDialog> createState() => _UpgradePopupDialogState();
}

class _UpgradePopupDialogState extends State<_UpgradePopupDialog> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _showClose = false;
  bool _showButton = false;
  bool _isVideoReady = false;
  bool _hasError = false;
  late AnimationController _animationController;
  late Animation<Offset> _offsetAnimation;
  late AnimationController _closeAnimationController;
  late AnimationController _buttonAnimationController;
  late Animation<double> _closeAnimation;
  late Animation<Offset> _buttonSlideAnimation;
  late Animation<double> _buttonFadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    
    // Show close button after 8 seconds
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _showClose = true);
        _closeAnimationController.forward();
      }
    });
    // Show button after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() => _showButton = true);
        _buttonAnimationController.forward();
      }
    });
    // Main slide animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    // Close button animation
    _closeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _closeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _closeAnimationController,
      curve: Curves.easeOutBack,
    ));
    // Button animation: slow, fade in + slide up
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _buttonSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _buttonAnimationController,
      curve: Curves.easeOutCubic,
    ));
    _buttonFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeIn,
      ),
    );
    _animationController.forward();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.asset('assets/unwatermark_adsAFTERUPLOAD.mp4');
      
      // Aggiungi listener per gestire errori e stato del video
      _controller!.addListener(() {
        if (mounted) {
          // Controlla se il video è pronto
          if (_controller!.value.isInitialized && !_isVideoReady) {
            setState(() {
              _isVideoReady = true;
            });
          }
          
          // Controlla se il video è finito
          if (_controller!.value.position >= _controller!.value.duration) {
            _controller!.pause();
          }
          
          // Controlla errori
          if (_controller!.value.hasError) {
            setState(() {
              _hasError = true;
            });
          }
        }
      });

      // Inizializza il video con gestione errori
      await _controller!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (mounted) {
            setState(() {
              _hasError = true;
            });
          }
          throw TimeoutException('Video initialization timeout');
        },
      );

      if (mounted && !_hasError) {
        setState(() {
          _isVideoReady = true;
        });
        
        // Imposta il video per non loopare
        _controller!.setLooping(false);
        
        // Avvia la riproduzione solo se il widget è ancora montato
        if (mounted) {
          await _controller!.play();
        }
      }
    } catch (e) {
      print('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _animationController.dispose();
    _closeAnimationController.dispose();
    _buttonAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.black.withOpacity(0.85),
      child: Stack(
        children: [
          SlideTransition(
            position: _offsetAnimation,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  // NIENTE borderRadius qui!
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: _buildVideoContent(),
                      ),
                    ),
                    // Button section con animazione fade + slide
                    if (_showButton)
                      FadeTransition(
                        opacity: _buttonFadeAnimation,
                        child: SlideTransition(
                          position: _buttonSlideAnimation,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                            child: Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF667eea), // Blu violaceo
                                    Color(0xFF764ba2), // Viola
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  transform: GradientRotation(135 * 3.14159 / 180),
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: widget.onUpgrade,
                                  child: Center(
                                    child: Text(
                                      'Try for Free',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
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
          ),
          if (_showClose)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 24,
              child: ScaleTransition(
                scale: _closeAnimation,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoContent() {
    // Se c'è un errore, mostra un fallback
    if (_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Video not available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wait a few seconds and press the "x".',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      );
    }

    // Se il video non è pronto, mostra il loading
    if (!_isVideoReady || _controller == null) {
      return Center(
        child: Lottie.asset(
          'assets/animations/MainScene.json',
          width: 100,
          height: 100,
          fit: BoxFit.contain,
        ),
      );
    }

    // Se il video è pronto, controlla che sia effettivamente inizializzato
    if (!_controller!.value.isInitialized) {
      return Center(
        child: Lottie.asset(
          'assets/animations/MainScene.json',
          width: 100,
          height: 100,
          fit: BoxFit.contain,
        ),
      );
    }

    // Video pronto e inizializzato
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}

class TypingTextWidget extends StatelessWidget {
  final String text;
  final Animation<double> animation;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final bool isCompleted;

  const TypingTextWidget({
    Key? key,
    required this.text,
    required this.animation,
    this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.isCompleted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If animation is already completed, show full text immediately
    if (isCompleted) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final visibleLength = (text.length * animation.value).round();
        final visibleText = text.substring(0, visibleLength.clamp(0, text.length));
        
        return Text(
          visibleText,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
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

