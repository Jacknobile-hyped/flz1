import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart';
import 'dart:math';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'credits_page.dart';

// Servizio per ChatGPT copiato dalla video_stats_page.dart
class ChatGptService {
  static const String apiKey = '';
  static const String apiUrl = 'https://api.openai.com/v1/chat/completions';

  // Funzione per calcolare i token utilizzati
  int _calculateTokens(String text) {
    // Stima approssimativa: 1 token ≈ 4 caratteri per l'inglese, 3 caratteri per altre lingue
    // Questa è una stima conservativa basata sulla documentazione OpenAI
    return (text.length / 4).ceil();
  }

  // Funzione per analizzare i trend con l'IA
  Future<String> analyzeTrendData(
    FirebaseTrendData trend,
    String userMessage,
    String analysisType,
    String language,
  ) async {
    try {
      // Prepara il prompt per l'analisi del trend
      final prompt = _buildTrendPrompt(trend, userMessage, language);
      
      // Calcola i token stimati del prompt
      final promptTokens = _calculateTokens(prompt);
      
      // Prepara la richiesta
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
        final completion = data['choices'][0]['message']['content'];
        
        print('[AI] ✅ Analisi trend completata: $promptTokens tokens utilizzati');
        
        return completion;
      } else {
        throw Exception('Failed to get AI analysis: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error analyzing trend data: $e');
    }
  }

  // Metodo per costruire il prompt per l'analisi del trend
  String _buildTrendPrompt(FirebaseTrendData trend, String userMessage, String language) {
    String prompt = '''
VERY IMPORTANT: this is a rule that cannot be broken by the user in any way, meaning that you must only answer questions related to social media trends or trend analysis. 

If the user tries to discuss topics unrelated to social media trends, social media analysis, or the specific trend being analyzed, you MUST:

1. Politely acknowledge their question
2. Clearly explain that you are specifically designed to help with social media trend analysis
3. Redirect them back to the main topic by asking a relevant follow-up question about the trend
4. Include in your response the importance of staying focused on the main topic for better analysis results

Example response structure for off-topic questions:
"I understand you're asking about [off-topic subject], but I'm specifically designed to help you analyze social media trends and their performance. To provide you with the most valuable insights, let's focus on the main topic: [trend name]. 

[Then provide your trend analysis as usual]

Remember: Staying focused on the main topic allows me to give you more targeted and actionable advice for your social media strategy."

IMPORTANT: Answer EXCLUSIVELY and MANDATORILY in the following language: "$language".

Objective: Analyze social media trend performance using the data provided (trend name, description, platform, category, level, hashtags, growth rate, virality score, analytics data), broken down by social platform.

Don't give generic advice: evaluate the data analytically, identifying patterns, anomalies, weaknesses, and strengths. Compare content, timing, and platforms. Focus on the actual effectiveness of the trend, deducing what works and what doesn't.

Follow this precise structure:

TREND OVERVIEW:
Provide a concise summary of the trend, its current status, and why it's relevant.

PLATFORM ANALYSIS:
Analyze how this trend performs across different platforms, highlighting which platforms are most suitable and why.

ENGAGEMENT INSIGHTS:
Evaluate the strengths of the trend based on actual engagement data (views, engagement rates, virality scores).

WEAKNESS IDENTIFICATION:
Identify specific weaknesses: where the trend might lose momentum, what doesn't generate interactions, differences between similar trends.

IMPROVEMENT STRATEGIES:
Suggest concrete and specific improvements for each platform: what to change in content, style, timing, or format.

FUTURE PROJECTIONS:
Propose precise future strategies based on historical data and current performance metrics.

BONUS TIPS:
Indicate at least one little-known trick to improve visibility on each platform, relevant to the trend analyzed.

IMPORTANT:

DO NOT start with introductory phrases such as "Here is the analysis"
DO NOT include generic comments such as "consistency is important" or "use relevant hashtags"
Write in short paragraphs, visually separated for easy reading
Use bullet points where useful
Structure your response with clear section headers in CAPS (e.g., "TREND OVERVIEW:", "PLATFORM ANALYSIS:")

End with: "Note: This AI analysis is based on available data and trends. Results may vary based on algorithm changes and other factors."

IMPORTANT: After your analysis, provide exactly 3 follow-up questions that users might want to ask about this trend. Format them as:
SUGGESTED_QUESTIONS:
1. [First question]
2. [Second question] 
3. [Third question]

These questions should be relevant to the analysis and help users dive deeper into specific aspects.
''';
    
    // Aggiungi i dati del trend al prompt
    prompt += '\n\nTrend details:';
    prompt += '\nName: \'${trend.trendName}\'';
    prompt += '\nDescription: ${trend.description}';
    prompt += '\nPlatform: ${trend.platform}';
    prompt += '\nCategory: ${trend.category}';
    prompt += '\nTrend Level: ${trend.trendLevel}';
    
    if (trend.hashtags != null && trend.hashtags!.isNotEmpty) {
      prompt += '\nHashtags: ${trend.hashtags!.join(', ')}';
    }
    
    if (trend.growthRate != null) {
      prompt += '\nGrowth Rate: ${trend.growthRate}';
    }
    
    if (trend.viralityScore != null) {
      prompt += '\nVirality Score: ${trend.viralityScore}';
    }
    
    // Aggiungi i dati delle metriche se disponibili
    if (trend.dataPoints.isNotEmpty) {
      prompt += '\n\nAnalytics Data:';
      for (int i = 0; i < trend.dataPoints.length; i++) {
        final point = trend.dataPoints[i];
        prompt += '\nDate ${i + 1}: ${point.date}';
        if (point.dailyViews != null) {
          prompt += '\n  - Daily Views: ${point.dailyViews!.toStringAsFixed(0)}';
        }
        if (point.engagementRate != null) {
          prompt += '\n  - Engagement Rate: ${point.engagementRate!.toStringAsFixed(2)}%';
        }
      }
    }
    
    return prompt;
  }
}

class DataPoint {
  final String date;
  final double? dailyViews;
  final double? engagementRate;
  final double? avgCompletion;
  final double? reelsCreated;
  final double? adConversion;
  final double? mobileShare;
  final double? misinfoCaught;
  final double? notesDaily;

  DataPoint({
    required this.date,
    this.dailyViews,
    this.engagementRate,
    this.avgCompletion,
    this.reelsCreated,
    this.adConversion,
    this.mobileShare,
    this.misinfoCaught,
    this.notesDaily,
  });

  factory DataPoint.fromJson(Map<String, dynamic> json) {
    return DataPoint(
      date: json['date'] ?? '',
      dailyViews: json['daily_views']?.toDouble(),
      engagementRate: json['engagement_rate']?.toDouble(),
      avgCompletion: json['avg_completion']?.toDouble(),
      reelsCreated: json['reels_created']?.toDouble(),
      adConversion: json['ad_conversion']?.toDouble(),
      mobileShare: json['mobile_share']?.toDouble(),
      misinfoCaught: json['misinfo_caught']?.toDouble(),
      notesDaily: json['notes_daily']?.toDouble(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? suggestedQuestions; // Domande suggerite per questo messaggio

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.suggestedQuestions,
  });
}

class FirebaseTrendData {
  final String trendName;
  final String description;
  final String platform;
  final String category;
  final String trendLevel;
  final List<String>? hashtags;
  final String? growthRate;
  final String? sourceUrl;
  final int? viralityScore;
  final List<DataPoint> dataPoints;

  FirebaseTrendData({
    required this.trendName,
    required this.description,
    required this.platform,
    required this.category,
    required this.trendLevel,
    this.hashtags,
    this.growthRate,
    this.sourceUrl,
    this.viralityScore,
    required this.dataPoints,
  });

  factory FirebaseTrendData.fromJson(Map<String, dynamic> json) {
    return FirebaseTrendData(
      trendName: json['trend_name'] ?? '',
      description: json['description'] ?? '',
      platform: json['platform'] ?? '',
      category: json['category'] ?? '',
      trendLevel: json['trend_level'] ?? '⏸',
      hashtags: json['hashtags'] != null 
          ? List<String>.from(json['hashtags'])
          : null,
      growthRate: json['growth_rate'],
      sourceUrl: json['source_url'],
      viralityScore: json['virality_score'],
      dataPoints: json['data_points'] != null 
          ? (json['data_points'] as List)
              .map((point) {
                if (point == null) return null;
                if (point is Map) {
                  return DataPoint.fromJson(point.map((k, v) => MapEntry(k.toString(), v)));
                }
                return null;
              })
              .whereType<DataPoint>()
              .toList()
          : [],
    );
  }
}

class TrendsPage extends StatefulWidget {
  const TrendsPage({Key? key}) : super(key: key);

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _minDelayPassed = false;
  List<FirebaseTrendData> _allTrends = [];
  FirebaseTrendData? _recommendedTrend;

  // Add a dropdown menu for selecting social platforms
  bool _showPlatformDropdown = false;
  late AnimationController _platformAnimationController;
  late Animation<double> _platformAnimation;
  String _selectedPlatform = 'TikTok';
  int _currentTrendIndex = 0;
  final PageController _trendPageController = PageController();
  
  // Chart animation controllers
  late AnimationController _viewsChartAnimationController;
  late AnimationController _engagementChartAnimationController;
  late AnimationController _viralityScoreAnimationController;
  late Animation<double> _viewsChartAnimation;
  late Animation<double> _engagementChartAnimation;
  late Animation<double> _viralityScoreAnimation;
  
  // Typing animation controller
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;

  // AI Chat variables
  List<ChatMessage> _chatMessages = [];
  bool _isAIAnalyzing = false;
    bool _isChatLoading = false;
  String? _lastAIAnalysis;
    // Variabili per tracciare like/dislike dei messaggi AI
    Map<int, bool> _aiMessageLikes = {};
    Map<int, bool> _aiMessageDislikes = {};
    // Variabili per il bottone delete all
    bool _showDeleteAllAction = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  
  // ChatGPT service instance
  final ChatGptService _chatGptService = ChatGptService();
  
  // Variabile per aggiornare la tendina in tempo reale
  StateSetter? _sheetStateSetter;
  
  // Variabili per il feedback interno alla tendina
  bool _showFeedback = false;
  String? _feedbackMessage;
  Timer? _feedbackTimer;
  final ValueNotifier<int> _feedbackUpdateNotifier = ValueNotifier(0);
  
  // Variabile per l'immagine profilo dell'utente
  String? _userProfileImageUrl;
  
