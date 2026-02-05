import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'video_details_page.dart';
import 'video_stats_page.dart';
import 'upgrade_premium_page.dart';
import 'history_page.dart';
import 'credits_page.dart';

// Servizio ChatGPT per analizzare i video comparati
class MultiVideoChatGptService {
  static const String apiKey = '';
  static const String apiUrl = 'https://api.openai.com/v1/chat/completions';

  Future<String> analyzeMultiVideoStats(
    List<Map<String, dynamic>?> videos,
    List<Map<String, double>?> statsData,
    String language,
    [String? customPrompt,
     String? analysisType = 'initial']
  ) async {
    try {
      String prompt;
      if (customPrompt != null && analysisType == 'chat') {
        // Per le chat, usa il customPrompt come domanda dell'utente e aggiungi il contesto
        prompt = _buildChatPrompt(videos, statsData, language, customPrompt);
      } else {
        prompt = _buildPrompt(videos, statsData, language);
      }
      
      // Calcola una stima dei token usati dal prompt (input)
      final int promptTokens = _calculateTokens(prompt);
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final completion = data['choices'][0]['message']['content'] as String? ?? '';
        
        // Calcola una stima dei token usati dalla risposta (output)
        final int completionTokens = _calculateTokens(completion);
        final int totalTokens = promptTokens + completionTokens;

        // Sottrai crediti per utenti non premium in base ai token usati
        await _subtractCreditsForTokens(totalTokens);
        
        print('[AI] ✅ Analisi multi-video completata');
        return completion;
      } else {
        throw Exception('Failed to get AI analysis: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error analyzing multi-video stats: $e');
    }
  }

  /// Stima dei token usati da un testo.
  /// Approssimazione: ~1 token ogni 4 caratteri (come in video_stats_page.dart).
  int _calculateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  /// Sottrae crediti all'utente NON premium in base ai token usati.
  /// Costo: 0.05 crediti per token (input + output), arrotondato per eccesso.
  Future<void> _subtractCreditsForTokens(int totalTokens) async {
    try {
      if (totalTokens <= 0) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final db = FirebaseDatabase.instance.ref().child('users').child('users').child(user.uid);

      // Controlla se l'utente è premium: gli utenti premium non pagano token
      final premiumSnap = await db.child('isPremium').get();
      final bool isPremium = (premiumSnap.value as bool?) ?? false;
      if (isPremium) return;

      // Leggi i crediti attuali
      final creditsSnap = await db.child('credits').get();
      int currentCredits = 0;
      if (creditsSnap.exists && creditsSnap.value != null) {
        final val = creditsSnap.value;
        if (val is int) {
          currentCredits = val;
        } else if (val is String) {
          currentCredits = int.tryParse(val) ?? 0;
        }
      }

      // Costo: 0.05 crediti per token ⇒ tokens / 20, arrotondato per eccesso
      final int creditsToSubtract = max(1, (totalTokens * 0.04).ceil());
      int newCredits = currentCredits - creditsToSubtract;
      if (newCredits < 0) newCredits = 0;

      await db.child('credits').set(newCredits);

      print('[AI MULTI] 💳 Token usati: $totalTokens → -$creditsToSubtract crediti (da $currentCredits a $newCredits)');
    } catch (e) {
      // Non bloccare l'analisi se il salvataggio crediti fallisce
      print('[AI MULTI] ⚠️ Errore nella sottrazione crediti per token: $e');
    }
  }

  String _buildPrompt(
    List<Map<String, dynamic>?> videos,
    List<Map<String, double>?> statsData,
    String language,
  ) {
    String prompt = '''
IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".

CRITICAL INFORMATION ABOUT VIEWS DATA:
- For Instagram and Facebook platforms, view counts are NOT available through their APIs. 
- When views data is missing or zero for Instagram/Facebook videos, you should estimate views based on the account's historical performance patterns, using likes and comments as indicators.
- Use the following estimation approach: analyze the like-to-view and comment-to-view ratios typical for that account/platform, then estimate views based on the provided likes and comments data.
- If views are provided, use them directly. If views are 0 or missing for Instagram/Facebook, make an educated estimate based on likes and comments.

Objective: Analyze and compare the performance of multiple videos using the data provided (likes, views, comments), identifying patterns, strengths, weaknesses, and opportunities for improvement.

Don't give generic advice: evaluate the data analytically, identifying patterns, anomalies, weaknesses, and strengths. Compare content, timing, and performance metrics. Focus on the actual effectiveness of the videos, deducing what works and what doesn't.

Follow this precise structure:

VIDEO COMPARISON OVERVIEW:
Provide a concise summary comparing all videos, highlighting which performed best overall and why.

PERFORMANCE ANALYSIS:
Compare likes, views, and comments across all videos. Identify which video has the best engagement rate, highest reach, and most interactions.

STRENGTHS IDENTIFICATION:
Evaluate the strengths of each video based on actual engagement data (like/view ratio, comment/view ratio, etc.). Highlight what makes the best-performing video successful.

WEAKNESSES IDENTIFICATION:
Identify specific weaknesses: where traffic is lost, what does not generate interactions, differences between similar videos.

IMPROVEMENT STRATEGIES:
Suggest concrete and specific improvements for each video: what to change in content, style, timing, or format based on the comparison.

FUTURE RECOMMENDATIONS:
Propose precise future content strategies based on the comparison data (e.g., "Video 1's format at 6-8 PM brings twice as many comments as Video 2's format at other times").

BONUS TIPS:
Indicate at least one little-known trick to improve visibility, relevant to the best-performing video's characteristics.

IMPORTANT:

DO NOT start with introductory phrases such as "Here is the analysis"
DO NOT include generic comments such as "consistency is important" or "use relevant hashtags"
Write in short paragraphs, visually separated for easy reading
Use bullet points where useful
Structure your response with clear section headers in CAPS (e.g., "VIDEO COMPARISON OVERVIEW:", "PERFORMANCE ANALYSIS:")

End with: "Note: This AI analysis is based on available data and trends. Results may vary based on algorithm changes and other factors."

IMPORTANT: After your analysis, provide exactly 3 follow-up questions that users might want to ask about this comparison. Format them as:
SUGGESTED_QUESTIONS:
1. [First question]
2. [Second question] 
3. [Third question]

These questions should be relevant to the analysis and help users dive deeper into specific aspects.
''';
    
    // Aggiungi i dati dei video
    prompt += '\n\nVideo Comparison Data:';
    for (int i = 0; i < videos.length; i++) {
      final video = videos[i];
      final stats = statsData[i];
      if (video == null || stats == null) continue;
      
      prompt += '\n\nVideo ${i + 1}:';
      prompt += '\nTitle: ${video['title'] ?? 'Untitled'}';
      
      final int ts = (video['published_at'] as int?) ?? (video['timestamp'] as int? ?? 0);
      if (ts > 0) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        prompt += '\nPublished: ${DateFormat('yyyy-MM-dd HH:mm').format(date)}';
      }
      
      // Estrai le piattaforme
      final videoId = video['id']?.toString();
      final userId = video['user_id']?.toString();
      final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
      
      List<String> platforms = [];
      if (isNewFormat && video['accounts'] is Map) {
        platforms = (video['accounts'] as Map).keys.map((e) => e.toString()).toList();
      } else {
        platforms = List<String>.from(video['platforms'] ?? []);
      }
      prompt += '\nPlatforms: ${platforms.join(", ")}';
      
      prompt += '\nLikes: ${stats['likes']?.toStringAsFixed(0) ?? '0'}';
      prompt += '\nViews: ${stats['views']?.toStringAsFixed(0) ?? '0'}';
      prompt += '\nComments: ${stats['comments']?.toStringAsFixed(0) ?? '0'}';
      
      // Aggiungi dati degli account
      final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
      if (accounts.isNotEmpty) {
        prompt += '\n\nAccount Details:';
        accounts.forEach((platform, platformAccounts) {
          if (platformAccounts == null) return;
          
          List<Map<dynamic, dynamic>> accountList = [];
          if (platformAccounts is Map) {
            accountList = [platformAccounts];
          } else if (platformAccounts is List) {
            accountList = platformAccounts.whereType<Map>().toList();
          }
          
          for (final account in accountList) {
            final username = (account['account_username'] ?? account['username'] ?? '').toString();
            final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
            final accountId = account['account_id']?.toString() ?? account['id']?.toString() ?? '';
            
            if (accountId.isNotEmpty || username.isNotEmpty) {
              prompt += '\n  - Platform: $platform';
              if (displayName.isNotEmpty) prompt += '\n    Display Name: $displayName';
              if (username.isNotEmpty) prompt += '\n    Username: $username';
              if (accountId.isNotEmpty) prompt += '\n    Account ID: $accountId';
            }
          }
        });
      }
      
      if (stats['views'] != null && stats['views']! > 0) {
        final engagementRate = ((stats['likes'] ?? 0) + (stats['comments'] ?? 0)) / stats['views']! * 100;
        prompt += '\nEngagement Rate: ${engagementRate.toStringAsFixed(2)}%';
      } else if (platforms.any((p) => p.toLowerCase() == 'instagram' || p.toLowerCase() == 'facebook')) {
        prompt += '\nNote: Views not available for Instagram/Facebook - estimate based on likes and comments';
      }
    }
    
    return prompt;
  }

  String _buildChatPrompt(
    List<Map<String, dynamic>?> videos,
    List<Map<String, double>?> statsData,
    String language,
    String userQuestion,
  ) {
    String prompt = '''
IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".

CRITICAL INFORMATION ABOUT VIEWS DATA:
- For Instagram and Facebook platforms, view counts are NOT available through their APIs. 
- When views data is missing or zero for Instagram/Facebook videos, you should estimate views based on the account's historical performance patterns, using likes and comments as indicators.
- Use the following estimation approach: analyze the like-to-view and comment-to-view ratios typical for that account/platform, then estimate views based on the provided likes and comments data.
- If views are provided, use them directly. If views are 0 or missing for Instagram/Facebook, make an educated estimate based on likes and comments.

You are analyzing a comparison of multiple videos. The user has asked: "$userQuestion"

Please provide a detailed, helpful response based on the video comparison data provided. Focus specifically on answering the user's question while using all the available data to support your analysis.

Video Comparison Data:
''';
    
    // Aggiungi i dati dei video
    for (int i = 0; i < videos.length; i++) {
      final video = videos[i];
      final stats = statsData[i];
      if (video == null || stats == null) continue;
      
      prompt += '\n\nVideo ${i + 1}:';
      prompt += '\nTitle: ${video['title'] ?? 'Untitled'}';
      
      final int ts = (video['published_at'] as int?) ?? (video['timestamp'] as int? ?? 0);
      if (ts > 0) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        prompt += '\nPublished: ${DateFormat('yyyy-MM-dd HH:mm').format(date)}';
      }
      
      // Estrai le piattaforme
      final videoId = video['id']?.toString();
      final userId = video['user_id']?.toString();
      final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
      
      List<String> platforms = [];
      if (isNewFormat && video['accounts'] is Map) {
        platforms = (video['accounts'] as Map).keys.map((e) => e.toString()).toList();
      } else {
        platforms = List<String>.from(video['platforms'] ?? []);
      }
      prompt += '\nPlatforms: ${platforms.join(", ")}';
      
      prompt += '\nLikes: ${stats['likes']?.toStringAsFixed(0) ?? '0'}';
      prompt += '\nViews: ${stats['views']?.toStringAsFixed(0) ?? '0'}';
      prompt += '\nComments: ${stats['comments']?.toStringAsFixed(0) ?? '0'}';
      
      // Aggiungi dati degli account
      final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
      if (accounts.isNotEmpty) {
        prompt += '\n\nAccount Details:';
        accounts.forEach((platform, platformAccounts) {
          if (platformAccounts == null) return;
          
          List<Map<dynamic, dynamic>> accountList = [];
          if (platformAccounts is Map) {
            accountList = [platformAccounts];
          } else if (platformAccounts is List) {
            accountList = platformAccounts.whereType<Map>().toList();
          }
          
          for (final account in accountList) {
            final username = (account['account_username'] ?? account['username'] ?? '').toString();
            final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
            final accountId = account['account_id']?.toString() ?? account['id']?.toString() ?? '';
            
            if (accountId.isNotEmpty || username.isNotEmpty) {
              prompt += '\n  - Platform: $platform';
              if (displayName.isNotEmpty) prompt += '\n    Display Name: $displayName';
              if (username.isNotEmpty) prompt += '\n    Username: $username';
              if (accountId.isNotEmpty) prompt += '\n    Account ID: $accountId';
            }
          }
        });
      }
      
      if (stats['views'] != null && stats['views']! > 0) {
        final engagementRate = ((stats['likes'] ?? 0) + (stats['comments'] ?? 0)) / stats['views']! * 100;
        prompt += '\nEngagement Rate: ${engagementRate.toStringAsFixed(2)}%';
      } else if (platforms.any((p) => p.toLowerCase() == 'instagram' || p.toLowerCase() == 'facebook')) {
        prompt += '\nNote: Views not available for Instagram/Facebook - estimate based on likes and comments';
      }
    }
    
    prompt += '\n\nIMPORTANT: After your response, provide exactly 3 follow-up questions that users might want to ask about this comparison. Format them as:';
    prompt += '\nSUGGESTED_QUESTIONS:';
    prompt += '\n1. [First question]';
    prompt += '\n2. [Second question]';
    prompt += '\n3. [Third question]';
    
    return prompt;
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? suggestedQuestions;
  final String id;
  
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    String? id,
    this.suggestedQuestions,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
}

class MultiVideoInsightsPage extends StatefulWidget {
  const MultiVideoInsightsPage({Key? key}) : super(key: key);

  @override
  State<MultiVideoInsightsPage> createState() => _MultiVideoInsightsPageState();
}

class _MultiVideoInsightsPageState extends State<MultiVideoInsightsPage> with SingleTickerProviderStateMixin {
  // Numero massimo di video confrontabili per gli utenti premium
  static const int _maxSlotsTotal = 10;
  static const int _maxFreeSlots = 3;

  final List<Map<String, dynamic>?> _manualSelected =
      List<Map<String, dynamic>?>.filled(_maxSlotsTotal, null, growable: false);

  final List<Color> _slotColors = const [
    Color(0xFF3B82F6), // blue
    Color(0xFFEC4899), // fuchsia
    Color(0xFFF59E0B), // orange
    Color(0xFF10B981), // emerald
    Color(0xFF6366F1), // indigo
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
    Color(0xFFA855F7), // purple
    Color(0xFF22C55E), // lime
    Color(0xFFF97316), // deep orange
  ];
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final VideoStatsService _statsService = VideoStatsService();
  bool _isFetching = false;
  String _fetchError = '';
  StreamSubscription<DatabaseEvent>? _videosSubscription;
  StreamSubscription<DatabaseEvent>? _scheduledSubscription;
  List<Map<String, dynamic>> _cachedPublishedVideos = [];
  Map<DateTime, List<Map<String, dynamic>>> _publishedByDay = {};
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  // Picker UI state: search & filters
  final TextEditingController _pickerSearchController = TextEditingController();
  bool _pickerWeekExpanded = true;
  String _pickerSearchQuery = '';
  final Map<String, bool> _pickerPlatformExpanded = {};
  final List<String> _pickerSelectedPlatforms = [];
  final List<String> _pickerSelectedAccounts = [];
  bool _pickerAccountsFilterActive = false;
  DateTime? _pickerStartDate;
  DateTime? _pickerEndDate;
  bool _pickerDateFilterActive = false;

  // Stato per il fetch sequenziale delle statistiche dei video selezionati
  bool _isStatsRunning = false;
  int _currentStatsIndex = -1;
  int _completedVideosCount = 0; // Contatore per i video completati
  String _statsError = '';
  final List<Map<String, double>?> _videoStats =
      List<Map<String, double>?>.filled(_maxSlotsTotal, null, growable: false); // per ogni slot: likes, views, comments
  
  // Page controllers per scroll orizzontale a scatti
  late PageController _chartsPageController;
  late PageController _topVideosPageController;
  late PageController _topAccountsPageController;
  int _currentChartIndex = 0;
  int _currentTopVideoIndex = 0;
  int _currentTopAccountIndex = 0;
  
  // Stato per le tendine espandibili dei ranking (chiave: 'video_likes', 'video_views', 'video_comments', 'account_likes', 'account_views', 'account_comments')
  final Map<String, bool> _rankingExpanded = {};
  
  // Stato per la visibilità animata del bottone
  bool _showFetchButton = false;
  late AnimationController _buttonAnimationController;
  late Animation<double> _buttonFadeAnimation;
  late Animation<Offset> _buttonSlideAnimation;
  bool _showHeaderHint = true;
  
  // Salva la "firma" dei video selezionati per cui abbiamo già le stats
  List<String?> _lastFetchedVideoIds = List.filled(_maxSlotsTotal, null);
  // Salva gli ID dei video per cui è stata fatta l'analisi IA
  List<String?> _lastAnalyzedVideoIds = List.filled(_maxSlotsTotal, null);
  
  // ChatGPT service e variabili per la chat
  final MultiVideoChatGptService _chatGptService = MultiVideoChatGptService();
  bool _isAnalyzing = false;
  bool _isChatLoading = false;
  String? _lastAnalysis;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _chatScrollController = ScrollController();
  List<ChatMessage> _chatMessages = [];
  final Set<String> _completedAIMessageAnimations = {};
  StateSetter? _sheetStateSetter;
  
  // Variabili per i pulsanti delle risposte IA (feedback e copia)
  Map<int, bool> _aiMessageLikes = {};
  Map<int, bool> _aiMessageDislikes = {};
  ValueNotifier<int> _feedbackUpdateNotifier = ValueNotifier(0);
  
  // Variabili per il feedback interno alla tendina
  String? _feedbackMessage;
  bool _showFeedback = false;
  Timer? _feedbackTimer;

  // Premium e slot visibili
  bool _isPremium = false;
  int _visibleSlots = _maxFreeSlots;
  
  // Variabili per crediti utente
  int _userCredits = 0;
  bool _showInsufficientCreditsSnackbar = false;

  @override
  void initState() {
    super.initState();
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _buttonFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _buttonSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _checkPremiumStatus();
    _loadUserCredits();
    
    // Inizializza i PageController
    _chartsPageController = PageController(viewportFraction: 0.9);
    _topVideosPageController = PageController(viewportFraction: 0.9);
    _topAccountsPageController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _videosSubscription?.cancel();
    _scheduledSubscription?.cancel();
    _pickerSearchController.dispose();
    _buttonAnimationController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _chatScrollController.dispose();
    _chartsPageController.dispose();
    _topVideosPageController.dispose();
    _topAccountsPageController.dispose();
    _feedbackTimer?.cancel();
    _feedbackUpdateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          // Main content area
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                16,
                100,
                16,
                100, // spazio fisso per non sovrapporsi al bottone IA fisso
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, animation) {
                      return SizeTransition(
                        sizeFactor: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ),
                        axisAlignment: -1.0,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: _showHeaderHint
                        ? Column(
                            key: const ValueKey('header_hint_visible'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeaderHint(theme, isDark),
                              const SizedBox(height: 16),
                            ],
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('header_hint_hidden'),
                          ),
                  ),
                  _buildManualCompareCard(theme, isDark),
                  if (!_isStatsRunning && _hasAllStatsCompleted()) ...[
                    const SizedBox(height: 16),
                    _buildChartsCard(theme, isDark),
                  ],
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
      backgroundColor: isDark ? Colors.black : const Color(0xFFF6F7FB),
      // Bottone fisso in basso per l'analisi con IA (sempre presente come in video_stats_page)
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF667eea), // blu violaceo
                Color(0xFF764ba2), // viola
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
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: (_isAnalyzing || _isStatsRunning || !_hasAllStatsCompleted()) ? null : _analyzeWithAI,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  (_isAnalyzing || _isStatsRunning || !_hasAllStatsCompleted()) ? Colors.grey.withOpacity(0.5) : Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Analyze with AI',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
                      Icons.psychology,
                      size: 14,
                      color: const Color(0xFF6C63FF),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI Insights',
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

  Widget _buildHeaderHint(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.30) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.45 : 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Lottie.asset(
            'assets/animations/analizeAI.json',
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Compare likes, views, and comments across your posts and let AI surface patterns, winners, and improvement ideas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot =
            await databaseRef.child('users').child('users').child(user.uid).child('isPremium').get();
        if (mounted) {
          setState(() {
            _isPremium = (snapshot.value as bool?) ?? false;
          });
        }
        print('DEBUG: Premium status (multi_video_insights): $_isPremium');
      }
    } catch (e) {
      print('Error checking premium status: $e');
    }
  }
  
  // Carica i crediti dell'utente
  Future<void> _loadUserCredits() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final creditsRef = databaseRef.child('users').child('users').child(user.uid).child('credits');
        final snapshot = await creditsRef.get();
        int currentCredits = 0;

        if (snapshot.exists && snapshot.value != null) {
          if (snapshot.value is int) {
            currentCredits = snapshot.value as int;
          } else if (snapshot.value is String) {
            currentCredits = int.tryParse(snapshot.value as String) ?? 0;
          }
        }

        if (mounted) {
          setState(() {
            _userCredits = currentCredits;
          });
        }
      }
    } catch (e) {
      // ignore load error
      print('Error loading credits: $e');
    }
  }
  
  // Calcola una stima dei token usati da un testo (stesso metodo del servizio)
  int _calculateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }
  
  // Calcola i token stimati per un messaggio di chat
  int _estimateChatMessageTokens(String userMessage) {
    // Prepara i dati dei video e delle stats per stimare il prompt
    final videos = _manualSelected;
    final stats = _videoStats;
    
    // Stima approssimativa: il prompt base + il messaggio dell'utente
    // Per semplicità, stimiamo che il prompt base sia circa 500 token
    final int basePromptTokens = 500;
    final int userMessageTokens = _calculateTokens(userMessage);
    
    // Stima anche i token della risposta (circa 200 token medi)
    final int estimatedResponseTokens = 200;
    
    return basePromptTokens + userMessageTokens + estimatedResponseTokens;
  }
  
  // Verifica se l'utente ha abbastanza crediti per inviare il messaggio
  Future<bool> _hasEnoughCreditsForMessage(String userMessage) async {
    if (_isPremium) return true;
    
    // Stima i token che verranno usati
    final int estimatedTokens = _estimateChatMessageTokens(userMessage);
    
    // Calcola i crediti necessari: 0.05 per token
    final int creditsNeeded = max(1, (estimatedTokens * 0.05).ceil());
    
    // Verifica se ha abbastanza crediti
    return _userCredits >= creditsNeeded;
  }

  Widget _buildManualCompareCard(ThemeData theme, bool isDark) {
    return _glassCard(
      theme: theme,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            theme: theme,
            icon: null,
            gradientColors: const [Color(0xFF667eea), Color(0xFF764ba2)],
            title: 'Choose Videos to Compare',
            subtitle: 'Pick any videos to visualize and compare',
          ),
          const SizedBox(height: 12),
          _buildAutoLastThreeButton(theme, isDark),
          const SizedBox(height: 8),
          _manualChooserRow(theme, isDark),
          const SizedBox(height: 10),
          _buildStartCompareButton(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildChartsCard(ThemeData theme, bool isDark) {
    // Mostra grafici solo dopo che tutte le chiamate API sono completate
    if (!_isStatsRunning && _hasAllStatsCompleted()) {
      return _glassCard(
        theme: theme,
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              theme: theme,
              icon: null,
              gradientColors: const [Color(0xFF667eea), Color(0xFF764ba2)],
              title: 'Comparison Charts',
              subtitle: 'Visualize and compare video metrics',
            ),
          const SizedBox(height: 14),
          _placeholderCombinedChart(theme, isDark),
            const SizedBox(height: 24),
            // Top Videos Rankings
            _buildRankingsSection(
              theme: theme,
              isDark: isDark,
              title: 'Top Posts',
              isVideoRanking: true,
            ),
            const SizedBox(height: 24),
            // Top Accounts Rankings
            _buildRankingsSection(
              theme: theme,
              isDark: isDark,
              title: 'Top Accounts',
              isVideoRanking: false,
            ),
        ],
      ),
    );
    }
    return const SizedBox.shrink();
  }

  Widget _glassCard({
    required ThemeData theme,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.45 : 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.6),
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
                  Colors.white.withOpacity(0.08),
                ]
              : [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.85),
                ],
        ),
      ),
      child: child,
    );
  }

  Widget _sectionHeader({
    required ThemeData theme,
    IconData? icon,
    required List<Color> gradientColors,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manualChooserRow(ThemeData theme, bool isDark) {
    final List<Widget> items = [];

    for (int index = 0; index < _visibleSlots; index++) {
        final selected = _manualSelected[index];
        String? selectedDateText;
        if (selected != null) {
          final int ts = (selected['published_at'] as int?) ?? (selected['timestamp'] as int? ?? 0);
          if (ts > 0) {
          selectedDateText = DateFormat('EEE, MMM d').format(
            DateTime.fromMillisecondsSinceEpoch(ts),
          );
          }
        }

      items.add(
        SizedBox(
          width: 170,
          child: InkWell(
            onTap: () => _openVideoPicker(index),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected == null
                    ? (isDark ? Colors.white.withOpacity(0.08) : Colors.white)
                    : _slotColors[index].withOpacity(isDark ? 0.25 : 0.18),
                border: Border.all(
                  color: selected == null
                      ? (isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.06))
                      : _slotColors[index].withOpacity(0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.45 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected == null
                          ? (isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFF0F2F7))
                          : Colors.white,
                    ),
                    child: Icon(
                      selected == null ? Icons.add_rounded : Icons.check_rounded,
                      color: selected == null ? theme.colorScheme.primary : _slotColors[index],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selected == null ? 'Select video' : (selectedDateText ?? 'Selected'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected == null ? null : _slotColors[index],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selected == null ? 'Tap to choose' : 'Selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: selected == null
                          ? theme.textTheme.bodySmall?.color?.withOpacity(0.7)
                          : _slotColors[index].withOpacity(0.85),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        );
    }

    // Card per aggiungere nuovi slot (sempre visibile finché non si raggiunge il limite massimo assoluto)
    // Per i non premium, il tap oltre i 3 slot mostra la tendina di upgrade.
    if (_visibleSlots < _maxSlotsTotal) {
      items.add(
        SizedBox(
          width: 170,
          child: InkWell(
            onTap: () {
              if (!_isPremium && _visibleSlots >= _maxFreeSlots) {
                _showUpgradeForMoreVideosBottomSheet();
                return;
              }
              if (_visibleSlots >= _maxSlotsTotal) return;
              setState(() {
                _visibleSlots++;
              });
              // Apri subito il picker per il nuovo slot
              _openVideoPicker(_visibleSlots - 1);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.45 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFF0F2F7),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isPremium ? 'Add video' : 'Select video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isPremium ? 'Tap to add slot' : 'Tap to choose',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemBuilder: (context, index) => items[index],
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }

  Widget _buildStartCompareButton(ThemeData theme, bool isDark) {
    final bool hasAtLeastOneSelection = _manualSelected.any((v) => v != null);
    
    if (!_showFetchButton) {
      return const SizedBox.shrink();
    }
    
    return FadeTransition(
      opacity: _buttonFadeAnimation,
      child: SlideTransition(
        position: _buttonSlideAnimation,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
      width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (!_isStatsRunning && hasAtLeastOneSelection) ? _runSequentialStatsFetch : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      // Effetto vetro opaco
                      color: isDark 
                          ? Colors.white.withOpacity(0.15) 
                          : Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
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
                      children: [
                        _isStatsRunning
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              )
                            : (!_isStatsRunning && hasAtLeastOneSelection)
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
                                      Icons.play_arrow_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    Icons.play_arrow_rounded,
                                    size: 20,
                                    color: isDark ? Colors.white.withOpacity(0.5) : Colors.black87.withOpacity(0.5),
                                  ),
                        const SizedBox(width: 8),
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
          _isStatsRunning
              ? (_currentStatsIndex >= 0 ? 'Fetching stats for video ${_getCurrentVideoProgressNumber()} of ${_getSelectedVideosCount()}...' : 'Fetching stats...')
              : 'Fetch stats for selected videos',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
                              color: (!_isStatsRunning && hasAtLeastOneSelection)
                                  ? Colors.white
                                  : (isDark ? Colors.white.withOpacity(0.5) : Colors.black87.withOpacity(0.5)),
                            ),
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
            // Barra di progresso minimal sotto il bottone
            if (_isStatsRunning) ...[
              const SizedBox(height: 12),
              _buildProgressBar(theme, isDark),
            ],
          ],
        ),
      ),
    );
  }

  /// Barra di progresso minimal per mostrare il completamento delle chiamate API
  Widget _buildProgressBar(ThemeData theme, bool isDark) {
    final int totalVideos = _getSelectedVideosCount();
    final double progress = totalVideos > 0 ? _completedVideosCount / totalVideos : 0.0;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            // Barra di background
            Container(
              width: double.infinity,
              height: 3,
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Barra di progresso con gradiente
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottone che, se nessun video è selezionato, propone di analizzare automaticamente
  /// gli ultimi 3 video pubblicati dall'utente.
  Widget _buildAutoLastThreeButton(ThemeData theme, bool isDark) {
    final bool hasSelection = _manualSelected.any((v) => v != null);

    // Visibile solo se nessun video è selezionato
    if (hasSelection) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: const SizedBox.shrink(),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          axisAlignment: -1.0,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: SizedBox(
        key: const ValueKey('auto_last_three_button'),
        width: double.infinity,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _isStatsRunning ? null : _autoSelectLastThreeAndAnalyze,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    // Effetto glass opaco minimal
                    color: isDark
                        ? Colors.white.withOpacity(0.10)
                        : Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.20)
                          : Colors.white.withOpacity(0.40),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withOpacity(0.35)
                            : Colors.black.withOpacity(0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icona con leggero accento viola
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF667eea).withOpacity(0.12),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          size: 16,
                          color: Color(0xFF667eea),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Testo con gradiente viola solo sulla scritta principale
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
                        child: const Text(
                          'Auto-analyze last 3 videos',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                            color: Colors.white,
                          ),
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
    );
  }

  /// Seleziona automaticamente gli ultimi 3 video pubblicati dall'utente
  /// (in base a `published_at` / `timestamp`), li inserisce nei primi 3 slot
  /// e lancia subito il fetch delle statistiche.
  Future<void> _autoSelectLastThreeAndAnalyze() async {
    if (_cachedPublishedVideos.isEmpty) {
      await _fetchPublishedVideos();
    }
    if (!mounted) return;
    if (_cachedPublishedVideos.length < 3) {
      // Mostra un messaggio chiaro se l'utente non ha almeno 3 video pubblicati
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need at least 3 published videos to use quick analysis.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Ordina i video per data decrescente (più recenti per primi)
    final List<Map<String, dynamic>> sorted =
        List<Map<String, dynamic>>.from(_cachedPublishedVideos);
    sorted.sort((a, b) {
      final int tsA = (a['published_at'] as int?) ?? (a['timestamp'] as int? ?? 0);
      final int tsB = (b['published_at'] as int?) ?? (b['timestamp'] as int? ?? 0);
      return tsB.compareTo(tsA);
    });

    // Prendi i primi 3
    final top3 = sorted.take(3).toList();

    setState(() {
      for (int i = 0; i < _maxSlotsTotal; i++) {
        _manualSelected[i] = null;
        _videoStats[i] = null;
        _lastFetchedVideoIds[i] = null;
      }
      for (int i = 0; i < 3; i++) {
        _manualSelected[i] = Map<String, dynamic>.from(top3[i]);
      }
      // Assicura che almeno i primi 3 slot siano visibili
      if (_visibleSlots < 3) {
        _visibleSlots = 3;
      }
    });

    // Aggiorna la visibilità del bottone
    _updateFetchButtonVisibility();
    
    await _runSequentialStatsFetch();
  }

  Widget _tripleMetricLegend(ThemeData theme, bool isDark) {
    final labels = List.generate(3, (index) {
      final sel = _manualSelected[index];
      final fallback = 'Video ${index + 1}';
      if (sel == null) return fallback;
      final title = sel['title'] as String? ?? fallback;
      if (title.length <= 14) return title;
      return '${title.substring(0, 13)}…';
    });
    return Row(
      children: [
        _legendItem(theme, isDark, _slotColors[0], labels[0]),
        const SizedBox(width: 12),
        _legendItem(theme, isDark, _slotColors[1], labels[1]),
        const SizedBox(width: 12),
        _legendItem(theme, isDark, _slotColors[2], labels[2]),
      ],
    );
  }

  Widget _legendItem(ThemeData theme, bool isDark, Color color, String label) {
    return Row(
      children: [
        _metricDot(color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _metricDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _placeholderCombinedChart(ThemeData theme, bool isDark) {
    final bool hasAnyStats = _videoStats.any((v) => v != null);
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF3F6FC),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: hasAnyStats
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comparison charts',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: PageView.builder(
                      controller: _chartsPageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentChartIndex = index;
                        });
                      },
                      itemCount: 3,
                      itemBuilder: (context, index) {
                        final metrics = [
                          {'label': 'Likes', 'key': 'likes', 'color': const Color(0xFF10B981)},
                          {'label': 'Views', 'key': 'views', 'color': const Color(0xFF3B82F6)},
                          {'label': 'Comments', 'key': 'comments', 'color': const Color(0xFFF59E0B)},
                        ];
                        return _buildMetricChartCard(
                          theme: theme,
                          isDark: isDark,
                          label: metrics[index]['label'] as String,
                          metricKey: metrics[index]['key'] as String,
                          color: metrics[index]['color'] as Color,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Indicatore di pagina
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      return Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _currentChartIndex
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withOpacity(0.3),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            )
          : Center(
              child: Text(
                'Chart placeholder (Views / Likes / Comments)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ),
    );
  }

  Widget _buildMiniMetricRow(ThemeData theme, String label, double value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
            ),
          ),
        ),
        Text(
          value > 0 ? value.toStringAsFixed(0) : '—',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricChartCard({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required String metricKey,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: _buildMetricBarChart(
        theme: theme,
        isDark: isDark,
        label: label,
        metricKey: metricKey,
        color: color,
      ),
    );
  }

  Widget _buildMetricBarChart({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required String metricKey,
    required Color color,
  }) {
    final int slotCount = _manualSelected.length;
    final List<double> values = List.generate(slotCount, (index) {
      final stats = _videoStats[index];
      if (stats == null) return 0.0;
      final v = stats[metricKey];
      if (v == null) return 0.0;
      return v;
    });

    final double maxValue = values.fold<double>(0, (prev, v) => v > prev ? v : prev);
    if (maxValue <= 0) {
      return Center(
        child: Text(
          'No $label data yet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
          ),
        ),
      );
    }

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < slotCount; i++) {
      final value = values[i];
      final barColor = _slotColors[i];
      if (value <= 0) continue;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              color: barColor,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxValue * 1.05,
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
              ),
            ),
          ],
        ),
      );
    }

    final titles = List.generate(slotCount, (index) {
      final sel = _manualSelected[index];
      final title = (sel != null ? (sel['title'] as String? ?? 'Video ${index + 1}') : '—');
      if (title.length <= 8) return title;
      return '${title.substring(0, 7)}…';
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxValue * 1.1,
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                horizontalInterval: maxValue > 0 ? (maxValue / 4).clamp(1, double.infinity) : 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  strokeWidth: 1,
                ),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: maxValue > 0 ? (maxValue / 4).clamp(1, double.infinity) : 1,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.round().toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: false,
                  ),
                ),
              ),
              barGroups: barGroups,
              barTouchData: BarTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipPadding: const EdgeInsets.all(8),
                  tooltipMargin: 8,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${rod.toY.round()}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
                touchCallback: (FlTouchEvent event, BarTouchResponse? touchResponse) {
                  if (event is FlTapUpEvent && touchResponse != null && touchResponse.spot != null) {
                    final spotIndex = touchResponse.spot!.touchedBarGroupIndex;
                    if (spotIndex >= 0 && spotIndex < _manualSelected.length) {
                      final video = _manualSelected[spotIndex];
                      if (video != null) {
                        HapticFeedback.lightImpact();
                        _showVideoDetailsModal(video, spotIndex);
                      }
                    }
                  }
                  if (event is FlTapDownEvent) {
                    HapticFeedback.lightImpact();
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankingsSection({
    required ThemeData theme,
    required bool isDark,
    required String title,
    required bool isVideoRanking,
  }) {
    // Calcola dinamicamente l'altezza della sezione in base al numero di elementi
    final double sectionHeight = _calculateRankingsSectionHeight(isVideoRanking);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
            decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1F1F1F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Horizontal scrollable rankings for Likes, Views, Comments
        AnimatedSize(
          duration: (_hasExpandedDropdown(isVideoRanking)
                  ? const Duration(milliseconds: 250)
                  : Duration.zero),
          curve: Curves.easeInOut,
          child: SizedBox(
            height: _calculateRankingsSectionHeight(isVideoRanking),
            child: PageView.builder(
              controller: isVideoRanking ? _topVideosPageController : _topAccountsPageController,
              onPageChanged: (index) {
                setState(() {
                  if (isVideoRanking) {
                    _currentTopVideoIndex = index;
                  } else {
                    _currentTopAccountIndex = index;
                  }
                  // Quando si cambia metrica (Likes / Views / Comments),
                  // chiudi istantaneamente tutte le tendine relative a questo blocco
                  // così non rimangono aperte passando orizzontalmente.
                  const metrics = ['likes', 'views', 'comments'];
                  for (final m in metrics) {
                    final key = '${isVideoRanking ? 'video' : 'account'}_$m';
                    _rankingExpanded[key] = false;
                  }
                });
              },
              itemCount: 3,
              itemBuilder: (context, index) {
                final metrics = [
                  {'metric': 'likes', 'label': 'Likes', 'color': const Color(0xFF10B981)},
                  {'metric': 'views', 'label': 'Views', 'color': const Color(0xFF3B82F6)},
                  {'metric': 'comments', 'label': 'Comments', 'color': const Color(0xFFF59E0B)},
                ];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildHorizontalRanking(
                    theme: theme,
                    isDark: isDark,
                    metric: metrics[index]['metric'] as String,
                    label: metrics[index]['label'] as String,
                    color: metrics[index]['color'] as Color,
                    isVideoRanking: isVideoRanking,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  double _calculateRankingsSectionHeight(bool isVideoRanking) {
    const double baseHeight = 260.0; // sufficiente per titolo + top 3 compatti
    const List<String> metrics = ['likes', 'views', 'comments'];
    const double bottomMargin = 20.0;

    // Verifica se ESISTE almeno una metrica (in questo blocco: video o account)
    // che ha più di 3 elementi → cioè ha una tendina "View X more ..."
    bool hasAnyDropdown = false;
    for (final m in metrics) {
      final itemsForMetric =
          isVideoRanking ? _getRankedVideos(m) : _getRankedAccounts(m);
      if (itemsForMetric.length > 3) {
        hasAnyDropdown = true;
        break;
      }
    }

    // Metrica corrente (pagina visibile nel PageView)
    final int pageIndex =
        isVideoRanking ? _currentTopVideoIndex : _currentTopAccountIndex;
    final String metric =
        (pageIndex >= 0 && pageIndex < metrics.length) ? metrics[pageIndex] : 'likes';

    final items =
        isVideoRanking ? _getRankedVideos(metric) : _getRankedAccounts(metric);
    final int totalItems = items.length;

    // Nessuna tendina in nessuna metrica: tutte le card possono rimanere compatte
    if (!hasAnyDropdown) {
      return baseHeight + bottomMargin;
    }

    // Se esiste almeno una tendina in qualche metrica:
    // - per la metrica corrente con 0-3 elementi, alziamo comunque il card di ~50px
    //   così anche il caso "No data available" mantiene proporzioni coerenti.
    const double extraForDropdownWhenEmpty = 32.0;

    if (totalItems <= 3) {
      return baseHeight + bottomMargin + extraForDropdownWhenEmpty;
    }

    // Per la metrica corrente che HA davvero una tendina: altezza diversa se aperta o chiusa
    const double headerHeight = 32.0; // altezza stimata dell'header "View X more..."
    const double maxListHeight = 140.0; // massimo usato nel SizedBox della lista
    final int remaining = totalItems - 3;
    final double listHeight = min(remaining * 64.0, maxListHeight);

    final expansionKey = '${isVideoRanking ? 'video' : 'account'}_$metric';
    final bool isExpanded = _rankingExpanded[expansionKey] ?? false;

    if (!isExpanded) {
      // Tendina chiusa: header visibile, lista nascosta
      return baseHeight + headerHeight + bottomMargin;
    } else {
      // Tendina aperta: header + lista
      return baseHeight + headerHeight + listHeight + bottomMargin;
    }
  }

  /// Ritorna true se, per la metrica corrente (pagina visibile),
  /// la tendina è attualmente espansa.
  bool _hasExpandedDropdown(bool isVideoRanking) {
    const List<String> metrics = ['likes', 'views', 'comments'];
    final int pageIndex =
        isVideoRanking ? _currentTopVideoIndex : _currentTopAccountIndex;
    final String metric =
        (pageIndex >= 0 && pageIndex < metrics.length) ? metrics[pageIndex] : 'likes';
    final items =
        isVideoRanking ? _getRankedVideos(metric) : _getRankedAccounts(metric);

    if (items.length <= 3) return false;

    final expansionKey = '${isVideoRanking ? 'video' : 'account'}_$metric';
    return _rankingExpanded[expansionKey] ?? false;
  }

  /// Apre il bottom sheet di dettaglio video (lo stesso usato per i video)
  /// prendendo il video "migliore" per quell'account in base alla metrica
  /// richiesta (likes / views / comments).
  void _openFirstVideoDetailsForAccount(String accountKey, String metric) {
    Map<String, dynamic>? bestVideo;
    int bestIndex = -1;
    double bestValue = -1;

    for (int i = 0; i < _manualSelected.length; i++) {
      final video = _manualSelected[i];
      final stats = _videoStats[i];
      if (video == null || stats == null || stats[metric] == null) continue;

      final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
      bool belongsToAccount = false;

      accounts.forEach((platform, platformAccounts) {
        if (belongsToAccount || platformAccounts == null) return;
        List<Map<dynamic, dynamic>> accountList = [];
        if (platformAccounts is Map) {
          accountList = [platformAccounts];
        } else if (platformAccounts is List) {
          accountList = platformAccounts.whereType<Map>().toList();
        }
        for (final account in accountList) {
          final id = account['account_id']?.toString() ??
              account['id']?.toString() ??
              account['username']?.toString() ??
              '';
          if (id == accountKey) {
            belongsToAccount = true;
            break;
          }
        }
      });

      if (!belongsToAccount) continue;

      final value = (stats[metric] as num).toDouble();
      if (value > bestValue) {
        bestValue = value;
        bestVideo = video;
        bestIndex = i;
      }
    }

    if (bestVideo != null && bestIndex >= 0) {
      _showVideoDetailsModal(bestVideo!, bestIndex);
    } else {
      // Fallback: se per qualche motivo non troviamo il video, mostriamo il dettaglio account
      _showAccountDetailsModal(accountKey, metric);
    }
  }

  Widget _buildHorizontalRanking({
    required ThemeData theme,
    required bool isDark,
    required String metric,
    required String label,
    required Color color,
    required bool isVideoRanking,
  }) {
    final List<Map<String, dynamic>> rankedItems = isVideoRanking
        ? _getRankedVideos(metric)
        : _getRankedAccounts(metric);

    if (rankedItems.isEmpty) {
      return Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
              border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
          ),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          // Mostra sempre i primi 3 elementi
          ...List.generate(3, (index) {
            final item = index < rankedItems.length ? rankedItems[index] : null;
            final isEmpty = item == null;
            
            // Determina il colore basato sul video nel grafico
            Color? itemColor;
            if (!isEmpty && isVideoRanking) {
              final videoIndex = item!['index'] as int?;
              if (videoIndex != null && videoIndex < _slotColors.length) {
                itemColor = _slotColors[videoIndex];
              }
            } else if (!isEmpty && !isVideoRanking) {
              // Per gli account, trova il primo video che contiene quell'account
              final accountKey = item!['account'] as String?;
              if (accountKey != null) {
                for (int i = 0; i < _manualSelected.length; i++) {
                  final video = _manualSelected[i];
                  if (video != null) {
                    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
                    bool found = false;
                    accounts.forEach((platform, platformAccounts) {
                      if (found) return;
                      if (platformAccounts == null) return;
                      List<Map<dynamic, dynamic>> accountList = [];
                      if (platformAccounts is Map) {
                        accountList = [platformAccounts];
                      } else if (platformAccounts is List) {
                        accountList = platformAccounts.whereType<Map>().toList();
                      }
                      for (final account in accountList) {
                        final accountId = account['account_id']?.toString() ?? 
                                         account['id']?.toString() ?? 
                                         account['username']?.toString() ?? '';
                        if (accountId == accountKey && i < _slotColors.length) {
                          itemColor = _slotColors[i];
                          found = true;
                          return;
                        }
                      }
                    });
                    if (found) break;
                  }
                }
              }
            }
            final finalColor = itemColor ?? color;
            
            return _buildRankingItem(
              item: item,
              index: index,
              isEmpty: isEmpty,
              isVideoRanking: isVideoRanking,
              finalColor: finalColor,
              isDark: isDark,
              metric: metric,
            );
          }),
          // Se ci sono più di 3 elementi, mostra una card espandibile
          if (rankedItems.length > 3) ...[
            const SizedBox(height: 8),
            _buildExpandableRankingCard(
              theme: theme,
              isDark: isDark,
              rankedItems: rankedItems,
              isVideoRanking: isVideoRanking,
              metric: metric,
              color: color,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankingItem({
    required Map<String, dynamic>? item,
    required int index,
    required bool isEmpty,
    required bool isVideoRanking,
    required Color finalColor,
    required bool isDark,
    required String metric,
  }) {
            return GestureDetector(
              onTap: isEmpty ? null : () {
                if (isVideoRanking) {
                  final videoIndex = item!['index'] as int?;
                  if (videoIndex != null && videoIndex < _manualSelected.length) {
                    final video = _manualSelected[videoIndex];
                    if (video != null) {
                      _showVideoDetailsModal(video, videoIndex);
                    }
                  }
                } else {
                  final accountKey = item!['account'] as String?;
                  if (accountKey != null) {
                    _openFirstVideoDetailsForAccount(accountKey, metric);
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isEmpty
                            ? (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100])
                            : finalColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isEmpty
                                ? (isDark ? Colors.white.withOpacity(0.3) : Colors.grey[400])
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Thumbnail or avatar
                    if (!isEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: isVideoRanking
                            ? _buildVideoThumbnail(item!, finalColor, isDark)
                            : _buildAccountAvatar(
                                item!['account'] as String?,
                                finalColor,
                                isDark,
                                profileImageUrl: item!['profile_image_url'] as String?,
                              ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    const SizedBox(width: 12),
                    // Title/Name and value
                    Expanded(
                      child: isEmpty
                          ? Container(
                              height: 20,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item!['title'] as String? ?? 'Untitled',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.grey[900],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatNumber((item['value'] as num).toInt()),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: finalColor,
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

  Widget _buildExpandableRankingCard({
    required ThemeData theme,
    required bool isDark,
    required List<Map<String, dynamic>> rankedItems,
    required bool isVideoRanking,
    required String metric,
    required Color color,
  }) {
    final expansionKey = '${isVideoRanking ? 'video' : 'account'}_$metric';
    final isExpanded = _rankingExpanded[expansionKey] ?? false;
    final remainingItems = rankedItems.skip(3).toList();
    
    // Determina il colore per la card espandibile
    Color? cardColor;
    if (remainingItems.isNotEmpty) {
      final firstItem = remainingItems[0];
      if (isVideoRanking) {
        final videoIndex = firstItem['index'] as int?;
        if (videoIndex != null && videoIndex < _slotColors.length) {
          cardColor = _slotColors[videoIndex];
        }
      } else {
        final accountKey = firstItem['account'] as String?;
        if (accountKey != null) {
          for (int i = 0; i < _manualSelected.length; i++) {
            final video = _manualSelected[i];
            if (video != null) {
              final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
              bool found = false;
              accounts.forEach((platform, platformAccounts) {
                if (found) return;
                if (platformAccounts == null) return;
                List<Map<dynamic, dynamic>> accountList = [];
                if (platformAccounts is Map) {
                  accountList = [platformAccounts];
                } else if (platformAccounts is List) {
                  accountList = platformAccounts.whereType<Map>().toList();
                }
                for (final account in accountList) {
                  final accountId = account['account_id']?.toString() ?? 
                                   account['id']?.toString() ?? 
                                   account['username']?.toString() ?? '';
                  if (accountId == accountKey && i < _slotColors.length) {
                    cardColor = _slotColors[i];
                    found = true;
                    return;
                  }
                }
              });
              if (found) break;
            }
          }
        }
      }
    }
    final finalCardColor = cardColor ?? color;

    return GestureDetector(
      onTap: () {
        setState(() {
          _rankingExpanded[expansionKey] = !isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
          ),
        ),
        child: Column(
          children: [
            // Header della card espandibile
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'View ${remainingItems.length} more ${isVideoRanking ? 'posts' : 'accounts'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    size: 20,
                  ),
                ],
              ),
            ),
            // Contenuto espandibile: animazione SOLO in apertura (non in chiusura)
            ClipRect(
              child: AnimatedSize(
                duration: isExpanded
                    ? const Duration(milliseconds: 250)
                    : Duration.zero,
                curve: Curves.easeInOut,
                child: isExpanded
                    ? SizedBox(
                        // Altezza massima per evitare overflow; il contenuto interno sarà scrollabile
                        height: min(remainingItems.length * 64.0, 140.0),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: remainingItems.length,
                          itemBuilder: (context, idx) {
                            final item = remainingItems[idx];
                            final actualIndex = idx + 4; // +4 perché i primi 3 sono già mostrati (0,1,2) + 1 per l'indice reale
                            
                            // Determina il colore per questo elemento
                            Color? itemColor;
                            if (isVideoRanking) {
                              final videoIndex = item['index'] as int?;
                              if (videoIndex != null && videoIndex < _slotColors.length) {
                                itemColor = _slotColors[videoIndex];
                              }
                            } else {
                              final accountKey = item['account'] as String?;
                              if (accountKey != null) {
                                for (int i = 0; i < _manualSelected.length; i++) {
                                  final video = _manualSelected[i];
                                  if (video != null) {
                                    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
                                    bool found = false;
                                    accounts.forEach((platform, platformAccounts) {
                                      if (found) return;
                                      if (platformAccounts == null) return;
                                      List<Map<dynamic, dynamic>> accountList = [];
                                      if (platformAccounts is Map) {
                                        accountList = [platformAccounts];
                                      } else if (platformAccounts is List) {
                                        accountList = platformAccounts.whereType<Map>().toList();
                                      }
                                      for (final account in accountList) {
                                        final accountId = account['account_id']?.toString() ?? 
                                                         account['id']?.toString() ?? 
                                                         account['username']?.toString() ?? '';
                                        if (accountId == accountKey && i < _slotColors.length) {
                                          itemColor = _slotColors[i];
                                          found = true;
                                          return;
                                        }
                                      }
                                    });
                                    if (found) break;
                                  }
                                }
                              }
                            }
                            final finalItemColor = itemColor ?? color;
                            
                            return _buildRankingItem(
                              item: item,
                              index: actualIndex - 1, // -1 perché _buildRankingItem usa index + 1 per il badge
                              isEmpty: false,
                              isVideoRanking: isVideoRanking,
                              finalColor: finalItemColor,
                              isDark: isDark,
                              metric: metric,
                            );
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail(Map<String, dynamic> item, Color color, bool isDark) {
    // Usa VideoPreviewWidget se abbiamo tutte le informazioni necessarie (come in history_page.dart)
    final isNewFormat = item['isNewFormat'] as bool? ?? false;
    final videoId = item['videoId'] as String?;
    final userId = item['userId'] as String?;
    final status = item['status'] as String? ?? 'published';
    final isImage = item['isImage'] as bool? ?? false;
    final videoPath = item['videoPath'] as String?;
    final thumbnailPath = item['thumbnailPath'] as String?;
    final thumbnailCloudflareUrl = item['thumbnailCloudflareUrl'] as String?;
    
    // Se abbiamo tutte le informazioni, usa VideoPreviewWidget (come in history_page.dart)
    if (videoId != null && userId != null && (videoPath?.isNotEmpty == true || thumbnailPath?.isNotEmpty == true)) {
      return VideoPreviewWidget(
        videoPath: videoPath,
        thumbnailPath: thumbnailPath,
        thumbnailCloudflareUrl: thumbnailCloudflareUrl,
        width: 48,
        height: 48,
        isImage: isImage,
        videoId: videoId,
        userId: userId,
        status: status,
        isNewFormat: isNewFormat,
      );
    }
    
    // Fallback: usa la thumbnail URL semplice se disponibile
    final thumbnailUrl = item['thumbnail'] as String?;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.video_library,
                  size: 24,
                  color: color,
                ),
              ),
            )
          : Icon(
              Icons.video_library,
              size: 24,
              color: color,
            ),
    );
  }

  Widget _buildAccountAvatar(String? accountName, Color color, bool isDark, {String? profileImageUrl}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: profileImageUrl != null && profileImageUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                profileImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person,
                  size: 24,
                  color: color,
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  );
                },
              ),
            )
          : Icon(
              Icons.person,
              size: 24,
              color: color,
            ),
    );
  }

  List<Map<String, dynamic>> _getRankedVideos(String metric) {
    final List<Map<String, dynamic>> videos = [];
    for (int i = 0; i < _manualSelected.length; i++) {
      final video = _manualSelected[i];
      final stats = _videoStats[i];
      if (video != null && stats != null && stats[metric] != null) {
        final value = stats[metric] as double;
        if (value > 0) {
          // Calcola la data per mostrarla invece del titolo
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
          
          final dateTime = timestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(timestamp) : DateTime.now();
          final dateString = DateFormat('MMM d, yyyy').format(dateTime);
          
          // THUMBNAIL: Gestione corretta per nuovo formato (come in history_page.dart)
          String? thumbnail;
          if (isNewFormat) {
            // Per il nuovo formato: usa thumbnail_url
            thumbnail = video['thumbnail_url'] as String?;
          } else {
            // Per il vecchio formato: usa thumbnail_cloudflare_url, fallback a thumbnail_url
            thumbnail = video['thumbnail_cloudflare_url'] as String? ??
                       video['thumbnail_url'] as String?;
          }
          
          videos.add({
            'index': i,
            'video': video,
            'value': value,
            'title': dateString, // Usa la data invece del titolo
            'thumbnail': thumbnail,
            'isNewFormat': isNewFormat,
            'videoId': videoId,
            'userId': userId,
            'status': video['status'] as String? ?? 'published',
            'isImage': video['is_image'] == true,
            'videoPath': isNewFormat 
                ? video['media_url'] as String?
                : video['video_path'] as String?,
            'thumbnailPath': isNewFormat
                ? video['thumbnail_url'] as String?
                : video['thumbnail_path'] as String?,
            'thumbnailCloudflareUrl': isNewFormat
                ? video['thumbnail_url'] as String?
                : video['thumbnail_cloudflare_url'] as String?,
          });
        }
      }
    }
    videos.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
    return videos.take(5).toList();
  }

  List<Map<String, dynamic>> _getRankedAccounts(String metric) {
    final Map<String, Map<String, dynamic>> accountTotals = {};
    
    for (int i = 0; i < _manualSelected.length; i++) {
      final video = _manualSelected[i];
      final stats = _videoStats[i];
      if (video != null && stats != null && stats[metric] != null) {
        final value = stats[metric] as double;
        if (value > 0) {
          // Estrai gli account dalla struttura accounts del video
          final videoId = video['id']?.toString();
          final userId = video['user_id']?.toString();
          final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
          
          final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
          
          // Itera attraverso tutte le piattaforme
          accounts.forEach((platform, platformAccounts) {
            if (platformAccounts == null) return;
            
            // Gestisci sia Map che List
            List<Map<dynamic, dynamic>> accountList = [];
            if (platformAccounts is Map) {
              accountList = [platformAccounts];
            } else if (platformAccounts is List) {
              accountList = platformAccounts.whereType<Map>().toList();
            }
            
            // Per ogni account nella piattaforma
            for (final account in accountList) {
              final accountId = account['account_id']?.toString() ?? 
                               account['id']?.toString() ?? 
                               account['username']?.toString() ?? '';
              
              if (accountId.isEmpty) continue;
              
              final username = (account['account_username'] ?? account['username'] ?? '').toString();
              final displayName = (account['account_display_name'] ?? account['display_name'] ?? username).toString();
              final profileImageUrl = (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '').toString();
              
              // Usa accountId come chiave univoca
              final accountKey = accountId;
              
              if (!accountTotals.containsKey(accountKey)) {
                accountTotals[accountKey] = {
                  'account': accountKey,
                  'title': displayName.isNotEmpty ? displayName : (username.isNotEmpty ? username : accountKey),
                  'username': username.isNotEmpty ? username : accountKey,
                  'profile_image_url': profileImageUrl,
                  'value': 0.0,
                };
              }
              accountTotals[accountKey]!['value'] =
                  (accountTotals[accountKey]!['value'] as double) + value;
            }
          });
        }
      }
    }
    
    final List<Map<String, dynamic>> accounts = accountTotals.values.toList();
    accounts.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
    return accounts.take(5).toList();
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  // Helper functions from history_page.dart
  String _formatTimestamp(DateTime timestamp) {
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

  int _countTotalAccounts(Map<String, dynamic> video, bool isNewFormat) {
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

  Widget _buildPlatformLogo(String platform) {
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
        return _buildPlatformIcon(platform);
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        logoPath,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlatformIcon(platform);
        },
      ),
    );
  }

  Widget _buildPlatformIcon(String platform) {
    IconData iconData;
    Color iconColor;
    
    switch (platform.toLowerCase()) {
      case 'youtube':
        iconData = Icons.play_circle_filled;
        iconColor = Colors.red;
        break;
      case 'tiktok':
        iconData = Icons.music_note;
        iconColor = Colors.black87;
        break;
      case 'instagram':
        iconData = Icons.camera_alt;
        iconColor = Colors.purple;
        break;
      case 'facebook':
        iconData = Icons.facebook;
        iconColor = Colors.blue;
        break;
      case 'twitter':
        iconData = Icons.chat_bubble;
        iconColor = Colors.lightBlue;
        break;
      case 'threads':
        iconData = Icons.tag;
        iconColor = Colors.black87;
        break;
      default:
        iconData = Icons.public;
        iconColor = Colors.grey;
    }
    
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        size: 14,
        color: iconColor,
      ),
    );
  }

  Widget _buildStaticDurationBadge(Map<String, dynamic> video) {
    final cloudflareUrls = video['cloudflare_urls'];
    final bool isCarousel = cloudflareUrls != null && 
                           (cloudflareUrls is List && (cloudflareUrls as List).length > 1 ||
                            cloudflareUrls is Map && (cloudflareUrls as Map).length > 1);
    
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
    
    String duration;
    final durationSeconds = video['video_duration_seconds'] as int?;
    final durationMinutes = video['video_duration_minutes'] as int?;
    final durationRemainingSeconds = video['video_duration_remaining_seconds'] as int?;
    
    if (durationSeconds != null && durationMinutes != null && durationRemainingSeconds != null) {
      duration = '$durationMinutes:${durationRemainingSeconds.toString().padLeft(2, '0')}';
    } else {
      final idString = video['id'] as String? ?? '';
      final hashCode = idString.hashCode.abs() % 300 + 30;
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

  void _showVideoDetailsModal(Map<String, dynamic> video, int videoIndex) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stats = _videoStats[videoIndex];
    
    if (stats == null) return;
    
    final likes = (stats['likes'] as num?)?.toInt() ?? 0;
    final views = (stats['views'] as num?)?.toInt() ?? 0;
    final comments = (stats['comments'] as num?)?.toInt() ?? 0;
    
    // Determina se è nuovo formato
    final videoId = video['id']?.toString();
    final userId = video['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
    
    // Calcola timestamp per visualizzazione
    int timestamp;
    if (isNewFormat) {
      timestamp = video['scheduled_time'] as int? ?? 
                 (video['created_at'] is int ? video['created_at'] : int.tryParse(video['created_at']?.toString() ?? '') ?? 0) ??
                 (video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0);
    } else {
      timestamp = video['timestamp'] is int ? video['timestamp'] : int.tryParse(video['timestamp'].toString()) ?? 0;
    }
    
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final timeAgo = _formatTimestamp(dateTime);
    
    // SOCIAL MEDIA: platforms
    List<String> platforms;
    if (isNewFormat && video['accounts'] is Map) {
      platforms = (video['accounts'] as Map).keys.map((e) => e.toString()).toList();
    } else {
      platforms = List<String>.from(video['platforms'] ?? []);
    }
    
    // NUMERO ACCOUNT
    int accountCount = _countTotalAccounts(video, isNewFormat);
    final accountText = accountCount > 0 
        ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
        : 'No accounts';
    
    // STATUS
    String status = video['status'] as String? ?? 'published';
    final publishedAt = video['published_at'] as int?;
    final scheduledTime = video['scheduled_time'] as int?;
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    final hasYouTube = accounts.containsKey('YouTube');
    final wasScheduled = (publishedAt != null && scheduledTime != null) || 
                        (status == 'scheduled' && hasYouTube && scheduledTime != null);
    
    // Estrai i path come in history_page.dart (prima del builder)
    final videoPath = isNewFormat 
        ? video['media_url'] as String?
        : video['video_path'] as String?;
    final thumbnailPath = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_path'] as String?;
    final thumbnailCloudflareUrl = isNewFormat
        ? video['thumbnail_url'] as String?
        : video['thumbnail_cloudflare_url'] as String?;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
            child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            
                return GestureDetector(
                  onTap: () {}, // Previene la chiusura quando si clicca sul contenuto
                  child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  
                  // Video preview
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Video container (stesso stile di history_page.dart)
                          ClipRRect(
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
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Video thumbnail row
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Thumbnail
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) => VideoDetailsPage(video: video),
                                                ),
                                              );
                                            },
                                            child: Container(
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
                                                        VideoPreviewWidget(
                                                          videoPath: videoPath,
                                                          thumbnailPath: thumbnailPath,
                                                          thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                                                          width: 150,
                                                          height: 110,
                                                          isImage: video['is_image'] == true,
                                                          videoId: videoId,
                                                          userId: userId,
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
                                                        child: _buildStaticDurationBadge(video),
                                                      ),
                                                    ],
                                                  ),
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
                                                  Container(
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
                                                      mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          if (platforms.length <= 4)
                                                            ...platforms.map((platform) => Padding(
                                                              padding: const EdgeInsets.only(right: 7),
                                                              child: _buildPlatformLogo(platform.toString()),
                                                            ))
                                                          else
                                                            ...[
                                                              ...platforms.take(4).map((platform) => Padding(
                                                                padding: const EdgeInsets.only(right: 7),
                                                                child: _buildPlatformLogo(platform.toString()),
                                                              )),
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                decoration: BoxDecoration(
                                                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                                                  borderRadius: BorderRadius.circular(10),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color: theme.colorScheme.primary.withOpacity(0.1),
                                                                      blurRadius: 2,
                                                                      offset: Offset(0, 1),
                                                                    ),
                                                                  ],
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
                                                const SizedBox(height: 15),
                                                // Account info
                                                Container(
                                                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.surfaceVariant,
                                                    borderRadius: BorderRadius.circular(6),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withOpacity(0.03),
                                                        blurRadius: 2,
                                                        offset: Offset(0, 1),
                                                      ),
                                                    ],
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
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors.black.withOpacity(0.03),
                                                              blurRadius: 2,
                                                              offset: Offset(0, 1),
                                                            ),
                                                          ],
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
                                                    _buildStatusChip(status, wasScheduled),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 24),
                                      
                                      // Metrics tables
                                      _buildMetricsTable(
                                        theme: theme,
                                        isDark: isDark,
                                        likes: likes,
                                        views: views,
                                        comments: comments,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),
            );
          },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String status, bool wasScheduled) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountDetailsModal(String accountKey, String metric) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Trova tutti i video di questo account
    final accountVideos = <Map<String, dynamic>>[];
    final accountStats = <Map<String, double>>[];
    
    for (int i = 0; i < _manualSelected.length; i++) {
      final video = _manualSelected[i];
      final stats = _videoStats[i];
      if (video != null && stats != null) {
        final accountUsername = video['account_username'] as String? ??
            video['username'] as String? ??
            '';
        if (accountUsername == accountKey) {
          accountVideos.add(video);
          accountStats.add(stats);
        }
      }
    }
    
    if (accountVideos.isEmpty) return;
    
    // Calcola i totali
    int totalLikes = 0;
    int totalViews = 0;
    int totalComments = 0;
    
    for (final stats in accountStats) {
      totalLikes += (stats['likes'] as num?)?.toInt() ?? 0;
      totalViews += (stats['views'] as num?)?.toInt() ?? 0;
      totalComments += (stats['comments'] as num?)?.toInt() ?? 0;
    }
    
    // Prendi il primo video come principale
    final mainVideo = accountVideos[0];
    final videoId = mainVideo['id']?.toString();
    final userId = mainVideo['user_id']?.toString();
    final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
            child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
                return GestureDetector(
                  onTap: () {}, // Previene la chiusura quando si clicca sul contenuto
                  child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  
                  // Account name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      accountVideos[0]['account_display_name'] as String? ??
                          accountVideos[0]['display_name'] as String? ??
                          accountKey,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Video preview
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Video container
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => VideoDetailsPage(video: mainVideo),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                height: 200,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: VideoPreviewWidget(
                                  videoPath: isNewFormat 
                                      ? mainVideo['media_url'] as String?
                                      : mainVideo['video_path'] as String?,
                                  thumbnailPath: isNewFormat
                                      ? mainVideo['thumbnail_url'] as String?
                                      : mainVideo['thumbnail_path'] as String?,
                                  thumbnailCloudflareUrl: isNewFormat
                                      ? mainVideo['thumbnail_url'] as String?
                                      : mainVideo['thumbnail_cloudflare_url'] as String?,
                                  width: double.infinity,
                                  height: 200,
                                  isImage: mainVideo['is_image'] == true,
                                  videoId: videoId,
                                  userId: userId,
                                  status: mainVideo['status'] as String? ?? 'published',
                                  isNewFormat: isNewFormat,
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Account info
                          Text(
                            '${accountVideos.length} ${accountVideos.length == 1 ? 'video' : 'videos'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.grey[600],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Total metrics table
                          _buildMetricsTable(
                            theme: theme,
                            isDark: isDark,
                            likes: totalLikes,
                            views: totalViews,
                            comments: totalComments,
                            isTotal: true,
                          ),
                          
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),
            );
          },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricsTable({
    required ThemeData theme,
    required bool isDark,
    required int likes,
    required int views,
    required int comments,
    bool isTotal = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isTotal ? 'Total Metrics' : 'Video Metrics',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          
          // Metrics rows
          _buildMetricRow(
            theme: theme,
            isDark: isDark,
            label: 'Likes',
            value: likes,
            color: const Color(0xFF10B981),
            icon: Icons.favorite,
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          ),
          _buildMetricRow(
            theme: theme,
            isDark: isDark,
            label: 'Views',
            value: views,
            color: const Color(0xFF3B82F6),
            icon: Icons.visibility,
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          ),
          _buildMetricRow(
            theme: theme,
            isDark: isDark,
            label: 'Comments',
            value: comments,
            color: const Color(0xFFF59E0B),
            icon: Icons.comment,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Text(
            _formatNumber(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeWithAI() async {
    // Se esiste già un'analisi e i video non sono cambiati, apri semplicemente la tendina
    if (_lastAnalysis != null && _haveVideosChangedForAnalysis() == false) {
      _showAIChat();
      return;
    }

    // Verifica crediti per utenti non premium
    if (!_isPremium) {
      // Assicurati che i crediti siano aggiornati
      await _loadUserCredits();
      
      // Verifica che l'utente abbia almeno 20 crediti
      if (_userCredits < 20) {
        _showInsufficientCreditsBottomSheet();
        return;
      }
    }

    setState(() {
      _isAnalyzing = true;
      _isChatLoading = true;
    });

    // Apri subito la tendina per mostrare l'animazione di analisi
    _showAIChat();

    try {
      // Ottieni la lingua dell'utente da Firebase
      final language = await _getLanguage();
      
      // Prepara i dati dei video e delle stats
      final videos = _manualSelected;
      final stats = _videoStats;
      
      // Usa il servizio ChatGPT per l'analisi
      final aiResponse = await _chatGptService.analyzeMultiVideoStats(
        videos,
        stats,
        language,
      );
      
      // Estrai le domande suggerite dal testo dell'IA
      final extractedData = _extractSuggestedQuestionsFromText(aiResponse);
      final cleanText = extractedData['cleanText'] as String;
      final suggestedQuestions = extractedData['questions'] as List<String>;
      
      setState(() {
        _lastAnalysis = cleanText;
        _chatMessages.clear();
        final message = ChatMessage(
          text: cleanText,
          isUser: false,
          timestamp: DateTime.now(),
          suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
        );
        _chatMessages.add(message);
        // Aggiungi immediatamente alle animazioni completate per mostrare le suggested questions
        _completedAIMessageAnimations.add(message.id);
        _isAnalyzing = false;
        _isChatLoading = false;
        
        // Salva gli ID dei video per cui è stata fatta l'analisi
        for (int i = 0; i < _manualSelected.length; i++) {
          if (_manualSelected[i] != null) {
            _lastAnalyzedVideoIds[i] = _manualSelected[i]!['id']?.toString() ?? 
                                        _manualSelected[i]!['video_id']?.toString();
          } else {
            _lastAnalyzedVideoIds[i] = null;
          }
        }
      });
      
      // Aggiorna la tendina esistente invece di aprirne una nuova
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      } else {
        // Se la tendina non è aperta, aprila
      _showAIChat();
      }
    } catch (e) {
      setState(() {
        _chatMessages.clear();
        _chatMessages.add(ChatMessage(
          text: 'Sorry, I encountered an error while analyzing the videos. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isAnalyzing = false;
        _isChatLoading = false;
      });
      
      // Aggiorna la tendina esistente invece di aprirne una nuova
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      } else {
        // Se la tendina non è aperta, aprila
      _showAIChat();
      }
    }
  }

  void _showUpgradeForMoreVideosBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
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
              
              // Title
              Center(
                child: ShaderMask(
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
                  child: Text(
                    'Oh, you want more?',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'On the free plan you can compare up to 3 videos at the same time. Upgrade to Premium to unlock comparison for up to 10 videos with full AI analysis.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 24),
              
              // Premium features list
              ...[
                'Compare up to 10 videos',
                'Full AI analysis for all videos',
                'Unlimited video comparisons',
                'Priority support: Premium',
              ].map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                        children: [
                          Container(
                        padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: theme.colorScheme.primary,
                          size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                          feature,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Upgrade button
              Container(
                        width: double.infinity,
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
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const UpgradePremiumPage(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.arrow_forward,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Upgrade',
                            style: TextStyle(
                              fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
              ),
        );
      },
    );
  }

  void _showInsufficientCreditsBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
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
              
              // Title
              Center(
                child: ShaderMask(
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
                  child: const Text(
                    'Insufficient Credits',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'Get more credits or upgrade to Premium for unlimited AI analysis.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 32),
              
              // Upgrade to Premium button
              Container(
                width: double.infinity,
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
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const UpgradePremiumPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Upgrade to Premium',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Get Credits button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreditsPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.stars,
                        size: 18,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Get Credits',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
              ),
        );
      },
    );
  }

  Future<String> _getLanguage() async {
    String language = 'english';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final langSnap = await databaseRef.child('users').child('users').child(user.uid).child('language_analysis').get();
        if (langSnap.exists && langSnap.value is String) {
          language = langSnap.value as String;
        }
      }
    } catch (e) {
      print('Error loading user language: $e');
    }
    return language;
  }

  Map<String, Object> _extractSuggestedQuestionsFromText(String text) {
    final headerPattern = RegExp(
      r'^(?:\s*)(SUGGESTED[_\s]?QUESTIONS|DOMANDE\s+SUGGERITE)\s*:?\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    final lines = text.split('\n');
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (headerPattern.hasMatch(lines[i])) {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex == -1) {
      return {
        'cleanText': text,
        'questions': <String>[],
      };
    }
    final List<String> questions = [];
    int endIndex = headerIndex;
    final bulletPattern = RegExp(r'^\s*(?:[0-9]+[\)\.-]|[-•*–—])\s*(.+)$');
    for (int i = headerIndex + 1; i < lines.length; i++) {
      final raw = lines[i].trimRight();
      final trimmed = raw.trim();
      final isNote = RegExp(r'^\s*note\s*:', caseSensitive: false).hasMatch(trimmed);
      final isHeaderLike = RegExp(r'^[A-Z][A-Z\s_]+:?$').hasMatch(trimmed);
      if (trimmed.isEmpty && questions.isNotEmpty) {
        endIndex = i - 1;
        break;
      }
      if (isNote || isHeaderLike) {
        endIndex = i - 1;
        break;
      }
      String? qText;
      final bm = bulletPattern.firstMatch(raw);
      if (bm != null) {
        qText = bm.group(1)?.trim();
      } else if (trimmed.isNotEmpty) {
        qText = trimmed;
      }
      if (qText != null && qText.isNotEmpty) {
        questions.add(qText);
        endIndex = i;
        if (questions.length >= 3) {
          break;
        }
      }
    }
    if (questions.isEmpty) {
      return {
        'cleanText': text,
        'questions': <String>[],
      };
    }
    final cleaned = [
      ...lines.sublist(0, headerIndex),
      ...lines.sublist(endIndex + 1),
    ].join('\n').trim();
    return {
      'cleanText': cleaned,
      'questions': questions,
    };
  }

  Future<void> _openVideoPicker(int targetIndex) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    setState(() {
      _fetchError = '';
    });
    if (_cachedPublishedVideos.isEmpty) {
      await _fetchPublishedVideos();
    }
    
    // Se c'è già un video selezionato in questo slot, imposta il giorno al giorno del video
    final selectedVideo = _manualSelected[targetIndex];
    if (selectedVideo != null) {
      final int ts = (selectedVideo['published_at'] as int?) ?? (selectedVideo['timestamp'] as int? ?? 0);
      if (ts > 0) {
        final videoDate = DateTime.fromMillisecondsSinceEpoch(ts);
        final videoDay = _dateOnly(videoDate);
        setState(() {
          _selectedDay = videoDay;
          _focusedDay = videoDay; // Imposta anche focusedDay per mostrare la settimana corretta
        });
      }
    }
    
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.8,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                clipBehavior: Clip.hardEdge,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                  ),
                  child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Row(
                          children: [
                            ShaderMask(
                              shaderCallback: (Rect bounds) {
                                return const LinearGradient(
                                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds);
                              },
                              child: Text(
                                'Select a published video',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Spacer(),
                            _buildFilterButton(theme, isDark, setModalState),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildSearchBar(theme, isDark, setModalState),
                        const SizedBox(height: 8),
                        _buildWeekSelector(theme, isDark, setModalState),
                        const SizedBox(height: 10),
                        if (_isFetching)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_fetchError.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              _fetchError,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                            ),
                          )
                        else
                          Expanded(
                            child: NotificationListener<UserScrollNotification>(
                              onNotification: (notification) {
                                if (notification.metrics.axis == Axis.vertical) {
                                  // Scroll verso il basso: chiudi la tendina settimanale
                                  if (notification.direction == ScrollDirection.reverse &&
                                      _pickerWeekExpanded) {
                                    setModalState(() {
                                      _pickerWeekExpanded = false;
                                    });
                                  }
                                  // Scroll verso l'alto: riapri la tendina settimanale
                                  else if (notification.direction == ScrollDirection.forward &&
                                      !_pickerWeekExpanded) {
                                    setModalState(() {
                                      _pickerWeekExpanded = true;
                                    });
                                  }
                                }
                                return false;
                              },
                              child: _buildVideosForSelectedDayList(
                                theme,
                                day: _selectedDay,
                                onSelect: (video) {
                                  setState(() {
                                    _manualSelected[targetIndex] = Map<String, dynamic>.from(video);
                                    _videoStats[targetIndex] = null;
                                    _lastFetchedVideoIds[targetIndex] = null;
                                  });
                                  _updateFetchButtonVisibility();
                                  Navigator.of(context).pop();
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ));
          },
        );
      },
    );
  }

  /// Conta il numero di video selezionati (non null)
  int _getSelectedVideosCount() {
    return _manualSelected.where((v) => v != null).length;
  }

  /// Calcola il numero progressivo del video corrente tra quelli selezionati
  /// (quanti video non null ci sono fino all'indice corrente incluso)
  int _getCurrentVideoProgressNumber() {
    if (_currentStatsIndex < 0 || _currentStatsIndex >= _manualSelected.length) {
      return 0;
    }
    int count = 0;
    for (int i = 0; i <= _currentStatsIndex; i++) {
      if (_manualSelected[i] != null) {
        count++;
      }
    }
    return count;
  }

  bool _hasAllStatsCompleted() {
    // Verifica se ci sono video selezionati e se per ognuno ci sono le stats
    for (int i = 0; i < _manualSelected.length; i++) {
      if (_manualSelected[i] != null && _videoStats[i] == null) {
        return false;
      }
    }
    // Se almeno un video è selezionato e ha stats, mostra i grafici
    return _manualSelected.any((v) => v != null) && 
           _videoStats.any((stats) => stats != null);
  }

  /// Verifica se i video selezionati sono cambiati rispetto a quelli per cui abbiamo già le stats
  bool _haveVideosChanged() {
    for (int i = 0; i < _manualSelected.length; i++) {
      final currentVideo = _manualSelected[i];
      final currentVideoId = currentVideo != null 
          ? (currentVideo['id']?.toString() ?? currentVideo['video_id']?.toString())
          : null;
      
      // Se il video corrente è diverso da quello per cui abbiamo le stats, è cambiato
      if (currentVideoId != _lastFetchedVideoIds[i]) {
        return true;
      }
    }
    return false;
  }

  /// Verifica se i video sono cambiati rispetto all'ultima analisi IA
  bool _haveVideosChangedForAnalysis() {
    for (int i = 0; i < _manualSelected.length; i++) {
      final currentVideo = _manualSelected[i];
      final currentVideoId = currentVideo != null 
          ? (currentVideo['id']?.toString() ?? currentVideo['video_id']?.toString())
          : null;
      
      // Se il video corrente è diverso da quello analizzato, è cambiato
      if (currentVideoId != _lastAnalyzedVideoIds[i]) {
        return true;
      }
    }
    return false;
  }

  /// Verifica se il bottone deve essere mostrato
  void _updateFetchButtonVisibility() {
    final bool hasAtLeastOneSelection = _manualSelected.any((v) => v != null);
    
    if (!hasAtLeastOneSelection) {
      // Nessun video selezionato, nascondi il bottone
      if (_showFetchButton) {
        setState(() {
          _showFetchButton = false;
          _buttonAnimationController.reverse();
        });
      }
    } else if (_hasAllStatsCompleted() && !_haveVideosChanged()) {
      // I dati sono stati caricati e i video non sono cambiati, nascondi il bottone
      if (_showFetchButton) {
        setState(() {
          _showFetchButton = false;
          _buttonAnimationController.reverse();
        });
      }
    } else {
      // I video sono cambiati o non abbiamo ancora le stats, mostra il bottone
      if (!_showFetchButton) {
        setState(() {
          _showFetchButton = true;
          _buttonAnimationController.forward();
        });
      }
    }
  }

  Future<void> _runSequentialStatsFetch() async {
    if (_isStatsRunning) return;
    
    // Resetta l'analisi quando vengono ricaricate le stats (nuove chiamate API)
    setState(() {
      _lastAnalysis = null;
      _chatMessages.clear();
      _lastAnalyzedVideoIds = List.filled(_maxSlotsTotal, null);
      _isStatsRunning = true;
      _currentStatsIndex = -1;
      _completedVideosCount = 0;
      _statsError = '';
    });

    try {
      for (int i = 0; i < _manualSelected.length; i++) {
        final video = _manualSelected[i];
        if (video == null) {
          continue;
        }
        setState(() {
          _currentStatsIndex = i;
        });
        try {
          final stats = await _fetchAggregatedStatsForVideo(video);
          setState(() {
            _videoStats[i] = stats;
            _completedVideosCount++;
          });
        } catch (e) {
          setState(() {
            _statsError = 'Failed to load stats for video ${i + 1}: $e';
          });
          break;
        }
      }
      // Se tutte le stats sono pronte, nascondi il card iniziale con animazione
      if (mounted && _hasAllStatsCompleted()) {
        // Salva gli ID dei video per cui abbiamo le stats
        for (int i = 0; i < _manualSelected.length; i++) {
          if (_manualSelected[i] != null && _videoStats[i] != null) {
            _lastFetchedVideoIds[i] = _manualSelected[i]!['id']?.toString() ?? 
                                      _manualSelected[i]!['video_id']?.toString();
          } else {
            _lastFetchedVideoIds[i] = null;
          }
        }
        
        setState(() {
          _showHeaderHint = false;
          _showFetchButton = false; // Nascondi il bottone quando i dati sono stati caricati
          _buttonAnimationController.reverse();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStatsRunning = false;
          _currentStatsIndex = -1;
          _completedVideosCount = 0;
        });
      }
    }
  }

  Future<Map<String, double>> _fetchAggregatedStatsForVideo(Map<String, dynamic> video) async {
    final user = FirebaseAuth.instance.currentUser;
    final String? videoId = video['id']?.toString();
    final String? ownerId = video['user_id']?.toString() ?? user?.uid;

    if (videoId == null || videoId.isEmpty || ownerId == null || ownerId.isEmpty) {
      throw Exception('Invalid video data (missing id or user_id)');
    }

    // 1) Aggiorna i dati chiamando le API in tempo reale (come in video_stats_page.dart)
    await _refreshApiStatsForVideo(video, ownerId, videoId);

    // 2) Rileggi tutti i dati aggregati salvati in api_stats
    final savedStats = await _statsService.loadApiStatsFromFirebase(
      userId: ownerId,
      videoId: videoId,
    );

    double totalLikes = 0;
    double totalComments = 0;
    double totalViews = 0;

    savedStats.forEach((_, stats) {
      final likes = stats['likes'];
      final comments = stats['comments'];
      final views = stats['views'];

      if (likes is num) {
        totalLikes += likes.toDouble();
      } else if (likes != null) {
        final parsed = double.tryParse(likes.toString());
        if (parsed != null) totalLikes += parsed;
      }

      if (comments is num) {
        totalComments += comments.toDouble();
      } else if (comments != null) {
        final parsed = double.tryParse(comments.toString());
        if (parsed != null) totalComments += parsed;
      }

      if (views is num) {
        totalViews += views.toDouble();
      } else if (views != null) {
        final parsed = double.tryParse(views.toString());
        if (parsed != null) totalViews += parsed;
      }
    });

    return {
      'likes': totalLikes,
      'comments': totalComments,
      'views': totalViews,
    };
  }

  Future<void> _refreshApiStatsForVideo(
    Map<String, dynamic> video,
    String ownerId,
    String videoId,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final db = FirebaseDatabase.instance.ref();
    final Map<dynamic, dynamic> rawAccounts =
        video['accounts'] as Map<dynamic, dynamic>? ?? {};

    final String tikTokId = video['tiktok_id']?.toString() ?? '';
    final String youtubeId = video['youtube_id']?.toString() ?? '';
    final String instagramId = video['instagram_id']?.toString() ?? '';
    final String threadsId = video['threads_id']?.toString() ?? '';
    final String facebookId = video['facebook_id']?.toString() ?? '';
    final String twitterId = video['twitter_id']?.toString() ?? '';

    final Map<String, String> errors = {};

    // --- TikTok ---
    try {
      final dynamic tkRaw = rawAccounts['TikTok'];
      List<dynamic> tkAccounts;
      if (tkRaw is List) {
        tkAccounts = tkRaw;
      } else if (tkRaw is Map) {
        tkAccounts = tkRaw.values.toList();
      } else {
        tkAccounts = [];
      }

      if (tkAccounts.isNotEmpty) {
        int tkIdx = 1;
        for (final account in tkAccounts) {
          if (account is Map<dynamic, dynamic>) {
            final mediaId = account['media_id']?.toString() ?? '';
            final username =
                (account['account_username'] ?? account['username'] ?? '')
                    .toString();
            final displayName =
                (account['account_display_name'] ?? account['display_name'] ?? username)
                    .toString();
            final tkId =
                (account['account_id'] ?? account['id'] ?? '').toString();
            final effectiveId =
                mediaId.isNotEmpty ? mediaId : tikTokId;
            if (effectiveId.isNotEmpty) {
              try {
                final tiktokStats =
                    await _statsService.getTikTokStats(effectiveId);
                final accountKey = tkId.isNotEmpty ? tkId : 'tiktok_$tkIdx';
                await _statsService.saveApiStatsToFirebase(
                  userId: ownerId,
                  videoId: videoId,
                  platform: 'tiktok',
                  accountId: accountKey,
                  stats: tiktokStats,
                  accountUsername:
                      username.isNotEmpty ? username : 'tiktok_user',
                  accountDisplayName:
                      displayName.isNotEmpty ? displayName : 'TikTok Account',
                );
                await _statsService.updateUserTotals(
                  userId: ownerId,
                  platform: 'tiktok',
                  accountId: accountKey,
                  newStats: tiktokStats,
                  accountUsername:
                      username.isNotEmpty ? username : 'tiktok_user',
                  accountDisplayName:
                      displayName.isNotEmpty ? displayName : 'TikTok Account',
                );
              } catch (e) {
                errors['tiktok'] = e.toString();
              }
            }
            tkIdx++;
          }
        }
      } else if (tikTokId.isNotEmpty) {
        try {
          final tiktokStats =
              await _statsService.getTikTokStats(tikTokId);
          await _statsService.saveApiStatsToFirebase(
            userId: ownerId,
            videoId: videoId,
            platform: 'tiktok',
            accountId: 'main',
            stats: tiktokStats,
            accountUsername: 'tiktok_user',
            accountDisplayName: 'TikTok Account',
          );
          await _statsService.updateUserTotals(
            userId: ownerId,
            platform: 'tiktok',
            accountId: 'main',
            newStats: tiktokStats,
            accountUsername: 'tiktok_user',
            accountDisplayName: 'TikTok Account',
          );
        } catch (e) {
          errors['tiktok'] = e.toString();
        }
      }
    } catch (e) {
      errors['tiktok'] = e.toString();
    }

    // --- Instagram (multi-account, come video_stats_page.dart) ---
    try {
      final dynamic igRaw = rawAccounts['Instagram'];
      List<dynamic> igAccounts;
      if (igRaw is List) {
        igAccounts = igRaw;
      } else if (igRaw is Map) {
        igAccounts = igRaw.values.toList();
      } else {
        igAccounts = [];
      }
      int igIdx = 1;
      for (final account in igAccounts) {
        if (account is Map<dynamic, dynamic>) {
          final mediaId = account['media_id']?.toString() ?? '';
          final profileImageUrl =
              (account['account_profile_image_url'] ?? account['profile_image_url'] ?? '')
                  .toString();
          final username =
              (account['account_username'] ?? account['username'] ?? '')
                  .toString();
          final displayName =
              (account['account_display_name'] ?? account['display_name'] ?? username)
                  .toString();
          final igId =
              (account['account_id'] ?? account['id'] ?? '').toString();
          if (mediaId.isNotEmpty && igId.isNotEmpty) {
            try {
              final tokenSnap = await db
                  .child('users')
                  .child(ownerId)
                  .child('instagram')
                  .child(igId)
                  .child('facebook_access_token')
                  .get();
              if (tokenSnap.exists) {
                final accessToken = tokenSnap.value.toString();
                try {
                  final instagramStats = await _statsService
                      .getInstagramStats(mediaId, accessToken);
                  await _statsService.saveApiStatsToFirebase(
                    userId: ownerId,
                    videoId: videoId,
                    platform: 'instagram',
                    accountId: igId,
                    stats: instagramStats,
                    accountUsername: username,
                    accountDisplayName: displayName,
                  );
                  await _statsService.updateUserTotals(
                    userId: ownerId,
                    platform: 'instagram',
                    accountId: igId,
                    newStats: instagramStats,
                    accountUsername: username,
                    accountDisplayName: displayName,
                  );
                } catch (e) {
                  errors['instagram'] = e.toString();
                }
              }
            } catch (e) {
              errors['instagram'] = e.toString();
            }
          }
          igIdx++;
        }
      }
    } catch (e) {
      errors['instagram'] = e.toString();
    }

    // --- Threads (multi-account) ---
    try {
      final dynamic thRaw = rawAccounts['Threads'];
      List<dynamic> threadsAccounts;
      if (thRaw is List) {
        threadsAccounts = thRaw;
      } else if (thRaw is Map) {
        threadsAccounts = thRaw.values.toList();
      } else {
        threadsAccounts = [];
      }
      int thIdx = 1;
      for (final account in threadsAccounts) {
        if (account is Map<dynamic, dynamic>) {
          final postId = account['post_id']?.toString() ?? '';
          final username =
              (account['account_username'] ?? account['username'] ?? '')
                  .toString();
          final displayName =
              (account['account_display_name'] ?? account['display_name'] ?? username)
                  .toString();
          final thId =
              (account['account_id'] ?? account['id'] ?? '').toString();
          if (postId.isNotEmpty && thId.isNotEmpty) {
            try {
              final tokenSnap = await db
                  .child('users')
                  .child('users')
                  .child(ownerId)
                  .child('social_accounts')
                  .child('threads')
                  .child(thId)
                  .child('access_token')
                  .get();
              if (tokenSnap.exists) {
                final accessToken = tokenSnap.value.toString();
                try {
                  final threadsStats =
                      await _statsService.getThreadsStats(postId, accessToken);
                  await _statsService.saveApiStatsToFirebase(
                    userId: ownerId,
                    videoId: videoId,
                    platform: 'threads',
                    accountId: thId,
                    stats: threadsStats,
                    accountUsername: username,
                    accountDisplayName: displayName,
                  );
                  await _statsService.updateUserTotals(
                    userId: ownerId,
                    platform: 'threads',
                    accountId: thId,
                    newStats: threadsStats,
                    accountUsername: username,
                    accountDisplayName: displayName,
                  );
                } catch (e) {
                  errors['threads'] = e.toString();
                }
              }
            } catch (e) {
              errors['threads'] = e.toString();
            }
          }
          thIdx++;
        }
      }
    } catch (e) {
      errors['threads'] = e.toString();
    }

    // --- Facebook (multi-account) ---
    try {
      final dynamic fbRaw = rawAccounts['Facebook'];
      List<dynamic> fbAccounts;
      if (fbRaw is List) {
        fbAccounts = fbRaw;
      } else if (fbRaw is Map) {
        fbAccounts = fbRaw.values.toList();
      } else {
        fbAccounts = [];
      }
      int fbIdx = 1;
      for (final account in fbAccounts) {
        if (account is Map<dynamic, dynamic>) {
          final postId = account['post_id']?.toString() ?? '';
          final pageId = account['page_id']?.toString() ?? '';
          final displayName =
              (account['account_display_name'] ?? account['display_name'] ?? '')
                  .toString();
          if (postId.isNotEmpty && pageId.isNotEmpty) {
            try {
              final tokenSnap = await db
                  .child('users')
                  .child(ownerId)
                  .child('facebook')
                  .child(pageId)
                  .child('access_token')
                  .get();
              if (tokenSnap.exists) {
                final accessToken = tokenSnap.value.toString();
                try {
                  final facebookStats = await _statsService
                      .getFacebookStats(postId, accessToken);
                  await _statsService.saveApiStatsToFirebase(
                    userId: ownerId,
                    videoId: videoId,
                    platform: 'facebook',
                    accountId: pageId,
                    stats: facebookStats,
                    accountUsername: displayName,
                    accountDisplayName: displayName,
                  );
                  await _statsService.updateUserTotals(
                    userId: ownerId,
                    platform: 'facebook',
                    accountId: pageId,
                    newStats: facebookStats,
                    accountUsername: displayName,
                    accountDisplayName: displayName,
                  );
                } catch (e) {
                  errors['facebook'] = e.toString();
                }
              }
            } catch (e) {
              errors['facebook'] = e.toString();
            }
          }
          fbIdx++;
        }
      }
    } catch (e) {
      errors['facebook'] = e.toString();
    }

    // --- Twitter ---
    try {
      // Usa la stessa logica di video_stats_page.dart: accounts/Twitter + social_accounts/twitter
      final twitterAccountsSnapshot = await db
          .child('users')
          .child('users')
          .child(ownerId)
          .child('videos')
          .child(videoId)
          .child('accounts')
          .child('Twitter')
          .get();
      if (twitterAccountsSnapshot.exists) {
        final raw = twitterAccountsSnapshot.value;
        List<dynamic> twitterAccounts;
        if (raw is List) {
          twitterAccounts = raw;
        } else if (raw is Map) {
          twitterAccounts = raw.values.toList();
        } else {
          twitterAccounts = [];
        }
        if (twitterAccounts.isNotEmpty) {
          final firstAccount = twitterAccounts[0] as Map<dynamic, dynamic>;
          final twitterProfileId =
              (firstAccount['account_id'] ?? firstAccount['id'] ?? '')
                  .toString();
          final twitterPostId = firstAccount['post_id']?.toString();
          final username =
              (firstAccount['account_username'] ?? firstAccount['username'] ?? '')
                  .toString();
          final displayName =
              (firstAccount['account_display_name'] ?? firstAccount['display_name'] ?? username)
                  .toString();
          if (twitterProfileId.isNotEmpty &&
              twitterPostId != null &&
              twitterPostId.isNotEmpty) {
            try {
              final twitterStats = await _statsService.getTwitterStats(
                userId: ownerId,
                videoId: videoId,
              );
              await _statsService.saveApiStatsToFirebase(
                userId: ownerId,
                videoId: videoId,
                platform: 'twitter',
                accountId: twitterProfileId,
                stats: twitterStats,
                accountUsername:
                    username.isNotEmpty ? username : 'twitter_user',
                accountDisplayName: displayName.isNotEmpty
                    ? displayName
                    : 'Twitter Account',
              );
              await _statsService.updateUserTotals(
                userId: ownerId,
                platform: 'twitter',
                accountId: twitterProfileId,
                newStats: twitterStats,
                accountUsername:
                    username.isNotEmpty ? username : 'twitter_user',
                accountDisplayName: displayName.isNotEmpty
                    ? displayName
                    : 'Twitter Account',
              );
            } catch (e) {
              errors['twitter'] = e.toString();
            }
          }
        }
      }
    } catch (e) {
      errors['twitter'] = e.toString();
    }

    // --- YouTube (multi-account da video['accounts']['YouTube']) ---
    try {
      final dynamic ytRaw = rawAccounts['YouTube'];
      List<dynamic> ytAccounts;
      if (ytRaw is List) {
        ytAccounts = ytRaw;
      } else if (ytRaw is Map) {
        ytAccounts = ytRaw.values.toList();
      } else {
        ytAccounts = [];
      }
      int ytIdx = 1;
      for (final account in ytAccounts) {
        if (account is Map<dynamic, dynamic>) {
          final videoIdYt =
              account['youtube_video_id']?.toString() ?? '';
          final username =
              (account['account_username'] ?? account['username'] ?? '')
                  .toString();
          final displayName =
              (account['account_display_name'] ?? account['display_name'] ?? username)
                  .toString();
          final ytId =
              (account['account_id'] ?? account['id'] ?? '').toString();
          if (videoIdYt.isNotEmpty) {
            try {
              final youtubeStats = await _statsService
                  .getYouTubeStats(videoIdYt, null);
              final accountKey = ytId.isNotEmpty ? ytId : 'youtube_$ytIdx';
              await _statsService.saveApiStatsToFirebase(
                userId: ownerId,
                videoId: videoId,
                platform: 'youtube',
                accountId: accountKey,
                stats: youtubeStats,
                accountUsername: username,
                accountDisplayName: displayName,
              );
              await _statsService.updateUserTotals(
                userId: ownerId,
                platform: 'youtube',
                accountId: accountKey,
                newStats: youtubeStats,
                accountUsername: username,
                accountDisplayName: displayName,
              );
            } catch (e) {
              errors['youtube'] = e.toString();
            }
          }
          ytIdx++;
        }
      }
    } catch (e) {
      errors['youtube'] = e.toString();
    }

    // In questa versione, eventuali errori vengono solo registrati nella mappa errors
    // per debug, ma non lanciati: la funzione principale sommerà i dati disponibili.
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark, StateSetter setModalState) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.06),
          ),
        ),
        child: TextField(
          controller: _pickerSearchController,
          onChanged: (v) {
            setModalState(() {
              _pickerSearchQuery = v.trim().toLowerCase();
            });
          },
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Search videos...',
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: 13,
            ),
            prefixIcon: SizedBox(
              width: 36,
              height: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 0),
                  child: Icon(Icons.search, color: theme.colorScheme.primary, size: 18),
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            suffixIcon: _pickerSearchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _pickerSearchController.clear();
                      setModalState(() {
                        _pickerSearchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    color: theme.hintColor,
                  )
                : null,
            contentPadding: const EdgeInsets.only(left: 0, right: 8, top: -3),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          textAlignVertical: TextAlignVertical.center,
        ),
      ),
    );
  }

  Widget _buildFilterButton(ThemeData theme, bool isDark, StateSetter setModalState) {
    final bool hasActiveFilters =
        _pickerSelectedPlatforms.isNotEmpty || _pickerAccountsFilterActive || _pickerDateFilterActive;
    return GestureDetector(
      onTap: () => _openPickerFilters(theme, isDark, setModalState),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.15),
                blurRadius: isDark ? 16 : 12,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.6),
                blurRadius: 2,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.filter_list, color: hasActiveFilters ? theme.colorScheme.primary : theme.iconTheme.color, size: 18),
              if (hasActiveFilters)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF667eea),
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? const Color(0xFF121212) : Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPickerFilters(ThemeData theme, bool isDark, StateSetter parentSetState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final platformsSet = <String>{};
            for (final v in _cachedPublishedVideos) {
              final List<String> platforms =
                  (v['platforms'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
              for (final p in platforms) {
                final lp = p.toLowerCase();
                if (lp == 'youtube') {
                  platformsSet.add('YouTube');
                } else if (lp == 'instagram') {
                  platformsSet.add('Instagram');
                } else if (lp == 'facebook') {
                  platformsSet.add('Facebook');
                } else if (lp == 'threads') {
                  platformsSet.add('Threads');
                }
              }
            }
            final platforms = ['All', ...platformsSet.toList()];
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: theme.dividerColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Filters',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setModalState(() {
                                    _pickerSelectedPlatforms.clear();
                                    _pickerSelectedAccounts.clear();
                                    _pickerAccountsFilterActive = false;
                                    _pickerStartDate = null;
                                    _pickerEndDate = null;
                                    _pickerDateFilterActive = false;
                                  });
                                },
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        ),
                          const SizedBox(height: 6),
                          // Date range
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildDateRangeFilter(theme, isDark, setModalState),
                          ),
                          const SizedBox(height: 8),
                        // Platforms with expandable account lists (like history_page)
                        Flexible(
                          fit: FlexFit.loose,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: platforms.length,
                            itemBuilder: (context, index) {
                              final platform = platforms[index];
                              final isAll = platform == 'All';
                              final isSelected =
                                  isAll ? _pickerSelectedPlatforms.isEmpty : _pickerSelectedPlatforms.contains(platform);
                              final bool isExpanded = _pickerPlatformExpanded[platform] ?? false;
                              if (isAll) {
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      _pickerSelectedPlatforms.clear();
                                      _pickerSelectedAccounts.clear();
                                      _pickerAccountsFilterActive = false;
                                      _pickerStartDate = null;
                                      _pickerEndDate = null;
                                      _pickerDateFilterActive = false;
                                    });
                                    Navigator.of(context).pop();
                                    parentSetState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 18,
                                          color: _pickerSelectedPlatforms.isEmpty
                                              ? theme.colorScheme.primary
                                              : theme.iconTheme.color?.withOpacity(0.6),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'All',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: _pickerSelectedPlatforms.isEmpty
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              final accounts = _getAccountsForPlatformInPicker(platform);
                              return Column(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        if (_pickerSelectedPlatforms.contains(platform)) {
                                          _pickerSelectedPlatforms.remove(platform);
                                        } else {
                                          _pickerSelectedPlatforms.add(platform);
                                        }
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? (isDark
                                                ? const Color(0xFF667eea).withOpacity(0.08)
                                                : const Color(0xFF667eea).withOpacity(0.06))
                                            : Colors.transparent,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected ? Icons.check_circle : Icons.circle_outlined,
                                            size: 18,
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                : theme.iconTheme.color?.withOpacity(0.6),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            platform,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (accounts.isNotEmpty)
                                            GestureDetector(
                                              onTap: () {
                                                setModalState(() {
                                                  _pickerPlatformExpanded[platform] = !isExpanded;
                                                });
                                              },
                                              child: Icon(
                                                isExpanded
                                                    ? Icons.expand_less_rounded
                                                    : Icons.expand_more_rounded,
                                                size: 20,
                                                color: theme.iconTheme.color?.withOpacity(0.7),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 200),
                                    crossFadeState: isExpanded
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    firstChild: const SizedBox.shrink(),
                                    secondChild: accounts.isEmpty
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                                left: 48, right: 16, bottom: 6),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: accounts.map((acc) {
                                                final id = acc['id'] ?? '';
                                                final displayName = acc['display_name'] ?? '';
                                                final profileUrl = acc['profile_image_url'] ?? '';
                                                final isAccSelected =
                                                    _pickerSelectedAccounts.contains(id);
                                                return InkWell(
                                                  onTap: () {
                                                    setModalState(() {
                                                      if (isAccSelected) {
                                                        _pickerSelectedAccounts.remove(id);
                                                      } else {
                                                        _pickerSelectedAccounts.add(id);
                                                      }
                                                      _pickerAccountsFilterActive =
                                                          _pickerSelectedAccounts.isNotEmpty;
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(
                                                        vertical: 4),
                                                    child: Row(
                                                      children: [
                                                        CircleAvatar(
                                                          radius: 12,
                                                          backgroundColor: theme
                                                              .colorScheme.surfaceVariant,
                                                          backgroundImage:
                                                              profileUrl.isNotEmpty
                                                                  ? NetworkImage(profileUrl)
                                                                  : null,
                                                          child: profileUrl.isEmpty
                                                              ? Icon(Icons.person,
                                                                  size: 14,
                                                                  color: theme
                                                                      .iconTheme.color
                                                                      ?.withOpacity(0.6))
                                                              : null,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            displayName,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: theme.textTheme.bodySmall
                                                                ?.copyWith(fontSize: 12),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Icon(
                                                          isAccSelected
                                                              ? Icons.check_box
                                                              : Icons
                                                                  .check_box_outline_blank,
                                                          size: 16,
                                                          color: isAccSelected
                                                              ? theme.colorScheme.primary
                                                              : theme.iconTheme.color
                                                                  ?.withOpacity(0.6),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  parentSetState(() {}); // refresh parent modal to apply filters
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Apply filters'),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
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
            );
          },
        );
      },
    );
  }

  Widget _buildDateRangeFilter(ThemeData theme, bool isDark, StateSetter setModalState) {
    final bool active = _pickerDateFilterActive && _pickerStartDate != null && _pickerEndDate != null;
    return Container(
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).scale(0.06)
            : null,
        color: active ? null : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F6FA)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? const Color(0xFF667eea).withOpacity(0.4) : theme.dividerColor.withOpacity(0.6),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _buildDateSelector(
                theme: theme,
                label: 'From',
                selected: _pickerStartDate,
                onSelected: (d) {
                  setModalState(() {
                    _pickerStartDate = d;
                    _pickerDateFilterActive = _pickerStartDate != null && _pickerEndDate != null;
                  });
                },
                maxDate: _pickerEndDate,
              ),
            ),
            Container(width: 1, height: 42, color: theme.dividerColor.withOpacity(0.3)),
            Expanded(
              child: _buildDateSelector(
                theme: theme,
                label: 'To',
                selected: _pickerEndDate,
                onSelected: (d) {
                  setModalState(() {
                    _pickerEndDate = d;
                    _pickerDateFilterActive = _pickerStartDate != null && _pickerEndDate != null;
                  });
                },
                minDate: _pickerStartDate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required ThemeData theme,
    required String label,
    required DateTime? selected,
    required Function(DateTime) onSelected,
    DateTime? minDate,
    DateTime? maxDate,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selected ?? DateTime.now(),
          firstDate: minDate ?? DateTime(2020),
          lastDate: maxDate ?? DateTime.now(),
        );
        if (picked != null) {
          onSelected(picked);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.calendar_today_rounded, size: 14, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              selected != null ? DateFormat('MMM dd, yyyy').format(selected) : 'Select date',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected != null ? theme.textTheme.bodyLarge?.color : theme.hintColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Week selector (compact, inspired by history_page)
  Widget _buildWeekSelector(ThemeData theme, bool isDark, StateSetter setModalState) {
    // Build week days Mon..Sun based on _focusedDay
    final DateTime startOfWeek = _focusedDay.subtract(Duration(days: _focusedDay.weekday - 1));
    final List<DateTime> weekDays = List.generate(7, (i) => DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + i));
    // Counts per day (respecting active filters/search)
    final Map<DateTime, int> counts = {};
    for (final day in weekDays) {
      final key = _dateOnly(day);
      final dayVideos = _publishedByDay[key] ?? [];
      counts[key] = _applyPickerFilters(dayVideos).length;
    }
    final today = _dateOnly(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.25) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setModalState(() {
                    _focusedDay = _focusedDay.subtract(const Duration(days: 7));
                    // keep selection within visible week
                    if (_selectedDay.isBefore(_focusedDay) || _selectedDay.isAfter(_focusedDay.add(const Duration(days: 6)))) {
                      _selectedDay = _focusedDay;
                    }
                  });
                },
              ),
              Expanded(
                child: Center(
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds);
                    },
                    child: Text(
                      DateFormat('MMM yyyy').format(_focusedDay),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setModalState(() {
                    _focusedDay = _focusedDay.add(const Duration(days: 7));
                    if (_selectedDay.isBefore(_focusedDay) || _selectedDay.isAfter(_focusedDay.add(const Duration(days: 6)))) {
                      _selectedDay = _focusedDay;
                    }
                  });
                },
              ),
            ],
          ),
           const SizedBox(height: 6),
           AnimatedCrossFade(
             duration: const Duration(milliseconds: 200),
             crossFadeState: _pickerWeekExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
             firstChild: GestureDetector(
               onTap: () {
                 setModalState(() {
                   _pickerWeekExpanded = true;
                 });
               },
               child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                 child: Row(
                   children: [
                     Expanded(
                       child: Text(
                         'Published on ${DateFormat('EEE, MMM d, yyyy').format(_selectedDay)}',
                         style: theme.textTheme.bodySmall?.copyWith(
                           fontWeight: FontWeight.w500,
                           color: theme.colorScheme.primary,
                         ),
                       ),
                     ),
                     Icon(Icons.expand_more_rounded, size: 20, color: theme.colorScheme.primary),
                   ],
                 ),
               ),
             ),
             secondChild: Column(
               children: [
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: weekDays.map((day) {
                     final key = _dateOnly(day);
                     final isSelected = isSameDay(key, _dateOnly(_selectedDay));
                     final isToday = isSameDay(key, today);
                     final count = counts[key] ?? 0;
                     return Expanded(
                       child: GestureDetector(
                         onTap: () {
                           setModalState(() {
                             _selectedDay = day;
                           });
                         },
                         child: AnimatedContainer(
                           duration: const Duration(milliseconds: 200),
                           margin: const EdgeInsets.symmetric(horizontal: 3),
                           padding: const EdgeInsets.symmetric(vertical: 8),
                           decoration: BoxDecoration(
                             color: isSelected ? null : (isDark ? Colors.white.withOpacity(0.06) : Colors.white),
                             gradient: isSelected
                                 ? const LinearGradient(
                                     colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                     begin: Alignment.topLeft,
                                     end: Alignment.bottomRight,
                                   )
                                 : null,
                             borderRadius: BorderRadius.circular(12),
                             border: Border.all(
                               color: isSelected
                                   ? const Color(0xFF667eea).withOpacity(0.0)
                                   : (isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.06)),
                             ),
                           ),
                           constraints: const BoxConstraints(minHeight: 76, maxHeight: 76),
                           child: Column(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               Text(
                                 DateFormat('E').format(day).substring(0, 1),
                                 style: theme.textTheme.bodySmall?.copyWith(
                                   fontSize: 10,
                                   fontWeight: FontWeight.w600,
                                   color: isSelected
                                       ? Colors.white
                                       : (isToday ? const Color(0xFF667eea) : theme.textTheme.bodySmall?.color),
                                 ),
                               ),
                               const SizedBox(height: 4),
                               Text(
                                 day.day.toString(),
                                 style: theme.textTheme.bodySmall?.copyWith(
                                   fontSize: 13,
                                   fontWeight: FontWeight.w700,
                                   color: isSelected
                                       ? Colors.white
                                       : (isToday ? const Color(0xFF667eea) : theme.textTheme.bodyLarge?.color),
                                 ),
                               ),
                               const SizedBox(height: 4),
                               count > 0
                                   ? Container(
                                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                       decoration: BoxDecoration(
                                         color: isSelected
                                             ? Colors.white.withOpacity(0.25)
                                             : const Color(0xFF667eea).withOpacity(0.12),
                                         borderRadius: BorderRadius.circular(10),
                                       ),
                                       child: Text(
                                         '$count',
                                         style: TextStyle(
                                           fontSize: 10,
                                           fontWeight: FontWeight.bold,
                                           color: isSelected ? Colors.white : const Color(0xFF667eea),
                                         ),
                                       ),
                                     )
                                   : const SizedBox(
                                       width: 14,
                                       height: 14,
                                     ),
                             ],
                           ),
                         ),
                       ),
                     );
                   }).toList(),
                 ),
                 const SizedBox(height: 4),
                 GestureDetector(
                   onTap: () {
                     setModalState(() {
                       _pickerWeekExpanded = false;
                     });
                   },
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.expand_less_rounded, size: 18, color: theme.colorScheme.primary),
                     ],
                   ),
                 ),
               ],
             ),
           ),
        ],
      ),
    );
  }

  Widget _buildVideosForSelectedDayList(ThemeData theme, {required DateTime day, required Function(Map<String, dynamic>) onSelect}) {
    final isDark = theme.brightness == Brightness.dark;
    List<Map<String, dynamic>> videos = _publishedByDay[_dateOnly(day)] ?? [];
    // Apply filters: search, platforms, date range
    videos = _applyPickerFilters(videos);
    if (videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No content on ${DateFormat('MMM d, yyyy').format(day)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final video = videos[i];
        final String title = (video['title'] as String?)?.trim().isNotEmpty == true ? video['title'] as String : 'Untitled';
        final List<String> platforms = (video['platforms'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        
        // Determina se è nuovo formato
        final videoId = video['id']?.toString();
        final userId = video['user_id']?.toString();
        final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
        
        // THUMBNAIL: Gestione corretta per nuovo formato (come in history_page.dart)
        final videoPath = isNewFormat 
            ? video['media_url'] as String?
            : video['video_path'] as String?;
        final thumbnailPath = isNewFormat
            ? video['thumbnail_url'] as String?
            : video['thumbnail_path'] as String?;
        final thumbnailCloudflareUrl = isNewFormat
            ? video['thumbnail_url'] as String?
            : video['thumbnail_cloudflare_url'] as String?;
        
        final int ts = (video['published_at'] as int?) ?? (video['timestamp'] as int? ?? 0);
        final String timeLabel = ts > 0 ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ts)) : '';
        final int accountCount = _countTotalAccountsForVideo(video);
        final int selectedIndex = _getSelectedSlotIndexById(video['id']?.toString());
        final bool isAlreadySelected = selectedIndex != -1;
        final Color? tint = isAlreadySelected ? _slotColors[selectedIndex].withOpacity(isDark ? 0.12 : 0.10) : null;
        final Color borderTint = isAlreadySelected ? _slotColors[selectedIndex].withOpacity(0.35) : (isDark ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.06));
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAlreadySelected ? null : () => onSelect(video),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: tint ?? (isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.95)),
                border: Border.all(
                  color: borderTint,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail con VideoPreviewWidget e badge (come in history_page.dart)
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
                      width: 96,
                      height: 72,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (videoPath?.isNotEmpty == true || thumbnailPath?.isNotEmpty == true)
                              VideoPreviewWidget(
                                videoPath: videoPath,
                                thumbnailPath: thumbnailPath,
                                thumbnailCloudflareUrl: thumbnailCloudflareUrl,
                                width: 96,
                                height: 72,
                                isImage: video['is_image'] == true,
                                videoId: videoId,
                                userId: userId,
                                status: video['status'] as String? ?? 'published',
                                isNewFormat: isNewFormat,
                              )
                            else
                              Container(
                                color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEFF2F7),
                                child: Center(
                                  child: Icon(
                                    video['is_image'] == true ? Icons.image : Icons.video_library,
                                    size: 20,
                                    color: theme.hintColor,
                                  ),
                                ),
                              ),
                            // Badge della durata in basso a destra (come in history_page.dart)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: _buildStaticDurationBadge(video),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (platforms.isNotEmpty)
                          _buildPlatformIconsRow(theme, platforms),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people, size: 12, color: theme.colorScheme.primary),
                              const SizedBox(width: 3),
                              Text(
                                accountCount > 0
                                    ? '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}'
                                    : 'No accounts',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ts > 0
                              ? DateFormat('EEE, MMM d').format(DateTime.fromMillisecondsSinceEpoch(ts))
                              : '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                           builder: (_) => VideoDetailsPage(video: {
                             ...video,
                             'accounts': video['accounts'] ?? {},
                           }),
                        ),
                      );
                    },
                    child: Icon(Icons.chevron_right_rounded, color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchPublishedVideos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _fetchError = 'User not authenticated.';
      });
      return;
    }
    setState(() {
      _isFetching = true;
      _fetchError = '';
    });
    try {
      // Fetch user videos (replichiamo la struttura usata in history_page.dart
      // così VideoPreviewWidget può caricare correttamente le thumbnail)
      final videosRef =
          _database.child('users').child('users').child(user.uid).child('videos');
      final videosSnap = await videosRef.get();
      final List<Map<String, dynamic>> published = [];
      if (videosSnap.exists && videosSnap.value is Map) {
        final data = videosSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.entries) {
          final videoData = entry.value as Map<dynamic, dynamic>;
          final videoId = entry.key?.toString();
          final userId = videoData['user_id']?.toString() ?? user.uid;
          final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
          
          // Gestisci lo status come in history_page.dart
          String status = videoData['status']?.toString() ?? 'published';
          final publishedAt = videoData['published_at'] is int
              ? videoData['published_at'] as int
              : int.tryParse(videoData['published_at']?.toString() ?? '');
          final scheduledTime = videoData['scheduled_time'] is int
              ? videoData['scheduled_time'] as int
              : int.tryParse(videoData['scheduled_time']?.toString() ?? '');
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
          
          // Includi solo i video pubblicati
          if (status == 'published') {
            published.add({
              'id': entry.key,
              'title': videoData['title'] ?? '',
              'description': videoData['description'] ?? '',
              'platforms': List<String>.from(videoData['platforms'] ?? []),
              'status': status,
              'timestamp': videoData['timestamp'] ?? 0,
              'created_at': videoData['created_at'],
              'video_path': videoData['video_path'] ?? '',
              'media_url': videoData['media_url'],
              'thumbnail_path': videoData['thumbnail_path'] ?? '',
              'thumbnail_url': videoData['thumbnail_url'],
              'thumbnail_cloudflare_url':
                  videoData['thumbnail_cloudflare_url'] ?? '',
              'accounts': videoData['accounts'] ?? {},
              'user_id': userId,
              'scheduled_time': scheduledTime,
              'published_at': publishedAt,
              'youtube_video_id': videoData['youtube_video_id'],
              'is_image': videoData['is_image'] ?? false,
              'video_duration_seconds': videoData['video_duration_seconds'],
              'video_duration_minutes': videoData['video_duration_minutes'],
              'video_duration_remaining_seconds':
                  videoData['video_duration_remaining_seconds'],
              'cloudflare_urls': videoData['cloudflare_urls'],
              // ID specifici per piattaforma (usati per chiamate API come in video_stats_page.dart)
              'tiktok_id': videoData['tiktok_id'],
              'youtube_id': videoData['youtube_id'],
              'instagram_id': videoData['instagram_id'],
              'threads_id': videoData['threads_id'],
              'facebook_id': videoData['facebook_id'],
              'twitter_id': videoData['twitter_id'],
            });
          }
        }
      }
      // Include scheduled_posts that became published for YouTube (past scheduled_time)
      final scheduledRef = _database
          .child('users')
          .child('users')
          .child(user.uid)
          .child('scheduled_posts');
      final scheduledSnap = await scheduledRef.get();
      if (scheduledSnap.exists && scheduledSnap.value is Map) {
        final data = scheduledSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.entries) {
          final postData = entry.value as Map<dynamic, dynamic>;
          try {
            String status = postData['status']?.toString() ?? 'scheduled';
            final int? scheduledTime = postData['scheduled_time'] is int
                ? postData['scheduled_time'] as int
                : int.tryParse(postData['scheduled_time']?.toString() ?? '');
            final Map<dynamic, dynamic> accounts =
                postData['accounts'] as Map<dynamic, dynamic>? ?? {};
            final platforms = accounts.keys.map((e) => e.toString().toLowerCase()).toList();
            final bool hasYouTube = accounts.containsKey('YouTube');
            final bool isOnlyYouTube = platforms.length == 1 && platforms.first == 'youtube';
            
            // Solo per YouTube schedulati con data passata
            if (status == 'scheduled' && isOnlyYouTube && hasYouTube && scheduledTime != null) {
              final dt = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
              final now = DateTime.now();
              if (dt.isBefore(now)) {
                status = 'published'; // Imposta come published
                
                final videoId = entry.key?.toString();
                final userId = postData['user_id']?.toString() ?? user.uid;
                final isNewFormat = videoId != null && userId != null && videoId.contains(userId);
                
                published.add({
                  'id': entry.key,
                  'title': postData['title'] ?? '',
                  'description': postData['description'] ?? '',
                  'platforms': List<String>.from(postData['platforms'] ?? platforms.map((e) => e.toString().toUpperCase())),
                  'status': status,
                  'timestamp': postData['timestamp'] ?? scheduledTime,
                  'created_at': postData['created_at'],
                  'video_path': isNewFormat ? (postData['media_url'] ?? '') : (postData['video_path'] ?? ''),
                  'media_url': postData['media_url'],
                  'thumbnail_path': isNewFormat ? (postData['thumbnail_url'] ?? '') : (postData['thumbnail_path'] ?? ''),
                  'thumbnail_url': postData['thumbnail_url'],
                  'thumbnail_cloudflare_url':
                      postData['thumbnail_cloudflare_url'] ?? '',
                  'accounts': accounts,
                  'user_id': userId,
                  'scheduled_time': scheduledTime,
                  'published_at': null,
                  'youtube_video_id': postData['youtube_video_id'],
                  'is_image': postData['is_image'] ?? false,
                  'video_duration_seconds': postData['video_duration_seconds'],
                  'video_duration_minutes': postData['video_duration_minutes'],
                  'video_duration_remaining_seconds':
                      postData['video_duration_remaining_seconds'],
                  'cloudflare_urls': postData['cloudflare_urls'],
                  // scheduled_posts possono avere ID per piattaforma simili
                  'tiktok_id': postData['tiktok_id'],
                  'youtube_id': postData['youtube_id'],
                  'instagram_id': postData['instagram_id'],
                  'threads_id': postData['threads_id'],
                  'facebook_id': postData['facebook_id'],
                  'twitter_id': postData['twitter_id'],
                });
              }
            }
          } catch (e) {
            print('Error processing scheduled post: $e');
          }
        }
      }
      
      // Ordina i video considerando anche scheduled_time per YouTube schedulati con data passata
      published.sort((a, b) {
        int aTime = (a['published_at'] as int?) ?? (a['timestamp'] as int? ?? 0);
        int bTime = (b['published_at'] as int?) ?? (b['timestamp'] as int? ?? 0);
        
        // Per i video YouTube schedulati con data passata, usa scheduled_time
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
        
        return bTime.compareTo(aTime); // Ordine decrescente (più recenti prima)
      });
      setState(() {
        _cachedPublishedVideos = published;
        _publishedByDay = _groupVideosByDay(published);
        _focusedDay = DateTime.now();
        _selectedDay = DateTime.now();
        // Aggiorna la visibilità del bottone
        _updateFetchButtonVisibility();
      });
    } catch (e) {
      setState(() {
        _fetchError = 'Failed to load videos: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    }
  }

  Map<DateTime, List<Map<String, dynamic>>> _groupVideosByDay(List<Map<String, dynamic>> items) {
    final Map<DateTime, List<Map<String, dynamic>>> map = {};
    for (final v in items) {
      int ts = (v['published_at'] as int?) ?? (v['timestamp'] as int? ?? 0);
      
      // Per i video YouTube schedulati con data passata, usa scheduled_time
      final status = v['status'] as String? ?? '';
      final scheduledTime = v['scheduled_time'] as int?;
      final accounts = v['accounts'] as Map<dynamic, dynamic>? ?? {};
      final hasYouTube = accounts.containsKey('YouTube');
      if (status == 'published' && hasYouTube && scheduledTime != null) {
        ts = scheduledTime;
      }
      
      if (ts <= 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final day = _dateOnly(dt);
      map[day] = (map[day] ?? []);
      map[day]!.add(v);
    }
    // ensure each day's list is sorted desc by time
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        int at = (a['published_at'] as int?) ?? (a['timestamp'] as int? ?? 0);
        int bt = (b['published_at'] as int?) ?? (b['timestamp'] as int? ?? 0);
        
        // Per i video YouTube schedulati con data passata, usa scheduled_time
        final aStatus = a['status'] as String? ?? '';
        final aScheduledTime = a['scheduled_time'] as int?;
        final aAccounts = a['accounts'] as Map<dynamic, dynamic>? ?? {};
        final aHasYouTube = aAccounts.containsKey('YouTube');
        if (aStatus == 'published' && aHasYouTube && aScheduledTime != null) {
          at = aScheduledTime;
        }
        
        final bStatus = b['status'] as String? ?? '';
        final bScheduledTime = b['scheduled_time'] as int?;
        final bAccounts = b['accounts'] as Map<dynamic, dynamic>? ?? {};
        final bHasYouTube = bAccounts.containsKey('YouTube');
        if (bStatus == 'published' && bHasYouTube && bScheduledTime != null) {
          bt = bScheduledTime;
        }
        
        return bt.compareTo(at);
      });
    }
    return map;
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _getSelectedSlotIndexById(String? videoId) {
    if (videoId == null || videoId.isEmpty) return -1;
    for (int i = 0; i < _manualSelected.length; i++) {
      final sel = _manualSelected[i];
      if (sel != null && sel['id']?.toString() == videoId) {
        return i;
      }
    }
    return -1;
  }

  int _countTotalAccountsForVideo(Map<String, dynamic> video) {
    final accounts = video['accounts'] as Map<dynamic, dynamic>? ?? {};
    final String? videoId = video['id']?.toString();
    final String? userId = video['user_id']?.toString();
    final bool isNewFormat = videoId != null && userId != null && videoId.contains(userId);
    if (accounts.isEmpty) return 0;
    int totalCount = 0;
    try {
      if (isNewFormat) {
        // New format: each platform entry may be Map (single) or List (multiple)
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
        // Old format: count elements under each platform
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
    } catch (_) {}
    return totalCount;
  }

  // Collect unique accounts per platform for filters (similar to history_page.dart)
  List<Map<String, String>> _getAccountsForPlatformInPicker(String platform) {
    final Set<String> accountIds = {};
    final Map<String, Map<String, String>> details = {};
    final String lowerPlatform = platform.toLowerCase();

    for (final video in _cachedPublishedVideos) {
      final Map<dynamic, dynamic> rawAccounts =
          video['accounts'] as Map<dynamic, dynamic>? ?? {};
      final String? videoId = video['id']?.toString();
      final String? userId = video['user_id']?.toString();
      final bool isNewFormat =
          videoId != null && userId != null && videoId.contains(userId);

      Map<String, dynamic>? accounts;
      List<String> platforms;

      if (isNewFormat && rawAccounts.isNotEmpty) {
        accounts = Map<String, dynamic>.from(
            rawAccounts.map((k, v) => MapEntry(k.toString(), v)));
        platforms = accounts.keys.map((e) => e.toString()).toList();
      } else {
        platforms = List<String>.from(video['platforms'] ?? []);
        if (rawAccounts.isNotEmpty) {
          accounts = Map<String, dynamic>.from(
              rawAccounts.map((k, v) => MapEntry(k.toString(), v)));
        }
      }

      if (accounts == null) continue;

      final bool hasPlatform = platforms.any(
        (p) => p.toLowerCase() == lowerPlatform,
      );
      if (!hasPlatform) continue;

      final dynamic rawPlatformAccounts =
          accounts[platform] ?? accounts[platform.toLowerCase()];
      if (rawPlatformAccounts == null) continue;

      void addAccount(Map<String, dynamic> acc) {
        final id = acc['account_id']?.toString() ??
            acc['id']?.toString() ??
            acc['username']?.toString() ??
            '';
        if (id.isEmpty) return;
        if (accountIds.contains(id)) return;
        accountIds.add(id);
        details[id] = {
          'id': id,
          'display_name': acc['account_display_name']?.toString() ??
              acc['display_name']?.toString() ??
              acc['username']?.toString() ??
              id,
          'profile_image_url': acc['account_profile_image_url']?.toString() ??
              acc['profile_image_url']?.toString() ??
              '',
        };
      }

      if (rawPlatformAccounts is Map) {
        addAccount(Map<String, dynamic>.from(rawPlatformAccounts));
      } else if (rawPlatformAccounts is List) {
        for (final acc in rawPlatformAccounts) {
          if (acc is Map) {
            addAccount(Map<String, dynamic>.from(acc));
          }
        }
      }
    }

    return accountIds.map((id) => details[id]!).toList();
  }

  List<Map<String, dynamic>> _applyPickerFilters(List<Map<String, dynamic>> input) {
    List<Map<String, dynamic>> out = List.from(input);
    // Search
    if (_pickerSearchQuery.isNotEmpty) {
      out = out.where((v) {
        final title = (v['title'] as String? ?? '').toLowerCase();
        final platforms = ((v['platforms'] as List<dynamic>? ?? []).map((e) => e.toString().toLowerCase()).join(' '));
        return title.contains(_pickerSearchQuery) || platforms.contains(_pickerSearchQuery);
      }).toList();
    }
    // Date range
    if (_pickerDateFilterActive && _pickerStartDate != null && _pickerEndDate != null) {
      final start = _dateOnly(_pickerStartDate!);
      final end = _dateOnly(_pickerEndDate!);
      out = out.where((v) {
        final int ts = (v['published_at'] as int?) ?? (v['timestamp'] as int? ?? 0);
        if (ts <= 0) return false;
        final d = _dateOnly(DateTime.fromMillisecondsSinceEpoch(ts));
        return (d.isAtSameMomentAs(start) || d.isAfter(start)) && (d.isAtSameMomentAs(end) || d.isBefore(end));
      }).toList();
    }
    // Platforms
    if (_pickerSelectedPlatforms.isNotEmpty) {
      out = out.where((v) {
        final List<String> platforms = (v['platforms'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        return platforms.any((p) => _pickerSelectedPlatforms.any((sel) => p.toLowerCase() == sel.toLowerCase()));
      }).toList();
    }
    // Accounts filter skipped (structure not guaranteed here). Placeholder if needed later.
    return out;
  }

  // UI helpers for platform icons
  Widget _buildPlatformIconsRow(ThemeData theme, List<String> platforms) {
    final visible = platforms.take(4).toList();
    final extra = platforms.length - visible.length;
    return Row(
      children: [
        ...visible.map((p) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildPlatformLogo(p),
            )),
        if (extra > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+$extra',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  void _showAIChat() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Inizializza la chat solo se è vuota
    if (_chatMessages.isEmpty && _lastAnalysis != null) {
      final extractedData = _extractSuggestedQuestionsFromText(_lastAnalysis!);
      final cleanText = extractedData['cleanText'] as String;
      final suggestedQuestions = extractedData['questions'] as List<String>;
      final message = ChatMessage(
        text: cleanText,
        isUser: false,
        timestamp: DateTime.now(),
        suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
      );
      _chatMessages.add(message);
      // Aggiungi immediatamente alle animazioni completate per mostrare le suggested questions
      _completedAIMessageAnimations.add(message.id);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          _sheetStateSetter = setSheetState;
          
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            shouldCloseOnMinExtent: false,
            builder: (context, scrollController) {
              // Mostra l'input solo dopo che l'IA ha restituito una prima risposta
              final bool showInput =
                  !_isAnalyzing && (_lastAnalysis != null || _chatMessages.isNotEmpty);

              return Container(
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Handle bar
                      Container(
                        margin: EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      
                      // Chat / loading area
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 16),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              scrollbarTheme: ScrollbarThemeData(
                                thumbColor: MaterialStateProperty.all(Theme.of(context).colorScheme.outline.withOpacity(0.6)),
                                trackColor: MaterialStateProperty.all(Colors.transparent),
                                thickness: MaterialStateProperty.all(8.0),
                                radius: Radius.circular(4),
                                crossAxisMargin: -8,
                              ),
                            ),
                            child: (_lastAnalysis == null && _isAnalyzing)
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Lottie.asset(
                                          'assets/animations/analizeAI.json',
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'AI is analyzing...',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Theme.of(context).brightness == Brightness.dark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Scrollbar(
                                    controller: _chatScrollController,
                                    thumbVisibility: true,
                                    trackVisibility: false,
                                    thickness: 8,
                                    radius: Radius.circular(4),
                                    interactive: true,
                                    child: ListView.builder(
                                      controller: _chatScrollController,
                                      padding: EdgeInsets.only(
                                        left: 0,
                                        right: 0,
                                        // spazio extra in basso per non far coprire i messaggi dall'input sospeso
                                        bottom: showInput ? 90 : 16,
                                        // spazio in alto per non sovrapporsi subito al badge sospeso
                                        top: 56,
                                      ),
                                      itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == _chatMessages.length && _isChatLoading) {
                                          return _buildAILoadingMessage();
                                        }
                                        final message = _chatMessages[index];
                                        return _buildChatMessage(message);
                                      },
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      
                    ],
                  ),
                  
                  // Badge con titolo sospeso al centro in alto con effetto glass
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.psychology,
                                  color: const Color(0xFF6C63FF),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'AI Analysis',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Chat input sospeso in basso che segue la tastiera
                  if (showInput)
                    Positioned(
                      bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                      left: 16,
                      right: 16,
                      child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.15) 
                                      : Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(25),
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
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageFocusNode,
                                  maxLines: null,
                                  textInputAction: TextInputAction.done,
                                  keyboardType: TextInputType.multiline,
                                  decoration: InputDecoration(
                                    hintText: 'Ask a follow-up question...',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    isDense: true,
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  onEditingComplete: () {
                                    FocusScope.of(context).unfocus();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                              decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                Color(0xFF764ba2), // Colore finale: viola al 100%
                              ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  transform: GradientRotation(135 * 3.14159 / 180),
                                ),
                            shape: BoxShape.circle,
                              ),
                              child: IconButton(
                            icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () {
                                  if (_messageController.text.trim().isNotEmpty) {
                                    _sendMessageToAI(_messageController.text);
                                  }
                                },
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                              ),
                              ),
                      ],
                    ),
                  ),
                  
                  // Feedback interno in basso, visibile sopra l'input e davanti al badge
                  if (showInput)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 92 + MediaQuery.of(context).viewInsets.bottom, // ~1 cm sopra l'input chat e sopra tastiera
                      child: ValueListenableBuilder<int>(
                        valueListenable: _feedbackUpdateNotifier,
                        builder: (context, _, __) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _showFeedback
                                ? Container(
                                    key: const ValueKey('feedback_bottom'),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.grey[800]?.withOpacity(0.98)
                                          : Colors.white.withOpacity(0.98),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _feedbackMessage ?? '',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                      ),
                    ),
                ],
              ),
                                  )
                                : const SizedBox.shrink(),
                          );
                        },
                      ),
                    ),
                  
                  // Snackbar per crediti insufficienti
                  if (showInput)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 92 + MediaQuery.of(context).viewInsets.bottom,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _showInsufficientCreditsSnackbar
                            ? Container(
                                key: const ValueKey('insufficient_credits_snackbar_bottom'),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Insufficient credits.',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const CreditsPage(),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF667eea),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: const Color(0xFF667eea),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          'Get Credits',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            );
            },
          );
        },
      ),
    ).whenComplete(() {
      _sheetStateSetter = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  // Metodi per gestire i pulsanti delle risposte IA (feedback e copia)
  void _copyAIMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showFeedbackMessage('Message copied to clipboard!');
    
    // Forza il rebuild immediato del bottom sheet per mostrare il feedback
    _feedbackUpdateNotifier.value++;
  }
  
  void _toggleLike(int messageIndex) {
    setState(() {
      if (_aiMessageLikes[messageIndex] == true) {
        _aiMessageLikes[messageIndex] = false;
        _aiMessageDislikes[messageIndex] = false;
      } else {
        _aiMessageLikes[messageIndex] = true;
        _aiMessageDislikes[messageIndex] = false;
      }
    });
    
    // Forza il rebuild immediato del bottom sheet
    _feedbackUpdateNotifier.value++;
    
    // Mostra feedback interno alla tendina solo quando si attiva
    if (_aiMessageLikes[messageIndex] == true) {
      _showFeedbackMessage('Thank you for your feedback!');
    }
  }
  
  void _toggleDislike(int messageIndex) {
    setState(() {
      if (_aiMessageDislikes[messageIndex] == true) {
        _aiMessageDislikes[messageIndex] = false;
        _aiMessageLikes[messageIndex] = false;
      } else {
        _aiMessageDislikes[messageIndex] = true;
        _aiMessageLikes[messageIndex] = false;
      }
    });
    
    // Forza il rebuild immediato del bottom sheet
    _feedbackUpdateNotifier.value++;
    
    // Mostra feedback interno alla tendina solo quando si attiva
    if (_aiMessageDislikes[messageIndex] == true) {
      _showFeedbackMessage('Thank you for your feedback!');
    }
  }
  
  // Metodo per mostrare il feedback interno
  void _showFeedbackMessage(String message) {
    // Cancella eventuali timer precedenti
    _feedbackTimer?.cancel();
    
    setState(() {
      _feedbackMessage = message;
      _showFeedback = true;
    });
    
    // Forza l'aggiornamento del ValueListenableBuilder
    _feedbackUpdateNotifier.value++;
    
    // Aggiorna anche lo StateSetter della tendina se disponibile
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }
    
    // Nascondi il feedback dopo 2 secondi
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showFeedback = false;
          _feedbackMessage = null;
        });
        // Forza l'aggiornamento del ValueListenableBuilder anche quando si nasconde
        _feedbackUpdateNotifier.value++;
        if (_sheetStateSetter != null) {
          _sheetStateSetter!(() {});
        }
      }
    });
  }

  Future<void> _sendMessageToAI(String message) async {
    if (message.trim().isEmpty) return;
    
    // Chiudi la tastiera quando si invia un messaggio
    FocusScope.of(context).unfocus();
    
    // Verifica crediti per utenti non premium
    if (!_isPremium) {
      final hasEnoughCredits = await _hasEnoughCreditsForMessage(message);
      if (!hasEnoughCredits) {
        if (mounted) {
          setState(() {
            _showInsufficientCreditsSnackbar = true;
          });
          // Nascondi lo snackbar dopo 3 secondi
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _showInsufficientCreditsSnackbar = false;
              });
            }
          });
        }
        return;
      }
    }

    // Aggiungi il messaggio dell'utente
    setState(() {
      _chatMessages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });

    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }

    _messageController.clear();

    // Imposta lo stato di caricamento
    setState(() {
      _isChatLoading = true;
    });

    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }

    try {
      // Ottieni la lingua dell'utente
      final language = await _getLanguage();
      
      // Prepara i dati dei video e delle stats
      final videos = _manualSelected;
      final stats = _videoStats;
      
      // Usa il servizio ChatGPT per la risposta
      final aiResponse = await _chatGptService.analyzeMultiVideoStats(
        videos,
        stats,
        language,
        message,
        'chat',
      );
      
      // Aggiorna i crediti dopo la risposta (i crediti sono già stati sottratti dal servizio)
      if (!_isPremium) {
        await _loadUserCredits();
      }
      
      // Estrai le domande suggerite dal testo dell'IA
      final extractedData = _extractSuggestedQuestionsFromText(aiResponse);
      final cleanText = extractedData['cleanText'] as String;
      final suggestedQuestions = extractedData['questions'] as List<String>;
      
      setState(() {
        final message = ChatMessage(
          text: cleanText,
          isUser: false,
          timestamp: DateTime.now(),
          suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
        );
        _chatMessages.add(message);
        // Aggiungi immediatamente alle animazioni completate per mostrare le suggested questions
        _completedAIMessageAnimations.add(message.id);
        _isChatLoading = false;
      });
      
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(ChatMessage(
          text: 'Sorry, I encountered an error. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isChatLoading = false;
      });
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      }
    }
  }

  Widget _buildAILoadingMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.psychology,
                  size: 14,
                  color: const Color(0xFF6C63FF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(4),
                      topRight: const Radius.circular(18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: const Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? Colors.grey[400]! : Colors.grey[600]!,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI is typing...',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                          fontStyle: FontStyle.italic,
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
    );
  }

  // ==== Helpers per formattare la risposta IA (stile video_stats_page.dart) ====

  Widget _buildGradientText(String text, TextStyle style) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
      ).createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }

  Widget _buildMarkdownWithGradient(
    String text,
    TextStyle baseStyle,
    TextStyle strongStyle,
  ) {
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        strong: strongStyle.copyWith(
          foreground: Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
        ),
      ),
    );
  }

  Widget _formatAnalysisText(String analysis, bool isDark, ThemeData theme) {
    final sections = _identifySections(analysis);
    final baseStyle = TextStyle(
      fontSize: 16,
      color: isDark ? Colors.white : Colors.grey[800],
      height: 1.5,
    );
    final strongStyle = const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 18,
    );

    if (sections.isEmpty) {
      return _buildMarkdownWithGradient(analysis, baseStyle, strongStyle);
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections.map((section) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: _buildGradientText(
                      section.title,
                      const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _buildMarkdownWithGradient(
                  section.content,
                  baseStyle.copyWith(fontSize: 15),
                  strongStyle,
                ),
              ),
            ],
          );
        }).toList(),
      );
    }
  }

  List<AnalysisSection> _identifySections(String analysis) {
    final sections = <AnalysisSection>[];
    final RegExp sectionRegex = RegExp(r'([\n\r]|^)([A-Z][A-Z0-9\\s]+:)[\n\r]');
    final matches = sectionRegex.allMatches(analysis);

    if (matches.isEmpty) {
      sections.add(AnalysisSection('', analysis));
      return sections;
    }

    if (matches.first.start > 0) {
      sections.add(
        AnalysisSection('', analysis.substring(0, matches.first.start).trim()),
      );
    }

    for (int i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final title = match.group(2)?.trim() ?? '';

      int endIndex;
      if (i < matches.length - 1) {
        endIndex = matches.elementAt(i + 1).start;
      } else {
        endIndex = analysis.length;
      }

      final content = analysis.substring(match.end, endIndex).trim();
      sections.add(AnalysisSection(title, content));
    }

    return sections;
  }

  Widget _buildChatMessage(ChatMessage message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spazio extra solo sopra il PRIMO messaggio IA della tendina
              if (!message.isUser && _chatMessages.indexOf(message) == 0)
                const SizedBox(height: 38),
              // Spazio di 1 cm sopra ai messaggi inviati dall'utente alla IA
              if (message.isUser)
                const SizedBox(height: 38),
              if (message.isUser)
                // Messaggio utente: sempre allineato a destra
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[100],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: const Radius.circular(18),
                        bottomRight: const Radius.circular(4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                )
              else
                // Messaggio IA con animazione
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.elasticOut,
                      )),
                      child: FadeTransition(
                        opacity: Tween<double>(
                          begin: 0.0,
                          end: 1.0,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        )),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.8,
                            end: 1.0,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.elasticOut,
                          )),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    key: ValueKey(message.id),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: const Radius.circular(4),
                        bottomRight: const Radius.circular(18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ChatTypingAnalysisWidget(
                      text: message.text,
                      isCompleted: _completedAIMessageAnimations.contains(message.id),
                      builder: (partialText) => _formatAnalysisText(
                        partialText,
                        isDark,
                        theme,
                      ),
                      onCompleted: () {
                        if (!_completedAIMessageAnimations.contains(message.id) && mounted) {
                          setState(() {
                            _completedAIMessageAnimations.add(message.id);
                          });
                        }
                      },
                    ),
                  ),
                ),
              
              // Icona IA e pulsanti (come in video_stats_page.dart)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (!message.isUser) ...[
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.psychology,
                          size: 14,
                          color: const Color(0xFF6C63FF),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Pulsanti di azione allineati con l'icona IA
                      ValueListenableBuilder<int>(
                        valueListenable: _feedbackUpdateNotifier,
                        builder: (context, _, __) {
                          final messageIndex = _chatMessages.indexOf(message);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Pulsante Copy
                              GestureDetector(
                                onTap: () => _copyAIMessage(message.text),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.copy_outlined,
                                    size: 16,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Pulsante Like
                              GestureDetector(
                                onTap: () => _toggleLike(messageIndex),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: _aiMessageLikes[messageIndex] == true 
                                      ? const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                        )
                                      : null,
                                    color: _aiMessageLikes[messageIndex] == true ? null : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _aiMessageLikes[messageIndex] == true 
                                      ? Icons.thumb_up 
                                      : Icons.thumb_up_outlined,
                                    size: 16,
                                    color: _aiMessageLikes[messageIndex] == true 
                                      ? Colors.white 
                                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Pulsante Dislike
                              GestureDetector(
                                onTap: () => _toggleDislike(messageIndex),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: _aiMessageDislikes[messageIndex] == true 
                                      ? const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                        )
                                      : null,
                                    color: _aiMessageDislikes[messageIndex] == true ? null : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _aiMessageDislikes[messageIndex] == true 
                                      ? Icons.thumb_down 
                                      : Icons.thumb_down_outlined,
                                    size: 16,
                                    color: _aiMessageDislikes[messageIndex] == true 
                                      ? Colors.white 
                                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ] else ...[
                      // Spazio vuoto per allineare i pulsanti
                      const SizedBox(width: 24),
                    ],
                    const Spacer(),
                    if (message.isUser) ...[
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.person,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Domande suggerite per i messaggi dell'IA
        if (!message.isUser &&
            _completedAIMessageAnimations.contains(message.id) &&
            message.suggestedQuestions != null &&
            message.suggestedQuestions!.isNotEmpty) ...[
          SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested AI Questions:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                ...message.suggestedQuestions!.asMap().entries.map((entry) {
                  final question = entry.value;
                  
                  return GestureDetector(
                    onTap: () {
                      // Rimuovi le suggested questions dal messaggio
                      final messageIndex = _chatMessages.indexOf(message);
                      if (messageIndex != -1) {
                        _chatMessages[messageIndex] = ChatMessage(
                          text: _chatMessages[messageIndex].text,
                          isUser: false,
                          timestamp: _chatMessages[messageIndex].timestamp,
                          id: _chatMessages[messageIndex].id,
                          suggestedQuestions: null,
                        );
                        if (_sheetStateSetter != null) {
                          _sheetStateSetter!(() {});
                        }
                      }
                      // Invia automaticamente la domanda (senza metterla nel campo di input)
                      _sendMessageToAI(question);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667eea).withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        question,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// Widget helper per animazione typing
class ChatTypingAnalysisWidget extends StatefulWidget {
  final String text;
  final bool isCompleted;
  final Widget Function(String partialText) builder;
  final VoidCallback? onCompleted;

  const ChatTypingAnalysisWidget({
    Key? key,
    required this.text,
    required this.isCompleted,
    required this.builder,
    this.onCompleted,
  }) : super(key: key);

  @override
  State<ChatTypingAnalysisWidget> createState() => _ChatTypingAnalysisWidgetState();
}

class _ChatTypingAnalysisWidgetState extends State<ChatTypingAnalysisWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _calculateDuration(widget.text.length),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _hasCompleted = widget.isCompleted || widget.text.isEmpty;

    if (_hasCompleted) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }

    _controller.addListener(() {
      if (mounted && !_hasCompleted) {
        setState(() {});
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _notifyCompletion();
      }
    });
  }

  // ---- Helpers per formattare la risposta IA (copiati da video_stats_page.dart) ----

  Widget _buildGradientText(String text, TextStyle style) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
      ).createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }

  Widget _buildMarkdownWithGradient(
    String text,
    TextStyle baseStyle,
    TextStyle strongStyle,
  ) {
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        strong: strongStyle.copyWith(
          foreground: Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
        ),
      ),
    );
  }

  Widget _formatAnalysisText(String analysis, bool isDark, ThemeData theme) {
    final sections = _identifySections(analysis);
    final baseStyle = TextStyle(
      fontSize: 16,
      color: isDark ? Colors.white : Colors.grey[800],
      height: 1.5,
    );
    final strongStyle = const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 18,
    );

    if (sections.isEmpty) {
      return _buildMarkdownWithGradient(analysis, baseStyle, strongStyle);
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections.map((section) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: _buildGradientText(
                      section.title,
                      const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _buildMarkdownWithGradient(
                  section.content,
                  baseStyle.copyWith(fontSize: 15),
                  strongStyle,
                ),
              ),
            ],
          );
        }).toList(),
      );
    }
  }

  List<AnalysisSection> _identifySections(String analysis) {
    final sections = <AnalysisSection>[];
    final RegExp sectionRegex = RegExp(r'([\n\r]|^)([A-Z][A-Z0-9\\s]+:)[\n\r]');
    final matches = sectionRegex.allMatches(analysis);

    if (matches.isEmpty) {
      sections.add(AnalysisSection('', analysis));
      return sections;
    }

    if (matches.first.start > 0) {
      sections.add(
        AnalysisSection('', analysis.substring(0, matches.first.start).trim()),
      );
    }

    for (int i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final title = match.group(2)?.trim() ?? '';

      int endIndex;
      if (i < matches.length - 1) {
        endIndex = matches.elementAt(i + 1).start;
      } else {
        endIndex = analysis.length;
      }

      final content = analysis.substring(match.end, endIndex).trim();
      sections.add(AnalysisSection(title, content));
    }

    return sections;
  }


  @override
  void didUpdateWidget(covariant ChatTypingAnalysisWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.text != oldWidget.text) {
      _controller.duration = _calculateDuration(widget.text.length);
      _hasCompleted = widget.isCompleted || widget.text.isEmpty;
      if (_hasCompleted) {
        _controller.value = 1;
        _notifyCompletion();
      } else {
        _controller
          ..value = 0
          ..forward();
      }
    } else if (widget.isCompleted && !_hasCompleted) {
      _controller.value = 1;
      _notifyCompletion();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _calculateDuration(int length) {
    const minDuration = 1200;
    const maxDuration = 9000;
    const perChar = 28;
    final target = length * perChar;
    return Duration(
      milliseconds: max(minDuration, min(maxDuration, target)),
    );
  }

  void _notifyCompletion() {
    if (_hasCompleted) return;
    _hasCompleted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onCompleted?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final progress = widget.isCompleted ? 1.0 : _animation.value;
    final visibleChars = (widget.text.length * progress).clamp(0, widget.text.length).round();

    if (visibleChars <= 0) {
      return const SizedBox.shrink();
    }

    final partialText = widget.text.substring(0, visibleChars);
    return widget.builder(partialText);
  }
}

class AnalysisSection {
  final String title;
  final String content;

  AnalysisSection(this.title, this.content);
}