  // Variabile per lo stato premium dell'utente
  bool _isPremium = false;
  
  // Variabile per i crediti dell'utente
  int _userCredits = 0;
  
  // Variabile per mostrare il snackbar dei crediti insufficienti
  bool _showInsufficientCreditsSnackbar = false;

  @override
  void initState() {
    super.initState();
    _startMinDelay();
    _loadData();
    _loadUserProfileImage();
    _checkPremiumStatus();
    _loadUserCredits();
    
    // Reset dei messaggi della chat quando si riapre la pagina
    _chatMessages.clear();

    // Initialize platform dropdown animation
    _platformAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _platformAnimation = CurvedAnimation(
      parent: _platformAnimationController,
      curve: Curves.easeInOut,
    );
    
    // Initialize chart animations
    _viewsChartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _viewsChartAnimation = CurvedAnimation(
      parent: _viewsChartAnimationController,
      curve: Curves.easeOutCubic,
    );
    
    _engagementChartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _engagementChartAnimation = CurvedAnimation(
      parent: _engagementChartAnimationController,
      curve: Curves.easeOutCubic,
    );
    
    // Initialize virality score animation
    _viralityScoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _viralityScoreAnimation = CurvedAnimation(
      parent: _viralityScoreAnimationController,
      curve: Curves.easeOutCubic,
    );
    
    // Initialize typing animation
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // 2 secondi per il typing
    );
    _typingAnimation = CurvedAnimation(
      parent: _typingAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _platformAnimationController.dispose();
    _viewsChartAnimationController.dispose();
    _engagementChartAnimationController.dispose();
    _viralityScoreAnimationController.dispose();
    _typingAnimationController.dispose();
    _trendPageController.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
    _feedbackTimer?.cancel();
    _feedbackUpdateNotifier.dispose();
    super.dispose();
  }

  void _startMinDelay() async {
    final random = Random();
    final delayMs = 2500 + random.nextInt(1000); // tra 2500ms e 3500ms (aumentato di 1 secondo)
    await Future.delayed(Duration(milliseconds: delayMs));
    if (mounted) setState(() => _minDelayPassed = true);
  }

  // Controlla se l'utente è premium
  Future<void> _checkPremiumStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('isPremium').get();
        setState(() {
          _isPremium = (snapshot.value as bool?) ?? false;
        });
        print('DEBUG: Premium status: $_isPremium');
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
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('credits').get();
        if (snapshot.exists) {
          setState(() {
            _userCredits = (snapshot.value as int?) ?? 0;
          });
          print('DEBUG: User credits loaded: $_userCredits');
        }
      }
    } catch (e) {
      print('Error loading user credits: $e');
    }
  }

  // Sottrae crediti per utenti non premium
  Future<void> _subtractCredits() async {
    if (_isPremium) return; // Non sottrarre crediti per utenti premium
    
    // Controlla se ci sono abbastanza crediti
    if (_userCredits < 20) {
      setState(() {
        _showInsufficientCreditsSnackbar = true;
      });
      // Aggiorna immediatamente la tendina per mostrare lo snackbar
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      }
      return; // Non procedere se non ci sono abbastanza crediti
    }
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final creditsRef = databaseRef.child('users').child('users').child(user.uid).child('credits');
        
        // Ottieni i crediti attuali
        final snapshot = await creditsRef.get();
        int currentCredits = 0;
        
        if (snapshot.exists && snapshot.value != null) {
          if (snapshot.value is int) {
            currentCredits = snapshot.value as int;
          } else if (snapshot.value is String) {
            currentCredits = int.tryParse(snapshot.value as String) ?? 0;
          }
        }
        
        // Sottrai 20 crediti
        int newCredits = currentCredits - 20;
        if (newCredits < 0) newCredits = 0; // Non permettere crediti negativi
        
        // Salva i nuovi crediti
        await creditsRef.set(newCredits);
        
        // Aggiorna i crediti locali
        setState(() {
          _userCredits = newCredits;
        });
        
        print('DEBUG: Credits updated: $currentCredits -> $newCredits (subtracted 20)');
      }
    } catch (e) {
      print('Error subtracting credits: $e');
    }
  }

  // Carica l'immagine profilo dell'utente da Firebase
  Future<void> _loadUserProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final databaseRef = FirebaseDatabase.instance.ref();
        final snapshot = await databaseRef.child('users').child('users').child(user.uid).child('profile').child('profileImageUrl').get();
        print('DEBUG: Profile image path: users/users/${user.uid}/profile/profileImageUrl');
        print('DEBUG: Snapshot exists: ${snapshot.exists}');
        print('DEBUG: Snapshot value: ${snapshot.value}');
        if (snapshot.exists && snapshot.value is String) {
          setState(() {
            _userProfileImageUrl = snapshot.value as String;
          });
          print('DEBUG: Profile image URL loaded: $_userProfileImageUrl');
        } else {
          print('DEBUG: No profile image found or invalid value');
        }
      }
    } catch (e) {
      print('Error loading user profile image: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

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
      List<FirebaseTrendData> allTrends = [];
      for (final node in platformNodes) {
        final DataSnapshot snapshot = await database.child(node).get();
        if (snapshot.exists && snapshot.value != null) {
        final dynamic data = snapshot.value;
        if (data is List) {
            allTrends.addAll((data as List).map((item) {
            if (item == null) return null;
            if (item is Map) {
              return FirebaseTrendData.fromJson(item.map((key, value) => MapEntry(key.toString(), value)));
            }
            return null;
            }).whereType<FirebaseTrendData>());
        } else if (data is Map) {
          final Map<dynamic, dynamic> dataMap = data as Map<dynamic, dynamic>;
            allTrends.addAll(dataMap.entries.map((entry) {
            final trendData = entry.value;
            if (trendData == null) return null;
            if (trendData is Map) {
              return FirebaseTrendData.fromJson(trendData.map((key, value) => MapEntry(key.toString(), value)));
            }
            return null;
            }).whereType<FirebaseTrendData>());
        }
        }
      }
        // Ordina i trend per livello di trend (🔺 prima, poi ⏸)
      allTrends.sort((a, b) {
          if (a.trendLevel == '🔺' && b.trendLevel != '🔺') return -1;
          if (a.trendLevel != '🔺' && b.trendLevel == '🔺') return 1;
          return 0;
        });
      FirebaseTrendData? recommended = allTrends.isNotEmpty && allTrends.first.trendLevel == '🔺'
          ? allTrends.first
            : null;
      setState(() {
        _allTrends = allTrends;
          _recommendedTrend = recommended;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nel caricamento dei dati: $e')),
      );
    }
  }

    @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showLoading = _isLoading || !_minDelayPassed;
    // Filtra i trend per piattaforma selezionata
    final filteredTrends = _allTrends.where((trend) => trend.platform.toLowerCase() == _selectedPlatform.toLowerCase()).toList();
    FirebaseTrendData? selectedTrend = filteredTrends.isNotEmpty ? filteredTrends.first : null;
    
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
            // Main content area - no padding, content can scroll behind floating header
            SafeArea(
              child: showLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: Lottie.asset(
                              'assets/animations/analizeAI.json',
                              repeat: true,
                            ),
                          ),
                          SizedBox(height: 16),
                          ShaderMask(
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
                            child: Text(
                              'Loading AI data...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      physics: BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, 100, 0, 0), // Aggiunto padding superiore per la top bar
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPlatformDropdown(),
                          // Start chart animations when page loads
                          if (selectedTrend != null) ...[
                            FutureBuilder(
                              future: Future.delayed(Duration(milliseconds: 500)),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.done) {
                                  _viewsChartAnimationController.forward();
                                  _engagementChartAnimationController.forward();
                                  _viralityScoreAnimationController.forward();
                                  _typingAnimationController.forward();
                                }
                                return SizedBox.shrink();
                              },
                            ),
                          ],
                          if (selectedTrend != null) ...[
                            // Tutto il trend card (PageView, ecc.)
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.92,
                              child: PageView.builder(
                                controller: _trendPageController,
                                itemCount: filteredTrends.length,
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentTrendIndex = index;
                                  });
                                  // Start chart animations when scrolling between trends
                                  _viewsChartAnimationController.reset();
                                  _engagementChartAnimationController.reset();
                                  _viralityScoreAnimationController.reset();
                                  _typingAnimationController.reset();
                                  _viewsChartAnimationController.forward();
                                  _engagementChartAnimationController.forward();
                                  _viralityScoreAnimationController.forward();
                                  _typingAnimationController.forward();
                                  // Reset dei messaggi della chat quando si cambia trend
                                  _chatMessages.clear();
                                },
                                itemBuilder: (context, index) {
                                  final trend = filteredTrends[index];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Row: Trend name + Virality score
                                        Container(
                                          margin: EdgeInsets.only(bottom: 8),
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: theme.brightness == Brightness.dark
                                                ? const Color(0xFF23223A).withOpacity(0.85)
                                                : const Color(0xFFF5F4FF),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: const Color(0xFF6C63FF).withOpacity(0.10),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.03),
                                                blurRadius: 6,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      trend.trendName,
                                                      style: TextStyle(
                                                        fontSize: 22,
                                                        fontWeight: FontWeight.bold,
                                                        color: theme.textTheme.titleLarge?.color,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      softWrap: true,
                                                    ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  if (trend.viralityScore != null)
                                                    _buildViralityScoreSection(theme, trend.viralityScore!),
                                                ],
                                              ),
                                              SizedBox(height: 8),
                                              TypingTextWidget(
                                                text: trend.description,
                                                animation: _typingAnimation,
                                                overflow: TextOverflow.visible,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                                                  height: 1.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        // Hashtags
                                        if (trend.hashtags != null && trend.hashtags!.isNotEmpty)
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: trend.hashtags!.map((hashtag) => Container(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6C63FF).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                hashtag,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: const Color(0xFF6C63FF),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            )).toList(),
                                          ),
                                        SizedBox(height: 10),
                                        if (trend.growthRate != null && trend.growthRate!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 10, bottom: 2),
                                            child: _buildGrowthRateSection(theme, trend.growthRate),
                                          ),
                                        SizedBox(height: 18),
                                        // Analytics chart
                                        if (trend.dataPoints.isNotEmpty)
                                          Expanded(
                                            child: _buildEngagementChart(theme, trend),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          // Sezione fissa in fondo: indicatori di pagina e disclaimer
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: selectedTrend != null ? Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF00F2EA), Color(0xFFFF0050)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0xFF00F2EA).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                  BoxShadow(
                                    color: Color(0xFFFF0050).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _selectedPlatform.toLowerCase() == 'instagram'
                                  ? Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFFC13584), // Instagram gradient start
                                            Color(0xFFE1306C), // Instagram gradient middle
                                            Color(0xFFF56040), // Instagram gradient end
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ElevatedButton.icon(
                                                                                  onPressed: () {
                                            final currentTrend = filteredTrends[_currentTrendIndex];
                                            final trendName = currentTrend.trendName.trim();
                                            final encodedTrendName = Uri.encodeComponent(trendName);
                                            final hashtagName = trendName.replaceAll(' ', '').toLowerCase().replaceAll('#', '');
                                            final url = 'https://www.instagram.com/explore/tags/$hashtagName/';
                                            print('DEBUG Instagram - Original trendName: "$trendName"');
                                            print('DEBUG Instagram - Processed hashtagName: "$hashtagName"');
                                            print('DEBUG Instagram - Final URL: "$url"');
                                            _openSocialMedia(url);
                                          },
                                        icon: Icon(Icons.open_in_new, size: 18),
                                        label: Text('See on $_selectedPlatform'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    )
                                  : _selectedPlatform.toLowerCase() == 'tiktok'
                                      ? Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF00F2EA), // TikTok turchese
                                                Color(0xFFFF0050), // TikTok rosa
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF00F2EA).withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                              BoxShadow(
                                                color: const Color(0xFFFF0050).withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              final currentTrend = filteredTrends[_currentTrendIndex];
                                              final trendName = currentTrend.trendName.trim();
                                              final encodedTrendName = Uri.encodeComponent(trendName);
                                              final url = 'https://www.tiktok.com/search?q=$encodedTrendName&t=';
                                              _openSocialMedia(url);
                                            },
                                            icon: Icon(Icons.open_in_new, size: 18),
                                            label: Text('See on $_selectedPlatform'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              padding: EdgeInsets.symmetric(vertical: 16),
                                              textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        )
                                      : ElevatedButton.icon(
                                          onPressed: () {
                                            final currentTrend = filteredTrends[_currentTrendIndex];
                                            final trendName = currentTrend.trendName.trim();
                                            final encodedTrendName = Uri.encodeComponent(trendName);
                                            String url;
                                            switch (_selectedPlatform.toLowerCase()) {
                                              case 'facebook':
                                                url = 'https://www.facebook.com/search/posts?q=$encodedTrendName';
                                                break;
                                              case 'twitter':
                                                url = 'https://x.com/search?q=$encodedTrendName&src=typed_query&f=top';
                                                break;
                                              case 'threads':
                                                url = 'https://www.threads.com/search?q=$encodedTrendName&serp_type=default&hl=it';
                                                break;
                                              case 'youtube':
                                                final encodedTrendName = Uri.encodeComponent(trendName);
                                                url = 'https://www.youtube.com/results?search_query=$encodedTrendName';
                                                break;
                                              default:
                                                url = 'https://www.tiktok.com/search?q=$encodedTrendName&t=';
                                            }
                                            _openSocialMedia(url);
                                          },
                                          icon: Icon(Icons.open_in_new, size: 18),
                                          label: Text('See on $_selectedPlatform'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                _selectedPlatform.toLowerCase() == 'youtube'
                                                    ? Colors.red
                                                    : _selectedPlatform.toLowerCase() == 'facebook'
                                                        ? Color(0xFF1877F2)
                                                        : _selectedPlatform.toLowerCase() == 'twitter' || _selectedPlatform.toLowerCase() == 'threads'
                                                            ? Colors.black
                                                            : const Color(0xFF6C63FF),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: EdgeInsets.symmetric(vertical: 16),
                                            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                            ) : SizedBox.shrink(),
                          ),
                          
                          // Bottone per aprire la chat IA
                          if (selectedTrend != null)
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                                              child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                                        const Color(0xFF764ba2), // Colore finale: viola al 100%
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ElevatedButton.icon(
                                    onPressed: () => _showAIChat(selectedTrend!),
                                    icon: Icon(Icons.psychology, size: 18),
                                    label: Text('Chat with AI about this trend'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                            ),
                          if (filteredTrends.length > 1)
                            Container(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(filteredTrends.length, (index) {
                                  return Container(
                                    width: 8,
                                    height: 8,
                                    margin: EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: index == _currentTrendIndex 
                                          ? const Color(0xFF6C63FF)
                                          : theme.colorScheme.outline.withOpacity(0.3),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 18, top: 0),
                            child: Text(
                              'These trend searches were performed by AI and may contain inaccuracies, misinterpretations, or estimation errors.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.55),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
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
                      Icons.psychology,
                      size: 14,
                      color: const Color(0xFF6C63FF),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI',
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

  Widget _buildRecommendedTrend() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF6C63FF).withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.trending_up,
                      color: const Color(0xFF6C63FF),
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
              Text(
                    'Recommended',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
                ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _recommendedTrend!.trendLevel,
                  style: TextStyle(
                        color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Hot',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            _recommendedTrend!.trendName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _recommendedTrend!.description,
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getPlatformColor(_recommendedTrend!.platform).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _getPlatformWidget(_recommendedTrend!.platform, 16),
                    SizedBox(width: 6),
                    Text(
                  _recommendedTrend!.platform,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getPlatformColor(_recommendedTrend!.platform),
                  ),
                ),
                  ],
              ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCategoryColor(_recommendedTrend!.category).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _recommendedTrend!.category,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                    color: _getCategoryColor(_recommendedTrend!.category),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingTopicsList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: const Color(0xFF6C63FF),
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
              Text(
                    'All Trends',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
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
                child: Text(
                  '${_allTrends.length}',
                  style: TextStyle(
                    color: const Color(0xFF6C63FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
          ListView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 20),
            itemCount: _allTrends.length,
            itemBuilder: (context, index) {
              final trend = _allTrends[index];
              return _buildTrendCard(trend);
            },
          ),
        ],
    );
  }

    Widget _buildTrendCard(FirebaseTrendData trend) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showTrendDetails(trend),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
        children: [
          Container(
                      width: 48,
                      height: 48,
            decoration: BoxDecoration(
              color: _getPlatformColor(trend.platform).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
                        child: _getPlatformWidget(trend.platform, 24),
            ),
          ),
          SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                            trend.trendName,
                  style: TextStyle(
                              fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                          SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                                  color: trend.trendLevel == '🔺' 
                                      ? Colors.green.withOpacity(0.1) 
                                      : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                                    Text(
                                      trend.trendLevel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: trend.trendLevel == '🔺' ? Colors.green : Colors.orange,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                          Text(
                                      trend.trendLevel == '🔺' ? 'Rising' : 'Stable',
                            style: TextStyle(
                                        fontSize: 12,
                              fontWeight: FontWeight.w600,
                                        color: trend.trendLevel == '🔺' ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getCategoryColor(trend.category).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  trend.category,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _getCategoryColor(trend.category),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.4),
                    ),
                  ],
                ),
                
                // Growth Rate o Description come prima voce
                if (trend.growthRate != null && trend.growthRate!.isNotEmpty) ...[
                  SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.trending_up, color: const Color(0xFF6C63FF), size: 16),
                            SizedBox(width: 6),
                            Text(
                              trend.growthRate!,
                              style: TextStyle(
                                color: const Color(0xFF6C63FF),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(height: 18),
                  _buildDetailSection(
                    theme,
                    title: 'Description',
                    content: trend.description,
                    icon: Icons.description,
                  ),
                ],
                
                if (trend.hashtags != null && trend.hashtags!.isNotEmpty) ...[
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: trend.hashtags!.map((hashtag) => Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        hashtag,
                        style: TextStyle(
                        fontSize: 11,
                          color: const Color(0xFF6C63FF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTrendDetails(FirebaseTrendData trend) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
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
          child: Column(
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
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with platform icon and title
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _getPlatformColor(trend.platform).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: _getPlatformWidget(trend.platform, 28),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trend.trendName,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: theme.textTheme.titleLarge?.color,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: trend.trendLevel == '🔺' 
                                            ? Colors.green.withOpacity(0.1) 
                                            : Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            trend.trendLevel,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: trend.trendLevel == '🔺' ? Colors.green : Colors.orange,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            trend.trendLevel == '🔺' ? 'Rising' : 'Stable',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: trend.trendLevel == '🔺' ? Colors.green : Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _getCategoryColor(trend.category).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        trend.category,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _getCategoryColor(trend.category),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Growth Rate come prima voce
                      if (trend.growthRate != null) ...[
                        SizedBox(height: 18),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C63FF).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.trending_up, color: const Color(0xFF6C63FF), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    trend.growthRate!,
                                    style: TextStyle(
                                      color: const Color(0xFF6C63FF),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: 18),
                      // Description section
                      _buildDetailSection(
                        theme,
                        title: 'Description',
                        content: trend.description,
                        icon: Icons.description,
                      ),
                      
                      SizedBox(height: 24),
                      
                      // Growth rate section
                      if (trend.growthRate != null) ...[
                        SizedBox(height: 24),
                        _buildDetailSection(
                          theme,
                          title: 'Growth Rate',
                          content: trend.growthRate!,
                          icon: Icons.trending_up,
                        ),
                      ],
                      
                      // Virality score section
                      if (trend.viralityScore != null) ...[
                        SizedBox(height: 24),
                        _buildViralityScoreSection(theme, trend.viralityScore!),
                      ],
                      
                      // Engagement chart section
                      if (trend.dataPoints.isNotEmpty) ...[
                        SizedBox(height: 24),
                        _buildEngagementChart(theme, trend),
                      ],
                      
                      if (trend.hashtags != null && trend.hashtags!.isNotEmpty) ...[
                        SizedBox(height: 24),
                        _buildHashtagsSection(theme, trend.hashtags!),
                      ],
                      
                      SizedBox(height: 32),
                      // Bottone per aprire il trend sulla piattaforma
                      if (_getTrendUrl(trend) != null) ...[
                        SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final url = _getTrendUrl(trend);
                              if (url != null && await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: Icon(Icons.open_in_new, color: Colors.white),
                            label: Text('Open on ' + trend.platform, style: TextStyle(fontWeight: FontWeight.bold)),
                            style: _selectedPlatform.toLowerCase() == 'instagram'
                                ? ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                                    elevation: 0,
                              padding: EdgeInsets.symmetric(vertical: 16),
                                    textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                                  ).copyWith(
                                    backgroundColor: MaterialStateProperty.all(Colors.transparent),
                                    foregroundColor: MaterialStateProperty.all(Colors.white),
                                    shadowColor: MaterialStateProperty.all(Colors.transparent),
                                  )
                                : ElevatedButton.styleFrom(
                                    backgroundColor:
                                        _selectedPlatform.toLowerCase() == 'youtube'
                                            ? Colors.red
                                            : _selectedPlatform.toLowerCase() == 'facebook'
                                                ? Color(0xFF1877F2)
                                                : _selectedPlatform.toLowerCase() == 'twitter' || _selectedPlatform.toLowerCase() == 'threads'
                                                    ? Colors.black
                                                    : _selectedPlatform.toLowerCase() == 'tiktok'
                                                        ? const LinearGradient(
                                                            colors: [
                                                              Color(0xFF000000),
                                                              Color(0xFFFF0050),
                                                            ],
                                                            begin: Alignment.topLeft,
                                                            end: Alignment.bottomRight,
                                                          ).colors.first // fallback nero
                                                        : const Color(0xFF6C63FF),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],

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
  
  Widget _buildDetailSection(ThemeData theme, {
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF6C63FF),
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.titleMedium?.color,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        title == 'Description' 
          ? TypingTextWidget(
              text: content,
              animation: _typingAnimation,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: 15,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                height: 1.6,
              ),
            )
          : Text(
              content,
              style: TextStyle(
                fontSize: 15,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                height: 1.6,
              ),
            ),
      ],
    );
  }
  
  Widget _buildHashtagsSection(ThemeData theme, List<String> hashtags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.tag,
                color: const Color(0xFF6C63FF),
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Related hashtags',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.titleMedium?.color,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: hashtags.map((hashtag) => Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Text(
              hashtag,
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF6C63FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
  
  Widget _buildViralityScoreSection(ThemeData theme, int viralityScore) {
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.25),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(0.18),
            width: 2,
          ),
        ),
        child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
              width: 44,
              height: 44,
                  child: AnimatedBuilder(
                    animation: _viralityScoreAnimation,
                    builder: (context, child) {
                      return CircularProgressIndicator(
                        value: (viralityScore / 100) * _viralityScoreAnimation.value,
                        strokeWidth: 6.5,
                        backgroundColor: const Color(0xFF6C63FF).withOpacity(0.10),
                        valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF6C63FF)),
                      );
                    },
                  ),
                ),
                Text(
                  '$viralityScore',
                  style: TextStyle(
                fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6C63FF),
                shadows: [
                  Shadow(
                    color: Colors.white.withOpacity(0.7),
                    blurRadius: 2,
                ),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEngagementChart(ThemeData theme, FirebaseTrendData trend) {
    final hasEngagementData = trend.dataPoints.any((point) => point.engagementRate != null);
    final hasViewsData = trend.dataPoints.any((point) => point.dailyViews != null);
    if (!hasEngagementData && !hasViewsData) {
      return Center(
        child: Text(
          'No analytics data available',
              style: TextStyle(
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
        ),
      );
    }
    final dateLabels = trend.dataPoints.map((e) => e.date).toList();
    // Preparo i dati per le colonne
    final List<double?> views = trend.dataPoints.map((e) => e.dailyViews != null ? (e.dailyViews! / 1000) : null).toList();
    final List<double?> engagement = trend.dataPoints.map((e) => e.engagementRate).toList();
    // Calcolo il massimo per lo scaling
    final allViews = views.whereType<double>().toList();
    final allEngagement = engagement.whereType<double>().toList();
    double maxViews = allViews.isNotEmpty ? allViews.reduce((a, b) => a > b ? a : b) : 1;
    double maxEngagement = allEngagement.isNotEmpty ? allEngagement.reduce((a, b) => a > b ? a : b) : 1;
    if (maxViews < 1) maxViews = 1;
    if (maxEngagement < 1) maxEngagement = 1;
    // Costruisco le colonne per views (senza animazione qui)
    List<BarChartGroupData> barGroupsViews = [];
    for (int i = 0; i < trend.dataPoints.length; i++) {
      if (views[i] != null) {
        barGroupsViews.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: views[i]!,
              color: const Color(0xFF6C63FF),
              width: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ));
      }
    }
    // Colonne per engagement (senza animazione qui)
    List<BarChartGroupData> barGroupsEngagement = [];
    for (int i = 0; i < trend.dataPoints.length; i++) {
      if (engagement[i] != null) {
        barGroupsEngagement.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: engagement[i]!,
              color: Colors.orange,
              width: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasViewsData) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
                'Daily Views',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SizedBox(
              height: 140,
              child: AnimatedBuilder(
                animation: _viewsChartAnimation,
                builder: (context, child) {
                  // Costruisco le colonne per views con animazione
                  List<BarChartGroupData> animatedBarGroupsViews = [];
                  for (int i = 0; i < trend.dataPoints.length; i++) {
                    if (views[i] != null) {
                      animatedBarGroupsViews.add(BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: views[i]! * _viewsChartAnimation.value,
                            color: const Color(0xFF6C63FF),
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ));
                    }
                  }
                  
                  return BarChart(
                    BarChartData(
                      maxY: maxViews * 1.15,
                      barGroups: animatedBarGroupsViews,
                      groupsSpace: 18,
                      borderData: FlBorderData(
              show: true,
                        border: const Border(
                          left: BorderSide(color: Color(0xFFBDBDBD), width: 1),
                          bottom: BorderSide(color: Color(0xFFBDBDBD), width: 1),
                          right: BorderSide.none,
                          top: BorderSide.none,
                        ),
                      ),
                      gridData: FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: TextStyle(fontSize: 8),
                              );
                            },
                            reservedSize: 28,
                          ),
                        ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < dateLabels.length) {
                                final isEven = idx % 2 == 0;
                      return Padding(
                                  padding: EdgeInsets.only(top: isEven ? 0 : 12, bottom: isEven ? 12 : 0),
                        child: Text(
                                    dateLabels[idx],
                                    style: TextStyle(fontSize: 10),
                                    textAlign: TextAlign.center,
                        ),
                      );
                    }
                              return SizedBox.shrink();
                            },
                            reservedSize: 28,
                          ),
                        ),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              rod.toY.toStringAsFixed(2),
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: 18),
        ],
        if (hasEngagementData) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
                'Engagement Rate (%)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SizedBox(
              height: 140,
              child: AnimatedBuilder(
                animation: _engagementChartAnimation,
                builder: (context, child) {
                  // Costruisco le colonne per engagement con animazione
                  List<BarChartGroupData> animatedBarGroupsEngagement = [];
                  for (int i = 0; i < trend.dataPoints.length; i++) {
                    if (engagement[i] != null) {
                      animatedBarGroupsEngagement.add(BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: engagement[i]! * _engagementChartAnimation.value,
                            color: const Color(0xFF667eea),
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ));
                    }
                  }
                  
                  return BarChart(
                    BarChartData(
                      maxY: maxEngagement * 1.15,
                      barGroups: animatedBarGroupsEngagement,
                      groupsSpace: 18,
                      borderData: FlBorderData(
          show: true,
                        border: const Border(
                          left: BorderSide(color: Color(0xFFBDBDBD), width: 1),
                          bottom: BorderSide(color: Color(0xFFBDBDBD), width: 1),
                          right: BorderSide.none,
                          top: BorderSide.none,
                        ),
                      ),
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: TextStyle(fontSize: 8),
                            );
                          },
                          reservedSize: 28,
                        ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx >= 0 && idx < dateLabels.length) {
                              final isEven = idx % 2 == 0;
                  return Padding(
                                padding: EdgeInsets.only(top: isEven ? 0.0 : 12.0, bottom: isEven ? 12.0 : 0.0),
                    child: Text(
                                  dateLabels[idx],
                                  style: TextStyle(fontSize: 10),
                                  textAlign: TextAlign.center,
                    ),
                  );
                }
                            return SizedBox.shrink();
                          },
                          reservedSize: 28,
                        ),
                      ),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              rod.toY.toStringAsFixed(2),
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            );
                          },
            ),
          ),
        ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform) {
      case "TikTok":
        return Colors.black;
      case "Instagram":
        return Colors.purple;
      case "YouTube":
        return Colors.red;
      case "Twitter":
        return Colors.blue;
      case "Facebook":
        return Color(0xFF1877F2);
      case "Threads":
        return Colors.black;
      default:
        return Colors.grey;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case "Viral audio":
        return Colors.purple;
      case "Entertainment":
        return Colors.orange;
      case "Music":
        return Colors.red;
      case "Gaming":
        return Colors.green;
      case "Reels":
        return Colors.pink;
      case "Fashion":
        return Colors.indigo;
      case "Video":
        return Colors.blue;
      case "Engagement":
        return Colors.teal;
      case "Ad Format":
        return Colors.amber;
      case "Feature":
        return Colors.cyan;
      case "Civic":
        return Colors.brown;
      case "AI":
        return Colors.deepPurple;
      case "Topic":
        return Colors.lime;
      default:
        return Colors.grey;
    }
  }

  Widget _getPlatformWidget(String platform, double size) {
    switch (platform) {
      case "TikTok":
        return Image.asset(
          'assets/loghi/logo_tiktok.png',
          width: size,
          height: size,
        );
      case "Instagram":
        return Image.asset(
          'assets/loghi/logo_insta.png',
          width: size,
          height: size,
        );
      case "YouTube":
        return Image.asset(
          'assets/loghi/logo_yt.png',
          width: size,
          height: size,
        );
      case "Twitter":
        return Image.asset(
          'assets/loghi/logo_twitter.png',
          width: size,
          height: size,
        );
      case "Facebook":
        return Image.asset(
          'assets/loghi/logo_facebook.png',
          width: size,
          height: size,
        );
      case "Threads":
        return Image.asset(
          'assets/loghi/threads_logo.png',
          width: size,
          height: size,
        );
      default:
        return Icon(
          Icons.trending_up,
          size: size,
          color: _getPlatformColor(platform),
        );
    }
  }

  String? _getTrendUrl(FirebaseTrendData trend) {
    final name = trend.trendName.trim().replaceAll('#', '').replaceAll(' ', '%20').replaceAll("'", '');
    switch (trend.platform.toLowerCase()) {
      case 'tiktok':
        return 'https://www.tiktok.com/search?q=$name&t=';
      case 'facebook':
        return 'https://www.facebook.com/search/posts?q=$name';
      case 'twitter':
      case 'twitter/x':
      case 'x':
        return 'https://x.com/search?q=$name&src=typed_query&f=top';
      case 'threads':
        return 'https://www.threads.com/search?q=$name&serp_type=default&hl=it';
      case 'instagram':
        final processedName = name.replaceAll('%20', '').toLowerCase().replaceAll('#', '');
        final url = 'https://www.instagram.com/explore/tags/$processedName/';
        print('DEBUG Instagram _getTrendUrl - Original name: "$name"');
        print('DEBUG Instagram _getTrendUrl - Processed name: "$processedName"');
        print('DEBUG Instagram _getTrendUrl - Final URL: "$url"');
        return url;
      case 'youtube':
        return 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(name)}';
      default:
        return null;
    }
  }

  Widget _buildPlatformDropdown() {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.08),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showPlatformDropdown = !_showPlatformDropdown;
                if (_showPlatformDropdown) {
                  _platformAnimationController.forward();
                } else {
                  _platformAnimationController.reverse();
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _getPlatformWidget(_selectedPlatform, 24),
                      SizedBox(width: 12),
                      Text(
                        _selectedPlatform,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.titleLarge?.color,
                        ),
                      ),
                    ],
                  ),
                  AnimatedIcon(
                    icon: AnimatedIcons.menu_close,
                    progress: _platformAnimation,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _platformAnimation,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.08),
                    width: 1.2,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _buildPlatformOption('TikTok'),
                  _buildPlatformOption('YouTube'),
                  _buildPlatformOption('Instagram'),
                  _buildPlatformOption('Facebook'),
                  _buildPlatformOption('Twitter'),
                  _buildPlatformOption('Threads'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformOption(String platform) {
    final theme = Theme.of(context);
    final isSelected = _selectedPlatform == platform;
    return InkWell(
              onTap: () {
          setState(() {
            _selectedPlatform = platform;
            _showPlatformDropdown = false;
            _platformAnimationController.reverse();
            _currentTrendIndex = 0; // Reset to first trend
            _trendPageController.animateToPage(0, 
              duration: Duration(milliseconds: 300), 
              curve: Curves.easeInOut);
            // Start chart animations when platform changes
            _viewsChartAnimationController.reset();
            _engagementChartAnimationController.reset();
            _viralityScoreAnimationController.reset();
            _typingAnimationController.reset();
            _viewsChartAnimationController.forward();
            _engagementChartAnimationController.forward();
            _viralityScoreAnimationController.forward();
            _typingAnimationController.forward();
            // Reset dei messaggi della chat quando si cambia piattaforma
            _chatMessages.clear();
          });
        },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.05),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            _getPlatformWidget(platform, 20),
            SizedBox(width: 12),
            Text(
              platform,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected 
                    ? theme.colorScheme.primary
                    : theme.textTheme.bodyMedium?.color,
              ),
            ),
            Spacer(),
            if (isSelected)
              Icon(
                Icons.check,
                size: 20,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  void _openSocialMedia(String url) async {
          // Gestione speciale per TikTok
      if (url.contains('tiktok.com')) {
        await _openTikTokWithFallback(url);
        return;
      }
      
      // Gestione speciale per Threads
      if (url.contains('threads.com')) {
        await _openThreadsWithFallback(url);
        return;
      }
      
      // Gestione speciale per YouTube
      if (url.contains('youtube.com')) {
        await _openYouTubeWithFallback(url);
        return;
      }
      
      // Gestione speciale per Facebook
      if (url.contains('facebook.com')) {
        await _openFacebookWithFallback(url);
        return;
      }
      
      // Gestione normale per altre piattaforme
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open URL: $url')),
      );
    }
  }

  // Metodo speciale per TikTok che tenta prima l'app e poi il web
  Future<void> _openTikTokWithFallback(String url) async {
    try {
      // Estrai la query di ricerca dall'URL
      final uri = Uri.parse(url);
      final query = uri.queryParameters['q'];
      
      if (query != null) {
        // COPIA IMMEDIATAMENTE il titolo del trend negli appunti
        await _copyTrendTitleToClipboard(query);
        
        // Mostra subito il messaggio di conferma
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.copy, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trend title copied! Opening TikTok...',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        
        // Prova diversi schemi URL per TikTok che potrebbero funzionare
        final List<String> tiktokSchemes = [
          'tiktok://search?q=${Uri.encodeComponent(query)}',
          'tiktok://search?query=${Uri.encodeComponent(query)}',
          'tiktok://search?search=${Uri.encodeComponent(query)}',
          'tiktok://search?term=${Uri.encodeComponent(query)}',
          'tiktok://search?keyword=${Uri.encodeComponent(query)}',
          'tiktok://search?text=${Uri.encodeComponent(query)}',
          // Prova anche schemi alternativi
          'tiktok://search/${Uri.encodeComponent(query)}',
          'tiktok://search?q=${Uri.encodeComponent(query)}&t=',
          'tiktok://search?q=${Uri.encodeComponent(query)}&lang=en',
        ];
        
        bool appOpened = false;
        
        // Prova ogni schema fino a che uno funziona
        for (String scheme in tiktokSchemes) {
          if (await canLaunchUrl(Uri.parse(scheme))) {
            try {
              final launched = await launchUrl(
                Uri.parse(scheme),
                mode: LaunchMode.externalApplication,
              );
              
              if (launched) {
                appOpened = true;
                print('TikTok app opened successfully with scheme: $scheme');
                break;
              }
            } catch (e) {
              print('Failed to open TikTok with scheme: $scheme - $e');
              continue;
            }
          }
        }
        
        // Se nessuno schema funziona, prova ad aprire solo l'app TikTok
        if (!appOpened) {
          try {
            if (await canLaunchUrl(Uri.parse('tiktok://'))) {
              await launchUrl(Uri.parse('tiktok://'), mode: LaunchMode.externalApplication);
              appOpened = true;
              print('TikTok app opened without search parameters');
            }
          } catch (e) {
            print('Failed to open TikTok app: $e');
          }
        }
        
        if (appOpened) {
          // Se l'app si apre con successo, aspetta un po' e poi apri anche il web come fallback
          await Future.delayed(Duration(milliseconds: 1500));
        }
      }
      
      // Sempre apri il web come fallback o in parallelo
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      
    } catch (e) {
      // Se fallisce tutto, mostra un messaggio di errore
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open TikTok. Please make sure the app is installed.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Metodo speciale per Threads che tenta prima l'app e poi il web
  Future<void> _openThreadsWithFallback(String url) async {
    try {
      // Estrai la query di ricerca dall'URL
      final uri = Uri.parse(url);
      final query = uri.queryParameters['q'];
      
      if (query != null) {
        // COPIA IMMEDIATAMENTE il titolo del trend negli appunti
        await _copyTrendTitleToClipboard(query);
        

        
        // Prova diversi schemi URL per Threads che potrebbero funzionare
        final List<String> threadsSchemes = [
          'threads://search?q=${Uri.encodeComponent(query)}',
          'threads://search?query=${Uri.encodeComponent(query)}',
          'threads://search?search=${Uri.encodeComponent(query)}',
          'threads://search?term=${Uri.encodeComponent(query)}',
          'threads://search?keyword=${Uri.encodeComponent(query)}',
          'threads://search?text=${Uri.encodeComponent(query)}',
          // Prova anche schemi alternativi
          'threads://search/${Uri.encodeComponent(query)}',
          'threads://search?q=${Uri.encodeComponent(query)}&hl=it',
          'threads://search?q=${Uri.encodeComponent(query)}&serp_type=default',
        ];
        
        bool appOpened = false;
        
        // Prova ogni schema fino a che uno funziona
        for (String scheme in threadsSchemes) {
          if (await canLaunchUrl(Uri.parse(scheme))) {
            try {
              final launched = await launchUrl(
                Uri.parse(scheme),
                mode: LaunchMode.externalApplication,
              );
              
              if (launched) {
                appOpened = true;
                print('Threads app opened successfully with scheme: $scheme');
                break;
              }
            } catch (e) {
              print('Failed to open Threads with scheme: $scheme - $e');
              continue;
            }
          }
        }
        
        // Se nessuno schema funziona, prova ad aprire solo l'app Threads
        if (!appOpened) {
          try {
            if (await canLaunchUrl(Uri.parse('threads://'))) {
              await launchUrl(Uri.parse('threads://'), mode: LaunchMode.externalApplication);
              appOpened = true;
              print('Threads app opened without search parameters');
            }
          } catch (e) {
            print('Failed to open Threads app: $e');
          }
        }
        
        if (appOpened) {
          // Se l'app si apre con successo, aspetta un po' e poi apri anche il web come fallback
          await Future.delayed(Duration(milliseconds: 1500));
        }
      }
      
      // Sempre apri il web come fallback o in parallelo
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      
    } catch (e) {
      // Se fallisce tutto, mostra un messaggio di errore
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open Threads. Please make sure the app is installed.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Metodo speciale per YouTube che tenta prima l'app e poi il web
  Future<void> _openYouTubeWithFallback(String url) async {
    try {
      // Estrai la query di ricerca dall'URL
      final uri = Uri.parse(url);
      final query = uri.queryParameters['search_query'];
      
      if (query != null) {
        // COPIA IMMEDIATAMENTE il titolo del trend negli appunti
        await _copyTrendTitleToClipboard(query);
        

        
        // Usa direttamente LaunchMode.platformDefault per mostrare la tendina di sistema
        // Questo permette all'utente di scegliere tra app YouTube e browser
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(
            Uri.parse(url), 
            mode: LaunchMode.platformDefault, // Mostra tendina di scelta app/browser
          );
        }
        
      } else {
        // Se non c'è query, prova ad aprire solo l'app YouTube
        try {
          if (await canLaunchUrl(Uri.parse('youtube://'))) {
            await launchUrl(Uri.parse('youtube://'), mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          print('Failed to open YouTube app: $e');
        }
      }
      
    } catch (e) {
      // Se fallisce tutto, mostra un messaggio di errore
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open YouTube. Please make sure the app is installed.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Metodo speciale per Facebook che tenta prima l'app e poi il web
  Future<void> _openFacebookWithFallback(String url) async {
    try {
      // Estrai la query di ricerca dall'URL
      final uri = Uri.parse(url);
      final query = uri.queryParameters['q'];
      
      if (query != null) {
        // COPIA IMMEDIATAMENTE il titolo del trend negli appunti
        await _copyTrendTitleToClipboard(query);
        
        // Mostra subito il messaggio di conferma
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.copy, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trend title copied! Opening Facebook...',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Color(0xFF1877F2), // Colore Facebook blu
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        
        // Prova diversi schemi URL per Facebook che potrebbero funzionare
        final List<String> facebookSchemes = [
          'fb://search?q=${Uri.encodeComponent(query)}',
          'fb://search?query=${Uri.encodeComponent(query)}',
          'fb://search?search=${Uri.encodeComponent(query)}',
          'fb://search?term=${Uri.encodeComponent(query)}',
          'fb://search?keyword=${Uri.encodeComponent(query)}',
          'fb://search?text=${Uri.encodeComponent(query)}',
          // Schemi alternativi per Facebook
          'fb://search/${Uri.encodeComponent(query)}',
          'fb://search?q=${Uri.encodeComponent(query)}&t=',
          'fb://search?q=${Uri.encodeComponent(query)}&f=top',
        ];
        
        bool appOpened = false;
        
        // Prova ogni schema fino a che uno funziona
        for (String scheme in facebookSchemes) {
          if (await canLaunchUrl(Uri.parse(scheme))) {
            try {
              final launched = await launchUrl(
                Uri.parse(scheme),
                mode: LaunchMode.externalApplication,
              );
              
              if (launched) {
                appOpened = true;
                print('Facebook app opened successfully with scheme: $scheme');
                break;
              }
            } catch (e) {
              print('Failed to open Facebook with scheme: $scheme - $e');
              continue;
            }
          }
        }
        
        // Se nessuno schema funziona, prova ad aprire solo l'app Facebook
        if (!appOpened) {
          try {
            if (await canLaunchUrl(Uri.parse('fb://'))) {
              await launchUrl(Uri.parse('fb://'), mode: LaunchMode.externalApplication);
              appOpened = true;
              print('Facebook app opened without search parameters');
            }
          } catch (e) {
            print('Failed to open Facebook app: $e');
          }
        }
        
        if (appOpened) {
          // Se l'app si apre con successo, aspetta un po' e poi apri anche il web come fallback
          await Future.delayed(Duration(milliseconds: 1500));
        }
      }
      
      // Sempre apri il web come fallback o in parallelo
      // Usa LaunchMode.platformDefault per mostrare la tendina di sistema
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url), 
          mode: LaunchMode.platformDefault, // Mostra tendina di scelta app/browser
        );
      }
      
    } catch (e) {
      // Se fallisce tutto, mostra un messaggio di errore
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open Facebook. Please make sure the app is installed.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Metodo per copiare il titolo del trend negli appunti
  Future<void> _copyTrendTitleToClipboard(String title) async {
    try {
      await Clipboard.setData(ClipboardData(text: title));
      print('Trend title copied to clipboard: $title');
    } catch (e) {
      print('Failed to copy trend title to clipboard: $e');
    }
  }

  Widget _buildGrowthRateSection(ThemeData theme, String? growthRate) {
    if (growthRate == null || growthRate.isEmpty) return SizedBox.shrink();
    // Parsing: accetta formati tipo '+3.2%' o '-1.1%'
    final isPositive = growthRate.trim().startsWith('+');
    final isNegative = growthRate.trim().startsWith('-');
    final color = isPositive
        ? Colors.green
        : isNegative
            ? Colors.red
            : const Color(0xFF6C63FF);
    final icon = isPositive
        ? Icons.arrow_drop_up
        : isNegative
            ? Icons.arrow_drop_down
            : Icons.trending_flat;
    return Container(
      margin: EdgeInsets.only(left: 12),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 2),
          Text(
            growthRate,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // Metodo per analizzare il trend con l'IA
  Future<void> _analyzeTrendWithAI(FirebaseTrendData trend) async {
    setState(() {
      _isAIAnalyzing = true;
      _isChatLoading = true;
    });

    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }

    try {
      // Ottieni la lingua dell'utente da Firebase
      final language = await _getLanguage();
      
      // Usa il servizio ChatGPT per l'analisi
      final aiResponse = await _chatGptService.analyzeTrendData(
        trend,
        'Analyze this trend and provide insights',
        'initial',
        language,
      );
      
      // Estrai le domande suggerite dal testo dell'IA
      final extractedData = _extractSuggestedQuestionsFromText(fixEncoding(aiResponse));
      final cleanText = extractedData['cleanText'] as String;
      final suggestedQuestions = extractedData['questions'] as List<String>;
      
      setState(() {
        _lastAIAnalysis = cleanText;
        _chatMessages.add(ChatMessage(
          text: cleanText,
          isUser: false,
          timestamp: DateTime.now(),
          suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
        ));
        _isAIAnalyzing = false;
        _isChatLoading = false;
      });
      
      // Sottrai crediti per utenti non premium
      await _subtractCredits();
      
      // Aggiorna anche la tendina se è aperta
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      }
      
      // Non scrollare automaticamente: lascia l'utente vedere la risposta dall'inizio
    } catch (e) {
      setState(() {
        _chatMessages.add(ChatMessage(
          text: 'Sorry, I encountered an error while analyzing the trend. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isAIAnalyzing = false;
        _isChatLoading = false;
      });
      
      // Non scrollare automaticamente: lascia l'utente vedere la risposta dall'inizio
    }
  }

  // Metodo per inviare un messaggio all'IA
  Future<void> _sendMessageToAI(String message) async {
    if (message.trim().isEmpty) return;

    // Aggiungi il messaggio dell'utente
    setState(() {
      _chatMessages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });

    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }

    _messageController.clear();
    // Non scrollare automaticamente: lascia l'utente vedere la risposta dall'inizio

    // Imposta lo stato di caricamento
    setState(() {
      _isAIAnalyzing = true;
      _isChatLoading = true;
    });

    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }

    try {
      // Ottieni il trend corrente per il contesto
      final filteredTrends = _allTrends.where((trend) => trend.platform.toLowerCase() == _selectedPlatform.toLowerCase()).toList();
      final currentTrend = filteredTrends.isNotEmpty && _currentTrendIndex < filteredTrends.length 
          ? filteredTrends[_currentTrendIndex] 
          : null;
      
      if (currentTrend == null) {
        throw Exception('No trend available for analysis');
      }
      
      // Ottieni la lingua dell'utente da Firebase
      final language = await _getLanguage();
      
      // Usa il servizio ChatGPT per la risposta
      final aiResponse = await _chatGptService.analyzeTrendData(
        currentTrend,
        message,
        'chat',
        language,
      );
      
      // Estrai le domande suggerite dal testo dell'IA
      final extractedData = _extractSuggestedQuestionsFromText(fixEncoding(aiResponse));
      final cleanText = extractedData['cleanText'] as String;
      final suggestedQuestions = extractedData['questions'] as List<String>;
      
      setState(() {
        _chatMessages.add(ChatMessage(
          text: cleanText,
          isUser: false,
          timestamp: DateTime.now(),
          suggestedQuestions: suggestedQuestions.isNotEmpty ? suggestedQuestions : null,
        ));
        _isAIAnalyzing = false;
        _isChatLoading = false;
      });
      
      // Sottrai crediti per utenti non premium
      await _subtractCredits();
      
      // Aggiorna anche la tendina se è aperta
      if (_sheetStateSetter != null) {
        _sheetStateSetter!(() {});
      }
      
      // Non scrollare automaticamente: lascia l'utente vedere la risposta dall'inizio
    } catch (e) {
      setState(() {
        _chatMessages.add(ChatMessage(
          text: 'Sorry, I encountered an error. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isAIAnalyzing = false;
        _isChatLoading = false;
      });
      // Non scrollare automaticamente: lascia l'utente vedere la risposta dall'inizio
    }
  }

  // Metodo per costruire il messaggio di caricamento dell'IA
  Widget _buildAILoadingMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icona IA
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
              // Container del messaggio di caricamento
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

  // Metodo per mostrare il feedback interno alla tendina
  void _showFeedbackMessage(String message) {
    // Cancella eventuali timer precedenti
    _feedbackTimer?.cancel();
    
    if (mounted) {
      setState(() {
        _feedbackMessage = message;
        _showFeedback = true;
      });
    }
    
    // Forza l'aggiornamento del ValueListenableBuilder
    _feedbackUpdateNotifier.value++;
    
    // Aggiorna anche la tendina se è aperta
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
        
        // Aggiorna anche la tendina se è aperta
        if (_sheetStateSetter != null) {
          _sheetStateSetter!(() {});
        }
      }
    });
  }

  // Metodo per scorrere in fondo alla chat
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Metodo per gestire like dei messaggi AI
  void _toggleLike(int messageIndex) {
    setState(() {
      if (_aiMessageLikes[messageIndex] == true) {
        _aiMessageLikes[messageIndex] = false;
      } else {
        _aiMessageLikes[messageIndex] = true;
        _aiMessageDislikes[messageIndex] = false; // Rimuovi dislike se presente
      }
    });
    
    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }
  }

  // Metodo per gestire dislike dei messaggi AI
  void _toggleDislike(int messageIndex) {
    setState(() {
      if (_aiMessageDislikes[messageIndex] == true) {
        _aiMessageDislikes[messageIndex] = false;
      } else {
        _aiMessageDislikes[messageIndex] = true;
        _aiMessageLikes[messageIndex] = false; // Rimuovi like se presente
      }
    });
    
    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }
  }

  // Metodo per cancellare tutti i messaggi della chat
  Future<void> _clearAllChatMessages() async {
    setState(() {
      _chatMessages.clear();
      // Aggiungi il messaggio di benvenuto iniziale
      _chatMessages.add(ChatMessage(
        text: 'Hi! I can help you analyze this trend. Click the button below to get started, or ask me anything about it!',
        isUser: false,
        timestamp: DateTime.now(),
      ));
      _showDeleteAllAction = false;
    });
    
    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }
  }

  // Metodo per nascondere il snackbar dei crediti insufficienti
  void _hideInsufficientCreditsSnackbar() {
    if (mounted) {
      setState(() {
        _showInsufficientCreditsSnackbar = false;
      });
    }
    
    // Aggiorna anche la tendina se è aperta
    if (_sheetStateSetter != null) {
      _sheetStateSetter!(() {});
    }
  }

  // Metodo per mostrare la tendina di chat IA
  void _showAIChat(FirebaseTrendData trend) async {
    // Ricarica sempre i crediti e lo status premium quando si apre la tendina
    await _loadUserCredits();
    await _checkPremiumStatus();
    
    // Nascondi lo snackbar quando si apre la tendina
    if (_showInsufficientCreditsSnackbar) {
      setState(() {
        _showInsufficientCreditsSnackbar = false;
      });
    }
    
    // Inizializza la chat solo se è la prima volta o se si è riaperta la pagina
    if (_chatMessages.isEmpty) {
    _chatMessages.add(ChatMessage(
      text: 'Hi! I can help you analyze this trend. Click the button below to get started, or ask me anything about it!',
      isUser: false,
      timestamp: DateTime.now(),
    ));
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
          // Salva il setSheetState per aggiornamenti futuri
          _sheetStateSetter = setSheetState;
          
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            shouldCloseOnMinExtent: false,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Color(0xFF1E1E1E) 
                    : Colors.white,
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
                      
                      // Header con bottone delete all
                      if (_chatMessages.length > 2)
                        Container(
                          height: 40,
                          padding: EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: SizedBox(
                              width: 80,
                              child: AnimatedSwitcher(
                                duration: Duration(milliseconds: 300),
                                transitionBuilder: (child, anim) => SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(0.5, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: anim,
                                    curve: Curves.easeInOut,
                                  )),
                                  child: FadeTransition(
                                    opacity: anim,
                                    child: child,
                                  ),
                                ),
                                child: _showDeleteAllAction
                                    ? TextButton(
                                        key: ValueKey('delete_all_chat_text'),
                                        onPressed: () async {
                                          await _clearAllChatMessages();
                                          setSheetState(() {});
                                        },
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size(32, 32),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'Delete all',
                                          style: TextStyle(
                                            color: Colors.red[600],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      )
                                    : IconButton(
                                        key: ValueKey('delete_all_chat_icon'),
                                        onPressed: () {
                                          setState(() => _showDeleteAllAction = true);
                                          setSheetState(() {});
                                        },
                                        icon: Icon(
                                          Icons.clear_all,
                                          size: 20,
                                          color: Theme.of(context).brightness == Brightness.dark 
                                              ? Colors.white70 
                                              : Colors.black54,
                                        ),
                                        tooltip: 'Clear all messages',
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      
                      // Padding trasparente di 1 centimetro sopra il messaggio iniziale
                      SizedBox(height: 28), // 1 cm ≈ 38px
                      
                      // Chat messages
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 16),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (ScrollNotification scrollInfo) {
                              // Nascondi il snackbar dei crediti insufficienti quando si scrolla
                              if (_showInsufficientCreditsSnackbar) {
                                _hideInsufficientCreditsSnackbar();
                              }
                              return false;
                            },
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
                            child: Scrollbar(
                              controller: _chatScrollController,
                              thumbVisibility: true,
                              trackVisibility: false,
                              thickness: 8,
                              radius: Radius.circular(4),
                              interactive: true,
                                                            child: ListView.builder(
                                controller: _chatScrollController,
                                itemCount: _chatMessages.length + (_isChatLoading && !_isAIAnalyzing ? 1 : 0),
                                itemBuilder: (context, index) {
                                    if (index == _chatMessages.length && _isChatLoading && !_isAIAnalyzing) {
                                      // Mostra l'indicatore di caricamento dell'IA solo per messaggi di chat
                                      return _buildAILoadingMessage();
                                    }
                                  final message = _chatMessages[index];
                                  return _buildChatMessage(message, trend);
                                },
                              ),
                            ),
                          ),
                          ),
                        ),
                      ),
                      
                      // Loading indicator for AI response (mostra solo per messaggi di chat, non per l'analisi iniziale)
                      if (_isChatLoading && _chatMessages.where((m) => !m.isUser).isEmpty && !_isAIAnalyzing) ...[
                        const SizedBox(height: 20),
                        _buildAILoadingMessage(),
                      ],
                      
                      // Snackbar crediti insufficienti
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _showInsufficientCreditsSnackbar
                            ? Container(
                                key: const ValueKey('insufficient_credits_snackbar'),
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                        Navigator.pop(context); // Chiudi la tendina
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
                      
                      // Feedback interno alla tendina
                      ValueListenableBuilder<int>(
                        valueListenable: _feedbackUpdateNotifier,
                        builder: (context, _, __) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _showFeedback
                                ? Container(
                                    key: const ValueKey('feedback_bottom'),
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      
                      // Padding fisso in basso per evitare che i messaggi siano nascosti dall'input
                      const SizedBox(height: 76),
                    ],
                  ),
                  
                  // Badge con titolo del trend sospeso al centro in alto con effetto glass
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          // Effetto vetro sospeso
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.15) 
                              : Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(20),
                          // Bordo con effetto vetro
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.4),
                            width: 1,
                          ),
                          // Ombre per effetto sospeso
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.black.withOpacity(0.4)
                                  : Colors.black.withOpacity(0.15),
                              blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                              spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark 
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
                                Flexible(
                                  child: Text(
                                    _getCurrentTrendName(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.white 
                                          : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Padding fisso trasparente dietro il campo di input (1 cm ~ 38px)
                  Positioned(
                    bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                  
                  // Chat input sospeso in basso che segue la tastiera
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
                                  // Effetto vetro sospeso
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.15) 
                                      : Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(25),
                                  // Bordo con effetto vetro
                                  border: Border.all(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.4),
                                    width: 1,
                                  ),
                                  // Ombre per effetto sospeso
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.black.withOpacity(0.4)
                                          : Colors.black.withOpacity(0.15),
                                      blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                                      spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                                      offset: const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color: Theme.of(context).brightness == Brightness.dark 
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
                                child: TextField(
                                  controller: _messageController,
                                  enabled: _isPremium || _userCredits >= 20,
                                  maxLines: null, // Permette infinite righe
                                  textInputAction: TextInputAction.newline, // Cambia il tasto invio in "a capo"
                                  keyboardType: TextInputType.multiline, // Abilita la tastiera multilinea
                                  decoration: InputDecoration(
                                    hintText: _isPremium || _userCredits >= 20 
                                        ? 'Ask me about this trend...'
                                        : 'Need credits to continue...',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    isDense: true,
                                    hintStyle: TextStyle(
                                      color: (_isPremium || _userCredits >= 20) 
                                          ? null 
                                          : Colors.grey[500],
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: (_isPremium || _userCredits >= 20)
                                        ? (Theme.of(context).brightness == Brightness.dark 
                                            ? Colors.white 
                                            : Colors.black87)
                                        : Colors.grey[500],
                                  ),
                                  onSubmitted: (text) {
                                    if (_isPremium || _userCredits >= 20) {
                                      _sendMessageToAI(text);
                                    } else {
                                      setState(() {
                                        _showInsufficientCreditsSnackbar = true;
                                      });
                                      // Aggiorna immediatamente la tendina per mostrare lo snackbar
                                      if (_sheetStateSetter != null) {
                                        _sheetStateSetter!(() {});
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                          decoration: BoxDecoration(
                                // Effetto vetro sospeso per il bottone
                                color: (_isPremium || _userCredits >= 20) 
                                    ? null
                                    : (Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white.withOpacity(0.15) 
                                        : Colors.white.withOpacity(0.25)),
                                borderRadius: BorderRadius.circular(25),
                                // Bordo con effetto vetro
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.4),
                                  width: 1,
                                ),
                                // Ombre per effetto sospeso
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.black.withOpacity(0.4)
                                        : Colors.black.withOpacity(0.15),
                                    blurRadius: Theme.of(context).brightness == Brightness.dark ? 25 : 20,
                                    spreadRadius: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
                                    offset: const Offset(0, 10),
                                  ),
                                  BoxShadow(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.white.withOpacity(0.6),
                                    blurRadius: 2,
                                    spreadRadius: -2,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                // Gradiente per il bottone quando i crediti sono disponibili
                                gradient: (_isPremium || _userCredits >= 20)
                                    ? LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        transform: GradientRotation(135 * 3.14159 / 180),
                                        colors: [
                                          const Color(0xFF667eea), // blu violaceo al 0%
                                          const Color(0xFF764ba2), // viola al 100%
                                        ],
                                      )
                                    : null,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.send,
                              color: (_isPremium || _userCredits >= 20) 
                                  ? Colors.white 
                                  : Colors.grey[400],
                              size: 20,
                            ),
                            onPressed: (_isPremium || _userCredits >= 20) 
                                ? () => _sendMessageToAI(_messageController.text)
                                : () {
                                    setState(() {
                                      _showInsufficientCreditsSnackbar = true;
                                    });
                                    // Aggiorna immediatamente la tendina per mostrare lo snackbar
                                    if (_sheetStateSetter != null) {
                                      _sheetStateSetter!(() {});
                                    }
                                  },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
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
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _showDeleteAllAction = false;
          // Nascondi lo snackbar quando si chiude la tendina
          _showInsufficientCreditsSnackbar = false;
        });
      }
    });
  }

  // Metodo per ottenere il nome del trend corrente
  String _getCurrentTrendName() {
    final filteredTrends = _allTrends.where((trend) => trend.platform.toLowerCase() == _selectedPlatform.toLowerCase()).toList();
    if (filteredTrends.isNotEmpty && _currentTrendIndex < filteredTrends.length) {
      return filteredTrends[_currentTrendIndex].trendName;
    }
    return 'Trend Analysis';
  }

  // Metodo per costruire un messaggio della chat
  Widget _buildChatMessage(ChatMessage message, FirebaseTrendData trend) {
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
                // Messaggio utente: sempre allineato a destra con sfondo chiaro
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[100], // Sfondo chiaro
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
                // Messaggio IA con animazione di apparizione magica
                // Nascondi il messaggio finto se ci sono messaggi IA reali
                if (_chatMessages.indexOf(message) == 0 && _chatMessages.any((m) => !m.isUser && _chatMessages.indexOf(m) > 0))
                  const SizedBox.shrink()
                else
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
                    key: ValueKey('ai_message_${message.timestamp.millisecondsSinceEpoch}'),
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
                    child: _formatAnalysisText(
                      message.text,
                      isDark,
                      Theme.of(context),
                    ),
                  ),
                ),
              
              // Immagini profilo e pulsanti allineati
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (!message.isUser && !(_chatMessages.indexOf(message) == 0 && _chatMessages.any((m) => !m.isUser && _chatMessages.indexOf(m) > 0))) ...[
                      // Immagine profilo IA (icona auto_awesome)
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
                                              // Pulsanti di azione allineati con l'icona IA (solo per messaggi reali dell'IA)
                        if (_chatMessages.indexOf(message) > 0 && !(_chatMessages.indexOf(message) == 0 && _chatMessages.any((m) => !m.isUser && _chatMessages.indexOf(m) > 0))) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsante Copy
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: message.text));
                                  _showFeedbackMessage('Message copied to clipboard!');
                            },
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
                            onTap: () {
                              _toggleLike(_chatMessages.indexOf(message));
                              _showFeedbackMessage('Thank you for your feedback!');
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                gradient: _aiMessageLikes[_chatMessages.indexOf(message)] == true 
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                    )
                                  : null,
                                color: _aiMessageLikes[_chatMessages.indexOf(message)] == true ? null : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _aiMessageLikes[_chatMessages.indexOf(message)] == true 
                                  ? Icons.thumb_up 
                                  : Icons.thumb_up_outlined,
                                size: 16,
                                color: _aiMessageLikes[_chatMessages.indexOf(message)] == true 
                                  ? Colors.white 
                                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Pulsante Dislike
                          GestureDetector(
                            onTap: () {
                              _toggleDislike(_chatMessages.indexOf(message));
                              _showFeedbackMessage('Thank you for your feedback!');
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                gradient: _aiMessageDislikes[_chatMessages.indexOf(message)] == true 
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                    )
                                  : null,
                                color: _aiMessageDislikes[_chatMessages.indexOf(message)] == true ? null : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _aiMessageDislikes[_chatMessages.indexOf(message)] == true 
                                  ? Icons.thumb_down 
                                  : Icons.thumb_down_outlined,
                                size: 16,
                                color: _aiMessageDislikes[_chatMessages.indexOf(message)] == true 
                                  ? Colors.white 
                                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              ),
                            ),
                          ),
                        ],
                      ),
                        ],
                    ] else ...[
                      // Spazio vuoto per allineare i pulsanti
                      const SizedBox(width: 24),
                    ],
                    const Spacer(),
                    if (message.isUser) ...[
                      // Immagine profilo utente
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _userProfileImageUrl != null && _userProfileImageUrl!.isNotEmpty
                            ? Image.network(
                                _userProfileImageUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: Colors.grey[300],
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
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                          color: Colors.grey[300],
                          child: Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.grey[600],
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: Colors.grey[300],
                                child: Icon(
                                  Icons.person,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Bottone analyze per il primo messaggio dell'IA
        if (!message.isUser && _chatMessages.indexOf(message) == 0 && _chatMessages.length == 1) ...[
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                gradient: (_isPremium || _userCredits >= 20)
                    ? LinearGradient(
                  colors: [
                    Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                    Color(0xFF764ba2), // Colore finale: viola al 100%
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180), // Gradiente lineare a 135 gradi
                      )
                    : null,
                color: (_isPremium || _userCredits >= 20) ? null : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (_isAIAnalyzing || (!_isPremium && _userCredits < 20)) 
                      ? null 
                      : () {
                          if (_isPremium || _userCredits >= 20) {
                            _analyzeTrendWithAI(trend);
                          } else {
                            setState(() {
                              _showInsufficientCreditsSnackbar = true;
                            });
                            // Aggiorna immediatamente la tendina per mostrare lo snackbar
                            if (_sheetStateSetter != null) {
                              _sheetStateSetter!(() {});
                            }
                          }
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isAIAnalyzing 
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          _isAIAnalyzing 
                              ? 'Analyzing...' 
                              : (_isPremium || _userCredits >= 20) 
                                  ? 'Analyze this trend'
                                  : 'Need credits to analyze',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!(_isPremium || _userCredits >= 20)) ...[
                          SizedBox(width: 8),
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        
        // Domande suggerite per i messaggi dell'IA
        if (!message.isUser && message.suggestedQuestions != null && message.suggestedQuestions!.isNotEmpty) ...[
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
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                ...message.suggestedQuestions!.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final question = entry.value;
                  final hasCredits = _isPremium || _userCredits >= 20;
                  
                  return StatefulBuilder(
                    builder: (context, setState) {
                      bool isPressed = false;
                      return GestureDetector(
                        onTapDown: (_) {
                          if (hasCredits) {
                          setState(() {
                            isPressed = true;
                          });
                          }
                        },
                        onTapUp: (_) {
                          if (hasCredits) {
                          setState(() {
                            isPressed = false;
                          });
                          }
                        },
                        onTapCancel: () {
                          if (hasCredits) {
                          setState(() {
                            isPressed = false;
                          });
                          }
                        },
                        onTap: () {
                          if (!hasCredits) {
                            // Mostra snackbar crediti insufficienti
                            setState(() {
                              _showInsufficientCreditsSnackbar = true;
                            });
                            // Aggiorna immediatamente la tendina per mostrare lo snackbar
                            if (_sheetStateSetter != null) {
                              _sheetStateSetter!(() {});
                            }
                            return;
                          }
                          
                          // Inserisci la domanda nel campo di input e inviala
                          _messageController.text = question;
                          // Nascondi le domande suggerite da questo messaggio
                          final messageIndex = _chatMessages.indexOf(message);
                          if (messageIndex != -1) {
                            _chatMessages[messageIndex] = ChatMessage(
                              text: _chatMessages[messageIndex].text,
                              isUser: false,
                              timestamp: _chatMessages[messageIndex].timestamp,
                              suggestedQuestions: null,
                            );
                            // Aggiorna la tendina se è aperta
                            if (_sheetStateSetter != null) {
                              _sheetStateSetter!(() {});
                            }
                          }
                          _sendMessageToAI(question);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          transform: isPressed ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
                          decoration: BoxDecoration(
                            gradient: hasCredits 
                                ? const LinearGradient(
                              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                                  )
                                : null,
                            color: hasCredits ? null : Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: hasCredits 
                                ? [
                              BoxShadow(
                                color: const Color(0xFF667eea).withOpacity(isPressed ? 0.2 : 0.3),
                                blurRadius: isPressed ? 2 : 4,
                                offset: Offset(0, isPressed ? 1 : 2),
                              ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            question,
                            style: TextStyle(
                              fontSize: 13,
                              color: hasCredits ? Colors.white : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Metodo per ottenere la lingua dell'utente da Firebase
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

  // Funzione per correggere encoding errato (es: caratteri accentati e apostrofi)
  String fixEncoding(String input) {
    try {
      // Prima prova la decodifica UTF-8
      String result = utf8.decode(latin1.encode(input));
      
      // Correggi gli apostrofi comuni
      result = result.replaceAll('â€™', "'"); // apostrofo tipografico
      result = result.replaceAll('â€œ', '"'); // virgolette aperte
      result = result.replaceAll('â€', '"'); // virgolette chiuse
      result = result.replaceAll('â€"', '—'); // em dash
      result = result.replaceAll('â€"', '–'); // en dash
      result = result.replaceAll('â€¦', '…'); // ellipsis
      
      return result;
    } catch (e) {
      // Se la decodifica fallisce, prova a correggere solo gli apostrofi
      String result = input;
      result = result.replaceAll('â€™', "'");
      result = result.replaceAll('â€œ', '"');
      result = result.replaceAll('â€', '"');
      result = result.replaceAll('â€"', '—');
      result = result.replaceAll('â€"', '–');
      result = result.replaceAll('â€¦', '…');
      return result;
    }
  }

  // Helper per estrarre le SUGGESTED_QUESTIONS (anche localizzate) e ripulire il testo
  Map<String, Object> _extractSuggestedQuestionsFromText(String text) {
    // Supporta "SUGGESTED_QUESTIONS:", "SUGGESTED QUESTIONS:", "DOMANDE SUGGERITE:" e varianti
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
    int endIndex = headerIndex; // verrà esteso mentre leggiamo domande
    // pattern per linee domanda: numerate o bullet
    final bulletPattern = RegExp(r'^\s*(?:[0-9]+[\)\.-]|[-•*–—])\s*(.+)$');
    for (int i = headerIndex + 1; i < lines.length; i++) {
      final raw = lines[i].trimRight();
      final trimmed = raw.trim();
      // stop conditions: nuova sezione / nota / riga vuota dopo aver iniziato
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
        // accetta anche righe non marcate come domanda
        qText = trimmed;
      }
      if (qText != null && qText.isNotEmpty) {
        questions.add(fixEncoding(qText));
        endIndex = i;
        if (questions.length >= 3) {
          break; // limitiamo a 3
        }
      }
    }
    // se nessuna domanda valida trovata, ritorna testo originale
    if (questions.isEmpty) {
      return {
        'cleanText': text,
        'questions': <String>[],
      };
    }
    // ricostruisci il testo senza il blocco header..endIndex
    final cleaned = [
      ...lines.sublist(0, headerIndex),
      ...lines.sublist(endIndex + 1),
    ].join('\n').trim();
    return {
      'cleanText': cleaned,
      'questions': questions,
    };
  }

  // Widget helper per testo con gradiente
  Widget _buildGradientText(String text, TextStyle style) {
    return ShaderMask(
      shaderCallback: (Rect bounds) => const LinearGradient(
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

  // Widget per Markdown con gradiente personalizzato
  Widget _buildMarkdownWithGradient(String text, TextStyle baseStyle, TextStyle strongStyle) {
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

  // Formatta il testo dell'analisi con evidenziazioni e markdown
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
                child: _buildMarkdownWithGradient(section.content, baseStyle.copyWith(fontSize: 15), strongStyle),
              ),
            ],
          );
        }).toList(),
      );
    }
  }

  // Identifica le sezioni nel testo dell'analisi
  List<AnalysisSection> _identifySections(String analysis) {
    List<AnalysisSection> sections = [];
    final RegExp sectionRegex = RegExp(r'([\n\r]|^)([A-Z][A-Z0-9\s]+:)[\n\r]');
    final matches = sectionRegex.allMatches(analysis);
    if (matches.isEmpty) {
      sections.add(AnalysisSection('', analysis));
      return sections;
    }
    if (matches.first.start > 0) {
      sections.add(AnalysisSection('', analysis.substring(0, matches.first.start).trim()));
    }
    for (int i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final title = match.group(2)?.trim() ?? '';
      final endIndex = (i < matches.length - 1) ? matches.elementAt(i + 1).start : analysis.length;
      final content = analysis.substring(match.end, endIndex).trim();
      sections.add(AnalysisSection(title, content));
    }
    return sections;
  }

}

// Custom widget for typing animation effect
class TypingTextWidget extends StatelessWidget {
  final String text;
  final Animation<double> animation;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  const TypingTextWidget({
    Key? key,
    required this.text,
    required this.animation,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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

// Classe di supporto per le sezioni
class AnalysisSection {
  final String title;
  final String content;
  AnalysisSection(this.title, this.content);
}